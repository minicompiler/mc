#!/usr/bin/env python3
"""report.py [OUTDIR] [--out REPORTDIR] -- the soak's tables and charts.

Reads every `facts.json` under OUTDIR (one directory per server, as soak.py
writes them and as the workflow's artifacts land) with its samples.csv and
oha.json, and writes into REPORTDIR (default OUTDIR/report):

  RESULTS.md     the conditions block, the two tables, one "what drifted" line per server
  results.json   every number behind the tables
  rss.svg        RSS of the process tree (KiB) against minutes, one line per server
  cpu.svg        %CPU of the process tree against minutes
  threads.svg    threads in the process tree against minutes
  <server>.svg   the three panels of one server (small multiples)

Python 3 standard library only; the SVG is written by hand (no matplotlib).
"""
import argparse, glob, json, math, os, sys

ORDER = ["mc-serial", "mc-fork1", "mc-forkka", "c-serial", "go-nethttp", "rust-threads", "rust-axum",
         "zig-threads", "cs-jit", "cs-aot", "node-single", "node-cluster", "py-stdlib", "py-uvicorn",
         "rb-webrick", "rb-puma", "php-builtin"]
# one color per server, distinguishable on white; dark enough to read as a line
COLORS = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd", "#8c564b", "#e377c2", "#7f7f7f",
          "#bcbd22", "#17becf", "#393b79", "#ad494a", "#637939", "#8c6d31", "#7b4173", "#e6550d", "#3182bd"]
MARKS_MIN = [1, 10, 30, 60]


# ---- reading --------------------------------------------------------------------------------
def load(outdir):
    runs = {}
    for fj in sorted(glob.glob(os.path.join(outdir, "**", "facts.json"), recursive=True)):
        d = os.path.dirname(fj)
        facts = json.load(open(fj))
        name = facts.get("server") or os.path.basename(d)
        samples = []
        sp = os.path.join(d, "samples.csv")
        if os.path.exists(sp):
            lines = open(sp).read().splitlines()
            if lines:
                cols = lines[0].split(",")
                for l in lines[1:]:
                    v = l.split(",")
                    if len(v) == len(cols):
                        samples.append({c: float(x) for c, x in zip(cols, v)})
        oha = {}
        op = os.path.join(d, "oha.json")
        if os.path.exists(op):
            txt = open(op).read()
            try:
                oha = json.loads(txt[txt.index("{"):])
            except (ValueError, json.JSONDecodeError):
                oha = {}
        runs[name] = {"facts": facts, "samples": samples, "oha": oha, "dir": d}
    return runs


def ordered(names):
    return sorted(names, key=lambda n: (ORDER.index(n) if n in ORDER else 99, n))


# ---- the numbers ----------------------------------------------------------------------------
def at_minute(samples, key, minute):
    """the last sample at or before `minute` (from server start); None past the end"""
    t = minute * 60
    best = None
    for s in samples:
        if s["t_s"] <= t:
            best = s
    if best is None or (samples and samples[-1]["t_s"] < t):
        return None
    return best[key]


def fit(xs, ys):
    """least squares y = a + b x; returns (b, r2) or (None, None)"""
    n = len(xs)
    if n < 3:
        return None, None
    mx = sum(xs) / n
    my = sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    syy = sum((y - my) ** 2 for y in ys)
    if sxx == 0:
        return None, None
    b = sxy / sxx
    r2 = (sxy * sxy) / (sxx * syy) if syy > 0 else 1.0
    return b, r2


def analyse(name, run):
    f, samples, oha = run["facts"], run["samples"], run["oha"]
    t0 = f.get("load_start_s", 0.0)
    t1 = f.get("load_end_s", samples[-1]["t_s"] if samples else 0.0)
    # the load window ends one second before oha's deadline (load_start + minutes), never at the
    # moment soak.py saw oha exit: at the deadline oha closes every connection, and a sample taken
    # in those seconds sees a server whose workers are already gone
    if f.get("minutes"):
        t1 = min(t1, t0 + float(f["minutes"]) * 60) - 1.0
    load = [s for s in samples if t0 <= s["t_s"] <= t1]
    dur_min = (t1 - t0) / 60 if t1 > t0 else 0.0
    r = {"server": name, "duration_min": round(dur_min, 2), "samples": len(samples), "error": f.get("error")}
    # the window of the slope: after the first ten minutes when the load lasted at least twenty,
    # otherwise after the first sixth of it -- the start-up transient stays out of the fit
    w0 = t0 + (600 if dur_min >= 20 else (t1 - t0) / 6)
    win = [s for s in load if s["t_s"] >= w0]
    r["window_min"] = [round((w0 - t0) / 60, 1), round(dur_min, 1)]
    for key, label in (("rss_group_kib", "rss"), ("threads", "threads"), ("procs", "procs")):
        r[label + "_at"] = {str(m): at_minute(samples, key, m) for m in MARKS_MIN}
        r[label + "_end"] = load[-1][key] if load else None
        r[label + "_peak"] = max((s[key] for s in samples), default=None)
    r["hwm_parent_kib"] = max((s["hwm_parent_kib"] for s in samples), default=None)
    b, r2 = fit([s["t_s"] / 60 for s in win], [s["rss_group_kib"] for s in win])
    r["rss_slope_kib_per_min"] = None if b is None else round(b, 2)
    r["rss_slope_r2"] = None if r2 is None else round(r2, 3)
    r["rss_window_start_kib"] = win[0]["rss_group_kib"] if win else None
    r["rss_window_mean_kib"] = round(sum(s["rss_group_kib"] for s in win) / len(win)) if win else None
    cpu = [s["pcpu_group"] for s in load[1:]]
    r["pcpu_mean"] = round(sum(cpu) / len(cpu), 2) if cpu else None
    r["pcpu_peak"] = round(max(cpu), 2) if cpu else None
    c0, c1 = f.get("cpu_time_at_load_start_s"), f.get("cpu_time_at_load_end_s")
    r["cpu_s"] = round(c1 - c0, 3) if c0 is not None and c1 is not None else None
    s = oha.get("summary", {})
    lat = oha.get("latencyPercentiles", {})
    codes = oha.get("statusCodeDistribution", {}) or {}
    errs = oha.get("errorDistribution", {}) or {}
    r["requests"] = sum(int(v) for v in codes.values())
    r["ok_200"] = int(codes.get("200", 0))
    r["non_200"] = r["requests"] - r["ok_200"]
    r["errors"] = sum(int(v) for v in errs.values())
    r["error_kinds"] = errs
    r["rps"] = round(s["requestsPerSec"], 1) if "requestsPerSec" in s else None
    r["rps_requested"] = f.get("rate")
    r["p50_ms"] = round(lat["p50"] * 1000, 3) if "p50" in lat else None
    r["p99_ms"] = round(lat["p99"] * 1000, 3) if "p99" in lat else None
    r["p999_ms"] = round(lat["p99.9"] * 1000, 3) if "p99.9" in lat else None
    r["cpu_ms_per_1k_req"] = round(r["cpu_s"] * 1e6 / r["requests"], 3) if r["cpu_s"] is not None and r["requests"] else None
    r["startup_s"] = f.get("startup_s")
    r["toolchain"] = f.get("toolchain", {})
    # the one-line verdict, from the numbers and nothing else
    if win and r["rss_slope_kib_per_min"] is not None and r["rss_window_mean_kib"]:
        delta = r["rss_end"] - r["rss_window_start_kib"]
        pct = 100.0 * delta / r["rss_window_start_kib"] if r["rss_window_start_kib"] else 0.0
        proj = r["rss_slope_kib_per_min"] * (r["window_min"][1] - r["window_min"][0])
        drifted = abs(proj) >= 0.05 * r["rss_window_mean_kib"] and (r["rss_slope_r2"] or 0) >= 0.5
        r["drift"] = "drifted" if drifted else "flat"
        r["drift_line"] = (f"`{name}`: RSS {r['rss_window_start_kib']:,.0f} -> {r['rss_end']:,.0f} KiB over minutes "
                           f"{r['window_min'][0]:g}-{r['window_min'][1]:g} ({pct:+.1f}%), slope {r['rss_slope_kib_per_min']:+.1f} KiB/min "
                           f"(R^2 {r['rss_slope_r2']:.2f}), peak {r['rss_peak']:,.0f} KiB: **{r['drift']}**")
    else:
        r["drift"] = "n/a"
        r["drift_line"] = f"`{name}`: no RSS window ({r['error'] or 'too few samples'})"
    return r


# ---- SVG -------------------------------------------------------------------------------------
def nice_ticks(lo, hi, n=6):
    """linear ticks with 1-2-5 steps covering [lo, hi]"""
    if hi <= lo:
        hi = lo + 1
    raw = (hi - lo) / max(1, n)
    mag = 10 ** math.floor(math.log10(raw))
    for m in (1, 2, 2.5, 5, 10):
        step = m * mag
        if raw <= step:
            break
    t0 = math.floor(lo / step) * step
    ticks = []
    t = t0
    while t <= hi + step * 1e-9:
        ticks.append(round(t, 10))
        t += step
    return ticks


def log_ticks(lo, hi):
    lo = max(lo, 1e-9)
    ticks = []
    e = math.floor(math.log10(lo))
    while 10 ** e <= hi * 1.0001:
        for m in (1, 2, 5):
            v = m * 10 ** e
            if lo * 0.9999 <= v <= hi * 1.0001:
                ticks.append(v)
        e += 1
    return ticks or [lo, hi]


def fmt(v):
    if v == 0:
        return "0"
    if abs(v) >= 1000:
        return f"{v:,.0f}"
    if abs(v) >= 10:
        return f"{v:.0f}" if float(v).is_integer() else f"{v:.1f}"
    return f"{v:g}"


def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def line_panel(series, title, ylabel, xlabel, log=False, w=960, h=480, legend=True):
    """series: [(name, color, [(x, y)])]. Returns the SVG text of one chart."""
    ml, mr, mt, mb = 90, 200 if legend else 24, 48, 56
    pw, ph = w - ml - mr, h - mt - mb
    xs = [x for _, _, pts in series for x, _ in pts]
    ys = [y for _, _, pts in series for _, y in pts]
    if not xs:
        return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}"><rect width="100%" height="100%" fill="#fff"/><text x="20" y="30" font-family="sans-serif" font-size="14" fill="#111">{esc(title)}: no data</text></svg>'
    x0, x1 = 0.0, max(xs)
    if x1 <= x0:
        x1 = x0 + 1
    if log:
        ylo = max(min(y for y in ys if y > 0) if any(y > 0 for y in ys) else 1, 1)
        yt = log_ticks(ylo, max(ys))
        y0, y1 = math.log10(yt[0]), math.log10(max(yt[-1], max(ys)))
        if y1 <= y0:
            y1 = y0 + 1
        yv = lambda y: mt + ph - (math.log10(max(y, ylo)) - y0) / (y1 - y0) * ph
    else:
        yt = nice_ticks(0, max(ys))
        y0, y1 = 0.0, max(yt[-1], max(ys))
        yv = lambda y: mt + ph - (y - y0) / (y1 - y0) * ph
    xt = nice_ticks(0, x1, 8)
    xv = lambda x: ml + (x - x0) / (x1 - x0) * pw
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" font-family="sans-serif" font-size="12">',
         '<rect width="100%" height="100%" fill="#fff"/>',
         f'<text x="{ml}" y="24" font-size="15" font-weight="bold" fill="#111">{esc(title)}</text>']
    for t in yt:
        y = yv(t)
        if y < mt - 1 or y > mt + ph + 1:
            continue
        o.append(f'<line x1="{ml}" y1="{y:.1f}" x2="{ml + pw}" y2="{y:.1f}" stroke="#ddd"/>')
        o.append(f'<text x="{ml - 6}" y="{y + 4:.1f}" text-anchor="end" fill="#111">{fmt(t)}</text>')
    for t in xt:
        x = xv(t)
        if x > ml + pw + 1:
            continue
        o.append(f'<line x1="{x:.1f}" y1="{mt}" x2="{x:.1f}" y2="{mt + ph}" stroke="#eee"/>')
        o.append(f'<text x="{x:.1f}" y="{mt + ph + 18}" text-anchor="middle" fill="#111">{fmt(t)}</text>')
    o.append(f'<rect x="{ml}" y="{mt}" width="{pw}" height="{ph}" fill="none" stroke="#333"/>')
    o.append(f'<text x="{ml + pw / 2:.1f}" y="{h - 14}" text-anchor="middle" fill="#111">{esc(xlabel)}</text>')
    o.append(f'<text transform="translate(18,{mt + ph / 2:.1f}) rotate(-90)" text-anchor="middle" fill="#111">{esc(ylabel)}{" (log)" if log else ""}</text>')
    for i, (name, color, pts) in enumerate(series):
        if not pts:
            continue
        d = " ".join(f"{'M' if k == 0 else 'L'}{xv(x):.1f},{yv(y):.1f}" for k, (x, y) in enumerate(pts))
        o.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="1.6"><title>{esc(name)}</title></path>')
        if legend:
            ly = mt + 8 + i * 18
            o.append(f'<line x1="{ml + pw + 14}" y1="{ly}" x2="{ml + pw + 38}" y2="{ly}" stroke="{color}" stroke-width="3"/>')
            o.append(f'<text x="{ml + pw + 44}" y="{ly + 4}" fill="#111">{esc(name)}</text>')
    o.append("</svg>")
    return "\n".join(o)


def stack(panels, w=960):
    """several charts one under the other, in one SVG"""
    total = 0
    body = []
    for p in panels:
        hh = int(p.split('height="')[1].split('"')[0])
        inner = p[p.index(">") + 1:p.rindex("</svg>")]
        body.append(f'<g transform="translate(0,{total})">{inner}</g>')
        total += hh
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{total}" viewBox="0 0 {w} {total}" font-family="sans-serif" font-size="12">'
            + "\n".join(body) + "</svg>")


def charts(runs, results, where, outdir):
    names = ordered(runs)
    color = {n: COLORS[i % len(COLORS)] for i, n in enumerate(names)}

    def series(key):
        return [(n, color[n], [(s["t_s"] / 60, s[key]) for s in runs[n]["samples"]]) for n in names]

    rss = series("rss_group_kib")
    ys = [y for _, _, pts in rss for _, y in pts if y > 0]
    log = bool(ys) and max(ys) / min(ys) > 20
    open(os.path.join(outdir, "rss.svg"), "w").write(line_panel(rss, f"RSS of the process tree -- {where}", "KiB", "minutes since server start", log=log))
    open(os.path.join(outdir, "cpu.svg"), "w").write(line_panel(series("pcpu_group"), f"CPU of the process tree -- {where}", "% of one core", "minutes since server start"))
    open(os.path.join(outdir, "threads.svg"), "w").write(line_panel(series("threads"), f"Threads in the process tree -- {where}", "threads", "minutes since server start"))
    for n in names:
        one = lambda key: [(n, color[n], [(s["t_s"] / 60, s[key]) for s in runs[n]["samples"]])]
        panels = [line_panel(one("rss_group_kib"), f"{n}: RSS (KiB) -- {where}", "KiB", "minutes", w=720, h=260, legend=False),
                  line_panel(one("pcpu_group"), f"{n}: CPU (% of one core)", "%", "minutes", w=720, h=260, legend=False),
                  line_panel(one("threads"), f"{n}: threads", "threads", "minutes", w=720, h=260, legend=False)]
        open(os.path.join(outdir, f"{n}.svg"), "w").write(stack(panels, w=720))
    return log


# ---- the markdown ----------------------------------------------------------------------------
def cell(v, digits=0):
    if v is None:
        return "-"
    if isinstance(v, float):
        return f"{v:,.{digits}f}"
    return f"{v:,}" if isinstance(v, int) else str(v)


def pretty_name(os_release):
    for l in os_release.splitlines():
        if l.startswith("PRETTY_NAME="):
            return l.split("=", 1)[1].strip().strip('"')
    return ""


def write_md(runs, results, outdir, log_rss):
    names = ordered(runs)
    f0 = runs[names[0]]["facts"] if names else {}
    rn = f0.get("runner", {})
    where = f"{rn.get('ImageOS') or 'unknown runner'} {rn.get('ImageVersion', '')}".strip()
    L = ["# The HTTP soak", "",
         "Every server under the same fixed request rate for the same length of time, one GitHub Actions",
         "runner per server, the server pinned to two cores and the load generator to the other two; the",
         "server's whole process tree sampled every few seconds. Produced by `bench/soak/report.py` from",
         "the artifacts of `.github/workflows/bench-soak.yml`; the protocol is `bench/README.md` § The soak.", "",
         "## Conditions", "", "| | |", "|---|---|",
         f"| Runner | {where} (`RUNNER_NAME` {rn.get('RUNNER_NAME', '')}, {rn.get('RUNNER_ARCH', '')}) |",
         f"| Kernel | {f0.get('kernel', '')} |",
         f"| OS | {pretty_name(f0.get('os_release', ''))} |",
         f"| CPUs / memory | {f0.get('nproc')} vCPU, {f0.get('meminfo', {}).get('MemTotal', '').strip()} |",
         f"| Pinning | server on cores {f0.get('server_cpus') or '(none)'}, oha and the sampler on cores {f0.get('load_cpus') or '(none)'} (`taskset`) |",
         f"| Load | `oha` {f0.get('oha', '')}: {f0.get('rate')} req/s over {f0.get('connections')} connections, keep-alive {'on' if f0.get('keepalive') else 'off'}, {f0.get('minutes')} min |",
         f"| Sampling | every {f0.get('sample_every_s')} s: RSS/CPU time/threads/processes of the tree, VmRSS/VmHWM of the parent, loadavg |",
         f"| Date | {f0.get('date_utc', '')} |",
         f"| Tree | `{f0.get('git', '')}` (run {rn.get('GITHUB_RUN_ID', '')}) |",
         "", "Toolchains, as each job recorded them:", "", "| server | toolchain |", "|---|---|"]
    for n in names:
        tc = runs[n]["facts"].get("toolchain", {})
        L.append(f"| `{n}` | " + "; ".join(f"`{v}`" for v in tc.values()) + " |")
    L += ["", "## Throughput and latency", "",
          "`req/s` is what oha achieved against what was asked; `requests` counts every response, `non-200`",
          "the ones that were not `200`, `errors` the connection-level failures oha reported (an `aborted due to",
          "deadline` at the very end is the normal way a timed run stops). Latencies in ms, from oha's",
          "own histogram.", "",
          "| server | req/s (asked) | requests | non-200 | errors | p50 | p99 | p99.9 | startup |", "|---|---|---|---|---|---|---|---|---|"]
    for n in names:
        r = results[n]
        L.append(f"| `{n}` | {cell(r['rps'], 1)} ({cell(r['rps_requested'])}) | {cell(r['requests'])} | {cell(r['non_200'])} | {cell(r['errors'])} | "
                 f"{cell(r['p50_ms'], 3)} | {cell(r['p99_ms'], 3)} | {cell(r['p999_ms'], 3) if r['p999_ms'] is not None else '-'} | "
                 f"{cell(r['startup_s'] * 1000 if r['startup_s'] is not None else None, 0)} ms |")
    L += ["", "## Memory and CPU", "",
          "RSS is the sum over the server's process tree (a fork-per-connection server's children, a",
          "cluster's workers) in KiB, read at the given minute since the server started; `peak` over the",
          "whole run; `slope` is the least-squares fit of RSS against time over the window named in the",
          "verdict lines below, with its R^2. `%CPU` is the tree's CPU time per wall-clock second, averaged",
          "over the load (100 = one core); `CPU ms / 1k req` is the tree's CPU time over the load divided by",
          "the requests oha counted -- the number comparable across concurrency shapes. `end` is the last",
          "sample taken more than a second before oha's deadline (oha closes its connections at the",
          "deadline, and a sample taken in those seconds sees a server whose workers are already gone).", "",
          "| server | RSS 1 min | 10 min | 30 min | 60 min | end | peak | slope KiB/min (R^2) | %CPU mean | CPU ms / 1k req | threads max | procs max |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for n in names:
        r = results[n]
        a = r["rss_at"]
        slope = "-" if r["rss_slope_kib_per_min"] is None else f"{r['rss_slope_kib_per_min']:+.1f} ({r['rss_slope_r2']:.2f})"
        L.append(f"| `{n}` | {cell(a['1'])} | {cell(a['10'])} | {cell(a['30'])} | {cell(a['60'])} | {cell(r['rss_end'])} | {cell(r['rss_peak'])} | {slope} | "
                 f"{cell(r['pcpu_mean'], 1)} | {cell(r['cpu_ms_per_1k_req'], 2)} | {cell(r['threads_peak'])} | {cell(r['procs_peak'])} |")
    L += ["", "## What drifted", "",
          "One line per server, from the numbers above. `drifted` means the fitted slope, projected over the",
          "window, moves RSS by at least 5% of the window's mean AND the fit explains at least half of the",
          "variance (R^2 >= 0.5); anything else is `flat`. A rule, not a judgement -- read the chart.", ""]
    for n in names:
        L.append("- " + results[n]["drift_line"])
    failed = [n for n in names if results[n]["error"]]
    if failed:
        L += ["", "Runs that ended with an error (their numbers above cover what was recorded before it):", ""]
        for n in failed:
            L.append(f"- `{n}`: {results[n]['error']}")
    L += ["", "## Charts", "",
          f"`rss.svg` (RSS of the tree, {'log scale: the range spans more than 20x' if log_rss else 'linear scale'}), `cpu.svg`, `threads.svg` --",
          "every server on one chart -- and one `<server>.svg` per server with its three panels. All in this",
          "directory, drawn by `report.py` with no library: dark text on a white background.", ""]
    open(os.path.join(outdir, "RESULTS.md"), "w").write("\n".join(L))
    return where


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("outdir", nargs="?", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "out"))
    ap.add_argument("--out", default=None, help="report directory (default OUTDIR/report)")
    a = ap.parse_args()
    runs = load(a.outdir)
    if not runs:
        print(f"report: no facts.json under {a.outdir}", file=sys.stderr)
        return 1
    rep = a.out or os.path.join(a.outdir, "report")
    os.makedirs(rep, exist_ok=True)
    results = {n: analyse(n, r) for n, r in runs.items()}
    rn = next(iter(runs.values()))["facts"].get("runner", {})
    date = next(iter(runs.values()))["facts"].get("date_utc", "")[:10]
    where = f"{rn.get('ImageOS') or 'local'} {date}".strip()
    log_rss = charts(runs, results, where, rep)
    write_md(runs, results, rep, log_rss)
    json.dump({"conditions": {n: r["facts"] for n, r in runs.items()}, "results": results}, open(os.path.join(rep, "results.json"), "w"), indent=1)
    for n in ordered(runs):
        print(results[n]["drift_line"])
    print(f"report: {rep}/RESULTS.md, results.json, {3 + len(runs)} SVG charts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
