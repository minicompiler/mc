// 096-callp-i32.mc — a cast on a `callp` declares what the indirect call
// returns, and M45's call-side extension then applies to it.
//
// A direct call reads its callee's declaration; `callp` has none, so the node
// was typed `i64` unconditionally and the value came back exactly as the callee
// left it -- every bit of the register, rubbish above bit 31 included. Written
// `(i32) callp(&f, x)`, the resolver types the CALLP node i32, the walker
// issues MTASK_CAST(i32) after the call (`sxtw` / `movsxd` / `sext.w`), and the
// written cast repeats it -- an extension is idempotent.
//
// `mixed` is declared i64 and returns a value whose high half is deliberately
// not the sign of its low half: 0x12345678_0000002a. The uncast call is the
// control -- it is still the whole 64 bits, 1311768464867721258.
//
// This is a REGRESSION GUARD and not a repro: the extension the columns need
// was already there before the contract existed, because the walker issues a
// MTASK_CAST for the written cast whatever the operand's type is. What moved is
// WHERE it happens -- the call's own depth now carries the declared type, the
// way a direct call's has since M45 -- so the written cast repeats it, and an
// `(i32) callp(...)` costs one idempotent `sxtw` more than it did. Nothing in
// the corpus writes a cast on a callp, so nothing else moves (check-inert).
//
// The file lives in tests/mc/ because the frozen seed has no `i32`.
// expect-exit: 0
// expect-stdout: 42 -1 4294967295 1311768464867721258 305419896

extern i64 write(i64 fd, uptr buf, i64 n);

u8 nbuf[24];

void puti(i64 v) {
    i64 i = 24;
    u64 u = v;
    i64 neg = 0;
    if (v < 0) { neg = 1; u = 0 - v; }
    loop {
        i = i - 1;
        st8(nbuf + i, '0' + u % 10);
        u = u / 10;
        if (u == 0) break;
    }
    if (neg) { i = i - 1; st8(nbuf + i, '-'); }
    write(1, nbuf + i, 24 - i);
}

void sp() { write(1, " ", 1); }

i64 mixed(i64 x) { return 0x1234567800000000 + x; }

i64 main() {
    uptr p = &mixed;
    puti((i32) callp(p, 42));                  // 42, sign-extended from bit 31
    sp(); puti((i32) callp(p, 0xffffffff));    // -1: the low half is all ones
    sp(); puti((u32) callp(p, 0xffffffff));    // 4294967295: the other extension
    sp(); puti(callp(p, 42));                  // the control: all 64 bits
    sp(); puti(callp(p, 42) >> 32);            // 0x12345678
    write(1, "\n", 1);
    return 0;
}
