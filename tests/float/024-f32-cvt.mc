// expect-exit: 25
// expect-stdout: 25 25 0x00000000c1c80000 0x000000005f800000 0x4039000000000000 0x000000003f000000
// Every conversion that names an f32, in both directions.
//
// The AArch64 machine picks the single-precision form of an instruction by
// walking a fixed distance in its own opcode table (`fa_w`), and the four
// conversions -- scvtf, ucvtf, fcvtzs, fcvtzu -- were the rows it did not walk:
// the `_S` opcodes existed and were never chosen, so `(i64) <f32 expr>` came out
// as `fcvtzs x, d` reading a register that held a single, and this file's exit
// code was 0 instead of 25. The x86-64 machine's `fx_w2` always mapped both
// pairs, which is why the same source was right there.
//
// f32 <-> f64 is `fcvt` (cvtss2sd/cvtsd2ss) and takes no table walk; it is here
// so that all five conversions of the two-width family are in one place.
//
// `p` is computed at run time (2.5f * 10.0f) on purpose: a cast of a literal
// never reaches a machine.
#include <sys>
#include <float_rt>

i64 main() {
    f32 y = 2.5f;
    f32 p = y * 10.0f;                  // 25.0f
    i64 sn = 0 - 25;
    u64 un = 0xffffffffffffffff;
    f64 d = 0.5;

    putnum((i64) p);      puts(" ");    // 25            fcvtzs x, s
    putnum((u64) p);      puts(" ");    // 25            fcvtzu x, s
    puthexf32((f32) sn);  puts(" ");    // -25.0f        scvtf s, x
    puthexf32((f32) un);  puts(" ");    // 2^64 as f32   ucvtf s, x
    puthexf((f64) p);     puts(" ");    // 25.0          fcvt d, s
    puthexf32((f32) d);   puts("\n");   // 0.5f          fcvt s, d
    return (i64) (y * 10.0f);           // 25 -- the whole defect, as an exit code
}
