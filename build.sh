#!/usr/bin/env bash
# Build wshowkeys. Run this INSIDE a Fedora toolbox/distrobox container --
# Bazzite/Kinoite hosts have no compiler or -devel packages.
#
#   toolbox enter
#   ./build.sh            # build only
#   ./build.sh --deps     # install build dependencies first (needs sudo in the container)
#
# Then, on the HOST:  sudo ./install.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ "${1:-}" = "--deps" ]; then
	sudo dnf install -y --setopt=install_weak_deps=False \
		meson ninja-build gcc pkgconf-pkg-config \
		wayland-devel wayland-protocols-devel libxkbcommon-devel \
		cairo-devel pango-devel libinput-devel systemd-devel
fi

for tool in meson ninja pkg-config; do
	command -v "$tool" >/dev/null || {
		echo "missing $tool -- run './build.sh --deps' inside the toolbox" >&2
		exit 1
	}
done

[ -d build ] || meson setup build --prefix=/usr/local
ninja -C build

echo
echo "built: $(pwd)/build/wshowkeys"
echo "now run on the HOST:  sudo $(pwd)/install.sh"
