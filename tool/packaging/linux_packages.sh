#!/usr/bin/env bash
#
# Turns the Flutter Linux bundle into native packages — .deb, .rpm and an Arch
# .pkg.tar.zst — from the single manifest in tool/packaging/linux/nfpm.yaml.
#
# The AppImage stays the "download and run anywhere" channel. These are for
# people who want ShellVibe from their package manager: listed in the app menu
# without an integration step, declared dependencies, clean removal.
#
# Requires nfpm (https://nfpm.goreleaser.com) on PATH, or NFPM pointing at it,
# and ImageMagick (or sips on macOS) to render the menu icon sizes.
#
# Usage:
#   tool/packaging/linux_packages.sh <version> [bundle-dir] [out-dir]

set -euo pipefail

version="${1:?usage: linux_packages.sh <version> [bundle-dir] [out-dir]}"
bundle="${2:-build/linux/x64/release/bundle}"
out="${3:-dist}"
nfpm="${NFPM:-nfpm}"
app_id='dev.shellvibe.app'

[[ -d "$bundle" ]] || { echo "No bundle at $bundle" >&2; exit 1; }
[[ -x "$bundle/shellvibe" ]] || { echo "No shellvibe executable in $bundle" >&2; exit 1; }
# The bridge is copied in by tool/build_bridge.sh after `flutter build`. A
# package without it installs fine and leaves AI Access reporting a missing
# binary, so refuse here instead.
[[ -x "$bundle/shellvibe-mcp" ]] || { echo "No shellvibe-mcp in $bundle; run tool/build_bridge.sh Release" >&2; exit 1; }
command -v "$nfpm" >/dev/null 2>&1 || { echo "nfpm not found" >&2; exit 1; }
mkdir -p "$out"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/opt/shellvibe" "$stage/usr/share/applications" \
         "$stage/usr/share/doc/shellvibe"
cp -r "$bundle"/. "$stage/opt/shellvibe/"
cp LICENSE "$stage/usr/share/doc/shellvibe/LICENSE"

# Named after the application id because that is what the window reports: the
# runner calls g_set_prgname(APPLICATION_ID), so the Wayland app_id and the X11
# WM_CLASS are both dev.shellvibe.app. A desktop file under any other name is
# not matched to the running window and the dock shows a second, generic entry.
cat > "$stage/usr/share/applications/$app_id.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=ShellVibe
GenericName=Terminal and SSH Client
Comment=Terminal, SSH and SFTP client
Exec=shellvibe
Icon=$app_id
Categories=Development;System;TerminalEmulator;Network;
Keywords=ssh;sftp;terminal;shell;mosh;tunnel;
Terminal=false
StartupNotify=true
StartupWMClass=$app_id
DESKTOP

# hicolor only looks in the sizes its index lists, and a 1024px source filed
# under 1024x1024 is skipped by several desktops, so render the common sizes.
icon='assets/brand/icon.png'
[[ -f "$icon" ]] || { echo "No icon at $icon" >&2; exit 1; }
for size in 48 64 128 256 512; do
  dir="$stage/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dir"
  if command -v magick >/dev/null 2>&1; then
    magick "$icon" -resize "${size}x${size}" "$dir/$app_id.png"
  elif command -v convert >/dev/null 2>&1; then
    convert "$icon" -resize "${size}x${size}" "$dir/$app_id.png"
  elif command -v sips >/dev/null 2>&1; then
    sips -z "$size" "$size" "$icon" --out "$dir/$app_id.png" >/dev/null
  else
    echo 'Need ImageMagick (magick/convert) or sips to render icons' >&2
    exit 1
  fi
done

# nfpm expands the environment in metadata fields such as version, but not in
# content source paths, so the staging directory is written into a copy.
sed "s|\${SHELLVIBE_STAGE}|$stage|g" tool/packaging/linux/nfpm.yaml > "$stage/nfpm.yaml"

for packager in deb rpm archlinux; do
  echo "==> Building $packager"
  config="$stage/nfpm.yaml"
  export SHELLVIBE_VERSION="$version"
  if [[ "$packager" == 'archlinux' ]]; then
    # nfpm drops the semver prerelease from an Arch pkgver, so 1.7.0-beta.1
    # would install as 1.7.0 and pacman would never upgrade it to the real
    # 1.7.0. pkgver may not contain '-', and pacman sorts 1.7.0beta.1 before
    # 1.7.0, so fold the prerelease in and hand nfpm the version verbatim.
    config="$stage/nfpm-arch.yaml"
    sed 's/^version_schema: semver$/version_schema: none/' "$stage/nfpm.yaml" > "$config"
    export SHELLVIBE_VERSION="${version//-/}"
  fi
  "$nfpm" package --config "$config" --packager "$packager" --target "$out/"
done

echo "==> Done:"
ls -lh "$out"/*.deb "$out"/*.rpm "$out"/*.pkg.tar.zst
