#!/bin/sh
# bootstrap.sh — M7: fixed point of the self-hosted compiler.
#
#   build/mc0 src/mc_seed.mc -> build/mc_seed.o  (+ link -> build/mc_seed)
#   build/mc_seed src/mc.mc  -> build/mc1.o      (+ link -> build/mc1)
#   build/mc1 src/mc.mc -> build/mc2.o  (+ link -> build/mc2)
#   build/mc2 src/mc.mc -> build/mc3.o
#   cmp build/mc2.o build/mc3.o         <- the criterion (not mc1.o vs mc2.o:
#                                          those may differ, they are different
#                                          compilers — clang vs mc1)
#   SHA-256 of build/mc2.o compared against the golden checked into
#   tests/golden/mc2.sha256 (recorded the first time the script runs).
#
# Bootstrap decoupling: mc0 (the frozen C seed, fixed 64 MiB arena) no longer
# compiles the whole src/mc.mc — compiling it already touches ~57 MiB, so the
# compiler cannot keep growing through mc0. mc0 now compiles only the minimal
# seed core (src/mc_seed.mc: <mc/core_min> + arm64 + macho, ~15 MiB), and the
# seed compiler — which carries the same growable, mmap-backed arena every mc1+
# has — compiles the full src/mc.mc on its own. The seed and the full compiler
# share the same codegen source, so build/mc1.o is byte for byte what mc0 used
# to produce directly, and the fixed point and golden below are unchanged.
#
# M49 adds a SECOND chain, the optimized road (docs/specs/M49.md § 3.3):
#
#   build/mc1  --opt=1 src/mc.mc -> build/mc2o.o  (+ link -> build/mc2o)
#   build/mc2o --opt=1 src/mc.mc -> build/mc3o.o
#   cmp build/mc2o.o build/mc3o.o       <- the optimized road's fixed point
#   SHA-256 of build/mc2o.o against tests/golden/mc2-opt.sha256
#   build/mc2o         src/mc.mc -> build/mc2o-plain.o
#   cmp build/mc2o-plain.o build/mc2.o  <- the CROSS-ROAD IDENTITY: an
#                                          optimized compiler computes exactly
#                                          the compiler the plain one computes
#
# It is skipped, with a message, when the compiler under test does not
# understand `--opt=` -- the frozen seed does not, and neither does any release
# older than M49, so `scripts/bootstrap.sh` keeps working with an old seed.
#
# No "set -e": each step checks its own exit code and fails with a clear
# message, so a failure in the middle of the chain never passes silently.

mc0="build/mc0"
golden="tests/golden/mc2.sha256"
golden_opt="tests/golden/mc2-opt.sha256"

if [ ! -x "$mc0" ]; then
    echo "FAIL: '$mc0' not found or not executable (run 'make stage0')" >&2
    exit 1
fi
if [ ! -f "src/mc.mc" ]; then
    echo "FAIL: src/mc.mc not found" >&2
    exit 1
fi
if [ ! -f "src/mc_seed.mc" ]; then
    echo "FAIL: src/mc_seed.mc not found" >&2
    exit 1
fi

# now() prints the clock with millisecond precision. The shell's 'time' can't
# be captured in a format that's portable across 'sh' and reused in the total;
# and GNU coreutils' 'date +%s.%N' doesn't exist in macOS's BSD date (%N isn't
# supported). perl is always installed on macOS and has Time::HiRes: we use it.
now() {
    perl -MTime::HiRes=time -e 'printf "%.3f\n", time'
}

# dt A B -> "B - A" with 3 decimal places.
dt() {
    perl -e 'printf "%.3f", '"$2"' - '"$1"''
}

fails=0
t_total0=$(now)

# step DESCRIPTION CMD... — runs CMD, times it, fails with a clear message if
# the exit code isn't 0. Doesn't use set -e: the 'if' itself captures the status.
step() {
    desc="$1"; shift
    t0=$(now)
    if ! "$@" >"$tmp_out" 2>"$tmp_err"; then
        rc=$?
        echo "FAIL: $desc (exit $rc)" >&2
        echo "--- command: $* ---" >&2
        cat "$tmp_out" "$tmp_err" >&2
        exit 1
    fi
    t1=$(now)
    echo "  $desc: $(dt "$t0" "$t1")s"
    cat "$tmp_out"
}

tmp_out="${TMPDIR:-/tmp}/bootstrap.$$.out"
tmp_err="${TMPDIR:-/tmp}/bootstrap.$$.err"
trap 'rm -f "$tmp_out" "$tmp_err"' EXIT

size_of() {
    # size in bytes, portable (BSD stat on macOS uses -f%z; GNU uses -c%s).
    wc -c < "$1" | tr -d ' '
}

echo "=== M7 -- fixed point: mc0 -> mc_seed -> mc1 -> mc2 -> mc3 ==="

echo "-- stage 0: build/mc0 src/mc_seed.mc -> build/mc_seed.o --"
step "mc0 compiles mc_seed.mc" "$mc0" src/mc_seed.mc -o build/mc_seed.o
echo "  size build/mc_seed.o: $(size_of build/mc_seed.o) bytes"
step "link build/mc_seed"     scripts/link.sh build/mc_seed build/mc_seed.o

echo "-- stage 1: build/mc_seed src/mc.mc -> build/mc1.o --"
step "mc_seed compiles mc.mc"  build/mc_seed src/mc.mc -o build/mc1.o
echo "  size build/mc1.o: $(size_of build/mc1.o) bytes"
step "link build/mc1"         scripts/link.sh build/mc1 build/mc1.o

echo "-- stage 2: build/mc1 src/mc.mc -> build/mc2.o --"
step "mc1 compiles mc.mc"      build/mc1 src/mc.mc -o build/mc2.o
echo "  size build/mc2.o: $(size_of build/mc2.o) bytes"
step "link build/mc2"         scripts/link.sh build/mc2 build/mc2.o

echo "-- stage 3: build/mc2 src/mc.mc -> build/mc3.o --"
step "mc2 compiles mc.mc"      build/mc2 src/mc.mc -o build/mc3.o
echo "  size build/mc3.o: $(size_of build/mc3.o) bytes"

echo "-- fixed-point criterion: cmp build/mc2.o build/mc3.o --"
if ! cmp build/mc2.o build/mc3.o; then
    echo "FAIL: build/mc2.o != build/mc3.o -- no fixed point" >&2
    echo "diagnosis: diff <(build/mc1 --dump-asm src/mc.mc) <(build/mc2 --dump-asm src/mc.mc)" >&2
    echo "then bisect by file/function (see docs/bootstrap.md)" >&2
    exit 1
fi
echo "  ok: build/mc2.o == build/mc3.o"

echo "-- golden SHA-256 of build/mc2.o --"
got_line=$(shasum -a 256 build/mc2.o)
got_hash=$(printf '%s\n' "$got_line" | awk '{print $1}')
mkdir -p "$(dirname "$golden")"
if [ ! -f "$golden" ]; then
    printf '%s\n' "$got_line" > "$golden"
    echo "  WARNING: $golden did not exist -- recorded now with the current hash:"
    echo "  $got_line"
else
    want_hash=$(awk '{print $1}' "$golden")
    if [ "$got_hash" != "$want_hash" ]; then
        echo "FAIL: build/mc2.o diverges from the golden $golden" >&2
        echo "  expected: $want_hash" >&2
        echo "  got:      $got_hash" >&2
        echo "  (if the change in src/*.mc or in codegen was intentional, review the" >&2
        echo "  --dump-asm diff and rewrite the golden -- see tests/golden/README.md)" >&2
        exit 1
    fi
    echo "  ok: $got_hash matches $golden"
fi

# ---- M49: the optimized road, and the cross-road identity ------------------
# The plain chain above is the reference and never takes a flag. This one is the
# same three stages with `--opt=1`, plus the one line that makes the whole
# milestone falsifiable: the optimized compiler, asked for the PLAIN road, has
# to write byte for byte the object the plain compiler wrote. A miscompiled
# allocator anywhere in the 1745 functions of src/mc.mc shows up there.
if build/mc1 --opt=0 --version > /dev/null 2>&1; then
    echo ""
    echo "=== M49 -- the optimized road: mc1 -O -> mc2o -> mc3o ==="

    echo "-- stage 2o: build/mc1 --opt=1 src/mc.mc -> build/mc2o.o --"
    step "mc1 -O compiles mc.mc"   build/mc1 --opt=1 src/mc.mc -o build/mc2o.o
    echo "  size build/mc2o.o: $(size_of build/mc2o.o) bytes"
    step "link build/mc2o"        scripts/link.sh build/mc2o build/mc2o.o

    echo "-- stage 3o: build/mc2o --opt=1 src/mc.mc -> build/mc3o.o --"
    step "mc2o -O compiles mc.mc"  build/mc2o --opt=1 src/mc.mc -o build/mc3o.o
    echo "  size build/mc3o.o: $(size_of build/mc3o.o) bytes"

    echo "-- fixed-point criterion: cmp build/mc2o.o build/mc3o.o --"
    if ! cmp build/mc2o.o build/mc3o.o; then
        echo "FAIL: build/mc2o.o != build/mc3o.o -- no fixed point on the optimized road" >&2
        echo "diagnosis: diff <(build/mc1 --dump-asm --opt=1 src/mc.mc) <(build/mc2o --dump-asm --opt=1 src/mc.mc)" >&2
        exit 1
    fi
    echo "  ok: build/mc2o.o == build/mc3o.o"

    echo "-- golden SHA-256 of build/mc2o.o --"
    got_line=$(shasum -a 256 build/mc2o.o)
    got_hash=$(printf '%s\n' "$got_line" | awk '{print $1}')
    if [ ! -f "$golden_opt" ]; then
        printf '%s\n' "$got_line" > "$golden_opt"
        echo "  WARNING: $golden_opt did not exist -- recorded now with the current hash:"
        echo "  $got_line"
    else
        want_hash=$(awk '{print $1}' "$golden_opt")
        if [ "$got_hash" != "$want_hash" ]; then
            echo "FAIL: build/mc2o.o diverges from the golden $golden_opt" >&2
            echo "  expected: $want_hash" >&2
            echo "  got:      $got_hash" >&2
            exit 1
        fi
        echo "  ok: $got_hash matches $golden_opt"
    fi

    echo "-- cross-road identity: build/mc2o src/mc.mc == build/mc2.o --"
    step "mc2o compiles mc.mc plain" build/mc2o src/mc.mc -o build/mc2o-plain.o
    if ! cmp build/mc2o-plain.o build/mc2.o; then
        echo "FAIL: the optimized compiler does not compute the plain compiler" >&2
        echo "diagnosis: diff <(build/mc2 --dump-asm src/mc.mc) <(build/mc2o --dump-asm src/mc.mc)" >&2
        exit 1
    fi
    echo "  ok: build/mc2o-plain.o == build/mc2.o"
else
    echo ""
    echo "=== M49 -- the optimized road: SKIPPED (build/mc1 does not accept --opt=) ==="
fi

t_total1=$(now)
echo "=== total bootstrap time: $(dt "$t_total0" "$t_total1")s ==="

echo ""
echo "=== scripts/test.sh build/mc2 ==="
if ! scripts/test.sh build/mc2; then
    echo "FAIL: scripts/test.sh build/mc2" >&2
    fails=1
fi

echo ""
echo "=== scripts/check-obj.sh build/mc1 build/mc2 ==="
if ! scripts/check-obj.sh build/mc1 build/mc2; then
    echo "FAIL: scripts/check-obj.sh build/mc1 build/mc2" >&2
    fails=1
fi

[ "$fails" -eq 0 ]
