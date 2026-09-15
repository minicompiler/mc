#!/bin/sh
# check-lex.sh [MC0] [LEXDUMP] — cross-check for M4.
# Compiles src/lexdump.mc (which includes src/arena.mc and src/lex.mc) with MC0,
# links it into LEXDUMP and, for each .mc source in the repo, compares
# `MC0 --dump-tokens F` with `LEXDUMP F`. Any difference (output or exit code) is a failure.
mc="${1:-build/mc0}"
lexdump="${2:-build/lexdump}"

# M38: on Windows a program that is not called *.exe cannot be launched, so the
# name is written with the suffix here, where it is chosen (docs/guide/95-windows-host.md).
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) lexdump="$lexdump.exe" ;; esac

if [ ! -x "$mc" ]; then
    echo "FAIL: compiler '$mc' not found or not executable"
    exit 1
fi

mkdir -p build
obj="build/lexdump.o"
if ! msg=$("$mc" src/lexdump.mc -o "$obj" 2>&1); then
    echo "FAIL: compiling src/lexdump.mc: $msg"
    exit 1
fi
if ! msg=$(scripts/link-host.sh "$lexdump" "$obj" 2>&1); then
    echo "FAIL: linking $lexdump: $msg"
    exit 1
fi

# The frozen C seed (build/mc0) is a differential oracle for src/ and tests/
# ONLY, never for lib/: a library is taught from the surface and comparing it
# against the seed has no purpose beyond pressing the seed's fixed MAX* tables
# (docs/plan.md, CLAUDE.md § State). lib/*.mc left this corpus for that reason,
# which is also why the seed-skip/lex-skip escapes (M24 risk 6/D6, M44 risk 17)
# have no user left here: every file that ever carried one of those headers
# (lib/mc_float.mc, lib/float_rt.mc, lib/mc_f16.mc, lib/syntax_demo_test.mc)
# was a library. If a future src/- or tests/-only file needs one, reintroduce
# the mechanism then -- git history has both escapes verbatim.

tmp="${TMPDIR:-/tmp}/check-lex.$$"
# Under Git Bash on Windows, MSYS hands TMPDIR to this shell in /d/... form, a
# path the native mc cannot open; cygpath -m gives D:/... which both accept.
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) tmp=$(cygpath -m "$tmp") ;; esac
mkdir -p "$tmp"
fails=0
total=0

for f in tests/*.mc tests/lib/*.mc src/*.mc; do
    [ -f "$f" ] || continue
    total=$((total + 1))

    "$mc" --dump-tokens "$f" > "$tmp/a" 2> "$tmp/ae"; ra=$?
    "$lexdump" "$f"          > "$tmp/b" 2> "$tmp/be"; rb=$?

    if [ "$ra" != "$rb" ]; then
        echo "FAIL $f (exit $rb, expected $ra)"
        sed -n '1,3p' "$tmp/ae" "$tmp/be"
        fails=$((fails + 1)); continue
    fi
    if ! diff -u "$tmp/a" "$tmp/b" > "$tmp/d" 2>&1; then
        echo "FAIL $f"
        sed -n '1,20p' "$tmp/d"
        fails=$((fails + 1)); continue
    fi
    if ! diff -u "$tmp/ae" "$tmp/be" > "$tmp/de" 2>&1; then
        echo "FAIL $f (stderr differs)"
        sed -n '1,20p' "$tmp/de"
        fails=$((fails + 1)); continue
    fi
    echo "ok $f"
done

rm -rf "$tmp"
echo "$((total - fails))/$total files identical"
[ "$fails" -eq 0 ]
