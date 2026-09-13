# Bench cell run linux-arm64-ubuntu-24.04-arm, 2026-09-13T21:11:16Z

Written by `bench/cell/cell.py` (M50 step A). Absolute seconds are recorded and
never gated; the verdict is the ratio of per-row medians to `c-O2`, built and timed
in this same run. See [`../cell/README.md`](../cell/README.md) for the protocol.

| | |
|---|---|
| cell | `linux-arm64-ubuntu-24.04-arm` |
| cpu | ? |
| nproc / mem | 4 / 16330088 kB |
| kernel | `Linux 6.17.0-1022-azure #22-Ubuntu SMP Mon Jul 27 17:12:01 UTC 2026 aarch64` |
| pinned cpus | 0 |
| image | `ubuntu24-arm64 20260907.118.1` |
| mc | `mc 0.15.34`, `os linux; arch aarch64; sys sys_linux_aarch64` |
| mc road | release, asset `mc-0.15.34-linux-arm64.tar.gz` |
| asset sha256 | `aa6f207810bb0fbc88cec6466a5bd5cd053790eaf42dbc86e58216a0bb51ffce` (verified before unpacking) |
| mc sha256 | `41fab98c3cfccd07820af5ae7edf4a177c1c0f5acd16e85a0b53a79f0e5f3621` (1432768 B) |
| reps | 7, first 1 dropped |
| runner cost | 5.71 min over 6 jobs (c 0.72, cs 0.82, go 0.85, mc 1.02, rust 0.98, zig 1.32) |
| tolerance / floor | 0.05 / 1.5 on `mix` |
| verdict | **ok** |

Toolchains, as the tools print them:

* `clang`: Ubuntu clang version 18.1.3 (1ubuntu1)
* `dotnet`: 10.0.400
* `go`: go version go1.26.7 linux/arm64
* `rustc`: rustc 1.96.0 (ac68faa20 2026-05-25)
* `zig`: 0.16.0

## Phase `all` (the reference, timed once per job: c 0.379 s, cs 0.430 s, go 0.392 s, mc 0.381 s, rust 0.376 s, zig 0.383 s)

| row | job | variant | median s | best s | max s | ratio | run RSS | compile s | binary B | `__text` B |
|---|---|---|---|---|---|---|---|---|---|---|
| `c-O2` | `c` | clang -O2 | 0.379 | 0.378 | 0.379 | 1.000 | 51417088 | 1.522 | 70624 | 1724 |
| `c-O0` | `c` | clang -O0 | 1.372 | 1.369 | 1.394 | 3.619 | 51417088 | 0.069 | 70680 | 1264 |
| `cs-aot` | `cs` | dotnet publish -p:PublishAot=true | 0.551 | 0.540 | 0.558 | 1.281 | 53903360 | 11.057 | 1188248 | 386284 |
| `cs-jit` | `cs` | dotnet publish (JIT, shared runtime) | 0.597 | 0.585 | 0.614 | 1.390 | 77680640 | 1.718 | 5120 | - |
| `go` | `go` | go build | 0.573 | 0.543 | 0.581 | 1.461 | 52334592 | 3.335 | 2395943 | 611556 |
| `mc-plain` | `mc` | mc --exe | 1.638 | 1.629 | 1.645 | 4.299 | 50802688 | 0.008 | 67256 | 1816 |
| `mc-opt` | `mc` | mc -O --exe | 0.661 | 0.658 | 0.664 | 1.736 | 50802688 | 0.008 | 67256 | 1560 |
| `rust-O3` | `rust` | rustc -C opt-level=3 | 0.371 | 0.370 | 0.374 | 0.987 | 51675136 | 0.163 | 4365368 | 228420 |
| `rust-O0` | `rust` | rustc -C opt-level=0 | 1.999 | 1.994 | 2.014 | 5.309 | 51732480 | 0.121 | 4374528 | 232436 |
| `zig-fast` | `zig` | zig -O ReleaseFast | 0.389 | 0.381 | 0.401 | 1.016 | 50618368 | 13.569 | 3828392 | 351088 |
| `zig-debug` | `zig` | zig -O Debug | 2.035 | 2.031 | 2.074 | 5.313 | 53678080 | 2.664 | 4371144 | 1286852 |

## Phase `mix` (the reference, timed once per job: c 0.141 s, cs 0.141 s, go 0.141 s, mc 0.141 s, rust 0.141 s, zig 0.141 s)

| row | job | variant | median s | best s | max s | ratio | run RSS | compile s | binary B | `__text` B |
|---|---|---|---|---|---|---|---|---|---|---|
| `c-O2` | `c` | clang -O2 | 0.141 | 0.141 | 0.141 | 1.000 | 19013632 | 1.522 | 70624 | 1724 |
| `c-O0` | `c` | clang -O0 | 0.717 | 0.716 | 0.740 | 5.087 | 19013632 | 0.069 | 70680 | 1264 |
| `cs-aot` | `cs` | dotnet publish -p:PublishAot=true | 0.143 | 0.142 | 0.143 | 1.010 | 20054016 | 11.057 | 1188248 | 386284 |
| `cs-jit` | `cs` | dotnet publish (JIT, shared runtime) | 0.172 | 0.172 | 0.174 | 1.217 | 27611136 | 1.718 | 5120 | - |
| `go` | `go` | go build | 0.264 | 0.264 | 0.265 | 1.873 | 20856832 | 3.335 | 2395943 | 611556 |
| `mc-plain` | `mc` | mc --exe | 0.928 | 0.927 | 0.929 | 6.587 | 19005440 | 0.008 | 67256 | 1816 |
| `mc-opt` | `mc` | mc -O --exe | 0.254 | 0.254 | 0.255 | 1.805 | 19005440 | 0.008 | 67256 | 1560 |
| `rust-O3` | `rust` | rustc -C opt-level=3 | 0.141 | 0.141 | 0.141 | 1.001 | 20893696 | 0.163 | 4365368 | 228420 |
| `rust-O0` | `rust` | rustc -C opt-level=0 | 0.782 | 0.780 | 0.823 | 5.551 | 20893696 | 0.121 | 4374528 | 232436 |
| `zig-fast` | `zig` | zig -O ReleaseFast | 0.141 | 0.141 | 0.141 | 1.002 | 21049344 | 13.569 | 3828392 | 351088 |
| `zig-debug` | `zig` | zig -O Debug | 0.940 | 0.940 | 0.946 | 6.668 | 21049344 | 2.664 | 4371144 | 1286852 |

## Phase `primes` (the reference, timed once per job: c 0.147 s, cs 0.200 s, go 0.173 s, mc 0.154 s, rust 0.145 s, zig 0.147 s)

| row | job | variant | median s | best s | max s | ratio | run RSS | compile s | binary B | `__text` B |
|---|---|---|---|---|---|---|---|---|---|---|
| `c-O2` | `c` | clang -O2 | 0.147 | 0.147 | 0.147 | 1.000 | 51417088 | 1.522 | 70624 | 1724 |
| `c-O0` | `c` | clang -O0 | 0.442 | 0.430 | 0.443 | 3.014 | 51351552 | 0.069 | 70680 | 1264 |
| `cs-aot` | `cs` | dotnet publish -p:PublishAot=true | 0.268 | 0.258 | 0.275 | 1.345 | 53837824 | 11.057 | 1188248 | 386284 |
| `cs-jit` | `cs` | dotnet publish (JIT, shared runtime) | 0.261 | 0.253 | 0.286 | 1.306 | 77680640 | 1.718 | 5120 | - |
| `go` | `go` | go build | 0.188 | 0.151 | 0.195 | 1.089 | 52334592 | 3.335 | 2395943 | 611556 |
| `mc-plain` | `mc` | mc --exe | 0.471 | 0.461 | 0.474 | 3.062 | 50802688 | 0.008 | 67256 | 1816 |
| `mc-opt` | `mc` | mc -O --exe | 0.216 | 0.212 | 0.222 | 1.406 | 50802688 | 0.008 | 67256 | 1560 |
| `rust-O3` | `rust` | rustc -C opt-level=3 | 0.139 | 0.138 | 0.140 | 0.963 | 51609600 | 0.163 | 4365368 | 228420 |
| `rust-O0` | `rust` | rustc -C opt-level=0 | 0.848 | 0.800 | 0.853 | 5.866 | 51732480 | 0.121 | 4374528 | 232436 |
| `zig-fast` | `zig` | zig -O ReleaseFast | 0.161 | 0.150 | 0.178 | 1.095 | 50618368 | 13.569 | 3828392 | 351088 |
| `zig-debug` | `zig` | zig -O Debug | 0.780 | 0.771 | 0.886 | 5.295 | 53678080 | 2.664 | 4371144 | 1286852 |

## Phase `fib` (the reference, timed once per job: c 0.094 s, cs 0.094 s, go 0.094 s, mc 0.094 s, rust 0.094 s, zig 0.094 s)

| row | job | variant | median s | best s | max s | ratio | run RSS | compile s | binary B | `__text` B |
|---|---|---|---|---|---|---|---|---|---|---|
| `c-O2` | `c` | clang -O2 | 0.094 | 0.094 | 0.094 | 1.000 | 19013632 | 1.522 | 70624 | 1724 |
| `c-O0` | `c` | clang -O0 | 0.222 | 0.222 | 0.223 | 2.363 | 19013632 | 0.069 | 70680 | 1264 |
| `cs-aot` | `cs` | dotnet publish -p:PublishAot=true | 0.135 | 0.135 | 0.136 | 1.429 | 20054016 | 11.057 | 1188248 | 386284 |
| `cs-jit` | `cs` | dotnet publish (JIT, shared runtime) | 0.201 | 0.200 | 0.201 | 2.128 | 26955776 | 1.718 | 5120 | - |
| `go` | `go` | go build | 0.125 | 0.124 | 0.125 | 1.326 | 20856832 | 3.335 | 2395943 | 611556 |
| `mc-plain` | `mc` | mc --exe | 0.244 | 0.243 | 0.244 | 2.587 | 19005440 | 0.008 | 67256 | 1816 |
| `mc-opt` | `mc` | mc -O --exe | 0.193 | 0.192 | 0.193 | 2.043 | 19005440 | 0.008 | 67256 | 1560 |
| `rust-O3` | `rust` | rustc -C opt-level=3 | 0.090 | 0.089 | 0.090 | 0.954 | 20893696 | 0.163 | 4365368 | 228420 |
| `rust-O0` | `rust` | rustc -C opt-level=0 | 0.374 | 0.373 | 0.375 | 3.976 | 20893696 | 0.121 | 4374528 | 232436 |
| `zig-fast` | `zig` | zig -O ReleaseFast | 0.091 | 0.090 | 0.092 | 0.962 | 21049344 | 13.569 | 3828392 | 351088 |
| `zig-debug` | `zig` | zig -O Debug | 0.327 | 0.326 | 0.329 | 3.467 | 21049344 | 2.664 | 4371144 | 1286852 |

## Verdict

* tooth `mc-plain / mc-opt` on `mix`: **3.6498** (floor 1.5)
* repetition 1 against the best of the kept (the `c,cs,go,mc,rust,zig` job's): 0.996x to 1.021x, median 1.002x -- which is why it is dropped
  * phase `all`: 1.001x to 1.015x, median 1.015x (run first in each repetition, so it pays the cold pages)
  * phase `mix`: 1.0x to 1.003x, median 1.001x
  * phase `primes`: 1.011x to 1.021x, median 1.013x
  * phase `fib`: 0.996x to 1.002x, median 1.002x
* every repetition of every row printed the workload's recorded answer: yes
