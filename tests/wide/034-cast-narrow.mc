// expect-exit: 0
// expect-stdout: 1 1 1 1 1 1 1 1 1
// A narrow integer widened to i128/u128 -- the regression test for the
// sign-extension bug (lib/i128.mc wi_cast / xw_cast keyed on `src == TY_I64`
// instead of `type_signed(src)`, so a signed sub-64-bit source -- i32 -- was
// ZERO-extended and `(i128)(i32) -5` came out 2^64-5 instead of -5).
//
// The narrow values are fed through calls (mk_i32/mk_u32/mk_i64) so they are
// genuinely runtime and the folder cannot pre-evaluate the cast: a call result
// arrives at its depth sign/zero-extended to 64 bits (M45), carrying its
// declared narrow type, which is exactly what the cast reads.
//
//   (i128)(i32) -5   -> lo 0xFFFFFFFFFFFFFFFB, hi 0xFFFFFFFFFFFFFFFF   sign
//   (u128)(i32) -5   -> the SAME bits: C sign-extends a signed source whatever
//                       the wide target's signedness
//   (i128)(i32)  5   -> lo 5, hi 0
//   (i128)(i64) -5   -> the already-correct i64 path
//   (i128)(u32) 0xFFFFFFFF -> lo 0xFFFFFFFF, hi 0                        zero
#include <sys>

i32 mk_i32(i64 x) { return (i32) x; }
u32 mk_u32(i64 x) { return (u32) x; }
i64 mk_i64(i64 x) { return x; }

i64 main() {
    i128 a = (i128) mk_i32(0 - 5);            // signed narrow -> sign-extend
    putnum(i128_lo(a) == 0xfffffffffffffffb); puts(" ");
    putnum(i128_hi(a) == 0xffffffffffffffff); puts(" ");

    u128 b = (u128) mk_i32(0 - 5);            // signed source, unsigned target
    putnum(u128_lo(b) == 0xfffffffffffffffb); puts(" ");
    putnum(u128_hi(b) == 0xffffffffffffffff); puts(" ");

    i128 c = (i128) mk_i32(5);                // positive i32
    putnum(i128_lo(c) == 5 && i128_hi(c) == 0); puts(" ");

    i128 d = (i128) mk_i64(0 - 5);            // the i64 path, unchanged
    putnum(i128_lo(d) == 0xfffffffffffffffb); puts(" ");
    putnum(i128_hi(d) == 0xffffffffffffffff); puts(" ");

    i128 e = (i128) mk_u32(0xffffffff);       // unsigned narrow -> zero-extend
    putnum(i128_lo(e) == 0xffffffff); puts(" ");
    putnum(i128_hi(e) == 0); puts("\n");
    return 0;
}
