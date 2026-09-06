#!/bin/sh
# build.sh NAME -- builds ONE soak server into bench/soak/bin/. Run from anywhere;
# every path is resolved from this file. The interpreted servers (node-*, py-*,
# rb-*, php-builtin) have nothing to build and print so.
#
# Environment: MC (the mc binary, default `mc` on PATH), CC (default clang),
# LIBC (Linux only: the family `mc --exe --libc=` writes, default gnu).
set -e
name="$1"
[ -n "$name" ] || { echo "usage: build.sh SERVER" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
bin="$here/bin"
mkdir -p "$bin"
MC=${MC:-mc}
CC=${CC:-clang}
case "$(uname -s)" in
    Darwin) incl=macos; libc=""; rid=osx-arm64 ;;
    Linux)  incl=linux; libc="--libc=${LIBC:-gnu}"
            case "$(uname -m)" in aarch64|arm64) rid=linux-arm64 ;; *) rid=linux-x64 ;; esac ;;
    *) echo "build.sh: unsupported host $(uname -s)" >&2; exit 2 ;;
esac
case "$name" in
    mc-serial|mc-fork1|mc-forkka)
        src=${name#mc-}
        rm -f "$bin/$name"     # a re-signed file at the same inode is killed on macOS (M12)
        # shellcheck disable=SC2086
        "$MC" --exe $libc --include="$root/bench/http/mc/$incl" "$root/bench/http/mc/$src.mc" -o "$bin/$name" ;;
    c-serial)
        "$CC" -O2 -o "$bin/c-serial" "$root/bench/http/c/serial.c" ;;
    go-nethttp)
        (cd "$root/bench/http/go" && go build -o "$bin/go-nethttp" .) ;;
    rust-threads)
        rustc -O -o "$bin/rust-threads" "$root/bench/http/rust/main.rs" ;;
    rust-axum)
        (cd "$root/bench/http2/axum" && cargo build --release --locked && cp target/release/axum-hello "$bin/rust-axum") ;;
    zig-threads)
        (cd "$root/bench/http/zig" && zig build-exe main.zig -O ReleaseFast -femit-bin="$bin/zig-threads") ;;
    cs-jit)
        (cd "$root/bench/http/cs" && dotnet publish -c Release -o "$bin/cs-jit") ;;
    cs-aot)
        (cd "$root/bench/http/cs" && dotnet publish -c Release -r "$rid" -p:PublishAot=true -o "$bin/cs-aot") ;;
    node-single|node-cluster|py-stdlib|py-uvicorn|rb-webrick|rb-puma|php-builtin)
        echo "$name: interpreted, nothing to build" ;;
    *)
        echo "build.sh: unknown server $name" >&2; exit 2 ;;
esac
echo "built $name"
