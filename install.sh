#!/usr/bin/env bash
# Install the built wshowkeys setuid-root into /usr/local/bin.
# Run this on the HOST (not inside the toolbox), with sudo:
#
#   sudo ./install.sh
#
# /usr/local is a symlink to /var/usrlocal on an rpm-ostree system, so this
# survives `rpm-ostree upgrade` and does not need a layered package. It also
# precedes /usr/bin on the default PATH, so it shadows any layered
# wshowkeys rpm without removing it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/build/wshowkeys"
DEST=/usr/local/bin/wshowkeys

if [ ! -f "$SRC" ]; then
	echo "no build found at $SRC" >&2
	echo "build it first, inside a Fedora toolbox:  ./build.sh --deps" >&2
	exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
	echo "run me with sudo: sudo $0" >&2
	exit 1
fi

# setuid root is required: wshowkeys reads /dev/input/event* directly (mode
# 0660 root:input) and drops privileges once the devices are open.
install -D -o root -g root -m 4755 "$SRC" "$DEST"

echo "installed $DEST"
ls -l "$DEST"
