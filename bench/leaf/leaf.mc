// leaf.mc -- the byte-loop microbenchmark of M49 step E (docs/specs/M49.md
// § Step E). Three LEAF functions in the shapes mc-php's hot runtime loops
// have (its docs/plan.md § 5): a byte sum, a strspn-shaped bitmap scan and a
// schoolbook add of two digit buffers. Each is called over a 4096-byte buffer
// many times from main, so the time is the leaf's own; a fourth phase calls
// all three on SHORT (16-byte) inputs, where the cost is the call, not the loop.
//
// One argument selects a phase by its first byte -- sum, spn, dadd, h(short); no
// argument runs all four. The printed numbers are the cross-check with
// leaf.c, which is the same program in C.
#include <sys>

#define LEN 4096
#define REPS 200000
#define SHORT 16
#define SREPS 40000000

u8 buf[LEN];
u8 bm[32];
u8 da[LEN];
u8 db[LEN];
u8 dout[LEN];

// the reproducer of mc-php's docs/plan.md § 5, verbatim
i64 leaf(uptr p, i64 n) {
    i64 s = 0;
    i64 i = 0;
    loop { if (i >= n) break; s = s + ld8(p + i); i = i + 1; }
    return s;
}

// php_spn's inner loop: how many leading bytes are (want = 1) or are not
// (want = 0) in the set the 256-bit map bm describes
i64 spn(uptr p, uptr m, i64 len, i64 want) {
    i64 i = 0;
    loop {
        if (i >= len) break;
        i64 c = ld8(p + i);
        if (((ld8(m + (c >> 3)) >> (c & 7)) & 1) != want) break;
        i = i + 1;
    }
    return i;
}

// o = a + b over n little-endian decimal digits; returns the carry out
i64 dadd(uptr a, uptr b, uptr o, i64 n) {
    i64 c = 0;
    i64 i = 0;
    loop {
        if (i >= n) break;
        i64 d = ld8(a + i) + ld8(b + i) + c;
        c = 0;
        if (d >= 10) { d = d - 10; c = 1; }
        st8(o + i, d);
        i = i + 1;
    }
    return c;
}

i64 main(i64 argc, uptr argv) {
    i64 ph = 'a';
    if (argc > 1) ph = ld8(ld64(argv + 8));
    if (ph != 's' && ph != 'p' && ph != 'd' && ph != 'h') ph = 'a';
    i64 i = 0;
    loop {                                   // bytes 'a'..'z', and digits
        if (i >= LEN) break;
        st8(buf + i, 'a' + i % 26);
        st8(da + i, i % 10);
        st8(db + i, (i * 7) % 10);
        i = i + 1;
    }
    i = 'a';
    loop {                                   // the set is every lowercase letter
        if (i > 'z') break;
        st8(bm + (i >> 3), ld8(bm + (i >> 3)) | (1 << (i & 7)));
        i = i + 1;
    }
    i64 r = 0;
    i64 t = 0;
    if (ph == 's' || ph == 'a') {
        t = 0; r = 0;
        loop { if (r >= REPS) break; t = t + leaf(buf, LEN - (r & 1)); r = r + 1; }
        putnum(t); puts("\n");
    }
    if (ph == 'p' || ph == 'a') {
        t = 0; r = 0;
        loop { if (r >= REPS) break; t = t + spn(buf, bm, LEN - (r & 1), 1); r = r + 1; }
        putnum(t); puts("\n");
    }
    if (ph == 'd' || ph == 'a') {
        t = 0; r = 0;
        loop {
            if (r >= REPS) break;
            t = t + dadd(da, db, dout, LEN - (r & 1)) + ld8(dout + (r & 1023));
            r = r + 1;
        }
        putnum(t); puts("\n");
    }
    if (ph == 'h' || ph == 'a') {                 // the same three on SHORT inputs:
        t = 0; r = 0;                               // what a call costs, not a loop
        loop {
            if (r >= SREPS) break;
            i64 k = r & 7;
            t = t + leaf(buf + k, SHORT) + spn(buf + k, bm, SHORT, 1) + dadd(da + k, db, dout, SHORT);
            r = r + 1;
        }
        putnum(t); puts("\n");
    }
    return 0;
}
