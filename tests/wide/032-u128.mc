// expect-exit: 0
// expect-stdout: 1 1 1 0 0 1 0 1 1 42 1 1
// u128 -- a 128-bit UNSIGNED integer taught by lib/i128.mc alongside i128. It
// shares the machine; the one difference is the compare, and this test pins it:
// the all-ones value is the MAXIMUM as u128 (> 5) but is -1 as i128 (< 5), with
// the same bits underneath.
#include <sys>

u128 addu(u128 a, u128 b) { return a + b; }

i64 main() {
    u128 max = 0u - 1u;                   // 2^128 - 1
    putnum(u128_lo(max) == 0xffffffffffffffff); puts(" ");   // 1
    putnum(u128_hi(max) == 0xffffffffffffffff); puts(" ");   // 1
    putnum(max > 5u); puts(" ");                              // 1  unsigned: huge
    putnum(max < 5u); puts(" ");                              // 0

    i128 neg = 0i - 1i;                   // -1, the same bit pattern
    putnum(neg > 5i); puts(" ");                              // 0  signed: -1 < 5
    putnum(neg < 5i); puts(" ");                              // 1

    u128 a = 18446744073709551615u;       // 2^64 - 1
    u128 c = a + 1u;                      // 2^64: lo 0, hi 1
    putnum(u128_lo(c)); puts(" ");                            // 0
    putnum(u128_hi(c)); puts(" ");                            // 1

    u128 e = 4294967296u;                 // 2^32
    u128 f = e * e;                       // 2^64
    putnum(u128_hi(f)); puts(" ");                            // 1

    u128 s = addu(40u, 2u);               // a call passing and returning u128
    putnum(u128_lo(s)); puts(" ");                            // 42

    putnum(max >= max); puts(" ");                            // 1
    putnum(5u <= max); puts("\n");                            // 1
    return 0;
}
