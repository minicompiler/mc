#!/bin/sh
# check-freeze.sh [--record] — M53 step A: the surface freeze gate.
#
# scripts/surface-extract.sh prints mc's public surface -- seven kinds, each
# extracted from one source of truth in the tree (M53 § 2). This script asks the
# second question: was each entry here last time? tests/golden/surface.txt is
# the recorded answer, compared on every `make check`.
#
#   an entry GONE      a removal is a MAJOR. It must be deprecated first
#                      (the marker in the golden), and only then removed, in a
#                      commit that re-records the file.
#   an entry ADDED     additive, a MINOR -- legal, and it still fails until the
#                      file is re-recorded, so that every surface change costs
#                      one committed line in the same pull request and the diff
#                      IS the announcement (M53 D10).
#   an arity CHANGED   a `sym` line carries the number of parameters its
#                      definition declares, and a change to it is a MAJOR that
#                      may never be re-recorded for a public name: the parameter
#                      list is part of the frozen surface, and the replacement
#                      for a new signature is a NEW NAME with the old one kept
#                      as a one-line wrapper (docs/reference/hooks.md § 8, the
#                      deprecation lane). PR #92 gave `cmp_cond` a second
#                      parameter and every consumer got `wrong number of
#                      arguments`; this column is what that cost.
#   the machine kind   the contract version may only go up, and only in a commit
#                      that adds a `Version N → M` paragraph to
#                      docs/reference/machine.md (M53 D5).
#
# Re-recording is a named act, `--record`, and not the hash goldens'
# delete-and-rerun: this file's CONTENT is the review artefact (M53 D9).
#
# It needs no compiler -- it is grep over src/ -- so it runs on every host.
# Run from the repository root, as `make check-freeze` does.
LC_ALL=C
export LC_ALL

golden=tests/golden/surface.txt
extract=scripts/surface-extract.sh
policy='docs/specs/M53.md § 5 (the policy; docs/reference/hooks.md § 8 from step B)'

tmp="${TMPDIR:-/tmp}/check-freeze.$$"
mkdir -p "$tmp"
cleanup() { rm -rf "$tmp"; return 0; }
trap cleanup EXIT INT TERM

sh "$extract" > "$tmp/now" || { echo "FAIL: $extract failed"; exit 1; }

if [ "$1" = "--record" ]; then
    {
        echo "# mc public surface -- recorded by scripts/check-freeze.sh --record."
        echo "# One line per entry: <kind> <TAB> <name> [<TAB> <arity>] [<TAB> deprecated <version> -> <replacement>]"
        echo "# The arity column is a sym's parameter count and is frozen with its name."
        echo "# Read $policy before editing this file by hand. Do not."
        cat "$tmp/now"
    } > "$golden"
    echo "recorded $golden: $(grep -cv '^#' "$golden") entries"
    exit 0
fi

[ -f "$golden" ] || { echo "FAIL: $golden is missing -- record it: scripts/check-freeze.sh --record"; exit 1; }

# The golden's first two columns are the entry, and a `sym` carries its arity in
# a third; a field reading `deprecated <version> -> <replacement>` is the only
# expressible removal (M53 § 5.2), and it is found by its text, not by its
# position, so it sits after the arity on a sym line and after the name on any
# other.
#
# `wasa`/`nowa` are the entry plus its arity ("" where there is none), `was`/
# `now1` the entry alone: one pair answers "was it here?", the other "did its
# parameter list move?".
arity='{ a = ""; for (i = 3; i <= NF; i++) if ($i ~ /^[0-9]+$/) a = $i; print $1 "\t" $2 "\t" a }'
grep -v '^#' "$golden" | awk -F'\t' "$arity" > "$tmp/wasa"
awk -F'\t' "$arity" "$tmp/now" > "$tmp/nowa"
cut -f1,2 "$tmp/wasa" > "$tmp/was"

fails=0

# ---------------------------------------------------------------- the machine
# Its own verdict, because a bump is neither a removal nor an addition: it is
# one line whose value moved, and the rule is about the direction.
was_m=$(grep '^machine	' "$tmp/was" | cut -f2)
now_m=$(grep '^machine	' "$tmp/now" | cut -f2)
if [ "$was_m" != "$now_m" ]; then
    if [ "$now_m" -lt "$was_m" ] 2>/dev/null; then
        echo "FAIL the machine contract's version went $was_m -> $now_m"
        echo "     a version may only go up (docs/reference/machine.md, $policy)."
        fails=$((fails + 1))
    elif ! grep -qE "Version $was_m (->|→|-->) $now_m" docs/reference/machine.md; then
        echo "FAIL the machine contract's version went $was_m -> $now_m with no"
        echo "     \"Version $was_m → $now_m\" paragraph in docs/reference/machine.md."
        fails=$((fails + 1))
    else
        echo "FAIL machine: the contract version went $was_m -> $now_m"
        echo "     re-record: scripts/check-freeze.sh --record"
        fails=$((fails + 1))
    fi
fi

# ------------------------------------------------------- removed, then added
grep -v '^machine	' "$tmp/was" | sort > "$tmp/was1"
grep -v '^machine	' "$tmp/nowa" | cut -f1,2 | sort > "$tmp/now1"

comm -23 "$tmp/was1" "$tmp/now1" > "$tmp/gone"
comm -13 "$tmp/was1" "$tmp/now1" > "$tmp/new"

if [ -s "$tmp/gone" ]; then
    while IFS='	' read -r k n; do
        printf 'removed: %s %s\n' "$k" "$n"
    done < "$tmp/gone"
    # A removal is legal only where the golden already carried the marker; the
    # file must still be re-recorded in this same commit.
    # Compared field by field and never as a regex: a `toml` key carries dots
    # and a `flag` carries dashes, and a loose match here would read one entry's
    # marker as another's.
    undeprecated=$(awk -F'	' '
        NR == FNR { for (i = 3; i <= NF; i++)
                        if ($i ~ /^deprecated /) mark[$1 "	" $2] = 1
                    next }
        !(($1 "	" $2) in mark) { bad = 1 }
        END { print bad + 0 }
    ' "$golden" "$tmp/gone")
    if [ "$undeprecated" = 1 ]; then
        echo "FAIL a removal is a MAJOR ($policy). Deprecate it first, or"
        echo "     re-record deliberately with scripts/check-freeze.sh --record."
    else
        echo "FAIL the removal is deprecated and legal; re-record it in this commit:"
        echo "     scripts/check-freeze.sh --record"
    fi
    fails=$((fails + 1))
fi

if [ -s "$tmp/new" ]; then
    while IFS='	' read -r k n; do
        printf 'new: %s %s -- additive, a MINOR\n' "$k" "$n"
    done < "$tmp/new"
    echo "FAIL re-record: scripts/check-freeze.sh --record"
    fails=$((fails + 1))
fi

# ------------------------------------------------------------ a moved arity
# Only for an entry present on both sides: one that arrived or left is already
# reported above, and its arity is not a second finding.
awk -F'	' '
    NR == FNR { was[$1 "	" $2] = $3; next }
    ($1 "	" $2) in was && was[$1 "	" $2] != $3 {
        printf "changed: %s %s %s->%s\n", $1, $2, was[$1 "	" $2], $3
    }
' "$tmp/wasa" "$tmp/nowa" > "$tmp/moved"

if [ -s "$tmp/moved" ]; then
    cat "$tmp/moved"
    echo "FAIL a public function's parameter list is frozen: add a new name instead"
    echo "     (docs/reference/hooks.md § 8 -- keep the old name as a one-line"
    echo "     wrapper over the new one). Re-record ONLY if this entry is not"
    echo "     public in the first place: scripts/check-freeze.sh --record"
    fails=$((fails + 1))
fi

if [ "$fails" != 0 ]; then
    exit 1
fi

n=$(grep -c . "$tmp/now")
counts=""
for k in sym flag toml dir bundle lock machine; do
    c=$(grep -c "^$k	" "$tmp/now")
    counts="$counts, $c $k"
done
echo "ok freeze: $n entries (${counts#, })"
exit 0
