# The bench cell

The reproducible measurement of [`docs/specs/M50.md`](../../docs/specs/M50.md). It replaces the two
caveats [`docs/comparison.md`](../../docs/comparison.md) § Conditions records — a shared host and an
unverifiable tree label — with two mechanisms:

* **the tree label is cured by a digest.** The cell records the SHA-256 and the byte count of every
  binary it timed, `mc`'s own included, plus what `mc --version` and `mc --host` print. A digest
  cannot go stale the way `bench/results.json`'s `"tree at commit e5a1643"` did.
* **the shared host is cured by the comparison rule, not by hardware.** `clang -O2` of
  [`../c/bench.c`](../c/bench.c) is built and timed **in the same run** as every row, and the verdict
  is `median(row) / median(that reference)`. Absolute seconds are recorded, reported, and never
  gated: the same unchanged `clang -O2` binary of this program has timed 0.420 s, 0.49 s and
  0.52–0.56 s in three sessions on one Mac, a 33% span with nothing changed.

This is **step A**: the runner, the schema and the phase argument. The workflow that runs it on three
cells (step B) and the committed history with its gate (step C) are not here yet.

## Running it

```sh
make bench-cell                                  # every row whose toolchain is installed
make bench-cell CELLFLAGS='--rows mc-plain,mc-opt,c-O2 --phases all'
python3 bench/cell/cell.py --help
```

`build/mc1` is measured by default (`make bench-cell` builds it first); `--mc PATH` or `MC=PATH`
names another one, which is how a release tarball or a compiler built from another commit is
measured. Results land in `build/bench-cell/<date>-<id>/` — `build/` is not tracked, so a local run
stages nothing. `--out bench/results/<date>-<run-id>` is the directory step C commits.

Python 3 standard library only, no third-party module anywhere. Not part of `make check`, and it
never will be: the numbers depend on the host's CPU, its load and the installed toolchain versions,
which `make check` must not (`bench/README.md`'s first paragraph).

## The protocol

| | |
|---|---|
| rows | 11 — `mc-plain`, `mc-opt`, `c-O2` (the reference), `c-O0`, `go`, `zig-fast`, `zig-debug`, `rust-O3`, `rust-O0`, `cs-aot`, `cs-jit` |
| phases | `all`, `mix`, `primes`, `fib` — the three phases M49's acceptance is stated in, plus the whole workload |
| repetitions | 7, the rows **interleaved** inside each one in a fixed order, one process at a time; repetition 1 recorded and excluded from every statistic |
| pinning | `taskset -c 0` on Linux, nothing on macOS; no memory cap (the workload is single-threaded and peaks near 51 MB, so a cap changes no number and a CPU *quota* is a share of a shared machine, not a speed) |
| verdict | per row and phase, `median(row) / median(c-O2)` over the kept repetitions of the same run |
| correctness | every repetition of every row must print the workload's recorded answer for its phase — a wrong answer is a failed row, not a timing |
| skips | a toolchain that is not installed, or a row whose build fails, is SKIPPED with the reason printed and recorded. Never faked, never silently dropped |

One row per `build.sh` invocation, the shape [`../soak/build.sh`](../soak/build.sh) already has;
`MC`, `CC` and `LIBC` override what it uses. Its last line of stdout is `run: <command>`, so
`cell.py` never needs to know that the C# JIT row is launched through the `dotnet` host while every
other row is a plain binary.

Every threshold and pin lives in [`versions.env`](versions.env) — one file, read by the workflow
(`cat bench/cell/versions.env >> "$GITHUB_ENV"`), by the local road (`. bench/cell/versions.env`)
and by `cell.py`. Two pins in this repository have already resolved to two different compilers in
two recorded runs (`go 1.26` → go1.26.4 and go1.26.7; `10.0.x` → SDK 10.0.301 and 10.0.400), which is
why they are exact and why `facts.json` records what every tool actually printed.

## The phase argument

All six benchmark sources take one optional argument and dispatch on its first byte: `mix`, `primes`,
`fib`, anything else (or no argument at all) runs all three phases in the recorded order. No
argument is byte-for-byte today's output — `8128903901837660708 / 3001134 / 39088169`, md5
`c369e8b4679ca95f45fa46bbff03b7b7` on all six — so `bench/run.sh`'s contract and every number
already recorded in [`../RESULTS.md`](../RESULTS.md) stay comparable. It exists because M49's
acceptance is stated per phase (`mix` ≤ 0.28 s, `primes` ≤ 0.21 s, `fib` ≤ 0.18 s) and nothing in the
repository could re-measure those: M49 got them by trimming `main` in a scratchpad.

## What the runs on this host measured

Six full runs, three consecutive PAIRS, on this project's own Mac (Apple M4, Darwin 25.6.0,
macOS 26.6.2) with nothing pinned — macOS has no `taskset`, so this is the noisiest of the three
cells step B will add. 11 rows × 4 phases × 7 repetitions each.

**Two consecutive runs agree, per row, within** (worst row of that phase; how many rows exceeded 5%):

| phase | pair 1 | pair 2 | pair 3 | over 5% |
|---|---|---|---|---|
| `all` | 2.44% | 4.54% | 4.76% | **0, 0, 0** |
| `mix` | 4.18% | 4.97% | 6.49% | 0, 0, 1 |
| `primes` | 3.56% | 5.85% | 8.36% | 0, 1, **4** |
| `fib` | 3.25% | 6.84% | 4.98% | 0, 1, 0 |

The median row moves 1.10–3.43% everywhere. The **absolute** medians of the same runs moved by up to
15.77%, and in pair 2 the reference row alone moved −9.34% between two runs started back to back —
the ratios held while the machine underneath did not, which is the whole case for the comparison
rule and for § 4.4's health indicator.

`TOLERANCE = 0.05` therefore **holds on the `all` phase** (0 violations in three pairs, ~5% of margin
on the worst row) and **does not hold on the three short phases** (7 of 99 rows over it, worst
8.36%). The reason is § 1.3 item 3's finding one level down: under 0.25 s both medians in the
quotient are dominated by scheduler noise and their errors add instead of cancelling. Recommendation
for step C, measured rather than guessed: gate the band on `all`, report the per-phase ratios beside
it (they would need about 0.10 here), and re-measure on the two pinned Linux cells before widening
anything for them.

**Repetition 1 is dropped, and it earns it on the phase that runs first.** Over the four runs that
recorded the breakdown, `all`'s repetition 1 is 1.28x, 1.33x, 1.56x and 1.34x the best of the kept
six, worst row 1.79x — the 1.25–1.62x band `bench/results.json`'s own three-run rows show. The three
later phases of the same repetition find the pages warm and sit at 1.01–1.12x median, so the cell
reports the gap per phase instead of one diluted number.

## The teeth

`mc --opt=0` against `mc --opt=1` is a deliberately regressed compiler that is already on `main`, so
the gate costs nothing to keep alive: if the register allocator, the peephole or the hoisting stops
working, the ratio falls towards 1.0 and the run fails in the same run, with no baseline to consult.

The floor is applied to **one phase**, `REGRESS_PHASE` in `versions.env`, which is a deviation from
the spec's § 4.3 and is decided by the numbers. The tooth per phase, the same six runs:

| phase | six runs | floor 1.5 |
|---|---|---|
| `all` | 1.554 … 1.619 | holds by 4–8% |
| `mix` | 2.243 … 2.379 | holds by 50% |
| `primes` | 1.049 … 1.093 | would fail |
| `fib` | 0.996 … 1.037 | would fail |

M49 moves `mix` by 2.3x, `primes` by 5% and `fib` by nothing (its cost is its call count), so `all`
is a weighted average that lands just above the floor — and on the quieter host M49 step C measured,
`all` was 0.793 / 0.548 = **1.45**, which a 1.5 floor would have failed. `mix` carries the same floor
with half again of margin and is the phase the optimizer is actually about.

## The files this writes

`results.json` — one object per cell run: the cell's identity (id, CPU model, nproc, memory, kernel,
pinned cpus, date, run id), the `mc` block (path, version, host, SHA-256, bytes), every toolchain
string as its tool printed it, the pins, the schedule, then one entry per (row, phase) with the build
and run commands verbatim, the compile seconds, the binary's bytes / `__text` / SHA-256, **all seven
repetitions**, best / median / max of the kept ones, max RSS, `stdout_ok` and `ratio_to_reference`.
Then the verdict: status, the tooth, the reference's absolute median per phase, and repetition 1's
gap overall and per phase. Complete enough to rebuild the run, which is acceptance 7.

`facts.json` — everything observable about the machine and every version string, verbatim. Separate
from `results.json` for the reason the soak separates them: one is the measurement, the other is the
excuse.

`RESULTS.md` — the same run as a page: the header table, one table per phase, the verdict, and the
skipped rows with their reasons.

## An optimizer milestone's use of this

```sh
gh workflow run bench-cell.yml -f ref=<the branch>     # once step B exists
make bench-cell                                        # or locally, before and after
```

and the two dated directories are the evidence — which is precisely what M49 had to do by hand in a
scratchpad. Nothing here is a required status check and nothing here runs on a pull request: a
benchmark that gates merges is either a benchmark that gets ignored or a merge that blocks on noise.
