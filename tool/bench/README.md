# Terminal benchmarks

Tooling for measuring ShellVibe's terminal against other terminals, and against
its own past self.

## What each tool can and cannot see

Both third-party benchmarks measure **how fast the terminal drains the PTY** —
how long a write to the terminal blocks. Neither can see a single frame. Their
own documentation says so:

> This benchmark is not sufficient to get a general understanding of the
> performance of a terminal emulator. It lacks support for critical factors
> like frame rate or latency.
> — [vtebench](https://github.com/alacritty/vtebench)

> While it cannot time how long it takes your terminal to render (since it has
> no idea), it _can_ time how long it takes your terminal to accept the data.
> — [termbench](https://github.com/cmuratori/termbench)

This matters because the two can disagree with the user's eyes in both
directions. A terminal that reads the PTY eagerly and paints lazily posts great
throughput numbers while looking like a slideshow. One that paints every frame
honestly posts worse numbers and feels smoother.

So throughput is only half the measurement. The other half is
`lib/core/perf/frame_metrics.dart`, which records build/raster/total time per
frame from inside the app and prints a JSON summary. Report them together or
don't report them.

| Tool | Measures | Verdict unit |
| --- | --- | --- |
| vtebench | PTY drain across 12 escape-sequence workloads | ms per sample, lower better |
| termbench | PTY drain, few large synthetic payloads | gb/s, higher better |
| frame metrics (ours) | build / raster / total per frame, jank ratio | ms percentiles + jank % |

**ShellVibe pipes PTY, SSH and Mosh output through xterm3's
`PacedTerminalWriter`**, which spends at most a frame's budget parsing before
yielding. Before that, the first `run.sh` against a local shell locked the
window hard enough for macOS to show the spinning wait cursor. Expect the
throughput numbers to be *worse* than an unpaced build would post, on purpose —
that is the trade being made, and it is the reason the frame metrics have to be
published beside them.

`cmatrix`, `doom-fire` and similar are **not** benchmarks. They produce no
number of their own. They are useful only as scenarios to record frame metrics
against.

## Setup

```sh
tool/bench/setup.sh
```

Clones and builds both tools into `tool/bench/vendor/` (gitignored). termbench
needs `clang++`; vtebench needs a Rust toolchain and is skipped with a warning
if `cargo` is missing:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

## Running

1. Launch the build under test. For ShellVibe, **profile mode with the perf
   define** — a debug-mode number is 5-10x off and worth less than no number:

   ```sh
   flutter run --profile --dart-define=SHELLVIBE_PERF=true -d macos \
     | tee tool/bench/results/run.log
   ```

2. Open a local shell tab and size the window. Record the grid — a result is
   only comparable against another at the same `COLSxROWS`.

3. Tap the perf HUD (top right) to start recording.

4. In that shell:

   ```sh
   tool/bench/run.sh --label shellvibe --max-secs 1 --max-samples 2 \
     --min-bytes 262144
   ```

   Start small. ShellVibe has no way to push back on its PTY (see *Known
   ceiling* below), so an unbounded vtebench run buries the UI isolate and the
   window stops responding. Raise the bounds until it stops finishing — where
   it stops is itself a number worth writing down. Whatever bounds you settle
   on, use the same ones for every terminal you compare against; they are
   recorded in `meta.json`.

5. Tap the HUD again to stop. It prints one `[shellvibe-perf] {...}` line into
   the `flutter run` log.

6. Summarise:

   ```sh
   tool/bench/summarize.py tool/bench/results/shellvibe/<stamp> \
     --perf tool/bench/results/run.log
   ```

`run.sh` refuses to run when stdout is not a tty, because a redirected run
measures the pipe rather than the terminal. This is not pedantry: several
vtebench benchmarks (`cursor_motion`, `light_cells`) read the grid size from
their controlling tty, and vtebench drops a benchmark that fails to load
**without printing anything** — so a piped run produces a clean-looking `.dat`
that is quietly missing entries. `run.sh` records the benchmarks the checkout
offers in `meta.json`, and `summarize.py` names any that went missing.

To compare terminals, run the identical `run.sh` from a shell inside each one
(`--label ghostty`, `--label iterm2`, …) and pass every result directory to
`summarize.py` at once. It flags runs whose grid sizes differ instead of
tabulating them as if they were comparable.

## Known ceiling

Measured with a harness in `test/scratch/` (gitignored, like the other ad-hoc
harnesses there) that builds a real `TerminalView` at 204x52 and times parsing
separately from the frame it produces:

| payload | parse | frame |
| --- | --- | --- |
| 10k plain lines (1.9 MB) | 34 ms | 3 ms |
| 1k dense coloured lines (4.4 MB) | 158 ms | 39 ms |
| steady repaint, full screen of coloured cells | — | 2.1 ms median |

So **rendering is not the bottleneck** — parsing is, at roughly 28 MB/s for
densely coloured output and 58 MB/s for plain text, on the UI isolate.

That would only cost frame rate if the producer could be slowed down. It
cannot: `flutter_pty` exposes output as a `ReceivePort`, and a native thread
reads the PTY and posts to it regardless of what Dart does. Pausing the Dart
subscription does not reach that thread, so there is no backpressure path at
all. Under a benchmark that writes as fast as the PTY accepts, the isolate's
message queue fills, the frame callback queues behind it, and the paced
writer's `endOfFrame` never arrives — the app stops drawing.

This is the same trap the two tools warn about, seen from the other side: they
report a *fast* drain precisely because a native thread is draining the PTY
while the UI is stalled. Bound the payload, and publish the frame metrics.

The investigation continued in xterm3, which owns `Terminal.write`. Its
`bin/parse_bench.dart` decomposes the write path with no Flutter in the way —
parser versus buffer versus scrollback — and `WRITE_PATH_BRIEF.md` there carries
the findings, including a pooling experiment that measured 2x *worse* and was
rejected. Numbers about the write path belong there, not here.

## When a run wedges the app

"It froze" is not a diagnosis. Run the memory sampler in a *separate* terminal
before starting the benchmark:

```sh
tool/bench/watch_rss.sh ShellVibe 0.5 tool/bench/results/rss.tsv
```

Two outcomes, two different fixes:

- **RSS climbs without bound** — output is queueing faster than it is parsed.
  That is the unbounded-queue path described under *Known ceiling*, and the fix
  is upstream of the renderer: cheaper receive handling, a per-frame parse
  budget, or moving the parse off the UI isolate.
- **RSS flat while CPU pegs a core** — not a queue. The UI isolate is stuck
  inside something long, and the fix is wherever that is.

Record the largest payload that still finishes. That ceiling is a publishable
result on its own, provided the same bounds are used for every terminal
compared against.

## Rules for publishing a result

A benchmark table nobody can reproduce is marketing, and readers can tell.

- **Lock the variables.** Same font and point size, same window pixel size,
  same `COLSxROWS`, same machine, nothing else running. `meta.json` records
  the grid, `TERM`, `uname` and the exact commit of each benchmark.
- **Five runs, publish the median and the spread.** A single run of either tool
  is within noise of the next.
- **Publish the raw data and these scripts**, not just the table.
- **Pick an honest comparison set.** ShellVibe is a Flutter application; GPU
  native terminals written in Zig or Rust (Ghostty, Alacritty, kitty, WezTerm)
  will win on raw throughput, and saying otherwise costs more credibility than
  the number is worth. The comparison that reflects what ShellVibe actually
  competes with is other mobile and cross-platform SSH clients — Termius,
  Blink, Prompt.
- **Never publish a throughput number without the frame metrics beside it.**
  See the top of this file for why.

## Outputs

```
tool/bench/results/<label>/<utc-stamp>/
  meta.json       grid, TERM, uname, benchmark commits
  vtebench.dat    one column per benchmark, one row per sample, ms
  vtebench.txt    vtebench's own stdout summary
  termbench.txt   "<test>: <secs>s (<gb/s>gb/s)" lines
```
