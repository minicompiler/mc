# Benchmarks

Two measurements, both against real toolchains on the same machine, both against `mc` at
commit `0648e1a` (`build/mc1`, `mc 0.0.0-dev`). Neither runs in `make check`: results depend on
the host's CPU, load and installed toolchain versions, which `make check` must not. A `make
bench` target runs them for a human reading the output, not for CI.

Full write-ups, with every command, every failure hit along the way, and every number:
[`RESULTS.md`](RESULTS.md) (the workload) and [`http/RESULTS.md`](http/RESULTS.md) (the servers).
The narrative version, read in five minutes, is [`docs/comparison.md`](../docs/comparison.md).

## A. The workload benchmark (`mc/ c/ go/ zig/ rust/ cs/`)

One integer program in six languages, same semantics, same three printed numbers, so the
compilers and runtimes can be compared on the same code:

1. 200,000,000 iterations of a wrapping 64-bit LCG plus xorshift mixing, accumulated in a
   wrapping `u64`.
2. Sieve of Eratosthenes over 50,000,000 bytes, counting primes below 50,000,000.
3. Naive recursive `fib(38)`.

Every variant prints the same three numbers (`8128903901837660708 / 3001134 / 39088169`) — the
cross-check that every implementation actually computed the same thing.

### Build and run, per language

Run these from the repository root (or adjust `../../build/mc1` for `mc` if you `cd bench`).

```sh
# mc — no linker, ad-hoc signed in place
build/mc1 --exe bench/mc/bench.mc -o /tmp/bench-mc && /tmp/bench-mc

# C
clang -O2 bench/c/bench.c -o /tmp/bench-c-O2 && /tmp/bench-c-O2
clang -O0 bench/c/bench.c -o /tmp/bench-c-O0 && /tmp/bench-c-O0

# Go
(cd bench/go && go build -o /tmp/bench-go . && /tmp/bench-go)

# Zig
(cd bench/zig && zig build-exe -O ReleaseFast bench.zig -femit-bin=/tmp/bench-zig)
/tmp/bench-zig

# Rust
rustc -C opt-level=3 bench/rust/bench.rs -o /tmp/bench-rust && /tmp/bench-rust

# C#
(cd bench/cs && dotnet build -c Release -o /tmp/bench-cs-build)
dotnet /tmp/bench-cs-build/bench.dll
```

`measure.sh LABEL OUTFILE cmd...` (best of 3 under `/usr/bin/time -l`, wall clock and max RSS) is
the timing harness used for every row of the table in `RESULTS.md`; it takes the command to time
as its remaining arguments, so `sh bench/measure.sh mc /tmp/out.txt build/mc1 --exe
bench/mc/bench.mc -o /tmp/bench-mc` times the `mc` compile itself.

`RESULTS.md` § A is the full table (compile time, compile RSS, binary size, `__text` size, run
time, run RSS, source lines) plus every failure hit getting each toolchain to build this program
(Zig 0.16's API changes, .NET NativeAOT's missing OpenSSL/brotli libraries on macOS, etc. — all
quoted verbatim). § B is toolchain footprint (size on disk, file count, whether a system linker is
needed, self-hosting). § C is `mc`'s own numbers (self-compile time, instruction counts from
`--dump-asm` against `clang -S`). § D is a feature matrix with a documentation citation for every
`mc` cell.

## B. The HTTP benchmark (`http/`)

Nine minimal HTTP servers (`GET /` → `200 text/plain hello, world\n`, contract verified identical
byte for byte across all nine with `curl -si` + `cmp`), three of them in `mc` at three different
concurrency shapes, driven with `ab` (Apache Bench) and `oha` under two load configurations.

| server | source | shape |
|---|---|---|
| `http/mc/serial.mc` + `httpmin.mc` | mc | 1 process, 1 thread, one connection at a time, no keep-alive — the `examples/api` shape |
| `http/mc/fork1.mc` + `httpmin.mc` | mc | `fork()` per connection, child answers ONE request and exits — the registry server's (`mc-registry`) shape |
| `http/mc/forkka.mc` + `httpmin.mc` | mc | `fork()` per connection, child loops over requests with keep-alive until the client closes |
| `http/c/serial.c` | C | raw sockets, the same shape as `mc-serial` |
| `http/go/main.go` | Go | `net/http`, goroutine per connection, keep-alive |
| `http/rust/main.rs` | Rust | `std::net` blocking, one OS thread per connection, keep-alive, no crates |
| `http/zig/main.zig` | Zig 0.16 | `std.Io.net` (Threaded Io), one OS thread per connection, keep-alive |
| `http/cs/Program.cs` | C# | ASP.NET Core minimal API on Kestrel, JIT (shared runtime) and NativeAOT, both measured |

### Build

```sh
# mc
build/mc1 --exe bench/http/mc/serial.mc -o bench/http/bin/mc-serial
build/mc1 --exe bench/http/mc/fork1.mc  -o bench/http/bin/mc-fork1
build/mc1 --exe bench/http/mc/forkka.mc -o bench/http/bin/mc-forkka

# C
clang -O2 -o bench/http/bin/c-serial bench/http/c/serial.c

# Go
(cd bench/http/go && go build -o ../bin/go-nethttp .)

# Rust
rustc -O -o bench/http/bin/rust-threads bench/http/rust/main.rs

# Zig
(cd bench/http/zig && zig build-exe main.zig -O ReleaseFast -femit-bin=../bin/zig-threads)

# C# — JIT and NativeAOT
(cd bench/http/cs && dotnet publish -c Release -o ../bin/cs-jit)
(cd bench/http/cs && dotnet publish -c Release -r osx-arm64 -p:PublishAot=true -o ../bin/cs-aot)
```

### Run

```sh
cd bench/http
python3 bench.py                 # every server, both load configurations, 3 runs each -> results.json
sh facts.sh                      # binary size, source lines, linked libraries per server
python3 report.py                # results.json + facts.sh -> RESULTS.md
sh smoke.sh mc-serial mc-fork1 mc-forkka c-serial go-nethttp rust-threads zig-threads cs-jit cs-aot
```

`bench.py` starts each server fresh, under `/usr/bin/time -l`, in its own process group; measures
startup (first `curl` 200), warms up 2 s, then runs `ab -k -c 64 -n 200000` (keep-alive, 64
connections) and `ab -c 1 -n 50000` (no keep-alive, serial) three times each, keeping the best;
`oha -c 64 -z 5s` and `oha -c 1 --disable-keepalive -z 5s` once each; a 0.5 s `ps` sampler runs the
whole time to track RSS, CPU% and thread/process counts for the whole process group (so a
fork-per-connection server's children are counted).

### The two harness facts to know before re-running this

1. **`ab` speaks HTTP/1.0.** With `-k` it sends `Connection: Keep-Alive`; without it, nothing. A
   server that always answers HTTP/1.1 with no `Connection` header (the naive way to write
   keep-alive) never sees an EOF and `ab` times out after 30 s. The three hand-written keep-alive
   servers here (`mc-forkka`, `rust-threads`, `zig-threads`) negotiate it explicitly: HTTP/1.1
   stays open unless `Connection: close`; HTTP/1.0 closes unless `keep-alive` is requested, and
   then it is echoed back. `oha` speaks HTTP/1.1 and was unaffected either way.
2. **TIME_WAIT must drain between runs.** A closed connection holds its ephemeral port in
   TIME_WAIT for `2 * net.inet.tcp.msl` (30 s on macOS by default); with a small ephemeral range
   (16384 ports here) a `-c 1` no-keep-alive run at ~15k conn/s can exhaust it inside a few
   seconds and the next run starts from a different, unfair socket state. `bench.py` waits for the
   TIME_WAIT count to drop under 2000 (`drain_time_wait`, up to 32 s) before every run so each one
   starts from the same state. No `sysctl` is changed (root only) — the harness works around the
   defaults instead.

Both are explained at length, with the exact error messages hit before they were fixed, in
[`http/RESULTS.md`](http/RESULTS.md) § Notes and failures.

`RESULTS.md` § "The servers" has the exact compile command and measured source-line count per
server; § "Contract" has the byte-for-byte response comparison; § "Method" explains every column
of the result tables (`CPU ms / 1k req` is the number comparable across concurrency models: life
CPU time over total requests served); the four result tables are keep-alive/no-keep-alive under
`ab` and under `oha`; § "Per-run req/s, startup time" has the individual runs behind each "best of
3"; § "Notes and failures" is fourteen numbered, verbatim facts about running this on macOS,
including two harness defects found and fixed mid-run.

## Round 2 (`http2/`, if present)

A second HTTP round widening the comparison to Node.js (single process and `cluster`), Rust
`axum`, Python (stdlib `http.server`, ASGI/uvicorn) and Ruby (`WEBrick`, `rackup`/Puma) may appear
alongside this one, under the same harness and the same load configurations. If `http2/` exists in
this tree, [`http2/RESULTS.md`](http2/RESULTS.md) is its write-up and `docs/comparison.md` § B
includes its rows; if it does not, it had not finished running when this page was written and is
still on the roadmap (`docs/plan.md`).
