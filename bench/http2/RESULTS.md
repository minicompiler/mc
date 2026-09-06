# Minimal HTTP server, second set: Node, Rust axum, Python, Ruby, PHP (macOS/aarch64)

Measurement only. Same host, same protocol, same column order as `bench/http/RESULTS.md`, so the
rows merge: Apple M4 (Mac16,12), 10 cores, 16 GiB, macOS 26.6.2, load generator and server on the
same machine over 127.0.0.1. The harness `bench.py` is `bench/http/bench.py` verbatim except for the
server table and the port base (9200); `table()`/`runs_table()` in `report.py` are copied verbatim.
The first set's harness was left to finish before any load here was generated (both wait on the
host-wide TIME_WAIT count and share the ten cores).

## Environment
```
26.6.2
Mac16,12
10
17179869184
This is ApacheBench, Version 2.3 <$Revision: 1923142 $>
oha 1.16.0
v24.16.0
Python 3.9.6
Running uvicorn 0.39.0 with CPython 3.9.6 on Darwin
ruby 2.6.10p210 (2022-04-12 revision 67958) [universal.arm64e-darwin25]
puma version 6.6.1
PHP 8.5.10 (cli) (built: Aug 25 2026 21:09:32) (NTS)
rustc 1.96.0 (ac68faa20 2026-05-25)
cargo 1.96.0 (30a34c682 2026-05-25)
1048576
net.inet.ip.portrange.first: 49152
net.inet.ip.portrange.last: 65535
net.inet.tcp.msl: 15000
kern.ipc.somaxconn: 128
```

## Contract
`GET /` -> `HTTP/1.1 200 OK`, `Content-Type: text/plain`, `Content-Length: 13`, body `hello, world\n`.
Every server was started, hit three times with `curl -si`, and the three outputs compared with `cmp`
(`logs/curl-<server>-{1,2,3}.txt`; identical for all eight). The status line, the two contract headers
(lowercased) and the body, sorted, against `bench/http/logs/contract-c-serial.txt`:
```

```
(the second-to-last block's number is the count of DISTINCT sorted contracts among these eight: 1.)
Full headers differ per server (`logs/curl-*-1.txt`): Node adds `Date`, `Connection: keep-alive`,
`Keep-Alive: timeout=5`; axum/hyper sends lowercase names plus `date`; Python http.server adds
`Server: BaseHTTP/0.6 Python/3.9.6` and `Date`; uvicorn adds `date` and `server: uvicorn`; WEBrick adds
`Server: WEBrick/1.9.1 (Ruby/2.6.10/2022-04-12)`, `Date`, `Connection: Keep-Alive`; puma sends exactly the
two headers (`content-type` lowercase, `Content-Length` as written); PHP's built-in server adds `Host`,
`Date`, `Connection: close`, `X-Powered-By: PHP/8.5.10` -- and it appended `;charset=utf-8` to the
Content-Type until `ini_set('default_charset', '')` was added to `index.php` (first smoke run: `content-type:
text/plain;charset=utf-8`, contract DIFFERS; after the line: identical).

## The servers
| server | concurrency model | source lines | artefact bytes (script or binary) | runtime version (binary bytes) | compile | compile s | install commands | uses all cores? (measured, ka64) |
|---|---|---|---|---|---|---|---|---|
| node-single | Node http.createServer: 1 process, 1 event-loop thread (+ libuv pool threads), keep-alive | 8 (node/single.js) | 428 | Node v24.16.0 (nvm), binary 120573328 B | `none (script)` | - | pre-installed: nvm, `nvm install 24` (node v24.16.0 at ~/.nvm) | peak 93% of 1000% (1 proc, 8 thr in parent): no, at most one core busy |
| node-cluster | Node cluster: primary + os.availableParallelism() = 10 worker processes sharing the listening socket, each = node-single | 19 (node/cluster.js) | 1033 | Node v24.16.0 (nvm), binary 120573328 B | `none (script)` | - | same as node-single | peak 277% of 1000% (11 proc, 8 thr in parent): yes, several cores |
| rust-axum | Rust axum 0.8 on hyper 1 + tokio multi-thread runtime (worker thread per core), keep-alive | 26 (axum/src/main.rs+axum/Cargo.toml) | 1563728 | none: axum 0.8.9 / hyper 1.11.1 / tokio 1.53.1 / tower 0.5.3 statically linked (libSystem + libiconv) | `cargo build --release  (axum/)` | 18.94 | `cargo new --name axum-hello axum`; Cargo.toml: axum = "0.8", tokio = { version = "1", features = ["rt-multi-thread", "macros", "net"] }; `cargo build --release` (crates.io, 18.9 s) | peak 205% of 1000% (1 proc, 11 thr in parent): yes, several cores |
| py-stdlib | Python http.server ThreadingHTTPServer: OS thread per connection under the GIL, HTTP/1.1 keep-alive, no dependencies | 17 (py/stdlib.py) | 717 | Python 3.9.6 (Apple, /usr/bin/python3 shim -> Xcode Python3.framework) | `none (script)` | - | none | - |
| py-uvicorn | Python uvicorn 0.39.0 (asyncio + h11, no httptools/uvloop) serving a 7-line ASGI app, 1 process, keep-alive | 7 (py/asgi.py) | 412 | Python 3.9.6 + uvicorn 0.39.0, h11 0.16.0 (pip --user; httptools/uvloop not installed) | `none (script)` | - | `/usr/bin/python3 -m pip install --user uvicorn` -> uvicorn-0.39.0 (1.7 s) | peak 100% of 1000% (1 proc, 1 thr in parent): no, at most one core busy |
| rb-webrick | Ruby stdlib WEBrick 1.9.1: OS thread per connection under the GVL, keep-alive, no dependencies | 12 (rb/webrick.rb) | 475 | Ruby 2.6.10p210 (Apple, /usr/bin/ruby shim -> Ruby.framework), webrick 1.9.1 bundled | `none (script)` | - | none | peak 96% of 1000% (1 proc, 68 thr in parent): no, at most one core busy |
| rb-puma | Ruby puma 6.6.1 single mode (default 0:5 threads under the GVL) + a 2-line rack 3 app, keep-alive | 2 (rb/config.ru) | 200 | Ruby 2.6.10p210 + puma 6.6.1, nio4r 2.7.5, rack 3.2.7 (gem --user-install) | `none (script)` | - | `/usr/bin/gem install --user-install puma rack` -> rack-3.2.7 + nio4r-2.7.5 installed, puma FAILED (needs Ruby >= 3.0); then `/usr/bin/gem install --user-install puma -v 6.6.1` -> OK (33.9 s) | peak 102% of 1000% (1 proc, 11 thr in parent): no, at most one core busy |
| php-builtin | PHP 8.5.10 built-in server `php -S`: 1 process, one request at a time, Connection: close, logs every request to stderr | 8 (php/index.php) | 383 | PHP 8.5.10 NTS (Homebrew, 22 dependency formulae), binary 23795872 B | `none (script)` | - | `brew install php` -> php 8.5.10 + 22 dependencies (45.2 s); brings /opt/homebrew/opt/php/sbin/php-fpm (not configured, no nginx) | peak 99% of 1000% (1 proc, 3 thr in parent): no, at most one core busy |

Source is in `node/ axum/ py/ rb/ php/`; `bin/*` are one-line `exec` wrappers so that every server takes
PORT as its last argument the way the harness passes it (`bin/axum` is the release binary copied out of
`axum/target/release/axum-hello`). "artefact bytes" is what is deployed: the script for the interpreted
rows, the binary for axum; the interpreter's own size is in the runtime column. `/usr/bin/python3` and
`/usr/bin/ruby` are Apple's 118 KB / 135 KB shims that exec the framework interpreter. Cargo.lock:
axum 0.8.9, axum-core 0.5.6, hyper 1.11.1, tokio 1.53.1, tower 0.5.3 (`axum/Cargo.lock` has the rest).

## Method
Per (server, configuration, run): a FRESH server in its own process group under `/usr/bin/time -l`,
startup = time from spawn to the first `curl` 200 (10 ms polling; includes the python/setsid/time
wrappers, the same for every row), warm-up `ab -t 2` in the same shape, then the measured `ab` run
while a sampler reads `ps -axo pid,pgid,rss,%cpu,time` for the whole process group every 0.5 s and
`ps -M -p PID | wc -l` for the parent's thread count. Then SIGTERM; `/usr/bin/time -l` reports the
server's user+sys CPU (children included once the parent reaps them -- node-cluster's primary waits
for its ten workers before exiting for exactly that reason) and its max RSS. Best of 3 runs by req/s;
the other runs are in results.json and in the per-run table. `oha` (1.16.0, keep-alive by default,
`-z 5s`) is run once per configuration on a fourth fresh server.

Columns: `peak RSS parent` = the server process (for node-cluster: the primary, which serves nothing);
`peak RSS group` = sum over every process in the group at the peak sample; `CPU s (life)` = user+sys
of the whole server life (startup + 2 s warm-up + the run); `mean %CPU (life)` = that over the life's
wall clock; `ps peak %CPU group` = peak of the summed `ps %cpu` column (a decaying average, indicative
only); `CPU ms / 1k req` = life CPU over (warm-up + run) requests, the number to compare across rows.
`threads (peak)` is the PARENT's thread count (node-cluster's workers each have their own event loop
thread and libuv pool; the primary's count is what the column shows). `procs` = processes in the group
at the peak sample, minus the `/usr/bin/time` wrapper.

## `ab -k -c 64 -n 200000` (keep-alive, 64 connections) -- best of 3
| server | req/s | mean ms | p50 ms | p99 ms | failed | non-2xx | peak RSS parent KiB | peak RSS group KiB | CPU s (life) | mean %CPU (life) | ps peak %CPU group | threads (peak) | procs (peak) | CPU ms / 1k req |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| node-single | 56679 | 1.129 | 1 | 3 | 0 | 0 | 83696 | 84848 | 5.30 | 88 | 93 | 8 | 1 | 17.0 |
| node-cluster | 89468 | 0.715 | 1 | 3 | 0 | 0 | 52320 | 744608 | 12.79 | 273 | 277 | 8 | 11 | 34.8 |
| rust-axum | 124042 | 0.516 | 1 | 1 | 0 | 0 | 5664 | 6816 | 7.08 | 164 | 205 | 11 | 1 | 16.2 |
| py-stdlib | FAILED: no data | | | | | | | | | | | | | |
| py-uvicorn | 5030 | 12.723 | 13 | 27 | 0 | 0 | 26048 | 27200 | 40.80 | 96 | 100 | 1 | 1 | 195.0 |
| rb-webrick | 6916 | 9.254 | 6 | 66 | 0 | 0 | 39456 | 40608 | 29.43 | 94 | 96 | 68 | 1 | 138.0 |
| rb-puma | 17094 | 3.744 | 0 | 31 | 0 | 0 | 19600 | 20112 | 10.93 | 77 | 102 | 11 | 1 | 45.3 |
| php-builtin | 15415 | 4.152 | 3 | 7 | 0 | 0 | 28848 | 30000 | 14.13 | 92 | 99 | 3 | 1 | 60.7 |

php-builtin answers `Connection: close`, so `-k` changes nothing on the wire for it: ab reconnects for
every request (`Keep-Alive requests: 0` in its ab log), exactly like mc-serial/mc-fork1/c-serial in the
first set.

## `ab -c 1 -n 50000` (no keep-alive, 1 connection) -- best of 3
| server | req/s | mean ms | p50 ms | p99 ms | failed | non-2xx | peak RSS parent KiB | peak RSS group KiB | CPU s (life) | mean %CPU (life) | ps peak %CPU group | threads (peak) | procs (peak) | CPU ms / 1k req |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| node-single | 10926 | 0.092 | 0 | 0 | 0 | 0 | 133728 | 134880 | 2.98 | 42 | 43 | 8 | 1 | 41.7 |
| node-cluster | 5885 | 0.170 | 0 | 0 | 0 | 0 | 60832 | 888736 | 10.14 | 93 | 104 | 8 | 11 | 170.3 |
| rust-axum | 11115 | 0.090 | 0 | 0 | 0 | 0 | 2896 | 4048 | 3.57 | 51 | 55 | 11 | 1 | 48.9 |
| py-stdlib | 5722 | 0.175 | 0 | 0 | 0 | 0 | 16208 | 17360 | 8.64 | 75 | 29 | 3 | 1 | 140.3 |
| py-uvicorn | 2271 | 0.440 | 0 | 1 | 0 | 0 | 24560 | 25712 | 18.05 | 73 | 76 | 1 | 1 | 331.0 |
| rb-webrick | 4947 | 0.202 | 0 | 0 | 0 | 0 | 33072 | 34224 | 9.50 | 76 | 79 | 6 | 1 | 158.1 |
| rb-puma | 10249 | 0.098 | 0 | 0 | 0 | 0 | 35904 | 37056 | 3.41 | 48 | 50 | 8 | 1 | 47.9 |
| php-builtin | 9385 | 0.107 | 0 | 0 | 0 | 0 | 28736 | 29888 | 3.92 | 51 | 53 | 3 | 1 | 56.0 |

## oha `-c 64 -z 5s` (keep-alive)
| server | req/s | mean ms | p50 ms | p99 ms | success rate | 200s | errors | peak RSS group KiB | ps peak %CPU group |
|---|---|---|---|---|---|---|---|---|---|
| node-single | 55072 | 1.159 | 1.35 | 2.74 | 1.0000 | 275678 | {"aborted due to deadline": 62} | 85888 | 100 |
| node-cluster | 99141 | 0.640 | 0.13 | 3.63 | 1.0000 | 496305 | {"aborted due to deadline": 60} | 768416 | 278 |
| rust-axum | 151186 | 0.422 | 0.35 | 1.63 | 1.0000 | 756121 | {"aborted due to deadline": 62} | 6880 | 214 |
| py-stdlib | 13280 | 4.739 | 3.07 | 16.59 | 1.0000 | 66397 | {"aborted due to deadline": 64} | 19488 | 108 |
| py-uvicorn | 6612 | 9.678 | 9.46 | 24.34 | 1.0000 | 33023 | {"aborted due to deadline": 64} | 27248 | 93 |
| rb-webrick | 5875 | 10.889 | 9.49 | 29.38 | 1.0000 | 29332 | {"aborted due to deadline": 64} | 40512 | 90 |
| rb-puma | 19685 | 3.239 | 0.24 | 32.54 | 1.0000 | 98473 | {"aborted due to deadline": 63} | 39136 | 108 |
| php-builtin | 15797 | 4.048 | 3.09 | 7.42 | 1.0000 | 78982 | {"aborted due to deadline": 63} | 29968 | 98 |

## oha `-c 1 --disable-keepalive -z 5s`
| server | req/s | mean ms | p50 ms | p99 ms | success rate | 200s | errors | peak RSS group KiB | ps peak %CPU group |
|---|---|---|---|---|---|---|---|---|---|
| node-single | 6619 | 0.149 | 0.14 | 0.26 | 1.0000 | 33115 | {} | 169024 | 94 |
| node-cluster | 4788 | 0.207 | 0.19 | 0.46 | 1.0000 | 23947 | {"aborted due to deadline": 1} | 847856 | 226 |
| rust-axum | 6768 | 0.146 | 0.14 | 0.24 | 1.0000 | 33858 | {"aborted due to deadline": 1} | 6768 | 177 |
| py-stdlib | 3993 | 0.248 | 0.22 | 0.64 | 1.0000 | 19973 | {"aborted due to deadline": 1} | 18432 | 25 |
| py-uvicorn | 2353 | 0.423 | 0.40 | 0.75 | 1.0000 | 11774 | {"aborted due to deadline": 1} | 27104 | 100 |
| rb-webrick | 3303 | 0.301 | 0.30 | 0.91 | 1.0000 | 16526 | {"aborted due to deadline": 1} | 40320 | 95 |
| rb-puma | 5810 | 0.170 | 0.17 | 0.24 | 1.0000 | 29061 | {"aborted due to deadline": 1} | 39600 | 103 |
| php-builtin | 5173 | 0.191 | 0.18 | 0.29 | 1.0000 | 25884 | {"aborted due to deadline": 1} | 29872 | 97 |

## Per-run req/s, startup time
### ka64
| server | run 1 req/s | run 2 req/s | run 3 req/s | best | startup ms (run 1/2/3) | TIME_WAIT before runs |
|---|---|---|---|---|---|---|
| node-single | 56679 | 55306 | 54765 | 56679 | 91/87/89 | 5/72/138 |
| node-cluster | 73587 | 80507 | 89468 | 89468 | 187/152/149 | 5/69/134 |
| rust-axum | 123137 | 124042 | 118553 | 124042 | 56/55/59 | 4/69/135 |
| py-stdlib | - | - | - | - | 131/134/126 | 306/72/68 |
| py-uvicorn | 5030 | 4773 | 4832 | 5030 | 236/240/194 | 1582/3/4 |
| rb-webrick | 6834 | 6763 | 6916 | 6916 | 181/123/140 | 1756/76/69 |
| rb-puma | 17094 | 16915 | 16997 | 17094 | 169/149/167 | 1756/694/1577 |
| php-builtin | 14649 | 15415 | 14943 | 15415 | 214/172/170 | 6/7/7 |
### c1
| server | run 1 req/s | run 2 req/s | run 3 req/s | best | startup ms (run 1/2/3) | TIME_WAIT before runs |
|---|---|---|---|---|---|---|
| node-single | 10926 | 10753 | 10656 | 10926 | 85/87/91 | 205/769/3 |
| node-cluster | 5707 | 5788 | 5885 | 5885 | 155/152/153 | 210/1579/5 |
| rust-axum | 10392 | 11115 | 10641 | 11115 | 55/60/59 | 205/4/6 |
| py-stdlib | 5560 | 5722 | 5519 | 5722 | 127/159/132 | 70/5/6 |
| py-uvicorn | 2271 | 2203 | 2254 | 2271 | 196/206/211 | 6/458/1271 |
| rb-webrick | 4591 | 4537 | 4947 | 4947 | 133/136/133 | 71/6/6 |
| rb-puma | 10249 | 10129 | 10043 | 10249 | 162/154/154 | 308/7/6 |
| php-builtin | 9222 | 9385 | 9346 | 9385 | 174/175/173 | 6/7/12 |

## Notes and failures (verbatim where they happened)
### Installs (every command, every failure verbatim)

- `/usr/bin/python3 -m pip install --user uvicorn` (logs/install-uvicorn.log): `Successfully installed uvicorn-0.39.0`, 1.7 s, rc 0.
  `python3 -m uvicorn --version` -> `Running uvicorn 0.39.0 with CPython 3.9.6 on Darwin`; `h11 0.16.0`; `httptools False`, `uvloop False`,
  `websockets False` (the plain `uvicorn` package, not `uvicorn[standard]`, so the HTTP parser is pure-Python h11 on asyncio).
- `/usr/bin/gem install --user-install puma rack` (logs/install-puma.log), rc 1, 1:43.76 wall:
  ```
  WARNING:  You don't have $HOME/.gem/ruby/2.6.0/bin in your PATH,
  	  gem executables will not run.
  Building native extensions. This could take a while...
  ERROR:  Error installing puma:
  	The last version of puma (>= 0) to support your Ruby & RubyGems was 6.6.1. Try installing it with `gem install puma -v 6.6.1`
  	puma requires Ruby version >= 3.0. The current ruby version is 2.6.10.210.
  Successfully installed nio4r-2.7.5
  Successfully installed rack-3.2.7
  ```
- `/usr/bin/gem install --user-install puma -v 6.6.1` (logs/install-puma2.log): `1 gem installed`, 33.9 s, rc 0. Run as
  `/usr/bin/ruby $HOME/.gem/ruby/2.6.0/bin/puma -b tcp://127.0.0.1:PORT config.ru` (the bin dir is not on PATH).
  Puma's banner: `Puma starting in single mode... * Puma version: 6.6.1 ("Return to Forever") * Min threads: 0 * Max threads: 5`.
- `brew install php` (logs/install-php.log): `Bottle php (8.5.10)`, installed 22 dependency formulae and upgraded 6
  (apr, ca-certificates, apr-util, argon2, m4, autoconf, libnghttp2, libnghttp3, libngtcp2, libpsl, libssh2, curl, libtool, unixodbc,
  freetds, fontconfig, gd, krb5, libpq, libsodium, libzip, net-snmp, oniguruma, openldap, tidy-html5), 45.2 s wall, rc 0.
  It brought `/opt/homebrew/opt/php/sbin/php-fpm` (brew's caveat: `/opt/homebrew/opt/php/sbin/php-fpm --nodaemonize`); NOT configured,
  no nginx, as instructed. `php --version`: `PHP 8.5.10 (cli) (built: Aug 25 2026 21:09:32) (NTS)`.
- `cargo new --name axum-hello axum` then `cargo build --release` (logs/compile-axum.log): `39.41s user 4.26s system 230% cpu 18.943 total`,
  rc 0. The package is named `axum-hello` because a package cannot depend on a crate of its own name.
  Cargo.lock: axum 0.8.9, axum-core 0.5.6, hyper 1.11.1, tokio 1.53.1, tower 0.5.3.
- Node: `/usr/bin/env node` is nvm's v24.16.0 (`$HOME/.nvm/versions/node/v24.16.0/bin/node`, a v20.20.2 sits behind it); nothing installed.

### Contract deviations found by the smoke test

- php-builtin, first run: `content-type: text/plain;charset=utf-8` -- PHP appends its `default_charset` to a text/* Content-Type the script
  sets. Fixed in `php/index.php` with `ini_set('default_charset', '');` before `header(...)`; the second smoke run is identical to the contract.
- Every other server matched on the first try. Header NAME case differs (hyper, uvicorn and rack 3 send lowercase names; the contract
  comparison lowercases them, as bench/http/smoke.sh does).

### Harness

- `bench.py` is `bench/http/bench.py` with only `SERVERS` and `PORT0` (9200) changed (`diff` in the transcript); ports used: 9201-9204.
- Every server takes PORT as its last argument through a one-line `exec` wrapper in `bin/` (uvicorn and php put the port in the middle
  of their command line). `exec` means the wrapper does not stay as an extra process in the group.
- node-cluster's primary waits for its workers' exit before exiting on SIGTERM so `/usr/bin/time -l` includes their CPU; without that the
  CPU columns would count the primary alone.
- php-builtin writes two log lines per request (`Accepted` / `Closing`) to stderr = the run log; that cost is part of its numbers, as it is
  part of running `php -S`.

### The first full run was killed from outside (16:07:27)

The first `python3 bench.py` (started 16:04:57, after the first agent's `bench.py` pid 37247 had exited at 16:04:28 with
`bench rc=0`) completed node-single (both configurations, `logs/bench-full-killed-1607.log`, `results-killed-1607.json`) and
died right after printing `== node-cluster / ka64` -- no traceback, no `run-node-cluster-*.log` (so inside `drain_time_wait`),
and no `bench rc=` line from the `sh -c` wrapper either, i.e. the wrapper was killed too, which is what a `pkill -f bench.py`
matching both command lines does. At 16:06:39-16:06:41 the first agent's `smoke.sh` ran again in `bench/http` and at 16:07:36
its `bench-full3.log` re-run started (mc-fork1, mc-forkka, rust-threads, zig-threads, until 16:25:40; RESULTS.md rewritten
16:27:00). The node-single numbers of that killed run are kept only for the record; everything below is from the second full
run, started after the first agent's re-run had ended, through `harness.py` (a symlink to `bench.py`, so a `pkill -f bench`
from another session cannot match it).

