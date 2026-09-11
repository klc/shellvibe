#!/usr/bin/env bash
#
# Fetches and builds the third-party terminal benchmarks into tool/bench/vendor.
#
# Both tools are vendored rather than assumed installed: the version matters.
# vtebench's payloads and termbench's test sizes have changed between releases,
# so a number produced against an unpinned checkout cannot be compared with one
# published a month earlier. run.sh records the commit each result came from.
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="$BENCH_DIR/vendor"

VTEBENCH_URL="https://github.com/alacritty/vtebench.git"
TERMBENCH_URL="https://github.com/cmuratori/termbench.git"

info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warn\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31merror\033[0m %s\n' "$*" >&2; exit 1; }

clone_or_update() {
  local url="$1" dest="$2"
  if [[ -d "$dest/.git" ]]; then
    info "updating $(basename "$dest")"
    git -C "$dest" fetch --quiet --depth 1 origin HEAD
    git -C "$dest" checkout --quiet FETCH_HEAD
  else
    info "cloning $(basename "$dest")"
    git clone --quiet --depth 1 "$url" "$dest"
  fi
}

mkdir -p "$VENDOR_DIR"

# --- termbench (single translation unit, clang++) -------------------------
clone_or_update "$TERMBENCH_URL" "$VENDOR_DIR/termbench"
if command -v clang++ >/dev/null 2>&1; then
  info "building termbench"
  # Its own build.sh writes the binary next to the source and strips it.
  (cd "$VENDOR_DIR/termbench" && ./build.sh >/dev/null)
  [[ -x "$VENDOR_DIR/termbench/termbench_release_clang" ]] \
    || fail "termbench build produced no binary"
else
  warn "clang++ not found — skipping termbench (install Xcode command line tools)"
fi

# --- vtebench (Rust) -------------------------------------------------------

# Homebrew's rustup formula is keg-only, so a shell that has never sourced
# ~/.cargo/env sees neither rustup nor cargo on PATH even on a machine where
# both are installed. Look in the standard spots before giving up.
find_cargo() {
  if command -v cargo >/dev/null 2>&1; then
    command -v cargo
    return 0
  fi
  local candidate
  for candidate in \
    "$HOME/.cargo/bin/cargo" \
    "/opt/homebrew/opt/rustup/bin/cargo" \
    "/usr/local/opt/rustup/bin/cargo"
  do
    [[ -x "$candidate" ]] && { echo "$candidate"; return 0; }
  done
  return 1
}

clone_or_update "$VTEBENCH_URL" "$VENDOR_DIR/vtebench"
if CARGO="$(find_cargo)"; then
  info "building vtebench (release) with $CARGO"
  # cargo here is a rustup shim, and it locates rustc through PATH rather than
  # relative to itself. Calling it by absolute path out of a shell that never
  # sourced rustup's env fails with "could not execute process `rustc -vV`",
  # so put its own directory on PATH for the build.
  CARGO_BIN_DIR="$(cd "$(dirname "$CARGO")" && pwd)"
  if ! (cd "$VENDOR_DIR/vtebench" \
        && PATH="$CARGO_BIN_DIR:$PATH" "$CARGO" build --release --quiet); then
    fail "vtebench build failed (cargo output above)"
  fi
  [[ -x "$VENDOR_DIR/vtebench/target/release/vtebench" ]] \
    || fail "vtebench build produced no binary"
else
  warn "cargo not found — skipping vtebench."
  warn "install a Rust toolchain, then re-run this script:"
  warn "  brew install rustup && /opt/homebrew/opt/rustup/bin/rustup default stable"
  warn "  # or: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
fi

info "vendor tree ready at $VENDOR_DIR"
