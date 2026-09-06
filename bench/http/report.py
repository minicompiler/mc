#!/usr/bin/env python3
"""results.json + logs -> RESULTS.md (tables) and the enriched results.json"""
import json, os, re, subprocess
os.chdir(os.path.dirname(os.path.abspath(__file__)))
R = json.load(open("results.json"))
ORDER = ["mc-serial", "mc-fork1", "mc-forkka", "c-serial", "go-nethttp", "rust-threads", "zig-threads", "cs-jit", "cs-aot"]
MODEL = {
 "mc-serial":    "mc, examples/api shape: 1 process, 1 thread, one connection at a time, no keep-alive (Connection: close)",
 "mc-fork1":     "mc, registry (mcweb) shape: parent accepts, fork() per connection, child answers ONE request and _exit()s (Connection: close), waitpid(WNOHANG) reap, <= 64 live workers",
 "mc-forkka":    "mc, fork() per connection with keep-alive: child loops over requests until the client closes; same parent as fork1",
 "c-serial":     "C raw sockets: 1 process, 1 thread, one connection at a time, no keep-alive (the mc-serial shape)",
 "go-nethttp":   "Go net/http: goroutine per connection, keep-alive, GOMAXPROCS=10",
 "rust-threads": "Rust std::net blocking, one OS thread per connection, keep-alive, no crates",
 "zig-threads":  "Zig 0.16 std.Io.net (Threaded Io), one OS thread per connection, keep-alive",
 "cs-jit":       "C# ASP.NET Core minimal API on Kestrel, `dotnet cs.dll` (JIT, shared runtime), thread pool + async I/O, keep-alive",
 "cs-aot":       "C# same program published NativeAOT (-p:PublishAot=true), Kestrel, thread pool + async I/O, keep-alive",
}
COMPILE = {
 "mc-serial":    ("../../build/mc1 --exe mc/serial.mc -o bin/mc-serial", "logs/compile-mc-serial.log"),
 "mc-fork1":     ("../../build/mc1 --exe mc/fork1.mc -o bin/mc-fork1", "logs/compile-mc-fork1.log"),
 "mc-forkka":    ("../../build/mc1 --exe mc/forkka.mc -o bin/mc-forkka", "logs/compile-mc-forkka.log"),
 "c-serial":     ("clang -O2 -o bin/c-serial c/serial.c", "logs/compile-c.log"),
 "go-nethttp":   ("go build -o bin/go-nethttp .", "logs/compile-go.log"),
 "rust-threads": ("rustc -O -o bin/rust-threads rust/main.rs", "logs/compile-rust.log"),
 "zig-threads":  ("zig build-exe main.zig -O ReleaseFast -femit-bin=../bin/zig-threads", "logs/compile-zig.log"),
 "cs-jit":       ("dotnet publish -c Release -o bin/cs-jit", "logs/compile-cs-jit.log"),
 "cs-aot":       ("LIBRARY_PATH=/opt/homebrew/opt/openssl@3/lib:/opt/homebrew/opt/brotli/lib dotnet publish -c Release -r osx-arm64 -p:PublishAot=true -o bin/cs-aot", "logs/compile-cs-aot4.log"),
}
def real(log):
    m = re.search(r"^real\s+([\d.]+)", open(log).read(), re.M); return float(m.group(1)) if m else None
facts = {}
for line in subprocess.run(["sh", "facts.sh"], capture_output=True, text=True).stdout.splitlines():
    f = line.split("|")
    if len(f) == 5: facts[f[0]] = {"src": f[1], "lines": int(f[2]), "size": int(f[3]), "libs": f[4].strip()}
RUNTIME = {
 "mc-serial": "none (libSystem only)", "mc-fork1": "none (libSystem only)", "mc-forkka": "none (libSystem only)",
 "c-serial": "none (libSystem only)", "go-nethttp": "Go runtime, statically linked into the binary",
 "rust-threads": "Rust std, statically linked (libSystem only)", "zig-threads": "Zig std, static (libSystem only)",
 "cs-jit": ".NET 10 CLR + ASP.NET Core shared framework, loaded at run time (106 MiB under libexec/shared)",
 "cs-aot": "NativeAOT: runtime + GC + Kestrel compiled into the binary; dylibs: libssl/libcrypto (Homebrew), brotli, ICU, Swift/Foundation",
}
def f(v, fmt="{:.0f}"):
    return "-" if v is None else fmt.format(v)
def table(cfg, tool):
    rows = []
    if tool == "ab":
        hdr = "| server | req/s | mean ms | p50 ms | p99 ms | failed | non-2xx | peak RSS parent KiB | peak RSS group KiB | CPU s (life) | mean %CPU (life) | ps peak %CPU group | threads (peak) | procs (peak) | CPU ms / 1k req |"
        rows.append(hdr); rows.append("|" + "---|" * (hdr.count("|") - 1))
        for s in ORDER:
            b = R.get(s, {}).get(cfg, {}).get("best")
            if not b:
                err = (R.get(s, {}).get(cfg, {}).get("runs") or [{}])[0].get("error", "no data")
                rows.append(f"| {s} | FAILED: {err} |" + " |" * 13); continue
            a, sm = b["ab"], b["sampler"]
            cpu1k = None if b['cpu_s_per_1k_req'] is None else b['cpu_s_per_1k_req'] * 1000
            rows.append(f"| {s} | {f(a['rps'],'{:.0f}')} | {f(a['mean_ms'],'{:.3f}')} | {f(a['p50_ms'])} | {f(a['p99_ms'])} | {a['failed']} | {a['non2xx']} | "
                        f"{sm['peak_parent_rss_kib']} | {sm['peak_group_rss_kib']} | {b['cpu_total_s']:.2f} | {f(b['rusage_mean_pcpu_over_life'])} | "
                        f"{sm['ps_peak_group_pcpu']:.0f} | {sm['peak_threads_parent']} | {sm['peak_processes'] - 1} | {f(cpu1k, '{:.1f}')} |")
    else:
        hdr = "| server | req/s | mean ms | p50 ms | p99 ms | success rate | 200s | errors | peak RSS group KiB | ps peak %CPU group |"
        rows.append(hdr); rows.append("|" + "---|" * (hdr.count("|") - 1))
        for s in ORDER:
            o = R.get(s, {}).get(cfg, {}).get("oha") or {}
            if "rps" not in o: rows.append(f"| {s} | {o.get('error', 'no data')} |" + " |" * 8); continue
            sm = o.get("sampler", {})
            rows.append(f"| {s} | {o['rps']:.0f} | {o['mean_ms']:.3f} | {o['p50_ms']:.2f} | {o['p99_ms']:.2f} | {o['success_rate']:.4f} | {(o.get('status') or {}).get('200', 0)} | "
                        f"{json.dumps(o.get('errors') or {})} | {sm.get('peak_group_rss_kib', '-')} | {sm.get('ps_peak_group_pcpu', 0):.0f} |")
    return "\n".join(rows)

def runs_table(cfg):
    rows = ["| server | run 1 req/s | run 2 req/s | run 3 req/s | best | startup ms (run 1/2/3) | TIME_WAIT before runs |", "|---|---|---|---|---|---|---|"]
    for s in ORDER:
        rs = R.get(s, {}).get(cfg, {}).get("runs") or []
        rps = [f(r.get("ab", {}).get("rps"), "{:.0f}") if "ab" in r else "ERR" for r in rs]
        st = "/".join(f(r.get("startup_s", None) and r["startup_s"] * 1000, "{:.0f}") for r in rs)
        tw = "/".join(str(r.get("time_wait_before", "-")) for r in rs)
        rows.append(f"| {s} | " + " | ".join(rps + ["-"] * (3 - len(rps))) + f" | {max([x for x in rps if x not in ('-','ERR')], key=float, default='-')} | {st} | {tw} |")
    return "\n".join(rows)

facts_rows = ["| server | concurrency model | source lines | binary bytes | compile command | compile s (`time -p` real; 0.00 = under 10 ms) | runtime linked |", "|---|---|---|---|---|---|---|"]
for s in ORDER:
    fa = facts.get(s, {}); c, log = COMPILE[s]
    facts_rows.append(f"| {s} | {MODEL[s]} | {fa.get('lines','-')} ({fa.get('src','')}) | {fa.get('size','-')} | `{c}` | {f(real(log), '{:.2f}')} | {RUNTIME[s]} |")

env = subprocess.run(["sh", "-c", "sw_vers -productVersion; sysctl -n hw.model hw.ncpu hw.memsize; ab -V | head -1; oha --version; go version; zig version; rustc --version; dotnet --version; clang --version | head -1; ../../build/mc1 --version; ulimit -n; sysctl net.inet.ip.portrange.first net.inet.ip.portrange.last net.inet.tcp.msl kern.ipc.somaxconn"], capture_output=True, text=True).stdout
contract = subprocess.run(["sh", "-c", "for s in " + " ".join(ORDER) + "; do echo \"$s: $(tr -d '\\r' < logs/contract-$s.txt | sort | tr '\\n' '|')\"; done; for s in " + " ".join(ORDER) + "; do tr -d '\\r' < logs/contract-$s.txt | sort | md5; done | sort -u | wc -l"], capture_output=True, text=True).stdout

md = f"""# Minimal HTTP server: mc vs Go vs Zig vs Rust vs C# vs C (macOS/aarch64)

Measurement only. Host: Apple M4 (Mac16,12), 10 cores, 16 GiB, macOS 26.6.2. Load generator and
server on the same machine over 127.0.0.1, so the generator competes for the same cores.

## Environment
```
{env.strip()}
```
`ulimit -n` = 1048576. No sysctl was changed (none of them can be without sudo). The two that
bound a no-keep-alive run: ephemeral ports 49152..65535 (16384) and `net.inet.tcp.msl` 15000 ms
(TIME_WAIT = 30 s). macOS recycles a TIME_WAIT 4-tuple against a higher ISN, so `ab -c 1 -n 50000`
completes with 0 failures even at 14.8k conn/s (probe: `bin/c-serial`, 50000/50000, 3.372 s), and
none of the 54 `ab` runs in the tables failed a request; `oha` did hit `Can't assign requested
address (os error 49)` in the first pass (note 4). The harness waits for TIME_WAIT to drain (< 2000 sockets, at most 32 s) before
every run so each run starts from the same state (`time_wait_before` in results.json).

## Contract
`GET /` -> `HTTP/1.1 200 OK`, `Content-Type: text/plain`, `Content-Length: 13`, body `hello, world\\n`.
Every server was started, hit three times with `curl -si`, and the three outputs compared with `cmp`
(identical for all nine -- `logs/curl-<server>-{{1,2,3}}.txt`). Across servers the status line, the two
contract headers and the body are identical (`logs/contract-*.txt`, sorted):
```
{contract.strip()}
```
(the last line is the number of DISTINCT sorted contracts: 1). Full headers differ: the raw servers
(mc, C, Rust, Zig) send exactly the three headers (the no-keep-alive ones add `Connection: close`);
Go adds `Date`; Kestrel adds `Date` and `Server: Kestrel`.

## The servers
{chr(10).join(facts_rows)}

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
{table("ka64", "ab")}

For the three `Connection: close` servers (mc-serial, mc-fork1, c-serial) `-k` changes nothing on the
wire: ab reconnects for every request (`Keep-Alive requests: 0` in their ab logs).

## `ab -c 1 -n 50000` (no keep-alive, 1 connection) -- best of 3
{table("c1", "ab")}

## oha `-c 64 -z 5s` (keep-alive)
{table("ka64", "oha")}

## oha `-c 1 --disable-keepalive -z 5s`
{table("c1", "oha")}

## Per-run req/s, startup time
### ka64
{runs_table("ka64")}
### c1
{runs_table("c1")}

## Notes and failures (verbatim where they happened)
{open("logs/notes.md").read() if os.path.exists("logs/notes.md") else ""}
"""
open("RESULTS.md", "w").write(md)
R["_facts"] = facts; R["_compile"] = {s: {"cmd": c, "real_s": real(l)} for s, (c, l) in COMPILE.items()}; R["_model"] = MODEL; R["_runtime"] = RUNTIME
json.dump(R, open("results.json", "w"), indent=1)
print("wrote RESULTS.md")
