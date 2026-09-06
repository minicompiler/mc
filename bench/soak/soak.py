#!/usr/bin/env python3
"""soak.py SERVER [options] -- the 60-minute soak of one HTTP server.

Starts the server (built by build.sh, or interpreted) in its own session, pinned
to `--server-cpus`; verifies the contract with `curl -si`; drives it with oha at a
FIXED request rate for `--minutes`, pinned to `--load-cpus`; and every
`--every` seconds samples the server's whole process tree (RSS, CPU time,
threads, processes; the parent's VmRSS/VmHWM; /proc/loadavg) into
out/SERVER/samples.csv. oha's JSON goes to out/SERVER/oha.json and the conditions
(toolchain versions, command lines verbatim, host facts) to out/SERVER/facts.json.

Exit status is non-zero only when the server died, did not answer, or failed the
contract. Python 3 standard library only. Linux is the target (/proc); on
macOS the sampler falls back to ps so the script can be smoke-tested there.
"""
import argparse, datetime, json, os, platform, re, shutil, signal, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
BIN = os.path.join(HERE, "bin")
H1 = os.path.join(ROOT, "bench", "http")
H2 = os.path.join(ROOT, "bench", "http2")

# name -> (argv with {port}, cwd). A trailing {port} is the convention of bench/http.
SERVERS = {
    "mc-serial":    (["bin/mc-serial", "{port}"], HERE),
    "mc-fork1":     (["bin/mc-fork1", "{port}"], HERE),
    "mc-forkka":    (["bin/mc-forkka", "{port}"], HERE),
    "c-serial":     (["bin/c-serial", "{port}"], HERE),
    "go-nethttp":   (["bin/go-nethttp", "{port}"], HERE),
    "rust-threads": (["bin/rust-threads", "{port}"], HERE),
    "rust-axum":    (["bin/rust-axum", "{port}"], HERE),
    "zig-threads":  (["bin/zig-threads", "{port}"], HERE),
    "cs-jit":       (["dotnet", "bin/cs-jit/cs.dll", "{port}"], HERE),
    "cs-aot":       (["bin/cs-aot/cs", "{port}"], HERE),
    "node-single":  (["node", os.path.join(H2, "node", "single.js"), "{port}"], HERE),
    "node-cluster": (["node", os.path.join(H2, "node", "cluster.js"), "{port}"], HERE),
    "py-stdlib":    (["python3", os.path.join(H2, "py", "stdlib.py"), "{port}"], HERE),
    "py-uvicorn":   (["python3", "-m", "uvicorn", "asgi:app", "--host", "127.0.0.1", "--port", "{port}",
                      "--log-level", "warning"], os.path.join(H2, "py")),
    "rb-webrick":   (["ruby", os.path.join(H2, "rb", "webrick.rb"), "{port}"], HERE),
    "rb-puma":      (["puma", "-b", "tcp://127.0.0.1:{port}", "config.ru"], os.path.join(H2, "rb")),
    "php-builtin":  (["php", "-S", "127.0.0.1:{port}", "index.php"], os.path.join(H2, "php")),
}
DEFAULT = ["mc-serial", "mc-forkka", "c-serial", "go-nethttp", "rust-threads", "rust-axum", "zig-threads",
           "cs-jit", "cs-aot", "node-single", "node-cluster", "py-uvicorn", "rb-puma", "php-builtin"]
OPTIONAL = ["mc-fork1", "py-stdlib", "rb-webrick"]
SOURCES = {
    "mc-serial": ["bench/http/mc/serial.mc", "bench/http/mc/httpmin.mc", "bench/http/mc/linux/netsys.mc"],
    "mc-fork1": ["bench/http/mc/fork1.mc", "bench/http/mc/httpmin.mc", "bench/http/mc/linux/netsys.mc"],
    "mc-forkka": ["bench/http/mc/forkka.mc", "bench/http/mc/httpmin.mc", "bench/http/mc/linux/netsys.mc"],
    "c-serial": ["bench/http/c/serial.c"], "go-nethttp": ["bench/http/go/main.go"],
    "rust-threads": ["bench/http/rust/main.rs"], "rust-axum": ["bench/http2/axum/src/main.rs", "bench/http2/axum/Cargo.toml"],
    "zig-threads": ["bench/http/zig/main.zig"], "cs-jit": ["bench/http/cs/Program.cs"], "cs-aot": ["bench/http/cs/Program.cs"],
    "node-single": ["bench/http2/node/single.js"], "node-cluster": ["bench/http2/node/cluster.js"],
    "py-stdlib": ["bench/http2/py/stdlib.py"], "py-uvicorn": ["bench/http2/py/asgi.py"],
    "rb-webrick": ["bench/http2/rb/webrick.rb"], "rb-puma": ["bench/http2/rb/config.ru"], "php-builtin": ["bench/http2/php/index.php"],
}
# the toolchain behind each server: commands whose first line of output is the version
VERSION_CMDS = {
    "mc-": [["mc", "--version"]], "c-serial": [["clang", "--version"]], "go-": [["go", "version"]],
    "rust-threads": [["rustc", "--version"]], "rust-axum": [["rustc", "--version"], ["cargo", "--version"]],
    "zig-": [["zig", "version"]], "cs-": [["dotnet", "--version"]], "node-": [["node", "--version"]],
    "py-stdlib": [["python3", "--version"]], "py-uvicorn": [["python3", "--version"], ["python3", "-m", "uvicorn", "--version"]],
    "rb-": [["ruby", "--version"], ["puma", "--version"]], "php-": [["php", "--version"]],
}
CLK = os.sysconf("SC_CLK_TCK") if hasattr(os, "sysconf") else 100
PAGE = os.sysconf("SC_PAGE_SIZE") if hasattr(os, "sysconf") else 4096
LINUX = sys.platform.startswith("linux")


def sh(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, **kw)
    except FileNotFoundError as e:
        return subprocess.CompletedProcess(cmd, 127, "", str(e))


def first_line(cmd):
    r = sh(cmd)
    out = (r.stdout or r.stderr).strip().splitlines()
    return out[0] if out else f"({cmd[0]}: rc {r.returncode})"


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return ""


# ---- the process tree, from /proc (Linux) or ps (macOS smoke tests) -------------------------
def proc_table_linux():
    """pid -> (ppid, pgrp, utime+stime seconds, cutime+cstime seconds, threads, rss KiB)"""
    t = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        s = read(f"/proc/{name}/stat")
        if not s:
            continue
        rp = s.rfind(")")
        f = s[rp + 2:].split()
        # after comm: state(0) ppid(1) pgrp(2) ... utime(11) stime(12) cutime(13) cstime(14) ... threads(17) ... rss(21)
        try:
            t[int(name)] = (int(f[1]), int(f[2]), (int(f[11]) + int(f[12])) / CLK, (int(f[13]) + int(f[14])) / CLK,
                            int(f[17]), int(f[21]) * PAGE // 1024)
        except (IndexError, ValueError):
            pass
    return t


def proc_table_ps():
    t = {}
    r = sh(["ps", "-axo", "pid=,ppid=,pgid=,rss=,time="])
    for line in r.stdout.splitlines():
        f = line.split()
        if len(f) < 5:
            continue
        tm = f[4].split(":")
        secs = 0.0
        for x in tm:
            secs = secs * 60 + float(x)
        t[int(f[0])] = (int(f[1]), int(f[2]), secs, 0.0, 1, int(f[3]))
    return t


def proc_table():
    return proc_table_linux() if LINUX else proc_table_ps()


def tree(table, root):
    """the server's process group plus every descendant of the root pid"""
    pgid = table[root][1] if root in table else root
    members = {p for p, v in table.items() if v[1] == pgid}
    members.add(root)
    frontier = list(members)
    while frontier:
        p = frontier.pop()
        for q, v in table.items():
            if v[0] == p and q not in members:
                members.add(q)
                frontier.append(q)
    return members


def status_field(pid, key):
    m = re.search(rf"^{key}:\s+(\d+)", read(f"/proc/{pid}/status"), re.M)
    return int(m.group(1)) if m else 0


def sample(root):
    table = proc_table()
    if root not in table:
        return None
    members = tree(table, root)
    rss = sum(table[p][5] for p in members)
    cpu_live = sum(table[p][2] for p in members)
    cpu_reaped = table[root][3]          # children the parent has already waited for (fork servers)
    threads = sum(table[p][4] for p in members)
    if not LINUX:
        threads = sum(max(0, len(sh(["ps", "-M", "-p", str(p)]).stdout.splitlines()) - 1) for p in members)
    hwm = status_field(root, "VmHWM") if LINUX else 0
    prss = status_field(root, "VmRSS") if LINUX else table[root][5]
    load = read("/proc/loadavg").split()
    return {"rss_group_kib": rss, "rss_parent_kib": prss, "hwm_parent_kib": hwm,
            "cpu_time_group_s": cpu_live + cpu_reaped, "cpu_time_reaped_s": cpu_reaped,
            "threads": threads, "procs": len(members), "loadavg1": float(load[0]) if load else 0.0}


# ---- the server ------------------------------------------------------------------------------
def wait_200(port, timeout):
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        r = sh(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "1", f"http://127.0.0.1:{port}/"])
        if r.stdout.strip() == "200":
            return time.monotonic() - t0
        time.sleep(0.05)
    return None


def contract(port):
    """status line, content-type, content-length: 13, body hello, world\\n -- the bench/http contract"""
    # bytes, not text: text mode would turn the CRLFs into LFs before they are checked
    r = subprocess.run(["curl", "-si", "--max-time", "5", f"http://127.0.0.1:{port}/"], capture_output=True)
    txt = r.stdout.decode("latin-1")
    head, _, body = txt.partition("\r\n\r\n")
    lines = head.split("\r\n")
    problems = []
    if not lines or not re.match(r"^HTTP/1\.[01] 200 OK$", lines[0]):
        problems.append(f"status line: {lines[0] if lines else '(none)'!r}")
    hdr = {}
    for l in lines[1:]:
        k, _, v = l.partition(":")
        hdr[k.strip().lower()] = v.strip()
    if hdr.get("content-type") != "text/plain":
        problems.append(f"content-type: {hdr.get('content-type')!r}")
    if hdr.get("content-length") != "13":
        problems.append(f"content-length: {hdr.get('content-length')!r}")
    if body != "hello, world\n":
        problems.append(f"body: {body!r}")
    return problems, txt


def stop(p):
    try:
        os.killpg(p.pid, signal.SIGTERM)
    except OSError:
        pass
    try:
        p.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        p.wait()
    try:
        os.killpg(p.pid, signal.SIGKILL)   # leftover workers (a fork server's children)
    except OSError:
        pass
    return p.returncode


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("server", nargs="?", choices=sorted(SERVERS))
    ap.add_argument("--plan", metavar="LIST", help="print the matrix for LIST (`all` or a comma list) as servers=<json> and exit")
    ap.add_argument("--minutes", type=float, default=60)
    ap.add_argument("--rate", type=int, default=3000, help="requests per second, total over all connections")
    ap.add_argument("--connections", type=int, default=16)
    ap.add_argument("--keepalive", default="true", help="true|false (false adds --disable-keepalive)")
    ap.add_argument("--every", type=float, default=5.0, help="sampling interval, seconds")
    ap.add_argument("--port", type=int, default=18080)
    ap.add_argument("--server-cpus", default="", help="taskset list for the server, e.g. 0,1 (empty: no pinning)")
    ap.add_argument("--load-cpus", default="", help="taskset list for oha and this sampler, e.g. 2,3")
    ap.add_argument("--latency-correction", action="store_true", help="pass --latency-correction to oha")
    ap.add_argument("--startup-timeout", type=float, default=90)
    ap.add_argument("--out", default=os.path.join(HERE, "out"))
    a = ap.parse_args()
    if a.plan is not None:
        want = a.plan.strip()
        sel = DEFAULT if want in ("", "all") else [x.strip() for x in want.split(",") if x.strip()]
        bad = [x for x in sel if x not in SERVERS]
        if bad:
            print(f"soak: unknown server(s) {', '.join(bad)}; known: {', '.join(DEFAULT + OPTIONAL)}", file=sys.stderr)
            return 2
        print("servers=" + json.dumps(sel))
        return 0
    if not a.server:
        ap.error("a server name is required (or --plan LIST)")

    keepalive = str(a.keepalive).lower() not in ("false", "0", "no")
    out = os.path.join(a.out, a.server)
    os.makedirs(out, exist_ok=True)
    have_taskset = bool(shutil.which("taskset"))
    pin_server = ["taskset", "-c", a.server_cpus] if a.server_cpus and have_taskset else []
    pin_load = ["taskset", "-c", a.load_cpus] if a.load_cpus and have_taskset else []
    if a.load_cpus and have_taskset and hasattr(os, "sched_setaffinity"):
        cpus = set()
        for part in a.load_cpus.split(","):
            lo, _, hi = part.partition("-")
            cpus.update(range(int(lo), int(hi or lo) + 1))
        os.sched_setaffinity(0, cpus)     # the sampler itself stays off the server's cores

    argv, cwd = SERVERS[a.server]
    argv = [x.replace("{port}", str(a.port)) for x in argv]
    server_cmd = pin_server + argv
    url = f"http://127.0.0.1:{a.port}/"
    oha_cmd = pin_load + ["oha", "-z", f"{a.minutes:g}m", "-q", str(a.rate), "-c", str(a.connections),
                          "--no-tui", "--output-format", "json"]
    if not keepalive:
        oha_cmd.append("--disable-keepalive")
    if a.latency_correction:
        oha_cmd.append("--latency-correction")
    oha_cmd.append(url)

    versions = {}
    for prefix, cmds in VERSION_CMDS.items():
        if a.server.startswith(prefix) or a.server == prefix:
            for c in cmds:
                versions[" ".join(c)] = first_line(c)
    if not versions:
        versions["(none)"] = "interpreted server with no version table entry"
    facts = {
        "server": a.server, "sources": SOURCES.get(a.server, []),
        "toolchain": versions, "oha": first_line(["oha", "--version"]),
        "server_cmd": server_cmd, "server_cwd": cwd, "oha_cmd": oha_cmd,
        "minutes": a.minutes, "rate": a.rate, "connections": a.connections, "keepalive": keepalive,
        "latency_correction": a.latency_correction, "sample_every_s": a.every,
        "server_cpus": a.server_cpus if pin_server else "", "load_cpus": a.load_cpus if pin_load else "",
        "taskset": have_taskset,
        "sysctl": {k: read(f"/proc/sys/net/ipv4/{k}").strip() for k in ("ip_local_port_range", "tcp_tw_reuse")} if LINUX else {},
        "nproc": os.cpu_count(), "kernel": " ".join(platform.uname()),
        "meminfo": {k: v for k, v in (l.split(":", 1) for l in read("/proc/meminfo").splitlines() if ":" in l)
                    if k in ("MemTotal", "MemAvailable")} if LINUX else {},
        "os_release": read("/etc/os-release").strip(),
        "runner": {k: os.environ.get(k, "") for k in ("ImageOS", "ImageVersion", "RUNNER_NAME", "RUNNER_ARCH",
                                                        "GITHUB_RUN_ID", "GITHUB_SHA", "GITHUB_REF_NAME")},
        "date_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
        "git": first_line(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"]),
    }

    log = open(os.path.join(out, "server.log"), "w")
    print(f"soak {a.server}: {' '.join(server_cmd)}  (cwd {cwd})", flush=True)
    p = subprocess.Popen(server_cmd, cwd=cwd, stdout=log, stderr=log, start_new_session=True)
    t_start = time.monotonic()
    startup = wait_200(a.port, a.startup_timeout)
    if startup is None or p.poll() is not None:
        facts["error"] = f"server did not answer 200 within {a.startup_timeout} s (exit {p.poll()})"
        json.dump(facts, open(os.path.join(out, "facts.json"), "w"), indent=1)
        stop(p)
        print("soak: " + facts["error"], file=sys.stderr)
        return 1
    facts["startup_s"] = round(startup, 4)
    problems, txt = contract(a.port)
    open(os.path.join(out, "contract.txt"), "w").write(txt)
    if problems:
        facts["error"] = "contract: " + "; ".join(problems)
        json.dump(facts, open(os.path.join(out, "facts.json"), "w"), indent=1)
        stop(p)
        print("soak: " + facts["error"], file=sys.stderr)
        return 1
    print(f"soak: up in {startup * 1000:.0f} ms, contract ok", flush=True)

    csv = open(os.path.join(out, "samples.csv"), "w")
    cols = ["t_s", "rss_group_kib", "rss_parent_kib", "hwm_parent_kib", "cpu_time_group_s", "pcpu_group",
            "threads", "procs", "loadavg1", "cpu_time_reaped_s"]
    csv.write(",".join(cols) + "\n")
    last = None

    def take():
        nonlocal last
        s = sample(p.pid)
        if s is None:
            return None
        t = time.monotonic() - t_start
        pcpu = 0.0
        if last is not None and t > last[0]:
            pcpu = 100.0 * (s["cpu_time_group_s"] - last[1]) / (t - last[0])
        last = (t, s["cpu_time_group_s"])
        s["t_s"] = round(t, 2)
        s["pcpu_group"] = round(pcpu, 2)
        s["cpu_time_group_s"] = round(s["cpu_time_group_s"], 3)
        s["cpu_time_reaped_s"] = round(s["cpu_time_reaped_s"], 3)
        csv.write(",".join(str(s[c]) for c in cols) + "\n")
        csv.flush()
        return s

    s0 = take()
    facts["cpu_time_at_load_start_s"] = s0["cpu_time_group_s"] if s0 else None
    facts["load_start_s"] = round(time.monotonic() - t_start, 2)
    print(f"soak: {' '.join(oha_cmd)}", flush=True)
    oha_out = open(os.path.join(out, "oha.json"), "w")
    oha_err = open(os.path.join(out, "oha.stderr"), "w")
    q = subprocess.Popen(oha_cmd, stdout=oha_out, stderr=oha_err)
    died = None
    while q.poll() is None:
        time.sleep(a.every)
        if q.poll() is not None:
            break        # oha is done: the next sample is the post-load one, taken below
        s = take()
        if s is None or p.poll() is not None:
            died = p.poll()
            break
        if int(s["t_s"]) % 300 < a.every:
            print(f"  t={s['t_s']:.0f}s rss={s['rss_group_kib']}K cpu={s['pcpu_group']:.1f}% thr={s['threads']} procs={s['procs']}", flush=True)
    if died is not None:
        try:
            q.kill()
        except OSError:
            pass
    q.wait()
    oha_out.close(); oha_err.close()
    facts["load_end_s"] = round(time.monotonic() - t_start, 2)
    s1 = take()      # one sample past load_end_s: the CPU total, outside the load window's RSS
    facts["cpu_time_at_load_end_s"] = s1["cpu_time_group_s"] if s1 else None
    facts["oha_exit"] = q.returncode
    facts["samples"] = sum(1 for _ in open(os.path.join(out, "samples.csv"))) - 1
    csv.close()
    if died is not None:
        facts["error"] = f"server died during the load (exit {died})"
    else:
        # one more contract check after the hour: the server must still answer
        problems, _ = contract(a.port)
        if problems:
            facts["error"] = "contract after the load: " + "; ".join(problems)
    facts["server_exit"] = stop(p)
    log.close()
    json.dump(facts, open(os.path.join(out, "facts.json"), "w"), indent=1)
    try:
        j = json.load(open(os.path.join(out, "oha.json")))
        print(f"soak: oha rps={j['summary']['requestsPerSec']:.1f} p50={j['latencyPercentiles']['p50'] * 1000:.3f}ms "
              f"p99={j['latencyPercentiles']['p99'] * 1000:.3f}ms status={j.get('statusCodeDistribution')} "
              f"errors={j.get('errorDistribution')}", flush=True)
    except Exception as e:
        print(f"soak: oha output not parsed: {e}", file=sys.stderr)
    if "error" in facts:
        print("soak: " + facts["error"], file=sys.stderr)
        return 1
    print("soak: done", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
