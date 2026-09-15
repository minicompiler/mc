// expect-exit: 0
// expect-stdout: 15 1 0 7 4616189618054758400 1073741824
// Two taught modules with three machines in ONE compiler: <float> (and its two
// derived machines) and <i128>/<u128>. The compiler that builds this file also
// carries <f16>, whose band is a third one -- but <f16> registers on `arm64`
// only, so the columns below stop where every target can follow (the arm64
// dump of tests/wide/031-f16.mc through the same compiler is what proves the
// third band, in scripts/check-wide.sh).
//
// Every derived machine claims a band of the opcode space the `arm64` and
// `x86_64` tables share, and before docs/reference/machine.md § 3 gave those
// bands a registry and the obligation to bound each at BOTH ends, two of these
// modules could not coexist:
//
//   arm64   <float> answered `op >= 100` for every opcode above its own base, so
//           with i128_init BEFORE machine_arm64_float_init the wide `umulh`
//           (205) was encoded by the float table and `i128 y = x * 3i` died with
//           SIGILL (exit 132).
//   x86-64  <float> and <i128> were both based at 100: XW_ADC..XW_SETCC were
//           byte for byte FX_ADD_D..FX_DIV_D, so whichever module derived second
//           encoded the other's instructions -- `mc: i128/u128 x86: no dump for
//           a wide opcode` on a plain `f64 b = a + a` in one order, and a silent
//           `mulsd` where a `mul` belongs in the other.
//
// So every column below is a different band, in one function, and the same
// program is compiled by lib/mc_float_wide.mc and lib/mc_wide_float.mc -- the
// two registration orders -- to the same object.
//
//   15          the wide product 5 * 3 (WI_UMULH on arm64, XW_MUL on x86-64)
//   1 0         2^32 * 2^32 = 2^64: a product that lands entirely in the HIGH
//               half, which is the umulh / mul-rdx path and nothing else
//   7           an unsigned wide compare (cset lo / setb) and a wide add
//   4616189...  the f64 sum 1.5 + 2.5 = 4.0, by its bits (0x4010000000000000)
//   1073741824  the f32 product 0.5 * 4.0 = 2.0, by its bits (0x40000000)
//
// Nothing here crosses a FUNCTION BOUNDARY carrying a type either module owns,
// and that restriction is deliberate. `<float>` and `<i128>` each keep their own
// AAPCS64/SysV argument counters, and each handles a type it does NOT own itself
// instead of delegating it -- correct for a lone extension, wrong for two
// stacked: whichever registered last reads the other's parameter out of the
// wrong register file (measured both ways: a f64 parameter arrives in x0 with
// i128 on top, a 16-byte parameter arrives in one register instead of an even
// pair with float on top). That is a SEPARATE defect, in the contract rather
// than in a band -- MTASK_PARAM has no way for one machine to tell the next how
// many registers it consumed -- and it is reported on its own. This file is the
// opcode-band one and stops where the band ends.
// <float_rt> is deliberately NOT included: its putf64/fmt_f64 take f64
// PARAMETERS, which is the separate defect above, and compiling them would make
// the two registration orders disagree on this file for a reason that has
// nothing to do with an opcode band.
#include <sys>

i64 main() {
    // the wide band
    i128 x = 5i;
    i128 y = x * 3i;
    putnum(i128_lo(y)); puts(" ");
    i128 e = 4294967296i;                         // 2^32
    i128 f = e * e;                               // 2^64: hi 1, lo 0
    putnum(i128_hi(f)); puts(" ");
    putnum(i128_lo(f)); puts(" ");
    u128 a = 3i;
    u128 b = 4i;
    i64 z = 0;
    if (a < b) z = i128_lo(a + b);
    putnum(z); puts(" ");

    // the float band, in the same function
    u64 r[1];
    f64 s = 1.5 + 2.5;
    stf64(r, s);
    putnum(ld64(r)); puts(" ");
    f32 p = 0.5f * 4.0f;
    st64(r, 0);
    stf32(r, p);
    putnum(ld64(r)); puts("\n");
    return 0;
}
