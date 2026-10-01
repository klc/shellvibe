#!/usr/bin/env bash
#
# Installs a built ShellVibe package on the current (clean) system through its
# native package manager, proves the app starts, then removes it. Run as root
# inside a distribution image; the linux-packages job in release.yml runs it on
# each supported one.
#
# "Starts" means launched under Xvfb and still running after 15 seconds. A
# library check alone is not enough: the engine dlopens EGL and GLES at start,
# so a package missing them passes ldd and aborts on first launch.
#
# Usage:
#   tool/packaging/linux/test_package.sh <dist-dir>

set -euo pipefail

# Absolute, because apt reads a relative `dist/x.deb` as package "dist" at
# release "x.deb" and only treats the argument as a file when it starts with
# / or ./.
dist="$(cd "${1:?usage: test_package.sh <dist-dir>}" && pwd)"
# The X server, xauth and a session bus are test scaffolding, not something
# the package may depend on, so they are installed alongside it here.
if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y desktop-file-utils xvfb xauth dbus-x11 "$dist"/*.deb
  desktop-file-validate /usr/share/applications/dev.shellvibe.app.desktop
  remove=(apt-get remove -y shellvibe)
elif command -v dnf >/dev/null; then
  dnf install -y xorg-x11-server-Xvfb xorg-x11-xauth dbus-x11 "$dist"/*.rpm
  remove=(dnf remove -y shellvibe)
else
  pacman -Syu --noconfirm
  pacman -S --noconfirm xorg-server-xvfb xorg-xauth
  pacman -U --noconfirm "$dist"/*.pkg.tar.zst
  remove=(pacman -R --noconfirm shellvibe)
fi

echo '==> Libraries'
# The plugins find libflutter_linux_gtk.so through the executable's RUNPATH at
# run time, so they are checked with the same search path. libdartjni wants a
# JVM that only exists on Android, and is never loaded on Linux.
missing="$(
  {
    ldd /opt/shellvibe/shellvibe
    for lib in /opt/shellvibe/lib/*.so; do
      [[ "$(basename "$lib")" == 'libdartjni.so' ]] && continue
      LD_LIBRARY_PATH=/opt/shellvibe/lib ldd "$lib"
    done
  } 2>&1 | grep 'not found' || true
)"
if [[ -n "$missing" ]]; then
  echo "Unresolved libraries:" >&2
  echo "$missing" >&2
  exit 1
fi

echo '==> MCP bridge'
# Exits cleanly when stdin closes, which also proves it starts.
shellvibe-mcp < /dev/null

echo '==> Launch'
export HOME="$(mktemp -d)"
status=0
xvfb-run -a dbus-launch --exit-with-session timeout 15 shellvibe \
  > "$HOME/app.log" 2>&1 || status=$?
# timeout's 124 is the pass: the app was still running when it was stopped.
if [[ "$status" -ne 124 ]]; then
  echo "ShellVibe exited with status $status before the timeout:" >&2
  tail -20 "$HOME/app.log" >&2
  exit 1
fi

echo '==> Remove'
"${remove[@]}"
if [[ -e /opt/shellvibe || -e /usr/bin/shellvibe ]]; then
  echo 'Removal left files behind.' >&2
  exit 1
fi
echo '==> OK'
