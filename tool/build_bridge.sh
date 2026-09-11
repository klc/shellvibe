#!/usr/bin/env bash
#
# Builds the `shellvibe-mcp` stdio bridge and drops it next to the app's own
# executable, which is the only place the AI Access settings screen looks for
# it (see `_detectBridgeCommand` in mcp_access_settings_section.dart).
#
# The bridge is a separate, Flutter-free Dart package, so `flutter build` knows
# nothing about it. Without this step the settings screen correctly reports
# "shellvibe-mcp not found" and the generated client config carries a
# placeholder instead of a usable command.
#
# Usage:
#   tool/build_bridge.sh                 # build for the host, install into the
#                                        # Debug app bundle (macOS) or the
#                                        # equivalent bundle dir on Linux/Windows
#   tool/build_bridge.sh Release         # same, against the Release build
#   tool/build_bridge.sh --dest <dir>    # build and copy into an explicit dir
#
# On macOS the copied binary is ad-hoc signed so a locally built .app can
# launch it. A distributed build must instead be signed and notarized together
# with the .app — an unsigned bridge is blocked by Gatekeeper with no visible
# error, which looks to the user exactly like the feature being broken.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE_SRC="$REPO_ROOT/tool/shellvibe_mcp_bridge/bin/shellvibe_mcp.dart"

CONFIG="Debug"
DEST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      DEST="$2"
      shift 2
      ;;
    Debug|Release|Profile)
      CONFIG="$1"
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

case "$(uname -s)" in
  Darwin)  PLATFORM="macos" ; BIN_NAME="shellvibe-mcp" ;;
  Linux)   PLATFORM="linux" ; BIN_NAME="shellvibe-mcp" ;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ; BIN_NAME="shellvibe-mcp.exe" ;;
  *) echo "unsupported host: $(uname -s)" >&2 ; exit 1 ;;
esac

if [[ -z "$DEST" ]]; then
  case "$PLATFORM" in
    macos)
      APP="$(find "$REPO_ROOT/build/macos/Build/Products/$CONFIG" \
              -maxdepth 1 -name '*.app' -type d 2>/dev/null | head -1)"
      if [[ -z "$APP" ]]; then
        echo "No $CONFIG .app found. Run 'flutter build macos' or 'flutter run' first," >&2
        echo "or pass --dest <dir> to install the bridge somewhere explicit." >&2
        exit 1
      fi
      DEST="$APP/Contents/MacOS"
      ;;
    linux)
      DEST="$REPO_ROOT/build/linux/x64/${CONFIG,,}/bundle"
      ;;
    windows)
      DEST="$REPO_ROOT/build/windows/x64/runner/$CONFIG"
      ;;
  esac
fi

if [[ ! -d "$DEST" ]]; then
  echo "Destination does not exist: $DEST" >&2
  echo "Build the app first, or pass --dest <dir>." >&2
  exit 1
fi

OUT="$DEST/$BIN_NAME"

echo "Building bridge  -> $OUT"
dart compile exe "$BRIDGE_SRC" -o "$OUT"

if [[ "$PLATFORM" == "macos" ]]; then
  # Ad-hoc signature: enough for a locally built bundle to launch it. Release
  # builds must be signed with the app's real identity and notarized.
  codesign --force --sign - "$OUT"
  echo "Ad-hoc signed (local use only — release builds need the real identity)"
fi

echo "Done. The AI Access settings screen will now find it at:"
echo "  $OUT"
