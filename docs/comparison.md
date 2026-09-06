# comparison.md — how `mc` compares, measured against C, Go, Zig, Rust and C# (2026-09-06)

Two benchmarks, run on one Mac, comparing `mc` against five real toolchains on the same code: a
CPU-bound integer workload compiled and run by all six, and 17 minimal HTTP servers under load
(nine in the first set: mc, C, Go, Zig, Rust threads, C#; eight more in a second set: Node,
Rust axum, Python, Ruby, PHP). Every command, every number and every failure hit along the way
is in [`../bench/RESULTS.md`](../bench/RESULTS.md), [`../bench/http/RESULTS.md`](../bench/http/RESULTS.md)
and [`../bench/http2/RESULTS.md`](../bench/http2/RESULTS.md); this page is the five-minute version.
The benchmark sources are in [`../bench/`](../bench/README.md) and build with the same `mc` this
repository builds — nothing here is a projection.

## Conditions

| | |
|---|---|
| Hardware | Apple M4, Mac16,12, 10 cores, 16 GiB RAM |
| OS | macOS 26.6.2 (Darwin 25.6.0) |
| Go | go1.26.4 darwin/arm64 |
| Zig | 0.16.0 |
| Rust | rustc 1.96.0 (ac68faa20 2026-05-25) |
| .NET | SDK 10.0.301, runtime 10.0.9 |
| C | Apple clang 21.0.0 (clang-2100.1.1.101) |
| mc | commit `0648e1a` (tag `v0.15.13`), `build/mc1`, `mc 0.0.0-dev` |
| Node (2nd HTTP set) | v24.16.0 (nvm) |
| Rust axum (2nd HTTP set) | axum 0.8.9, hyper 1.11.1, tokio 1.53.1 (`cargo` 1.96.0, same rustc as above) |
| Python (2nd HTTP set) | 3.9.6 (Apple `/usr/bin/python3` shim), uvicorn 0.39.0 (h11 0.16.0, no httptools/uvloop) |
| Ruby (2nd HTTP set) | 2.6.10p210 (Apple `/usr/bin/ruby` shim), puma 6.6.1 |
| PHP (2nd HTTP set) | 8.5.10 (cli, NTS, Homebrew) |
| Load generators | ApacheBench (`ab`) 2.3, `oha` 1.16.0 |
| Method | best of 3 timed runs, `/usr/bin/time -l` for wall clock and max RSS, a warm-up run before each measured one, `ps` sampled every 0.5 s for the HTTP servers, `ulimit -n` raised, TIME_WAIT drained between HTTP runs |
| Date | 2026-09-06 |

The HTTP tables below merge two measurement sets on the same host, back to back: the first (mc, C, Go, Zig, Rust threads, C#) ran to completion before the second (Node single/cluster, Rust axum, Python, Ruby, PHP) was started, so neither harness's load competed with the other's for the ten cores. Every command and number for the second set is in [`../bench/http2/RESULTS.md`](../bench/http2/RESULTS.md).

**Read this with two things in mind.**

1. **One host, shared with other work.** The load generator and the server run on the same ten
   cores over loopback, and `make check` runs were competing for the machine while some of this
   was measured. `../bench/http/RESULTS.md` § Notes 13 names three runs whose numbers swing
   ~20% run-to-run with nothing in the logs to explain it beyond that contention (`c-serial` on
   the serial no-keep-alive configuration, `mc-forkka` and `go-nethttp` on one of their three
   keep-alive runs). Best of 3 is reported everywhere; the spread is in the raw results.
2. **The `mc` binary that ran the workload benchmark reports the tree it was built from as
   `e5a1643`.** That commit is real (an M24-era point, before the M31–M47 work this repository has
   since landed) but it is NOT what produced the measured binary: rebuilding `build/mc1` from
   `e5a1643` gives a 755,840-byte executable, while the workload table's own numbers
   (33,461-byte output, 1,181,184-byte compiler) match a build from the CURRENT `main`
   (`0648e1a` / `v0.15.13`) exactly. The tree label in the raw file is stale — most likely copied
   from an older session's context — and this page cites the verified commit instead. It does not
   change any number: `mc`'s codegen for plain integer/array/function code has been byte-identical
   across that range on purpose (the M17 walker/machine split's acceptance test is exactly "arm64
   objects unchanged byte for byte after the refactor," and every milestone since has its own
   inertness proof for programs that do not use what it adds — [`../CLAUDE.md`](../CLAUDE.md) § State
   records each one). The HTTP benchmark's servers were built the same afternoon, after `0648e1a`
   landed, with no tree annotation to double-check.
3. **The reproducible cell — a fixed VPS, one Docker container per row, pinned toolchain
   versions, `--cpus 1 --memory 512m` — is on the roadmap** (see § Where to improve) and will
   replace these numbers as the reference measurement. Until then, treat this page as one host's
   honest snapshot, not a controlled benchmark suite.

## Where mc stands

### The workload: one integer program, six languages

200,000,000 iterations of a wrapping 64-bit LCG + xorshift mix, a sieve of Eratosthenes over
50,000,000 bytes, and naive recursive `fib(38)`. Every variant printed the same three numbers
(cross-checked, `../bench/RESULTS.md` § A).

| Language / variant | Compile (best of 3) | Binary (bytes) | `__text` (bytes) | Run (best of 3) | Run RSS | Source lines |
|---|---|---|---|---|---|---|
| **mc** `--exe` | **4.1 ms** | 33,461 | 1,480 | 1.09 s | 51.3 MB | 76 |
| C `clang -O2` | 0.11 s | 33,464 | 1,320 | **0.49 s** | 51.4 MB | 50 |
| C `clang -O0` | 0.09 s | 33,512 | 740 | 1.02 s | 51.4 MB | 50 |
| Go `go build` | 0.08 s warm (5.94 s cold) | 2,492,482 | 649,316 | 0.55 s | 54.8 MB | 55 |
| Zig `-O ReleaseFast` | 9.80 s | 396,304 | 238,804 | 0.50 s | 51.6 MB | 57 |
| Rust `-O3` | 0.19 s | 466,320 | 216,908 | **0.47 s** | 51.6 MB | 59 |
| C# NativeAOT | 3.23 s cold publish | 1,020,584 | 282,276 | 0.62 s | 57.5 MB | 58 |
| C# JIT | 0.54 s (`dotnet build`) | 5,120 + 78 MB shared runtime | n/a (IL) | 0.59 s | 94.6 MB | 58 |

(Full table with every variant, every failure and the exact build command: `../bench/RESULTS.md` § A.)

### Toolchain footprint

| Toolchain | Size on disk | Files | System linker needed | Self-hosting |
|---|---|---|---|---|
| **mc** | **1.2 MB** (one binary, `build/mc1`) | **1** | No (`--exe` writes and ad-hoc signs Mach-O itself) | Yes — self-hosted, 2,848-line C23 seed only for bootstrap |
| Go | 258 MB | 14,954 | No (internal linker) | Yes, since 1.5 |
| Zig | 246 MB | 19,548 | No (bundled `zig ld`) | Yes, since 0.11 |
| Rust | 1.7 GB (+233 MB `~/.cargo`) | 54,532 | Yes (`cc`) | Yes (LLVM backend) |
| .NET | 666 MB | 4,738 | JIT no; NativeAOT yes | Roslyn in C#, CoreCLR in C++ |
| clang | 1.0 GB | 5,109 | Yes (Apple `ld`) | Yes (C++) |

(Full table with version strings and exact measurement commands: `../bench/RESULTS.md` § B.)

### The HTTP servers

Seventeen servers, same contract (`GET /` → `200 text/plain hello, world\n`, verified byte-identical
across all of them, first set and second set each checked on their own), driven with
`ab -k -c 64 -n 200000` (64 keep-alive connections) and `ab -c 1 -n 50000` (one connection, no
keep-alive), plus `oha` once per configuration. `CPU ms / 1k req` is the number comparable across
concurrency models: total server-life CPU time (user+sys, children included) divided by requests
served. The second set (Node single-process and `cluster`, Rust `axum`, Python stdlib and uvicorn,
Ruby WEBrick and Puma, PHP's built-in server) is marked with its runtime version in the server
column; its full method, environment and per-run numbers are in
[`../bench/http2/RESULTS.md`](../bench/http2/RESULTS.md).

**Keep-alive, 64 connections — best of 3:**

| server | req/s | mean ms | peak RSS (group) | CPU ms / 1k req |
|---|---|---|---|---|
| mc-serial (1 proc, 1 conn at a time, no keep-alive) | 28,578 | 2.24 | 2.4 MB | 9.6 |
| **mc-forkka** (fork per connection, keep-alive) | **120,177** | 0.53 | 66.3 MB | 12.5 |
| mc-fork1 (fork per REQUEST — the registry server's old shape) | 3,892 | 16.44 | 14.6 MB | 335.5 |
| c-serial | 25,128 | 2.55 | 2.4 MB | 8.2 |
| go-nethttp | 103,770 | 0.62 | 22.6 MB | 21.5 |
| rust-threads | 132,595 | 0.48 | 3.8 MB | **11.5** |
| zig-threads | 111,900 | 0.57 | 5.4 MB | **11.5** |
| cs-jit (Kestrel, JIT) | 112,072 | 0.57 | 118.6 MB | 19.2 |
| cs-aot (Kestrel, NativeAOT) | 98,755 | 0.65 | 57.1 MB | 14.3 |
| node-single (Node 24) | 56,679 | 1.13 | 84.8 MB | 17.0 |
| node-cluster (Node 24) | 89,468 | 0.72 | 744.6 MB | 34.8 |
| rust-axum (Rust 1.96, axum 0.8) | 124,042 | 0.52 | 6.8 MB | 16.2 |
| py-stdlib (Python 3.9) | FAILED — `ab -k` hung, 0 requests completed in warm-up on all 3 runs | - | - | - |
| py-uvicorn (Python 3.9, uvicorn 0.39) | 5,030 | 12.72 | 27.2 MB | 195.0 |
| rb-webrick (Ruby 2.6) | 6,916 | 9.25 | 40.6 MB | 138.0 |
| rb-puma (Ruby 2.6, puma 6.6) | 17,094 | 3.74 | 20.1 MB | 45.3 |
| php-builtin (PHP 8.5) | 15,415 | 4.15 | 30.0 MB | 60.7 |

**No keep-alive, 1 connection — best of 3:**

| server | req/s | CPU ms / 1k req |
|---|---|---|
| mc-serial | 14,713 | 13.9 |
| c-serial | 13,331 | 11.0 |
| rust-threads | 11,380 | 35.0 |
| zig-threads | 11,091 | 43.3 |
| go-nethttp | 9,522 | 61.9 |
| cs-aot | 9,465 | 159.1 |
| cs-jit | 9,650 | 274.0 |
| mc-fork1 | 2,359 | 344.9 |
| mc-forkka | 2,326 | 342.7 |
| rust-axum (Rust 1.96, axum 0.8) | 11,115 | 48.9 |
| node-single (Node 24) | 10,926 | 41.7 |
| rb-puma (Ruby 2.6, puma 6.6) | 10,249 | 47.9 |
| php-builtin (PHP 8.5) | 9,385 | 56.0 |
| py-stdlib (Python 3.9) | 5,722 | 140.3 |
| node-cluster (Node 24) | 5,885 | 170.3 |
| rb-webrick (Ruby 2.6) | 4,947 | 158.1 |
| py-uvicorn (Python 3.9, uvicorn 0.39) | 2,271 | 331.0 |

**`oha -c 64 -z 5s` (keep-alive), one run:**

| server | req/s | mean ms | peak RSS (group) | ps peak %CPU (group) |
|---|---|---|---|---|
| mc-serial | 30,967 | 2.07 | 2.5 MB | 36 |
| **mc-forkka** | **106,741** | 0.60 | 67.4 MB | 154 |
| mc-fork1 | 3,874 | 16.54 | 3.7 MB | 67 |
| c-serial | 19,289 | 3.31 | 2.5 MB | 14 |
| go-nethttp | 96,171 | 0.66 | 22.8 MB | 220 |
| rust-threads | 171,220 | 0.37 | 3.9 MB | 188 |
| zig-threads | 148,548 | 0.43 | 5.6 MB | 159 |
| cs-jit | 106,425 | 0.60 | 124.4 MB | 177 |
| cs-aot | 121,131 | 0.53 | 66.8 MB | 254 |
| node-single (Node 24) | 55,072 | 1.16 | 85.9 MB | 100 |
| node-cluster (Node 24) | 99,141 | 0.64 | 768.4 MB | 278 |
| rust-axum (Rust 1.96, axum 0.8) | 151,186 | 0.42 | 6.9 MB | 214 |
| py-stdlib (Python 3.9) | 13,280 | 4.74 | 19.5 MB | 108 |
| py-uvicorn (Python 3.9, uvicorn 0.39) | 6,612 | 9.68 | 27.2 MB | 93 |
| rb-webrick (Ruby 2.6) | 5,875 | 10.89 | 40.5 MB | 90 |
| rb-puma (Ruby 2.6, puma 6.6) | 19,685 | 3.24 | 39.1 MB | 108 |
| php-builtin (PHP 8.5) | 15,797 | 4.05 | 30.0 MB | 98 |

py-stdlib's `oha` keep-alive run succeeded (13,280 req/s) even though its `ab -k` run did not —
the failure is specific to that combination of `ab` and `ThreadingHTTPServer`, not to keep-alive
connections in general; its no-keep-alive number (5,722 req/s, above) is unaffected either way.

(Both `ab` tables in full, plus the `oha` `-c 1 --disable-keepalive` run and the per-run spread:
[`../bench/http/RESULTS.md`](../bench/http/RESULTS.md) and
[`../bench/http2/RESULTS.md`](../bench/http2/RESULTS.md).)

## Reading the numbers

**Compile time, binary size and toolchain size are where `mc` leads everything measured here.**
4.1 ms to build the workload (`clang -O2`'s own compile is 27x slower at 0.11 s; Zig's optimized
build is 2,400x slower at 9.8 s), a 33 KB executable matching `clang -O2`'s within 3 bytes with no
linker involved, and a 1.2 MB single-file toolchain against Rust's 1.7 GB or clang's 1.0 GB. No
`.dll`/`.so` to find at run time, no SDK to install, no linker to configure — `build/mc1` alone
compiles and signs a working macOS executable.

**Generated code is at `clang -O0` level, and 2.2x behind the optimized compilers, on this
workload.** `mc`'s run time (1.09 s) sits between `clang -O0` (1.02 s) and `clang -O2` (0.49 s);
Zig, Rust and Go's optimized builds land in the same 0.47–0.55 s band as `clang -O2`. This is the
one structural gap the numbers show, and it has a name: `mc` does constant folding and nothing
else ([`reference/machine.md`](reference/machine.md), [`core-language.md`](core-language.md)).
There is no register allocator — expression depths 0–6 map to fixed registers `x9`–`x15` and a
7th-deep value spills to the frame immediately, whether or not a register is free elsewhere
([`reference/objects.md`](reference/objects.md) § 4) — and no peephole, inlining or dead-code
elimination ([`surface.md`](surface.md)). The M17 walker/machine split
([`reference/machine.md`](reference/machine.md)) is exactly where a register allocator would live:
it already separates the target-independent walker (which knows liveness per expression, since it
assigns and frees depths) from the machine that encodes instructions, so an allocator would be a
new consumer of information the walker already computes, not a rewrite of the pipeline.

**In the HTTP benchmark, the concurrency MODEL decides more than the language does.** `mc-forkka`
(fork per connection, the process kept alive across a connection's requests) is in the same band
as Rust/Zig/Go/Kestrel — 120k req/s, and at 12.5 CPU ms per 1,000 requests it is the second-lowest
CPU cost measured, behind only Rust and Zig's raw thread-per-connection servers (11.5). The serial
shape (`mc-serial`, one connection at a time, no keep-alive) is at parity with the equivalent C
server (28,578 vs 25,128 req/s, 9.6 vs 8.2 CPU ms/1k — close enough to be inside this host's
~20% run-to-run variance). The shape to retire is fork-per-**request** (`mc-fork1`): it is the
`examples/api` / early registry-server pattern, and at 3,892 req/s with 335 CPU ms per 1,000
requests it costs 28x the CPU of the keep-alive shape for a fifth of the throughput — the `fork()`
and `waitpid()` overhead dominates once every request pays for a fresh process. Memory tells the
same story from a different angle: the `mc-forkka` PARENT holds 1.3 MB RSS the whole time; the 65
worker processes it fans out to under load sum to 66 MB, against Rust's 3.9 MB (65 threads in one
process), Go's 22 MB, or C#'s 118 MB (Kestrel/JIT) — a process-per-connection design pays in
per-process baseline (stack, TLS, libSystem's own footprint) what a thread-per-connection or
event-loop design does not.

**The second HTTP set lands where each runtime's model predicts, one order of magnitude apart in
two steps.** Node's single-process event loop (`node-single`) reaches 47% of mc-forkka's
keep-alive throughput (56,679 vs 120,177 req/s, `ab -k`) at 1.4x the CPU per request (17.0 vs
12.5 CPU ms/1k req) — one JS thread against mc-forkka's process-per-connection fan-out. Node's
`cluster` mode (11 processes: 1 primary + `os.availableParallelism()` = 10 workers sharing the
listening socket) closes most of that gap to 75% of the throughput (89,468 req/s) but at 727 MB
of combined RSS across those 11 processes and 2.8x the CPU (34.8 ms/1k) — the primary alone stays
under 52 MB, the ten workers are where the memory and the CPU go. Rust's `axum` (0.8, on hyper 1
and a multi-thread tokio runtime) lands inside the same 120k–133k req/s band as `mc-forkka` and
`rust-threads` (124,042 req/s), between Node's CPU cost and mc's own (16.2 vs 17.0 and 12.5 ms/1k)
— a general-purpose async framework paying a little more than a hand-rolled thread-per-connection
loop, and about the same as `mc`'s own fork-per-connection shape. The four servers with no
compiled runtime underneath the request path — `py-uvicorn`, `rb-webrick`, `rb-puma`,
`php-builtin` — sit an order of magnitude below that band (5,030–17,094 req/s) at 3 to 16x the
CPU per request (45.3–195.0 ms/1k against mc-forkka's 12.5). `py-stdlib`'s `ab -k` run failed
outright — 0 requests completed in warm-up on all three attempts, the same `ThreadingHTTPServer`
that its own no-keep-alive run (5,722 req/s) and its `oha` keep-alive run (13,280 req/s) both
completed without incident, so the failure is specific to that combination of `ab` and the
server, not to keep-alive itself (`../bench/http2/RESULTS.md` § Notes).

## What is not measured, and is not comparable

- **No floating-point workload.** `<float>` is a library, not core (`f32`/`f64` via `type_new` +
  a derived machine, [`surface.md`](surface.md) § M24); neither benchmark here exercises it.
- **No GC-pressure test.** `mc` allocates nothing itself (no core allocator); Go and C# pay a GC
  under sustained allocation that a pointer-free integer workload never triggers.
- **No I/O-bound test beyond the HTTP servers**, and those are all `GET /` returning a fixed
  13-byte body — no database, no disk, no JSON parsing.
- **One host, one architecture (Apple M4 / arm64).** `mc` also targets `x86_64` (macOS via
  Rosetta is not tested; Linux/Windows x86_64 are supported build targets — `machine_x86_64.mc` —
  but not benchmarked here) and RISC-V/AVR bare metal, none measured in this pass.
- **The second HTTP set (Node single-process and `cluster`, Rust `axum`, Python, Ruby, PHP)
  is now merged into the tables above and read in § Reading the numbers.** Its full method,
  environment and every command run are in
  [`../bench/http2/RESULTS.md`](../bench/http2/RESULTS.md); the sources are in
  [`../bench/http2/`](../bench/http2/README.md).
- **Nothing here ran for longer than five seconds.** What a server's memory does over an HOUR
  under a steady load — the drift the public Rust/Go/Zig comparisons argue about — is a separate
  measurement with a separate protocol: the soak workflow (`.github/workflows/bench-soak.yml`,
  described in [`../bench/README.md`](../bench/README.md) § "C. The soak") runs every server
  above plus round 2's, one GitHub Actions runner each, under a fixed 3000 req/s for 60 minutes,
  pinned to two cores, sampling the whole process tree every 5 s, and reports RSS at 1/10/30/60
  min, the fitted slope over the last fifty minutes, CPU ms per 1k requests and p50/p99/p99.9
  with time-series charts. No numbers from it are on this page yet: they are added once a full
  hour has run.

### Feature matrix

Facts only — cited to the reference docs for `mc`, from general knowledge of each language's
current version elsewhere (`../bench/RESULTS.md` § D has the full row-by-row citations; this is
the summary).

| Feature | mc | C | Go | Zig | Rust | C# |
|---|---|---|---|---|---|---|
| Generics | No in the core; taught by `examples/lang` from the surface | No | Yes | Yes (comptime) | Yes (monomorphized) | Yes (runtime, CLR) |
| Structs | No `struct`; `#define` offsets + accessors, or `class`/`interface` taught (`examples/api`) | Yes | Yes | Yes | Yes | Yes |
| Floats | None in the core; `<float>` is the first library primitive | Yes | Yes | Yes (f16..f128) | Yes | Yes |
| Strings | Literals only, no string type | char arrays + libc | Built-in `string` | `[]const u8` | `String`/`&str` | `System.String` |
| Error handling | Diagnostic + exit code; no language construct | Return codes/errno | Multiple returns, `error`, panic | `!T`, `try`/`catch` | `Result`/`?`, panics | Exceptions |
| Memory safety | Unchecked; raw `ld*`/`st*` on `uptr` | Unchecked | GC + bounds checks | Checked in Debug/ReleaseSafe | Ownership/borrowing | GC + bounds checks |
| GC | None; reference counting taught by `examples/lang` | None | Tracing, concurrent | None (explicit allocators) | None (RAII) | Tracing, generational |
| Concurrency | None in the core; taught by `examples/conc` | pthreads (library) | Goroutines, channels (built in) | std.Thread, atomics | Threads, atomics, async | Threads, Task/async |
| Optimizer | Constant folding only | LLVM -O0..-O3 | SSA, inlining, DCE | LLVM or self-hosted | LLVM -O0..-O3 | RyuJIT tiered + PGO |
| Register allocation | None (fixed depth scheme) | Yes | Yes | Yes | Yes | Yes (RyuJIT LSRA) |
| Cross targets shipped | macOS/Linux/Windows arm64+x86_64, RISC-V and AVR bare metal | Many (LLVM) | Many (`GOOS`/`GOARCH`) | Many (LLVM) | Many (rustup) | osx/linux/win RIDs |
| Package manager | Yes (`mc pkg`, `[deps]`, `mc.lock`, MVS) | None | Go modules | `zig fetch` | cargo | NuGet |
| LSP / Debugger | Planned (M28/M30), not shipped | clangd, DWARF/lldb | gopls, DWARF/delve | zls (3rd party), DWARF | rust-analyzer, DWARF/lldb | Roslyn LSP, PDB |
| Reproducible builds | Byte-identical fixed point, SHA-256 goldens | Mostly, with effort | Yes by design | Yes (content-addressed) | Yes in practice | Deterministic IL |
| Compiler extensibility | Four tiers in the language: directives, `pass()`/`backend()`/`machine()`, six word registrations + seven hooks, `intrinsic` | None (preprocessor) | None (`go generate`, external) | `comptime` (nearest analogue) | proc-macros (nearest analogue) | Source generators (nearest analogue) |

## Where to improve

Ranked by what it buys, with every number here labelled as an ESTIMATE — none of this is
implemented, and each links to the milestone that would carry it in
[`plan.md`](plan.md).

1. **A register allocator, a peephole and small-function inlining.** The single biggest lever on
   the one gap this page shows: `mc` at `clang -O0` level today, 2.2x behind `clang -O2` on this
   workload. Estimated shape: allocate the callee-saved registers to locals and live-across-call
   values (the walker already tracks per-block liveness through its depth stack, since it must
   know when a depth is free), a peephole over the `Ins` buffer for store-then-immediately-load and
   redundant register moves, and constant propagation plus inlining of small leaf functions as
   `pass()`-level AST rewrites before `gen_walk`. **Estimated target: within 1.3x of `clang -O2` on
   this workload** — a guess pending real measurement, not a promise. See `plan.md` § M49.
2. **A reproducible bench cell.** A `bench/Dockerfile` with every toolchain pinned to an exact
   version, run on a fixed VPS with `--cpus 1 --memory 512m` per container, results committed as
   dated JSON so a regression shows up in `git blame` instead of a chat log. Removes both
   caveats in the § Conditions block above. See `plan.md` § M50.
3. **A bundled `<http>` library with the fork-per-connection-with-keep-alive shape** (`mc-forkka`
   above) as an `#include <http>` away, with an event-loop shape to follow once one exists, so a
   program gets the 120k-req/s band by including a library instead of hand-rolling sockets — and
   so the registry server itself (`minicompiler/mc-registry`) can move off its current
   fork-per-request shape onto it. **The registry server's own migration is
   `minicompiler/mc-registry`'s work, not this repository's** — this repository only owns the
   library. See `plan.md` § M51.
4. **The LSP, the debugger, and the rest of the feature matrix's blanks** the plan already names:
   `mc lsp` (M28), DWARF + `lldb` (M30), and the register-allocator work above is itself a
   prerequisite this page did not know it had until it was measured.
