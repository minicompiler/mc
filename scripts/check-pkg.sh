#!/bin/sh
# check-pkg.sh [MC] — the acceptance criteria of M44, steps 2 and 3: the
# resolution model, the lock, the tree hash, the closure rule and the
# [package].files boundary (step 2), and then the registry, MVS, the lock
# WRITER, the archive fetch, vendoring, `mc pkg add|list|verify|hash|check` and
# `mc update` (step 3).
#
# NOTHING HERE TOUCHES THE NETWORK. The fixture registry is a DIRECTORY this
# script builds -- index files whose `url` is a local tarball it made with `tar`
# out of tests/pkg/src -- which is exactly the private-registry shape M44 § 5
# prices at zero lines, and it is why a `curl`/`wget` shim that FAILS if it is
# invoked sits on PATH for the whole run: `mc build` and `mc pkg` against a
# local registry must be PROVED never to download, not just documented
# (M44 § Acceptance, architect's addition (a)).
#
# The `tar` shim is on PATH for every `mc build` and off it for `mc pkg`, which
# has to unpack an archive; `pkg()` below is the one place that difference
# lives.
#
# The fixtures are tests/pkg/:
#
#   src/mathx-1.0.0   a library, no dependencies
#   src/geo-1.2.0     a library that depends on mathx; `lib = "geo.mc"`
#   src/geo-1.0.0     the version the lock does NOT name
#   src/teach-1.0.0   a COMPILER-MODULE package (`unless`, through syntax_stmt)
#   src/bad-1.0.0     reads one file above its own tree, twice over
#   src/float-1.3.0   a copy of lib/float.mc + float_rt.mc where putf64 writes
#                     a `!`: a registry package carrying a BUNDLED name (§ A5)
#   app/ app-float/ app-bad/ app-extra/ std/    the consumers
#
# `<libs>` is populated from those trees by this script, with one cache manifest
# per installed version -- the file `mc pkg sync` will write in step 3, produced
# here by scripts/pkg-hash.sh, which is a SECOND implementation of the tree hash
# in shell. Every lock hash checked into tests/pkg is compared against it, so a
# divergence between src/deps.mc and the specification is a red `make check`.
mc="${1:-build/mc1}"

if [ ! -x "$mc" ]; then
    echo "FAIL: compiler '$mc' not found or not executable"
    exit 1
fi
here=$(pwd)
mc=$(cd "$(dirname "$mc")" && pwd)/$(basename "$mc")

tmp="${TMPDIR:-/tmp}/check-pkg.$$"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) tmp=$(cygpath -m "$tmp") ;; esac
rm -rf "$tmp"
mkdir -p "$tmp/libs" "$tmp/libs2" "$tmp/empty" "$tmp/bin" "$tmp/bin2" "$tmp/out" \
         "$tmp/archives" "$tmp/stage" "$tmp/registry/index" "$tmp/c1" "$tmp/c2" "$tmp/chk"
cleanup() {
    rm -rf "$tmp"
    rm -rf "$here/tests/pkg/app/build" "$here/tests/pkg/app/deps" \
           "$here/tests/pkg/app-float/build" "$here/tests/pkg/app-bad/build" \
           "$here/tests/pkg/app-extra/build" "$here/tests/pkg/std/build" \
           "$here/tests/pkg/sync/build" "$here/tests/pkg/sync/deps" \
           "$here/tests/pkg/sync/mc.lock" "$here/tests/pkg/major/build" \
           "$here/tests/pkg/major/mc.lock" "$here/tests/pkg/add/build" \
           "$here/tests/pkg/add/mc.lock" "$here/tests/pkg/add/deps" \
           "$here/tests/pkg/perm/build" "$here/tests/pkg/perm/deps" \
           "$here/tests/pkg/perm/mc.lock" "$here/tests/pkg/perm/wider.toml" \
           "$here/tests/pkg/perm/wrong.toml"
    git -C "$here" checkout -- tests/pkg/add/add.toml 2> /dev/null
}
trap cleanup EXIT INT TERM

fails=0
total=0
ok()   { total=$((total + 1)); echo "ok $1"; }
fail() { total=$((total + 1)); echo "FAIL $1: $2"; fails=$((fails + 1)); }

# ---- the no-network shim ----
# Every downloader mc knows about (src/host_*.mc host_downloader/_alt), plus the
# archive tool, refusing loudly. Anything that reaches for the network in this
# script fails the run instead of silently succeeding on a developer's machine.
realpath_env="$PATH"                  # the PATH with a working tar on it
for t in curl wget tar; do
    cat > "$tmp/bin/$t" <<EOF
#!/bin/sh
echo "check-pkg: $t was invoked -- mc build must never download" >&2
exit 97
EOF
    chmod +x "$tmp/bin/$t"
    # bin2 is what `mc pkg` runs under: the two downloaders still refuse, so a
    # fetch that reached the network would fail the run, but `tar` is real --
    # unpacking an archive is what a package fetch DOES.
    [ "$t" = tar ] || cp "$tmp/bin/$t" "$tmp/bin2/$t"
done
PATH="$tmp/bin:$PATH"
export PATH

# `mc pkg ...` with the real tar and the refusing downloaders
pkg() { PATH="$tmp/bin2:$realpath_env" "$mc" pkg "$@" > "$tmp/o" 2>&1; rc=$?; }
# the script's own archive building, which the shim would otherwise refuse
rtar() { PATH="$realpath_env" tar "$@"; }
upd() { PATH="$tmp/bin2:$realpath_env" "$mc" update "$@" > "$tmp/o" 2>&1; rc=$?; }

# ---- <libs>, populated by hand: this is what `mc pkg sync` will write ----
install_pkg() {                       # install_pkg SRCDIR NAME VERSION LIBSDIR
    d="$4/$2/v$3"
    mkdir -p "$d"
    cp -R "$1/." "$d/"
    {
        echo '[source]'
        echo "name = \"$2\""
        echo "version = \"$3\""
        echo "sha256 = \"$(sh scripts/pkg-hash.sh "$1")\""
        sh scripts/pkg-hash.sh --files "$1" | while read -r h f; do
            echo
            echo '[[file]]'
            echo "path = \"$f\""
            echo "sha256 = \"$h\""
        done
    } > "$4/$2/v$3.toml"
}

for L in "$tmp/libs" "$tmp/libs2"; do
    install_pkg tests/pkg/src/mathx-1.0.0 mathx 1.0.0 "$L"
    install_pkg tests/pkg/src/geo-1.2.0   geo   1.2.0 "$L"
    install_pkg tests/pkg/src/teach-1.0.0 teach 1.0.0 "$L"
    install_pkg tests/pkg/src/bad-1.0.0   bad   1.0.0 "$L"
    install_pkg tests/pkg/src/float-1.3.0 float 1.3.0 "$L"
done
# the version no lock names, in ONE of the two installations only
install_pkg tests/pkg/src/geo-1.0.0 geo 1.0.0 "$tmp/libs"
cp tests/pkg/app-bad/outside.mc "$tmp/libs/outside.mc"
cp tests/pkg/app-bad/outside.mc "$tmp/libs2/outside.mc"

# ---- 1. the two implementations of the tree hash agree with the locks ----
lock_hash() { sed -n "/name *= *\"$2\"/,/^$/p" "$1" | sed -n 's/^sha256 *= *"\(.*\)"/\1/p' | head -1; }
check_hash() {                        # check_hash LOCK NAME SRCDIR
    want=$(lock_hash "$1" "$2")
    got=$(sh scripts/pkg-hash.sh "$3")
    if [ "$want" = "$got" ]; then ok "tree hash $2: mc.lock and scripts/pkg-hash.sh agree"
    else fail "tree hash $2" "lock says $want, pkg-hash.sh says $got"
    fi
}
check_hash tests/pkg/app/mc.lock       geo   tests/pkg/src/geo-1.2.0
check_hash tests/pkg/app/mc.lock       mathx tests/pkg/src/mathx-1.0.0
check_hash tests/pkg/app/mc.lock       teach tests/pkg/src/teach-1.0.0
check_hash tests/pkg/app-float/mc.lock float tests/pkg/src/float-1.3.0
check_hash tests/pkg/app-bad/mc.lock   bad   tests/pkg/src/bad-1.0.0

# ---- helpers ----
cc="$mc"                              # which compiler `build` drives
build() {                             # build DIR CONFIG LIBSDIR -> $tmp/o, $rc
    rm -rf "$1/build"
    if [ -n "$2" ]; then
        "$cc" build "$1" --config "$2" --libs-dir "$3" > "$tmp/o" 2>&1
    else
        "$cc" build "$1" --libs-dir "$3" > "$tmp/o" 2>&1
    fi
    rc=$?
}
want_exit() {                         # want_exit LABEL CODE
    if [ "$rc" = "$2" ]; then return 0; fi
    fail "$1" "exit $rc, expected $2 -- $(tail -2 "$tmp/o" | tr '\n' ' ')"
    return 1
}
want_msg() {                          # want_msg LABEL TEXT
    if grep -q "$2" "$tmp/o"; then ok "$1: $(grep -m1 "$2" "$tmp/o")"
    else fail "$1" "no '$2' in: $(cat "$tmp/o")"
    fi
}

# ---- 2. the chain builds and runs (acceptance 5) ----
build tests/pkg/app "" "$tmp/libs"
if want_exit "app builds" 0; then
    out=$(tests/pkg/app/build/app 2>/dev/null); arc=$?
    if [ "$arc" = 42 ] && [ "$out" = "geo 120" ]; then
        ok "<geo/geo.mc> + <geo> + <mathx/mathx.mc> + <teach/mc_teach.mc>: exit 42, 'geo 120'"
    else
        fail "app runs" "exit $arc, stdout '$out'"
    fi
fi

# ---- 3. an unlocked version beside the locked one is never opened ----
build tests/pkg/app tests/pkg/app/obj.toml "$tmp/libs"
want_exit "app object (libs with geo v1.0.0 present)" 0 && cp tests/pkg/app/build/app.o "$tmp/out/a1.o"
build tests/pkg/app tests/pkg/app/obj.toml "$tmp/libs2"
if want_exit "app object (libs2, only v1.2.0)" 0; then
    if cmp -s "$tmp/out/a1.o" tests/pkg/app/build/app.o; then
        ok "geo v1.0.0 beside v1.2.0 changes nothing: the two objects are identical"
    else
        fail "unlocked version" "the objects differ"
    fi
fi

# ---- 4. two independent installations give the same bytes ----
# (that is the same comparison as 3 read the other way round: libs and libs2
# were populated separately, from the same sources.)

# ---- 5. the lock refuses a tampered source (acceptance 7) ----
cp "$tmp/libs/geo/v1.2.0/vec.mc" "$tmp/out/vec.mc"
printf 'x' >> "$tmp/libs/geo/v1.2.0/vec.mc"
build tests/pkg/app tests/pkg/app/obj.toml "$tmp/libs"
want_exit "tampered vec.mc" 2 && want_msg "tampered vec.mc" "geo 1.2.0: vec.mc does not match mc.lock"
# restore, and prove the refusal was the byte and not the road
cp "$tmp/out/vec.mc" "$tmp/libs/geo/v1.2.0/vec.mc"
build tests/pkg/app tests/pkg/app/obj.toml "$tmp/libs"
want_exit "restored vec.mc" 0 && ok "restored: the same tree builds again"

# ---- 6. the files list itself is hashed (acceptance 7, second half) ----
cp "$tmp/libs/geo/v1.2.0/mc.toml" "$tmp/out/geo-mc.toml"
sed 's/^files *=.*/files = ["geo.mc"]/' "$tmp/out/geo-mc.toml" > "$tmp/libs/geo/v1.2.0/mc.toml"
build tests/pkg/app tests/pkg/app/obj.toml "$tmp/libs"
want_exit "tampered geo mc.toml" 2 && want_msg "tampered geo mc.toml" "geo 1.2.0: mc.toml does not match mc.lock"
cp "$tmp/out/geo-mc.toml" "$tmp/libs/geo/v1.2.0/mc.toml"

# ---- 7. stale lock and unfetched package (acceptance 8) ----
sed 's/^geo   = "1.2.0"/geo   = "1.9.0"/' tests/pkg/app/obj.toml > "$tmp/out/stale.toml"
cp "$tmp/out/stale.toml" tests/pkg/app/stale.toml
build tests/pkg/app tests/pkg/app/stale.toml "$tmp/libs"
want_exit "stale lock" 2 && want_msg "stale lock" "mc.lock is stale"
rm -f tests/pkg/app/stale.toml
mv "$tmp/libs/mathx" "$tmp/out/mathx-away"
build tests/pkg/app tests/pkg/app/obj.toml "$tmp/libs"
want_exit "unfetched package" 2 && want_msg "unfetched package" "mathx 1.0.0 is not fetched"
grep -q "mc pkg sync --yes" "$tmp/o" && ok "the refusal carries its run: line" \
    || fail "unfetched package" "no run: line"
mv "$tmp/out/mathx-away" "$tmp/libs/mathx"

# ---- 8. vendoring is the offline road (acceptance 9) ----
rm -rf tests/pkg/app/deps
mkdir -p tests/pkg/app/deps
cp -R tests/pkg/src/geo-1.2.0   tests/pkg/app/deps/geo
cp -R tests/pkg/src/mathx-1.0.0 tests/pkg/app/deps/mathx
cp -R tests/pkg/src/teach-1.0.0 tests/pkg/app/deps/teach
build tests/pkg/app tests/pkg/app/obj.toml "$tmp/empty"
if want_exit "vendored build with an EMPTY libs dir" 0; then
    if cmp -s "$tmp/out/a1.o" tests/pkg/app/build/app.o; then
        ok "deps/ wins and gives the same object as the cache road, byte for byte"
    else
        fail "vendored object" "differs from the cache road's"
    fi
fi
rm -rf tests/pkg/app/deps

# ---- 9. a package is closed (acceptance 10) ----
build tests/pkg/app-bad "" "$tmp/libs"
want_exit "closure, #include" 1 && want_msg "closure, #include" "package bad reaches outside its tree"
build tests/pkg/app-bad tests/pkg/app-bad/embed.toml "$tmp/libs"
want_exit "closure, #embed" 1 && want_msg "closure, #embed" "package bad reaches outside its tree"

# ---- 10. [package].files is a boundary (acceptance 10, third half) ----
cat > "$tmp/libs/geo/v1.2.0/extra.mc" <<'EOF'
i64 geo_extra() { return 5; }
EOF
build tests/pkg/app-extra "" "$tmp/libs"
want_exit "undeclared file" 1 && want_msg "undeclared file" "not declared in geo's \[package\].files"
rm -f "$tmp/libs/geo/v1.2.0/extra.mc"

# ---- 11. names (acceptance 11) ----
name_case() {                         # name_case LABEL LINE EXPECT
    cat > tests/pkg/app/names.toml <<EOF
[project]
name  = "app"
entry = "main.mc"
out   = "build/x.o"
kind  = "obj"

[deps]
$2
EOF
    build tests/pkg/app tests/pkg/app/names.toml "$tmp/libs"
    got=$(tail -1 "$tmp/o")
    if [ "$rc" != 1 ]; then fail "$1" "exit $rc, expected 1"
    elif ! printf '%s' "$got" | grep -q "$3"; then fail "$1" "got '$got'"
    else ok "$1: $got"
    fi
    rm -f tests/pkg/app/names.toml
}
name_case "reserved name mc"  'mc = "1.0.0"'  'reserved package name: deps.mc'
name_case "invalid name Geo"  'Geo = "1.0.0"' 'invalid package name: deps.Geo'
name_case "reserved name deps" 'deps = "1.0.0"' 'reserved package name: deps.deps'

# ---- 12. a bundled name pinned in [deps] (acceptance 18) ----
build tests/pkg/app-float "" "$tmp/libs"
if want_exit "float override builds" 0; then
    out=$(tests/pkg/app-float/build/appf 2>/dev/null); arc=$?
    if [ "$arc" = 42 ] && [ "$out" = "1.500000!" ]; then
        ok "<float> and <float/float_rt.mc> come from the locked tree ('1.500000!')"
    else
        fail "float override runs" "exit $arc, stdout '$out'"
    fi
fi
build tests/pkg/app-float tests/pkg/app-float/obj.toml "$tmp/libs"
want_exit "float override object" 0 && cp tests/pkg/app-float/build/appf.o "$tmp/out/f1.o"
rm -rf tests/pkg/app-float/deps
mkdir -p tests/pkg/app-float/deps
cp -R tests/pkg/src/float-1.3.0 tests/pkg/app-float/deps/float
build tests/pkg/app-float tests/pkg/app-float/obj.toml "$tmp/empty"
if want_exit "float override, vendored" 0; then
    cmp -s "$tmp/out/f1.o" tests/pkg/app-float/build/appf.o \
        && ok "the override is the same object vendored or installed" \
        || fail "float override" "vendored and installed objects differ"
fi
rm -rf tests/pkg/app-float/deps
printf 'x' >> "$tmp/libs/float/v1.3.0/float_rt.mc"
build tests/pkg/app-float tests/pkg/app-float/obj.toml "$tmp/libs"
want_exit "tampered float_rt.mc" 2 && want_msg "tampered float_rt.mc" "float 1.3.0: float_rt.mc does not match mc.lock"
install_pkg tests/pkg/src/float-1.3.0 float 1.3.0 "$tmp/libs"
# and with the [deps] line gone the bundle answers again, whatever is installed
build tests/pkg/app-float tests/pkg/app-float/nodeps.toml "$tmp/libs"
want_exit "no [deps] float, libs populated" 0 && cp tests/pkg/app-float/build/nodeps.o "$tmp/out/n1.o"
build tests/pkg/app-float tests/pkg/app-float/nodeps.toml "$tmp/empty"
if want_exit "no [deps] float, empty libs" 0; then
    cmp -s "$tmp/out/n1.o" tests/pkg/app-float/build/nodeps.o \
        && ok "with no [deps] the installed float cannot change a byte" \
        || fail "no [deps] float" "the two objects differ"
fi
if cmp -s "$tmp/out/f1.o" "$tmp/out/n1.o"; then
    fail "the override" "the overridden object equals the bundled one -- it changed nothing"
else
    ok "the override does change the object, and removing it puts it back"
fi

# ---- 13. never the working directory ----
cat > "$tmp/out/float.mc" <<'EOF'
i64 shadow() { return 1; }
EOF
cp "$tmp/out/float.mc" tests/pkg/app-float/float.mc
build tests/pkg/app-float tests/pkg/app-float/nodeps.toml "$tmp/empty"
if want_exit "a float.mc next to the entry" 0; then
    cmp -s "$tmp/out/n1.o" tests/pkg/app-float/build/nodeps.o \
        && ok "a float.mc beside the entry does not shadow <float_rt>" \
        || fail "shadowing" "the object moved"
fi
rm -f tests/pkg/app-float/float.mc

# ---- 14. the single-file CLI has no lock and therefore no step 1 ----
cat > "$tmp/out/nolock.mc" <<'EOF'
#include <geo/geo.mc>
i64 main() { return 0; }
EOF
msg=$("$mc" "$tmp/out/nolock.mc" -o "$tmp/out/nolock.o" 2>&1); rc=$?
if [ "$rc" = 1 ] && printf '%s' "$msg" | grep -q "unknown bundled include: geo/geo"; then
    ok "the single-file CLI refuses <geo/geo.mc>: $msg"
else
    fail "single-file CLI" "exit $rc: $msg"
fi

# ---- 15. step 3 of the resolution order: the installed `mc` package ----
# A full binary answers every one of these names out of its own blob and never
# reaches step 3, so the probe is a compiler with no blob: src/mc_slim.mc, which
# since M44 step 4 IS the slim flavour and not a fixture (it replaced
# tests/pkg/nobundle.mc). What this section installs, it installs BY HAND -- the
# layout of § A4 written in shell, a second implementation of what src/install.mc
# writes; § 32 below is the same proof through `mc install` itself.
probe="$tmp/bin/nobundle"
if "$mc" --exe src/mc_slim.mc -o "$probe" > "$tmp/o" 2>&1; then
    ok "the bundle-less probe compiler builds"
    mcd="$tmp/libs/mc/v$("$mc" --version | sed 's/^mc //')"
    mkdir -p "$mcd"
    cp tools/bundle.list "$mcd/bundle.list"
    while IFS="$(printf '\t')" read -r n p; do
        [ -n "$p" ] || continue
        mkdir -p "$mcd/$(dirname "$p")"
        cp "$p" "$mcd/$p"
    done < tools/bundle.list
    # bundle_data.mc is the ONE name the blob cannot carry (it would contain
    # itself); on disk it is an ordinary file that src/core.mc includes by path.
    cp src/bundle_data.mc "$mcd/src/bundle_data.mc"
    cc="$probe"
    build tests/pkg/std "" "$tmp/libs"
    if want_exit "the probe compiles <mc/core> from disk" 0; then
        "$mc" src/mc.mc -o "$tmp/out/ref.o" 2> /dev/null
        if cmp -s tests/pkg/std/build/def.o "$tmp/out/ref.o"; then
            ok "<mc/host> + <mc/core> + <user_default> served from <libs>/mc/v... == src/mc.mc, byte for byte"
        else
            fail "installed mc package" "the object differs from src/mc.mc's"
        fi
    fi
    # the same probe with no installed package says so, with the bundle's words
    build tests/pkg/std "" "$tmp/empty"
    want_exit "the probe with no installed package" 1 \
        && want_msg "the probe with no installed package" \
                    "#include <mc/host>: not bundled in this compiler and mc .* is not installed: run mc install"
    cc="$mc"
else
    fail "the bundle-less probe compiler" "$(cat "$tmp/o")"
fi

# ---- 16. check-standalone under the shim, plus <float> ----
if sh scripts/check-standalone.sh build/mc-exe build/mc2.o > "$tmp/o" 2>&1; then
    ok "check-standalone is green with curl/wget/tar refusing to run"
else
    fail "check-standalone under the shim" "$(tail -3 "$tmp/o")"
fi

# =========================== step 3: the registry ============================
# The fixture registry is a DIRECTORY, built here from tests/pkg/src with the
# real tar:
#
#   $tmp/archives/<name>-<version>.tar.gz   top directory <name>-<version>, so
#                                           strip = 1, GitHub's own shape
#   $tmp/registry/index/<name>.toml         url = that file, sha256 = the TREE
#                                           hash scripts/pkg-hash.sh computes
#
# gzip timestamps make the archives non-reproducible, and nothing hashes them:
# the hash is over CONTENT (M44 D5), which is exactly why a regenerated tarball
# cannot move it. Generating the index here instead of checking it in keeps ONE
# source of truth for the fixture hashes -- the trees -- while still comparing
# two implementations of the rule, since the index is written by the shell one
# and read by the compiler's.
mkarchive() {                         # mkarchive SRCDIR NAME VERSION
    rm -rf "$tmp/stage/$2-$3"
    cp -R "$1" "$tmp/stage/$2-$3"
    ( cd "$tmp/stage" && PATH="$realpath_env" tar -czf "$tmp/archives/$2-$3.tar.gz" "$2-$3" )
}
index_open() {                        # index_open NAME
    { echo "# index/$1.toml -- written by scripts/check-pkg.sh, M44 § 5's layout"
      echo '[package]'
      echo "name        = \"$1\""
      echo "repo        = \"https://example.invalid/mc-$1\""
      echo "description = \"a fixture package\""
    } > "$tmp/registry/index/$1.toml"
}
# $ixx, when set, is written verbatim after `deps`: the M48 keys a row gained
# (kind, bin, permissions, tools, licence). They are written HERE, by the shell,
# and re-derived by the compiler from the archive -- `mc pkg check --yes` is
# what compares the two, so a row that disagrees with its own tree is a red run
# and not a mystery at the consumer.
ixx=""
index_row() {                         # index_row NAME VERSION SRCDIR DEPS YANKED
    { echo
      echo '[[versions]]'
      echo "version = \"$2\""
      echo "url     = \"$tmp/archives/$1-$2.tar.gz\""
      echo "strip   = 1"
      echo "sha256  = \"$(sh scripts/pkg-hash.sh "$3")\""
      echo "deps    = [$4]"
      [ -z "$ixx" ] || printf '%s\n' "$ixx"
      [ -z "$5" ] || echo "yanked  = true"
    } >> "$tmp/registry/index/$1.toml"
    mkarchive "$3" "$1" "$2"
    ixx=""
}

index_open mathx
index_row mathx 1.0.0 tests/pkg/src/mathx-1.0.0 ""
index_row mathx 1.1.0 tests/pkg/src/mathx-1.1.0 ""
index_row mathx 2.0.0 tests/pkg/src/mathx-2.0.0 ""
index_row mathx 2.0.1 tests/pkg/src/mathx-2.0.1 "" yanked
index_row mathx 2.1.0-rc1 tests/pkg/src/mathx-2.1.0-rc1 ""
index_row mathx 2.1.0 tests/pkg/src/mathx-2.1.0 ""
index_open plot
index_row plot 1.0.0 tests/pkg/src/plot-1.0.0 '"mathx 1.1.0"'
index_open heavy
index_row heavy 1.0.0 tests/pkg/src/heavy-1.0.0 '"mathx 2.0.0"'
index_open geo
index_row geo 1.0.0 tests/pkg/src/geo-1.0.0 '"mathx 1.0.0"'
index_row geo 1.2.0 tests/pkg/src/geo-1.2.0 '"mathx 1.0.0"'
# M48: a tool and a library that declares a permission. `net` is published
# twice, and 1.1.0 asks for one thing more than 1.0.0 -- the accept rule's case.
index_open tool
ixx='kind        = "tool"
bin         = "hello-tool"
permissions = ["fs.read workspace", "net"]
licence     = "MIT"'
index_row tool 0.1.0 tests/pkg/src/tool-0.1.0 ""
index_open net
ixx='kind        = "lib"
permissions = ["net"]'
index_row net 1.0.0 tests/pkg/src/net-1.0.0 ""
ixx='permissions = ["exec sh", "net"]'
index_row net 1.1.0 tests/pkg/src/net-1.1.0 ""
reg="$tmp/registry"

# ---- 17. `mc pkg hash` is the same rule as the shell and as the lock ----
for pair in "geo tests/pkg/src/geo-1.2.0" "mathx tests/pkg/src/mathx-1.0.0" \
            "plot tests/pkg/src/plot-1.0.0"; do
    set -- $pair
    got=$("$mc" pkg hash "$2")
    want=$(sh scripts/pkg-hash.sh "$2")
    if [ "$got" = "$want" ]; then ok "mc pkg hash $1: $got"
    else fail "mc pkg hash $1" "mc says $got, pkg-hash.sh says $want"
    fi
done

# ---- 18. the plan is printed and nothing is fetched (acceptance 3) ----
pkg sync tests/pkg/sync --registry "$reg" --libs-dir "$tmp/c1"
if [ "$rc" != 0 ]; then
    fail "sync plan" "exit $rc: $(cat "$tmp/o")"
elif ! grep -q "nothing was downloaded: re-run with --yes" "$tmp/o"; then
    fail "sync plan" "no 'nothing was downloaded' line: $(cat "$tmp/o")"
elif [ "$(grep -c '^fetch  ' "$tmp/o")" != 2 ]; then
    fail "sync plan" "expected 2 fetch rows, got: $(grep -c '^fetch  ' "$tmp/o")"
elif [ -n "$(ls -A "$tmp/c1" 2> /dev/null)" ]; then
    fail "sync plan" "$tmp/c1 is not empty"
elif [ -f tests/pkg/sync/mc.lock ]; then
    fail "sync plan" "a lock was written without --yes"
else
    ok "the plan names 2 archives with their hashes and nothing was fetched"
fi

# ---- 18b. an https registry with no snapshot: the plan is the index files ----
# No network is reached: without --yes the fetch is a PLAN, and the two shims on
# PATH would fail the run if a downloader were spawned. This is the only place
# the URL road is exercised offline, and it is what a first `mc pkg sync`
# against minicompiler.dev prints.
pkg sync tests/pkg/sync --registry https://example.invalid/registry --libs-dir "$tmp/c0"
if [ "$rc" != 0 ]; then
    fail "an https registry, no --yes" "exit $rc: $(cat "$tmp/o")"
elif ! grep -q "^fetch  index " "$tmp/o"; then
    fail "an https registry, no --yes" "no index row in the plan: $(cat "$tmp/o")"
elif ! grep -q "nothing was downloaded" "$tmp/o"; then
    fail "an https registry, no --yes" "$(cat "$tmp/o")"
else
    ok "an https registry with no snapshot: the plan is its index files, nothing spawned"
fi

# ---- 19. MVS, not "latest" (acceptance 4) ----
pkg sync tests/pkg/sync --registry "$reg" --libs-dir "$tmp/c1" --yes
[ -z "$MC_FREEZE" ] || cp tests/pkg/sync/mc.lock tests/pkg/sync/mc.lock.expect
if [ "$rc" != 0 ]; then
    fail "sync --yes" "exit $rc: $(cat "$tmp/o")"
elif ! cmp -s tests/pkg/sync/mc.lock tests/pkg/sync/mc.lock.expect; then
    fail "the lock" "differs from mc.lock.expect: $(diff tests/pkg/sync/mc.lock.expect tests/pkg/sync/mc.lock | head -6)"
else
    ok "sync --yes: mc.lock is mc.lock.expect, mathx at 1.1.0 (MVS, not 1.0.0 and not 2.0.0)"
fi
if [ -f "$tmp/c1/mathx/v1.1.0.toml" ] && [ -f "$tmp/c1/plot/v1.0.0.toml" ] \
   && grep -q '^\[\[file\]\]' "$tmp/c1/plot/v1.0.0.toml"; then
    ok "two manifests exist, written last, with [[file]] rows"
else
    fail "the cache manifests" "$(ls -R "$tmp/c1" | head -10)"
fi
if [ -f "$tmp/c1/mathx/v2.0.0.toml" ] || [ -f "$tmp/c1/mathx/v1.0.0.toml" ]; then
    fail "MVS" "a version nothing selected was fetched"
else
    ok "no unselected version was fetched (1.0.0, 2.0.0 and the yanked 2.0.1 stayed put)"
fi
cp tests/pkg/sync/mc.lock "$tmp/out/lock1"
pkg sync tests/pkg/sync --registry "$reg" --libs-dir "$tmp/c1" --yes
if [ "$rc" != 0 ]; then
    fail "second sync" "exit $rc: $(cat "$tmp/o")"
elif grep -q '^fetch  ' "$tmp/o"; then
    fail "second sync" "it fetched again"
elif ! cmp -s "$tmp/out/lock1" tests/pkg/sync/mc.lock; then
    fail "second sync" "the lock is not byte-identical"
else
    ok "a second sync downloads nothing and rewrites the same lock, byte for byte"
fi

# ---- 20. the fetched chain builds and runs (acceptance 5) ----
build tests/pkg/sync "" "$tmp/c1"
if want_exit "the synced project builds" 0; then
    out=$(tests/pkg/sync/build/sync 2>/dev/null); arc=$?
    if [ "$arc" = 42 ] && [ "$out" = "plot 110" ]; then
        ok "<plot> through the lock's lib entry: exit 42, 'plot 110' (mathx 1.1.0)"
    else
        fail "the synced project runs" "exit $arc, stdout '$out'"
    fi
fi

# ---- 21. two independent fetches give the same object (acceptance 6) ----
build tests/pkg/sync tests/pkg/sync/obj.toml "$tmp/c1"
want_exit "sync object (cache 1)" 0 && cp tests/pkg/sync/build/sync.o "$tmp/out/s1.o"
rm -f tests/pkg/sync/mc.lock
pkg sync tests/pkg/sync --registry "$reg" --libs-dir "$tmp/c2" --yes
want_lock=$?
if ! cmp -s "$tmp/out/lock1" tests/pkg/sync/mc.lock; then
    fail "the second cache" "its lock differs from the first's"
else
    ok "a second fetch into another cache writes the same lock"
fi
build tests/pkg/sync tests/pkg/sync/obj.toml "$tmp/c2"
if want_exit "sync object (cache 2)" 0; then
    cmp -s "$tmp/out/s1.o" tests/pkg/sync/build/sync.o \
        && ok "two fetches, two caches, byte-identical objects" \
        || fail "two fetches" "the objects differ"
fi

# ---- 22. vendoring is the offline road (acceptance 9) ----
pkg vendor tests/pkg/sync --libs-dir "$tmp/c1"
if [ "$rc" != 0 ]; then
    fail "vendor" "exit $rc: $(cat "$tmp/o")"
elif [ ! -f tests/pkg/sync/deps/plot/plot.mc ] || [ ! -f tests/pkg/sync/deps/mathx/mc.toml ]; then
    fail "vendor" "deps/ is not populated: $(ls -R tests/pkg/sync/deps 2>&1 | head -5)"
else
    ok "vendor: deps/plot and deps/mathx hold mc.toml plus [package].files"
fi
build tests/pkg/sync tests/pkg/sync/obj.toml "$tmp/empty"
if want_exit "vendored build with an EMPTY libs dir" 0; then
    cmp -s "$tmp/out/s1.o" tests/pkg/sync/build/sync.o \
        && ok "the vendored tree gives the same object as the cache road, byte for byte" \
        || fail "vendored object" "differs from the cache road's"
fi
PATH="$tmp/bin2:$realpath_env" "$mc" pkg list tests/pkg/sync --libs-dir "$tmp/empty" > "$tmp/o" 2>&1
[ -z "$MC_FREEZE" ] || cp "$tmp/o" tests/golden/pkg-list.txt
if [ $? != 0 ]; then
    fail "pkg list" "$(cat "$tmp/o")"
elif ! cmp -s "$tmp/o" tests/golden/pkg-list.txt; then
    fail "pkg list" "differs from tests/golden/pkg-list.txt: $(diff tests/golden/pkg-list.txt "$tmp/o" | head -5)"
else
    ok "mc pkg list: every row 'vendored', and it matches tests/golden/pkg-list.txt"
fi
PATH="$tmp/bin2:$realpath_env" "$mc" pkg verify tests/pkg/sync --libs-dir "$tmp/empty" > "$tmp/o" 2>&1
grep -q "verified 2 packages against mc.lock" "$tmp/o" \
    && ok "mc pkg verify: verified 2 packages against mc.lock" \
    || fail "pkg verify" "$(cat "$tmp/o")"
rm -rf tests/pkg/sync/deps

# ---- 23. majors are refused, not solved (acceptance 12) ----
pkg sync tests/pkg/major --registry "$reg" --libs-dir "$tmp/c1" --yes
if [ "$rc" != 1 ]; then
    fail "majors" "exit $rc, expected 1: $(cat "$tmp/o")"
elif ! grep -q "mathx: 1.0.0 and 2.0.0: different majors: no solver" "$tmp/o"; then
    fail "majors" "$(cat "$tmp/o")"
elif [ -f tests/pkg/major/mc.lock ]; then
    fail "majors" "a lock was written anyway"
else
    ok "majors: $(cat "$tmp/o")"
fi

# ---- 24. a failed fetch leaves no claim behind (acceptance 13) ----
cp -R "$reg" "$tmp/badreg"
sed 's|/archives/plot-1.0.0.tar.gz|/archives/plot-9.9.9.tar.gz|' "$reg/index/plot.toml" > "$tmp/badreg/index/plot.toml"
pkg sync tests/pkg/sync --registry "$tmp/badreg" --libs-dir "$tmp/c3" --yes
if [ "$rc" != 2 ]; then
    fail "a missing archive" "exit $rc, expected 2: $(cat "$tmp/o")"
elif ! grep -q "^mc: cannot open: " "$tmp/o"; then
    fail "a missing archive" "$(cat "$tmp/o")"
elif [ -f "$tmp/c3/plot/v1.0.0.toml" ]; then
    fail "a missing archive" "a manifest was written for a package that never arrived"
else
    ok "a failed fetch: $(head -1 "$tmp/o"), no manifest"
fi
cp -R "$reg" "$tmp/badsha"
sed 's/^sha256  = "./sha256  = "0/' "$reg/index/mathx.toml" | sed 's/^\(sha256  = "0.\{64\}\).*"$/\1"/' > "$tmp/badsha/index/mathx.toml"
pkg sync tests/pkg/sync --registry "$tmp/badsha" --libs-dir "$tmp/c4" --yes
if [ "$rc" != 2 ]; then
    fail "a wrong hash" "exit $rc, expected 2: $(cat "$tmp/o")"
elif ! grep -q "checksum mismatch for mathx 1.1.0" "$tmp/o"; then
    fail "a wrong hash" "$(cat "$tmp/o")"
elif [ -f "$tmp/c4/mathx/v1.1.0.toml" ] || [ -f "$tmp/c4/mathx/v1.1.0/mathx.mc" ]; then
    fail "a wrong hash" "the refused tree was left behind"
else
    ok "a wrong hash: checksum mismatch, the listed files unlinked, no manifest"
fi
build tests/pkg/sync tests/pkg/sync/obj.toml "$tmp/c4"
want_exit "a build over the debris" 2 \
    && want_msg "a build over the debris" "is not fetched"
rm -f tests/pkg/sync/mc.lock

# ---- 25. `mc pkg add` edits exactly one line (acceptance 14) ----
cp tests/pkg/add/add.toml "$tmp/out/add.toml.orig"
pkg add mathx@1.0.0 tests/pkg/add --config tests/pkg/add/add.toml \
        --registry "$reg" --libs-dir "$tmp/c1" --yes
[ -z "$MC_FREEZE" ] || cp tests/pkg/add/add.toml tests/pkg/add/add.toml.expect
if [ "$rc" != 0 ]; then
    fail "pkg add" "exit $rc: $(cat "$tmp/o")"
elif ! cmp -s tests/pkg/add/add.toml tests/pkg/add/add.toml.expect; then
    fail "pkg add" "$(diff tests/pkg/add/add.toml.expect tests/pkg/add/add.toml | head -8)"
else
    d=$(diff "$tmp/out/add.toml.orig" tests/pkg/add/add.toml | grep -c '^>')
    ok "mc pkg add mathx@1.0.0: add.toml.expect byte for byte ($d lines added, every other byte through)"
fi
pkg add mathx tests/pkg/add --config tests/pkg/add/add.toml \
        --registry "$reg" --libs-dir "$tmp/c1" --yes
if [ "$rc" != 0 ]; then
    fail "pkg add, no version" "exit $rc: $(cat "$tmp/o")"
elif ! grep -q 'mathx = "2.1.0"' tests/pkg/add/add.toml; then
    fail "pkg add, no version" "$(grep mathx tests/pkg/add/add.toml)"
else
    ok "mc pkg add mathx: the newest RELEASED non-yanked row, 2.1.0 -- never the yanked 2.0.1, never the candidate 2.1.0-rc1"
fi
cp "$tmp/out/add.toml.orig" tests/pkg/add/add.toml
rm -f tests/pkg/add/mc.lock

# ---- 25b. pre-releases order below their release and are never chosen ------
# SemVer 2.0 § 11 in the registry: mathx 2.1.0-rc1 sits between the yanked 2.0.1
# and 2.1.0. Four things follow, and each of them is a different half of the rule.
pkg add mathx@2.1.0-rc1 tests/pkg/add --config tests/pkg/add/add.toml \
        --registry "$reg" --libs-dir "$tmp/c1" --yes
if [ "$rc" != 0 ]; then
    fail "pkg add @rc" "exit $rc: $(cat "$tmp/o")"
elif ! grep -q 'mathx = "2.1.0-rc1"' tests/pkg/add/add.toml; then
    fail "pkg add @rc" "$(grep mathx tests/pkg/add/add.toml)"
elif ! grep -q '^version *= *"2.1.0-rc1"$' tests/pkg/add/mc.lock; then
    fail "pkg add @rc" "the lock does not carry the suffix: $(cat tests/pkg/add/mc.lock)"
else
    ok "mc pkg add mathx@2.1.0-rc1: asked for by name, and mc.lock carries the suffix verbatim"
fi
pkg list tests/pkg/add --config tests/pkg/add/add.toml --libs-dir "$tmp/c1"
if [ "$rc" = 0 ] && grep -q '^mathx *2.1.0-rc1' "$tmp/o"; then
    ok "mc pkg list: $(grep mathx "$tmp/o")"
else
    fail "pkg list @rc" "exit $rc: $(cat "$tmp/o")"
fi
upd mathx tests/pkg/add --config tests/pkg/add/add.toml \
        --registry "$reg" --libs-dir "$tmp/c1" --yes
if [ "$rc" != 0 ]; then
    fail "update off a candidate" "exit $rc: $(cat "$tmp/o")"
elif ! grep -q 'mathx = "2.1.0"' tests/pkg/add/add.toml; then
    fail "update off a candidate" "$(grep mathx tests/pkg/add/add.toml)"
else
    ok "mc update from 2.1.0-rc1: raised to 2.1.0 -- the release outranks the candidate"
fi
cp "$tmp/out/add.toml.orig" tests/pkg/add/add.toml
rm -f tests/pkg/add/mc.lock

pkg add mathx@2.0.0 tests/pkg/add --config tests/pkg/add/add.toml \
        --registry "$reg" --libs-dir "$tmp/c1" --yes
if [ "$rc" != 0 ]; then
    fail "sync at a released minimum" "exit $rc: $(cat "$tmp/o")"
elif ! grep -q '^version *= *"2.0.0"$' tests/pkg/add/mc.lock; then
    fail "sync at a released minimum" "$(cat tests/pkg/add/mc.lock)"
elif grep -q 'rc1' tests/pkg/add/mc.lock; then
    fail "sync at a released minimum" "the candidate reached the lock"
else
    ok "sync with the minimum 2.0.0: MVS locks 2.0.0, never the newer 2.1.0-rc1"
fi
upd mathx tests/pkg/add --config tests/pkg/add/add.toml \
        --registry "$reg" --libs-dir "$tmp/c1" --yes
if [ "$rc" != 0 ]; then
    fail "update past a candidate" "exit $rc: $(cat "$tmp/o")"
elif ! grep -q 'mathx = "2.1.0"' tests/pkg/add/add.toml; then
    fail "update past a candidate" "$(grep mathx tests/pkg/add/add.toml)"
else
    ok "mc update from 2.0.0: 2.1.0, stepping OVER 2.1.0-rc1"
fi
cp "$tmp/out/add.toml.orig" tests/pkg/add/add.toml
rm -f tests/pkg/add/mc.lock
rm -rf tests/pkg/add/deps

# ---- 26. `mc update` raises a minimum, inside its own major ----
pkg sync tests/pkg/sync --registry "$reg" --libs-dir "$tmp/c1" --yes
cp tests/pkg/sync/mc.toml "$tmp/out/sync.toml.orig"
upd mathx tests/pkg/sync --registry "$reg" --libs-dir "$tmp/c1" --yes
if [ "$rc" != 0 ]; then
    fail "mc update" "exit $rc: $(cat "$tmp/o")"
elif ! grep -q 'mathx = "1.1.0"' tests/pkg/sync/mc.toml; then
    fail "mc update" "$(grep mathx tests/pkg/sync/mc.toml)"
else
    ok "mc update mathx: 1.0.0 -> 1.1.0, the newest of ITS major (2.0.0 is not an update)"
fi
cp "$tmp/out/sync.toml.orig" tests/pkg/sync/mc.toml
rm -f tests/pkg/sync/mc.lock

# ---- 27. `mc pkg check` is the registry gate (acceptance 15) ----
pkg check "$reg/index/geo.toml" --registry "$reg" --libs-dir "$tmp/chk" --yes
if [ "$rc" = 0 ] && grep -q "^ok     geo 1.2.0" "$tmp/o"; then
    ok "mc pkg check geo.toml --yes: both rows re-derived from their archives"
else
    fail "pkg check" "exit $rc: $(cat "$tmp/o")"
fi
pkg check "$reg/index/geo.toml" --registry "$reg" --libs-dir "$tmp/chk"
if [ "$rc" = 0 ] && grep -q "^would check geo 1.2.0" "$tmp/o" \
   && grep -q "nothing was downloaded" "$tmp/o"; then
    ok "mc pkg check without --yes: what it would check, and nothing downloaded"
else
    fail "pkg check, no --yes" "exit $rc: $(cat "$tmp/o")"
fi
sed 's/^name        = "geo"/name        = "mc"/' "$reg/index/geo.toml" > "$tmp/out/mc.toml.bad"
pkg check "$tmp/out/mc.toml.bad" --libs-dir "$tmp/chk" --yes
if [ "$rc" = 1 ] && grep -q "reserved package name: package.name" "$tmp/o"; then
    ok "mc pkg check refuses name = \"mc\": $(tail -1 "$tmp/o")"
else
    fail "pkg check, reserved name" "exit $rc: $(cat "$tmp/o")"
fi
sed 's/^\(sha256  = "\)./\10/' "$reg/index/plot.toml" | sed 's/^\(sha256  = "0.\{63\}\).*"$/\1"/' > "$tmp/out/plot-badsha.toml"
pkg check "$tmp/out/plot-badsha.toml" --libs-dir "$tmp/chk2" --yes
if [ "$rc" = 2 ] && grep -q "checksum mismatch for plot 1.0.0" "$tmp/o"; then
    ok "mc pkg check refuses a row whose hash is not the archive's: exit 2"
else
    fail "pkg check, wrong hash" "exit $rc: $(cat "$tmp/o")"
fi
sed 's|/archives/plot-1.0.0.tar.gz|/archives/plot-1.0.0.tar.gz?v=2|' "$reg/index/plot.toml" > "$tmp/out/plot-edited.toml"
pkg check "$tmp/out/plot-edited.toml" --registry "$reg" --libs-dir "$tmp/chk"
if [ "$rc" = 1 ] && grep -q "a published row was edited" "$tmp/o"; then
    ok "mc pkg check refuses an edit to a published row: $(tail -1 "$tmp/o")"
else
    fail "pkg check, edited row" "exit $rc: $(cat "$tmp/o")"
fi

# ---- 28. the part that is not there: a compiler without <mc/core_pkg> ----
# It builds the vendored project of step 22 -- reading a lock and a deps/ tree
# is <mc/core_build>'s (D12) -- and it advertises neither `pkg` nor `update`.
nopkg="$tmp/bin/nopkg"
if "$mc" --exe tests/pkg/nopkg.mc -o "$nopkg" > "$tmp/o" 2>&1; then
    ok "the pkg-less probe compiler builds"
    if "$nopkg" 2>&1 | grep -qE 'mc (pkg|update)'; then
        fail "the pkg-less compiler" "it still prints a pkg or update usage line"
    else
        ok "no <mc/core_pkg>: no 'mc pkg' and no 'mc update' usage line"
    fi
    msg=$("$nopkg" pkg 2>&1); prc=$?
    if [ "$prc" = 1 ] && [ "$msg" = "mc: cannot open: pkg" ]; then
        ok "no <mc/core_pkg>: 'mc pkg' is an ordinary file name, exit 1"
    else
        fail "the pkg-less compiler" "'pkg' said [$msg], exit $prc"
    fi
    mkdir -p tests/pkg/sync/deps
    cp -R tests/pkg/src/plot-1.0.0  tests/pkg/sync/deps/plot
    cp -R tests/pkg/src/mathx-1.1.0 tests/pkg/sync/deps/mathx
    cp "$tmp/out/lock1" tests/pkg/sync/mc.lock
    cc="$nopkg"
    build tests/pkg/sync tests/pkg/sync/obj.toml "$tmp/empty"
    if want_exit "the pkg-less compiler builds the vendored project" 0; then
        cmp -s "$tmp/out/s1.o" tests/pkg/sync/build/sync.o \
            && ok "a compiler with no fetcher builds the vendored project, same object" \
            || fail "the pkg-less compiler" "its object differs"
    fi
    cc="$mc"
    rm -rf tests/pkg/sync/deps tests/pkg/sync/mc.lock
else
    fail "the pkg-less probe compiler" "$(cat "$tmp/o")"
fi

# ---- 29. the post-M44 supply-chain review ----
# Six findings, each with the shape that reproduced it before the batch. The
# common thread is that everything a package SAYS about itself -- the paths in
# [package].files, the member names in its archive -- arrives from a registry
# row and used to be handed straight to open(), write_file() and unlink().

# 29a. a files entry that escapes, in the four shapes it can take. `$esc` holds
# a canary the entry points at, so the assertion is not only "it refused" but
# "the file outside was not touched".
esc_setup() {                         # esc_setup FILES-ARRAY
    rm -rf "$tmp/esc"
    mkdir -p "$tmp/esc/libs/evil/v1.0.0" "$tmp/esc/a/b/proj"
    echo CANARY > "$tmp/esc/canary.txt"
    echo 'i64 evil_x() { return 1; }' > "$tmp/esc/libs/evil/v1.0.0/evil.mc"
    printf '[package]\nname  = "evil"\nfiles = %s\nlib   = "evil.mc"\n' "$1" \
        > "$tmp/esc/libs/evil/v1.0.0/mc.toml"
    printf '[source]\nname = "evil"\nversion = "1.0.0"\nsha256 = "%064d"\n' 0 \
        > "$tmp/esc/libs/evil/v1.0.0.toml"
    printf '[project]\nname  = "p"\nentry = "main.mc"\nout   = "build/p.o"\nkind  = "obj"\n\n[deps]\nevil = "1.0.0"\n' \
        > "$tmp/esc/a/b/proj/mc.toml"
    printf '[[package]]\nname    = "evil"\nversion = "1.0.0"\nlib     = "evil.mc"\nsha256  = "%064d"\ndeps    = []\n' 0 \
        > "$tmp/esc/a/b/proj/mc.lock"
    printf '#include <sys>\ni64 main() { return 42; }\n' > "$tmp/esc/a/b/proj/main.mc"
}
esc_case() {                          # esc_case LABEL FILES-ARRAY ENTRY
    esc_setup "$2"
    build "$tmp/esc/a/b/proj" "" "$tmp/esc/libs"
    want_exit "files escape ($1)" 2 \
        && want_msg "files escape ($1)" "evil 1.0.0: files entry escapes the package: $3"
}
esc_case "..\/"          '["evil.mc", "../../../canary.txt"]'  '\.\./\.\./\.\./canary.txt'
esc_case "absolute"      '["evil.mc", "/etc/passwd"]'          '/etc/passwd'
esc_case "a\/..\/..\/x"  '["evil.mc", "a/../../canary.txt"]'   'a/\.\./\.\./canary.txt'
esc_case "a newline"     '["evil.mc", "a.mc\\nx"]'             'a.mc'
esc_case "a drive letter" '["evil.mc", "C:/canary.txt"]'        'C:/canary.txt'
esc_case "a reserved char" '["evil.mc", "a<b.mc"]'              'a<b.mc'

# the WRITE half: `mc pkg vendor` copied the entry out of the project entirely
esc_setup '["evil.mc", "../../../canary.txt"]'
pkg vendor "$tmp/esc/a/b/proj" --libs-dir "$tmp/esc/libs"
if want_exit "vendor refuses an escaping files entry" 2; then
    # deps/evil/../../../canary.txt is $tmp/esc/a/b/canary.txt, which the
    # package's own tree resolves to $tmp/esc/canary.txt: two different files,
    # so a copy that happened is a file that appeared
    if [ -f "$tmp/esc/a/b/canary.txt" ]; then
        fail "vendor refuses an escaping files entry" "a copy landed outside deps/"
    else
        ok "vendor refuses an escaping files entry: nothing was written outside deps/"
    fi
fi

# 29b. the unbless-as-delete: a row whose sha256 is wrong made mc re-read the
# just-extracted (untrusted) mc.toml and unlink everything it listed. The
# attacker never needed a hash that passes.
rm -rf "$tmp/del"
mkdir -p "$tmp/del/libs" "$tmp/del/reg/index" "$tmp/del/stage/del-1.0.0" "$tmp/del/proj"
echo IMPORTANT > "$tmp/del/canary.txt"
echo 'i64 del_x() { return 1; }' > "$tmp/del/stage/del-1.0.0/del.mc"
printf '[package]\nname  = "del"\nfiles = ["del.mc", "../../../canary.txt"]\nlib   = "del.mc"\n' \
    > "$tmp/del/stage/del-1.0.0/mc.toml"
(cd "$tmp/del/stage" && rtar -czf "$tmp/del/del-1.0.0.tar.gz" del-1.0.0)
printf '[package]\nname = "del"\nrepo = "https://example.invalid/del"\n\n[[versions]]\nversion = "1.0.0"\nurl     = "%s"\nstrip   = 1\nsha256  = "%064d"\ndeps    = []\n' \
    "$tmp/del/del-1.0.0.tar.gz" 0 > "$tmp/del/reg/index/del.toml"
printf '[project]\nname  = "p"\nentry = "main.mc"\nout   = "build/p.o"\nkind  = "obj"\n\n[deps]\ndel = "1.0.0"\n' \
    > "$tmp/del/proj/mc.toml"
printf '#include <sys>\ni64 main() { return 42; }\n' > "$tmp/del/proj/main.mc"
pkg sync "$tmp/del/proj" --registry "$tmp/del/reg" --libs-dir "$tmp/del/libs" --yes
if want_exit "a fetched tree whose files escape" 2; then
    if [ -f "$tmp/del/canary.txt" ]; then
        ok "the refused tree did not delete the file its mc.toml pointed at"
    else
        fail "unbless" "the canary outside the tree was unlinked"
    fi
fi
[ -f "$tmp/del/libs/del/v1.0.0.toml" ] \
    && fail "unbless" "a manifest was written for a refused tree" \
    || ok "the refused tree carries no manifest and no debris"

# 29c. the archive itself: tar used to be trusted with a file somebody else
# produced. The three member shapes, each crafted here.
rm -rf "$tmp/arc"
mkdir -p "$tmp/arc/libs" "$tmp/arc/reg/index" "$tmp/arc/stage/a-1.0.0" "$tmp/arc/proj"
echo 'i64 a_x() { return 1; }' > "$tmp/arc/stage/a-1.0.0/a.mc"
printf '[package]\nname  = "a"\nfiles = ["a.mc"]\nlib   = "a.mc"\n' > "$tmp/arc/stage/a-1.0.0/mc.toml"
printf '[project]\nname  = "p"\nentry = "main.mc"\nout   = "build/p.o"\nkind  = "obj"\n\n[deps]\na = "1.0.0"\n' \
    > "$tmp/arc/proj/mc.toml"
printf '#include <sys>\ni64 main() { return 42; }\n' > "$tmp/arc/proj/main.mc"
arc_row() {                           # arc_row ARCHIVE
    printf '[package]\nname = "a"\nrepo = "https://example.invalid/a"\n\n[[versions]]\nversion = "1.0.0"\nurl     = "%s"\nstrip   = 1\nsha256  = "%064d"\ndeps    = []\n' \
        "$1" 0 > "$tmp/arc/reg/index/a.toml"
}
arc_case() {                          # arc_case LABEL ARCHIVE TEXT
    arc_row "$2"
    rm -rf "$tmp/arc/libs" "$tmp/arc/proj/mc.lock"
    mkdir -p "$tmp/arc/libs"
    pkg sync "$tmp/arc/proj" --registry "$tmp/arc/reg" --libs-dir "$tmp/arc/libs" --yes
    want_exit "archive member ($1)" 2 && want_msg "archive member ($1)" "$3"
}
if ln -s /etc/hosts "$tmp/arc/stage/a-1.0.0/link.mc" 2> /dev/null; then
    (cd "$tmp/arc/stage" && rtar -czf "$tmp/arc/sym.tar.gz" a-1.0.0)
    rm -f "$tmp/arc/stage/a-1.0.0/link.mc"
    arc_case "a symlink" "$tmp/arc/sym.tar.gz" "archive member is a link"
else
    ok "SKIPPED archive member (a symlink): this filesystem has no ln -s"
fi
if ln "$tmp/arc/stage/a-1.0.0/a.mc" "$tmp/arc/stage/a-1.0.0/hard.mc" 2> /dev/null; then
    (cd "$tmp/arc/stage" && rtar -czf "$tmp/arc/hard.tar.gz" a-1.0.0)
    rm -f "$tmp/arc/stage/a-1.0.0/hard.mc"
    arc_case "a hard link" "$tmp/arc/hard.tar.gz" "archive member is a link"
else
    ok "SKIPPED archive member (a hard link): this filesystem has no ln"
fi
# a member that leaves the destination once --strip-components=1 is applied
(cd "$tmp/arc/stage/a-1.0.0" && rtar -czf "$tmp/arc/esc.tar.gz" ../a-1.0.0/mc.toml ../a-1.0.0/a.mc ../../stage/a-1.0.0/a.mc 2> /dev/null)
if rtar -tzf "$tmp/arc/esc.tar.gz" 2> /dev/null | grep -q '\.\.'; then
    arc_case "a .. member" "$tmp/arc/esc.tar.gz" "member escapes the archive"
else
    ok "SKIPPED archive member (a .. member): this tar will not store one"
fi
# and the archive a package is really made of still goes through
(cd "$tmp/arc/stage" && rtar -czf "$tmp/arc/ok.tar.gz" a-1.0.0)
arc_row "$tmp/arc/ok.tar.gz"
rm -rf "$tmp/arc/libs" "$tmp/arc/proj/mc.lock"
mkdir -p "$tmp/arc/libs"
h=$(sh scripts/pkg-hash.sh "$tmp/arc/stage/a-1.0.0")
sed "s/^sha256  = .*/sha256  = \"$h\"/" "$tmp/arc/reg/index/a.toml" > "$tmp/arc/reg/index/a.toml.new"
mv "$tmp/arc/reg/index/a.toml.new" "$tmp/arc/reg/index/a.toml"
pkg sync "$tmp/arc/proj" --registry "$tmp/arc/reg" --libs-dir "$tmp/arc/libs" --yes
want_exit "an ordinary archive still extracts" 0 \
    && ok "the member check passes an ordinary package archive"

# 29d. `mc pkg check` used to answer "immutable" by doing nothing whenever it
# could not read the published index -- without --yes, and on ANY failed fetch.
pkg check "$tmp/registry/index/plot.toml" --registry https://example.invalid --libs-dir "$tmp/chk"
want_exit "check without --yes against a URL registry" 2 \
    && want_msg "check without --yes against a URL registry" "check needs --yes to compare against the published index"
pkg check "$tmp/registry/index/plot.toml" --registry https://example.invalid --libs-dir "$tmp/chk" --yes
want_exit "check with an unreadable published index" 2 \
    && want_msg "check with an unreadable published index" "cannot read the published index for plot"

# 29e. the size caps: neither a downloaded body nor a local path had one.
rm -rf "$tmp/big"
mkdir -p "$tmp/big/libs" "$tmp/big/reg/index" "$tmp/big/proj"
dd if=/dev/zero of="$tmp/big/huge.tar.gz" bs=1 count=1 seek=68000000 > /dev/null 2>&1
printf '[package]\nname = "a"\nrepo = "https://example.invalid/a"\n\n[[versions]]\nversion = "1.0.0"\nurl     = "%s"\nstrip   = 1\nsha256  = "%064d"\ndeps    = []\n' \
    "$tmp/big/huge.tar.gz" 0 > "$tmp/big/reg/index/a.toml"
printf '[project]\nname  = "p"\nentry = "main.mc"\nout   = "build/p.o"\nkind  = "obj"\n\n[deps]\na = "1.0.0"\n' \
    > "$tmp/big/proj/mc.toml"
printf '#include <sys>\ni64 main() { return 42; }\n' > "$tmp/big/proj/main.mc"
pkg sync "$tmp/big/proj" --registry "$tmp/big/reg" --libs-dir "$tmp/big/libs" --yes
want_exit "an archive over the 64 MiB cap" 2 \
    && want_msg "an archive over the 64 MiB cap" "larger than the cap of 67108864 bytes"
rm -f "$tmp/big/huge.tar.gz"

# 29f. the hash lines are length-prefixed, and the two implementations still
# agree on the new shape (the tree-hash cases above already compare them; this
# is the format itself, read once).
if sh scripts/pkg-hash.sh --lines tests/pkg/src/mathx-1.0.0 | grep -q '^[0-9a-f]\{64\} 8:mathx.mc$'; then
    ok "the hash line is <hex> <byte length>:<path>, not <hex> two spaces <path>"
else
    fail "the hash line format" "$(sh scripts/pkg-hash.sh --lines tests/pkg/src/mathx-1.0.0 | tr '\n' '|')"
fi

# ======================= S5: this repository is a package =====================
# mc.toml at the root carries [package] name = "mc" (docs/specs/M47-S5.md,
# docs/reference/packages.md § The `mc` package). Three things are asserted:
# the array does not drift from tools/bundle.list, the two hash implementations
# agree on it, and `mc pkg hash .` -- the argument a person types -- answers the
# same hash as the absolute path.
cd "$here" || exit 1

# 30a. `files` is exactly `cut -f2 tools/bundle.list | LC_ALL=C sort -u` plus the
# four files that list cannot name: the blob (which cannot be in a bundle of
# itself), the NAME<TAB>PATH map itself, and the two the [package].check entry
# needs -- the entry point src/mc_linux_x86_64.mc and the src/user.mc it
# includes, neither of which has a bundle row (a compiler is BUILT from them;
# they are not names it serves). A check entry that is not in `files` is
# refused by the registry's validator, since the tree hash covers `files` alone.
#
# LC_ALL=C is not decoration. Under a UTF-8 locale macOS collates `_` BEFORE
# `.`, so `lib/float_rt.mc` sorts above `lib/float.mc` and `lib/sys_linux.mc`
# above `lib/sys.mc` -- a developer with LANG unset and a runner with it set
# disagree about the order of the array, and the manifest order is what the tree
# hash is over. The byte order is the only one that is the same everywhere.
{ cut -f2 tools/bundle.list; echo "src/bundle_data.mc"; echo "tools/bundle.list"
  echo "src/mc_linux_x86_64.mc"; echo "src/user.mc"; } \
    | LC_ALL=C sort -u > "$tmp/out/want-files"
sed -n 's/^    "\(.*\)",$/\1/p' mc.toml > "$tmp/out/got-files"
if cmp -s "$tmp/out/want-files" "$tmp/out/got-files"; then
    ok "mc.toml [package].files == tools/bundle.list + the four it cannot name"
else
    fail "mc.toml [package].files drifted from tools/bundle.list" \
         "$(diff "$tmp/out/want-files" "$tmp/out/got-files" | head -6 | tr '\n' '|')"
fi

# 30b. every entry is readable where the manifest says it is (the tree hash
# below would say so too, but not by name).
missing=""
while IFS= read -r f; do
    [ -f "$f" ] || missing="$missing $f"
done < "$tmp/out/got-files"
if [ -z "$missing" ]; then
    ok "every [package].files entry of the root manifest is on disk"
else
    fail "root manifest files" "missing:$missing"
fi

# 30b'. every [package].check entry is in [package].files and on disk. The
# registry compiles those units and refuses one the package does not ship
# (`[package].check names a file [package].files does not declare`), so the
# drift this catches is one nobody would see until a tag failed to publish.
sed -n 's/^check *= *\[\(.*\)\]$/\1/p' mc.toml | tr ',' '\n' \
    | sed -n 's/^ *"\(.*\)" *$/\1/p' > "$tmp/out/check-units"
if [ ! -s "$tmp/out/check-units" ]; then
    fail "root manifest check" "[package].check is empty or unreadable"
else
    bad=""
    while IFS= read -r f; do
        [ -f "$f" ] || bad="$bad $f(missing)"
        grep -qx "$f" "$tmp/out/got-files" || bad="$bad $f(not-in-files)"
    done < "$tmp/out/check-units"
    if [ -z "$bad" ]; then
        ok "every [package].check unit is on disk and in [package].files ($(tr '\n' ' ' < "$tmp/out/check-units"))"
    else
        fail "root manifest check units" "$bad"
    fi
fi

# 30c/30d. the compiler and the shell agree, and `.` is the same package as the
# absolute path. `mc pkg hash .` used to be `files entry escapes the package`
# for EVERY package -- path_norm answers "." for a directory with no segments
# and path_join then drops that segment, so the prefix test in dep_under could
# never match (fixed with this section).
h_abs=$("$mc" pkg hash "$here")
h_dot=$(cd "$here" && "$mc" pkg hash .)
h_sh=$(sh scripts/pkg-hash.sh "$here")
if [ -n "$h_abs" ] && [ "$h_abs" = "$h_sh" ]; then
    ok "the root package's tree hash: mc and pkg-hash.sh agree ($h_abs)"
else
    fail "the root package's tree hash" "mc=$h_abs sh=$h_sh"
fi
if [ "$h_dot" = "$h_abs" ]; then
    ok "\`mc pkg hash .\` is the same package as \`mc pkg hash <abs>\`"
else
    fail "mc pkg hash ." "$h_dot (absolute: $h_abs)"
fi

# 30e. and the containment rule still refuses, with `.` as the base.
mkdir -p "$tmp/dot"
echo canary > "$tmp/canary.txt"
printf 'i64 f() { return 0; }\n' > "$tmp/dot/a.mc"
for entry in "../canary.txt" "/etc/hosts" "./a.mc" "a/../../canary.txt"; do
    printf '[package]\nname  = "p"\nfiles = ["%s"]\n' "$entry" > "$tmp/dot/mc.toml"
    msg=$( (cd "$tmp/dot" && "$mc" pkg hash .) 2>&1 ); rc=$?
    case "$rc:$msg" in
        2:*"files entry escapes the package: $entry") ok "\`.\` as the base still refuses: $entry" ;;
        *) fail "\`.\` as the base refuses $entry" "exit $rc: $msg" ;;
    esac
done

# ---- 31. M48 C1: the kind, the permissions and what the lock records ----
# Acceptance § 9 items 2 and 3. The fixtures are a TOOL (`[project] kind =
# "exe"`, a `bin`, two permissions) and a LIBRARY published twice, the second
# time asking for one thing more than the first.

# 31a. the install table, and nothing fetched without --yes
pkg sync tests/pkg/perm --registry "$reg" --libs-dir "$tmp/p1"
tbl="$tmp/o"
if [ "$rc" != 0 ]; then
    fail "the install table" "exit $rc: $(cat "$tbl")"
elif ! grep -q '^fetch  tool 0.1.0 *tool  bin hello-tool$' "$tbl"; then
    fail "the install table" "no tool fetch line: $(cat "$tbl")"
elif ! grep -q '^  tool 0.1.0       fs.read workspace     may read files under the directory it is run from$' "$tbl"; then
    fail "the install table" "no fs.read sentence: $(cat "$tbl")"
elif ! grep -q '^                   net                   may open network connections to any host and port$' "$tbl"; then
    fail "the install table" "no net sentence: $(cat "$tbl")"
elif ! grep -q '(declared by the author; a library runs inside your program)' "$tbl"; then
    fail "the install table" "no library caveat: $(cat "$tbl")"
elif ! grep -q '^tools required by this project$' "$tbl" || ! grep -q '^  tool >= 0.1.0$' "$tbl"; then
    fail "the install table" "no tools block: $(cat "$tbl")"
elif ! grep -q '^nothing was downloaded: re-run with --yes to fetch and to accept the permissions above$' "$tbl"; then
    fail "the install table" "the last line is: $(tail -1 "$tbl")"
elif [ -f tests/pkg/perm/mc.lock ] || [ -n "$(ls -A "$tmp/p1" 2> /dev/null)" ]; then
    fail "the install table" "something was written without --yes"
else
    ok "the install table: the tool's fetch line, both sentences, the caveat, the tools block, nothing fetched"
fi
grep -q 'these permissions were declared by each package.s author and checked by the registry where the package runs a test; a library runs inside your program and is held to nothing at run time' "$tbl" \
    && ok "the table carries the trust sentence, and it does not say safe" \
    || fail "the trust sentence" "$(cat "$tbl")"

# 31b. --yes fetches and locks, with kind, bin and the two sets
pkg sync tests/pkg/perm --registry "$reg" --libs-dir "$tmp/p1" --yes
[ -z "$MC_FREEZE" ] || cp tests/pkg/perm/mc.lock tests/pkg/perm/mc.lock.expect
if [ "$rc" != 0 ]; then
    fail "sync --yes (perm)" "exit $rc: $(cat "$tmp/o")"
elif ! cmp -s tests/pkg/perm/mc.lock tests/pkg/perm/mc.lock.expect; then
    fail "the perm lock" "differs: $(diff tests/pkg/perm/mc.lock.expect tests/pkg/perm/mc.lock | head -8)"
else
    ok "sync --yes: the lock is mc.lock.expect -- kind = \"tool\", bin, and both permission sets"
fi
grep -q '^permissions = \["fs.read workspace", "net"\]$' tests/pkg/perm/mc.lock \
    && grep -q '^permissions = \["net"\]$' tests/pkg/perm/mc.lock \
    && grep -q '^permissions = \[\]$' tests/pkg/sync/mc.lock.expect \
    && ok "the lock's sets are canonical and sorted, and a package that asks for nothing writes []" \
    || fail "the lock's permissions" "$(cat tests/pkg/perm/mc.lock)"
cp tests/pkg/perm/mc.lock "$tmp/out/perm.lock"

# 31c. a second sync has nothing to fetch and nothing new to accept
pkg sync tests/pkg/perm --registry "$reg" --libs-dir "$tmp/p1"
if [ "$rc" != 0 ]; then
    fail "the second sync" "exit $rc: $(cat "$tmp/o")"
elif grep -q 'permissions' "$tmp/o" || grep -q 'nothing was downloaded' "$tmp/o"; then
    fail "the second sync" "it asked again: $(cat "$tmp/o")"
elif ! cmp -s "$tmp/out/perm.lock" tests/pkg/perm/mc.lock; then
    fail "the second sync" "the lock moved"
else
    ok "a second sync needs no --yes: the accepted sets cover what is required"
fi

# 31d. one permission MORE stops it, and prints only the package that changed
sed 's/^net = "1.0.0"/net = "1.1.0"/' tests/pkg/perm/mc.toml > "$tmp/out/perm11.toml"
cp "$tmp/out/perm11.toml" tests/pkg/perm/wider.toml
pkg sync tests/pkg/perm --config tests/pkg/perm/wider.toml --registry "$reg" --libs-dir "$tmp/p1"
if [ "$rc" != 0 ]; then
    fail "a wider set" "exit $rc: $(cat "$tmp/o")"
elif ! grep -q '^  net 1.1.0        exec sh               may run the program `sh` found on your PATH$' "$tmp/o"; then
    fail "a wider set" "$(cat "$tmp/o")"
elif grep -q '^  tool 0.1.0' "$tmp/o"; then
    fail "a wider set" "it printed a package whose set was already accepted"
elif ! grep -q 'to fetch and to accept the permissions above' "$tmp/o"; then
    fail "a wider set" "$(tail -1 "$tmp/o")"
elif ! cmp -s "$tmp/out/perm.lock" tests/pkg/perm/mc.lock; then
    fail "a wider set" "the lock was rewritten without --yes"
else
    ok "a version that adds one permission stops the sync and prints only the package that changed"
fi
rm -f tests/pkg/perm/wider.toml

# 31e. the tool is inert at build time: no root, no tree, no byte
build tests/pkg/perm tests/pkg/perm/obj.toml "$tmp/p1"
want_exit "perm builds with the tool locked" 0 && cp tests/pkg/perm/build/perm.o "$tmp/out/perm1.o"
build tests/pkg/perm tests/pkg/perm/notools.toml "$tmp/p1"
if want_exit "perm builds with no [tools] table" 0; then
    cmp -s "$tmp/out/perm1.o" tests/pkg/perm/build/perm-nt.o \
        && ok "the [tools] table changes no byte: the two objects are identical" \
        || fail "the [tools] table" "the objects differ"
fi
mv "$tmp/p1/tool" "$tmp/out/tool-away"
build tests/pkg/perm tests/pkg/perm/obj.toml "$tmp/p1"
if want_exit "perm builds with the tool's tree GONE" 0; then
    cmp -s "$tmp/out/perm1.o" tests/pkg/perm/build/perm.o \
        && ok "a build never opens the tool's tree: it is not there and nothing noticed" \
        || fail "the tool's tree" "the object moved"
fi
mv "$tmp/out/tool-away" "$tmp/p1/tool"
build tests/pkg/perm "" "$tmp/p1"
if want_exit "the perm program builds" 0; then
    out=$(tests/pkg/perm/build/perm > /dev/null 2>&1; echo $?)
    [ "$out" = 42 ] && ok "<net/net.mc> through the lock: exit 42" \
                    || fail "the perm program" "exit $out"
fi

# 31f. mc pkg list gains the column, and --long the reasons
PATH="$tmp/bin2:$realpath_env" "$mc" pkg list tests/pkg/perm --libs-dir "$tmp/p1" > "$tmp/o" 2>&1
if grep -q '^net          1.0.0    .\{12\} cache    net$' "$tmp/o" \
   && grep -q '^tool         0.1.0    .\{12\} tool     fs.read workspace, net$' "$tmp/o"; then
    ok "mc pkg list: the permissions column, and tool as the road of a row no build opens"
else
    fail "mc pkg list" "$(cat "$tmp/o")"
fi
PATH="$tmp/bin2:$realpath_env" "$mc" pkg list tests/pkg/perm --libs-dir "$tmp/p1" --long > "$tmp/o" 2>&1
grep -q '^    net                   sends what it measured to a collector$' "$tmp/o" \
    && ok "mc pkg list --long: the reason, read out of the tree and not out of the lock" \
    || fail "mc pkg list --long" "$(cat "$tmp/o")"

# 31g. `mc pkg check` re-derives the five new keys from the archive
pkg check "$reg/index/tool.toml" --registry "$reg" --libs-dir "$tmp/chk3" --yes
if [ "$rc" = 0 ] && grep -q "^ok     tool 0.1.0" "$tmp/o"; then
    ok "mc pkg check tool.toml --yes: kind, bin, permissions, tools and licence re-derived"
else
    fail "pkg check, a tool row" "exit $rc: $(cat "$tmp/o")"
fi
sed 's/^permissions = \["fs.read workspace", "net"\]/permissions = ["net"]/' "$reg/index/tool.toml" > "$tmp/out/tool-liar.toml"
pkg check "$tmp/out/tool-liar.toml" --libs-dir "$tmp/chk4" --yes
if [ "$rc" = 1 ] && grep -q "the row's permissions are not the archive's" "$tmp/o"; then
    ok "mc pkg check refuses a row that under-declares its archive's permissions"
else
    fail "pkg check, a lying row" "exit $rc: $(cat "$tmp/o")"
fi

# 31h. the four refusals, each at the offending key's own file:line:col
badpkg() {                            # badpkg LABEL MANIFEST EXPECT
    rm -rf "$tmp/badp/x-1.0.0"
    mkdir -p "$tmp/badp/x-1.0.0"
    printf '%s' "$2" > "$tmp/badp/x-1.0.0/mc.toml"
    printf 'i64 x_f() { return 1; }\n' > "$tmp/badp/x-1.0.0/x.mc"
    ( cd "$tmp/badp" && PATH="$realpath_env" tar -czf "$tmp/archives/x-1.0.0.tar.gz" x-1.0.0 )
    mkdir -p "$tmp/badreg2/index"
    printf '[package]\nname = "x"\n\n[[versions]]\nversion = "1.0.0"\nurl     = "%s"\nstrip   = 1\nsha256  = "%s"\ndeps    = []\n' \
        "$tmp/archives/x-1.0.0.tar.gz" "$(sh scripts/pkg-hash.sh "$tmp/badp/x-1.0.0")" \
        > "$tmp/badreg2/index/x.toml"
    rm -rf "$tmp/bp"
    pkg check "$tmp/badreg2/index/x.toml" --libs-dir "$tmp/bp" --yes
    if [ "$rc" != 1 ]; then
        fail "$1" "exit $rc: $(cat "$tmp/o")"
    elif ! grep -q "$3" "$tmp/o"; then
        fail "$1" "$(cat "$tmp/o")"
    elif [ -f "$tmp/bp/x/v1.0.0.toml" ]; then
        fail "$1" "the refused tree was blessed anyway"
    else
        ok "$1: $(grep -m1 "$3" "$tmp/o" | sed 's|^.*/mc.toml:|mc.toml:|')"
    fi
}
badpkg "an absolute permission path" \
    '[package]
name  = "x"
files = ["x.mc"]

[[permission]]
kind = "fs.read"
path = "/etc"
' 'mc.toml:7:8: a permission path is workspace, tmp, workspace/<rel> or home/<rel>: permission.0.path'
badpkg "a permission path that escapes" \
    '[package]
name  = "x"
files = ["x.mc"]

[[permission]]
kind = "fs.write"
path = "workspace/../x"
' 'mc.toml:7:8: a permission path is workspace, tmp, workspace/<rel> or home/<rel>: permission.0.path'
badpkg "an unknown permission kind" \
    '[package]
name  = "x"
files = ["x.mc"]

[[permission]]
kind = "fs.delete"
path = "workspace"
' 'mc.toml:6:8: a permission kind is fs.read, fs.write, net, exec or env: permission.0.kind'
badpkg "a [project] with no kind" \
    '[package]
name  = "x"
files = ["x.mc"]

[project]
entry = "x.mc"
out   = "build/x"
' 'mc.toml:6:9: a package.s .project. must say kind = "obj" or "exe": project.entry'

# 31i. a name is a library or a tool, and the registry says which
cat > tests/pkg/perm/wrong.toml <<'EOF'
[project]
name  = "perm"
entry = "main.mc"
out   = "build/w.o"
kind  = "obj"

[deps]
net  = "1.0.0"
tool = "0.1.0"
EOF
pkg sync tests/pkg/perm --config tests/pkg/perm/wrong.toml --registry "$reg" --libs-dir "$tmp/p1"
if [ "$rc" = 1 ] && grep -q "^mc: tool: is a tool: name it under \[tools\]$" "$tmp/o"; then
    ok "a tool under [deps]: $(tail -1 "$tmp/o")"
else
    fail "a tool under [deps]" "exit $rc: $(cat "$tmp/o")"
fi
cat > tests/pkg/perm/wrong.toml <<'EOF'
[project]
name  = "perm"
entry = "main.mc"
out   = "build/w.o"
kind  = "obj"

[tools]
net = "1.0.0"
EOF
pkg sync tests/pkg/perm --config tests/pkg/perm/wrong.toml --registry "$reg" --libs-dir "$tmp/p1"
if [ "$rc" = 1 ] && grep -q "^mc: net: is a library: name it under \[deps\]$" "$tmp/o"; then
    ok "a library under [tools]: $(tail -1 "$tmp/o")"
else
    fail "a library under [tools]" "exit $rc: $(cat "$tmp/o")"
fi
rm -f tests/pkg/perm/wrong.toml

# 31j. a lock written before M48 -- no `kind`, no `permissions` -- still builds
# and asks nothing. tests/pkg/app/mc.lock is that lock, checked in as it was.
grep -q 'permissions' tests/pkg/app/mc.lock \
    && fail "the old lock" "tests/pkg/app/mc.lock has been rewritten" \
    || ok "tests/pkg/app/mc.lock still has neither kind nor permissions, and § 2 built with it"

# ---- 32. M44 step 4: `mc install` and the slim compiler ----
# `mc install` puts the compiler's OWN package where a binary with no blob reads
# its `<name>` includes from, and `mc-slim` (src/mc_slim.mc) is that binary. The
# whole section is offline: the `--from-tree` road copies a checkout, and the
# registry road reads an index file whose `url` is a tarball this script made.
cd "$here" || exit 1
ins() { PATH="$tmp/bin2:$realpath_env" "$mc" install "$@" > "$tmp/o" 2>&1; rc=$?; }
mcver=$("$mc" --version | sed 's/^mc //')

# 32a. --from-tree: the layout, and `bundle.list` at the ROOT of the tree --
# which is the one file the package does not carry there (it is under tools/)
# and the one src/deps.mc reads to answer `<name>` (M48 § 2.6).
i1="$tmp/i1"
ins --libs-dir "$i1" --from-tree .
if [ "$rc" != 0 ]; then
    fail "mc install --from-tree ." "exit $rc: $(cat "$tmp/o")"
else
    d="$i1/mc/v$mcver"
    if [ -f "$d/mc.toml" ] && [ -f "$d.toml" ] && cmp -s tools/bundle.list "$d/bundle.list"; then
        ok "mc install --from-tree .: $(wc -l < "$tmp/out/got-files" | tr -d ' ') files, the manifest beside the tree, bundle.list at its root"
    else
        fail "mc install --from-tree . layout" "$(ls "$d" 2>&1 | tr '\n' ' ')"
    fi
    # the manifest's hash is the tree hash, and the shell agrees about it
    got=$(sed -n 's/^sha256  = "\(.*\)"/\1/p' "$d.toml" | head -1)
    want=$(sh scripts/pkg-hash.sh .)
    if [ -n "$got" ] && [ "$got" = "$want" ]; then
        ok "the installed tree's manifest carries the repository's tree hash ($got)"
    else
        fail "the installed manifest hash" "manifest=$got pkg-hash.sh=$want"
    fi
fi

# 32b. idempotent: a second run says so and touches nothing
ins --libs-dir "$i1" --from-tree .
if [ "$rc" = 0 ] && grep -q "^mc $mcver is installed (" "$tmp/o"; then
    ok "a second mc install does nothing: $(head -1 "$tmp/o")"
else
    fail "mc install is idempotent" "exit $rc: $(cat "$tmp/o")"
fi

# 32c. the sentinel: a dev build has no published version, and the message says
# what to run instead. (A released binary reports a real version and takes the
# registry road; that half is 32e.)
ins --libs-dir "$tmp/i2"
case "$mcver" in
0.0.0-dev)
    if [ "$rc" = 2 ] && grep -q "is a development build" "$tmp/o" \
       && grep -q "mc install --from-tree" "$tmp/o"; then
        ok "mc install on a dev build: $(head -1 "$tmp/o")"
    else
        fail "mc install on a dev build" "exit $rc: $(cat "$tmp/o")"
    fi ;;
*) ok "mc install: not a dev build ($mcver), the sentinel case does not apply" ;;
esac

# 32d. the slim compiler: what it refuses with nothing installed, and what it
# does afterwards. HOME is what picks <libs> for the single-file CLI, which has
# no --libs-dir of its own.
slim="$tmp/bin/mc-slim"
rm -f "$slim"
if ! msg=$("$mc" --exe src/mc_slim.mc -o "$slim" 2>&1); then
    fail "building src/mc_slim.mc" "$msg"
else
    ok "mc-slim builds ($(wc -c < "$slim" | tr -d ' ') bytes, against $(wc -c < build/mc-exe | tr -d ' ') for the full binary)"
    if [ "$("$slim" --version)" = "mc $mcver" ]; then
        ok "mc-slim --version: mc $mcver"
    else
        fail "mc-slim --version" "$("$slim" --version)"
    fi
    mkdir -p "$tmp/slim/home" "$tmp/slim/p"
    printf '#include <prelude>\ni64 main() { i64 i = 0; while (i < 42) { i = i + 1; } return i; }\n' \
        > "$tmp/slim/p/prog.mc"
    HOME="$tmp/slim/home" "$slim" "$tmp/slim/p/prog.mc" -o "$tmp/slim/p/prog.o" > "$tmp/o" 2>&1; rc=$?
    if [ "$rc" = 1 ] && grep -q "#include <prelude>: not bundled in this compiler and mc $mcver is not installed: run mc install" "$tmp/o"; then
        ok "mc-slim with nothing installed: $(sed 's|^.*prog.mc:1: ||' "$tmp/o")"
    else
        fail "mc-slim with nothing installed" "exit $rc: $(cat "$tmp/o")"
    fi
    # the full binary's message for a name nobody ships does NOT move
    printf '#include <nosuchlib>\ni64 main() { return 0; }\n' > "$tmp/slim/p/nope.mc"
    HOME="$tmp/slim/home" "$mc" "$tmp/slim/p/nope.mc" -o "$tmp/slim/p/nope.o" > "$tmp/o" 2>&1; rc=$?
    if [ "$rc" = 1 ] && grep -q "unknown bundled include: nosuchlib" "$tmp/o"; then
        ok "the full binary still says: $(sed 's|^.*nope.mc:1: ||' "$tmp/o")"
    else
        fail "the full binary's unknown-include message moved" "exit $rc: $(cat "$tmp/o")"
    fi
    # and now the install the message asked for, run BY THE SLIM COMPILER
    HOME="$tmp/slim/home" PATH="$tmp/bin2:$realpath_env" "$slim" install --from-tree . > "$tmp/o" 2>&1; rc=$?
    if [ "$rc" != 0 ]; then
        fail "mc-slim install --from-tree ." "exit $rc: $(cat "$tmp/o")"
    else
        ok "mc-slim installs its own package: $(head -1 "$tmp/o" | sed 's| -> .*| -> <libs>/mc/v'"$mcver"'/|')"
        HOME="$tmp/slim/home" "$slim" "$tmp/slim/p/prog.mc" -o "$tmp/slim/p/prog.o" > "$tmp/o" 2>&1; rc=$?
        "$mc" "$tmp/slim/p/prog.mc" -o "$tmp/slim/p/ref.o" > /dev/null 2>&1
        if [ "$rc" = 0 ] && cmp -s "$tmp/slim/p/prog.o" "$tmp/slim/p/ref.o"; then
            ok "mc-slim + the installed package: <prelude> compiles to the full binary's object, byte for byte"
        else
            fail "mc-slim after install" "exit $rc: $(cat "$tmp/o")"
        fi
    fi
    # the whole compiler, from the installed tree: M44 § A3 step 3, through
    # `mc install` this time rather than a layout this script wrote by hand
    cc="$slim"
    build tests/pkg/std "" "$i1"
    if want_exit "mc-slim compiles <mc/core> from the installed package" 0; then
        "$mc" src/mc.mc -o "$tmp/out/ref2.o" 2> /dev/null
        if cmp -s tests/pkg/std/build/def.o "$tmp/out/ref2.o"; then
            ok "mc-slim + mc install: <mc/host> + <mc/core> + <user_default> == src/mc.mc, byte for byte"
        else
            fail "mc-slim + mc install" "the object differs from src/mc.mc's"
        fi
    fi
    # and the pre-scan sees through the installed package: without that, a slim
    # compiler estimates nothing for a project whose sources are all `<...>`,
    # every table grows from its seed and the build uses twice the heap for the
    # same output (M44 § Implementation notes -- step 4, note 9).
    rm -rf tests/pkg/std/build
    "$slim" build tests/pkg/std --libs-dir "$i1" --limits > "$tmp/o" 2>&1; rc=$?
    if [ "$rc" = 0 ] && grep -q "verdict ok" "$tmp/o" \
       && ! awk '$1 == "nodes" { print $5 }' "$tmp/o" | grep -qv '^0$'; then
        ok "mc-slim's pre-scan reads the installed package: $(grep '^nodes' "$tmp/o")"
    else
        fail "mc-slim --limits" "exit $rc: $(grep -E '^(nodes|verdict|tolerance)' "$tmp/o" | tr '\n' ' ')"
    fi
    cc="$mc"
fi

# 32e. the registry road, offline: an index row for the `mc` package whose
# archive is a tarball of this checkout. The reserved-name rule (`mc` in [deps],
# [replace] or `mc pkg add`) does not apply here -- see § 11 above, which still
# refuses all three -- because this road installs the compiler's own package for
# the compiler itself (src/install.mc's header).
mkdir -p "$tmp/mcstage/mc-1.0.0" "$tmp/i3"
cp mc.toml "$tmp/mcstage/mc-1.0.0/"
while IFS= read -r f; do
    mkdir -p "$tmp/mcstage/mc-1.0.0/$(dirname "$f")"
    cp "$f" "$tmp/mcstage/mc-1.0.0/$f"
done < "$tmp/out/got-files"
(cd "$tmp/mcstage" && rtar czf "$tmp/archives/mc-1.0.0.tar.gz" mc-1.0.0)
mch=$(sh scripts/pkg-hash.sh "$tmp/mcstage/mc-1.0.0")
{ echo '[package]'; echo 'name = "mc"'; echo
  echo '[[versions]]'; echo 'version = "1.0.0"'
  echo "url = \"$tmp/archives/mc-1.0.0.tar.gz\""
  echo 'strip = 1'; echo "sha256 = \"$mch\""; echo 'deps = []'
} > "$tmp/registry/index/mc.toml"

ins 1.0.0 --registry "$tmp/registry" --libs-dir "$tmp/i3"
if [ "$rc" = 0 ] && grep -q "^nothing was downloaded: re-run with --yes$" "$tmp/o" \
   && grep -q "^fetch  mc 1.0.0$" "$tmp/o" && [ ! -d "$tmp/i3/mc" ]; then
    ok "mc install VERSION prints the plan and fetches nothing without --yes"
else
    fail "mc install without --yes" "exit $rc: $(cat "$tmp/o")"
fi

ins 1.0.0 --registry "$tmp/registry" --libs-dir "$tmp/i3" --yes
if [ "$rc" = 0 ] && [ -f "$tmp/i3/mc/v1.0.0.toml" ] \
   && cmp -s tools/bundle.list "$tmp/i3/mc/v1.0.0/bundle.list"; then
    ok "mc install 1.0.0 --yes: fetched, hashed against the row, blessed, bundle.list at the root"
else
    fail "mc install 1.0.0 --yes" "exit $rc: $(cat "$tmp/o")"
fi

# the row's sha256 is the tree hash and it is CHECKED: a wrong one leaves no
# manifest behind, which is what `is not fetched` reads as afterwards
sed 's/^sha256 = ".*"/sha256 = "0000000000000000000000000000000000000000000000000000000000000000"/' \
    "$tmp/registry/index/mc.toml" > "$tmp/registry/index/mc.toml.new"
mv "$tmp/registry/index/mc.toml.new" "$tmp/registry/index/mc.toml"
ins 1.0.0 --registry "$tmp/registry" --libs-dir "$tmp/i4" --yes
if [ "$rc" = 2 ] && grep -q "^mc: checksum mismatch for mc 1.0.0$" "$tmp/o" \
   && [ ! -f "$tmp/i4/mc/v1.0.0.toml" ] && [ ! -f "$tmp/i4/mc/v1.0.0/mc.toml" ]; then
    ok "a wrong sha256 refuses and leaves no claim: $(head -1 "$tmp/o")"
else
    fail "mc install with a wrong sha256" "exit $rc: $(cat "$tmp/o")"
fi

# a version nobody published
ins 9.9.9 --registry "$tmp/registry" --libs-dir "$tmp/i4" --yes
if [ "$rc" = 1 ] && grep -q "^mc: no such version of mc in the registry: 9.9.9$" "$tmp/o"; then
    ok "an unpublished version: $(head -1 "$tmp/o")"
else
    fail "mc install 9.9.9" "exit $rc: $(cat "$tmp/o")"
fi

# ---- 33. M44 step 5: `mc upgrade` ----
# The compiler replaces itself from a RELEASE, and the release is not in the
# registry: the index row carries the tag archive, the binaries live beside it
# (src/upgrade.mc's asset rule). Offline like everything above, on the second
# road that rule provides -- a row whose url is a local path has its assets in
# the same directory, which is exactly what a staged or air-gapped release is.
#
# The fixture is a real one: a compiler built from THIS tree with one line of
# src/version.mc changed, packaged by scripts/release-assets.sh. That is the
# only way to have a binary that answers `mc 9.9.9`, and it is what makes the
# version check, the `cmp` against the packaged bytes and the self-replacement
# mean something.
cd "$here" || exit 1
upgrade_run() {   # BINARY ARGS...
    bin="$1"; shift
    PATH="$tmp/bin2:$realpath_env" "$bin" upgrade "$@" > "$tmp/o" 2>&1; rc=$?
}

uos=$("$mc" --host | awk '$1 == "os" { print $2 }')
uarch=$("$mc" --host | awk '$1 == "arch" { print $2 }')
utarget="$uos-$uarch"
[ "$uarch" = aarch64 ] && utarget="$uos-arm64"
case "$utarget" in
macos-arm64)   uentry=src/mc.mc ;;
linux-arm64)   uentry=src/mc_linux.mc ;;
linux-x86_64)  uentry=src/mc_linux_x86_64.mc ;;
*)             uentry="" ;;
esac

if [ -z "$uentry" ]; then
    echo "skip mc upgrade: no compiler entry for $utarget"
else
mkdir -p "$tmp/u/tree" "$tmp/u/rel" "$tmp/u/reg/index" "$tmp/u/bin"
cp -R src "$tmp/u/tree/" && cp -R lib "$tmp/u/tree/"
# the one line that makes this binary a release: scripts/set-version.sh's edit,
# applied to a COPY so the checkout keeps its 0.0.0-dev sentinel
sed 's|return "0.0.0-dev";|return "9.9.9";|' src/version.mc > "$tmp/u/tree/src/version.mc"
if ! msg=$("$mc" --exe "$tmp/u/tree/$uentry" -o "$tmp/u/bin/mc999" 2>&1); then
    fail "building a 9.9.9 compiler for the upgrade fixture" "$msg"
else
    if [ "$("$tmp/u/bin/mc999" --version)" = "mc 9.9.9" ]; then
        ok "the upgrade fixture: a compiler from this tree that reports mc 9.9.9"
    else
        fail "the upgrade fixture's version" "$("$tmp/u/bin/mc999" --version)"
    fi
    PATH="$realpath_env" sh scripts/release-assets.sh 9.9.9 "$utarget" "$tmp/u/bin/mc999" "$tmp/u/rel" > /dev/null
    # a SECOND archive, holding the same binary under the name of another
    # version: the case the `--version` check after the extraction is for
    PATH="$realpath_env" sh scripts/release-assets.sh 1.0.0 "$utarget" "$tmp/u/bin/mc999" "$tmp/u/rel" > /dev/null
    asset="$tmp/u/rel/mc-9.9.9-$utarget.tar.gz"

    # the index: four rows, so that "the newest" has something to skip -- a
    # yanked 11.0.0 and a pre-release 10.0.0-rc1 -- plus the 1.0.0 that is
    # older than the fixture binary and therefore a downgrade.
    mkdir -p "$tmp/u/srcstage/mc-9.9.9"
    cp mc.toml "$tmp/u/srcstage/mc-9.9.9/"
    while IFS= read -r f; do
        mkdir -p "$tmp/u/srcstage/mc-9.9.9/$(dirname "$f")"
        cp "$f" "$tmp/u/srcstage/mc-9.9.9/$f"
    done < "$tmp/out/got-files"
    (cd "$tmp/u/srcstage" && rtar czf "$tmp/u/rel/mc-9.9.9-src.tar.gz" mc-9.9.9)
    uh=$(sh scripts/pkg-hash.sh "$tmp/u/srcstage/mc-9.9.9")
    urow() {   # VERSION [yanked]
        echo; echo '[[versions]]'; echo "version = \"$1\""
        [ -n "$2" ] && echo 'yanked = true'
        echo "url = \"$tmp/u/rel/mc-9.9.9-src.tar.gz\""
        echo 'strip = 1'; echo "sha256 = \"$uh\""; echo 'deps = []'
    }
    { echo '[package]'; echo 'name = "mc"'
      urow 1.0.0; urow 9.9.9; urow 10.0.0-rc1; urow 11.0.0 yanked
    } > "$tmp/u/reg/index/mc.toml"

    # 33a. the dev sentinel refuses the road that CHOOSES a version, and only
    # that one: `mc upgrade VERSION` on a tree build is allowed, which is what
    # every case below rests on (src/install.mc's precedent for the same string)
    if [ "$mcver" = 0.0.0-dev ]; then
        upgrade_run "$mc" --registry "$tmp/u/reg" --libs-dir "$tmp/u/l0" --to "$tmp/u/bin/x"
        if [ "$rc" = 2 ] && grep -q "^mc: mc 0.0.0-dev is a development build: build from the tree$" "$tmp/o" \
           && grep -q "run:   make mc1" "$tmp/o"; then
            ok "mc upgrade on a dev build: $(head -1 "$tmp/o")"
        else
            fail "mc upgrade on a dev build" "exit $rc: $(cat "$tmp/o")"
        fi
    else
        ok "mc upgrade: not a dev build ($mcver), the sentinel case does not apply"
    fi

    # 33b. the plan, exactly -- and nothing downloaded without --yes
    upgrade_run "$mc" 9.9.9 --registry "$tmp/u/reg" --libs-dir "$tmp/u/l1" --to "$tmp/u/bin/mc-new"
    { echo "upgrade mc $mcver -> 9.9.9"
      echo "url    $asset"
      echo "sha256 $asset.sha256"
      echo "into   $tmp/u/bin/mc-new"
      echo "nothing was downloaded: re-run with --yes"
    } > "$tmp/u/want"
    if [ "$rc" = 0 ] && cmp -s "$tmp/o" "$tmp/u/want" && [ ! -f "$tmp/u/bin/mc-new" ]; then
        ok "mc upgrade prints the plan and fetches nothing without --yes"
    else
        fail "the upgrade plan" "exit $rc: $(diff "$tmp/u/want" "$tmp/o" | head -6)"
    fi

    # 33c. the asset rule: a GitHub tag archive names the release download, any
    # other forge is refused rather than guessed at. Plan only -- no --yes, so
    # the https url is printed and never fetched.
    mkdir -p "$tmp/u/reg2/index"
    { echo '[package]'; echo 'name = "mc"'; echo
      echo '[[versions]]'; echo 'version = "0.16.0"'
      echo 'url = "https://github.com/minicompiler/mc/archive/refs/tags/v0.16.0.tar.gz"'
      echo 'strip = 1'
      echo 'sha256 = "0000000000000000000000000000000000000000000000000000000000000000"'
      echo 'deps = []'
    } > "$tmp/u/reg2/index/mc.toml"
    upgrade_run "$mc" 0.16.0 --registry "$tmp/u/reg2" --libs-dir "$tmp/u/l2" --to "$tmp/u/bin/x"
    want="https://github.com/minicompiler/mc/releases/download/v0.16.0/mc-0.16.0-$utarget.tar.gz"
    if [ "$rc" = 0 ] && grep -q "^url    $want\$" "$tmp/o" && grep -q "^sha256 $want.sha256\$" "$tmp/o"; then
        ok "the asset rule: the tag archive names $(grep '^url' "$tmp/o" | sed 's|.*/releases/|releases/|')"
    else
        fail "the asset rule (github)" "exit $rc: $(cat "$tmp/o")"
    fi
    mkdir -p "$tmp/u/reg3/index"
    sed 's|https://github.com/minicompiler/mc/archive/refs/tags/v0.16.0.tar.gz|https://example.invalid/mc/0.16.0.tar.gz|' \
        "$tmp/u/reg2/index/mc.toml" > "$tmp/u/reg3/index/mc.toml"
    upgrade_run "$mc" 0.16.0 --registry "$tmp/u/reg3" --libs-dir "$tmp/u/l2" --to "$tmp/u/bin/x"
    if [ "$rc" = 2 ] && grep -q "^mc: upgrade: no binaries known for: https://example.invalid/mc/0.16.0.tar.gz$" "$tmp/o"; then
        ok "another forge is refused: $(head -1 "$tmp/o")"
    else
        fail "the asset rule (other forge)" "exit $rc: $(cat "$tmp/o")"
    fi

    # 33d. a tampered archive: refused against the release's own .sha256, with
    # nothing written and no download left behind
    mkdir -p "$tmp/u/rel4" "$tmp/u/reg4/index"
    cp "$tmp/u/rel/mc-9.9.9-src.tar.gz" "$tmp/u/rel4/"
    cp "$asset" "$asset.sha256" "$tmp/u/rel4/"
    printf 'x' | dd of="$tmp/u/rel4/mc-9.9.9-$utarget.tar.gz" bs=1 seek=500 conv=notrunc 2> /dev/null
    sed "s|$tmp/u/rel/|$tmp/u/rel4/|" "$tmp/u/reg/index/mc.toml" > "$tmp/u/reg4/index/mc.toml"
    upgrade_run "$mc" 9.9.9 --yes --no-install --registry "$tmp/u/reg4" --libs-dir "$tmp/u/l4" --to "$tmp/u/bin/mc-bad"
    if [ "$rc" = 2 ] && grep -q "^mc: checksum mismatch for mc 9.9.9$" "$tmp/o" \
       && [ ! -f "$tmp/u/bin/mc-bad" ] && [ ! -f "$tmp/u/bin/mc-bad.new" ] \
       && [ -z "$(find "$tmp/u/l4" -type f 2> /dev/null)" ]; then
        ok "a tampered release is refused before it is unpacked: $(grep '^mc: checksum mismatch' "$tmp/o")"
    else
        fail "the checksum refusal" "exit $rc: $(cat "$tmp/o") [$(find "$tmp/u/l4" -type f 2> /dev/null | tr '\n' ' ')]"
    fi

    # 33e. the archive that carries the wrong compiler: verified, unpacked, and
    # then refused because it does not answer the version that was asked for
    upgrade_run "$mc" 1.0.0 --yes --no-install --registry "$tmp/u/reg" --libs-dir "$tmp/u/l5" --to "$tmp/u/bin/mc-wrong"
    if [ "$rc" = 2 ] && grep -q "^mc: the downloaded mc reports another version: mc 9.9.9, expected mc 1.0.0$" "$tmp/o" \
       && [ ! -f "$tmp/u/bin/mc-wrong" ]; then
        ok "an asset built from another tag: $(grep '^mc: the downloaded mc' "$tmp/o")"
    else
        fail "the version check after extraction" "exit $rc: $(cat "$tmp/o")"
    fi

    # 33f. the happy path, --no-install: the file that lands is the file that
    # was packaged, byte for byte, and it runs
    upgrade_run "$mc" 9.9.9 --yes --no-install --registry "$tmp/u/reg" --libs-dir "$tmp/u/l6" --to "$tmp/u/bin/mc-new"
    if [ "$rc" = 0 ] && cmp -s "$tmp/u/bin/mc-new" "$tmp/u/bin/mc999" \
       && [ "$("$tmp/u/bin/mc-new" --version)" = "mc 9.9.9" ] \
       && grep -q "^mc $mcver -> 9.9.9 ($tmp/u/bin/mc-new)$" "$tmp/o" \
       && [ ! -f "$tmp/u/bin/mc-new.new" ]; then
        ok "mc upgrade --yes: $(grep '^mc .* -> 9.9.9' "$tmp/o" | sed "s|($tmp/u/bin/|(<tmp>/|")"
    else
        fail "mc upgrade --yes --no-install" "exit $rc: $(cat "$tmp/o")"
    fi
    if [ "$uos" = macos ]; then
        if codesign --verify --verbose=4 "$tmp/u/bin/mc-new" > /dev/null 2>&1; then
            ok "the replaced binary still verifies (codesign --verify)"
        else
            fail "codesign --verify on the replaced binary" "$(codesign --verify --verbose=4 "$tmp/u/bin/mc-new" 2>&1 | tail -1)"
        fi
    else
        ok "codesign: not a macOS host ($uos), the signature case does not apply"
    fi
    if [ -z "$(find "$tmp/u/l6/mc/tmp" -type f 2> /dev/null)" ]; then
        ok "the download directory is left empty"
    else
        fail "the download directory" "$(find "$tmp/u/l6/mc/tmp" -type f | tr '\n' ' ')"
    fi

    # 33g. without --no-install, the NEW binary installs the tree that matches
    # its own version -- which is the whole reason the install is a spawn
    upgrade_run "$mc" 9.9.9 --yes --registry "$tmp/u/reg" --libs-dir "$tmp/u/l7" --to "$tmp/u/bin/mc-new2"
    if [ "$rc" = 0 ] && [ -f "$tmp/u/l7/mc/v9.9.9.toml" ] \
       && cmp -s tools/bundle.list "$tmp/u/l7/mc/v9.9.9/bundle.list" \
       && grep -q "^package mc 9.9.9 -> " "$tmp/o"; then
        ok "mc upgrade installs the matching library tree: $(grep '^package mc' "$tmp/o" | sed "s|$tmp/u/l7|<libs>|")"
    else
        fail "the install after the upgrade" "exit $rc: $(cat "$tmp/o")"
    fi

    # 33h. resolution, from the fixture binary itself: 9.9.9 is the newest with
    # 11.0.0 yanked and 10.0.0-rc1 a candidate, 1.0.0 is a downgrade and says
    # so, and a yanked version named by hand is refused
    upgrade_run "$tmp/u/bin/mc-new" --registry "$tmp/u/reg" --libs-dir "$tmp/u/l8" --to "$tmp/u/bin/x"
    if [ "$rc" = 0 ] && [ "$(cat "$tmp/o")" = "mc 9.9.9 is the newest" ]; then
        ok "a second mc upgrade with nothing newer: $(cat "$tmp/o") (11.0.0 yanked, 10.0.0-rc1 a candidate)"
    else
        fail "mc upgrade with nothing newer" "exit $rc: $(cat "$tmp/o")"
    fi
    upgrade_run "$tmp/u/bin/mc-new" 1.0.0 --registry "$tmp/u/reg" --libs-dir "$tmp/u/l8" --to "$tmp/u/bin/x"
    if [ "$rc" = 0 ] && [ "$(head -1 "$tmp/o")" = "downgrade mc 9.9.9 -> 1.0.0" ] && [ ! -f "$tmp/u/bin/x" ]; then
        ok "a version named explicitly may be older, and the plan says so: $(head -1 "$tmp/o")"
    else
        fail "the downgrade plan" "exit $rc: $(cat "$tmp/o")"
    fi
    upgrade_run "$tmp/u/bin/mc-new" 11.0.0 --registry "$tmp/u/reg" --libs-dir "$tmp/u/l8" --to "$tmp/u/bin/x"
    if [ "$rc" = 1 ] && grep -q "is yanked: pick another version" "$tmp/o"; then
        ok "a yanked version named by hand: $(grep '^mc: ' "$tmp/o")"
    else
        fail "a yanked version" "exit $rc: $(cat "$tmp/o")"
    fi

    # 33i. and the real thing: no --to at all. The binary replaces the file it
    # was itself loaded from -- host_self_path() -- and the new one runs.
    mkdir -p "$tmp/u/self"
    cp "$mc" "$tmp/u/self/mc"
    before=$(ls -i "$tmp/u/self/mc" | awk '{print $1}')
    upgrade_run "$tmp/u/self/mc" 9.9.9 --yes --no-install --registry "$tmp/u/reg" --libs-dir "$tmp/u/l9"
    after=$(ls -i "$tmp/u/self/mc" | awk '{print $1}')
    if [ "$rc" = 0 ] && grep -q "^into   $tmp/u/self/mc$" "$tmp/o" \
       && [ "$("$tmp/u/self/mc" --version)" = "mc 9.9.9" ] \
       && [ "$before" != "$after" ] && [ ! -f "$tmp/u/self/mc.new" ]; then
        ok "mc upgrade replaces the running binary: inode $before -> $after, and it reports mc 9.9.9"
    else
        fail "the self-replacement" "exit $rc: $(cat "$tmp/o")"
    fi
fi
fi

echo "check-pkg: $((total - fails))/$total"
[ "$fails" -eq 0 ]
