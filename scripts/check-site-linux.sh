#!/bin/sh
# check-site-linux.sh [MC] — mcsite runs on Linux, and renders exactly what it
# renders on macOS.
#
# Three things used to stop it (0.15.1, the coop/ops patch):
#
#   * site/gen/check.mc declared `extern uptr _NSGetEnviron()`, a libSystem
#     symbol musl does not have, so an mcsite linked against musl failed to LOAD
#     -- `Error relocating build/mcsite: _NSGetEnviron`;
#   * site/gen/util.mc read `struct dirent` at the macOS offsets, and the Linux
#     record is one field shorter, so every directory listing came out empty or
#     truncated and an unpatched mcsite rendered 7 pages instead of 87;
#   * site/mc.toml pinned `[target] os = "macos"`.
#
# What this script proves is not "it starts": it is that the SAME `docs/` tree
# comes out byte for byte on the two systems (`diff -r`), which is what makes the
# rendered site independent of the machine that rendered it -- the same claim
# docs/determinism.md makes about every other artefact here.
#
# It cross-builds the Linux compiler from THIS tree (M42: no linker, no sysroot,
# one command) rather than downloading a release, so the thing under test is the
# compiler in the working directory. Each architecture then runs, inside
# `alpine:3`, the whole chain a maintainer would run on a Linux box:
#
#   mc build site --config site/mc.linux.toml     # build/mcsite, ELF
#   build/mcsite site                             # render docs/ -> site/public
#   build/mcsite site --check                     # the internal-link check
#
# It runs TWO cells per architecture: a MUSL one in alpine:3 with
# site/mc.linux.toml (the ELF writer's default interpreter), and a GLIBC one in
# ubuntu:latest with site/mc.linux-gnu.toml (`[target] libc = "gnu"`). The glibc
# cell is what a report from the teko session asked for: mcsite built with the
# default (musl) config gets `/lib/ld-musl-<arch>.so.1` and will not start on a
# glibc runner. The render itself is libc-independent, so every cell has to come
# out byte for byte the macOS reference; the libc only decides whether the
# mcsite BINARY starts on that host.
#
# Without Docker it prints SKIPPED and exits 0: it is the same rule
# scripts/test-linux.sh follows, and for the same reason -- a macOS laptop with
# Docker Desktop stopped must still be able to run `make check`.
#
# The macOS artefacts (build/mcsite and site/public) are put back on the way out,
# because `make site` ran before this and `make check-site` may run after.
mc="${1:-build/mc1}"

if [ ! -x "$mc" ]; then
    echo "FAIL: compiler '$mc' not found or not executable"
    exit 1
fi

case "$(uname -s)" in
    Darwin) ;;
    *) echo "check-site-linux: SKIPPED (cross-check from a macOS host; this is $(uname -s))"; exit 0 ;;
esac

if ! command -v docker > /dev/null 2>&1 || ! docker info > /dev/null 2>&1; then
    echo "check-site-linux: SKIPPED (docker not available)"
    exit 0
fi

tmp="${TMPDIR:-/tmp}/check-site-linux.$$"
mkdir -p "$tmp"
root=$(pwd)
fails=0
total=0
ok()   { total=$((total + 1)); echo "ok $1"; }
fail() { total=$((total + 1)); echo "FAIL $1: $2"; fails=$((fails + 1)); }

restore() {
    "$mc" build site > /dev/null 2>&1
    ./build/mcsite site > /dev/null 2>&1
    rm -rf "$tmp"
}
trap 'restore' EXIT INT TERM

# ---- 1. the reference: what macOS renders ----------------------------------
if ! msg=$("$mc" build site 2>&1); then
    echo "FAIL: mc build site on macOS: $msg"; exit 1
fi
rm -rf site/public
if ! msg=$(./build/mcsite site 2>&1); then
    echo "FAIL: mcsite site on macOS: $msg"; exit 1
fi
pages=$(echo "$msg" | sed -n 's|^mcsite: \([0-9]*\) pages.*|\1|p')
rm -rf "$tmp/public-macos"
cp -a site/public "$tmp/public-macos"
ok "macos: $pages pages rendered (the reference)"

# ---- 2. one cell per architecture ------------------------------------------
cell() {              # cell ARCH PLATFORM LIBC IMAGE COMPILER-CONFIG SITE-CONFIG COMPILER
    arch="$1"; platform="$2"; libc="$3"; img="$4"; cfg="$5"; scfg="$6"; cc="$7"
    tag="linux/$arch $libc"
    rm -f "$cc"
    if ! msg=$("$mc" build src --config "$cfg" 2>&1); then
        fail "$tag: cross-building the compiler" "$msg"; return
    fi
    ok "$tag: $cc cross-built from this tree ($(wc -c < "$cc" | tr -d ' ') bytes)"

    # mc build site, inside the container
    rm -f build/mcsite
    if ! msg=$(docker run --rm --platform "$platform" -v "$root":/w -w /w "$img" \
               "/w/$cc" build site --config "$scfg" 2>&1); then
        fail "$tag: mc build site" "$msg"; return
    fi
    if [ ! -f build/mcsite ]; then
        fail "$tag: mc build site" "no build/mcsite was written"; return
    fi
    ok "$tag: mc build site --config $scfg -> $msg"

    # render, into the same site/public the macOS run wrote
    rm -rf site/public
    if ! msg=$(docker run --rm --platform "$platform" -v "$root":/w -w /w "$img" \
               /w/build/mcsite site 2>&1); then
        fail "$tag: mcsite site" "$msg"; return
    fi
    got=$(echo "$msg" | sed -n 's|^mcsite: \([0-9]*\) pages.*|\1|p')
    if [ "$got" != "$pages" ]; then
        fail "$tag: page count" "$got pages, macOS rendered $pages"; return
    fi
    ok "$tag: $got pages rendered"

    if ! d=$(diff -r "$tmp/public-macos" site/public 2>&1); then
        fail "$tag: site/public differs from the macOS render" "$(echo "$d" | head -8)"
        return
    fi
    n=$(find site/public -type f | wc -l | tr -d ' ')
    ok "$tag: site/public is byte for byte the macOS render ($n files, diff -r empty)"

    # --check, in the container. alpine:3 has no python3, so the two Python
    # checkers report themselves skipped and the mc link check is what runs --
    # which is the half written in this language and the half that has to work.
    if ! msg=$(docker run --rm --platform "$platform" -v "$root":/w -w /w "$img" \
               /w/build/mcsite site --check 2>&1); then
        fail "$tag: mcsite site --check" "$(echo "$msg" | tail -5)"; return
    fi
    line=$(echo "$msg" | grep 'link problems' | head -1)
    case "$line" in
        *" 0 link problems") ok "$tag: --check: $line" ;;
        *) fail "$tag: --check" "$line" ;;
    esac
}

# musl, in alpine:3 -- the default interpreter and the historical cells.
cell aarch64 linux/arm64 musl alpine:3 \
     src/mc.linux-aarch64.toml site/mc.linux.toml build/mc-linux-arm64
cell x86_64  linux/amd64 musl alpine:3 \
     src/mc.linux-x86_64.toml  site/mc.linux.toml build/mc-linux-x86_64

# glibc, in ubuntu:latest -- site/mc.linux-gnu.toml, the case the teko report
# asked for. A musl mcsite would not even start here.
cell aarch64 linux/arm64 gnu ubuntu:latest \
     src/mc.linux-aarch64-gnu.toml site/mc.linux-gnu.toml build/mc-linux-arm64-gnu
cell x86_64  linux/amd64 gnu ubuntu:latest \
     src/mc.linux-x86_64-gnu.toml  site/mc.linux-gnu.toml build/mc-linux-x86_64-gnu

if [ "$fails" != 0 ]; then
    echo "check-site-linux: $fails of $total FAILED"
    exit 1
fi
echo "check-site-linux: $total/$total"
