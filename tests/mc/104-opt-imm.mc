// 104-opt-imm.mc — M49 step E (E.2): a constant operand becomes an immediate and
// an address sum folds into the load or store that consumes it.
//
// The boundaries are the point, because each fold is guarded by a range:
//   `arith`   add/sub at 4095 (folds) and 4096 (does not), 65535 (one movz, too
//             wide for the immediate) and 65536 (movz + movk: never a lone
//             constant); a negative; and with a mask (folds) and with 254 (not
//             a mask: stays a register); shifts by 0, 1 and 63; a comparison
//             against 4095 and 4096 -- on x86-64 every one of these fits imm32;
//   `access`  every width loaded and stored at a register offset [p + i] and at
//             a constant offset [p + k], with k both a multiple of the width
//             (folds) and not (stays an add), and a store whose value is a
//             constant or an alias -- the two shapes whose add can be folded;
//   `self`    `x = x + x` and `i = i + 1` -- on x86-64 the in-place rewrite must
//             not fold the first, whose source IS the copy.
// expect-exit: 42
// expect-stdout: 1 4094 4095 70000 70001 131071 95 255 172 22 1 2 0 1 1 0 | 7 7 7 7 6 6 1 1 1 1 1 1 14 | 150 32 7 1
#include <sys>
#include <prelude>

u8 buf[64];

void pr(i64 v) { putnum(v); puts(" "); }

void arith(i64 x) {                      // called with x == 1
    pr(x + 0);
    pr(x + 4093);
    pr(x + 4094);
    pr(x + 69999);
    pr((x + 70000) - 0);
    pr(x + 65535 + 65535);
    pr(x - 6 + 100);
    pr((x + 510) & 255);
    pr((x + 427) & 254);
    pr((x + 21) << 0);
    pr((x << 1) >> 1);
    pr(x << 1);
    pr(x >> 63);
    pr((0 - x) >> 63 & 1);
    pr(x + 4094 == 4095);
    pr(x + 4095 > 4096);
    puts("| ");
}

void access(uptr p) {
    i64 i = 3;
    st8(p + i, 7);
    st16(p + 8, 7);
    st32(p + 16, 7);
    st64(p + 24, 7);
    pr(ld8(p + i));
    pr(ld16(p + 8));
    pr(ld32(p + 16));
    pr(ld64(p + 24));
    i64 v = 6;
    st8(p + i, v);
    st64(p + 32 + i, v);                  // not a multiple of 8: stays an add
    pr(ld8(p + i));
    pr(ld64(p + 35));
    st16(p + 40, 0 - 1);
    pr(ld16(p + 40) == 65535);
    i64 j = 41;
    pr(ld8(p + j) == 255);
    i64 k = 48;                           // every width at a register offset
    st16(p + k, 0x1234);
    st32(p + k + 4 - 4 + i - 3, 0x55667788);
    st64(p + k + 8, 0x0102030405060708);
    pr(ld16(p + k) == 0x7788);
    pr(ld32(p + k) == 0x55667788);
    pr(ld64(p + k + 8) == 0x0102030405060708);
    pr(ld16(p + i + 47) == 0x5566);
    // a constant stored at an address whose index was COMPUTED: the add reads
    // the depth register the constant is then written into, so the fold must
    // not move the add past it (found by the optimized road's fixed point)
    st8(p + (i + 1), 5);
    st64(p + (i + 53), 9);
    pr(ld8(p + 4) + ld64(p + 56));
    puts("| ");
}

i64 self(i64 n) {
    i64 x = 5;
    i64 i = 0;
    i64 s = 0;
    loop {
        if (i >= n) break;
        x = x + x;
        s = s + x;
        i = i + 1;
    }
    pr(s);
    pr(i * 8);
    pr(i + 3);
    return s / 60 - 1;
}

i64 main() {
    arith(1);
    access(buf);
    putnum(self(4));
    puts("\n");
    return 42;
}
