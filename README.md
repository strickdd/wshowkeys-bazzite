# wshowkeys-bazzite

[wshowkeys](https://git.sr.ht/~sircmpwn/wshowkeys) — the on-screen keypress
display for Wayland — patched so it actually works under **KWin** (Plasma 6),
plus **mouse-click display**. Built and used on Bazzite (Fedora Kinoite), but
nothing here is Bazzite-specific: the fixes apply to any KDE Plasma Wayland
session.

Upstream is archived and targets wlroots. On KWin, stock wshowkeys either exits
silently the moment it starts, or shows a key or two and then dies with:

```
zwlr_layer_surface_v1#13: error 0: a buffer has been attached to a layer surface
prior to the first layer_surface.configure event
wl_display_dispatch: Protocol error
```

## What was wrong

Two independent incompatibilities, both confirmed against KWin 6.7's source.

### 1. Closed before it ever draws

wshowkeys makes its first commit with `desiredSize` 0x0 and no anchors. KWin
lays layer surfaces out from that size, and in `layershellv1integration.cpp`:

```cpp
if (geometry.isValid()) {
    window->place(geometry);
} else {
    qCWarning(KWIN_CORE) << "Closing a layer shell window due to invalid geometry";
    window->closeWindow();
}
```

An empty rect is not valid, so the surface is closed before a single frame is
drawn. wshowkeys treats `closed` as "exit", so it disappears with status 0 and
no message at all.

### 2. The protocol error

When the key list empties, upstream "hides" itself by attaching a **NULL
buffer** — that is, by *unmapping* the layer surface. wlroots tolerates the
unmap/remap cycle. KWin implements the protocol's reset rule, in
`wayland/layershell_v1.cpp`:

```cpp
// detect reset
if (!surface->isMapped() && state.firstBufferAttached) {
    state = LayerSurfaceV1State();   // configured = false
    return;
}
...
if (Q_UNLIKELY(surface->isMapped() && !state.configured)) {
    wl_resource_post_error(resource()->handle, error_invalid_surface_state,
        "a buffer has been attached to a layer surface prior "
        "to the first layer_surface.configure event");
```

So the unmap clears `configured`, and the buffer attached on the *next*
keypress arrives before the new configure. KWin kills the client. (KWin also
routes an unmapped layer surface through `handleUnmapped() → recreateWindow()`,
which sends `closed` — so the unmap is fatal twice over.)

## What this fork changes

`wshowkeys-kwin.patch` is the complete diff against upstream `main.c`
(commit `6388a49`). Five changes:

| | change | why |
|---|---|---|
| 1 | `set_size(1, 1)` before the first commit | gives KWin a valid geometry, so it does not close the surface on sight |
| 2 | never unmap — stay mapped with a 1x1 fully transparent buffer when idle | avoids KWin's state reset and the `closed` on unmap |
| 3 | track `configured`; never attach a buffer before a configure | the protocol rule the error above enforces |
| 4 | empty input region on the surface | the overlay can no longer swallow clicks — it is a recording overlay, it should never be a click target |
| 5 | `-c` mouse buttons, `-C` their colour | libinput already delivers pointer events on the context wshowkeys opens; upstream drops everything that is not a keyboard event |

Buttons render as `Left-Click`, `Middle-Click`, `Right-Click`, `Mouse-4`,
`Mouse-5`, in the special-key colour but **without** the trailing `+` that
marks a modifier — so you get `Ctrl+Left-Click`, not `Ctrl+Left-Click+`.
Scroll is deliberately not shown; wheel events fire fast enough to flood the
overlay.

## Build and install

Bazzite/Kinoite hosts have no toolchain, so build in a container and install on
the host. Two steps, two contexts:

```bash
# in a Fedora toolbox  (toolbox enter)
git clone https://github.com/strickdd/wshowkeys-bazzite
cd wshowkeys-bazzite
./build.sh --deps          # --deps installs the build packages; omit it later

# on the host
sudo ./install.sh
```

`install.sh` puts the binary **setuid root** at `/usr/local/bin/wshowkeys`.
Both parts of that matter:

- **setuid root** is required — wshowkeys reads `/dev/input/event*` (mode
  `0660 root:input`) directly, and drops privileges once the devices are open.
  Being in the `input` group is not enough; it checks for euid 0 at startup.
- **`/usr/local/bin`** is `/var/usrlocal` on an rpm-ostree system, so the
  install survives `rpm-ostree upgrade` without a layered package, and it
  precedes `/usr/bin` on PATH — it shadows the layered `wshowkeys` rpm (if you
  have one) without removing it.

Verify with `wshowkeys -h`; the `-C  mouse-click text` line means you are
running this build.

## Usage

```
wshowkeys [-c] [-b|-f|-s|-C #RRGGBB[AA]] [-F font] [-t timeout]
	[-a top|left|right|bottom] [-m margin] [-o output]
```

| flag | meaning | default |
|---|---|---|
| `-c` | also show mouse buttons | off |
| `-b` | background colour | `#000000CC` |
| `-f` | normal key text | `#FFFFFFFF` |
| `-s` | modifier text (`Ctrl+`, `Shift+`) | `#AAAAAAFF` |
| `-C` | mouse-click text | follows `-s` |
| `-F` | font — a full Pango description, so `Bold`, `Italic`, any family | `monospace 24` |
| `-t` | seconds before a keystroke ages out | `1` |
| `-a` | anchor to an edge; may be given twice | centred |
| `-m` | margin from the anchored edge, px | `32` |
| `-o` | pick an output | unimplemented upstream |

Colours are `#RRGGBB` or `#RRGGBBAA`. The alpha byte is real: `-b '#00000000'`
gives text on a fully transparent background.

`-C` resolves to whatever `-s` ends up as, regardless of flag order, so you only
pass it when you want clicks in a colour of their own.

### The command to start it

Keys and clicks, bold, bottom-anchored, in the Serious Geese terminal-theme
green with that theme's own on-accent near-black:

```bash
wshowkeys -c -a bottom -t 2 -F 'monospace Bold 32' \
  -b '#49F27CFF' -f '#070908FF' -s '#070908FF' -C '#070908FF'
```

It runs in the foreground — start it in a terminal you can leave open, or
background it, and Ctrl-C when the recording is done.

A couple of notes from using it on camera:

- **Chroma key?** `#49F27C` is a soft mint and will not key cleanly. Use
  broadcast green `-b '#00B140FF'` instead. `#00FF00` keys hardest but spills
  onto glyph edges.
- **`Left-Click` is ~10x the width of a single keystroke.** During click-heavy
  stretches the overlay grows fast; drop `-t` to `1` to age entries out
  quicker.
- The box hugs the glyphs with no padding — that is upstream behaviour, the
  surface is sized exactly to the text.

## Verifying a change without a mouse and keyboard

The awkward part of hacking on this is that you cannot run it without setuid,
and you cannot see the layer-surface lifecycle from the outside. The approach
that worked: build a variant with the privileged libinput stack stubbed out and
synthetic key/click labels injected on a timer, so the map → idle → remap cycle
runs headless against the real compositor with the lifecycle traced to stderr.

Injecting the **same** label every cycle is the important detail — the remapped
surface then asks for exactly the size the previous configure granted, which is
precisely the case where upstream attaches a buffer without waiting for the new
one. Stock wshowkeys dies on cycle 1; this build ran 45 cycles clean.

## Credits and licence

wshowkeys is by Drew DeVault and contributors —
<https://git.sr.ht/~sircmpwn/wshowkeys>. This is that program with the patch
above applied; all of it remains **GPL-3.0**, see [LICENSE](LICENSE).
