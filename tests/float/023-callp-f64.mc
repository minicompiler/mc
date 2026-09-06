// expect-exit: 0
// expect-stdout: 0x4014000000000000 0x4014000000000000 0x4087f80000000000 0x000000003fc00000
// A CAST applied directly to a `callp` declares what the indirect call returns.
//
// `callp` has no callee to read a signature from, so gen_resolve typed the node
// TY_I64 unconditionally and `walk_ret_type()` said "integer" for every indirect
// call -- which meant <float>'s MTASK_CALLP never moved d0 into the destination
// and `1.0 + callp(&dbl, 2.0)` answered 3.0 instead of 5.0 (the pointer's own
// bits were still sitting at the depth). Written with the cast, the resolver
// types the CALLP node f64, the machine moves the register, and the cast itself
// is an identity.
//
// Column 3 is the same thing at a SPILLED float depth: eight live float depths
// (v16..v23) before the call, so the result lands past FREG_MAX and goes to the
// frame with `str d` -- and the eight live ones are saved and restored around
// the `blr` like any other call.
//
// The float TYPES come from the COMPILER (build/mc-float), not from an include.
#include <sys>
#include <float_rt>

f64 dbl(f64 x) { return x * 2.0; }
f64 sub2(f64 a, f64 b) { return a - b; }
f32 half32(f32 x) { return x * 0.5f; }

i64 main() {
    f64 nested = 1.0 + (f64) callp(&dbl, 2.0);                  // 5.0
    puthexf(nested); puts(" ");

    f64 two = (f64) callp(&sub2, 7.5, 2.5);                     // 5.0, two float arguments
    puthexf(two); puts(" ");

    f64 deep = 1.0 + (2.0 + (4.0 + (8.0 + (16.0 + (32.0 + (64.0
             + (128.0 + (f64) callp(&dbl, 256.0))))))));        // 255 + 512 = 767.0
    puthexf(deep); puts(" ");

    f32 h = (f32) callp(&half32, 3.0f);                         // 1.5f
    puthexf32(h); puts("\n");
    return 0;
}
