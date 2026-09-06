# Round 2: the scripting runtimes, Node and axum

The second HTTP round of `bench/`: the same contract as round 1 (`GET /` -> `200`,
`Content-Type: text/plain`, `Content-Length: 13`, body `hello, world\n`), the same harness shape,
eight more servers. These are the SOURCES; the write-up (`RESULTS.md`) does not exist yet -- see
[`../README.md`](../README.md) § Round 2 -- and the soak (`../README.md` § C) is where they are
first measured next to round 1's servers.

| server | source | shape | run as |
|---|---|---|---|
| `node-single` | `node/single.js` | `http.createServer`, one process, one event-loop thread | `node node/single.js PORT` |
| `node-cluster` | `node/cluster.js` | `cluster`: the primary forks one worker per core (`os.availableParallelism()`), a shared listening socket; SIGTERM reaps the workers | `node node/cluster.js PORT` |
| `rust-axum` | `axum/src/main.rs`, `axum/Cargo.toml` | axum 0.8 on the tokio multi-thread runtime (`Cargo.lock` pins the tree; `cargo build --release --locked`) | `axum/target/release/axum-hello PORT` |
| `py-stdlib` | `py/stdlib.py` | stdlib `http.server` on `ThreadingHTTPServer`, a thread per connection, HTTP/1.1 keep-alive | `python3 py/stdlib.py PORT` |
| `py-uvicorn` | `py/asgi.py` | a 7-line ASGI app under uvicorn | `cd py && python3 -m uvicorn asgi:app --host 127.0.0.1 --port PORT --log-level warning` |
| `rb-webrick` | `rb/webrick.rb` | stdlib WEBrick, a thread per connection | `ruby rb/webrick.rb PORT` |
| `rb-puma` | `rb/config.ru` | a Rack 3 app under Puma | `cd rb && puma -b tcp://127.0.0.1:PORT config.ru` |
| `php-builtin` | `php/index.php` | PHP's built-in server, one process, one request at a time; `default_charset` cleared so the content type is exactly `text/plain` | `cd php && php -S 127.0.0.1:PORT index.php` |

`bench.py`, `facts.sh` and `smoke.sh` are round 1's harness with this server table (`bench.py`
expects `bin/<server>` wrappers, one-line shell scripts that `exec` the commands above; they are
machine-local and not checked in). `facts.sh` uses `otool`/`stat -f` and is macOS-only, like
round 1's.

No `bin/`, `logs/`, `target/` or `node_modules/` is versioned. `bench/soak/build.sh` and
`bench/soak/soak.py` carry the build and run commands for the workflow.
