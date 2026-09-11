#!/usr/bin/env bash
#
# Turns the Flutter Linux bundle into an AppImage: one executable file that runs
# on any reasonably current distribution without a package manager, which is why
# it is the first Linux channel rather than .deb and .rpm.
#
# The bundle is not relocatable on its own — the runner looks for `data/` and
# `lib/` beside itself — so everything moves into the AppDir together and AppRun
# enters through the real executable.
#
# Usage:
#   tool/packaging/linux_appimage.sh <version> [bundle-dir] [out-dir]

set -euo pipefail

version="${1:?usage: linux_appimage.sh <version> [bundle-dir] [out-dir]}"
bundle="${2:-build/linux/x64/release/bundle}"
out="${3:-dist}"

[[ -d "$bundle" ]] || { echo "No bundle at $bundle" >&2; exit 1; }
mkdir -p "$out"

appdir="$(mktemp -d)/ShellVibe.AppDir"
trap 'rm -rf "$(dirname "$appdir")"' EXIT
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" \
         "$appdir/usr/share/icons/hicolor/1024x1024/apps"

cp -r "$bundle"/. "$appdir/usr/bin/"

# The desktop entry is read by the AppImage runtime and by the desktop
# environment after integration; StartupWMClass has to match what the window
# actually reports or the taskbar shows a second, iconless entry.
cat > "$appdir/usr/share/applications/shellvibe.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=ShellVibe
Comment=Terminal, SSH and SFTP client
Exec=shellvibe
Icon=shellvibe
Categories=Development;System;TerminalEmulator;
Terminal=false
StartupWMClass=shellvibe
DESKTOP
cp "$appdir/usr/share/applications/shellvibe.desktop" "$appdir/shellvibe.desktop"

# 1024x1024, so it lands in the hicolor directory of that size rather than
# being filed under a size it is not.
icon='assets/brand/icon.png'
[[ -f "$icon" ]] || { echo "No icon at $icon" >&2; exit 1; }
cp "$icon" "$appdir/usr/share/icons/hicolor/1024x1024/apps/shellvibe.png"
cp "$icon" "$appdir/shellvibe.png"

cat > "$appdir/AppRun" <<'APPRUN'
#!/bin/sh
# $APPDIR is set by the AppImage runtime; resolving it here as well keeps the
# AppDir runnable directly, which is how you debug a packaging problem without
# rebuilding the image.
HERE="$(dirname "$(readlink -f "$0")")"
export APPDIR="${APPDIR:-$HERE}"
exec "$APPDIR/usr/bin/shellvibe" "$@"
APPRUN
chmod +x "$appdir/AppRun"

if ! command -v appimagetool >/dev/null 2>&1; then
  echo '==> Fetching appimagetool'
  tool_path="$(dirname "$appdir")/appimagetool"
  curl -fsSL -o "$tool_path" \
    'https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage'
  chmod +x "$tool_path"
  APPIMAGETOOL="$tool_path"
else
  APPIMAGETOOL="$(command -v appimagetool)"
fi

target="$out/ShellVibe-${version}-linux-x86_64.AppImage"
rm -f "$target"
# No FUSE on a CI runner, so the tool has to unpack itself rather than mount.
ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run "$appdir" "$target"
chmod +x "$target"

echo "==> Done:"
ls -lh "$target"
