// expect-exit: 42
// expect-stdout: 0x00000000c640e400 0xc0c81c8000000000 0x00000000c640e400 0xc0c81c8000000000 0x00000000c1c80000 0xc039000000000000 0x00000000c1c80000 0xc039000000000000
// A NEGATIVE integer converted to f32 AND f64, from both an i32 (a TK_SINT
// narrow type) and an i64 (the full-width signed type). This is the coverage
// 024 and 026 each left half-open:
//
//   024-f32-cvt        (f32) of an i64 only
//   026-signed-narrow  (f64) of an i32 only
//
// so narrow-signed -> f32 -- `scvtf s, x` reached from a TK_SINT source -- was
// exercised by nothing. It is right on aarch64 (fa_cast tests type_signed, since
// the fix in 026's milestone) and on x86-64 (fx_cast treats everything but
// TY_U64/TY_UPTR as signed), and this file is what says so on every leg.
//
// Each value is fed through a call (gi32/gi64) so the folder cannot pre-evaluate
// the cast: a cast of a literal never reaches a machine. puthexf/puthexf32 store
// with stf64/stf32 and read the bytes back with ld64, so each field is the exact
// bit pattern -- not a rendering. The eight expected words were confirmed against
// the running compiler and cross-checked with struct.pack:
//
//   -12345.0  f32 0xc640e400  f64 0xc0c81c8000000000
//     -25.0   f32 0xc1c80000  f64 0xc039000000000000
//
// The i32 column and the i64 column are identical because the value fits both
// widths; what differs is the SOURCE type the machine's cast sees (i32 is
// TK_SINT, i64 is TY_I64), and both must choose scvtf, never ucvtf.
#include <sys>
#include <float_rt>

i32 gi32(i32 x) { return x; }
i64 gi64(i64 x) { return x; }

i64 main() {
    i32 a = gi32(0 - 12345);
    i64 b = gi64(0 - 12345);
    i32 c = gi32(0 - 25);
    i64 d = gi64(0 - 25);

    puthexf32((f32) a); puts(" ");     // -12345.0f from i32   scvtf s, x
    puthexf((f64) a);   puts(" ");     // -12345.0  from i32   scvtf d, x
    puthexf32((f32) b); puts(" ");     // -12345.0f from i64   scvtf s, x
    puthexf((f64) b);   puts(" ");     // -12345.0  from i64   scvtf d, x
    puthexf32((f32) c); puts(" ");     //    -25.0f from i32   scvtf s, x
    puthexf((f64) c);   puts(" ");     //    -25.0  from i32   scvtf d, x
    puthexf32((f32) d); puts(" ");     //    -25.0f from i64   scvtf s, x
    puthexf((f64) d);   puts("\n");    //    -25.0  from i64   scvtf d, x
    return 42;
}
