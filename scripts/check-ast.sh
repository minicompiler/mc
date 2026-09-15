#!/bin/sh
# check-ast.sh [MC0] [ASTDUMP] — cross-check for M6 slice 3.
# Compiles src/astdump.mc (which includes arena.mc, macho.mc, lex.mc, ast.mc
# and parse.mc) with MC0, links it into ASTDUMP and, for each .mc source in
# the repo, compares `MC0 --dump-ast F` with `ASTDUMP F`. Any difference
# (stdout, stderr, or exit code) is a failure — including the files MC0
# rejects: the error message and the code have to be the same.
mc="${1:-build/mc0}"
astdump="${2:-build/astdump}"

# M38: on Windows a program that is not called *.exe cannot be launched, so the
# name is written with the suffix here, where it is chosen (docs/guide/95-windows-host.md).
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) astdump="$astdump.exe" ;; esac

if [ ! -x "$mc" ]; then
    echo "FAIL: compiler '$mc' not found or not executable"
    exit 1
fi

mkdir -p build
obj="build/astdump.o"
if ! msg=$("$mc" src/astdump.mc -o "$obj" 2>&1); then
    echo "FAIL: compiling src/astdump.mc: $msg"
    exit 1
fi
if ! msg=$(scripts/link-host.sh "$astdump" "$obj" 2>&1); then
    echo "FAIL: linking $astdump: $msg"
    exit 1
fi


# The frozen C seed (build/mc0) is a differential oracle for src/ and tests/
# ONLY, never for lib/: a library is taught from the surface and comparing it
# against the seed has no purpose beyond pressing the seed's fixed MAX* tables
# (docs/plan.md, CLAUDE.md § State). lib/*.mc left this corpus for that reason,
# which is also why the seed-skip escape (M38) has no user left here: the one
# file that ever carried it, lib/sys_windows_host.mc (CreateProcessA takes ten
# parameters and stage0 keeps MAXPARAMS at 8), was a library. If a future src/-
# or tests/-only file needs it, reintroduce the mechanism then -- git history
# has it verbatim.

tmp="${TMPDIR:-/tmp}/check-ast.$$"
# Under Git Bash on Windows, MSYS hands TMPDIR to this shell in /d/... form, a
# path the native mc cannot open; cygpath -m gives D:/... which both accept.
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) tmp=$(cygpath -m "$tmp") ;; esac
mkdir -p "$tmp"
fails=0
total=0

for f in tests/*.mc tests/lib/*.mc src/*.mc; do
    [ -f "$f" ] || continue
    total=$((total + 1))

    "$mc" --dump-ast "$f" > "$tmp/a" 2> "$tmp/ae"; ra=$?
    "$astdump" "$f"       > "$tmp/b" 2> "$tmp/be"; rb=$?

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
