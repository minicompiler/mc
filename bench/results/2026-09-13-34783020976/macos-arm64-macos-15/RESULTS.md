# Bench cell run macos-arm64-macos-15, 2026-09-13T21:11:09Z

Written by `bench/cell/cell.py` (M50 step A). Absolute seconds are recorded and
never gated; the verdict is the ratio of per-row medians to `c-O2`, built and timed
in this same run. See [`../cell/README.md`](../cell/README.md) for the protocol.

| | |
|---|---|
| cell | `macos-arm64-macos-15` |
| cpu | Apple M1 (Virtual) |
| nproc / mem | 3 / 7340032 kB |
| kernel | `Darwin 24.6.0 Darwin Kernel Version 24.6.0: Tue Jul 21 20:51:34 PDT 2026; root:xnu-11417.140.69.711.44~1/RELEASE_ARM64_VMAPPLE arm64` |
| pinned cpus | none (not Linux) |
| image | `macos15 20260907.0337.1` |
| mc | `mc 0.15.34`, `os macos; arch aarch64; sys sys` |
| mc road | release, asset `mc-0.15.34-macos-arm64.tar.gz` |
| asset sha256 | `7dedb269af8ecbdc8068ba538b435b766d9d13428e3a1a6268744b121e64b864` (verified before unpacking) |
| mc sha256 | `5980c68162488ef0b4f20eb5822a9742aef5ae456b80e27b62abe6e570d6dbc8` (1400287 B) |
| reps | 7, first 1 dropped |
| runner cost | 5.71 min over 6 jobs (c 0.7, cs 0.93, go 0.78, mc 1.03, rust 1.05, zig 1.22) |
| tolerance / floor | 0.05 / 1.5 on `mix` |
| verdict | **ok** |

Toolchains, as the tools print them:

* `clang`: Apple clang version 17.0.0 (clang-1700.0.13.5)
* `dotnet`: 10.0.400
* `go`: go version go1.26.7 darwin/arm64
* `rustc`: rustc 1.96.0 (ac68faa20 2026-05-25)
* `zig`: 0.16.0

## Phase `all` (the reference, timed once per job: c 0.710 s, cs 0.729 s, go 0.570 s, mc 0.719 s, rust 0.556 s, zig 0.641 s)

| row | job | variant | median s | best s | max s | ratio | run RSS | compile s | binary B | `__text` B |
|---|---|---|---|---|---|---|---|---|---|---|
| `c-O2` | `c` | clang -O2 | 0.710 | 0.627 | 0.758 | 1.000 | 51200000 | 0.743 | 33464 | 1464 |
| `c-O0` | `c` | clang -O0 | 1.628 | 1.367 | 1.713 | 2.292 | 51200000 | 0.107 | 33528 | 980 |
| `cs-aot` | `cs` | dotnet publish -p:PublishAot=true | 0.848 | 0.818 | 0.865 | 1.163 | 54067200 | 10.291 | 1102808 | 369068 |
| `cs-jit` | `cs` | dotnet publish (JIT, shared runtime) | 0.860 | 0.813 | 0.889 | 1.179 | 84705280 | 1.116 | 5120 | - |
| `go` | `go` | go build | 0.728 | 0.661 | 0.791 | 1.277 | 54509568 | 3.968 | 2492498 | 649540 |
| `mc-plain` | `mc` | mc --exe | 1.819 | 1.692 | 1.995 | 2.530 | 51150848 | 0.060 | 33461 | 1816 |
| `mc-opt` | `mc` | mc -O --exe | 1.045 | 0.946 | 1.200 | 1.453 | 51150848 | 0.045 | 33459 | 1560 |
| `rust-O3` | `rust` | rustc -C opt-level=3 | 0.564 | 0.550 | 0.662 | 1.014 | 51429376 | 2.978 | 468616 | 219136 |
| `rust-O0` | `rust` | rustc -C opt-level=0 | 1.723 | 1.630 | 1.819 | 3.097 | 51462144 | 0.154 | 492232 | 223036 |
| `zig-fast` | `zig` | zig -O ReleaseFast | 0.695 | 0.620 | 0.810 | 1.085 | 51380224 | 8.613 | 396216 | 239004 |
| `zig-debug` | `zig` | zig -O Debug | 1.853 | 1.760 | 2.038 | 2.891 | 52969472 | 1.742 | 2047432 | 1273504 |

## Phase `mix` (the reference, timed once per job: c 0.261 s, cs 0.252 s, go 0.225 s, mc 0.263 s, rust 0.230 s, zig 0.239 s)

| row | job | variant | median s | best s | max s | ratio | run RSS | compile s | binary B | `__text` B |
|---|---|---|---|---|---|---|---|---|---|---|
| `c-O2` | `c` | clang -O2 | 0.261 | 0.240 | 0.284 | 1.000 | 1196032 | 0.743 | 33464 | 1464 |
| `c-O0` | `c` | clang -O0 | 0.781 | 0.597 | 0.869 | 2.997 | 1196032 | 0.107 | 33528 | 980 |
| `cs-aot` | `cs` | dotnet publish -p:PublishAot=true | 0.256 | 0.243 | 0.296 | 1.017 | 4128768 | 10.291 | 1102808 | 369068 |
| `cs-jit` | `cs` | dotnet publish (JIT, shared runtime) | 0.301 | 0.276 | 0.354 | 1.196 | 37928960 | 1.116 | 5120 | - |
| `go` | `go` | go build | 0.360 | 0.321 | 0.365 | 1.597 | 3948544 | 3.968 | 2492498 | 649540 |
| `mc-plain` | `mc` | mc --exe | 0.905 | 0.847 | 1.053 | 3.439 | 1179648 | 0.060 | 33461 | 1816 |
| `mc-opt` | `mc` | mc -O --exe | 0.374 | 0.344 | 0.419 | 1.420 | 1245184 | 0.045 | 33459 | 1560 |
| `rust-O3` | `rust` | rustc -C opt-level=3 | 0.227 | 0.215 | 0.247 | 0.989 | 1409024 | 2.978 | 468616 | 219136 |
| `rust-O0` | `rust` | rustc -C opt-level=0 | 0.622 | 0.588 | 0.666 | 2.706 | 1441792 | 0.154 | 492232 | 223036 |
| `zig-fast` | `zig` | zig -O ReleaseFast | 0.242 | 0.231 | 0.263 | 1.012 | 1490944 | 8.613 | 396216 | 239004 |
| `zig-debug` | `zig` | zig -O Debug | 0.743 | 0.701 | 0.906 | 3.103 | 2965504 | 1.742 | 2047432 | 1273504 |

## Phase `primes` (the reference, timed once per job: c 0.304 s, cs 0.284 s, go 0.210 s, mc 0.281 s, rust 0.204 s, zig 0.273 s)

| row | job | variant | median s | best s | max s | ratio | run RSS | compile s | binary B | `__text` B |
|---|---|---|---|---|---|---|---|---|---|---|
| `c-O2` | `c` | clang -O2 | 0.304 | 0.222 | 0.367 | 1.000 | 51265536 | 0.743 | 33464 | 1464 |
| `c-O0` | `c` | clang -O0 | 0.500 | 0.424 | 0.942 | 1.642 | 51200000 | 0.107 | 33528 | 980 |
| `cs-aot` | `cs` | dotnet publish -p:PublishAot=true | 0.376 | 0.342 | 0.438 | 1.325 | 53968896 | 10.291 | 1102808 | 369068 |
| `cs-jit` | `cs` | dotnet publish (JIT, shared runtime) | 0.372 | 0.318 | 0.525 | 1.310 | 84623360 | 1.116 | 5120 | - |
| `go` | `go` | go build | 0.223 | 0.210 | 0.257 | 1.064 | 54493184 | 3.968 | 2492498 | 649540 |
| `mc-plain` | `mc` | mc --exe | 0.675 | 0.597 | 0.813 | 2.405 | 51265536 | 0.060 | 33461 | 1816 |
| `mc-opt` | `mc` | mc -O --exe | 0.403 | 0.354 | 0.520 | 1.437 | 51150848 | 0.045 | 33459 | 1560 |
| `rust-O3` | `rust` | rustc -C opt-level=3 | 0.217 | 0.203 | 0.240 | 1.063 | 51429376 | 2.978 | 468616 | 219136 |
| `rust-O0` | `rust` | rustc -C opt-level=0 | 0.860 | 0.748 | 0.898 | 4.213 | 51462144 | 0.154 | 492232 | 223036 |
| `zig-fast` | `zig` | zig -O ReleaseFast | 0.292 | 0.235 | 0.394 | 1.069 | 51380224 | 8.613 | 396216 | 239004 |
| `zig-debug` | `zig` | zig -O Debug | 0.813 | 0.756 | 0.859 | 2.978 | 53035008 | 1.742 | 2047432 | 1273504 |

## Phase `fib` (the reference, timed once per job: c 0.170 s, cs 0.156 s, go 0.131 s, mc 0.154 s, rust 0.133 s, zig 0.146 s)

| row | job | variant | median s | best s | max s | ratio | run RSS | compile s | binary B | `__text` B |
|---|---|---|---|---|---|---|---|---|---|---|
| `c-O2` | `c` | clang -O2 | 0.170 | 0.158 | 0.220 | 1.000 | 1196032 | 0.743 | 33464 | 1464 |
| `c-O0` | `c` | clang -O0 | 0.317 | 0.269 | 0.333 | 1.862 | 1196032 | 0.107 | 33528 | 980 |
| `cs-aot` | `cs` | dotnet publish -p:PublishAot=true | 0.214 | 0.195 | 0.264 | 1.370 | 4014080 | 10.291 | 1102808 | 369068 |
| `cs-jit` | `cs` | dotnet publish (JIT, shared runtime) | 0.205 | 0.188 | 0.254 | 1.309 | 37896192 | 1.116 | 5120 | - |
| `go` | `go` | go build | 0.150 | 0.137 | 0.158 | 1.144 | 3866624 | 3.968 | 2492498 | 649540 |
| `mc-plain` | `mc` | mc --exe | 0.257 | 0.214 | 0.307 | 1.669 | 1179648 | 0.060 | 33461 | 1816 |
| `mc-opt` | `mc` | mc -O --exe | 0.259 | 0.206 | 0.278 | 1.684 | 1277952 | 0.045 | 33459 | 1560 |
| `rust-O3` | `rust` | rustc -C opt-level=3 | 0.130 | 0.124 | 0.144 | 0.982 | 1409024 | 2.978 | 468616 | 219136 |
| `rust-O0` | `rust` | rustc -C opt-level=0 | 0.305 | 0.277 | 0.424 | 2.295 | 1441792 | 0.154 | 492232 | 223036 |
| `zig-fast` | `zig` | zig -O ReleaseFast | 0.149 | 0.137 | 0.196 | 1.018 | 1359872 | 8.613 | 396216 | 239004 |
| `zig-debug` | `zig` | zig -O Debug | 0.307 | 0.295 | 0.311 | 2.099 | 2965504 | 1.742 | 2047432 | 1273504 |

## Verdict

* tooth `mc-plain / mc-opt` on `mix`: **2.422** (floor 1.5)
* repetition 1 against the best of the kept (the `c,cs,go,mc,rust,zig` job's): 1.082x to 1.408x, median 1.234x -- which is why it is dropped
  * phase `all`: 1.212x to 1.267x, median 1.253x (run first in each repetition, so it pays the cold pages)
  * phase `mix`: 1.082x to 1.136x, median 1.116x
  * phase `primes`: 1.22x to 1.383x, median 1.247x
  * phase `fib`: 1.129x to 1.408x, median 1.301x
* every repetition of every row printed the workload's recorded answer: yes
