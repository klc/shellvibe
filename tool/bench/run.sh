#!/usr/bin/env bash
#
# Runs the vendored benchmarks *inside the terminal under test* and records the
# conditions they ran under.
#
# Deliberately terminal-agnostic: the same script has to run unchanged in
# ShellVibe, iTerm2, Ghostty and Alacritty, or the comparison is worthless.
# It writes to the tty it is invoked from, so run it from a shell inside
# whichever terminal you are measuring.
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="$BENCH_DIR/vendor"
RESULTS_ROOT="$BENCH_DIR/results"

LABEL=""
SIZE="normal"
ONLY=""
# vtebench defaults to 10 seconds per benchmark with no sample cap, which lets
# it push far more data than a terminal on the slower end can absorb. ShellVibe
# has no backpressure path to the PTY (flutter_pty delivers output over a
# ReceivePort, which a Dart-side pause does not reach), so an unbounded run
# buries the UI isolate. Bounding the payload keeps a run finishable; the
# bounds are recorded in meta.json so results are only compared like for like.
MAX_SECS="3"
MAX_SAMPLES="5"
MIN_BYTES=""

usage() {
  cat <<'USAGE'
usage: run.sh --label <name> [--size small|normal|large] [--only vtebench|termbench]

  --label   Terminal being measured, e.g. shellvibe-profile, ghostty, iterm2.
            Becomes the result directory name, so keep it stable across runs.
  --size    termbench payload size. Default "normal"; use "small" on a
            terminal slow enough that a normal run would take minutes.
  --only    Run just one of the two benchmarks.
  --max-secs      Seconds per vtebench benchmark. Default 3 (vtebench's own
                  default is 10, which can outrun a terminal that has no way
                  to push back on its PTY).
  --max-samples   Sample cap per vtebench benchmark. Default 5.
  --min-bytes     Bytes per vtebench sample. Default is vtebench's own (1 MiB).
                  Lower it if a run still will not finish.

Run five times per terminal and report the median. A single run of either tool
is within noise of the next one.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="${2:-}"; shift 2 ;;
    --size) SIZE="${2:-}"; shift 2 ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    --max-secs) MAX_SECS="${2:-}"; shift 2 ;;
    --max-samples) MAX_SAMPLES="${2:-}"; shift 2 ;;
    --min-bytes) MIN_BYTES="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$LABEL" ]] || { echo "error: --label is required" >&2; usage >&2; exit 2; }

# A redirected run measures the pipe, not the terminal. Refuse rather than
# quietly produce a number that looks real.
[[ -t 1 ]] || { echo "error: stdout is not a tty — run this inside the terminal you are measuring" >&2; exit 2; }

COLS="$(tput cols)"
ROWS="$(tput lines)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$RESULTS_ROOT/$LABEL/$STAMP"
mkdir -p "$OUT_DIR"

git_head() { git -C "$1" rev-parse --short HEAD 2>/dev/null || echo unknown; }

# Several vtebench benchmarks read the grid size from their controlling tty and
# fail to load without one. vtebench drops a benchmark that fails to load
# without printing anything, so a result set can quietly be missing entries.
# Record what the checkout offers, and let summarize.py compare.
vtebench_available_json() {
  local dir="$VENDOR_DIR/vtebench/benchmarks" entry names=()
  [[ -d "$dir" ]] || { echo "[]"; return; }
  for entry in "$dir"/*/; do
    [[ -d "$entry" ]] && names+=("\"$(basename "$entry")\"")
  done
  local IFS=,
  echo "[${names[*]}]"
}

# The grid size decides how much work each escape sequence causes, so a result
# is only comparable against another result at the same COLSxROWS.
cat > "$OUT_DIR/meta.json" <<META
{
  "label": "$LABEL",
  "timestamp_utc": "$STAMP",
  "cols": $COLS,
  "rows": $ROWS,
  "term": "${TERM:-}",
  "term_program": "${TERM_PROGRAM:-}",
  "termbench_size": "$SIZE",
  "vtebench_max_secs": "$MAX_SECS",
  "vtebench_max_samples": "$MAX_SAMPLES",
  "vtebench_min_bytes": "${MIN_BYTES:-default}",
  "uname": "$(uname -srm)",
  "vtebench_commit": "$(git_head "$VENDOR_DIR/vtebench")",
  "termbench_commit": "$(git_head "$VENDOR_DIR/termbench")",
  "vtebench_available": $(vtebench_available_json)
}
META

echo "==> label=$LABEL grid=${COLS}x${ROWS} -> $OUT_DIR"
echo "==> If this is ShellVibe with the perf HUD, start recording now, and stop"
echo "    it when the run finishes. Neither tool below can see your frame rate."
echo

run_vtebench() {
  local bin="$VENDOR_DIR/vtebench/target/release/vtebench"
  if [[ ! -x "$bin" ]]; then
    echo "-- vtebench not built, skipping (run setup.sh)" >&2
    return 0
  fi
  echo "==> vtebench"
  # --benchmarks must point at the checkout's own payload directory; the
  # default is relative to the cwd.
  local args=(
    --benchmarks "$VENDOR_DIR/vtebench/benchmarks"
    --dat "$OUT_DIR/vtebench.dat"
    --max-secs "$MAX_SECS"
    --max-samples "$MAX_SAMPLES"
  )
  [[ -n "$MIN_BYTES" ]] && args+=(--min-bytes "$MIN_BYTES")
  "$bin" "${args[@]}" | tee "$OUT_DIR/vtebench.txt"
}

run_termbench() {
  local bin="$VENDOR_DIR/termbench/termbench_release_clang"
  if [[ ! -x "$bin" ]]; then
    echo "-- termbench not built, skipping (run setup.sh)" >&2
    return 0
  fi
  echo "==> termbench ($SIZE)"
  # macOS ships bash 3.2, where an empty array expands as unset and trips
  # `set -u`. The default size passes no argument at all, so guard it.
  local args=()
  [[ "$SIZE" != "normal" ]] && args+=("$SIZE")
  "$bin" ${args[@]+"${args[@]}"} | tee "$OUT_DIR/termbench.txt"
}

case "$ONLY" in
  vtebench) run_vtebench ;;
  termbench) run_termbench ;;
  "") run_vtebench; echo; run_termbench ;;
  *) echo "unknown --only value: $ONLY" >&2; exit 2 ;;
esac

# vtebench resets the screen between samples; leave the terminal usable.
tput cnorm 2>/dev/null || true
echo
echo "==> results in $OUT_DIR"
echo "==> summarise with: tool/bench/summarize.py $OUT_DIR"
