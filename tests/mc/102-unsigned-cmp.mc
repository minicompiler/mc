// 102-unsigned-cmp.mc — machine contract v6: a comparison of u64 or uptr is
// UNSIGNED. Every integer comparison used to be signed, so any value with bit
// 63 set read as negative: `2 >= (1 << 63)` answered TRUE.
//
// It lives in tests/mc/ and not in tests/ because the frozen stage0 seed
// COMPILES this source and gets it wrong -- it has one set of six conditions --
// so check-obj.sh, which compares the two compilers object for object over
// tests/*.mc, would report the difference this file exists to prove.
//
// The rule, and it is deliberately narrower than C's: a comparison is unsigned
// only when NEITHER side is a signed type and one of them is eight bytes wide.
// Two narrow unsigned operands keep the signed code -- they are zero-extended
// into their slots, so a signed 64-bit compare of them is already right and no
// byte of the corpus moved -- and a comparison with an i64 on either side stays
// signed, so no program that works today changes meaning. Check 12 is that rule
// written as a number.
// expect-exit: 0
// expect-stdout: 011000111111

extern i64 write(i64 fd, uptr buf, i64 n);

u8 obuf[16];

void put1(i64 v) { st8(obuf, '0' + v); write(1, obuf, 1); }

i64 main() {
    u64 one = 1;
    u64 big = one << 63;                      // 0x8000000000000000
    u64 small = 2;

    // the reproducer, in the branch form the M49 peephole fuses into one
    // b.lo / jb: under a signed compare 2 >= 2^63 is TRUE and this returns 3
    if (small >= big) return 3;

    put1(small >= big);                        // 0  the same, as a value
    put1(small <  big);                        // 1
    put1(small <= big);                        // 1
    put1(small >  big);                        // 0
    put1(small >= big);                        // 0
    put1(small == big);                        // 0
    put1(small != big);                        // 1

    // uptr is an address, and an address above half the space is not negative
    uptr phi = (uptr) big;
    uptr plo = (uptr) small;
    put1(plo < phi);                           // 1

    // mixed widths, neither side signed: the eight-byte side decides
    u8 b = 200;
    put1(b < big);                             // 1

    // both narrow: the signed code, and right by zero-extension. This is the
    // shape that must NOT move, and 200 < 40000 is the proof it did not.
    u8 x = 200;
    u32 y = 40000;
    put1(x < y);                               // 1

    // the signed control: unchanged, and still signed
    i64 n = 0 - 1;
    i64 z = 1;
    put1(n < z);                               // 1

    // mixed signedness: the signed side wins, so this is -1 < 2 and not
    // 0xffffffffffffffff < 2. C would answer the other way.
    i64 s = 0 - 1;
    u64 u = 2;
    put1(s < u);                               // 1

    write(1, "\n", 1);
    return 0;
}
