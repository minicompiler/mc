#!/bin/sh
# test-windows-exe.sh — the SELF-CONTAINED subset of the suite cross-compiled to
# a Windows PE executable through `mc --exe` (the pe-exe-* backend), with NO
# lld-link, and RUN on a Windows machine (M42 step 2, docs/specs/M42-step2.md).
#
#   test-windows-exe.sh [--arch A] [MC]                     cross-compile + assert
#   test-windows-exe.sh [--arch A] --build-only OUTDIR [MC] cross-compile only
#   test-windows-exe.sh [--arch A] --run-only OUTDIR        run OUTDIR's .exe
#
# The same split shape as test-windows.sh: `mc` runs on macOS and a PE runs on
# Windows, so the objects are produced here and executed on the windows-* runner
# (docs/ci.md). Unlike test-windows.sh there is no lld-link: the PE writer does
# the whole job, so --run-only needs nothing but a Windows host.
#
# WHY A SUBSET. On Windows `write`/`open`/`read`/`close`/`creat`/`exit` are mc
# wrappers in lib/sys_windows.mc over kernel32, NOT DLL exports. A portable test
# declares `extern write`; on the lld-link path (test-windows.sh) that resolves
# to a separate winrt.obj. In a single `--exe` translation unit `write` must be
# DEFINED (include <sys_windows>), and mc treats an `extern` as a full symbol
# definition, so the test's `extern write` and <sys_windows>'s `write` are
# `function declared twice`. This is the inverse of Linux, where `write` is a
# libc DLL symbol and the bare test --exe's directly. So this harness builds:
#
#   * a test that includes <sys_windows> itself (070..073): wrapped with an
#     `mc_start` that calls `main` through `callp` (not arity-checked), so the
#     command line is split by win_setup/win_argv;
#   * a pure-compute test (no I/O): built bare, entered through the writer's
#     synthesized stub (argc/argv/envp = 0, ExitProcess);
#
# and SKIPS a portable I/O test, which stays on the lld-link path.
#
# Headers are test.sh's: // expect-exit, // expect-stdout, // skip-windows,
# // skip-<arch>.
mode="full"
split=""
arch="aarch64"
mc=""
while [ $# -gt 0 ]; do
    case "$1" in
        --arch)   arch="$2"; shift 2 ;;
        --arch=*) arch="${1#--arch=}"; shift ;;
        --build-only|--run-only)
            [ -n "$2" ] || { echo "FAIL: $1 needs a directory" >&2; exit 1; }
            if [ "$1" = "--build-only" ]; then mode="build"; else mode="run"; fi
            split="$2"; shift 2
            ;;
        *) mc="$1"; shift ;;
    esac
done

case "$arch" in
    aarch64) backend="pe-exe-arm64";  cmachine="IMAGE_FILE_MACHINE_ARM64" ;;
    x86_64)  backend="pe-exe-x86_64"; cmachine="IMAGE_FILE_MACHINE_AMD64" ;;
    *) echo "FAIL: unknown --arch $arch (aarch64, x86_64)" >&2; exit 1 ;;
esac
mc="${mc:-build/mc1}"
outdir="build/tests-windows-exe-$arch"
[ "$mode" = "full" ] && split="$outdir"

if [ "$mode" != "run" ] && [ ! -x "$mc" ]; then
    echo "FAIL: compiler '$mc' not found or not executable"; exit 1
fi

findtool() {
    t=$(command -v "$1" 2>/dev/null)
    if [ -z "$t" ]; then
        for cand in /opt/homebrew/opt/llvm/bin/"$1" /usr/local/opt/llvm/bin/"$1" \
                    /usr/lib/llvm-*/bin/"$1"; do
            [ -x "$cand" ] && { t="$cand"; break; }
        done
    fi
    echo "$t"
}
readobj=$(findtool llvm-readobj)

root=$(pwd)
winpath() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) cygpath -m "$1" ;; *) printf '%s\n' "$1" ;; esac; }
root=$(winpath "$root")
tmp="${TMPDIR:-/tmp}/test-windows-exe.$$"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) tmp=$(cygpath -m "$tmp") ;; esac
mkdir -p "$tmp" "$outdir"
fails=0
total=0
skipped=""

if [ "$mode" = "run" ]; then
    [ -f "$split/manifest" ] || { echo "FAIL: '$split/manifest' not found (run --build-only first)"; exit 1; }
else
    mkdir -p "$split" || exit 1
fi
split=$(cd "$split" && pwd) || exit 1
split=$(winpath "$split")

skip_reason() {
    r=$(sed -n 's|^// skip-windows: *||p' "$1" | head -1)
    [ -n "$r" ] && { echo "$r"; return; }
    sed -n "s|^// skip-$arch: *||p" "$1" | head -1
}

# how a test is built as a self-contained PE, or empty to skip it:
#   self  the source includes <sys_windows>: wrap it with an mc_start
#   pure  no I/O layer and no mc-wrapper extern: build bare (synthesized entry)
#   ""    a portable I/O test: skipped, it belongs to the lld-link path
classify() {
    if grep -q '#include *<sys_windows>' "$1"; then echo self; return; fi
    # any macOS/Linux I/O layer brings mc-wrapper `extern write` etc. that a PE
    # cannot import: <sys>, <sys_svc>, <sys_linux*>, <io>, or a quoted sys*.mc
    if grep -qE '#include *<(sys[a-z0-9_]*|io)>|#include *"[^"]*sys([a-z0-9_]*)?\.mc"' "$1"; then echo ""; return; fi
    if grep -qE '\bextern\b.*\b(open|creat|read|write|close|exit)[[:space:]]*\(' "$1"; then echo ""; return; fi
    echo pure
}

read_expect() {
    want_exit=$(sed -n 's|^// expect-exit: *||p' "$1" | head -1)
    want_out=$(sed -n 's|^// expect-stdout: *||p' "$1" | head -1)
    has_out=$(grep -c '^// expect-stdout:' "$1")
}

# writes $split/<name>.mc = the translation unit `mc --exe` compiles
gen_wrapper() {
    f="$1"; name="$2"; kind="$3"
    if [ "$kind" = "self" ]; then
        {
            echo "#include \"$root/$f\""
            echo 'i64 mc_start() { i64 argc = win_setup(); ExitProcess(callp(&main, argc, win_argv(), 0)); }'
        } > "$split/$name.mc"
    else
        echo "#include \"$root/$f\"" > "$split/$name.mc"
    fi
}

build_one() {
    f="$1"; name="$2"
    total=$((total + 1))
    read_expect "$f"
    if [ -z "$want_exit" ]; then
        echo "FAIL $name (no expect-exit header)"; fails=$((fails + 1)); return
    fi
    kind=$(classify "$f")
    gen_wrapper "$f" "$name" "$kind"
    rm -f "$split/$name.exe"
    if ! msg=$("$mc" --backend=$backend "$split/$name.mc" -o "$split/$name.exe" 2>&1); then
        echo "FAIL $name (build: $msg)"; fails=$((fails + 1)); return
    fi
    if [ -n "$readobj" ]; then
        case "$("$readobj" --file-headers "$split/$name.exe" 2>&1)" in
            *"$cmachine"*) ;;
            *) echo "FAIL $name (not an $arch PE)"; fails=$((fails + 1)); return ;;
        esac
    fi
    echo "exit: $want_exit" > "$split/$name.expect"
    [ "$has_out" != "0" ] && echo "stdout: $want_out" >> "$split/$name.expect"
    echo "$name" >> "$split/manifest"
    echo "built $name ($kind)"
}

run_one() {
    name="$1"
    total=$((total + 1))
    if [ ! -f "$split/$name.exe" ] || [ ! -f "$split/$name.expect" ]; then
        echo "FAIL $name (missing $name.exe or $name.expect)"; fails=$((fails + 1)); return
    fi
    want_exit=$(sed -n 's|^exit: *||p' "$split/$name.expect" | head -1)
    want_out=$(sed -n 's|^stdout: *||p' "$split/$name.expect" | head -1)
    has_out=$(grep -c '^stdout:' "$split/$name.expect")
    got_out=$("$split/$name.exe" 2>"$tmp/err")
    got_exit=$?
    if [ "$got_exit" != "$want_exit" ]; then
        echo "FAIL $name (exit $got_exit, expected $want_exit)"
        err=$(cat "$tmp/err"); [ -n "$err" ] && echo "     stderr: $err"
        fails=$((fails + 1)); return
    fi
    if [ "$has_out" != "0" ] && [ "$got_out" != "$want_out" ]; then
        echo "FAIL $name (stdout '$got_out', expected '$want_out')"; fails=$((fails + 1)); return
    fi
    echo "ok $name"
}

if [ "$mode" = "run" ]; then
    while read -r name; do
        [ -n "$name" ] || continue
        run_one "$name"
    done < "$split/manifest"
    if [ -f "$split/skipped" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            skipped="$skipped
  $line"
        done < "$split/skipped"
    fi
else
    : > "$split/manifest"
    : > "$split/skipped"
    for f in tests/*.mc tests/mc/0[89]*.mc tests/mc/1*.mc tests/windows/*.mc; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .mc)
        why=$(skip_reason "$f")
        if [ -n "$why" ]; then
            skipped="$skipped
  $name — $why"; echo "$name — $why" >> "$split/skipped"; continue
        fi
        kind=$(classify "$f")
        if [ -z "$kind" ]; then
            skipped="$skipped
  $name — portable I/O test (lld-link path)"; continue
        fi
        build_one "$f" "$name"
    done
    # a run-mode oracle on this host if the machine happens to be Windows
    if [ "$mode" = "full" ]; then
        case "$(uname -s)" in
            MINGW*|MSYS*|CYGWIN*)
                echo "--- running here (Windows host) ---"
                while read -r name; do run_one "$name"; done < "$split/manifest" ;;
            *) echo "built the PE suite; a Windows host runs it (test-windows-exe.sh --run-only)" ;;
        esac
    fi
fi

rm -rf "$tmp"
if [ "$mode" = "build" ]; then
    echo "$((total - fails))/$total PE executables cross-compiled for windows/$arch in $split"
else
    echo "$((total - fails))/$total PE tests passed on windows/$arch"
fi
if [ -n "$skipped" ]; then
    echo "skipped:$skipped"
fi
[ "$fails" -eq 0 ]
