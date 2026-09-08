// expect-exit: 0
// expect-stdout: 10 1 3000000000000000000
// Exercises the x86-64 wide-value ABI overflow that 030/032 do not. Four 16-byte
// arguments fit AArch64's eight argument registers (x0:x1 .. x6:x7), but on
// x86-64 they overflow: SysV has six integer argument registers, so the third
// pair (r8:r9) is the last that fits and the FOURTH value goes on the stack;
// Win64 passes each 16-byte value by reference and, with the hidden return
// pointer taking rcx, the fourth pointer lands on the stack above the shadow
// space. Every callee returns i128, so the return path (rax:rdx on SysV,
// by-reference on Win64) rides along. On AArch64 this compiles with everything
// in registers; a fifth wide argument in one call is refused there.
#include <sys>

i128 sum4(i128 a, i128 b, i128 c, i128 d) { return a + b + c + d; }

// the fourth argument is the stack-passed one on x86-64; return it unchanged so
// the value survives the round trip through memory and the return path
i128 pick4(i128 a, i128 b, i128 c, i128 d) { return d; }

i64 main() {
    i128 s = sum4(1i, 2i, 3i, 4i);                    // 10
    putnum(i128_lo(s)); puts(" ");                    // 10

    i128 big = 18446744073709551616i;                // 2^64, hi=1 lo=0
    i128 r = pick4(0i, 0i, 0i, big);                  // d on the stack (x86), returned
    putnum(i128_hi(r)); puts(" ");                    // 1

    i128 m = sum4(1000000000000000000i, 1000000000000000000i, 1000000000000000000i, 0i);
    putnum(i128_lo(m)); puts("\n");                   // 3000000000000000000
    return 0;
}
