#!/bin/sh
# check-libroot.sh [MC] — M52 step A: the library root beside the binary, and
# the refusal that names `mc install` (docs/specs/M52.md § 4, D4 and D6).
#
# A `#include <name>` the blob cannot answer is served by a tree in the
# repository layout whose root holds `bundle.list`. Three roots are tried, in
# order (docs/reference/packages.md § 2):
#
#   1. <libs>/mc/v<ver>/                     -- `mc install`, $HOME or --libs-dir
#   2. <dir of the binary>/lib/mc/v<ver>/    -- the release tarball, and `make`
#   3. <dir of the binary>/../lib/mc/v<ver>/ -- a packager's bin/ beside lib/
#
# In step A the blob still carries all 101 rows, so every name a program can
# spell is answered before any of this is reached: the new road is proved with
# a name the blob DOES NOT have, `m52probe`, added to the tree under test. That
# is the trick below, and it is what makes each case say which root answered
# instead of asserting a name that would have worked anyway.
#
# Seven cases:
#   a  no root at all: the refusal names the road, exit 1 (D6, first row)
#   b  root 2 serves the name: the program compiles and RUNS (exit 42)
#   c  root 3 serves it too, with the binary in a bin/ beside a lib/
#   d  root 1 beats root 2: two trees differing in one byte, and <libs> wins
#   e  a misspelled name with a root present keeps `unknown bundled include`
#      (D6, middle row -- the message check-pkg asserts)
#   f  docs/bootstrap.md's claim: untar a scripts/release-assets.sh archive and
#      the tree that came out of it is a working root -- no --libs-dir, no
#      $HOME tree, no network
#   g  M52 step D: a taught compiler `mc build` wrote gets a root of its own,
#      staged beside it, and works STANDALONE -- the case the consumer measured
#      (a [compiler] product is a second binary in the project's build/, so the
#      parent's roots 2 and 3 are invisible to it). The staging is idempotent.
#
# HOME is an empty directory for every compile: the single-file CLI has no
# --libs-dir, so HOME is what picks root 1, and a developer who ran `mc install`
# for real must not change what this gate measures.
#
# Run from the repository root, as `make check-libroot` does.
mc="${1:-build/mc1}"

if [ ! -x "$mc" ]; then
    echo "FAIL: compiler '$mc' not found or not executable"
    exit 1
fi
here=$(pwd)
case "$mc" in /*) ;; *) mc="$here/$mc" ;; esac

ver=$(sed -n 's/^uptr mc_version() { return "\(.*\)"; }$/\1/p' src/version.mc | head -1)
if [ -z "$ver" ]; then
    echo "FAIL: cannot read the version out of src/version.mc"
    exit 1
fi

tmp="${TMPDIR:-/tmp}/check-libroot.$$"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) tmp=$(cygpath -m "$tmp") ;; esac
rm -rf "$tmp"
mkdir -p "$tmp/home" "$tmp/p"
trap 'rm -rf "$tmp"' EXIT INT TERM

fails=0
total=0
ok()   { total=$((total + 1)); echo "ok $1"; }
fail() { total=$((total + 1)); echo "FAIL $1: $2"; fails=$((fails + 1)); }

# the program every positive case compiles: a name the blob does not carry
cat > "$tmp/p/prog.mc" <<'EOF'
#include <m52probe>
i64 main() { return m52probe(); }
EOF
# and a misspelled one, for case (e)
cat > "$tmp/p/nope.mc" <<'EOF'
#include <no/such/module>
i64 main() { return 0; }
EOF

# Lay a root under DIR (a directory that holds a copy of the compiler) and give
# it m52probe, returning N. Everything else in it is what scripts/libroot.sh
# writes -- the same tree `make` lays beside build/mc1 and the same one a
# release tarball carries.
lay() {
    sh scripts/libroot.sh "$1" "$ver" > /dev/null
    printf 'i64 m52probe() { return %s; }\n' "$2" > "$1/lib/mc/v$ver/lib/m52probe.mc"
    printf 'm52probe\tlib/m52probe.mc\n' >> "$1/lib/mc/v$ver/bundle.list"
}

# compile + link + run $tmp/p/prog.mc with the compiler $1 and HOME $2
build_run() {
    rm -f "$tmp/p/prog.o" "$tmp/p/prog"
    out=$(HOME="$2" "$1" "$tmp/p/prog.mc" -o "$tmp/p/prog.o" 2>&1); rc=$?
    if [ "$rc" = 0 ]; then
        out=$(sh scripts/link.sh "$tmp/p/prog" "$tmp/p/prog.o" 2>&1); rc=$?
        if [ "$rc" = 0 ]; then "$tmp/p/prog"; rc=$?; fi
    fi
}

# ------------------------------------------------------- a. no root at all
mkdir -p "$tmp/alone"
cp "$mc" "$tmp/alone/mc"
chmod +x "$tmp/alone/mc"
out=$(HOME="$tmp/home" "$tmp/alone/mc" "$tmp/p/prog.mc" -o "$tmp/p/prog.o" 2>&1); rc=$?
want="#include <m52probe>: not in this compiler and mc $ver's library tree was not found: run mc install"
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -qF "$want"; then
    ok "no root: $(printf '%s' "$out" | sed 's|^.*prog.mc:1: ||')"
else
    fail "the refusal with no root" "exit $rc: $out"
fi

# ------------------------------------------------------------- b. root 2
lay "$tmp/alone" 42
build_run "$tmp/alone/mc" "$tmp/home"
if [ "$rc" = 42 ]; then
    ok "root 2 (<dir of the binary>/lib/mc/v$ver/) serves <m52probe>, exit 42"
else
    fail "root 2" "exit $rc: $out"
fi

# ------------------------------------------------------------- c. root 3
mkdir -p "$tmp/pkg/bin"
cp "$mc" "$tmp/pkg/bin/mc"
chmod +x "$tmp/pkg/bin/mc"
lay "$tmp/pkg" 42
build_run "$tmp/pkg/bin/mc" "$tmp/home"
if [ "$rc" = 42 ]; then
    ok "root 3 (bin/mc finds ../lib/mc/v$ver/), exit 42"
else
    fail "root 3" "exit $rc: $out"
fi

# ----------------------------------------------------- d. root 1 beats root 2
# The two trees differ in one byte: the one beside the binary answers 7, the
# installed one answers 42, and the program returns what <libs> said.
mkdir -p "$tmp/prec/bin" "$tmp/prechome/.mc/libs/mc"
cp "$mc" "$tmp/prec/bin/mc"
chmod +x "$tmp/prec/bin/mc"
lay "$tmp/prec/bin" 7
cp -R "$tmp/prec/bin/lib/mc/v$ver" "$tmp/prechome/.mc/libs/mc/v$ver"
printf 'i64 m52probe() { return 42; }\n' > "$tmp/prechome/.mc/libs/mc/v$ver/lib/m52probe.mc"
build_run "$tmp/prec/bin/mc" "$tmp/prechome"
if [ "$rc" = 42 ]; then
    ok "<libs> wins over the tree beside the binary (42, not 7)"
else
    fail "root precedence" "exit $rc (7 = the tree beside the binary won): $out"
fi

# ------------------------------------------------- e. the middle message stays
out=$(HOME="$tmp/home" "$tmp/alone/mc" "$tmp/p/nope.mc" -o "$tmp/p/nope.o" 2>&1); rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'unknown bundled include: no/such/module'; then
    ok "a root is there and the name is not in it: $(printf '%s' "$out" | sed 's|^.*nope.mc:1: ||')"
else
    fail "the unknown-include message with a root present" "exit $rc: $out"
fi

# --------------------------------------------------------- f. a release tarball
# docs/bootstrap.md's claim after M52: untar, and a `#include <name>` the binary
# does not carry resolves from the tree the archive brought -- offline, with no
# --libs-dir and an empty HOME. The probe row is added to the UNPACKED copy, for
# the reason at the top of this file.
mkdir -p "$tmp/dist" "$tmp/unpack"
if ! out=$(sh scripts/release-assets.sh "$ver" libroot-probe "$mc" "$tmp/dist" 2>&1); then
    fail "release-assets.sh" "$out"
else
    d="$tmp/unpack/mc-$ver-libroot-probe"
    tar xzf "$tmp/dist/mc-$ver-libroot-probe.tar.gz" -C "$tmp/unpack"
    n=$(find "$d/lib/mc/v$ver/lib" -type f 2> /dev/null | wc -l | tr -d ' ')
    want=$(awk -F'\t' '$2 ~ /^lib\//' tools/bundle.list | wc -l | tr -d ' ')
    if [ -f "$d/lib/mc/v$ver/bundle.list" ] && [ "$n" = "$want" ]; then
        ok "the tarball carries lib/mc/v$ver/ (bundle.list + $n library files)"
    else
        fail "the tarball's library root" "files=$n want=$want"
    fi
    printf 'i64 m52probe() { return 42; }\n' > "$d/lib/mc/v$ver/lib/m52probe.mc"
    printf 'm52probe\tlib/m52probe.mc\n' >> "$d/lib/mc/v$ver/bundle.list"
    build_run "$d/mc" "$tmp/home"
    if [ "$rc" = 42 ]; then
        ok "untar and compile: the unpacked tree is a working root, no \$HOME and no network"
    else
        fail "the unpacked tarball as a root" "exit $rc: $out"
    fi
fi

# ---------------------------------------- g. the taught compiler's own tree
# The shape the consumer reported on 2026-09-13: `[compiler].core =
# "<mc/core_min>"`, so the product has NO blob and `<sys>` can only come from
# resolution road 3. It worked when `mc build` spawned it (the parent hands its
# own root over, deps_libs_for_child) and failed when run standalone --
# `unknown bundled include: sys`, measured on this tree before the fix.
#
# The module is what examples/avr/mc-avr.mc is, minus the AVR: the parts a
# host compiler needs, and <mc/core_build> because road 3 arrives with it
# (lex_set_libs is mc_build_init's line; without that part the product cannot
# read a tree at all, which is measured too -- it is why this module names it).
mkdir -p "$tmp/teach"
cat > "$tmp/teach/mod.mc" <<'EOF'
#include <mc/core_machines>
#include <mc/core_writers>
#include <mc/core_build>
i64 main(i64 argc, uptr argv, uptr envp) {
    host_init(envp);
    mc_machines_init();
    mc_writers_init();
    mc_build_init();
    return mc_main(argc, argv, envp);
}
void user_init() { }
EOF
cat > "$tmp/teach/mc.toml" <<'EOF'
[project]
name  = "taught"
entry = "prog.mc"
out   = "build/prog.o"
kind  = "obj"

[compiler]
core    = "<mc/core_min>"
modules = ["mod.mc"]
out     = "build/taught"
EOF
cat > "$tmp/teach/prog.mc" <<'EOF'
#include <sys>
i64 main() { return 42; }
EOF
out=$(HOME="$tmp/home" "$mc" build "$tmp/teach" --compiler-only 2>&1); rc=$?
if [ "$rc" != 0 ]; then
    fail "mc build --compiler-only" "exit $rc: $out"
else
    staged=0
    if [ -f "$tmp/teach/build/lib/mc/v$ver/bundle.list" ]; then
        staged=1
        n=$(find "$tmp/teach/build/lib/mc/v$ver" -type f | wc -l | tr -d ' ')
        ok "the product carries lib/mc/v$ver/ beside it ($n files)"
    else
        fail "the staged tree" "no $tmp/teach/build/lib/mc/v$ver/bundle.list"
    fi
    # standalone: not `mc build`, no --libs-dir, an empty HOME. The product has
    # no blob, so a success here is road 3 through the staged tree and nothing
    # else -- with the tree moved away the same command is `not bundled in this
    # compiler and mc <ver> is not installed`.
    rm -f "$tmp/teach/build/prog.o" "$tmp/teach/build/prog"
    out=$(HOME="$tmp/home" "$tmp/teach/build/taught" "$tmp/teach/prog.mc" \
              -o "$tmp/teach/build/prog.o" 2>&1); rc=$?
    if [ "$rc" = 0 ]; then
        out=$(sh scripts/link.sh "$tmp/teach/build/prog" "$tmp/teach/build/prog.o" 2>&1); rc=$?
        if [ "$rc" = 0 ]; then "$tmp/teach/build/prog"; rc=$?; fi
    fi
    if [ "$rc" = 42 ]; then
        ok "the product run STANDALONE compiles #include <sys>, exit 42"
    else
        fail "the product standalone" "exit $rc: $out"
    fi
    # idempotent: a second build rewrites nothing. `find -newer` is the test --
    # the bytes are identical by construction, so what has to be proved is that
    # no file was WRITTEN, and a marker laid between the two builds says it.
    if [ "$staged" = 0 ]; then
        fail "the staging is idempotent" "nothing was staged to compare"
    else
        sleep 1
        touch "$tmp/marker"
        HOME="$tmp/home" "$mc" build "$tmp/teach" --compiler-only > /dev/null 2>&1
        touched=$(find "$tmp/teach/build/lib" -type f -newer "$tmp/marker" | wc -l | tr -d ' ')
        if [ "$touched" = 0 ]; then
            ok "a second build restages nothing: 0 of $n files rewritten"
        else
            fail "the staging is not idempotent" "$touched files rewritten"
        fi
    fi
fi

echo "check-libroot: $((total - fails))/$total"
[ "$fails" = 0 ] || exit 1
