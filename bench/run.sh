#!/bin/sh
# bench/run.sh -- a portable, quick sanity run of the mc half of both
# benchmarks: needs only build/mc1 and clang (both already required by
# `make check`), not Go/Zig/Rust/.NET. It builds the workload and the three
# mc HTTP servers, checks their output/response against the recorded
# contract, and prints where the full multi-language measurement lives.
# Not part of `make check` (hardware- and toolchain-dependent); see
# `make bench` and bench/README.md.
set -e
cd "$(dirname "$0")/.."
mc=build/mc1
[ -x "$mc" ] || { echo "bench: $mc not found; run 'make mc1' first" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "== workload (bench/mc/bench.mc) =="
t0=$(perl -MTime::HiRes=time -e 'print time' 2>/dev/null || echo 0)
"$mc" --exe bench/mc/bench.mc -o "$tmp/bench-mc"
t1=$(perl -MTime::HiRes=time -e 'print time' 2>/dev/null || echo 0)
out=$("$tmp/bench-mc")
want='8128903901837660708
3001134
39088169'
if [ "$out" = "$want" ]; then
    echo "ok: stdout matches the recorded cross-check"
else
    echo "FAIL: unexpected stdout:" >&2
    echo "$out" >&2
    exit 1
fi
if [ "$t0" != 0 ]; then
    perl -e "printf(\"compile: %.3f s\n\", $t1 - $t0)"
fi
ls -l "$tmp/bench-mc" | awk '{print "binary: " $5 " bytes"}'

echo
echo "== HTTP servers (bench/http/mc/*.mc) =="
mkdir -p "$tmp/bin"
for s in serial fork1 forkka; do
    "$mc" --exe --include=bench/http/mc/macos "bench/http/mc/$s.mc" -o "$tmp/bin/mc-$s"
done
port=18700
for s in serial fork1 forkka; do
    port=$((port + 1))
    "$tmp/bin/mc-$s" "$port" >/dev/null 2>&1 &
    pid=$!
    ok=0
    for _ in $(seq 1 50); do
        if curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/" 2>/dev/null | grep -q 200; then
            ok=1; break
        fi
        sleep 0.05
    done
    body=$(curl -s "http://127.0.0.1:$port/" 2>/dev/null || echo "")
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    if [ "$ok" = 1 ] && [ "$body" = "hello, world" ]; then
        echo "ok: mc-$s answers the contract"
    else
        echo "FAIL: mc-$s did not answer 200 'hello, world'" >&2
        exit 1
    fi
done

echo
echo "Full multi-language measurement (Go/Zig/Rust/C#/C, ab/oha load): see bench/README.md"
echo "and RESULTS.md / http/RESULTS.md for the numbers already recorded on this project's host."
