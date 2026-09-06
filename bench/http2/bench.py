#!/usr/bin/env python3
"""HTTP micro-benchmark driver (bench/http2: bench/http/bench.py verbatim, only SERVERS and PORT0 differ). For each server and load configuration:
start a FRESH server in its own process group under /usr/bin/time -l, wait for
the first 200 (startup time), warm up 2 s, run ab (best of 3, each run on a
fresh server) with a 0.5 s ps sampler, then oha once. Results -> results.json."""
import json, os, re, signal, subprocess, sys, time, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
os.chdir(HERE)
SERVERS = {
    "node-single":  ["bin/node-single"],
    "node-cluster": ["bin/node-cluster"],
    "rust-axum":    ["bin/axum"],
    "py-stdlib":    ["bin/py-stdlib"],
    "py-uvicorn":   ["bin/py-uvicorn"],
    "rb-webrick":   ["bin/rb-webrick"],
    "rb-puma":      ["bin/rb-puma"],
    "php-builtin":  ["bin/php-builtin"],
}
CONFIGS = {
    "ka64": {"ab": ["-k", "-c", "64", "-n", "200000"], "oha": ["-c", "64", "-z", "5s"]},
    "c1":   {"ab": ["-c", "1", "-n", "50000"],         "oha": ["-c", "1", "--disable-keepalive", "-z", "5s"]},
}
RUNS = int(os.environ.get("RUNS", "3"))
PORT0 = int(os.environ.get("PORT0", "9200"))
ONLY = sys.argv[1:] or list(SERVERS)
if "N" in os.environ:  # quick mode
    CONFIGS["ka64"]["ab"][-1] = os.environ["N"]; CONFIGS["c1"]["ab"][-1] = os.environ["N"]

def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)

def wait_200(port, timeout=30.0):
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        r = sh(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "1", f"http://127.0.0.1:{port}/"])
        if r.stdout.strip() == "200":
            return time.monotonic() - t0
        time.sleep(0.01)
    return None

def drain_time_wait(limit=2000, timeout=32):
    """TIME_WAIT sockets from the previous run hold ephemeral ports for 2*MSL = 30 s
    (net.inet.tcp.msl 15000, range 49152..65535 = 16384 ports, no sudo to change);
    wait until they are gone so every run starts from the same state"""
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        r = sh(["netstat", "-an", "-p", "tcp"])
        n = sum(1 for l in r.stdout.splitlines() if "TIME_WAIT" in l)
        if n < limit: return n, time.monotonic() - t0
        time.sleep(1)
    return n, time.monotonic() - t0

def start(name, port):
    cmd = ["python3", "-c", "import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])",
           "/usr/bin/time", "-l"] + SERVERS[name] + [str(port)]
    log = open(f"logs/run-{name}-{port}.log", "w")
    t0 = time.monotonic()
    p = subprocess.Popen(cmd, stdout=log, stderr=log)
    st = wait_200(port)
    return p, st, log

def group(pgid):
    """[(pid, rss_kib, pcpu, time_s)] for every process in the group"""
    r = sh(["ps", "-axo", "pid=,pgid=,rss=,%cpu=,time=,comm="])
    out = []
    for line in r.stdout.splitlines():
        f = line.split(None, 5)
        if len(f) >= 5 and int(f[1]) == pgid:
            m, s = f[4].split(":") if ":" in f[4] else ("0", f[4])
            out.append((int(f[0]), int(f[2]), float(f[3]), int(m) * 60 + float(s), f[5] if len(f) > 5 else ""))
    return out

def server_pid(pgid):
    # the real server is the process in the group that is not /usr/bin/time
    for pid, rss, cpu, t, comm in group(pgid):
        if "time" not in comm:
            return pid
    return None

def threads(pid):
    r = sh(["ps", "-M", "-p", str(pid)])
    return max(0, len(r.stdout.splitlines()) - 1)

def stop(p, pgid, log):
    """SIGTERM the server; /usr/bin/time then prints the rusage; returns it"""
    spid = server_pid(pgid)
    if spid:
        os.kill(spid, signal.SIGTERM)
    try:
        p.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try: os.killpg(pgid, signal.SIGKILL)
        except OSError: pass
        p.wait()
    # kill any leftover worker in the group
    try: os.killpg(pgid, signal.SIGKILL)
    except OSError: pass   # ESRCH when empty; EPERM was seen once on a fork server's group (a zombie child)
    log.close()
    txt = open(log.name).read()
    ru = {}
    for k, pat in [("user_s", r"([\d.]+) user"), ("sys_s", r"([\d.]+) sys"), ("real_s", r"([\d.]+) real"),
                   ("maxrss_bytes", r"(\d+)\s+maximum resident set size"), ("invol_ctx", r"(\d+)\s+involuntary context switches"),
                   ("vol_ctx", r"(\d+)\s+voluntary context switches")]:
        m = re.search(pat, txt)
        if m: ru[k] = float(m.group(1))
    return ru

def parse_ab(txt):
    d = {}
    def g(pat, cast=float):
        m = re.search(pat, txt, re.M); return cast(m.group(1)) if m else None
    d["complete"] = g(r"^Complete requests:\s+(\d+)", int)
    d["failed"] = g(r"^Failed requests:\s+(\d+)", int)
    d["non2xx"] = g(r"^Non-2xx responses:\s+(\d+)", int) or 0
    d["rps"] = g(r"^Requests per second:\s+([\d.]+)")
    d["mean_ms"] = g(r"^Time per request:\s+([\d.]+) \[ms\] \(mean\)")
    d["mean_ms_all"] = g(r"^Time per request:\s+([\d.]+) \[ms\] \(mean, across")
    d["p50_ms"] = g(r"^\s+50%\s+(\d+)", int)
    d["p99_ms"] = g(r"^\s+99%\s+(\d+)", int)
    d["max_ms"] = g(r"^\s+100%\s+(\d+)", int)
    d["keepalive"] = g(r"^Keep-Alive requests:\s+(\d+)", int)
    d["total_s"] = g(r"^Time taken for tests:\s+([\d.]+)")
    return d

def parse_oha(txt):
    d = {}
    try:
        j = json.loads(txt[txt.index("{"):])   # oha prints a DNS warning line first
        d["rps"] = j["summary"]["requestsPerSec"]; d["success_rate"] = j["summary"]["successRate"]
        d["mean_ms"] = j["summary"]["average"] * 1000
        d["p50_ms"] = j["latencyPercentiles"]["p50"] * 1000; d["p99_ms"] = j["latencyPercentiles"]["p99"] * 1000
        d["duration_s"] = j["summary"]["total"]
        d["total"] = sum(int(v) for v in j.get("statusCodeDistribution", {}).values())
        d["status"] = j.get("statusCodeDistribution"); d["errors"] = j.get("errorDistribution")
    except Exception as e:
        d["error"] = f"parse: {e}: {txt[:400]}"
    return d

def run_load(cmd, pgid, sample_every=0.5):
    """run the load generator; sample the server's process group meanwhile"""
    spid = server_pid(pgid)
    t_before = sum(t for _, _, _, t, _ in group(pgid))
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    t0 = time.monotonic()
    peak_grp_rss = peak_par_rss = peak_grp_cpu = peak_par_cpu = peak_procs = peak_thr = 0
    cpu_samples = []
    while proc.poll() is None:
        g = group(pgid)
        grp_rss = sum(r for _, r, _, _, _ in g); grp_cpu = sum(c for _, _, c, _, _ in g)
        par = [x for x in g if x[0] == spid]
        if par:
            peak_par_rss = max(peak_par_rss, par[0][1]); peak_par_cpu = max(peak_par_cpu, par[0][2])
            peak_thr = max(peak_thr, threads(spid))
        peak_grp_rss = max(peak_grp_rss, grp_rss); peak_grp_cpu = max(peak_grp_cpu, grp_cpu)
        peak_procs = max(peak_procs, len(g)); cpu_samples.append(grp_cpu)
        time.sleep(sample_every)
    wall = time.monotonic() - t0
    out = proc.stdout.read()
    t_after = sum(t for _, _, _, t, _ in group(pgid))
    return out, {"wall_s": wall, "peak_group_rss_kib": peak_grp_rss, "peak_parent_rss_kib": peak_par_rss,
                 "ps_peak_group_pcpu": peak_grp_cpu, "ps_mean_group_pcpu": sum(cpu_samples) / max(1, len(cpu_samples)),
                 "ps_peak_parent_pcpu": peak_par_cpu, "peak_threads_parent": peak_thr, "peak_processes": peak_procs,
                 "live_cputime_delta_s": t_after - t_before, "samples": len(cpu_samples)}

def bench(name, cfg):
    runs = []
    port = PORT0
    for i in range(RUNS):
        port += 1
        tw, waited = drain_time_wait()
        p, st, log = start(name, port)
        pgid = p.pid
        if st is None:
            runs.append({"error": "server did not answer 200 within 30 s"}); stop(p, pgid, log); continue
        # warm-up: 2 s of the same shape
        warm = ["ab", "-q", "-t", "2", "-n", "1000000"] + [a for a in CONFIGS[cfg]["ab"] if a not in ("-n",)][:]
        # ab needs -n after -t; rebuild: keep -k/-c, drop -n VALUE
        ab_args = CONFIGS[cfg]["ab"]; keep = []
        j = 0
        while j < len(ab_args):
            if ab_args[j] == "-n": j += 2; continue
            keep.append(ab_args[j]); j += 1
        warm = ["ab", "-q", "-t", "2", "-n", "1000000"] + keep + [f"http://127.0.0.1:{port}/"]
        tw0 = time.monotonic(); w = sh(warm); warm_s = time.monotonic() - tw0
        wa = parse_ab(w.stdout)
        cmd = ["ab", "-q"] + CONFIGS[cfg]["ab"] + [f"http://127.0.0.1:{port}/"]
        out, samp = run_load(cmd, pgid)
        open(f"logs/ab-{name}-{cfg}-{i+1}.txt", "w").write(" ".join(cmd) + "\n" + out)
        ab = parse_ab(out)
        ru = stop(p, pgid, log)
        cpu_total = ru.get("user_s", 0) + ru.get("sys_s", 0)
        # rusage covers warm-up + run (+ startup); the run dominates. mean %CPU over the whole life:
        life = ru.get("real_s", warm_s + samp["wall_s"])
        runs.append({"port": port, "startup_s": st, "time_wait_before": tw, "drain_wait_s": waited, "warmup": {"wall_s": warm_s, "requests": wa.get("complete"), "rps": wa.get("rps")},
                     "ab": ab, "ab_cmd": " ".join(cmd), "sampler": samp, "rusage_time_l": ru,
                     "cpu_total_s": cpu_total, "rusage_mean_pcpu_over_life": 100 * cpu_total / life if life else None,
                     "cpu_s_per_1k_req": 1000 * cpu_total / ((ab.get("complete") or 0) + (wa.get("complete") or 0)) if ab.get("complete") else None})
        print(f"  {name} {cfg} run{i+1}: rps={ab.get('rps')} mean={ab.get('mean_ms')}ms p50={ab.get('p50_ms')} p99={ab.get('p99_ms')} failed={ab.get('failed')} "
              f"grpRSS={samp['peak_group_rss_kib']}K parRSS={samp['peak_parent_rss_kib']}K thr={samp['peak_threads_parent']} procs={samp['peak_processes']} "
              f"cpu={cpu_total:.2f}s ({runs[-1]['rusage_mean_pcpu_over_life']:.0f}% of life) startup={st*1000:.0f}ms", flush=True)
    # oha, once
    port += 1
    drain_time_wait()
    p, st, log = start(name, port)
    pgid = p.pid
    oha = {}
    if st is not None and shutil.which("oha"):
        sh(["ab", "-q", "-t", "2", "-n", "1000000", "-k", "-c", "64", f"http://127.0.0.1:{port}/"])
        cmd = ["oha", "--no-tui", "--output-format", "json"] + CONFIGS[cfg]["oha"] + [f"http://127.0.0.1:{port}/"]
        out, samp = run_load(cmd, pgid)
        open(f"logs/oha-{name}-{cfg}.json", "w").write(out)
        oha = parse_oha(out); oha["cmd"] = " ".join(cmd); oha["sampler"] = samp
        print(f"  {name} {cfg} oha: rps={oha.get('rps')} p50={oha.get('p50_ms')} p99={oha.get('p99_ms')} success={oha.get('success_rate')}", flush=True)
    ru = stop(p, pgid, log)
    oha["rusage_time_l"] = ru
    best = max((r for r in runs if "ab" in r and r["ab"].get("rps")), key=lambda r: r["ab"]["rps"], default=None)
    return {"runs": runs, "best": best, "oha": oha}

results = {}
if os.path.exists("results.json"):
    results = json.load(open("results.json"))
for name in ONLY:
    results.setdefault(name, {})
    for cfg in CONFIGS:
        print(f"== {name} / {cfg}", flush=True)
        results[name][cfg] = bench(name, cfg)
        json.dump(results, open("results.json", "w"), indent=1)
print("done")
