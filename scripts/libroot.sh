#!/bin/sh
# libroot.sh DEST [VERSION] — lay the library root D4 of docs/specs/M52.md
# describes: DEST/lib/mc/v<VERSION>/, holding `bundle.list` at its root and
# every `lib/` file that manifest names, at the path it names.
#
# That is resolution root 2 (`<dir of the binary>/lib/mc/v<ver>/`), so DEST is
# the directory the binary sits in: `build` for build/mc1, the staging
# directory for a release tarball. Root 3 is the same tree one level up, for a
# packager who puts the binary in bin/; nothing here has to know which is which.
#
# It is a PARTIAL tree on purpose (M52 § 4): the map keeps all its rows, and
# the files staged are the library ones. A name whose file is absent falls
# through in src/deps.mc (dp_mc_open) exactly as an unknown name does, so a
# full binary answers every `mc/*` name from its own blob and never reads here.
#
# With --libs the same tree is laid at `DEST/mc/v<VERSION>/` instead, which is
# resolution root 1 -- what `mc install --libs-dir DEST` writes. A fixture that
# overrides `<libs>` and then expects a library name needs it: --libs-dir
# REPLACES `<libs>`, so a `<libs>` with no `mc/v<ver>/` in it has no library
# tree, and a taught compiler spawned into a project's own build/ has no other
# road to one (src/deps.mc, deps_libs_for_child).
#
# VERSION defaults to the one this tree bakes into the compiler, `mc_version()`
# in src/version.mc -- `0.0.0-dev` in a checkout. Run from the repository root:
# tools/bundle.list and the lib/ files are read relative to the working
# directory.
set -e

mid="/lib"
if [ "$1" = "--libs" ]; then
    mid=""
    shift
fi
dest="$1"
if [ -z "$dest" ]; then
    echo "usage: libroot.sh [--libs] DEST [VERSION]" >&2
    exit 1
fi
ver="$2"
[ -n "$ver" ] || ver=$(sed -n 's/^uptr mc_version() { return "\(.*\)"; }$/\1/p' src/version.mc | head -1)
if [ -z "$ver" ]; then
    echo "libroot: cannot read the version out of src/version.mc" >&2
    exit 1
fi

root="$dest$mid/mc/v$ver"
rm -rf "$root"
mkdir -p "$root"
cp tools/bundle.list "$root/bundle.list"

# Every row the blob does NOT carry, at the path the manifest names. Since M52
# step B that is `bl_in_blob` in tools/bundle.mc read the other way round: the
# blob keeps src/* plus prelude and user_default, and everything else lives
# here. The two exceptions are staged as well, because they are lib/ paths and
# a duplicate is free -- the blob answers first and this copy is never read.
n=0
while IFS='	' read -r name path; do
    case "$path" in
    '' | \#*) ;;
    src/*) ;;
    *)
        mkdir -p "$root/${path%/*}"
        cp "$path" "$root/$path"
        n=$((n + 1))
        ;;
    esac
done < tools/bundle.list

echo "libroot: $root ($n files)"
