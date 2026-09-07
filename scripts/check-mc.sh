#!/bin/sh
# check-mc.sh COMPILER — the tests that only the self-hosted compiler can
# compile (M15). They live in tests/mc/, not in tests/, on purpose:
# `#embed` and `#include <name>` exist in src/*.mc and NOT in the frozen
# stage0/*.c, so scripts/test.sh, check-obj.sh, check-ast.sh and check-asm.sh —
# which all compare mc0 against mc1 over tests/*.mc — would report a difference
# that is the whole point of the milestone. Keeping them in their own directory
# leaves those four cross-checks meaning exactly what they meant before.
#
# Same header contract as scripts/test.sh:
#   // expect-exit: N        (required)
#   // expect-stdout: TEXT   (optional)
# Every test is built twice: through .o + scripts/link.sh, and through --exe.
mc="${1:-build/mc1}"

if [ ! -x "$mc" ]; then
    echo "FAIL: compiler '$mc' not found or not executable"
    exit 1
fi

mkdir -p build/tests-mc
fails=0
total=0
skips=0

# M49: the two-level `// skip-<os>:` / `// skip-<arch>:` header every other
# runner already honours (scripts/test-linux.sh, scripts/test-windows.sh). It
# was not needed here while tests/mc/ held only portable cases; 100-opt-opcode
# writes an AArch64 word by hand, so on an x86_64 host it is four bytes of
# garbage and the test segfaults -- which is what its header says and what
# tests/031-opcode.mc has said since M17 step B. The pair comes from the
# COMPILER's own answer, so a compiler cross-built for another host is not
# asked to run its tests here at all.
host_os=$("$mc" --host 2>/dev/null | sed -n 's|^os ||p')
host_arch=$("$mc" --host 2>/dev/null | sed -n 's|^arch ||p')
skip_reason() {
    r=$(sed -n "s|^// skip-$host_os: *||p" "$1" | head -1)
    [ -n "$r" ] || r=$(sed -n "s|^// skip-$host_arch: *||p" "$1" | head -1)
    printf '%s' "$r"
}

# M38: on Windows a program that is not called *.exe cannot be launched.
hostexe=""
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) hostexe=".exe" ;; esac

for f in tests/mc/*.mc; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .mc)
    why=$(skip_reason "$f")
    if [ -n "$why" ]; then
        echo "skip $name — $why"
        skips=$((skips + 1))
        continue
    fi
    total=$((total + 1))
    obj="build/tests-mc/$name.o"
    exe="build/tests-mc/$name$hostexe"
    exe2="build/tests-mc/$name-exe"

    want_exit=$(sed -n 's|^// expect-exit: *||p' "$f" | head -1)
    want_out=$(sed -n 's|^// expect-stdout: *||p' "$f" | head -1)
    has_out=$(grep -c '^// expect-stdout:' "$f")

    if [ -z "$want_exit" ]; then
        echo "FAIL $name (no expect-exit header)"; fails=$((fails + 1)); continue
    fi
    if ! msg=$("$mc" "$f" -o "$obj" 2>&1); then
        echo "FAIL $name (compilation: $msg)"; fails=$((fails + 1)); continue
    fi
    if ! msg=$(scripts/link-host.sh "$exe" "$obj" 2>&1); then
        echo "FAIL $name (link: $msg)"; fails=$((fails + 1)); continue
    fi
    # M37: `--exe` writes a direct executable FOR THE HOST. Linux and Windows
    # are registered with no such backend -- since the post-M41 review batch
    # the flag is refused there, and before it it silently produced a macOS
    # binary this machine cannot run -- so the second half of each case is the
    # object + linker path only, and only macOS runs both.
    runs="$exe"
    if [ "$(uname -s)" = "Darwin" ]; then
        rm -f "$exe2"
        if ! msg=$("$mc" --exe "$f" -o "$exe2" 2>&1); then
            echo "FAIL $name (--exe: $msg)"; fails=$((fails + 1)); continue
        fi
        runs="$exe $exe2"
    fi

    bad=0
    for run in $runs; do
        got_out=$("$run" 2>/dev/null)
        got_exit=$?
        if [ "$got_exit" != "$want_exit" ]; then
            echo "FAIL $name ($run: exit $got_exit, expected $want_exit)"; bad=1
        fi
        if [ "$has_out" != "0" ] && [ "$got_out" != "$want_out" ]; then
            echo "FAIL $name ($run: stdout '$got_out', expected '$want_out')"; bad=1
        fi
    done
    if [ "$bad" != "0" ]; then fails=$((fails + 1)); continue; fi
    echo "ok $name"
done

# the seed has to REFUSE these sources: `#embed` and `#include <name>` are
# Phase 2 surface that only lives in src/*.mc (docs/surface.md § Tier 1, M15),
# and `continue N;` is core surface the frozen stage0/parse.c predates -- it
# reads `continue` and then demands a semicolon. That refusal is the reason
# 094/095 live in tests/mc/ rather than in tests/, so it is asserted and not
# assumed.
if [ -x build/mc0 ]; then
    for f in tests/mc/070-embed.mc tests/mc/072-include-bundle.mc \
             tests/mc/094-continue-level.mc tests/mc/095-continue-one.mc; do
        total=$((total + 1))
        if msg=$(build/mc0 "$f" -o build/tests-mc/seed.o 2>&1); then
            echo "FAIL: build/mc0 accepted $f"; fails=$((fails + 1))
        else
            echo "ok build/mc0 rejects $f ($msg)"
        fi
    done
fi

# ---- the long sibling chain (post-M48 C2) ----
# A list in this compiler is an `nd_next` chain with one node per element, and
# fold() used to RECURSE on `next` -- so the stack depth was the LENGTH of a
# list, not its nesting. src/bundle_data.mc is exactly that shape (the M21.5
# deviation keeps `u64 bundle_blob[] = { ... }` on disk, because the frozen
# seed's lexer has no #embed), and at 73045 elements it overflowed the 8 MiB
# stack of the windows/x86_64-hosted compiler, where the Win64 shadow space
# makes fold's frame 112 bytes against the 80 of AAPCS64 and SysV. Measured
# ceilings before the fix: ~74000 elements on windows/x86_64 and ~104000 on
# every other host; after it, the nesting depth and nothing else.
#
# GENERATED and not committed: it takes 150000 elements to fail on every host
# and that is 300 KB of source. This is the one case in this file that compiles
# a program the repository does not carry, and it is here rather than in
# tests/mc/ for that reason -- everything else about it (compile with $mc, link
# with the host linker, run, check the exit code) is what the loop above does.
total=$((total + 1))
gen="build/tests-mc/long-list.mc"
awk 'BEGIN {
    n = 150000
    printf "// generated by scripts/check-mc.sh -- a 150000-element sibling chain\n"
    printf "u64 big[] = {\n"
    for (i = 0; i < n; i++) {
        printf "%d", i % 251
        if (i + 1 < n) printf ","
        if (i % 40 == 39) printf "\n"
    }
    printf "\n};\n"
    printf "i64 main() { if (ld64(big + 149999 * 8) != 152) return 1; return 42; }\n"
}' > "$gen"
long_ok=1
if ! msg=$("$mc" "$gen" -o build/tests-mc/long-list.o 2>&1); then
    echo "FAIL long-list (compilation: $msg)"; long_ok=0
elif ! msg=$(scripts/link-host.sh "build/tests-mc/long-list$hostexe" build/tests-mc/long-list.o 2>&1); then
    echo "FAIL long-list (link: $msg)"; long_ok=0
else
    "build/tests-mc/long-list$hostexe"; got=$?
    if [ "$got" != "42" ]; then echo "FAIL long-list (exit $got, expected 42)"; long_ok=0; fi
fi
if [ "$long_ok" = "1" ]; then echo "ok long-list (150000 elements)"; else fails=$((fails + 1)); fi

if [ "$skips" != 0 ]; then
    echo "$((total - fails))/$total mc-only tests passed ($skips skipped on $host_os/$host_arch)"
else
    echo "$((total - fails))/$total mc-only tests passed"
fi
[ "$fails" -eq 0 ]
