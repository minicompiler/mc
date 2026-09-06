# Minimal HTTP server: mc vs Go vs Zig vs Rust vs C# vs C (macOS/aarch64)

Measurement only. Host: Apple M4 (Mac16,12), 10 cores, 16 GiB, macOS 26.6.2. Load generator and
server on the same machine over 127.0.0.1, so the generator competes for the same cores.

## Environment
```
26.6.2
Mac16,12
10
17179869184
This is ApacheBench, Version 2.3 <$Revision: 1923142 $>
oha 1.16.0
go version go1.26.4 darwin/arm64
0.16.0
rustc 1.96.0 (ac68faa20 2026-05-25)
10.0.301
Apple clang version 21.0.0 (clang-2100.1.1.101)
mc 0.0.0-dev
1048576
net.inet.ip.portrange.first: 49152
net.inet.ip.portrange.last: 65535
net.inet.tcp.msl: 15000
kern.ipc.somaxconn: 128
```
`ulimit -n` = 1048576. No sysctl was changed (none of them can be without sudo). The two that
bound a no-keep-alive run: ephemeral ports 49152..65535 (16384) and `net.inet.tcp.msl` 15000 ms
(TIME_WAIT = 30 s). macOS recycles a TIME_WAIT 4-tuple against a higher ISN, so `ab -c 1 -n 50000`
completes with 0 failures even at 14.8k conn/s (probe: `bin/c-serial`, 50000/50000, 3.372 s), and
none of the 54 `ab` runs in the tables failed a request; `oha` did hit `Can't assign requested
address (os error 49)` in the first pass (note 4). The harness waits for TIME_WAIT to drain (< 2000 sockets, at most 32 s) before
every run so each run starts from the same state (`time_wait_before` in results.json).

## Contract
`GET /` -> `HTTP/1.1 200 OK`, `Content-Type: text/plain`, `Content-Length: 13`, body `hello, world\n`.
Every server was started, hit three times with `curl -si`, and the three outputs compared with `cmp`
(identical for all nine -- `logs/curl-<server>-{1,2,3}.txt`). Across servers the status line, the two
contract headers and the body are identical (`logs/contract-*.txt`, sorted):
```
mc-serial: HTTP/1.1 200 OK|content-length: 13|content-type: text/plain|hello, world|
mc-fork1: HTTP/1.1 200 OK|content-length: 13|content-type: text/plain|hello, world|
mc-forkka: HTTP/1.1 200 OK|content-length: 13|content-type: text/plain|hello, world|
c-serial: HTTP/1.1 200 OK|content-length: 13|content-type: text/plain|hello, world|
go-nethttp: HTTP/1.1 200 OK|content-length: 13|content-type: text/plain|hello, world|
rust-threads: HTTP/1.1 200 OK|content-length: 13|content-type: text/plain|hello, world|
zig-threads: HTTP/1.1 200 OK|content-length: 13|content-type: text/plain|hello, world|
cs-jit: HTTP/1.1 200 OK|content-length: 13|content-type: text/plain|hello, world|
cs-aot: HTTP/1.1 200 OK|content-length: 13|content-type: text/plain|hello, world|
       1
```
(the last line is the number of DISTINCT sorted contracts: 1). Full headers differ: the raw servers
(mc, C, Rust, Zig) send exactly the three headers (the no-keep-alive ones add `Connection: close`);
Go adds `Date`; Kestrel adds `Date` and `Server: Kestrel`.

## The servers
| server | concurrency model | source lines | binary bytes | compile command | compile s (`time -p` real; 0.00 = under 10 ms) | runtime linked |
|---|---|---|---|---|---|---|
| mc-serial | mc, examples/api shape: 1 process, 1 thread, one connection at a time, no keep-alive (Connection: close) | 148 (mc/serial.mc+mc/httpmin.mc) | 34182 | `build/mc1 --exe mc/serial.mc -o bin/mc-serial` | 0.00 | none (libSystem only) |
| mc-fork1 | mc, registry (mcweb) shape: parent accepts, fork() per connection, child answers ONE request and _exit()s (Connection: close), waitpid(WNOHANG) reap, <= 64 live workers | 179 (mc/fork1.mc+mc/httpmin.mc) | 34373 | `build/mc1 --exe mc/fork1.mc -o bin/mc-fork1` | 0.00 | none (libSystem only) |
| mc-forkka | mc, fork() per connection with keep-alive: child loops over requests until the client closes; same parent as fork1 | 182 (mc/forkka.mc+mc/httpmin.mc) | 34374 | `build/mc1 --exe mc/forkka.mc -o bin/mc-forkka` | 0.01 | none (libSystem only) |
| c-serial | C raw sockets: 1 process, 1 thread, one connection at a time, no keep-alive (the mc-serial shape) | 47 (c/serial.c) | 34152 | `clang -O2 -o bin/c-serial c/serial.c` | 0.32 | none (libSystem only) |
| go-nethttp | Go net/http: goroutine per connection, keep-alive, GOMAXPROCS=10 | 16 (go/main.go) | 7966914 | `go build -o bin/go-nethttp .` | 6.88 | Go runtime, statically linked into the binary |
| rust-threads | Rust std::net blocking, one OS thread per connection, keep-alive, no crates | 48 (rust/main.rs) | 516192 | `rustc -O -o bin/rust-threads rust/main.rs` | 0.68 | Rust std, statically linked (libSystem only) |
| zig-threads | Zig 0.16 std.Io.net (Threaded Io), one OS thread per connection, keep-alive | 74 (zig/main.zig) | 397368 | `zig build-exe main.zig -O ReleaseFast -femit-bin=../bin/zig-threads` | 6.64 | Zig std, static (libSystem only) |
| cs-jit | C# ASP.NET Core minimal API on Kestrel, `dotnet cs.dll` (JIT, shared runtime), thread pool + async I/O, keep-alive | 22 (cs/Program.cs+cs/cs.csproj) | 6656 | `dotnet publish -c Release -o bin/cs-jit` | 4.78 | .NET 10 CLR + ASP.NET Core shared framework, loaded at run time (106 MiB under libexec/shared) |
| cs-aot | C# same program published NativeAOT (-p:PublishAot=true), Kestrel, thread pool + async I/O, keep-alive | 22 (cs/Program.cs+cs/cs.csproj) | 8772816 | `LIBRARY_PATH=/opt/homebrew/opt/openssl@3/lib:/opt/homebrew/opt/brotli/lib dotnet publish -c Release -r osx-arm64 -p:PublishAot=true -o bin/cs-aot` | 7.92 | NativeAOT: runtime + GC + Kestrel compiled into the binary; dylibs: libssl/libcrypto (Homebrew), brotli, ICU, Swift/Foundation |

Source is in `mc/ c/ go/ rust/ zig/ cs/`. The mc rows include the 129-line `mc/httpmin.mc` (37 of them the HTTP/1.0 keep-alive negotiation added after the first pass, note 1), the
copy of `examples/api/lib/http.mc` reduced to what a GET needs (socket/bind/listen/accept externs,
sockaddr_in by hand, header-end scan, write-all). `build/mc1` compiles them directly with
`--exe`; the `fork`/`_exit`/`waitpid` calls are ordinary libSystem `extern`s (`waitpid` is already
in `lib/sys.mc`; `fork` and `_exit` are declared in the file). `bin/cs-jit/cs` (the apphost) refuses
to start without `DOTNET_ROOT`, so the JIT row is run as `dotnet bin/cs-jit/cs.dll PORT`.

NativeAOT: the first two `dotnet publish -p:PublishAot=true` attempts failed at link time --
`ld: library 'ssl' not found`, then `ld: library 'brotlienc' not found` (the ILCompiler links
`-lssl -lcrypto ... -lbrotlienc` and macOS ships neither). `LIBRARY_PATH` pointing at Homebrew's
openssl@3 and brotli fixed it (7.9 s publish, 8.7 MB binary that dynamically links those Homebrew dylibs).

## Method
Per (server, configuration, run): a FRESH server in its own process group under `/usr/bin/time -l`,
startup = time from spawn to the first `curl` 200 (10 ms polling; includes the python/setsid/time
wrappers, the same for every row), warm-up `ab -t 2` in the same shape, then the measured `ab` run
while a sampler reads `ps -axo pid,pgid,rss,%cpu,time` for the whole process group every 0.5 s and
`ps -M -p PID | wc -l` for the parent's thread count. Then SIGTERM; `/usr/bin/time -l` reports the
server's user+sys CPU (children included once the parent reaps them -- which the fork servers do) and
its max RSS. Best of 3 runs by req/s; the other runs are in results.json and in the per-run table.
`oha` (1.16.0, keep-alive by default, `-z 5s`) is run once per configuration on a fourth fresh server.

Columns: `peak RSS parent` = the server process; `peak RSS group` = sum over every process in the
group at the peak sample (only differs for the fork servers; a child that lives < 0.5 s is mostly
invisible to the sampler). `CPU s (life)` = user+sys of the whole server life (startup + 2 s warm-up +
the run); `mean %CPU (life)` = that over the life's wall clock; `ps peak %CPU group` = peak of the
summed `ps %cpu` column (a decaying average, indicative only); `CPU ms / 1k req` = life CPU over
(warm-up + run) requests, the number to compare across rows. `procs` = processes in the group at
the peak sample, minus the `/usr/bin/time` wrapper.

## `ab -k -c 64 -n 200000` (keep-alive, 64 connections) -- best of 3
| server | req/s | mean ms | p50 ms | p99 ms | failed | non-2xx | peak RSS parent KiB | peak RSS group KiB | CPU s (life) | mean %CPU (life) | ps peak %CPU group | threads (peak) | procs (peak) | CPU ms / 1k req |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| mc-serial | 28578 | 2.239 | 2 | 4 | 0 | 0 | 1328 | 2480 | 2.44 | 26 | 32 | 1 | 1 | 9.6 |
| mc-fork1 | 3892 | 16.444 | 15 | 35 | 0 | 0 | 1312 | 14592 | 70.11 | 130 | 71 | 1 | 57 | 335.5 |
| mc-forkka | 120177 | 0.533 | 1 | 1 | 0 | 0 | 1328 | 66320 | 5.52 | 129 | 152 | 1 | 65 | 12.5 |
| c-serial | 25128 | 2.547 | 2 | 5 | 0 | 0 | 1344 | 2496 | 2.07 | 19 | 24 | 1 | 1 | 8.2 |
| go-nethttp | 103770 | 0.617 | 1 | 2 | 0 | 0 | 21488 | 22640 | 7.68 | 173 | 232 | 15 | 1 | 21.5 |
| rust-threads | 132595 | 0.483 | 1 | 1 | 0 | 0 | 2768 | 3920 | 5.26 | 140 | 148 | 65 | 1 | 11.5 |
| zig-threads | 111900 | 0.572 | 1 | 1 | 0 | 0 | 4272 | 5424 | 5.02 | 115 | 129 | 65 | 1 | 11.5 |
| cs-jit | 112072 | 0.571 | 1 | 2 | 0 | 0 | 117488 | 118640 | 7.50 | 163 | 209 | 48 | 1 | 19.2 |
| cs-aot | 98755 | 0.648 | 1 | 2 | 0 | 0 | 55984 | 57136 | 5.69 | 127 | 143 | 33 | 1 | 14.3 |

For the three `Connection: close` servers (mc-serial, mc-fork1, c-serial) `-k` changes nothing on the
wire: ab reconnects for every request (`Keep-Alive requests: 0` in their ab logs).

## `ab -c 1 -n 50000` (no keep-alive, 1 connection) -- best of 3
| server | req/s | mean ms | p50 ms | p99 ms | failed | non-2xx | peak RSS parent KiB | peak RSS group KiB | CPU s (life) | mean %CPU (life) | ps peak %CPU group | threads (peak) | procs (peak) | CPU ms / 1k req |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| mc-serial | 14713 | 0.068 | 0 | 0 | 0 | 0 | 1328 | 2480 | 1.07 | 18 | 21 | 1 | 1 | 13.9 |
| mc-fork1 | 2359 | 0.424 | 0 | 1 | 0 | 0 | 1312 | 3424 | 18.95 | 80 | 46 | 1 | 7 | 344.9 |
| mc-forkka | 2326 | 0.430 | 0 | 1 | 0 | 0 | 1328 | 3456 | 18.76 | 79 | 45 | 1 | 6 | 342.7 |
| c-serial | 13331 | 0.075 | 0 | 0 | 0 | 0 | 1344 | 2496 | 0.80 | 13 | 17 | 1 | 1 | 11.0 |
| go-nethttp | 9522 | 0.105 | 0 | 0 | 0 | 0 | 18224 | 19376 | 4.32 | 57 | 62 | 7 | 1 | 61.9 |
| rust-threads | 11380 | 0.088 | 0 | 0 | 0 | 0 | 1696 | 2848 | 2.58 | 37 | 15 | 2 | 1 | 35.0 |
| zig-threads | 11091 | 0.090 | 0 | 0 | 0 | 0 | 1680 | 2832 | 3.18 | 45 | 16 | 3 | 1 | 43.3 |
| cs-jit | 9650 | 0.104 | 0 | 0 | 0 | 0 | 185712 | 186880 | 18.40 | 234 | 289 | 34 | 1 | 274.0 |
| cs-aot | 9465 | 0.106 | 0 | 0 | 0 | 0 | 123968 | 125120 | 11.03 | 144 | 164 | 32 | 1 | 159.1 |

## oha `-c 64 -z 5s` (keep-alive)
| server | req/s | mean ms | p50 ms | p99 ms | success rate | 200s | errors | peak RSS group KiB | ps peak %CPU group |
|---|---|---|---|---|---|---|---|---|---|
| mc-serial | 30967 | 2.065 | 1.87 | 4.86 | 1.0000 | 154863 | {"aborted due to deadline": 64} | 2480 | 36 |
| mc-fork1 | 3874 | 16.536 | 15.09 | 38.30 | 1.0000 | 19328 | {"aborted due to deadline": 64} | 3712 | 67 |
| mc-forkka | 106741 | 0.597 | 0.24 | 4.52 | 1.0000 | 534609 | {"aborted due to deadline": 45} | 67424 | 154 |
| c-serial | 19289 | 3.312 | 1.88 | 17.42 | 1.0000 | 96606 | {"aborted due to deadline": 38} | 2496 | 14 |
| go-nethttp | 96171 | 0.663 | 0.30 | 8.67 | 1.0000 | 481474 | {"aborted due to deadline": 39} | 22768 | 220 |
| rust-threads | 171220 | 0.371 | 0.15 | 3.77 | 1.0000 | 856894 | {"aborted due to deadline": 49} | 3904 | 188 |
| zig-threads | 148548 | 0.428 | 0.15 | 4.73 | 1.0000 | 743469 | {"aborted due to deadline": 49} | 5584 | 159 |
| cs-jit | 106425 | 0.600 | 0.55 | 1.48 | 1.0000 | 532560 | {"aborted due to deadline": 58} | 124352 | 177 |
| cs-aot | 121131 | 0.526 | 0.31 | 3.09 | 1.0000 | 606265 | {"aborted due to deadline": 48} | 66816 | 254 |

## oha `-c 1 --disable-keepalive -z 5s`
| server | req/s | mean ms | p50 ms | p99 ms | success rate | 200s | errors | peak RSS group KiB | ps peak %CPU group |
|---|---|---|---|---|---|---|---|---|---|
| mc-serial | 6509 | 0.152 | 0.14 | 0.25 | 1.0000 | 32561 | {"aborted due to deadline": 1} | 2480 | 24 |
| mc-fork1 | 1137 | 0.875 | 0.49 | 7.16 | 1.0000 | 5687 | {"aborted due to deadline": 1} | 3360 | 44 |
| mc-forkka | 1326 | 0.750 | 0.48 | 5.79 | 1.0000 | 6633 | {"aborted due to deadline": 1} | 3456 | 38 |
| c-serial | 5796 | 0.171 | 0.14 | 0.69 | 1.0000 | 28991 | {"aborted due to deadline": 1} | 2496 | 25 |
| go-nethttp | 6905 | 0.143 | 0.14 | 0.23 | 1.0000 | 34545 | {"aborted due to deadline": 1} | 21984 | 186 |
| rust-threads | 5384 | 0.183 | 0.15 | 0.82 | 1.0000 | 26935 | {} | 2864 | 9 |
| zig-threads | 6629 | 0.149 | 0.13 | 0.36 | 1.0000 | 33178 | {"aborted due to deadline": 1} | 3888 | 8 |
| cs-jit | 7455 | 0.133 | 0.12 | 0.37 | 1.0000 | 37305 | {"aborted due to deadline": 1} | 188240 | 235 |
| cs-aot | 7036 | 0.141 | 0.13 | 0.38 | 1.0000 | 35205 | {"aborted due to deadline": 1} | 125872 | 148 |

## Per-run req/s, startup time
### ka64
| server | run 1 req/s | run 2 req/s | run 3 req/s | best | startup ms (run 1/2/3) | TIME_WAIT before runs |
|---|---|---|---|---|---|---|
| mc-serial | 27680 | 28324 | 28578 | 28578 | 38/59/57 | 704/4/7 |
| mc-fork1 | 3892 | 3023 | 3849 | 3892 | 57/64/63 | 1909/1846/299 |
| mc-forkka | 120177 | 119899 | 91188 | 120177 | 59/58/33 | 941/90/155 |
| c-serial | 23472 | 21760 | 25128 | 25128 | 194/55/59 | 1301/36/737 |
| go-nethttp | 103770 | 98078 | 81710 | 103770 | 91/58/49 | 1690/71/135 |
| rust-threads | 132595 | 128915 | 132117 | 132595 | 60/32/34 | 1409/69/134 |
| zig-threads | 111019 | 110851 | 111900 | 111900 | 60/52/58 | 1788/71/137 |
| cs-jit | 97197 | 111425 | 112072 | 112072 | 304/226/224 | 6/70/141 |
| cs-aot | 95718 | 97186 | 98755 | 98755 | 140/110/116 | 4/70/135 |
### c1
| server | run 1 req/s | run 2 req/s | run 3 req/s | best | startup ms (run 1/2/3) | TIME_WAIT before runs |
|---|---|---|---|---|---|---|
| mc-serial | 14063 | 14713 | 13920 | 14713 | 45/36/44 | 4/5/7 |
| mc-fork1 | 1234 | 2214 | 2359 | 2359 | 68/61/53 | 1796/1579/26 |
| mc-forkka | 2041 | 2326 | 2023 | 2326 | 38/66/54 | 231/6/655 |
| c-serial | 4058 | 4710 | 13331 | 13331 | 201/63/66 | 5/194/22 |
| go-nethttp | 9109 | 9077 | 9522 | 9522 | 44/64/65 | 250/72/8 |
| rust-threads | 11258 | 11232 | 11380 | 11380 | 51/57/62 | 222/6/4 |
| zig-threads | 10970 | 11091 | 11078 | 11091 | 33/60/34 | 233/8/1502 |
| cs-jit | 9647 | 8958 | 9650 | 9650 | 247/290/353 | 227/6/7 |
| cs-aot | 9465 | 9325 | 9323 | 9465 | 117/146/143 | 233/3/4 |

## Notes and failures (verbatim where they happened)
1. **`ab` speaks HTTP/1.0.** With `-k` it sends `Connection: Keep-Alive`; without it, nothing.
   The first version of the three hand-written keep-alive servers (mc-forkka, rust-threads,
   zig-threads) answered every request as HTTP/1.1 keep-alive with no `Connection` header, so ab
   waited for an EOF that never came and every run of those three, both configurations, died with
   `apr_pollset_poll: The timeout specified has expired (70007)` after ab's 30 s timeout
   (`logs/ab-mc-forkka-*.txt`, `logs/ab-rust-threads-*.txt`, `logs/ab-zig-threads-*.txt` from the
   first pass are overwritten by the rerun; the first-pass sources are kept as `logs/*.v1`).
   Go's net/http and Kestrel negotiate it: for an HTTP/1.0 request they answer
   `Connection: keep-alive` when asked and close otherwise. The three servers were given the same
   rule (HTTP/1.1: keep open unless `Connection: close`; HTTP/1.0: close unless `keep-alive`, echoed
   back) and rerun; `oha` (HTTP/1.1) had been fine with the first version, which is why its rows for
   those servers are consistent with the rerun. This is the only change made to a server after the
   first pass; `mc-serial`, `mc-fork1` and `c-serial` never took that path (they always close).
2. **Harness defect, fixed before the rerun:** the SIGTERM at the end of a run went to "the first
   process in the group that is not `/usr/bin/time`", which for a fork server could be a worker;
   the parent survived, the 10 s wait expired, the group SIGKILL took `time` with it and the rusage
   line was lost (`cpu=0.00s` in the first-pass log `logs/bench-full2.log` for mc-fork1). The server
   is now identified as `time`'s child. mc-fork1 and mc-forkka were rerun for that reason (plus 1.).
3. **A stray `python3 bench.py` with no arguments** (every server) was found running alongside the
   rerun at 16:04:57 and killed together with the rerun 2.5 minutes later; `results.json` was
   verified unchanged (`logs/results.after-full2.json`) and the rerun restarted at 16:07:36 with no
   other load generator on the machine. Its origin is not known; nothing in the logs was produced by it.
4. **Ephemeral ports.** In the first pass the `c1` oha runs of rust-threads and zig-threads reported
   `Can't assign requested address (os error 49)` (7404 and 8420 errors against ~16300 successes --
   49152..65535 exhausted while the previous connections sit in TIME_WAIT for 30 s); the rerun of the
   same rows, started after a TIME_WAIT drain, had none. The `aborted due to deadline` entries are
   oha's own `-z 5s` cut-off (the requests in flight when the 5 s expire, at most one per connection). The `ab` runs never hit it: macOS recycles a
   TIME_WAIT 4-tuple when the new SYN carries a higher ISN, which is why `ab -c 1 -n 50000`
   completes at 14k conn/s with 0 failures. No sysctl was changed (needs sudo: `net.inet.tcp.msl`,
   `net.inet.ip.portrange.*`). The harness waits for TIME_WAIT < 2000 before each run.
5. **`oha` prints `DNS: failed to load /etc/resolv.conf: failed to parse nameserver address:
   invalid IP address syntax`** before its JSON on this host (an IPv6 scope in resolv.conf); it
   resolves 127.0.0.1 without DNS, the line is stripped before parsing.
6. **`ab`'s `Time per request (mean)` for `-c 64` is per-connection latency** (64 x the
   across-all-connections value). With `-c 1` the two are the same. `ab` prints percentiles in whole
   milliseconds, so p50/p99 of `0` and `1` mean "< 1 ms"; use the oha columns for sub-millisecond latency.
7. **NativeAOT** needed `LIBRARY_PATH=/opt/homebrew/opt/openssl@3/lib:/opt/homebrew/opt/brotli/lib`
   (the ILCompiler's link line has `-lssl -lcrypto -lbrotlienc ...` and macOS ships none of them):
   `ld: library 'ssl' not found` (attempt 1), `ld: library 'brotlienc' not found` (attempt 2, with
   `-p:LinkerArg=-L...`, which is not applied on macOS), success on attempt 3
   (`logs/compile-cs-aot*.log`). The resulting binary dynamically links the Homebrew dylibs.
8. **`bin/cs-jit/cs` (the apphost) does not start** without `DOTNET_ROOT` (`You must install .NET to
   run this application ... /usr/local/share/dotnet` -- Homebrew's install is under
   `/opt/homebrew/opt/dotnet/libexec`), so the JIT row runs as `dotnet bin/cs-jit/cs.dll PORT`.
9. **Zig 0.16** replaced `std.process.args()`/`std.net` with the `std.Io` interface (`main(init:
   std.process.Init)`, `init.io`, `Io.net.IpAddress.listen`, `Stream.reader/writer`); the first
   draft against the 0.14 API failed with `root source file struct 'process' has no member named
   'args'`. `std.http.Server` was not used: the raw accept loop is the shape that matches the
   Rust row.
10. **mc compile errors on the way** (all in the benchmark's own files, the compiler was not
    touched): `while`/`++` need `#include <prelude>`; a `while` body must be a block (`expected {`);
    an 8 KiB local array is `local array too large`, so the request buffer is a global; a function
    must be defined before its first call.
11. **mc-serial and mc-fork1 were measured with the first-pass binaries** (34038 / 34245 bytes);
    the rebuilt ones (34182 / 34373) only add the unused `http_keep`/`http_respond` functions of
    `httpmin.mc`, the code they execute is byte for byte the same. The sizes table shows the rebuilt files.
12. **What the sampler cannot see:** a mc-fork1 worker lives for one request (~0.3 ms), so `peak RSS
    group` for that row is the few workers alive at a 0.5 s sample, not the sum over 200000 forks; the
    `CPU s (life)` column does include them (the parent reaps every worker, so their rusage is
    accumulated into what `/usr/bin/time -l` reports). `peak RSS parent` for mc-fork1/mc-forkka is
    the accepting parent alone (1.3 MiB).
13. **Run-to-run variance.** Best of 3 is reported; the per-run table shows the spread. Three runs
    stand out: c-serial c1 runs 1-2 (4058, 4710 req/s) against run 3 (13331, in line with mc-serial's
    14k for the identical shape), mc-forkka ka64 run 3 (91188 vs ~120000) and go-nethttp ka64 run 3
    (81710 vs ~104000). Nothing in the logs explains them (`time_wait_before` is small in every case);
    the load generator shares the ten cores with the server and with whatever else the desktop was
    doing. Repeat the outlier rows before reading anything into a difference under ~20%.
14. **`ps -M` thread counts** are sampled at 0.5 s; `65` for rust/zig is 1 acceptor + 64 connection
    threads; Go's 15-21 are runtime Ms (GOMAXPROCS=10 plus netpoller/sysmon/idle); Kestrel's 31-48
    are the .NET thread pool plus its I/O and timer threads. mc's rows are 1 thread per process.

