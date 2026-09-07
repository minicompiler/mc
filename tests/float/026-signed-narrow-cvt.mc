// expect-exit: 42
// expect-stdout: 0xc014000000000000 0x00000000c0a00000 0x41efffffffe00000 0xfffffffffffffffb 0x0000000000000005
// A SIGNED NARROW integer (i32, a TK_SINT kind) converted to and from a float.
//
// The AArch64 machine (lib/machine_arm64_float.mc, `fa_cast`) decided the
// signedness of a conversion by testing `== TY_I64`, which is true only of the
// full-width signed integer and MISSES every TK_SINT narrow type. So `(f64) d`
// for an i32 `d` came out as `ucvtf d, x` and `-5` was converted as if it were
// 18446744073709551611.0 -- a silently wrong result, exit code and all. The fix
// tests `type_signed()` (`t == TY_I64 || type_kind(t) == TK_SINT`) instead, so
// `scvtf`/`fcvtzs` are chosen for i32 just as they are for i64.
//
// The x86-64 machine's `fx_cast` already treated everything but TY_U64/TY_UPTR
// as signed, so the same source was right there; this file is what makes the two
// agree, on all five legs.
//
// puthexf/puthexf32 store with stf64/stf32 and read the bytes back with ld64, so
// each field is the exact bit pattern -- not a rendering. The u32 column is the
// UNSIGNED control: it must stay the large positive (ucvtf), which is how the
// fix is shown to leave the unsigned path alone.
#include <sys>
#include <float_rt>

i64 main() {
    i32 n = 0 - 5;
    u32 u = 4294967295;
    f64 neg = 0.0 - 5.0;
    f64 pos = 5.0;

    i32 rs = (i32) neg;                 // -5, signed destination:   fcvtzs
    u32 ru = (u32) pos;                 //  5, unsigned destination: fcvtzu

    puthexf((f64) n);    puts(" ");     // -5.0            0xc014000000000000  scvtf d, x
    puthexf32((f32) n);  puts(" ");     // -5.0f           0x...c0a00000       scvtf s, x
    puthexf((f64) u);    puts(" ");     // 4294967295.0    0x41efffffffe00000  ucvtf d, x (control)
    puthex64((u64) rs);  puts(" ");     // -5              0xfffffffffffffffb
    puthex64((u64) ru);  puts("\n");    //  5              0x0000000000000005
    return 42;
}
