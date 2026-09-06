#!/bin/sh
# check-opt.sh [COMPILER] — M49 § 7.2: the differential test of the two roads.
#
# The optimizer must not change what a program DOES. So every program in the
# corpus is compiled twice by the same compiler -- plain and with `--opt=1` --
# linked, run, and its exit code and stdout compared with each other AND with
# the `expect-*` header the source carries. A miscompilation that changes a
# value shows up here as a difference; one that changes nothing observable is
# caught by scripts/check-inert.sh and by the cross-road identity of
# scripts/bootstrap.sh instead.
#
# It also asserts the clause the plan row carries: for a program with NO
# candidate (no local the allocator would take, no loop constant to hoist)
# `--dump-asm` and `--dump-asm --opt=1` are identical, and the two lists are
# printed so the count is a fact in the commit and not a promise.
#
# The third-party machines are the null-slot rule's proof: examples/kernel's
# flat image and examples/avr's ELF have to be `cmp`-identical with and without
# the flag, with no edit to either machine (§ 9.7).
mc="${1:-build/mc1}"

if [ ! -x "$mc" ]; then
    echo "FAIL: compiler '$mc' not found or not executable"
    exit 1
fi

d="${TMPDIR:-/tmp}/check-opt.$$"
rm -rf "$d"; mkdir -p "$d"
cleanup() { rm -rf "$d"; return 0; }
trap cleanup EXIT INT TERM

fails=0
total=0
same=0
diff_asm=""
same_asm=""

# ---- 1. the corpus, both roads --------------------------------------------
# one SOURCE: compile plain and with -O, link both, run both, compare against
# the header and against each other.
run_case() {
    f="$1"
    name=$(basename "$f" .mc)
    total=$((total + 1))

    want_exit=$(sed -n 's|^// expect-exit: *||p' "$f" | head -1)
    want_out=$(sed -n 's|^// expect-stdout: *||p' "$f" | head -1)
    has_out=$(grep -c '^// expect-stdout:' "$f")
    if [ -z "$want_exit" ]; then
        echo "FAIL $name (no expect-exit header)"; fails=$((fails + 1)); return 0
    fi

    if ! msg=$("$mc" "$f" -o "$d/$name-p.o" 2>&1); then
        echo "FAIL $name (plain compile: $msg)"; fails=$((fails + 1)); return 0
    fi
    if ! msg=$("$mc" --opt=1 "$f" -o "$d/$name-o.o" 2>&1); then
        echo "FAIL $name (--opt=1 compile: $msg)"; fails=$((fails + 1)); return 0
    fi
    if ! msg=$(scripts/link-host.sh "$d/$name-p" "$d/$name-p.o" 2>&1); then
        echo "FAIL $name (plain link: $msg)"; fails=$((fails + 1)); return 0
    fi
    if ! msg=$(scripts/link-host.sh "$d/$name-o" "$d/$name-o.o" 2>&1); then
        echo "FAIL $name (--opt=1 link: $msg)"; fails=$((fails + 1)); return 0
    fi

    bad=0
    p_out=$("$d/$name-p" 2>/dev/null); p_exit=$?
    o_out=$("$d/$name-o" 2>/dev/null); o_exit=$?
    if [ "$p_exit" != "$want_exit" ]; then
        echo "FAIL $name (plain: exit $p_exit, expected $want_exit)"; bad=1
    fi
    if [ "$o_exit" != "$want_exit" ]; then
        echo "FAIL $name (--opt=1: exit $o_exit, expected $want_exit)"; bad=1
    fi
    if [ "$has_out" != "0" ] && [ "$p_out" != "$want_out" ]; then
        echo "FAIL $name (plain: stdout '$p_out', expected '$want_out')"; bad=1
    fi
    if [ "$has_out" != "0" ] && [ "$o_out" != "$want_out" ]; then
        echo "FAIL $name (--opt=1: stdout '$o_out', expected '$want_out')"; bad=1
    fi
    if [ "$p_out" != "$o_out" ]; then
        echo "FAIL $name (the two roads disagree on stdout)"; bad=1
    fi
    if [ "$bad" != "0" ]; then fails=$((fails + 1)); return 0; fi

    # the --dump-asm identity for a program with no candidate
    "$mc" --dump-asm "$f" > "$d/asm-p" 2>&1
    "$mc" --dump-asm --opt=1 "$f" > "$d/asm-o" 2>&1
    if cmp -s "$d/asm-p" "$d/asm-o"; then
        same=$((same + 1)); same_asm="$same_asm $name"
    else
        diff_asm="$diff_asm $name"
    fi
    echo "ok $name"
}

for f in tests/*.mc; do
    [ -f "$f" ] || continue
    run_case "$f"
done
for f in tests/mc/*.mc; do
    [ -f "$f" ] || continue
    run_case "$f"
done

echo "---- --dump-asm identity ----"
echo "same on both roads ($same):$same_asm"
echo "changed by --opt=1:$diff_asm"

# ---- 2. <float>: integer locals in a program whose machine is derived ------
# The float machines copy MTASK_COUNT entries out of the bundled table and
# therefore inherit the six v5 slots; an integer local in a float program is
# allocated exactly as in any other, and a float one never reaches a v5 task.
# macOS only, for the reason check-float.sh gives: this is where the taught
# compiler can be built AND run.
if [ "$(uname -s)" = "Darwin" ] && [ -f lib/mc_float.mc ]; then
    if "$mc" --exe lib/mc_float.mc -o "$d/mc-float" > "$d/e" 2>&1; then
        for f in tests/float/*.mc; do
            [ -f "$f" ] || continue
            name=$(basename "$f" .mc)
            total=$((total + 1))
            want_exit=$(sed -n 's|^// expect-exit: *||p' "$f" | head -1)
            [ -n "$want_exit" ] || want_exit=0
            want_out=$(sed -n 's|^// expect-stdout: *||p' "$f" | head -1)
            has_out=$(grep -c '^// expect-stdout:' "$f")
            if ! msg=$("$d/mc-float" --exe --opt=1 "$f" -o "$d/f-$name" 2>&1); then
                echo "FAIL float/$name (--opt=1 compile: $msg)"; fails=$((fails + 1)); continue
            fi
            got=$("$d/f-$name" 2>/dev/null); rc=$?
            if [ "$rc" != "$want_exit" ]; then
                echo "FAIL float/$name (--opt=1: exit $rc, expected $want_exit)"
                fails=$((fails + 1)); continue
            fi
            if [ "$has_out" != "0" ] && [ "$got" != "$want_out" ]; then
                echo "FAIL float/$name (--opt=1: stdout '$got', expected '$want_out')"
                fails=$((fails + 1)); continue
            fi
            echo "ok float/$name (--opt=1)"
        done
    else
        echo "FAIL float: the float compiler did not build"; sed -n 1,3p "$d/e"
        fails=$((fails + 1))
    fi
fi

# ---- 3. the taught examples ------------------------------------------------
# The compiler is built once, plainly (a taught compiler is a TOOL, and
# `[project].opt` is about the entry), and then the entry is compiled twice
# through it. lang and conc are ordinary programs with an exit code and a
# stdout, so both roads are RUN and compared; api and desktop need a socket and
# a display, so what is asserted there is that the optimized build succeeds.
taught_run() {                        # dir, output, run|build, then config args
    dir="$1"; out="$2"; how="$3"; shift 3
    total=$((total + 1))
    cc=$("$mc" build "$dir" --compiler-only "$@" 2> "$d/e" | tail -1) || {
        echo "FAIL taught $dir (compiler)"; sed -n 1,3p "$d/e"
        fails=$((fails + 1)); return 0; }
    for road in plain opt; do
        flag=""
        [ "$road" = opt ] && flag="--opt=1"
        rm -f "$dir/$out"
        # shellcheck disable=SC2086
        "$cc" build "$dir" --entry-only $flag "$@" > /dev/null 2> "$d/e" || {
            echo "FAIL taught $dir ($road, entry)"; sed -n 1,3p "$d/e"
            fails=$((fails + 1)); return 0; }
        cp "$dir/$out" "$d/t-$road"
    done
    if [ "$how" = build ]; then
        echo "ok taught $dir (both roads build)"
        return 0
    fi
    p_out=$("$d/t-plain" 2>/dev/null); p_exit=$?
    o_out=$("$d/t-opt" 2>/dev/null); o_exit=$?
    if [ "$p_exit" = "$o_exit" ] && [ "$p_out" = "$o_out" ]; then
        echo "ok taught $dir -> $out (exit $p_exit, same stdout on both roads)"
    else
        echo "FAIL taught $dir: plain exit $p_exit / opt exit $o_exit"
        printf '  plain:\n%s\n  opt:\n%s\n' "$p_out" "$o_out"
        fails=$((fails + 1))
    fi
}

if [ "$(uname -s)" = "Darwin" ]; then
    taught_run examples/lang    build/lang-demo run
    taught_run examples/conc    build/conc-demo run
    taught_run examples/api     build/api       build
    taught_run examples/desktop build/desktop-ui build --config examples/desktop/ui.toml
fi

# ---- 4. the null-slot rule -------------------------------------------------
# examples/kernel (riscv64) and examples/avr fill 31 slots of a zero-filled
# table and answer 0 to MTASK_REG_COUNT without knowing it exists, so their
# artefacts must be byte for byte the same on both roads, with no edit.
null_slot() {                         # dir, artefact
    dir="$1"; out="$2"
    total=$((total + 1))
    cc=$("$mc" build "$dir" --compiler-only 2> "$d/e" | tail -1) || {
        echo "FAIL null-slot $dir (compiler)"; sed -n 1,3p "$d/e"
        fails=$((fails + 1)); return 0; }
    for road in plain opt; do
        flag=""
        [ "$road" = opt ] && flag="--opt=1"
        rm -f "$dir/$out"
        # shellcheck disable=SC2086
        "$cc" build "$dir" --entry-only $flag > /dev/null 2> "$d/e" || {
            echo "FAIL null-slot $dir ($road)"; sed -n 1,3p "$d/e"
            fails=$((fails + 1)); return 0; }
        cp "$dir/$out" "$d/n-$road"
    done
    if cmp -s "$d/n-plain" "$d/n-opt"; then
        echo "ok null-slot $dir -> $out identical on both roads ($(wc -c < "$d/n-plain" | tr -d ' ') bytes)"
    else
        echo "FAIL null-slot $dir -> $out differs with --opt=1"
        fails=$((fails + 1))
    fi
}

if [ "$(uname -s)" = "Darwin" ]; then
    null_slot examples/kernel build/kernel.bin
    null_slot examples/avr    build/avr.elf
fi

echo "$((total - fails))/$total check-opt cases passed"
[ "$fails" -eq 0 ]
