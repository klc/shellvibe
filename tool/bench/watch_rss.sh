#!/usr/bin/env bash
#
# Samples ShellVibe's resident memory and CPU while a benchmark runs.
#
# "It froze" is not a diagnosis. This separates the two candidates:
#   - RSS climbing without bound  -> output is queueing faster than it is
#     parsed, which is the unbounded-queue path (flutter_pty posts PTY output
#     over a ReceivePort that Dart cannot push back on).
#   - RSS flat while CPU pegs one core -> not a queue; the UI isolate is stuck
#     in something long, and the fix is elsewhere.
#
# Run this in a *separate* terminal (not the one under test) before starting
# the benchmark, and Ctrl-C it when the run ends or the app wedges.
set -euo pipefail

PROCESS="${1:-ShellVibe}"
INTERVAL="${2:-0.5}"
OUT="${3:-}"

pid="$(pgrep -x "$PROCESS" | head -1 || true)"
if [[ -z "$pid" ]]; then
  echo "error: no running process named '$PROCESS'" >&2
  echo "usage: watch_rss.sh [process-name] [interval-seconds] [out.tsv]" >&2
  exit 1
fi

echo "watching pid $pid ($PROCESS), every ${INTERVAL}s — Ctrl-C to stop" >&2
header=$'elapsed_s\trss_mb\tcpu_pct'
if [[ -n "$OUT" ]]; then
  printf '%s\n' "$header" > "$OUT"
fi
printf '%s\n' "$header"

start="$(date +%s)"
peak=0
while kill -0 "$pid" 2>/dev/null; do
  # rss is in KiB on macOS; %cpu is per-core, so >100 is possible.
  read -r rss cpu <<<"$(ps -o rss=,%cpu= -p "$pid" | tr -s ' ')" || break
  [[ -z "${rss:-}" ]] && break
  mb=$(( rss / 1024 ))
  (( mb > peak )) && peak=$mb
  line=$(printf '%s\t%s\t%s' "$(( $(date +%s) - start ))" "$mb" "$cpu")
  printf '%s\n' "$line"
  [[ -n "$OUT" ]] && printf '%s\n' "$line" >> "$OUT"
  sleep "$INTERVAL"
done

echo "peak RSS: ${peak} MB" >&2
