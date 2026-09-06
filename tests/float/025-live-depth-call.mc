// expect-exit: 0
// expect-stdout: 0x4014000000000000 0x4087f80000000000 0x0000000040200000
// The DIRECT-call sibling of 023: a float result taken while another float depth
// is live. It matters because a machine may put its depths on top of the ABI's
// own return register -- on Win64 the float depths are xmm0..xmm5 (xmm6..xmm15
// are callee-saved), so depth 0 IS xmm0, and a machine that restores the live
// depths before it moves the result overwrites what the callee just returned.
// The 023 columns are the same defect through `callp`; nothing covered the plain
// call, which is why this file exists.
//
// Column 1 is one live depth, column 2 a spilled one (nine live floats before
// the call, six registers), column 3 the same at f32 width.
#include <sys>
#include <float_rt>

f64 dbl(f64 x)    { return x * 2.0; }
f32 half32(f32 x) { return x * 0.5f; }

i64 main() {
    f64 near = 1.0 + dbl(2.0);                                  // 5.0
    puthexf(near); puts(" ");

    f64 deep = 1.0 + (2.0 + (4.0 + (8.0 + (16.0 + (32.0 + (64.0
             + (128.0 + dbl(256.0))))))));                      // 255 + 512 = 767.0
    puthexf(deep); puts(" ");

    f32 h = 1.0f + half32(3.0f);                                // 2.5f
    puthexf32(h); puts("\n");
    return 0;
}
