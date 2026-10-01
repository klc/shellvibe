#!/usr/bin/env bash
#
# Turns a built ShellVibe.app into the artifacts a macOS user can actually run:
# a signed, notarized, stapled DMG and a matching ZIP.
#
# The script degrades on purpose. With no signing identity in the environment it
# still produces a DMG, clearly marked unsigned, so the packaging path is
# exercised on every release build rather than only on the first one that has
# certificates. That is the failure this ordering is written against: a signing
# pipeline first run on release day fails on release day.
#
# Environment:
#   APPLE_SIGNING_IDENTITY   Developer ID Application: ... (signs when set)
#   APPLE_TEAM_ID            Team the notarization submission belongs to
#   APPLE_API_KEY_ID         App Store Connect API key id      \
#   APPLE_API_ISSUER_ID      App Store Connect issuer id        } notarizes
#   APPLE_API_KEY_PATH       Path to the .p8 private key file  /  when all set
#   APPLE_NOTARY_PROFILE     notarytool keychain profile; replaces the three
#                            API key variables for local builds
#
# Usage:
#   tool/packaging/macos_package.sh <version> [app-path] [out-dir]

set -euo pipefail

version="${1:?usage: macos_package.sh <version> [app-path] [out-dir]}"
app="${2:-build/macos/Build/Products/Release/ShellVibe.app}"
out="${3:-dist}"

[[ -d "$app" ]] || { echo "No app bundle at $app" >&2; exit 1; }
mkdir -p "$out"

identity="${APPLE_SIGNING_IDENTITY:-}"
suffix=''
if [[ -z "$identity" ]]; then
  suffix='-unsigned'
  echo '==> No APPLE_SIGNING_IDENTITY; packaging unsigned.'

  # Re-seal ad hoc. `flutter build` signs the bundle ad hoc, and build_bridge.sh
  # then copies shellvibe-mcp in beside the executable, which invalidates that
  # seal: the bundle ships reporting "a sealed resource is missing or invalid",
  # which several checks treat more harshly than an honestly unsigned binary.
  # Ad-hoc signing buys no trust, but it does make the bundle internally
  # consistent, and it is the same inside-out order the real signing path uses.
  codesign --force --sign - "$app/Contents/MacOS/shellvibe-mcp" 2>/dev/null || true
  codesign --force --sign - \
    --entitlements macos/Runner/Release.entitlements "$app"
  codesign --verify --strict "$app"
else
  echo "==> Signing with: $identity"

  # Inside out. Codesign seals a bundle against its contents, so signing the
  # outer .app first and a nested framework second invalidates the outer
  # signature — and the failure surfaces as a launch refusal rather than a
  # signing error. The MCP bridge is signed here too: it was copied in after
  # `flutter build`, and an unsigned executable inside a signed bundle is
  # blocked by Gatekeeper with no visible error, which reads to the user as
  # the AI Access feature being broken.
  #
  # The bridge is a `dart compile exe` binary, whose runtime maps its AOT
  # snapshot into executable memory that carries no code signature. Under the
  # hardened runtime the kernel kills it on start (SIGKILL, nothing logged to
  # the caller) unless it holds allow-unsigned-executable-memory. allow-jit is
  # not enough. Only the bridge gets it; the app itself runs without.
  while IFS= read -r -d '' nested; do
    extra=()
    if [[ "$(basename "$nested")" == 'shellvibe-mcp' ]]; then
      extra=(--entitlements tool/packaging/shellvibe-mcp.entitlements)
    fi
    codesign --force --timestamp --options runtime \
      ${extra[@]+"${extra[@]}"} --sign "$identity" "$nested"
  done < <(
    find "$app/Contents" \
      \( -name '*.dylib' -o -name '*.framework' -o -perm -u+x -type f \) \
      -print0 | sort -rz
  )

  codesign --force --timestamp --options runtime \
    --entitlements macos/Runner/Release.entitlements \
    --sign "$identity" "$app"

  codesign --verify --deep --strict --verbose=2 "$app"
fi

notarize=''
notary_auth=()
if [[ -n "$identity" ]]; then
  if [[ -n "${APPLE_NOTARY_PROFILE:-}" ]]; then
    notarize=1
    notary_auth=(--keychain-profile "$APPLE_NOTARY_PROFILE")
  elif [[ -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" && -n "${APPLE_API_KEY_PATH:-}" ]]; then
    notarize=1
    notary_auth=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID")
  fi
fi

# Submits a file, waits for Apple, and fails loudly on anything but Accepted.
# notarytool's own exit status does not say whether the submission was
# accepted, and the reason a submission is rejected lives only in its log, so
# that log is printed here rather than left for someone to fetch by hand.
notarize_file() {
  local file="$1" result id status
  echo "==> Notarizing $(basename "$file") (this waits for Apple)"
  result="$(xcrun notarytool submit "$file" "${notary_auth[@]}" --wait --output-format json)"
  id="$(plutil -extract id raw -o - - <<<"$result")"
  status="$(plutil -extract status raw -o - - <<<"$result")"
  echo "    submission $id: $status"
  if [[ "$status" != 'Accepted' ]]; then
    xcrun notarytool log "$id" "${notary_auth[@]}" >&2 || true
    return 1
  fi
}

if [[ -n "$notarize" ]]; then
  # The app is notarized and stapled on its own before anything is built from
  # it. Notarizing only the DMG registers the app with Apple too, but leaves no
  # ticket inside the bundle, so the ZIP — and any copy dragged out of the DMG
  # — needs a network round trip on first launch, and a user who is offline
  # gets the same refusal an unsigned app does.
  app_zip="$(mktemp -d)/ShellVibe.zip"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$app_zip"
  notarize_file "$app_zip"
  rm -rf "$(dirname "$app_zip")"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute -vv "$app"
elif [[ -n "$identity" ]]; then
  echo '==> Notarization credentials incomplete; skipping.'
fi

dmg="$out/ShellVibe-${version}-macos${suffix}.dmg"
zip="$out/ShellVibe-${version}-macos${suffix}.zip"

echo "==> Building $dmg"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
# The drop target every Mac user expects; without it the DMG is a folder with
# an app in it and people run the app from the mounted image, which breaks on
# the next eject.
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname "ShellVibe $version" -srcfolder "$staging" \
  -ov -format UDZO "$dmg" >/dev/null

if [[ -n "$identity" ]]; then
  codesign --force --timestamp --sign "$identity" "$dmg"
fi

if [[ -n "$notarize" ]]; then
  notarize_file "$dmg"
  # Stapling is what lets a first launch succeed offline. Without it Gatekeeper
  # has to reach Apple to learn the image is notarized, and a user on a plane
  # sees the same dialog an unsigned app gets.
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"

  echo '==> Gatekeeper assessment'
  spctl --assess --type open --context context:primary-signature -vv "$dmg"
fi

# Built from the stapled app, so it carries its own ticket.
echo "==> Building $zip"
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

echo "==> Done:"
ls -lh "$dmg" "$zip"
