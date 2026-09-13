#!/bin/sh
# build.sh ROW OUTDIR -- builds ONE row of the bench cell into OUTDIR. Run from
# anywhere; every path is resolved from this file, the soak's bench/soak/build.sh
# shape. On success the LAST line of stdout is
#
#     run: <command that runs the built artefact>
#
# so bench/cell/cell.py never needs to know that the C# JIT row is launched
# through the `dotnet` host while every other row is a binary. A phase argument
# is appended to that command by the caller.
#
# Environment: MC (the mc binary, default ../../build/mc1 then `mc` on PATH),
# CC (default clang), LIBC (Linux only: the family `mc --exe --libc=` writes,
# default gnu).
set -e
row="$1"
out="$2"
[ -n "$row" ] && [ -n "$out" ] || { echo "usage: build.sh ROW OUTDIR" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
mkdir -p "$out"
if [ -z "$MC" ]; then
    if [ -x "$root/build/mc1" ]; then MC="$root/build/mc1"; else MC=mc; fi
fi
CC=${CC:-clang}
case "$(uname -s)" in
    Darwin) libc=""; rid=osx-arm64 ;;
    Linux)  libc="--libc=${LIBC:-gnu}"
            case "$(uname -m)" in aarch64|arm64) rid=linux-arm64 ;; *) rid=linux-x64 ;; esac ;;
    *) echo "build.sh: unsupported host $(uname -s)" >&2; exit 2 ;;
esac

case "$row" in
    mc-plain|mc-opt)
        # a re-signed file at the same inode is killed on macOS (M12)
        rm -f "$out/$row"
        opt=""
        [ "$row" = mc-opt ] && opt="-O"
        # shellcheck disable=SC2086
        "$MC" $opt --exe $libc "$root/bench/mc/bench.mc" -o "$out/$row"
        echo "run: $out/$row" ;;
    c-O2|c-O0)
        "$CC" "-${row#c-}" "$root/bench/c/bench.c" -o "$out/$row"
        echo "run: $out/$row" ;;
    go)
        (cd "$root/bench/go" && go build -o "$out/go" .)
        echo "run: $out/go" ;;
    zig-fast|zig-debug)
        mode=ReleaseFast
        [ "$row" = zig-debug ] && mode=Debug
        (cd "$out" && zig build-exe "$root/bench/zig/bench.zig" -O "$mode" -femit-bin="$out/$row")
        echo "run: $out/$row" ;;
    rust-O3|rust-O0)
        lvl=3
        [ "$row" = rust-O0 ] && lvl=0
        rustc -C "opt-level=$lvl" "$root/bench/rust/bench.rs" -o "$out/$row"
        echo "run: $out/$row" ;;
    cs-aot)
        # NativeAOT links against libssl and libbrotli, which macOS does not
        # ship: without these two paths the link is `ld: library 'ssl' not
        # found` (bench/RESULTS.md section A records the same workaround). When
        # they are absent the build fails and cell.py records the row as
        # SKIPPED with the linker's own message; it is never faked.
        if [ "$(uname -s)" = Darwin ]; then
            LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:/opt/homebrew/opt/brotli/lib:$LIBRARY_PATH"
            export LIBRARY_PATH
        fi
        (cd "$root/bench/cs" && dotnet publish -c Release -r "$rid" -p:PublishAot=true -o "$out/cs-aot")
        echo "run: $out/cs-aot/bench" ;;
    cs-jit)
        # The apphost next to bench.dll needs DOTNET_ROOT when dotnet is not in
        # /usr/local/share/dotnet; `dotnet bench.dll` is the same host process
        # launched through the muxer on PATH and needs nothing set.
        (cd "$root/bench/cs" && dotnet publish -c Release -o "$out/cs-jit")
        echo "run: dotnet $out/cs-jit/bench.dll" ;;
    *)
        echo "build.sh: unknown row $row" >&2; exit 2 ;;
esac
