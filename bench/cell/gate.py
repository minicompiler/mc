#!/usr/bin/env python3
"""bench/cell/gate.py -- the cell's verdict against the committed history (M50 step C).

One invocation reads a FRESH results.json (or a directory of them, which is what
`cell.py --merge` writes) and, for every cell id in it, answers three questions
against the newest COMMITTED run of that same cell id under bench/results/:

  * GATE -- did a row print the wrong answer, and is the tooth
    (median(mc-plain) / median(mc-opt) on REGRESS_PHASE) still at or above
    REGRESS_MIN for this architecture? Non-zero exit if not. That is the plan
    row's "a deliberately regressed `mc` build fails the cell", and it is the
    ONLY thing gated, because it is the only comparison the measurements support:
    both medians come from the SAME job of the SAME run, and step B measured that
    ratio drifting 0.13% (linux-arm64), 1.6% (linux-x86_64) and 5.1%
    (macos-arm64) between two consecutive runs.
  * REPORT -- how far each row's `ratio_to_reference` moved from the committed
    run's, with TOLERANCE as the band. NOT gated, and the reason is a
    measurement, not caution: the reference is timed once per JOB, and between
    step B's two consecutive runs a job's own reference median moved +31.81%
    (macos-arm64's mc job), -23.57% (its go job) and -13.27% (linux-x86_64's mc
    job), while inside ONE run the six per-job references of macos-arm64 spanned
    0.556 to 0.719 s for the same clang -O2 binary. A row's ratio carries its own
    job's reference noise, so comparing it across runs adds two independent
    samples of runner load instead of cancelling them -- TOLERANCE = 0.05 held on
    one of the three cells (docs/specs/M50.md § Implementation notes -- step B,
    item 6, which is what sends this band here as a report).
  * NOTE -- the reference row's own absolute median, against the committed run's,
    with a 10% threshold (D15). Never gating: the same unchanged clang -O2 binary
    of this program has timed 0.420 s, 0.49 s and 0.52-0.56 s in three sessions
    on one Mac. It says whether the machine was the same one, which is the honest
    replacement for the "shared host load" caveat rather than a claim of quiet.
    A changed CPU model or runner image is reported beside it (risk 2 happened on
    the cell's first day: ubuntu-latest came up as an AMD EPYC 7763 and, twenty
    minutes later, as an Intel Xeon 8573C).

A cell id with nothing committed yet says "baseline recorded" and exits 0 (§ 4.5,
risk 6): the x86-64 cell's first run is a baseline, and reading a regression into
the only data point would be reading it into nothing.

The thresholds are read from bench/cell/versions.env and NOT from the run being
gated: a gate that took its floor out of its own artefact would pass whatever the
artefact claimed.

Python 3 standard library only. Not part of `make check`.
"""

import argparse
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# D15: the reference's absolute median is the machine's health indicator, and
# this is the threshold at which the run says the machine moved.
HEALTH = 0.10


def read_env(path):
    """KEY=value lines, '#' comments -- the same three lines cell.py uses."""
    out = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip()
    return out


def norm_arch(a):
    return {"aarch64": "arm64"}.get(a, a)


def load(path):
    """Every results.json at or under `path`, skipping the ones cell.py skips."""
    if os.path.isfile(path):
        cands = [path]
    else:
        cands = sorted(glob.glob(os.path.join(path, "**", "results.json"),
                                 recursive=True))
        if os.path.exists(os.path.join(path, "results.json")):
            cands.append(os.path.join(path, "results.json"))
    out = []
    for p in dict.fromkeys(cands):
        with open(p) as f:
            r = json.load(f)
        if "cell" in r and "rows" in r:
            out.append((p, r))
    return out


def newest_committed(history, cid, skip_run_id):
    """The newest committed run of this cell id, by its dated directory name.

    bench/results/<date>-<run-id>/<cell id>/results.json (§ 5.1): the directory
    name sorts by date and then by run id, which is the order the runs happened
    in. A directory carrying the run id being gated is skipped, so gating a run
    that has already been committed compares it against the one before it.
    """
    best = None
    for d in sorted(os.listdir(history)) if os.path.isdir(history) else []:
        p = os.path.join(history, d, cid, "results.json")
        if not os.path.exists(p):
            continue
        with open(p) as f:
            r = json.load(f)
        if str(r["cell"].get("run_id")) == str(skip_run_id):
            continue
        best = (d, p, r)
    return best


def ratios(res):
    """(row, phase) -> the ratio that row's OWN job measured in this run."""
    return dict(((r["row"], r["phase"]), r["ratio_to_reference"])
                for r in res["rows"] if r.get("ratio_to_reference"))


def annotate(kind, msg):
    """A GitHub annotation when there is a GitHub to annotate, plain text else."""
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print("::%s::%s" % (kind, msg))
    else:
        print("%-6s %s" % (kind, msg))


def drift(new, old):
    return (new - old) / old if old else 0.0


def gate_one(res, env, history):
    """Gate and report ONE cell run. Returns the list of gate failures."""
    c = res["cell"]
    cid = c["id"]
    arch = norm_arch(c.get("arch") or "")
    floor = float(env.get("REGRESS_MIN_" + arch.upper(),
                          env.get("REGRESS_MIN", "1.5")))
    tol = float(env.get("TOLERANCE", "0.05"))
    phase = env.get("REGRESS_PHASE", "mix")

    print()
    print("=== %s   %s   mc %s   run %s"
          % (cid, c.get("date"), (res["mc"].get("version") or "?"), c.get("run_id")))
    print("    cpu %s, image %s, pinned cpus %s"
          % (c.get("cpu_model") or "not reported", c.get("image") or "?",
             c.get("pinned_cpus") or "none"))

    fails = []

    # --- gate: a row that printed the wrong number is not a fast row ---------
    for f in res["verdict"].get("failures", []):
        if "wrong answer" in f or "printed the wrong" in f:
            fails.append(f)

    # --- gate: the teeth -----------------------------------------------------
    tooth = res["verdict"].get("tooth")
    if tooth is None:
        annotate("warning", "%s: no tooth (the mc rows did not both run)" % cid)
    elif res.get("tooth_phase") != phase or not res.get("regress_gated", True):
        annotate("notice", "%s: tooth %.3f on phase %s -- not gated, the floor is "
                           "calibrated for %s" % (cid, tooth, res.get("tooth_phase"), phase))
    elif tooth < floor:
        fails.append("tooth %.3f below %.2f on phase %s (mc --opt=1 is not beating "
                     "--opt=0: the optimizer regressed)" % (tooth, floor, phase))
    else:
        print("    tooth  %.3f on phase %s, floor %.2f -- ok (+%.0f%% of margin)"
              % (tooth, phase, floor, 100.0 * (tooth / floor - 1.0)))

    prev = newest_committed(history, cid, c.get("run_id"))
    if prev is None:
        print("    baseline recorded: nothing committed for %s under %s"
              % (cid, os.path.relpath(history, ROOT)))
        return fails
    pdir, ppath, old = prev
    print("    compared to %s (mc %s, cpu %s)"
          % (pdir, old["mc"].get("version") or "?",
             old["cell"].get("cpu_model") or "not reported"))

    # --- note: is this the same machine? (risk 2, D15) ----------------------
    if (old["cell"].get("cpu_model") or None) != (c.get("cpu_model") or None):
        annotate("notice", "%s: the CPU model changed, %s -> %s: the ratios survive "
                           "it, the absolute seconds do not"
                 % (cid, old["cell"].get("cpu_model") or "not reported",
                    c.get("cpu_model") or "not reported"))
    if (old["cell"].get("image") or None) != (c.get("image") or None):
        annotate("notice", "%s: the runner image changed, %s -> %s"
                 % (cid, old["cell"].get("image"), c.get("image")))

    oref = old["verdict"].get("reference_absolute_median") or {}
    nref = res["verdict"].get("reference_absolute_median") or {}
    for ph in sorted(set(oref) & set(nref)):
        d = drift(nref[ph], oref[ph])
        if abs(d) > HEALTH:
            annotate("notice", "%s: the machine moved: %s %s %.3f s -> %.3f s (%+.1f%%) "
                               "-- recorded, never gated"
                     % (cid, res["reference"], ph, oref[ph], nref[ph], 100.0 * d))

    # --- report: the cross-run band on every row's in-job ratio -------------
    new, prevr = ratios(res), ratios(old)
    shared = sorted(set(new) & set(prevr))
    if not shared:
        annotate("warning", "%s: no row in common with %s" % (cid, pdir))
        return fails
    over, worst = [], None
    for key in shared:
        d = drift(new[key], prevr[key])
        if worst is None or abs(d) > abs(worst[1]):
            worst = (key, d)
        if abs(d) > tol:
            over.append((key, d))
    print("    %d rows in common, worst %s/%s %+.2f%%, %d over the %.0f%% band"
          % (len(shared), worst[0][0], worst[0][1], 100.0 * worst[1],
             len(over), 100.0 * tol))
    # the worst five and a count: a report of eighteen identical lines is a
    # report nobody reads, and the whole set is in the two results.json files.
    for (row, ph), d in sorted(over, key=lambda x: -abs(x[1]))[:5]:
        annotate("notice", "%s: %s/%s ratio %.3f -> %.3f (%+.1f%%), over the %.0f%% "
                           "band -- a report, not a gate (a row's ratio carries its "
                           "own job's reference noise)"
                 % (cid, row, ph, prevr[(row, ph)], new[(row, ph)],
                    100.0 * d, 100.0 * tol))
    return fails


def main():
    ap = argparse.ArgumentParser(description="gate one bench cell run against "
                                             "the committed history")
    ap.add_argument("fresh", nargs="?",
                    help="a results.json, or a directory holding them "
                         "(default: the newest run under build/bench-cell)")
    ap.add_argument("--history", default=os.path.join(ROOT, "bench", "results"),
                    help="where the committed runs live (default bench/results)")
    ap.add_argument("--env", default=os.path.join(HERE, "versions.env"),
                    help="the thresholds (default bench/cell/versions.env)")
    args = ap.parse_args()

    fresh = args.fresh
    if not fresh:
        # the local road's own output root: `make bench-cell` writes
        # build/bench-cell/<date>-<cell id>/ and gates the one it just wrote.
        local = os.path.join(ROOT, "build", "bench-cell")
        runs = sorted(glob.glob(os.path.join(local, "*")))
        if not runs:
            sys.exit("gate: nothing under %s and no path given "
                     "(run `make bench-cell` first)" % local)
        fresh = runs[-1]

    found = load(fresh)
    if not found:
        sys.exit("gate: no results.json at or under %s" % fresh)
    env = read_env(args.env)

    fails = []
    for path, res in found:
        for f in gate_one(res, env, args.history):
            fails.append("%s: %s" % (res["cell"]["id"], f))

    print()
    if fails:
        for f in fails:
            annotate("error", f)
        print("FAIL   %d cell run(s) gated, %d failure(s)" % (len(found), len(fails)),
              file=sys.stderr)
        return 1
    print("ok     %d cell run(s) gated, no failures" % len(found))
    return 0


if __name__ == "__main__":
    sys.exit(main())
