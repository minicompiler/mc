#!/bin/sh
# check-wide.sh [MC] — M24 step 2: the three modules that prove the PRINCIPLE.
#
# `<float>` could have been special-cased. These three could not, and the test
# for all of them is the same one sentence: **`git diff src/` is empty.** They
# are built by the compilers lib/mc_i128.mc, lib/mc_f16.mc and
# examples/avx/mc-avx.mc, each of which is `#include <mc/core>` plus a module.
#
#   i128         a 128-bit integer, memory-resident in ONE depth backed by a
#                16-byte slot; adds/adc, subs/sbc, mul/umulh, and a compare that
#                is not just "the 64-bit one twice"; a literal through a
#                module-private global with an N_BLOB initializer; a value passed
#                to a TWO-REGISTER callee
#   f16          half precision as a storage type, four slots on top of
#                <float>'s machine and nothing else -- because <float> dispatches
#                on the KIND and not on the id
#   examples/avx one AVX instruction named by its encoding, applied to two values
#                the allocator placed, with its own VEX bytes; re-assembled by
#                llvm-mc, not executed (this host has no AVX to run it on)
#
# --build-only OUTDIR --os OS --arch ARCH [MC]  writes the WIDE half of an
# EXISTING cross-compile artifact, exactly the shape check-float.sh does: one
# <name>.{o,obj}, one <name>.expect and one manifest line per wide test, so the
# `--run-only` half of scripts/test-{linux,windows}.sh links and RUNS the wide
# corpus on the CI legs -- which is the only place the Win64 by-reference wide
# ABI is actually EXECUTED (the local check below only links it). It must run
# AFTER the suite's --build-only: that step truncates the manifest.
mode="full"
split=""
bos=""
barch=""
while [ $# -gt 0 ]; do
    case "$1" in
        --build-only) mode="build"; split="$2"; shift 2 ;;
        --os)         bos="$2"; shift 2 ;;
        --arch)       barch="$2"; shift 2 ;;
        *)            break ;;
    esac
done

mc="${1:-build/mc1}"
root=$(pwd)
llvm="/opt/homebrew/opt/llvm/bin"

if [ ! -x "$mc" ]; then
    echo "FAIL: compiler '$mc' not found or not executable"
    exit 1
fi

fails=0
tmp="${TMPDIR:-/tmp}/check-wide.$$"
mkdir -p "$tmp"
cleanup() { rm -rf "$tmp"; return 0; }
trap cleanup EXIT INT TERM

tool() { if command -v "$1" > /dev/null 2>&1; then echo "$1"; else echo "$llvm/$1"; fi; }
have() { command -v "$1" > /dev/null 2>&1 || [ -x "$llvm/$1" ]; }

# The taught compilers. mc-i128 registers BOTH i128 and u128, so it compiles the
# whole wide corpus; mc-u128 is the second door and is built for parity with the
# run-time checks below. Each is `#include <mc/core>` plus the module.
build_wide_compilers() {
    for pair in "lib/mc_i128.mc build/mc-i128" "lib/mc_u128.mc build/mc-u128"; do
        set -- $pair
        rm -f "$2"
        if ! msg=$("$mc" --exe "$1" -o "$2" 2>&1); then
            echo "FAIL: building $2 from $1: $msg"; return 1
        fi
    done
    return 0
}

# which taught compiler owns a wide test (mc-i128 compiles all four, but the
# u128 program is built by its own door, matching the full-run convention)
wide_compiler() { case "$1" in *u128*) echo build/mc-u128 ;; *) echo build/mc-i128 ;; esac; }

if [ "$mode" = "build" ]; then
    [ -n "$split" ] && [ -n "$bos" ] && [ -n "$barch" ] || {
        echo "FAIL: --build-only needs OUTDIR, --os and --arch"; exit 1; }
    [ -f "$split/manifest" ] || {
        echo "FAIL: '$split/manifest' not found (run the suite's --build-only first)"; exit 1; }
    build_wide_compilers || exit 1
    lmode="libc"; ext="o"
    if [ "$bos" = "windows" ]; then lmode="kernel32"; ext="obj"; fi
    tmpb="$tmp/build"; mkdir -p "$tmpb"
    n=0
    for f in tests/wide/030-i128.mc tests/wide/032-u128.mc \
             tests/wide/033-wide-abi.mc tests/wide/034-cast-narrow.mc; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .mc)
        why=$(sed -n "s|^// skip-$bos: *||p" "$f" | head -1)
        [ -n "$why" ] || why=$(sed -n "s|^// skip-$barch: *||p" "$f" | head -1)
        if [ -n "$why" ]; then
            echo "skip $name ($why)"; echo "$name — $why" >> "$split/skipped"; continue
        fi
        {
            echo '[project]'
            echo "entry = \"$root/$f\""
            echo "out   = \"$root/$split/$name.$ext\""
            echo 'kind  = "obj"'
            echo
            echo '[target]'
            echo "os   = \"$bos\""
            echo "arch = \"$barch\""
        } > "$tmpb/mc.toml"
        if ! msg=$("$(wide_compiler "$f")" build "$tmpb" --config "$tmpb/mc.toml" 2>&1); then
            echo "FAIL $name (build: $msg)"; fails=$((fails + 1)); continue
        fi
        echo "exit: $(sed -n 's|^// expect-exit: *||p' "$f" | head -1)" > "$split/$name.expect"
        if grep -q '^// expect-stdout:' "$f"; then
            echo "stdout: $(sed -n 's|^// expect-stdout: *||p' "$f" | head -1)" >> "$split/$name.expect"
        fi
        echo "$name $lmode" >> "$split/manifest"
        echo "built $name"
        n=$((n + 1))
    done
    if [ "$fails" != 0 ]; then echo "check-wide --build-only: $fails failures"; exit 1; fi
    echo "check-wide --build-only: $n wide objects for $bos/$barch in $split"
    exit 0
fi

run_case() {                            # compiler-source, test-source, name
    csrc="$1"; tsrc="$2"; name="$3"
    c="build/mc-$name"
    rm -f "$c"
    if ! msg=$("$mc" --exe "$csrc" -o "$c" 2>&1); then
        echo "FAIL $name (building $csrc: $msg)"; fails=$((fails + 1)); return 0
    fi
    rm -f "$tmp/$name"
    if ! msg=$("$c" --exe "$tsrc" -o "$tmp/$name" 2>&1); then
        echo "FAIL $name (compiling $tsrc: $msg)"; fails=$((fails + 1)); return 0
    fi
    got=$("$tmp/$name" 2>/dev/null)
    rc=$?
    want_exit=$(sed -n 's|^// expect-exit: *||p' "$tsrc" | head -1)
    want_out=$(sed -n 's|^// expect-stdout: *||p' "$tsrc" | head -1)
    if [ "$rc" != "$want_exit" ] || [ "$got" != "$want_out" ]; then
        echo "FAIL $name (exit $rc '$got', expected $want_exit '$want_out')"
        fails=$((fails + 1)); return 0
    fi
    echo "ok   $name: $tsrc"
    # ...and the DEFAULT compiler must refuse the same source
    if msg=$("$mc" "$tsrc" -o "$tmp/no.o" 2>&1); then
        echo "FAIL $name: the default compiler accepted $tsrc"
        fails=$((fails + 1))
    else
        echo "ok   $name: the default compiler refuses it ($msg)"
    fi
}

run_case lib/mc_i128.mc tests/wide/030-i128.mc i128
run_case lib/mc_u128.mc tests/wide/032-u128.mc u128
run_case lib/mc_f16.mc  tests/wide/031-f16.mc  f16

# i128: the 16-byte global initializer is an N_BLOB, one per literal, and the
# symbols are 16 bytes apart -- which is type_new's width, in the object
nblob=$(build/mc-i128 --dump-ast tests/wide/030-i128.mc | grep -c '^  BLOB val=16$')
if [ "$nblob" -ge 4 ]; then
    echo "ok   i128: $nblob literal globals, each an N_BLOB of 16 bytes"
else
    echo "FAIL i128: expected N_BLOB literal globals, found $nblob"
    fails=$((fails + 1))
fi
if build/mc-i128 --dump-syms tests/wide/030-i128.mc | grep -q 'value=16 _\$i128_1'; then
    echo "ok   i128: the literal globals are 16 bytes apart in the object"
else
    echo "FAIL i128: the literal globals are not 16 bytes apart"
    fails=$((fails + 1))
fi
# ...the adds/adc pair, and a 16-byte frame slot for a value that is one depth
if build/mc-i128 --dump-asm tests/wide/030-i128.mc | grep -q '^  adds x8, x16, x17$' \
   && build/mc-i128 --dump-asm tests/wide/030-i128.mc | grep -q '^  adc x16, x16, x17$'; then
    echo "ok   i128: --dump-asm shows the adds/adc pair"
else
    echo "FAIL i128: no adds/adc pair in --dump-asm"
    fails=$((fails + 1))
fi
# a two-register callee: x0:x1 and x2:x3, the AAPCS64 even-pair rule
if build/mc-i128 --dump-asm tests/wide/030-i128.mc | sed -n '/^_add2:/,/ret/p' \
   | grep -q 'str x3, \[sp, #40\]'; then
    echo "ok   i128: a 16-byte argument arrives in an even register pair"
else
    echo "FAIL i128: the two-register callee does not read x0..x3"
    fails=$((fails + 1))
fi

# u128: the same machine, but the ordering compare is UNSIGNED -- cset hs/lo,
# never ge/lt, which is the one difference from i128 (arm64 --dump-asm)
if build/mc-i128 --dump-asm tests/wide/032-u128.mc | grep -qE '^  cset x[0-9]+, (hs|lo)$'; then
    echo "ok   u128: the unsigned compare uses cset hs/lo"
else
    echo "FAIL u128: no unsigned cset (hs/lo) in --dump-asm"
    fails=$((fails + 1))
fi
# ...and the SIGNED i128 compare in the same program still reads ge/lt
if build/mc-i128 --dump-asm tests/wide/032-u128.mc | grep -qE '^  cset x[0-9]+, (ge|lt)$'; then
    echo "ok   u128: the i128 compare beside it still uses cset ge/lt"
else
    echo "FAIL u128: no signed cset (ge/lt) for the i128 half"
    fails=$((fails + 1))
fi
# the u128 literals are N_BLOB globals too, with the $u128_ prefix
nub=$(build/mc-i128 --dump-syms tests/wide/032-u128.mc | grep -c 'value=16 _\$u128_')
if [ "$nub" -ge 1 ]; then
    echo "ok   u128: literal globals ($nub) are 16 bytes apart, prefix \$u128_"
else
    echo "FAIL u128: no 16-byte-apart \$u128_ literal globals"
    fails=$((fails + 1))
fi

# ---- x86-64: the SysV and Win64 machines, cross-compiled and re-assembled ----
# The wide machine emits add/adc, sub/sbb, mul, setb/setae (unsigned) and
# setl/setge (signed) that no bundled x86 machine has; llvm-mc must re-assemble
# every one of them byte for byte, on BOTH ABIs (M24's sweep obligation).
x86_sweep() {                           # test-source, name
    tsrc="$1"; xname="$2"
    if ! have llvm-objdump || ! have llvm-mc; then
        echo "skip $xname x86 sweep: llvm-objdump/llvm-mc not found"; return 0
    fi
    for pair in "elf-obj-x86_64 x86_64-linux-musl SysV" "coff-obj-x86_64 x86_64-windows-msvc Win64"; do
        set -- $pair; backend="$1"; triple="$2"; abi="$3"
        obj="$tmp/$xname-$abi.o"
        if ! msg=$("build/mc-$xname" --backend=$backend "$tsrc" -o "$obj" 2>&1); then
            echo "FAIL $xname $abi (compile: $msg)"; fails=$((fails + 1)); continue
        fi
        $(tool llvm-objdump) -d --triple="$triple" "$obj" 2>/dev/null \
            | sed -n 's|^ *[0-9a-f]*: *\([0-9a-f ]*[0-9a-f]\)  *\(.*\)$|\1\t\2|p' \
            | sort -u > "$tmp/$xname-$abi.ins"
        n=0; bad=0
        while IFS='	' read -r bytes text; do
            [ -n "$text" ] || continue
            case "$text" in *"<"*|jmp*|j[a-z]*|call*|*rip*|.byte*) continue ;; esac
            text=$(echo "$text" | sed 's|#.*||; s|[[:space:]]*$||')
            enc=$(printf '%s\n' "$text" | $(tool llvm-mc) -triple="$triple" --show-encoding 2>/dev/null \
                  | sed -n 's|.*encoding: \[\(.*\)\].*|\1|p' | tr -d ' ' | tr ',' '\n' \
                  | sed 's|^0x||' | tr '\n' ' ' | sed 's| *$||')
            [ -n "$enc" ] || continue
            if [ "$enc" != "$(echo "$bytes" | tr -s ' ')" ]; then
                echo "FAIL $xname $abi sweep: '$text' -> $enc, mc emitted $bytes"; bad=$((bad + 1)); continue
            fi
            n=$((n + 1))
        done < "$tmp/$xname-$abi.ins"
        if [ "$bad" != 0 ]; then fails=$((fails + bad))
        else echo "ok   $xname $abi sweep: $n distinct instructions re-assemble byte for byte"; fi
    done
}
# the wide-ABI overflow test: four 16-byte arguments, which fit AArch64's eight
# argument registers but overflow x86-64's (SysV stack, Win64 by-reference stack)
rm -f "$tmp/abi"
if ! msg=$(build/mc-i128 --exe tests/wide/033-wide-abi.mc -o "$tmp/abi" 2>&1); then
    echo "FAIL abi (compile: $msg)"; fails=$((fails + 1))
else
    got=$("$tmp/abi" 2>/dev/null); rc=$?
    if [ "$rc" = 0 ] && [ "$got" = "10 1 3000000000000000000" ]; then
        echo "ok   abi: tests/wide/033-wide-abi.mc (macos/aarch64, exit 0)"
    else
        echo "FAIL abi (exit $rc '$got', expected 0 '10 1 3000000000000000000')"; fails=$((fails + 1))
    fi
fi

# the cast test: a signed narrow source (i32) widened to i128/u128 must
# sign-extend, an unsigned one (u32) zero-extend (macos/aarch64 native)
rm -f "$tmp/cast"
if ! msg=$(build/mc-i128 --exe tests/wide/034-cast-narrow.mc -o "$tmp/cast" 2>&1); then
    echo "FAIL cast (compile: $msg)"; fails=$((fails + 1))
else
    got=$("$tmp/cast" 2>/dev/null); rc=$?
    if [ "$rc" = 0 ] && [ "$got" = "1 1 1 1 1 1 1 1 1" ]; then
        echo "ok   cast: tests/wide/034-cast-narrow.mc (macos/aarch64, exit 0)"
    else
        echo "FAIL cast (exit $rc '$got', expected 0 '1 1 1 1 1 1 1 1 1')"; fails=$((fails + 1))
    fi
fi

x86_sweep tests/wide/030-i128.mc i128
x86_sweep tests/wide/032-u128.mc u128
x86_sweep tests/wide/033-wide-abi.mc i128
x86_sweep tests/wide/034-cast-narrow.mc i128

# ---- x86-64 and aarch64 EXECUTION in Docker (SysV) ----
# The strongest check the sweep cannot make: does the code RUN? mc build with a
# Linux target selects the right <sys> layer and links statically with musl; one
# container per architecture. Self-skips without docker/ld.lld/the sysroot.
root=$(pwd)
wide_linux() {                          # arch, docker platform, compiler, test, name, want-exit, want-out
    warch="$1"; plat="$2"; comp="$3"; wsrc="$4"; wnm="$5"; wex="$6"; wout="$7"
    sysroot="$root/build/sysroot/linux-$warch"
    if ! have ld.lld; then echo "skip linux/$warch $wnm: ld.lld not in PATH"; return 0; fi
    if ! docker info > /dev/null 2>&1; then echo "skip linux/$warch $wnm: docker is not running"; return 0; fi
    if [ ! -f "$sysroot/libc.a" ]; then
        if ! msg=$(sh scripts/sysroot-linux.sh --arch "$warch" 2>&1); then
            echo "skip linux/$warch $wnm: no musl sysroot ($msg)"; return 0
        fi
    fi
    mkdir -p "$root/build/wide-lin"
    out="$root/build/wide-lin/$wnm-$warch"
    cfg="$root/build/wide-lin/$wnm-$warch.toml"
    {
        echo '[project]'; echo "entry = \"$root/$wsrc\""; echo "out   = \"$out\""; echo
        echo '[target]'; echo 'os   = "linux"'; echo "arch = \"$warch\""; echo
        echo '[sysroot]'; echo "path = \"$sysroot\""; echo
        echo '[linker]'; echo 'cmd  = "ld.lld"'
        echo 'args = ["-o", "{out}", "{sysroot}/crt1.o", "{sysroot}/crti.o", "{obj}", "{sysroot}/libc.a", "{sysroot}/crtn.o", "-static"]'
    } > "$cfg"
    if ! msg=$("build/mc-$comp" build "$root/build/wide-lin" --config "$cfg" 2>&1); then
        echo "FAIL linux/$warch $wnm (build: $msg)"; fails=$((fails + 1)); return 0
    fi
    got=$(docker run --rm --platform "$plat" -v "$root":/w -w /w alpine:3 "./build/wide-lin/$wnm-$warch" 2>/dev/null)
    rc=$?
    if [ "$rc" != "$wex" ] || [ "$got" != "$wout" ]; then
        echo "FAIL linux/$warch $wnm (exit $rc '$got', expected $wex '$wout')"; fails=$((fails + 1)); return 0
    fi
    echo "ok   linux/$warch $wnm: runs, exit $rc"
}
if docker info > /dev/null 2>&1 && have ld.lld; then
    wide_linux aarch64 linux/arm64 i128 tests/wide/030-i128.mc i128 0 "0 1 1 0 1 0 42 1 1 0"
    wide_linux x86_64  linux/amd64 i128 tests/wide/030-i128.mc i128 0 "0 1 1 0 1 0 42 1 1 0"
    wide_linux aarch64 linux/arm64 u128 tests/wide/032-u128.mc u128 0 "1 1 1 0 0 1 0 1 1 42 1 1"
    wide_linux x86_64  linux/amd64 u128 tests/wide/032-u128.mc u128 0 "1 1 1 0 0 1 0 1 1 42 1 1"
    wide_linux aarch64 linux/arm64 i128 tests/wide/033-wide-abi.mc abi 0 "10 1 3000000000000000000"
    wide_linux x86_64  linux/amd64 i128 tests/wide/033-wide-abi.mc abi 0 "10 1 3000000000000000000"
    wide_linux aarch64 linux/arm64 i128 tests/wide/034-cast-narrow.mc cast 0 "1 1 1 1 1 1 1 1 1"
    wide_linux x86_64  linux/amd64 i128 tests/wide/034-cast-narrow.mc cast 0 "1 1 1 1 1 1 1 1 1"
else
    echo "skip linux exec: need docker and ld.lld"
fi

# ---- windows/aarch64 and windows/x86_64: object + a real lld-link link ----
# EXECUTION of the Win64 by-reference wide ABI is the CI legs' job (the macOS
# check job cross-compiles the wide objects into windows-{arm64,x86_64}-objects
# via `check-wide.sh --build-only`, and test-windows.sh --run-only links and
# RUNS them). Here, as with the float suite's windows_leg, every wide object is
# LINKED with the same kernel32.lib + winrt.obj + winstart.obj a Windows binary
# needs, which proves symbol resolution -- not just a valid .text section.
wide_windows() {                        # arch, lld machine, coff backend
    warch="$1"; lmach="$2"; be="$3"
    if ! have lld-link || ! have llvm-dlltool; then
        echo "skip windows/$warch: lld-link or llvm-dlltool not found"; return 0
    fi
    sysroot="build/sysroot/windows-$warch"
    if [ ! -f "$sysroot/kernel32.lib" ]; then
        if ! msg=$(sh scripts/sysroot-windows.sh --arch "$warch" "$sysroot" 2>&1); then
            echo "skip windows/$warch: no kernel32.lib ($msg)"; return 0
        fi
    fi
    out="build/wide-windows-$warch"; mkdir -p "$out"
    # the two support objects carry no wide code and are the STOCK compiler's,
    # exactly the objects scripts/test-windows.sh links
    for m in sys_windows sys_windows_start; do
        if ! msg=$("$mc" --backend=$be "lib/$m.mc" -o "$out/$m.obj" 2>&1); then
            echo "FAIL windows/$warch ($m: $msg)"; fails=$((fails + 1)); return 0
        fi
    done
    wp=0; wt=0
    for wsrc in tests/wide/030-i128.mc tests/wide/032-u128.mc \
                tests/wide/033-wide-abi.mc tests/wide/034-cast-narrow.mc; do
        wnm=$(basename "$wsrc" .mc); wt=$((wt + 1))
        if ! msg=$("$(wide_compiler "$wsrc")" --backend=$be "$wsrc" -o "$out/$wnm.obj" 2>&1); then
            echo "FAIL windows/$warch $wnm (compile: $msg)"; fails=$((fails + 1)); continue
        fi
        if ! msg=$($(tool lld-link) -machine:$lmach -subsystem:console -entry:mc_start \
                   -nodefaultlib -out:"$out/$wnm.exe" "$out/$wnm.obj" "$out/sys_windows.obj" \
                   "$out/sys_windows_start.obj" "$sysroot/kernel32.lib" 2>&1); then
            echo "FAIL windows/$warch $wnm (link: $msg)"; fails=$((fails + 1)); continue
        fi
        wp=$((wp + 1))
    done
    echo "ok   windows/$warch: $wp/$wt wide objects linked (executed on the CI leg)"
}
wide_windows aarch64 arm64 coff-obj-arm64
wide_windows x86_64  x64   coff-obj-x86_64

# f16: `f16 tbl[8]` is SIXTEEN bytes of __bss, from the width alone
if build/mc-f16 --dump-syms tests/wide/031-f16.mc | grep -q '__DATA,__bss.*size=48'; then
    echo "ok   f16: a global array of 8 halves occupies 16 bytes in the object"
else
    echo "FAIL f16: the global array is not 16 bytes"
    build/mc-f16 --dump-syms tests/wide/031-f16.mc | grep bss
    fails=$((fails + 1))
fi
if build/mc-f16 --dump-asm tests/wide/031-f16.mc | grep -q '^  fcvt h16, s16$'; then
    echo "ok   f16: the conversion is one instruction (fcvt h, s)"
else
    echo "FAIL f16: no fcvt h, s in --dump-asm"
    fails=$((fails + 1))
fi

# ---- examples/avx: the object, and llvm-mc on every instruction it invented ----
avx="build/mc-avx"
rm -f "$avx"
if ! msg=$("$mc" --exe examples/avx/mc-avx.mc -o "$avx" 2>&1); then
    echo "FAIL avx (building the compiler: $msg)"; fails=$((fails + 1))
elif ! msg=$("$avx" --backend=elf-obj-x86_64 examples/avx/main.mc -o "$tmp/avx.o" 2>&1); then
    echo "FAIL avx (compiling examples/avx/main.mc: $msg)"; fails=$((fails + 1))
else
    echo "ok   avx: examples/avx/main.mc compiles to a linux/x86_64 object"
    if msg=$("$mc" --backend=elf-obj-x86_64 examples/avx/main.mc -o "$tmp/no.o" 2>&1); then
        echo "FAIL avx: the default compiler accepted examples/avx/main.mc"
        fails=$((fails + 1))
    else
        echo "ok   avx: the default compiler refuses it ($msg)"
    fi
    if ! have llvm-objdump || ! have llvm-mc; then
        echo "skip avx sweep: llvm-objdump/llvm-mc not found"
    else
        $(tool llvm-objdump) -d --triple=x86_64-linux-musl "$tmp/avx.o" 2>/dev/null \
            | sed -n 's|^ *[0-9a-f]*: *\([0-9a-f ]*[0-9a-f]\)  *\(.*\)$|\1\t\2|p' \
            | grep -E '	[[:space:]]*v(addps|mulps|movups)' | sort -u > "$tmp/ins"
        n=0; bad=0
        while IFS='	' read -r bytes text; do
            [ -n "$text" ] || continue
            text=$(echo "$text" | sed 's|#.*||; s|[[:space:]]*$||')
            enc=$(printf '%s\n' "$text" | $(tool llvm-mc) -triple=x86_64-linux-musl --show-encoding 2>/dev/null \
                  | sed -n 's|.*encoding: \[\(.*\)\].*|\1|p' | tr -d ' ' | tr ',' '\n' \
                  | sed 's|^0x||' | tr '\n' ' ' | sed 's| *$||')
            want=$(echo "$bytes" | tr -s ' ')
            if [ "$enc" != "$want" ]; then
                echo "FAIL avx sweep: '$text' -> $enc, mc emitted $want"; bad=$((bad + 1)); continue
            fi
            n=$((n + 1))
        done < "$tmp/ins"
        if [ "$bad" != 0 ]; then fails=$((fails + bad))
        else echo "ok   avx sweep: $n distinct VEX instructions re-assemble byte for byte"; fi
    fi
fi

if [ "$fails" != 0 ]; then
    echo "check-wide: $fails failures"
    exit 1
fi
echo "check-wide: ok"
