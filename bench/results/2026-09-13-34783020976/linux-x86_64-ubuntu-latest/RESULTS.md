# Bench cell run linux-x86_64-ubuntu-latest, 2026-09-13T21:11:02Z

Written by `bench/cell/cell.py` (M50 step A). Absolute seconds are recorded and
never gated; the verdict is the ratio of per-row medians to `c-O2`, built and timed
in this same run. See [`../cell/README.md`](../cell/README.md) for the protocol.

| | |
|---|---|
| cell | `linux-x86_64-ubuntu-latest` |
| cpu | AMD EPYC 7763 64-Core Processor |
| nproc / mem | 4 / 16373452 kB |
| kernel | `Linux 6.17.0-1022-azure #22-Ubuntu SMP Mon Jul 27 17:24:03 UTC 2026 x86_64` |
| pinned cpus | 0 |
| image | `ubuntu24 20260907.300.1` |
| mc | `mc 0.15.34`, `os linux; arch x86_64; sys sys_linux_x86_64` |
| mc road | release, asset `mc-0.15.34-linux-x86_64.tar.gz` |
| asset sha256 | `2134e49686d170bab8f6c1020ae24493ad3adb966347833808c732e3f1acc840` (verified before unpacking) |
| mc sha256 | `804135cf545607c29d2a9b6aa98a56c9120f9e0836a4c1b247711a3da1f0d858` (1446104 B) |
| reps | 7, first 1 dropped |
| runner cost | 6.15 min over 6 jobs (c 0.9, cs 1.12, go 0.72, mc 0.88, rust 1.05, zig 1.48) |
| tolerance / floor | 0.05 / 1.1 on `mix` |
| verdict | **ok** |

Toolchains, as the tools print them:

* `clang`: Ubuntu clang version 18.1.3 (1ubuntu1)
* `dotnet`: 10.0.400
* `go`: go version go1.26.7 linux/amd64
* `rustc`: rustc 1.96.0 (ac68faa20 2026-05-25)
* `zig`: 0.16.0

## Phase `all` (the reference, timed once per job: c 0.579 s, cs 0.653 s, go 0.613 s, mc 0.569 s, rust 0.571 s, zig 0.654 s)

| row | job | variant | median s | best s | max s | ratio | run RSS | compile s | binary B | `__text` B |
|---|---|---|---|---|---|---|---|---|---|---|
| `c-O2` | `c` | clang -O2 | 0.579 | 0.572 | 0.602 | 1.000 | 51585024 | 3.844 | 16072 | 919 |
| `c-O0` | `c` | clang -O0 | 1.576 | 1.573 | 1.580 | 2.721 | 51625984 | 0.077 | 16128 | 1050 |
| `cs-aot` | `cs` | dotnet publish -p:PublishAot=true | 0.835 | 0.831 | 0.862 | 1.278 | 54185984 | 11.601 | 1151552 | 403506 |
| `cs-jit` | `cs` | dotnet publish (JIT, shared runtime) | 0.870 | 0.866 | 0.885 | 1.331 | 78725120 | 1.573 | 5120 | 2288 |
| `go` | `go` | go build | 0.747 | 0.742 | 0.802 | 1.218 | 56520704 | 4.894 | 2402055 | 644145 |
| `mc-plain` | `mc` | mc --exe | 1.250 | 1.238 | 1.267 | 2.196 | 50982912 | 0.008 | 5816 | 1978 |
| `mc-opt` | `mc` | mc -O --exe | 0.962 | 0.955 | 0.982 | 1.690 | 50982912 | 0.008 | 5816 | 1637 |
| `rust-O3` | `rust` | rustc -C opt-level=3 | 0.571 | 0.569 | 0.579 | 1.000 | 52019200 | 0.113 | 4341320 | 253587 |
| `rust-O0` | `rust` | rustc -C opt-level=0 | 2.138 | 2.134 | 2.154 | 3.744 | 52031488 | 0.070 | 4357504 | 258259 |
| `zig-fast` | `zig` | zig -O ReleaseFast | 0.645 | 0.610 | 0.656 | 0.986 | 50659328 | 18.666 | 3905744 | 412105 |
| `zig-debug` | `zig` | zig -O Debug | 2.170 | 2.149 | 2.179 | 3.317 | 55021568 | 3.578 | 10278968 | 2136618 |

## Phase `mix` (the reference, timed once per job: c 0.303 s, cs 0.342 s, go 0.303 s, mc 0.303 s, rust 0.303 s, zig 0.342 s)

| row | job | variant | median s | best s | max s | ratio | run RSS | compile s | binary B | `__text` B |
|---|---|---|---|---|---|---|---|---|---|---|
| `c-O2` | `c` | clang -O2 | 0.303 | 0.303 | 0.303 | 1.000 | 19984384 | 3.844 | 16072 | 919 |
| `c-O0` | `c` | clang -O0 | 0.840 | 0.840 | 0.842 | 2.774 | 19984384 | 0.077 | 16128 | 1050 |
| `cs-aot` | `cs` | dotnet publish -p:PublishAot=true | 0.356 | 0.356 | 0.359 | 1.042 | 20914176 | 11.601 | 1151552 | 403506 |
| `cs-jit` | `cs` | dotnet publish (JIT, shared runtime) | 0.384 | 0.383 | 0.392 | 1.122 | 28762112 | 1.573 | 5120 | 2288 |
| `go` | `go` | go build | 0.316 | 0.316 | 0.317 | 1.042 | 22179840 | 4.894 | 2402055 | 644145 |
| `mc-plain` | `mc` | mc --exe | 0.523 | 0.517 | 0.529 | 1.727 | 19988480 | 0.008 | 5816 | 1978 |
| `mc-opt` | `mc` | mc -O --exe | 0.438 | 0.438 | 0.450 | 1.447 | 19988480 | 0.008 | 5816 | 1637 |
| `rust-O3` | `rust` | rustc -C opt-level=3 | 0.303 | 0.303 | 0.303 | 1.000 | 22204416 | 0.113 | 4341320 | 253587 |
| `rust-O0` | `rust` | rustc -C opt-level=0 | 0.870 | 0.870 | 0.872 | 2.873 | 22204416 | 0.070 | 4357504 | 258259 |
| `zig-fast` | `zig` | zig -O ReleaseFast | 0.315 | 0.315 | 0.316 | 0.922 | 22106112 | 18.666 | 3905744 | 412105 |
| `zig-debug` | `zig` | zig -O Debug | 0.783 | 0.782 | 0.786 | 2.292 | 22106112 | 3.578 | 10278968 | 2136618 |

## Phase `primes` (the reference, timed once per job: c 0.165 s, cs 0.207 s, go 0.199 s, mc 0.155 s, rust 0.159 s, zig 0.203 s)

| row | job | variant | median s | best s | max s | ratio | run RSS | compile s | binary B | `__text` B |
|---|---|---|---|---|---|---|---|---|---|---|
| `c-O2` | `c` | clang -O2 | 0.165 | 0.158 | 0.172 | 1.000 | 51585024 | 3.844 | 16072 | 919 |
| `c-O0` | `c` | clang -O0 | 0.512 | 0.506 | 0.519 | 3.104 | 51601408 | 0.077 | 16128 | 1050 |
| `cs-aot` | `cs` | dotnet publish -p:PublishAot=true | 0.270 | 0.250 | 0.278 | 1.302 | 54104064 | 11.601 | 1151552 | 403506 |
| `cs-jit` | `cs` | dotnet publish (JIT, shared runtime) | 0.288 | 0.272 | 0.299 | 1.390 | 78630912 | 1.573 | 5120 | 2288 |
| `go` | `go` | go build | 0.216 | 0.203 | 0.262 | 1.089 | 56516608 | 4.894 | 2402055 | 644145 |
| `mc-plain` | `mc` | mc --exe | 0.424 | 0.420 | 0.436 | 2.737 | 50982912 | 0.008 | 5816 | 1978 |
| `mc-opt` | `mc` | mc -O --exe | 0.262 | 0.259 | 0.266 | 1.692 | 50982912 | 0.008 | 5816 | 1637 |
| `rust-O3` | `rust` | rustc -C opt-level=3 | 0.157 | 0.157 | 0.161 | 0.990 | 52023296 | 0.113 | 4341320 | 253587 |
| `rust-O0` | `rust` | rustc -C opt-level=0 | 0.949 | 0.944 | 0.955 | 5.975 | 52031488 | 0.070 | 4357504 | 258259 |
| `zig-fast` | `zig` | zig -O ReleaseFast | 0.205 | 0.171 | 0.212 | 1.008 | 50659328 | 18.666 | 3905744 | 412105 |
| `zig-debug` | `zig` | zig -O Debug | 0.873 | 0.855 | 0.877 | 4.295 | 55021568 | 3.578 | 10278968 | 2136618 |

## Phase `fib` (the reference, timed once per job: c 0.114 s, cs 0.118 s, go 0.114 s, mc 0.114 s, rust 0.114 s, zig 0.118 s)

| row | job | variant | median s | best s | max s | ratio | run RSS | compile s | binary B | `__text` B |
|---|---|---|---|---|---|---|---|---|---|---|
| `c-O2` | `c` | clang -O2 | 0.114 | 0.113 | 0.114 | 1.000 | 19984384 | 3.844 | 16072 | 919 |
| `c-O0` | `c` | clang -O0 | 0.229 | 0.229 | 0.232 | 2.015 | 19984384 | 0.077 | 16128 | 1050 |
| `cs-aot` | `cs` | dotnet publish -p:PublishAot=true | 0.254 | 0.253 | 0.254 | 2.149 | 20914176 | 11.601 | 1151552 | 403506 |
| `cs-jit` | `cs` | dotnet publish (JIT, shared runtime) | 0.282 | 0.281 | 0.283 | 2.388 | 28073984 | 1.573 | 5120 | 2288 |
| `go` | `go` | go build | 0.225 | 0.211 | 0.231 | 1.983 | 22179840 | 4.894 | 2402055 | 644145 |
| `mc-plain` | `mc` | mc --exe | 0.301 | 0.299 | 0.304 | 2.647 | 19988480 | 0.008 | 5816 | 1978 |
| `mc-opt` | `mc` | mc -O --exe | 0.264 | 0.263 | 0.270 | 2.321 | 19988480 | 0.008 | 5816 | 1637 |
| `rust-O3` | `rust` | rustc -C opt-level=3 | 0.114 | 0.113 | 0.121 | 1.000 | 22204416 | 0.113 | 4341320 | 253587 |
| `rust-O0` | `rust` | rustc -C opt-level=0 | 0.323 | 0.323 | 0.326 | 2.844 | 22204416 | 0.070 | 4357504 | 258259 |
| `zig-fast` | `zig` | zig -O ReleaseFast | 0.126 | 0.126 | 0.126 | 1.072 | 22106112 | 18.666 | 3905744 | 412105 |
| `zig-debug` | `zig` | zig -O Debug | 0.533 | 0.532 | 0.534 | 4.532 | 22106112 | 3.578 | 10278968 | 2136618 |

## Verdict

* tooth `mc-plain / mc-opt` on `mix`: **1.1931** (floor 1.1)
* repetition 1 against the best of the kept (the `c,cs,go,mc,rust,zig` job's): 0.996x to 1.016x, median 1.001x -- which is why it is dropped
  * phase `all`: 0.996x to 1.002x, median 1.0x (run first in each repetition, so it pays the cold pages)
  * phase `mix`: 1.0x to 1.001x, median 1.001x
  * phase `primes`: 1.002x to 1.016x, median 1.003x
  * phase `fib`: 0.999x to 1.001x, median 1.0x
* every repetition of every row printed the workload's recorded answer: yes
