#!/bin/sh
# check-limits.sh [MC] — the seed guard of M23 (docs/specs/M23.md, § Seed guard),
# re-pointed by the bootstrap decoupling (see docs/build.md § check-limits).
#
# `src/*.mc` has no MAX* left: every table grows on demand. `stage0/*.c` still
# has its fixed ceilings, and stage0 has to keep compiling exactly one program.
# Since the bootstrap decoupling that program is NO LONGER the full `src/mc.mc`
# — `build/mc0` compiles the minimal seed core `src/mc_seed.mc`, and the seed
# compiler it produces (on its own growable, mmap-backed arena) is what compiles
# the full `src/mc.mc`. So the seed-headroom guard measures `src/mc_seed.mc`,
# the thing mc0 actually compiles: it is the early warning the architect lacked
# at M15, and it FAILS when the seed core uses more than 90% of any fixed
# ceiling.
#
# The full `src/mc.mc` is bounded by the DYNAMIC arena (M23 mmap + the
# `src/limits.mc` pre-scan), not by stage0's fixed arrays, so gating it on those
# arrays would be a false ceiling — exactly the one the decoupling removes. It
# gets an INFORMATIONAL `mc limits src/mc.mc` report below: the full compiler's
# dynamic-arena verdict (ok / grew / tight), which never fails the build.
#
# M17 added the seventeenth row, the one whose absence cost a milestone: the
# ARENA. Every MAX* table was under 57% when `build/mc0` started dying with
# `arena exhausted`, because the thing that was full is not a table -- it is
# `HEAP_SIZE` in stage0/arena.c, and the seed's growable arrays double and never
# free (`nodes_grow` in stage0/ast.c leaves every earlier copy behind, which is
# most of what is resident). See docs/build.md § limits.
#
# The verdict `mc limits` itself returns (0 / 3) is NOT what decides the gate:
# this check is about the seed's headroom, not about how good the estimate was.
mc="${1:-build/mc1}"

if [ ! -x "$mc" ]; then
    echo "FAIL: compiler '$mc' not found or not executable"
    exit 1
fi

tmp="${TMPDIR:-/tmp}/check-limits.$$"
# Under Git Bash on Windows, MSYS hands TMPDIR to this shell in /d/... form, a
# path the native mc cannot open; cygpath -m gives D:/... which both accept.
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) tmp=$(cygpath -m "$tmp") ;; esac
mkdir -p "$tmp"

# The seed guard measures the program mc0 compiles: src/mc_seed.mc. exit 3 means
# `grew`/`tight`, which is a report, not a failure; only a real compile error
# (1, or anything else) stops us.
seed_src="src/mc_seed.mc"
"$mc" limits "$seed_src" > "$tmp/o" 2>&1
rc=$?
if [ "$rc" != 0 ] && [ "$rc" != 3 ]; then
    echo "FAIL: $mc limits $seed_src exited $rc"
    sed -n '1,10p' "$tmp/o"
    rm -rf "$tmp"
    exit 1
fi

# used count of one table in the seed report
used() {
    awk -v t="$1" '$1 == t { print $4 }' "$tmp/o"
}

# value of a #define in the seed's C sources
seed() {
    grep -h "^#define $1[[:space:]]" stage0/mc.h stage0/*.c 2>/dev/null |
        head -1 | awk '{ print $3 }'
}

# HEAP_SIZE is written `(64u << 20)`, so it needs its own reader
heap_bytes() {
    grep -h '^#define HEAP_SIZE' stage0/arena.c 2>/dev/null |
        sed -E 's/.*\(([0-9]+)u? *<< *([0-9]+)\).*/\1 \2/' |
        awk '{ printf "%d", $1 * (2 ^ $2) }'
}

# The seed cannot report its own high-water mark, and instrumenting it would be
# a change to the frozen seed. The proxy is the maximum resident set size of one
# real run of the thing mc0 compiles now, src/mc_seed.mc: the arena is a bss
# array, so only the pages the bump allocator actually touched are resident,
# plus a megabyte or two of the binary itself. It over-reports a little, which
# is the safe direction for a guard.
seed_rss() {
    out=$(/usr/bin/time -l build/mc0 "$seed_src" -o "$tmp/seed.o" 2>&1 >/dev/null)
    v=$(printf '%s\n' "$out" | awk '/maximum resident set size/ { print $1 }')
    if [ -z "$v" ]; then                          # GNU time, in kilobytes
        v=$(printf '%s\n' "$out" | awk -F': *' '/Maximum resident set size/ { print $2 * 1024 }')
    fi
    printf '%s' "$v"
}

fails=0
total=0

# table in `mc limits` -> constant in stage0. Tables the seed grows on demand
# (nodes, symbols, msecs) have no constant and are left out on purpose.
check() {
    total=$((total + 1))
    u=$(used "$1")
    c=$(seed "$2")
    if [ -z "$u" ] || [ -z "$c" ]; then
        echo "FAIL $1: no usage ('$u') or no $2 in stage0 ('$c')"
        fails=$((fails + 1)); return
    fi
    pct=$((u * 100 / c))
    if [ "$pct" -gt 90 ]; then
        echo "FAIL $1: $u/$c = $pct% of the seed's $2 (over 90%)"
        fails=$((fails + 1)); return
    fi
    printf 'ok   %-9s %6s / %-6s %3s%%  (%s)\n' "$1" "$u" "$c" "$pct" "$2"
}

echo "seed guard: $seed_src (what build/mc0 compiles) vs stage0's fixed MAX*"
check tokens   MAXTOK
check includes MAXINC
check opens    MAXOPEN
check defines  MAXDEFS
check infix    MAXOPS
check prefix   MAXOPS
check opcodes  MAXOPCS
check sections MAXSECS
check rules    MAXRULES
check funcs    MAXFUNCS
check lowered  MAXFUNCS
check globals  MAXGLOBALS
check strings  MAXSTRS
check locals   MAXLOCALS
check loops    MAXLOOPS
check prel     MAXPREL

# the arena, in bytes rather than elements
check_heap() {
    total=$((total + 1))
    c=$(heap_bytes)
    if [ -z "$c" ]; then
        echo "FAIL heap: HEAP_SIZE is not in stage0/arena.c"
        fails=$((fails + 1)); return
    fi
    # M37: the seed is a macOS program and there is no build/mc0 on a Linux
    # host. The row measures the SEED's arena, so on a host that cannot run it
    # the honest answer is that it was not measured, not a failure -- the macOS
    # job in CI is what guards this ceiling.
    if [ ! -x build/mc0 ]; then
        echo "ok   heap      SKIPPED (no build/mc0 on this host: the C seed is macOS-only)"
        return
    fi
    u=$(seed_rss)
    if [ -z "$u" ]; then
        echo "ok   heap      SKIPPED (no /usr/bin/time -l on this system)"
        return
    fi
    pct=$((u * 100 / c))
    if [ "$pct" -gt 90 ]; then
        echo "FAIL heap: $u/$c = $pct% of the seed's HEAP_SIZE (over 90%)"
        echo "     the C seed can no longer compile $seed_src for much longer;"
        echo "     raise HEAP_SIZE in stage0/arena.c (see docs/build.md § limits)"
        fails=$((fails + 1)); return
    fi
    printf 'ok   %-9s %6s / %-6s %3s%%  (%s)\n' heap \
        "$((u / 1048576))Mi" "$((c / 1048576))Mi" "$pct" "HEAP_SIZE, max RSS of build/mc0"
}

check_heap

echo "$((total - fails))/$total seed limits under 90%"

# INFORMATIONAL: the full src/mc.mc under its DYNAMIC arena. This is the right
# watch for the full compiler now (M23: mmap-backed arena + the pre-scan), and
# it does NOT gate the build on stage0's fixed MAX* — the full compiler is no
# longer seed-bounded. A `grew`/`tight` verdict (exit 3) is a report; only a
# real compile error is surfaced (and it is caught for real by bootstrap and
# check-obj, not here).
full_src="src/mc.mc"
echo
echo "dynamic-limits report (not gated): $full_src under the growable arena"
"$mc" limits "$full_src" > "$tmp/full" 2>&1
frc=$?
if [ "$frc" != 0 ] && [ "$frc" != 3 ]; then
    echo "note: $mc limits $full_src exited $frc (not a check-limits failure; see bootstrap/check-obj)"
    sed -n '1,10p' "$tmp/full"
else
    # tail line is `tolerance ..., verdict ...`; the tables that grew or are
    # tight, if any, are the ones worth showing.
    awk 'NR==1 { next }
         /^tolerance/ { print "     " $0; next }
         $6 == "grew" || $6 == "tight" { print "     " $0 }' "$tmp/full"
    grep -q '^tolerance' "$tmp/full" || sed -n '$p' "$tmp/full" | sed 's/^/     /'
fi

rm -rf "$tmp"
[ "$fails" -eq 0 ]
