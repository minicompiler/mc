#!/bin/sh
# check-asm.sh [MC0] [MC1] — acceptance criterion for M6 slice 4.
# For each .mc source in the repo, compares `MC0 --dump-asm F` with `MC1 --dump-asm F`.
# Any difference (stdout, stderr, or exit code) is a failure — including the
# files the compilers reject: the error message and the code have to be the
# same. The src/ sources compiled on their own are exactly those cases (the
# functions they call live in another file), and the identical error is the test.
#
# While build/mc1 doesn't exist yet, run with MC1 = MC0: it has to come out
# 100% identical (proves the test itself is deterministic and the script is correct).
mc0="${1:-build/mc0}"
mc1="${2:-build/mc1}"

for mc in "$mc0" "$mc1"; do
    if [ ! -x "$mc" ]; then
        echo "FAIL: compiler '$mc' not found or not executable"
        exit 1
    fi
done


# The frozen C seed (build/mc0) is a differential oracle for src/ and tests/
# ONLY, never for lib/: a library is taught from the surface and comparing it
# against the seed has no purpose beyond pressing the seed's fixed MAX* tables
# (docs/plan.md, CLAUDE.md § State). lib/*.mc left this corpus for that reason,
# which is also why the seed-skip escape (M38) has no user left here: the one
# file that ever carried it, lib/sys_windows_host.mc (CreateProcessA takes ten
# parameters and stage0 keeps MAXPARAMS at 8), was a library. If a future src/-
# or tests/-only file needs it, reintroduce the mechanism then -- git history
# has it verbatim.
#
# One known divergence is allow-listed, dated 2026-09-15 (PR #92, "unsigned
# comparisons"): the frozen seed compares every integer, including uptr,
# SIGNED, and mc1 now compares u64/uptr UNSIGNED (machine contract v6). The
# seed cannot be fixed -- it is frozen -- and it will never emit the unsigned
# condition codes, so any source reaching src/lex.mc or src/toml.mc (whose
# cp < cend / tm_p < tm_end loops are uptr compares) differs from mc1 by
# exactly one of four single-token substitutions on a `cset`/`b.<cond>` line:
#   ge -> hs   lt -> lo   gt -> hi   le -> ls
# (mc0's signed code on the `-` side, mc1's unsigned twin on the `+` side,
# nothing else on the line changed). This is NOT a blanket normalisation: any
# other difference on such a file, or a substitution outside this exact set
# (which would mean mc1 emitting an unsigned code for what should stay a
# signed compare, or vice versa), still FAILS the file. The total count of
# allowed substitution pairs is recorded in tests/golden/seed-cmp.txt and
# compared below -- a change in that number is a change in codegen and must
# be re-recorded in the same pull request that moves it, the goldens'
# discipline (see tests/golden/README.md).

# validate_seed_diff DIFFILE -- reads a `diff -u A B` output. Prints the
# number of allowed substitution pairs on stdout and exits 0 if EVERY hunk is
# one of the four ge/lt/gt/le -> hs/lo/hi/ls substitutions (context and @@
# headers ignored); exits 1 and prints nothing else otherwise.
validate_seed_diff() {
    awk '
        BEGIN { pairs = 0; nminus = 0; nplus = 0; bad = 0 }
        /^--- / || /^\+\+\+ / { next }
        /^@@/ {
            if (nminus != nplus) { bad = 1 }
            nminus = 0; nplus = 0
            next
        }
        /^-/ {
            if (nplus > 0) { bad = 1 }  # a "-" after a "+" without a new hunk
            minus[nminus++] = substr($0, 2)
            next
        }
        /^\+/ {
            if (nminus == 0) { bad = 1; next }
            plus[nplus++] = substr($0, 2)
            if (nplus == nminus) {
                for (i = 0; i < nminus; i++) {
                    m = minus[i]; p = plus[i]
                    ok = 0
                    n = split("ge hs lt lo gt hi le ls", subs, " ")
                    for (j = 1; j < n; j += 2) {
                        from = subs[j]; to = subs[j + 1]
                        pos = index(m, from)
                        if (pos > 0) {
                            cand = substr(m, 1, pos - 1) to substr(m, pos + length(from))
                            if (cand == p) { ok = 1; break }
                        }
                    }
                    if (!ok) { bad = 1 } else { pairs++ }
                }
                nminus = 0; nplus = 0; delete minus; delete plus
            }
            next
        }
        { if (nminus != nplus) { bad = 1 }; nminus = 0; nplus = 0 }
        END {
            if (nminus != nplus) { bad = 1 }
            if (bad) { exit 1 }
            print pairs
        }
    ' "$1"
}

tmp="${TMPDIR:-/tmp}/check-asm.$$"
# Under Git Bash on Windows, MSYS hands TMPDIR to this shell in /d/... form, a
# path the native mc cannot open; cygpath -m gives D:/... which both accept.
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) tmp=$(cygpath -m "$tmp") ;; esac
mkdir -p "$tmp"
fails=0
total=0
seed_pairs=0

# The allow-list applies ONLY when MC0 is the frozen C seed by name: on the
# Linux and Windows hosts this script compares two post-fix .mc compilers
# (mc1l/mc2l, mc1w/mc2w), which must come out byte for byte identical -- any
# divergence there is a real bug, never this one.
case "$(basename "$mc0")" in
    mc0) is_seed=1 ;;
    *) is_seed=0 ;;
esac

for f in tests/*.mc tests/lib/*.mc src/*.mc; do
    [ -f "$f" ] || continue
    total=$((total + 1))

    "$mc0" --dump-asm "$f" > "$tmp/a" 2> "$tmp/ae"; ra=$?
    "$mc1" --dump-asm "$f" > "$tmp/b" 2> "$tmp/be"; rb=$?

    if [ "$ra" != "$rb" ]; then
        echo "FAIL $f (exit $rb with '$mc1', $ra with '$mc0')"
        sed -n '1,3p' "$tmp/ae" "$tmp/be"
        fails=$((fails + 1)); continue
    fi
    if ! diff -u "$tmp/a" "$tmp/b" > "$tmp/d" 2>&1; then
        if [ "$is_seed" -eq 1 ] && n=$(validate_seed_diff "$tmp/d"); then
            seed_pairs=$((seed_pairs + n))
            echo "ok $f ($n seed-signed compares)"
        else
            echo "FAIL $f"
            sed -n '1,20p' "$tmp/d"
            fails=$((fails + 1))
        fi
        continue
    fi
    if ! diff -u "$tmp/ae" "$tmp/be" > "$tmp/de" 2>&1; then
        echo "FAIL $f (stderr differs)"
        sed -n '1,20p' "$tmp/de"
        fails=$((fails + 1)); continue
    fi
    echo "ok $f"
done

if [ "$is_seed" -eq 1 ]; then
    golden="tests/golden/seed-cmp.txt"
    if [ -f "$golden" ]; then
        want=$(cat "$golden")
        if [ "$seed_pairs" != "$want" ]; then
            echo "FAIL seed-signed compare count moved: got $seed_pairs, $golden says $want"
            echo "     (a codegen change -- re-record $golden in the same pull request)"
            fails=$((fails + 1))
        fi
    elif [ "$seed_pairs" -gt 0 ]; then
        echo "FAIL $golden is missing (got $seed_pairs seed-signed compares) -- record it"
        fails=$((fails + 1))
    fi
fi

rm -rf "$tmp"
echo "$((total - fails))/$total files identical"
[ "$fails" -eq 0 ]
