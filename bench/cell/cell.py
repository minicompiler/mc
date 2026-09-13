#!/usr/bin/env python3
"""bench/cell/cell.py -- the reproducible bench cell (M50 step A).

One invocation is ONE CELL RUN: it builds every row whose toolchain is present,
times each of them at each phase with the reference timed beside them, and writes
results.json, facts.json and RESULTS.md into a dated directory.

The protocol, and why (docs/specs/M50.md):

  * seven repetitions, the rows INTERLEAVED inside each repetition in a fixed
    order, one process at a time; repetition 1 is recorded and excluded from
    every statistic (it is 1.25-1.62x the best in nine of the ten rows recorded
    in bench/results.json: the 50 MB __bss sieve is first-touched and the
    binary's pages are cold);
  * the verdict is `median(row) / median(reference)` over the kept repetitions
    of the SAME run, the reference being `clang -O2` of bench/c/bench.c built and
    timed in this very run. Absolute seconds are recorded and NEVER gated: the
    same unchanged clang binary of this program has timed 0.420, 0.49 and
    0.52-0.56 s in three sessions on one Mac, while the ratio agreed to 0.7%
    between two consecutive runs;
  * every repetition of every row asserts the workload's own recorded answer, so
    a row that prints the wrong number is a failed row and not a timing;
  * `taskset -c 0` on Linux, nothing on macOS (the workload is single-threaded
    and peaks at ~51 MB, so a memory cap changes no number and a CPU quota is a
    share of a shared machine, not a speed);
  * the SHA-256 of every binary timed, the mc one included, because a digest
    cannot go stale the way bench/results.json's "tree at commit e5a1643" did.

Python 3 standard library only. Not part of `make check`: results depend on the
host's CPU, its load and the installed toolchain versions, which `make check`
must not.
"""

import argparse
import json
import os
import platform
import re
import resource
import shutil
import statistics
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# The recorded cross-check, per phase: what every implementation must print.
# bench/run.sh asserts the same three numbers for the no-argument road.
EXPECT = {
    "all": "8128903901837660708\n3001134\n39088169\n",
    "mix": "8128903901837660708\n",
    "primes": "3001134\n",
    "fib": "39088169\n",
}

# (row, the tool that must be on PATH, how the row is labelled).
# The order is the interleaving order and never changes.
ROWS = [
    ("mc-plain", "mc", "mc --exe"),
    ("mc-opt", "mc", "mc -O --exe"),
    ("c-O2", "clang", "clang -O2"),
    ("c-O0", "clang", "clang -O0"),
    ("go", "go", "go build"),
    ("zig-fast", "zig", "zig -O ReleaseFast"),
    ("zig-debug", "zig", "zig -O Debug"),
    ("rust-O3", "rustc", "rustc -C opt-level=3"),
    ("rust-O0", "rustc", "rustc -C opt-level=0"),
    ("cs-aot", "dotnet", "dotnet publish -p:PublishAot=true"),
    ("cs-jit", "dotnet", "dotnet publish (JIT, shared runtime)"),
]


def read_env(path):
    """KEY=value lines, '#' comments, no quoting and no substitution."""
    out = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def run(cmd, cwd=None):
    """Run a command, return (rc, stdout+stderr). Never raises."""
    try:
        p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except OSError as e:
        return 127, str(e)


def out_of(cmd):
    """First line a tool prints, or None when the tool is not there."""
    rc, txt = run(cmd)
    if rc != 0:
        return None
    for line in txt.splitlines():
        if line.strip():
            return line.strip()
    return ""


def mc_binary(cfg_mc):
    if cfg_mc:
        return cfg_mc
    local = os.path.join(ROOT, "build", "mc1")
    if os.access(local, os.X_OK):
        return local
    found = shutil.which("mc")
    return found if found else local


def sha256_of(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(1 << 20)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def text_bytes(path):
    """The executable section's size, or None when no size tool answers.

    Informational only: it is what bench/RESULTS.md section A records per row.
    """
    if sys.platform == "darwin":
        rc, txt = run(["size", "-m", path])
        if rc == 0:
            m = re.search(r"Section __text:\s*(\d+)", txt)
            if m:
                return int(m.group(1))
        return None
    rc, txt = run(["size", "-A", path])
    if rc == 0:
        m = re.search(r"^\.text\s+(\d+)", txt, re.M)
        if m:
            return int(m.group(1))
    return None


def pin_prefix():
    """`taskset -c 0` on Linux, nothing anywhere else (D3)."""
    if sys.platform.startswith("linux") and shutil.which("taskset"):
        return ["taskset", "-c", "0"]
    return []


def time_once(cmd, outfile):
    """One timed run. Returns (seconds, max_rss_bytes, rc, stdout)."""
    with open(outfile, "wb") as fh:
        t0 = time.monotonic()
        p = subprocess.Popen(cmd, stdout=fh, stderr=subprocess.DEVNULL)
        _, status, ru = os.wait4(p.pid, 0)
        secs = time.monotonic() - t0
    # os.wait4 already reaped the child; telling Popen so keeps its destructor
    # from waiting on a pid that is gone and warning about it.
    p.returncode = status
    rc = os.waitstatus_to_exitcode(status) if hasattr(os, "waitstatus_to_exitcode") \
        else (status >> 8 if status >= 256 else -(status & 127))
    # ru_maxrss is bytes on Darwin and kibibytes on Linux.
    rss = ru.ru_maxrss if sys.platform == "darwin" else ru.ru_maxrss * 1024
    with open(outfile, "rb") as fh:
        txt = fh.read().decode("utf-8", "replace")
    return secs, rss, rc, txt


def build_row(row, bindir, env):
    """Build one row. Returns a dict; 'skip' names the reason when it has one."""
    script = os.path.join(HERE, "build.sh")
    t0 = time.monotonic()
    rc, txt = run(["sh", script, row, bindir])
    compile_s = time.monotonic() - t0
    if rc != 0:
        tail = " | ".join(txt.strip().splitlines()[-3:])[:400]
        return {"skip": "build failed (rc %d): %s" % (rc, tail)}
    cmd = None
    for line in txt.splitlines():
        if line.startswith("run: "):
            cmd = line[5:].strip().split()
    if not cmd:
        return {"skip": "build.sh printed no run: line"}
    art = cmd[-1]
    if not os.path.exists(art):
        return {"skip": "build.sh named a missing artefact: %s" % art}
    return {
        "run_cmd": cmd,
        "compile_s": round(compile_s, 4),
        "binary_bytes": os.path.getsize(art),
        "binary_sha256": sha256_of(art),
        "text_bytes": text_bytes(art),
    }


def cell_id(runner):
    osname = {"darwin": "macos", "linux": "linux"}.get(sys.platform, sys.platform)
    arch = platform.machine()
    arch = {"x86_64": "x86_64", "aarch64": "arm64", "arm64": "arm64"}.get(arch, arch)
    return "%s-%s-%s" % (osname, arch, runner)


def host_facts(mc):
    """Everything observable about the machine, as the tools print it."""
    # `uname -srvm` and not `uname -a`: the node name is the developer's hostname
    # and these two files are committed (docs/specs/M50.md section 5.3).
    cmds = {
        "uname -srvm": ["uname", "-s", "-r", "-v", "-m"],
        "clang": ["clang", "--version"],
        "go": ["go", "version"],
        "zig": ["zig", "version"],
        "rustc": ["rustc", "-V"],
        "dotnet": ["dotnet", "--version"],
        "mc --version": [mc, "--version"],
        "mc --host": [mc, "--host"],
        "python3": [sys.executable, "--version"],
    }
    if sys.platform == "darwin":
        cmds["cpu"] = ["sysctl", "-n", "machdep.cpu.brand_string"]
        cmds["mem"] = ["sysctl", "-n", "hw.memsize"]
        cmds["ncpu"] = ["sysctl", "-n", "hw.ncpu"]
        cmds["sw_vers"] = ["sw_vers"]
    else:
        cmds["cpu"] = ["sh", "-c", "grep -m1 'model name' /proc/cpuinfo || true"]
        cmds["mem"] = ["sh", "-c", "grep MemTotal /proc/meminfo || true"]
        cmds["ncpu"] = ["nproc"]
        cmds["os-release"] = ["sh", "-c", "cat /etc/os-release || true"]
    facts = {}
    for name, cmd in cmds.items():
        rc, txt = run(cmd)
        facts[name] = txt.strip() if rc == 0 else None
    return facts


def cpu_model(facts):
    c = facts.get("cpu")
    if not c:
        return None
    c = c.splitlines()[0].strip()
    if ":" in c and c.lower().startswith("model name"):
        c = c.split(":", 1)[1].strip()
    return c


def mem_kb(facts):
    m = facts.get("mem") or ""
    digits = re.findall(r"\d+", m)
    if not digits:
        return None
    n = int(digits[0])
    return n // 1024 if sys.platform == "darwin" else n


def main():
    ap = argparse.ArgumentParser(description="run one bench cell")
    ap.add_argument("--out", help="results directory (default build/bench-cell/<date>-<id>)")
    ap.add_argument("--reps", type=int, help="repetitions (default REPS in versions.env)")
    ap.add_argument("--rows", help="comma-separated subset of the row names")
    ap.add_argument("--phases", help="comma-separated subset of all,mix,primes,fib")
    ap.add_argument("--runner", default=os.environ.get("RUNNER_LABEL", "local"),
                    help="the runner label in the cell id (default local)")
    ap.add_argument("--run-id", default=os.environ.get("GITHUB_RUN_ID"),
                    help="the run id in the directory name")
    ap.add_argument("--mc", help="the mc binary to measure (default build/mc1, then PATH)")
    args = ap.parse_args()

    env = read_env(os.path.join(HERE, "versions.env"))
    reps = args.reps or int(env.get("REPS", "7"))
    drop = int(env.get("DROP", "1"))
    tol = float(env.get("TOLERANCE", "0.05"))
    regress_min = float(env.get("REGRESS_MIN", "1.5"))
    regress_phase = env.get("REGRESS_PHASE", "all")
    reference = env.get("REFERENCE", "c-O2")
    phases = (args.phases or env.get("PHASES", "all")).split(",")
    for ph in phases:
        if ph not in EXPECT:
            sys.exit("cell: unknown phase %s (known: %s)" % (ph, ", ".join(EXPECT)))
    want = args.rows.split(",") if args.rows else [r[0] for r in ROWS]
    rows = [r for r in ROWS if r[0] in want]
    if not rows:
        sys.exit("cell: no such row")

    mc = mc_binary(args.mc or os.environ.get("MC"))
    os.environ["MC"] = mc
    facts = host_facts(mc)
    date = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    run_id = args.run_id or time.strftime("%H%M%S", time.gmtime())
    cid = cell_id(args.runner)
    outdir = args.out or os.path.join(ROOT, "build", "bench-cell",
                                      "%s-%s" % (date[:10], run_id))
    bindir = os.path.join(outdir, "bin")
    os.makedirs(bindir, exist_ok=True)
    pin = pin_prefix()

    print("cell %s, %d repetitions (%d dropped), phases %s"
          % (cid, reps, drop, ",".join(phases)))
    print("mc      %s" % mc)
    print("pinning %s" % (" ".join(pin) if pin else "none (not Linux)"))
    print("out     %s" % outdir)
    print()

    # --- build ---------------------------------------------------------------
    built, skipped = [], []
    for name, tool, label in rows:
        probe = mc if tool == "mc" else shutil.which(tool)
        if not probe or (tool == "mc" and not os.access(mc, os.X_OK)):
            skipped.append((name, "%s is not installed on this host" % tool))
            print("skip  %-10s %s is not installed" % (name, tool))
            continue
        info = build_row(name, bindir, env)
        if "skip" in info:
            skipped.append((name, info["skip"]))
            print("skip  %-10s %s" % (name, info["skip"]))
            continue
        info.update({"row": name, "label": label, "tool": tool})
        built.append(info)
        print("build %-10s %7.3f s  %9d B  %s"
              % (name, info["compile_s"], info["binary_bytes"],
                 info["binary_sha256"][:16]))
    if not built:
        sys.exit("cell: nothing to measure")
    if not any(b["row"] == reference for b in built):
        sys.exit("cell: the reference row %s could not be built; "
                 "every verdict is a ratio to it" % reference)

    # --- time: seven repetitions, the rows interleaved inside each ------------
    plan = [(b, ph) for ph in phases for b in built]
    samples = {}
    bad = []
    print("\ntiming %d rows x %d phases x %d repetitions"
          % (len(built), len(phases), reps))
    for rep in range(1, reps + 1):
        line = []
        for b, ph in plan:
            key = (b["row"], ph)
            cmd = pin + b["run_cmd"] + ([] if ph == "all" else [ph])
            outfile = os.path.join(outdir, "stdout.tmp")
            secs, rss, rc, txt = time_once(cmd, outfile)
            ok = (rc == 0 and txt == EXPECT[ph])
            if not ok:
                bad.append((b["row"], ph, rep, rc, txt[:120]))
            s = samples.setdefault(key, {"run_s": [], "rss": [], "ok": True})
            s["run_s"].append(round(secs, 4))
            s["rss"].append(rss)
            s["ok"] = s["ok"] and ok
            if ph == phases[0]:
                line.append("%s %.3f" % (b["row"], secs))
        print("  rep %d: %s" % (rep, "  ".join(line)))
    tmp = os.path.join(outdir, "stdout.tmp")
    if os.path.exists(tmp):
        os.unlink(tmp)

    # --- statistics ----------------------------------------------------------
    def stat(key):
        s = samples[key]
        kept = s["run_s"][drop:]
        return {
            "run_s": s["run_s"],
            "best": min(kept),
            "median": statistics.median(kept),
            "max": max(kept),
            "rss_bytes": max(s["rss"][drop:]),
            "stdout_ok": s["ok"],
        }

    stats = dict((k, stat(k)) for k in samples)
    ref_median = dict((ph, stats[(reference, ph)]["median"]) for ph in phases)

    out_rows = []
    for ph in phases:
        for b in built:
            st = stats[(b["row"], ph)]
            out_rows.append({
                "row": b["row"],
                "phase": ph,
                "label": b["label"],
                "build_cmd": " ".join(["sh", "bench/cell/build.sh", b["row"], "<out>/bin"]),
                "run_cmd": " ".join(b["run_cmd"] + ([] if ph == "all" else [ph])),
                "compile_s": b["compile_s"],
                "binary_bytes": b["binary_bytes"],
                "text_bytes": b["text_bytes"],
                "binary_sha256": b["binary_sha256"],
                "stdout_ok": st["stdout_ok"],
                "run_s": st["run_s"],
                "best": st["best"],
                "median": st["median"],
                "max": st["max"],
                "rss_bytes": st["rss_bytes"],
                "ratio_to_reference": round(st["median"] / ref_median[ph], 4),
            })

    # Repetition 1 against the best of the kept ones: the measurement DROP rests
    # on. Broken down per phase, because the cold cost belongs to whichever phase
    # runs FIRST in a repetition -- that is where the binary's pages and the
    # 50 MB __bss sieve are first touched, and a later phase inside the same
    # repetition finds them warm.
    def rep1_span(rows_in):
        got = []
        for r in rows_in:
            kept_best = min(r["run_s"][drop:])
            if kept_best > 0:
                got.append(r["run_s"][0] / kept_best)
        if not got:
            return None
        return {"min": round(min(got), 3), "max": round(max(got), 3),
                "median": round(statistics.median(got), 3)}

    rep1_by_phase = dict((ph, rep1_span([r for r in out_rows if r["phase"] == ph]))
                         for ph in phases)
    rep1_all = rep1_span(out_rows)

    # The teeth: the deliberately regressed compiler is `mc --opt=0`. REGRESS_MIN
    # is calibrated for ONE phase (REGRESS_PHASE) and is meaningless on the
    # others -- M49 moves `mix` by 2.3x, `primes` by 5% and `fib` by nothing, so
    # `all` is a weighted average that lands at 1.43-1.62 against the same floor.
    # When a run was asked for a subset that excludes that phase the tooth is
    # still computed and reported, for the first phase there is, and NOT gated.
    tooth = None
    tooth_phase = regress_phase if regress_phase in phases else phases[0]
    tooth_gated = tooth_phase == regress_phase
    if all((n, tooth_phase) in stats for n in ("mc-plain", "mc-opt")):
        tooth = round(stats[("mc-plain", tooth_phase)]["median"]
                      / stats[("mc-opt", tooth_phase)]["median"], 4)

    failures = []
    for r in out_rows:
        if not r["stdout_ok"]:
            failures.append("%s/%s printed the wrong answer" % (r["row"], r["phase"]))
    if tooth is not None and tooth_gated and tooth < regress_min:
        failures.append("tooth %.3f below %.2f on phase %s (mc --opt=1 is not "
                        "beating --opt=0: the optimizer regressed)"
                        % (tooth, regress_min, tooth_phase))

    toolchains = dict((k, facts[k]) for k in
                      ("clang", "go", "zig", "rustc", "dotnet") if facts.get(k))
    for k in toolchains:
        toolchains[k] = toolchains[k].splitlines()[0]

    result = {
        "cell": {
            "id": cid,
            "os": {"darwin": "macos"}.get(sys.platform, sys.platform),
            "arch": platform.machine(),
            "runner": args.runner,
            "cpu_model": cpu_model(facts),
            "nproc": int(facts["ncpu"]) if (facts.get("ncpu") or "").isdigit() else None,
            "mem_kb": mem_kb(facts),
            "kernel": (facts.get("uname -srvm") or "").strip() or None,
            "pinned_cpus": "0" if pin else None,
            "date": date,
            "run_id": run_id,
            "workflow_ref": os.environ.get("GITHUB_REF_NAME"),
        },
        "mc": {
            "road": "tree" if os.path.abspath(mc).startswith(os.path.join(ROOT, "build")) else "path",
            "path": mc,
            "version": facts.get("mc --version"),
            # `mc --host` prints three lines; one field, so they are joined.
            "host": "; ".join((facts.get("mc --host") or "").split("\n")) or None,
            "binary_sha256": sha256_of(mc) if os.access(mc, os.R_OK) else None,
            "binary_bytes": os.path.getsize(mc) if os.access(mc, os.R_OK) else None,
        },
        "toolchains": toolchains,
        "pins": dict((k, v) for k, v in env.items()
                     if k.endswith("_VERSION") or k == "CLANG_APT"),
        "reference": reference,
        "reps": reps,
        "dropped": drop,
        "tolerance": tol,
        "regress_min": regress_min,
        "regress_phase": regress_phase,
        "regress_gated": tooth_gated,
        "tooth_phase": tooth_phase,
        "timing_method": "time.monotonic() around one process at a time, "
                         "os.wait4 for max RSS; compile_s is one build, same clock",
        "rows": out_rows,
        "skipped": [{"row": n, "reason": why} for n, why in skipped],
        "verdict": {
            "status": "fail" if failures else "ok",
            "failures": failures,
            "tooth": tooth,
            "reference_absolute_median": dict((ph, ref_median[ph]) for ph in phases),
            "rep1_over_kept_best": rep1_all,
            "rep1_over_kept_best_by_phase": rep1_by_phase,
        },
    }

    with open(os.path.join(outdir, "results.json"), "w") as f:
        json.dump(result, f, indent=1, sort_keys=False)
        f.write("\n")
    with open(os.path.join(outdir, "facts.json"), "w") as f:
        json.dump(facts, f, indent=1, sort_keys=True)
        f.write("\n")
    write_report(os.path.join(outdir, "RESULTS.md"), result, phases)

    # --- say it on stdout ----------------------------------------------------
    print()
    for ph in phases:
        print("phase %s (reference %s median %.3f s)" % (ph, reference, ref_median[ph]))
        for r in out_rows:
            if r["phase"] != ph:
                continue
            print("  %-10s median %7.3f s  best %7.3f  ratio %6.3f%s"
                  % (r["row"], r["median"], r["best"], r["ratio_to_reference"],
                     "" if r["stdout_ok"] else "  WRONG ANSWER"))
    print()
    if rep1_all:
        print("repetition 1 / best of the kept: %.2fx to %.2fx (median %.2fx) -- dropped"
              % (rep1_all["min"], rep1_all["max"], rep1_all["median"]))
        for ph in phases:
            s = rep1_by_phase[ph]
            print("  phase %-7s %.2fx to %.2fx (median %.2fx)%s"
                  % (ph, s["min"], s["max"], s["median"],
                     "  <- run first in each repetition" if ph == phases[0] else ""))
    if tooth is not None:
        print("tooth  mc-plain / mc-opt on %s: %.3f (%s)"
              % (tooth_phase, tooth,
                 "floor %.2f" % regress_min if tooth_gated else
                 "not gated: the floor is calibrated for phase %s" % regress_phase))
    for n, why in skipped:
        print("skipped %-10s %s" % (n, why))
    print("wrote  %s/{results.json,facts.json,RESULTS.md}" % outdir)
    if failures:
        for f in failures:
            print("FAIL   %s" % f, file=sys.stderr)
        return 1
    print("ok     %d rows x %d phases, verdict ok" % (len(built), len(phases)))
    return 0


def write_report(path, res, phases):
    c, mc = res["cell"], res["mc"]
    L = []
    L.append("# Bench cell run %s, %s\n" % (c["id"], c["date"]))
    L.append("Written by `bench/cell/cell.py` (M50 step A). Absolute seconds are recorded and")
    L.append("never gated; the verdict is the ratio of per-row medians to `%s`, built and timed"
             % res["reference"])
    L.append("in this same run. See [`../cell/README.md`](../cell/README.md) for the protocol.\n")
    L.append("| | |")
    L.append("|---|---|")
    L.append("| cell | `%s` |" % c["id"])
    L.append("| cpu | %s |" % (c["cpu_model"] or "?"))
    L.append("| nproc / mem | %s / %s kB |" % (c["nproc"], c["mem_kb"]))
    L.append("| kernel | `%s` |" % (c["kernel"] or "?"))
    L.append("| pinned cpus | %s |" % (c["pinned_cpus"] or "none (not Linux)"))
    L.append("| mc | `%s`, `%s` |" % (mc["version"], mc["host"]))
    L.append("| mc sha256 | `%s` (%s B) |" % (mc["binary_sha256"], mc["binary_bytes"]))
    L.append("| reps | %d, first %d dropped |" % (res["reps"], res["dropped"]))
    L.append("| tolerance / floor | %s / %s on `%s`%s |"
             % (res["tolerance"], res["regress_min"], res["regress_phase"],
                "" if res["regress_gated"] else " (not gated: that phase was not run)"))
    L.append("| verdict | **%s** |" % res["verdict"]["status"])
    L.append("")
    L.append("Toolchains, as the tools print them:\n")
    for k, v in sorted(res["toolchains"].items()):
        L.append("* `%s`: %s" % (k, v))
    L.append("")
    for ph in phases:
        ref = res["verdict"]["reference_absolute_median"][ph]
        L.append("## Phase `%s` (reference median %.3f s)\n" % (ph, ref))
        L.append("| row | variant | median s | best s | max s | ratio | run RSS | compile s | binary B | `__text` B |")
        L.append("|---|---|---|---|---|---|---|---|---|---|")
        for r in res["rows"]:
            if r["phase"] != ph:
                continue
            L.append("| `%s` | %s | %.3f | %.3f | %.3f | %.3f | %d | %.3f | %d | %s |"
                     % (r["row"], r["label"], r["median"], r["best"], r["max"],
                        r["ratio_to_reference"], r["rss_bytes"], r["compile_s"],
                        r["binary_bytes"],
                        r["text_bytes"] if r["text_bytes"] is not None else "-"))
        L.append("")
    v = res["verdict"]
    L.append("## Verdict\n")
    L.append("* tooth `mc-plain / mc-opt` on `%s`: **%s** (%s)"
             % (res["tooth_phase"], v["tooth"],
                "floor %s" % res["regress_min"] if res["regress_gated"] else
                "reported, not gated: the floor is calibrated for phase `%s`"
                % res["regress_phase"]))
    r1 = v["rep1_over_kept_best"]
    L.append("* repetition 1 against the best of the kept: %sx to %sx, median %sx -- which is why it is dropped"
             % (r1["min"], r1["max"], r1["median"]))
    for ph in phases:
        s = v["rep1_over_kept_best_by_phase"][ph]
        L.append("  * phase `%s`: %sx to %sx, median %sx%s"
                 % (ph, s["min"], s["max"], s["median"],
                    " (run first in each repetition, so it pays the cold pages)"
                    if ph == phases[0] else ""))
    L.append("* every repetition of every row printed the workload's recorded answer: %s"
             % ("yes" if all(r["stdout_ok"] for r in res["rows"]) else "**no**"))
    if res["skipped"]:
        L.append("")
        L.append("Skipped rows (never faked):\n")
        for s in res["skipped"]:
            L.append("* `%s`: %s" % (s["row"], s["reason"]))
    for f in v["failures"]:
        L.append("")
        L.append("**FAIL**: %s" % f)
    L.append("")
    with open(path, "w") as fh:
        fh.write("\n".join(L))


if __name__ == "__main__":
    sys.exit(main())
