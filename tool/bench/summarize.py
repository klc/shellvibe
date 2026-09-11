#!/usr/bin/env python3
"""Turn raw benchmark output into a table you can put in a commit or a README.

Reads the result directories written by run.sh, plus (optionally) the frame
metrics ShellVibe printed while the benchmarks ran. Keeping the two side by
side is the whole point: vtebench and termbench both say in their own READMEs
that they cannot see rendering, only how fast the terminal drains the PTY. A
terminal that reads eagerly and paints lazily wins both of them while looking
like a slideshow.

usage:
    tool/bench/summarize.py results/shellvibe/20260828T101500Z [more dirs...]
    tool/bench/summarize.py results/*/2026* --perf run.log --json
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
from pathlib import Path

PERF_MARKER = "[shellvibe-perf]"
TERMBENCH_LINE = re.compile(r"^(?P<name>.+?): (?P<secs>[\d.]+)s \((?P<gbs>[\d.]+)gb/s\)$")


def median(values: list[float]) -> float:
    return statistics.median(values) if values else 0.0


def parse_vtebench_dat(path: Path) -> dict[str, list[int]]:
    """Parse the gnuplot .dat vtebench writes: a header row of benchmark names,
    then one row per sample, in milliseconds, with `_` for a short column."""
    if not path.exists():
        return {}
    lines = path.read_text().splitlines()
    if not lines:
        return {}

    names = lines[0].split()
    series: dict[str, list[int]] = {name: [] for name in names}
    for row in lines[1:]:
        for name, cell in zip(names, row.split()):
            if cell != "_":
                series[name].append(int(cell))
    return series


def parse_termbench(path: Path) -> dict[str, dict[str, float]]:
    """Parse `Name: 1.234s (0.567gb/s)` lines. The final line is a total whose
    name carries the version and size, so it is kept as-is."""
    if not path.exists():
        return {}
    results: dict[str, dict[str, float]] = {}
    for line in path.read_text().splitlines():
        match = TERMBENCH_LINE.match(line.strip())
        if match:
            results[match["name"]] = {
                "seconds": float(match["secs"]),
                "gb_per_s": float(match["gbs"]),
            }
    return results


def parse_perf(path: Path) -> list[dict]:
    """Pull the marker-prefixed JSON the perf HUD printed into `flutter run`
    stdout. Everything else in that log is ignored."""
    if not path.exists():
        return []
    snapshots = []
    for line in path.read_text(errors="replace").splitlines():
        index = line.find(PERF_MARKER)
        if index == -1:
            continue
        payload = line[index + len(PERF_MARKER) :].strip()
        try:
            snapshots.append(json.loads(payload))
        except json.JSONDecodeError:
            print(f"warn: unparseable perf line skipped: {payload[:60]}", file=sys.stderr)
    return snapshots


def load_run(directory: Path) -> dict:
    meta_path = directory / "meta.json"
    meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
    return {
        "dir": str(directory),
        "meta": meta,
        "vtebench": parse_vtebench_dat(directory / "vtebench.dat"),
        "termbench": parse_termbench(directory / "termbench.txt"),
    }


def render_table(headers: list[str], rows: list[list[str]]) -> str:
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))
    def line(cells: list[str]) -> str:
        return "| " + " | ".join(c.ljust(widths[i]) for i, c in enumerate(cells)) + " |"
    out = [line(headers), "|" + "|".join("-" * (w + 2) for w in widths) + "|"]
    out.extend(line(row) for row in rows)
    return "\n".join(out)


def report(runs: list[dict], perf: list[dict]) -> str:
    chunks: list[str] = []

    labels = [run["meta"].get("label", Path(run["dir"]).name) for run in runs]

    grids = {f"{r['meta'].get('cols')}x{r['meta'].get('rows')}" for r in runs}
    chunks.append("## Conditions\n")
    cond_rows = [
        [
            labels[i],
            f"{run['meta'].get('cols', '?')}x{run['meta'].get('rows', '?')}",
            run["meta"].get("term", "?"),
            run["meta"].get("termbench_size", "?"),
            run["meta"].get("vtebench_commit", "?"),
        ]
        for i, run in enumerate(runs)
    ]
    chunks.append(
        render_table(["run", "grid", "TERM", "tb size", "vtebench"], cond_rows)
    )
    if len(grids) > 1:
        chunks.append(
            "\n> **Not comparable.** These runs used different grid sizes. "
            "Re-run them at one COLSxROWS before reporting anything."
        )

    # --- vtebench ---------------------------------------------------------
    # vtebench silently drops a benchmark whose loader fails — several of them
    # need a controlling tty to read the grid size — so a .dat can be missing
    # entries with no error anywhere. Say so rather than tabulate a hole.
    for i, run in enumerate(runs):
        available = run["meta"].get("vtebench_available") or []
        if not available or not run["vtebench"]:
            continue
        dropped = sorted(set(available) - set(run["vtebench"]))
        if dropped:
            note = (
                "They failed to load, so this run is missing them."
            )
            # cursor_motion and light_cells resolve their tty with
            # `/dev/$(ps -o tty= -p $$)`, which yields /dev/s001 on macOS where
            # the real device is /dev/ttys001. They cannot load there, in any
            # terminal — so their absence says nothing about the terminal.
            if set(dropped) <= {"cursor_motion", "light_cells"}:
                note = (
                    "Both build their tty path as `/dev/$(ps -o tty= -p $$)`, "
                    "which is a Linux-ism — on macOS that resolves to "
                    "/dev/s001 instead of /dev/ttys001, so they fail to load "
                    "in *every* terminal. Not a property of this one, but the "
                    "comparison set is smaller than vtebench advertises."
                )
            chunks.append(
                f"\n> **{labels[i]}: vtebench dropped {len(dropped)} benchmark(s)** "
                f"({', '.join(dropped)}). {note}"
            )

    names = sorted({n for run in runs for n in run["vtebench"]})
    if names:
        chunks.append("\n## vtebench — PTY drain, median ms (lower is better)\n")
        rows = []
        for name in names:
            row = [name]
            for run in runs:
                samples = run["vtebench"].get(name, [])
                row.append(f"{median(samples):.0f} (n={len(samples)})" if samples else "—")
            rows.append(row)
        chunks.append(render_table(["benchmark", *labels], rows))

    # --- termbench --------------------------------------------------------
    tb_names = sorted({n for run in runs for n in run["termbench"]})
    if tb_names:
        chunks.append("\n## termbench — throughput, gb/s (higher is better)\n")
        rows = []
        for name in tb_names:
            row = [name]
            for run in runs:
                entry = run["termbench"].get(name)
                row.append(f"{entry['gb_per_s']:.3f}" if entry else "—")
            rows.append(row)
        chunks.append(render_table(["test", *labels], rows))

    # --- frame metrics ----------------------------------------------------
    chunks.append("\n## Frame timing (ShellVibe only)\n")
    if perf:
        rows = [
            [
                str(snap.get("label", "?"))[:32],
                str(snap.get("frames", 0)),
                f"{snap.get('build', {}).get('p50_ms', 0):.1f}",
                f"{snap.get('build', {}).get('p95_ms', 0):.1f}",
                f"{snap.get('raster', {}).get('p50_ms', 0):.1f}",
                f"{snap.get('raster', {}).get('p95_ms', 0):.1f}",
                f"{snap.get('total', {}).get('p99_ms', 0):.1f}",
                f"{snap.get('jank_ratio', 0) * 100:.1f}%",
            ]
            for snap in perf
        ]
        chunks.append(
            render_table(
                [
                    "window", "frames", "build p50", "build p95",
                    "raster p50", "raster p95", "total p99", "jank",
                ],
                rows,
            )
        )
    else:
        chunks.append(
            "_No frame metrics supplied._ The two benchmarks above measure only "
            "how fast the PTY is drained — neither can tell a smooth run from a "
            "slideshow that finished quickly. Re-run ShellVibe with "
            "`--profile --dart-define=SHELLVIBE_PERF=true`, record with the HUD, "
            "and pass the log via `--perf`."
        )

    return "\n".join(chunks) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dirs", nargs="+", type=Path, help="result directories from run.sh")
    parser.add_argument("--perf", type=Path, help="flutter run log containing perf report lines")
    parser.add_argument("--json", action="store_true", help="emit raw JSON instead of a table")
    args = parser.parse_args()

    missing = [d for d in args.dirs if not d.is_dir()]
    if missing:
        print(f"error: not a directory: {', '.join(map(str, missing))}", file=sys.stderr)
        return 2

    runs = [load_run(d) for d in args.dirs]
    perf = parse_perf(args.perf) if args.perf else []

    if args.json:
        print(json.dumps({"runs": runs, "frame_metrics": perf}, indent=2))
    else:
        print(report(runs, perf))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
