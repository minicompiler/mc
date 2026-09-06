# The HTTP soak

Every server under the same fixed request rate for the same length of time, one GitHub Actions
runner per server, the server pinned to two cores and the load generator to the other two; the
server's whole process tree sampled every few seconds. Produced by `bench/soak/report.py` from
the artifacts of `.github/workflows/bench-soak.yml`; the protocol is `bench/README.md` § The soak.

## Conditions

| | |
|---|---|
| Runner | ubuntu24 20260831.293.1 (`RUNNER_NAME` GitHub Actions 1000000843, X64) |
| Kernel | Linux runnervmejwal 6.17.0-1022-azure #22-Ubuntu SMP Mon Jul 27 17:24:03 UTC 2026 x86_64 x86_64 |
| OS | Ubuntu 24.04.4 LTS |
| CPUs / memory | 4 vCPU, 16373452 kB |
| Pinning | server on cores 0,1, oha and the sampler on cores 2,3 (`taskset`) |
| Load | `oha` oha 1.16.0: 3000 req/s over 16 connections, keep-alive on, 60.0 min |
| Sampling | every 5.0 s: RSS/CPU time/threads/processes of the tree, VmRSS/VmHWM of the parent, loadavg |
| Date | 2026-09-06 21:57:25 UTC |
| Tree | `7d01b3a` (run 34062566194) |

Toolchains, as each job recorded them:

| server | toolchain |
|---|---|
| `mc-serial` | `mc 0.15.15` |
| `mc-forkka` | `mc 0.15.15` |
| `c-serial` | `Ubuntu clang version 18.1.3 (1ubuntu1)` |
| `go-nethttp` | `go version go1.26.7 linux/amd64` |
| `rust-threads` | `rustc 1.96.0 (ac68faa20 2026-05-25)` |
| `rust-axum` | `rustc 1.96.0 (ac68faa20 2026-05-25)`; `cargo 1.96.0 (30a34c682 2026-05-25)` |
| `zig-threads` | `0.16.0` |
| `cs-jit` | `10.0.400` |
| `cs-aot` | `10.0.400` |
| `node-single` | `v24.20.0` |
| `node-cluster` | `v24.20.0` |
| `py-uvicorn` | `Python 3.12.14`; `Running uvicorn 0.39.0 with CPython 3.12.14 on Linux` |
| `rb-puma` | `ruby 3.3.12 (2026-07-16 revision 0581089df9) [x86_64-linux]`; `puma version 6.6.1` |
| `php-builtin` | `PHP 8.4.25 (cli) (built: Aug 27 2026 15:39:11) (NTS)` |

## Throughput and latency

`req/s` is what oha achieved against what was asked; `requests` counts every response, `non-200`
the ones that were not `200`, `errors` the connection-level failures oha reported (an `aborted due to
deadline` at the very end is the normal way a timed run stops). Latencies in ms, from oha's
own histogram.

| server | req/s (asked) | requests | non-200 | errors | p50 | p99 | p99.9 | startup |
|---|---|---|---|---|---|---|---|---|
| `mc-serial` | 3,000.0 (3,000) | 10,799,997 | 0 | 0 | 0.168 | 0.302 | 0.418 | 8 ms |
| `mc-forkka` | 3,000.0 (3,000) | 10,800,000 | 0 | 2 | 0.077 | 0.118 | 0.150 | 8 ms |
| `c-serial` | 3,000.0 (3,000) | 10,800,000 | 0 | 2 | 0.167 | 0.306 | 0.477 | 8 ms |
| `go-nethttp` | 3,000.0 (3,000) | 10,800,000 | 0 | 2 | 0.122 | 0.219 | 0.354 | 24 ms |
| `rust-threads` | 3,000.0 (3,000) | 10,799,998 | 0 | 2 | 0.073 | 0.116 | 0.148 | 9 ms |
| `rust-axum` | 3,000.0 (3,000) | 10,799,997 | 0 | 1 | 0.057 | 0.081 | 0.322 | 100 ms |
| `zig-threads` | 3,000.0 (3,000) | 10,800,000 | 0 | 4 | 0.070 | 0.114 | 0.151 | 8 ms |
| `cs-jit` | 3,000.0 (3,000) | 10,800,000 | 0 | 3 | 0.122 | 0.181 | 0.386 | 851 ms |
| `cs-aot` | 3,000.0 (3,000) | 10,799,998 | 0 | 3 | 0.071 | 0.101 | 0.137 | 61 ms |
| `node-single` | 3,000.0 (3,000) | 10,799,998 | 0 | 0 | 0.041 | 0.082 | 0.444 | 127 ms |
| `node-cluster` | 3,000.0 (3,000) | 10,799,999 | 0 | 3 | 0.127 | 0.232 | 0.290 | 129 ms |
| `py-uvicorn` | - (3,000) | 0 | 0 | 0 | - | - | - | - ms |
| `rb-puma` | 3,000.0 (3,000) | 10,799,988 | 0 | 11 | 0.163 | 38.476 | 41.994 | 672 ms |
| `php-builtin` | 3,000.0 (3,000) | 10,799,997 | 0 | 1 | 0.318 | 0.719 | 1.699 | 58 ms |

## Memory and CPU

RSS is the sum over the server's process tree (a fork-per-connection server's children, a
cluster's workers) in KiB, read at the given minute since the server started; `peak` over the
whole run; `slope` is the least-squares fit of RSS against time over the window named in the
verdict lines below, with its R^2. `%CPU` is the tree's CPU time per wall-clock second, averaged
over the load (100 = one core); `CPU ms / 1k req` is the tree's CPU time over the load divided by
the requests oha counted -- the number comparable across concurrency shapes. `end` is the last
sample taken more than a second before oha's deadline (oha closes its connections at the
deadline, and a sample taken in those seconds sees a server whose workers are already gone).

| server | RSS 1 min | 10 min | 30 min | 60 min | end | peak | slope KiB/min (R^2) | %CPU mean | CPU ms / 1k req | threads max | procs max |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `mc-serial` | 940 | 940 | 940 | 940 | 940 | 940 | +0.0 (1.00) | 7.6 | 25.46 | 1 | 1 |
| `mc-forkka` | 5,348 | 5,348 | 5,348 | 5,348 | 5,348 | 5,348 | +0.0 (1.00) | 8.1 | 27.07 | 17 | 17 |
| `c-serial` | 1,124 | 1,124 | 1,124 | 1,124 | 1,124 | 1,124 | +0.0 (1.00) | 7.4 | 24.79 | 1 | 1 |
| `go-nethttp` | 15,828 | 15,784 | 16,032 | 15,956 | 16,108 | 16,556 | +2.0 (0.08) | 20.9 | 69.48 | 7 | 1 |
| `rust-threads` | 2,436 | 2,436 | 2,436 | 2,436 | 2,436 | 2,436 | +0.0 (1.00) | 6.8 | 22.52 | 17 | 1 |
| `rust-axum` | 3,832 | 3,832 | 3,832 | 3,832 | 3,832 | 3,832 | +0.0 (1.00) | 6.4 | 21.22 | 3 | 1 |
| `zig-threads` | 12,480 | 12,480 | 12,480 | 12,480 | 12,480 | 12,480 | +0.0 (1.00) | 6.8 | 22.53 | 17 | 1 |
| `cs-jit` | 66,196 | 68,452 | 68,964 | 69,732 | 69,732 | 69,988 | +26.2 (0.98) | 32.5 | 108.37 | 18 | 1 |
| `cs-aot` | 19,780 | 19,488 | 19,872 | 20,640 | 20,640 | 20,640 | +23.1 (0.96) | 11.7 | 39.02 | 13 | 1 |
| `node-single` | 68,656 | 72,496 | 79,792 | 94,128 | 94,128 | 94,396 | +369.6 (0.68) | 4.8 | 16.00 | 7 | 1 |
| `node-cluster` | 191,784 | 199,208 | 200,752 | 215,216 | 215,216 | 215,776 | +448.1 (0.80) | 22.2 | 73.89 | 21 | 3 |
| `py-uvicorn` | - | - | - | - | - | - | - | - | - | - | - |
| `rb-puma` | 46,280 | 46,536 | 47,048 | 47,304 | 47,304 | 47,304 | +12.8 (0.91) | 21.1 | 70.46 | 12 | 1 |
| `php-builtin` | 66,352 | 142,256 | 311,088 | 564,400 | 564,400 | 564,784 | +8437.6 (1.00) | 35.3 | 117.68 | 1 | 1 |

## What drifted

One line per server, from the numbers above. `drifted` means the fitted slope, projected over the
window, moves RSS by at least 5% of the window's mean AND the fit explains at least half of the
variance (R^2 >= 0.5); anything else is `flat`. A rule, not a judgement -- read the chart.

- `mc-serial`: RSS 940 -> 940 KiB over minutes 10-60 (+0.0%), slope +0.0 KiB/min (R^2 1.00), peak 940 KiB: **flat**
- `mc-forkka`: RSS 5,348 -> 5,348 KiB over minutes 10-60 (+0.0%), slope +0.0 KiB/min (R^2 1.00), peak 5,348 KiB: **flat**
- `c-serial`: RSS 1,124 -> 1,124 KiB over minutes 10-60 (+0.0%), slope +0.0 KiB/min (R^2 1.00), peak 1,124 KiB: **flat**
- `go-nethttp`: RSS 15,784 -> 16,108 KiB over minutes 10-60 (+2.1%), slope +2.0 KiB/min (R^2 0.08), peak 16,556 KiB: **flat**
- `rust-threads`: RSS 2,436 -> 2,436 KiB over minutes 10-60 (+0.0%), slope +0.0 KiB/min (R^2 1.00), peak 2,436 KiB: **flat**
- `rust-axum`: RSS 3,832 -> 3,832 KiB over minutes 10-60 (+0.0%), slope +0.0 KiB/min (R^2 1.00), peak 3,832 KiB: **flat**
- `zig-threads`: RSS 12,480 -> 12,480 KiB over minutes 10-60 (+0.0%), slope +0.0 KiB/min (R^2 1.00), peak 12,480 KiB: **flat**
- `cs-jit`: RSS 68,452 -> 69,732 KiB over minutes 10-60 (+1.9%), slope +26.2 KiB/min (R^2 0.98), peak 69,988 KiB: **flat**
- `cs-aot`: RSS 19,488 -> 20,640 KiB over minutes 10-60 (+5.9%), slope +23.1 KiB/min (R^2 0.96), peak 20,640 KiB: **drifted**
- `node-single`: RSS 72,496 -> 94,128 KiB over minutes 10-60 (+29.8%), slope +369.6 KiB/min (R^2 0.68), peak 94,396 KiB: **drifted**
- `node-cluster`: RSS 199,336 -> 215,216 KiB over minutes 10-60 (+8.0%), slope +448.1 KiB/min (R^2 0.80), peak 215,776 KiB: **drifted**
- `py-uvicorn`: no RSS window (server did not answer 200 within 90 s (exit 2))
- `rb-puma`: RSS 46,536 -> 47,304 KiB over minutes 10-60 (+1.7%), slope +12.8 KiB/min (R^2 0.91), peak 47,304 KiB: **flat**
- `php-builtin`: RSS 143,024 -> 564,400 KiB over minutes 10-60 (+294.6%), slope +8437.6 KiB/min (R^2 1.00), peak 564,784 KiB: **drifted**

Runs that ended with an error (their numbers above cover what was recorded before it):

- `py-uvicorn`: server did not answer 200 within 90 s (exit 2)

## Charts

`rss.svg` (RSS of the tree, log scale: the range spans more than 20x), `cpu.svg`, `threads.svg` --
every server on one chart -- and one `<server>.svg` per server with its three panels, from the
server's start to oha's deadline (the teardown after it is not charted). All in this directory,
drawn by `report.py` with no library: dark text on a white background.
