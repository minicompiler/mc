// i128.mc — 128-bit integers (signed `i128` and unsigned `u128`) taught to `mc`
// from outside the compiler, on every hardware-capable ISA.
//
// It is the wide-integer counterpart of `<float>`: the core has no 128-bit type,
// and this module supplies two of them the way `<float>` supplies f64/f32 --
// with nothing in `src/`. The coverage is the same as `<float>`'s, the ISAs that
// have a native carry chain and a wide multiply:
//
//   arm64                 adds/adc, subs/sbc, mul/umulh
//   x86_64 (SysV)         add/adc, sub/sbb, mul (rdx:rax)
//   x86_64-win (Win64)    the same instructions; the ABI is by-reference
//
// riscv64 (an example machine) and avr (8-bit, no wide multiply) are out of
// scope by decision: they have no single derived machine that could carry it.
//
// The eight mechanisms are the M24 ones:
//
//   type_new("i128", 16, 16, TK_WIDE)   the width gives a 16-byte frame slot
//   type_new("u128", 16, 16, TK_WIDE)   (M5), a 16-byte global and array element
//   syntax_lit                          `123i` and `123u` -- a 128-bit value does
//                                       not fit MTASK_CONST's i64, so the literal
//                                       becomes a module-private GLOBAL with an
//                                       N_BLOB initializer, and the node is a load
//   walk_depth_type                     what tells the machine a depth is wide,
//                                       and -- keyed by the exact id -- whether it
//                                       is SIGNED (i128) or UNSIGNED (u128)
//   machine_tab / machine_slot          the three derived machines below
//
// **The value lives in ONE depth, backed by a 16-byte slot.** A value spanning
// two depths would collide with gen_binary's `depth + 1` and gen_call's
// `depth + i` -- the walker's own arithmetic. Memory residency is the price, and
// carry survives it: a load or a store touches no flag register.
//
// **u128 is i128 with an unsigned compare.** add/sub/low-multiply/load/store/
// call/ret are the same bits; the ONLY difference is that the six ordering
// comparisons use unsigned conditions. type_signed answers false for both
// (TK_WIDE), so the core cannot tell them apart -- the machine keys on the id,
// `walk_depth_type(d) == ty_u128`. That is a lib-only choice: a TK_UWIDE kind
// would work too, but it is a core line and TK_WIDE already means "wide integer
// in a slot". Op set: `+ - *`, the six comparisons, load/store, call/ret, the
// literal, and lo/hi -- no divide, shift or bitwise (M24 defers them; a language
// building `decimal` on top does its division in its own runtime, from lo/hi).

i64 ty_i128 = 0;
i64 ty_u128 = 0;

#define IW_LO 0                       // the two halves, little-endian in memory
#define IW_HI 8

// ---- shared bookkeeping: the 16-byte slot a wide depth lives in ----
i64  iw_slot[MAXDEPTH];               // the slot offset of each wide depth
i64  iw_nlit = 0;                     // module-private literal globals, numbered

i64  iw_slot_at(i64 d)            { return ld64(iw_slot + d * 8); }
void set_iw_slot_at(i64 d, i64 v) { st64(iw_slot + d * 8, v); }

// a wide type? (guarded so the machine works whether or not u128 was registered)
i64 iw_is(i64 t)  { return (ty_i128 && t == ty_i128) || (ty_u128 && t == ty_u128); }
i64 iw_uns(i64 t) { return ty_u128 && t == ty_u128; }

// the frame slot a wide depth lives in, asked for once per function
i64 iw_depth(i64 d) {
    if (iw_slot_at(d) == 0) set_iw_slot_at(d, slot_new(16));
    return iw_slot_at(d);
}

// ---- the intrinsics lo/hi: registered once, dispatched to the machine in
// effect. Each machine's prologue sets iwh_lo/iwh_hi, exactly as <float>'s
// flh_* hooks are set by fa_claim/fx_claim. ----
uptr iwh_lo = 0;
uptr iwh_hi = 0;
void iw_i_lo(i64 d, i64 na) { callp(iwh_lo, d, na); }
void iw_i_hi(i64 d, i64 na) { callp(iwh_hi, d, na); }

// ---- the literal: `<digits>i` -> i128, `<digits>u` -> u128, up to 2^128 - 1 ----
// The bytes go into a module-private global, because MTASK_CONST carries one i64
// and an N_INT's val is one i64. The initializer is an N_BLOB (M21.5), the one
// node kind that puts arbitrary bytes into a section.
u64 iw_l0 = 0;
u64 iw_l1 = 0;
u64 iw_l2 = 0;
u64 iw_l3 = 0;

void iw_reset() { iw_l0 = 0; iw_l1 = 0; iw_l2 = 0; iw_l3 = 0; }

i64 iw_isdig(i64 c) { return c >= '0' && c <= '9'; }

void iw_muladd(u64 m, u64 add) {      // value = value * m + add, 128 bits
    u64 c = add;
    u64 p = iw_l0 * m + c;  iw_l0 = p & 0xffffffff;  c = p >> 32;
    p = iw_l1 * m + c;      iw_l1 = p & 0xffffffff;  c = p >> 32;
    p = iw_l2 * m + c;      iw_l2 = p & 0xffffffff;  c = p >> 32;
    p = iw_l3 * m + c;      iw_l3 = p & 0xffffffff;
}

i64 iw_lit() {
    uptr s = p_start();
    uptr e = p_src_end();
    if (s >= e || !iw_isdig(ld8(s))) return 0;
    uptr q = s;
    iw_reset();
    loop {
        if (q >= e || !iw_isdig(ld8(q))) break;
        iw_muladd(10, ld8(q) - '0');
        q = q + 1;
    }
    if (q >= e) return 0;
    i64 suf = ld8(q);                             // `123i` -> i128, `123u` -> u128
    i64 ty = 0;
    if (suf == 'i') ty = ty_i128;
    else if (suf == 'u') ty = ty_u128;
    else return 0;
    if (ty == 0) return 0;                        // that width is not registered
    if (q + 1 < e && is_alnum(ld8(q + 1))) return 0;
    i64 line = p_line();
    uptr fl = p_file();
    q = q + 1;
    p_take_lit(q);

    u64 lo = iw_l0 | (iw_l1 << 32);
    u64 hi = iw_l2 | (iw_l3 << 32);
    uptr b = xalloc(16);
    i64 i = 0;
    loop {                                        // little-endian, byte by byte
        if (i >= 8) break;
        st8(b + i, (lo >> (i * 8)) & 0xff);
        st8(b + 8 + i, (hi >> (i * 8)) & 0xff);
        i = i + 1;
    }
    // one global per literal. The name carries `$`, which the lexer never forms
    // into an identifier, so it cannot collide with anything a program wrote.
    u8 nb[24];
    i64 nn = 0;
    i64 v = iw_nlit;
    iw_nlit = iw_nlit + 1;
    loop {
        st8(nb + nn, '0' + v % 10);
        v = v / 10;
        nn = nn + 1;
        if (v == 0) break;
    }
    uptr pfx = "$i128_";
    if (ty == ty_u128) pfx = "$u128_";
    uptr name = xalloc(8 + nn);
    mem_copy(name, pfx, 6);
    i64 k = 0;
    loop {
        if (k >= nn) break;
        st8(name + 6 + k, ld8(nb + nn - 1 - k));
        k = k + 1;
    }
    i64 blob = node_new(N_BLOB, line, fl);
    set_nd_name(blob, b);
    set_nd_val(blob, 16);
    i64 g = node_new(N_GLOBAL, line, fl);
    set_nd_type(g, ty);
    set_nd_name(g, name);
    set_nd_val(g, 0);
    set_nd_a(g, blob);
    top_add(g);
    i64 id = node_new(N_IDENT, line, fl);         // the expression is the global
    set_nd_name(id, name);
    set_nd_type(id, ty);
    p_next();
    return id;
}

// ============================================================================
// The arm64 machine.
// ============================================================================
// Slots replaced; everything else delegates. New opcodes above every I_* the
// bundled machine uses, with their own encoder, sizer and dump, so `--dump-asm`
// shows `adds`/`adc` and not a raw word.
#define WI_BASE   200
#define WI_ADDS   200
#define WI_ADC    201
#define WI_SUBS   202
#define WI_SBC    203
#define WI_SBCS   204
#define WI_UMULH  205
#define WI_ASR63  206
#define WI_CMPZ   207                 // subs xzr, rn, rm  -- the low half of a compare
#define WI_SBCZ   208                 // sbcs xzr, rn, rm  -- and the high half
#define WI_CSET   209                 // cset rd, <cond>   -- an unsigned condition (hs/lo)
#define WI_MAXOP  210

// arm64 condition codes for the UNSIGNED compare (the core only ever uses the
// signed/equal ones, so these are the module's).
#define WC_HS 2                       // unsigned >=  (carry set: no borrow)
#define WC_LO 3                       // unsigned <   (carry clear: borrow)

u32 wi_base[] = { 0xAB000000, 0x9A000000, 0xEB000000, 0xDA000000, 0xFA000000,
                  0x9BC07C00, 0x937FFC00, 0xEB00001F, 0xFA00001F };
uptr wi_name[] = { "adds", "adc", "subs", "sbc", "sbcs", "umulh", "asr", "subs", "sbcs" };
i64  wi_ops[]  = { 3, 3, 3, 3, 3, 3, 2, 9, 9 };   // operands: 3, 2, or 9 = xzr form

i64  wi_base_at(i64 i) { return ld32(wi_base + i * 4); }
uptr wi_name_at(i64 i) { return ld64(wi_name + i * 8); }
i64  wi_ops_at(i64 i)  { return ld64(wi_ops + i * 8); }

uptr iw_tab;
uptr iw_orig;
i64  iw_ngrn = 0;                     // AAPCS64 counters, per function
i64  iw_pstk = 0;

uptr iw_of(i64 task) { return ld64(iw_orig + task * 8); }

// load one half of a wide depth into an integer register
i64 iw_half(i64 d, i64 half, i64 reg) {
    em(I_LDR, reg, REG_FRAME, 0 - iw_depth(d) + half);
    return reg;
}

void iw_put(i64 d, i64 half, i64 reg) {
    em(I_STR, reg, REG_FRAME, 0 - iw_depth(d) + half);
}

void wi_lo(i64 d, i64 na) {
    i64 rd = dst_reg(d);
    em(I_LDR, rd, REG_FRAME, 0 - iw_depth(d));
    dst_done(d, rd);
}

void wi_hi(i64 d, i64 na) {
    i64 rd = dst_reg(d);
    em(I_LDR, rd, REG_FRAME, 0 - iw_depth(d) + 8);
    dst_done(d, rd);
}

void wi_prologue() {
    i64 d = 0;
    loop {
        if (d >= MAXDEPTH) break;
        set_iw_slot_at(d, 0);
        d = d + 1;
    }
    iw_ngrn = 0;
    iw_pstk = 0;
    iwh_lo = &wi_lo;
    iwh_hi = &wi_hi;
    callp(iw_of(MTASK_PROLOGUE));
}

// a + b and a - b: two halves, and the carry survives the loads and stores
// between them because ldr/str do not touch NZCV
void wi_addsub(i64 d, i64 d2, i64 first, i64 second) {
    iw_half(d, IW_LO, REG_S1);
    iw_half(d2, IW_LO, REG_S2);
    e3(first, REG_TMP, REG_S1, REG_S2);
    iw_half(d, IW_HI, REG_S1);
    iw_half(d2, IW_HI, REG_S2);
    e3(second, REG_S1, REG_S1, REG_S2);
    iw_put(d, IW_HI, REG_S1);
    iw_put(d, IW_LO, REG_TMP);
}

// (hi:lo) = (hi1:lo1) * (hi2:lo2), the school product with the top half dropped:
// lo = lo1*lo2, hi = umulh(lo1,lo2) + lo1*hi2 + hi1*lo2. Every load happens
// before the two stores, so an in-place multiply cannot read what it wrote.
void wi_mul(i64 d, i64 d2) {
    iw_half(d, IW_LO, REG_S1);
    iw_half(d2, IW_LO, REG_S2);
    e3(WI_UMULH, REG_TMP, REG_S1, REG_S2);
    iw_half(d, IW_LO, REG_S1);
    iw_half(d2, IW_HI, REG_S2);
    e3(I_MUL, REG_S1, REG_S1, REG_S2);
    e3(I_ADD, REG_TMP, REG_TMP, REG_S1);
    iw_half(d, IW_HI, REG_S1);
    iw_half(d2, IW_LO, REG_S2);
    e3(I_MUL, REG_S1, REG_S1, REG_S2);
    e3(I_ADD, REG_TMP, REG_TMP, REG_S1);
    iw_half(d, IW_LO, REG_S1);
    iw_half(d2, IW_LO, REG_S2);
    e3(I_MUL, REG_S1, REG_S1, REG_S2);
    iw_put(d, IW_HI, REG_TMP);
    iw_put(d, IW_LO, REG_S1);
}

void wi_bin(i64 op, i64 d, i64 d2) {
    if (!iw_is(walk_depth_type(d))) { callp(iw_of(MTASK_BIN), op, d, d2); return; }
    if (op == MOP_ADD) { wi_addsub(d, d2, WI_ADDS, WI_ADC); return; }
    if (op == MOP_SUB) { wi_addsub(d, d2, WI_SUBS, WI_SBC); return; }
    if (op == MOP_MUL) { wi_mul(d, d2); return; }
    die("i128/u128: only + - * are taught (docs/specs/M24.md defers the rest)");
}

// `subs` on the low halves and `sbcs` on the high ones leaves N, V and C exactly
// as a 128-bit subtraction would. For the SIGNED type `ge`/`lt` read N==V off the
// flags; for the UNSIGNED type `hs`/`lo` read the carry (C set = no borrow =
// unsigned >=). Z reflects only the high half, so equality is computed
// separately -- (lo1 ^ lo2) | (hi1 ^ hi2) -- and `>` and `<=` are built from the
// two: `gt = ge && !eq`, `le = lt || eq`. x8 carries the equality flag across
// the subs/sbcs pair: nothing between them writes it.
void wi_eqflag(i64 d, i64 d2, i64 cc) {
    iw_half(d, IW_LO, REG_S1);
    iw_half(d2, IW_LO, REG_S2);
    e3(I_EOR, REG_S1, REG_S1, REG_S2);
    iw_half(d, IW_HI, REG_TMP);
    iw_half(d2, IW_HI, REG_S2);
    e3(I_EOR, REG_S2, REG_TMP, REG_S2);
    e3(I_ORR, REG_S1, REG_S1, REG_S2);
    ei(I_CMPI, 0, REG_S1, 0);
    ins_add(I_CSET, REG_TMP, 0, 0, cc, 0, 0);
}

void wi_cmp(i64 cond, i64 d, i64 d2) {
    i64 dt = walk_depth_type(d);
    if (!iw_is(dt)) { callp(iw_of(MTASK_CMP), cond, d, d2); return; }
    i64 uns = iw_uns(dt);
    if (cond == MCOND_EQ || cond == MCOND_NE) {
        i64 c = C_EQ;
        if (cond == MCOND_NE) c = C_NE;
        wi_eqflag(d, d2, c);
        i64 rd = dst_reg(d);
        e2(I_MOV, rd, REG_TMP);
        dst_done(d, rd);
        return;
    }
    // `>` needs "not equal" and `<=` needs "equal", both computed BEFORE the
    // subtraction that sets the flags they are combined with
    i64 need = 0;
    if (cond == MCOND_GT) { wi_eqflag(d, d2, C_NE); need = 1; }
    if (cond == MCOND_LE) { wi_eqflag(d, d2, C_EQ); need = 2; }
    iw_half(d, IW_LO, REG_S1);
    iw_half(d2, IW_LO, REG_S2);
    e3(WI_CMPZ, 0, REG_S1, REG_S2);
    iw_half(d, IW_HI, REG_S1);
    iw_half(d2, IW_HI, REG_S2);
    e3(WI_SBCZ, 0, REG_S1, REG_S2);
    i64 base = cond;
    if (cond == MCOND_GT) base = MCOND_GE;        // gt = ge && !eq
    if (cond == MCOND_LE) base = MCOND_LT;        // le = lt || eq
    i64 rd = dst_reg(d);
    if (uns) {                                    // hs (>=) / lo (<)
        i64 wc = WC_HS;
        if (base == MCOND_LT) wc = WC_LO;
        ins_add(WI_CSET, rd, 0, 0, wc, 0, 0);
    } else {
        ins_add(I_CSET, rd, 0, 0, cond_arm_at(base), 0, 0);
    }
    if (need == 1) e3(I_AND, rd, rd, REG_TMP);
    if (need == 2) e3(I_ORR, rd, rd, REG_TMP);
    dst_done(d, rd);
}

void wi_copy(i64 dst_off, i64 dst_base, i64 src_off, i64 src_base) {
    em(I_LDR, REG_S1, src_base, src_off);
    em(I_STR, REG_S1, dst_base, dst_off);
    em(I_LDR, REG_S1, src_base, src_off + 8);
    em(I_STR, REG_S1, dst_base, dst_off + 8);
}

void wi_local_load(i64 ty, i64 d, i64 off) {
    if (!iw_is(ty)) { callp(iw_of(MTASK_LOCAL_LOAD), ty, d, off); return; }
    wi_copy(0 - iw_depth(d), REG_FRAME, 0 - off, REG_FRAME);
}

void wi_local_store(i64 ty, i64 d, i64 off) {
    if (!iw_is(ty)) { callp(iw_of(MTASK_LOCAL_STORE), ty, d, off); return; }
    wi_copy(0 - off, REG_FRAME, 0 - iw_depth(d), REG_FRAME);
}

void wi_global_load(i64 ty, i64 d, i64 sym) {
    if (!iw_is(ty)) { callp(iw_of(MTASK_GLOBAL_LOAD), ty, d, sym); return; }
    gen_gaddr(REG_S2, sym);
    wi_copy(0 - iw_depth(d), REG_FRAME, 0, REG_S2);
}

void wi_global_store(i64 ty, i64 d, i64 sym) {
    if (!iw_is(ty)) { callp(iw_of(MTASK_GLOBAL_STORE), ty, d, sym); return; }
    gen_gaddr(REG_S2, sym);
    wi_copy(0, REG_S2, 0 - iw_depth(d), REG_FRAME);
}

// AAPCS64 passes a 16-byte integer in an EVEN-numbered register pair, which is
// the one rule a positional ABI would get wrong.
void wi_param_reg(i64 ty, i64 i, i64 r) {
    if (iw_is(ty)) die("an i128/u128 parameter in an allocatable register");
    if (iw_ngrn < REG_ARGS) {
        e2(I_MOV, REG_ALLOC + r, iw_ngrn);
        iw_ngrn = iw_ngrn + 1;
    } else {
        em(I_LDR, REG_ALLOC + r, REG_FP, 16 + iw_pstk * 8);
        iw_pstk = iw_pstk + 1;
    }
    gen_cast(REG_ALLOC + r, ty);
}

void wi_param(i64 ty, i64 i, i64 off) {
    if (!iw_is(ty)) {
        if (iw_ngrn < REG_ARGS) {
            em(mem_op(ty, 1), iw_ngrn, REG_FRAME, 0 - off);
            iw_ngrn = iw_ngrn + 1;
            return;
        }
        em(I_LDR, REG_S1, REG_FP, 16 + iw_pstk * 8);
        em(mem_op(ty, 1), REG_S1, REG_FRAME, 0 - off);
        iw_pstk = iw_pstk + 1;
        return;
    }
    if (iw_ngrn % 2) iw_ngrn = iw_ngrn + 1;       // the even-pair rule
    if (iw_ngrn + 1 < REG_ARGS) {
        em(I_STR, iw_ngrn, REG_FRAME, 0 - off);
        em(I_STR, iw_ngrn + 1, REG_FRAME, 0 - off + 8);
        iw_ngrn = iw_ngrn + 2;
        return;
    }
    if (iw_pstk % 2) iw_pstk = iw_pstk + 1;
    em(I_LDR, REG_S1, REG_FP, 16 + iw_pstk * 8);
    em(I_STR, REG_S1, REG_FRAME, 0 - off);
    em(I_LDR, REG_S1, REG_FP, 16 + iw_pstk * 8 + 8);
    em(I_STR, REG_S1, REG_FRAME, 0 - off + 8);
    iw_pstk = iw_pstk + 2;
}

void wi_call(i64 d, i64 na, i64 sym) {
    i64 wide = 0;
    i64 i = 0;
    loop {
        if (i >= na) break;
        if (iw_is(walk_depth_type(d + i))) wide = 1;
        i = i + 1;
    }
    if (!wide && !iw_is(walk_ret_type())) { callp(iw_of(MTASK_CALL), d, na, sym); return; }
    save_live(d);
    i64 ngrn = 0;
    i = 0;
    loop {
        if (i >= na) break;
        if (iw_is(walk_depth_type(d + i))) {
            if (ngrn % 2) ngrn = ngrn + 1;
            if (ngrn + 1 >= REG_ARGS) die("i128/u128: too many arguments for the register pairs");
            iw_half(d + i, IW_LO, ngrn);
            iw_half(d + i, IW_HI, ngrn + 1);
            ngrn = ngrn + 2;
        } else {
            if (ngrn >= REG_ARGS) die("i128/u128: too many arguments");
            arg_to_reg(ngrn, d + i);
            ngrn = ngrn + 1;
        }
        i = i + 1;
    }
    ins_add(I_BL, 0, 0, 0, 0, 0, sym);
    restore_live(d);
    if (iw_is(walk_ret_type())) {                 // x0:x1 back into the depth's slot
        iw_put(d, IW_LO, 0);
        iw_put(d, IW_HI, 1);
        return;
    }
    i64 rd = dst_reg(d);
    e2(I_MOV, rd, 0);
    dst_done(d, rd);
}

void wi_ret(i64 d) {
    if (!iw_is(walk_depth_type(d))) { callp(iw_of(MTASK_RET), d); return; }
    iw_half(d, IW_LO, 0);
    iw_half(d, IW_HI, 1);
}

void wi_cast(i64 ty, i64 d) {
    i64 src = walk_depth_type(d);
    if (!iw_is(src) && !iw_is(ty)) { callp(iw_of(MTASK_CAST), ty, d); return; }
    if (src == ty) return;
    if (iw_is(src) && iw_is(ty)) return;          // i128 <-> u128: same bits
    if (iw_is(src)) {                             // wide -> integer: the low half
        i64 rd = dst_reg(d);
        em(I_LDR, rd, REG_FRAME, 0 - iw_depth(d));
        gen_cast(rd, ty);
        dst_done(d, rd);
        return;
    }
    i64 r = val_reg(d, REG_S1);                   // integer -> wide
    iw_put(d, IW_LO, r);
    // A signed source (i64, i32, or a taught i8/i16) sign-extends into the
    // high half; anything else (u8..u64, uptr) zero-extends. C sign-extends a
    // signed source regardless of the wide target's signedness, so (u128) of a
    // negative i32 is all-ones up top too. A narrow value already arrives
    // sign/zero-extended to 64 bits, so r's bit 63 is the sign to replicate.
    if (type_signed(src)) e2(WI_ASR63, REG_S2, r);
    else                  ei(I_MOVZ, REG_S2, 0, 0);
    iw_put(d, IW_HI, REG_S2);
}

// ---- arm64 encoding, sizing and the dump ----
uptr wi_cond_name(i64 c) {
    if (c == WC_HS) return "hs";
    if (c == WC_LO) return "lo";
    return "??";
}

i64 wi_ins_size(uptr e) {
    if (ins_op(e) >= WI_BASE) return 4;
    return callp(iw_of(MTASK_INS_SIZE), e);
}

i64 wi_reloc_kind(uptr e) {
    if (ins_op(e) >= WI_BASE) return 0 - 1;
    return callp(iw_of(MTASK_RELOC_KIND), e);
}

void wi_encode(uptr e, i64 pc, uptr lab, uptr b) {
    if (ins_op(e) < WI_BASE) { callp(iw_of(MTASK_ENCODE), e, pc, lab, b); return; }
    if (ins_op(e) == WI_CSET) {
        buf_u32(b, 0x9A9F07E0 | (((ins_imm(e) ^ 1) & 0xf) << 12) | ins_rd(e));
        return;
    }
    i64 i = ins_op(e) - WI_BASE;
    i64 w = wi_base_at(i);
    if (wi_ops_at(i) == 2) buf_u32(b, w | (ins_rn(e) << 5) | ins_rd(e));
    else if (wi_ops_at(i) == 9) buf_u32(b, w | (ins_rm(e) << 16) | (ins_rn(e) << 5));
    else buf_u32(b, w | (ins_rm(e) << 16) | (ins_rn(e) << 5) | ins_rd(e));
}

void wi_dump(uptr in) {
    if (ins_op(in) < WI_BASE) { callp(iw_of(MTASK_DUMP), in); return; }
    if (ins_op(in) == WI_CSET) {
        out_str(1, "  cset x"); out_num(1, ins_rd(in));
        out_str(1, ", "); out_str(1, wi_cond_name(ins_imm(in)));
        out_str(1, "\n");
        return;
    }
    i64 i = ins_op(in) - WI_BASE;
    out_str(1, "  ");
    out_str(1, wi_name_at(i));
    out_str(1, " ");
    if (wi_ops_at(i) == 9) {
        out_str(1, "xzr, x"); out_num(1, ins_rn(in));
        out_str(1, ", x");    out_num(1, ins_rm(in));
        out_str(1, "\n");
        return;
    }
    out_str(1, "x"); out_num(1, ins_rd(in));
    out_str(1, ", x"); out_num(1, ins_rn(in));
    if (wi_ops_at(i) == 2) { out_str(1, ", #63\n"); return; }
    out_str(1, ", x"); out_num(1, ins_rm(in));
    out_str(1, "\n");
}

// ============================================================================
// The x86-64 machines: x86_64 (SysV) and x86_64-win (Win64).
// ============================================================================
// One set of functions, two tables, exactly as machine_x86_64_float.mc produces
// two float machines. The arithmetic (add/adc, sub/sbb, mul, the compare, the
// 16-byte copy, the literal) is shared; the DIVERGENCE is the ABI:
//
//   SysV    a 16-byte value in two consecutive integer argument registers
//           (rdi:rsi, rdx:rcx, r8:r9...), or in memory if two do not remain;
//           returned in rax:rdx.
//   Win64   a value larger than 8 bytes is passed BY REFERENCE: the caller
//           allocates a copy and passes a pointer in the ordinary integer
//           argument slot; a wide RETURN is a hidden pointer as the first
//           argument, and the callee returns that pointer in rax.
//
// The register partition is the bundled machine's: rax/rcx/rdx scratch,
// r8..r11 the depths, [rbp - off] for locals.
#define XW_BASE   100
#define XW_ADC    100                 // adc rd, rn      REX.W 11 /r
#define XW_SBB    101                 // sbb rd, rn      REX.W 19 /r
#define XW_MUL    102                 // mul rd          REX.W f7 /4  (rdx:rax = rax*rd)
#define XW_SETCC  103                 // setcc rd        0f 9x /0

// x86 condition nibbles (setcc cc): the unsigned pair the core dump has no name
// for, plus the signed/equal ones this compare uses.
// XC_E (4) and XC_NE (5) are the core x86 machine's; these are the four the
// core has no name for.
#define XC_B  2                       // below     (unsigned <)
#define XC_AE 3                       // above-eq  (unsigned >=)
#define XC_L  12                      // signed <
#define XC_GE 13                      // signed >=

uptr xw_tab;
uptr xw_orig;
uptr xw_tab_win;
uptr xw_orig_win;
uptr xw_cur = 0;                      // whichever pristine copy is in force
u8   xw_tmp[BUF_SIZE];

i64  xw_win = 0;                      // 1 for the Win64 machine
i64  xw_retwide = 0;                  // the current function returns wide (Win64)
i64  xw_retptr = 0;                   // frame slot holding the hidden return ptr
i64  xw_ngrn = 0;                     // integer-register arguments used
i64  xw_pstk = 0;                     // 8-byte stack units used (callee side)
i64  xw_stmp = 0;                     // a 16-byte scratch slot (mul low / cmp eq)
i64  xw_ctmp[16];                     // caller temps: [0] return buffer, [i+1] arg i copy

uptr xw_of(i64 task) { return ld64(xw_cur + task * 8); }

i64 xw_stmp_off() { if (xw_stmp == 0) xw_stmp = slot_new(16); return xw_stmp; }
i64 xw_ctmp_off(i64 i) {
    if (ld64(xw_ctmp + i * 8) == 0) st64(xw_ctmp + i * 8, slot_new(16));
    return ld64(xw_ctmp + i * 8);
}

// the two halves of a wide depth, addressed off rbp
void xw_ld(i64 reg, i64 d, i64 half)  { em(X_LD64, reg, XR_RBP, 0 - iw_depth(d) + half); }
void xw_st(i64 reg, i64 d, i64 half)  { em(X_ST64, reg, XR_RBP, 0 - iw_depth(d) + half); }

void xw_copy(i64 dst_off, i64 dst_base, i64 src_off, i64 src_base) {
    em(X_LD64, XR_RAX, src_base, src_off);
    em(X_ST64, XR_RAX, dst_base, dst_off);
    em(X_LD64, XR_RAX, src_base, src_off + 8);
    em(X_ST64, XR_RAX, dst_base, dst_off + 8);
}

void xw_lo(i64 d, i64 na) {
    i64 rd = x86_dst_reg(d);
    xw_ld(rd, d, IW_LO);
    x86_dst_done(d, rd);
}

void xw_hi(i64 d, i64 na) {
    i64 rd = x86_dst_reg(d);
    xw_ld(rd, d, IW_HI);
    x86_dst_done(d, rd);
}

void xw_pro_common() {
    i64 i = 0;
    loop { if (i >= MAXDEPTH) break; set_iw_slot_at(i, 0); i = i + 1; }
    i = 0;
    loop { if (i >= 16) break; st64(xw_ctmp + i * 8, 0); i = i + 1; }
    xw_stmp = 0;
    xw_ngrn = 0;
    xw_pstk = 0;
    xw_retptr = 0;
    xw_retwide = iw_is(walk_fn_ret);
    iwh_lo = &xw_lo;
    iwh_hi = &xw_hi;
}

void xw_prologue_sysv() {
    xw_win = 0;
    xw_cur = xw_orig;
    xw_pro_common();
    callp(ld64(xw_orig + MTASK_PROLOGUE * 8));     // the bundled x86_prologue
}

void xw_prologue_win() {
    xw_win = 1;
    xw_cur = xw_orig_win;
    xw_pro_common();
    callp(ld64(xw_orig_win + MTASK_PROLOGUE * 8));  // the bundled x86_prologue_win
    if (xw_retwide) {                              // the hidden return pointer is arg 0 (rcx)
        xw_retptr = slot_new(8);
        em(X_ST64, XR_RCX, XR_RBP, 0 - xw_retptr);
        xw_ngrn = 1;
    }
}

// add: lo = lo(d) + lo(d2) (sets CF), hi = hi(d) + hi(d2) + CF. mov does not
// touch CF, so the store of the low result and the loads of the high halves sit
// harmlessly between the add and the adc. sub is the same with sub/sbb.
void xw_addsub(i64 d, i64 d2, i64 second) {
    i64 low = X_ADD;
    if (second == XW_SBB) low = X_SUB;
    xw_ld(XR_RAX, d, IW_LO);
    xw_ld(XR_RCX, d2, IW_LO);
    e2(low, XR_RAX, XR_RCX);                       // rax = lo result, CF set
    xw_ld(XR_RDX, d, IW_HI);                        // hi(d) before it is clobbered
    xw_st(XR_RAX, d, IW_LO);                        // commit the low half (rax free)
    xw_ld(XR_RAX, d2, IW_HI);
    e2(second, XR_RDX, XR_RAX);                     // rdx = hi(d) (+/-) hi(d2) (+/-) CF
    xw_st(XR_RDX, d, IW_HI);
}

// (hi:lo) = the low 128 bits of the product. rdx:rax = lo1*lo2 (unsigned mul);
// the running high sum lives in rdx, which the 2-operand imul leaves untouched.
void xw_mul(i64 d, i64 d2) {
    i64 tmp = 0 - xw_stmp_off();
    xw_ld(XR_RAX, d, IW_LO);
    xw_ld(XR_RCX, d2, IW_LO);
    e2(XW_MUL, XR_RCX, 0);                          // rdx:rax = lo1 * lo2
    em(X_ST64, XR_RAX, XR_RBP, tmp);               // the final low half
    xw_ld(XR_RAX, d, IW_LO);
    xw_ld(XR_RCX, d2, IW_HI);
    e2(X_IMUL, XR_RAX, XR_RCX);                     // lo1 * hi2 (low 64), rdx kept
    e2(X_ADD, XR_RDX, XR_RAX);
    xw_ld(XR_RAX, d, IW_HI);
    xw_ld(XR_RCX, d2, IW_LO);
    e2(X_IMUL, XR_RAX, XR_RCX);                     // hi1 * lo2 (low 64)
    e2(X_ADD, XR_RDX, XR_RAX);                      // rdx = final high half
    em(X_LD64, XR_RAX, XR_RBP, tmp);
    xw_st(XR_RAX, d, IW_LO);
    xw_st(XR_RDX, d, IW_HI);
}

void xw_bin(i64 op, i64 d, i64 d2) {
    if (!iw_is(walk_depth_type(d))) { callp(xw_of(MTASK_BIN), op, d, d2); return; }
    if (op == MOP_ADD) { xw_addsub(d, d2, XW_ADC); return; }
    if (op == MOP_SUB) { xw_addsub(d, d2, XW_SBB); return; }
    if (op == MOP_MUL) { xw_mul(d, d2); return; }
    die("i128/u128: only + - * are taught (docs/specs/M24.md defers the rest)");
}

// (lo1 ^ lo2) | (hi1 ^ hi2) == 0  is equality; setcc into `reg`, cleared first.
void xw_eq_into(i64 d, i64 d2, i64 reg, i64 cc) {
    xw_ld(XR_RAX, d, IW_LO);
    xw_ld(XR_RCX, d2, IW_LO);
    e2(X_XOR, XR_RAX, XR_RCX);
    xw_ld(XR_RCX, d, IW_HI);
    xw_ld(XR_RDX, d2, IW_HI);
    e2(X_XOR, XR_RCX, XR_RDX);
    e2(X_OR, XR_RAX, XR_RCX);                       // ZF = equal (mov below keeps it)
    ei(X_MOVI, reg, 0, 0);
    ins_add(XW_SETCC, reg, 0, 0, cc, 0, 0);
}

// `mov t, hi1; cmp lo1, lo2; sbb t, hi2` sets CF (unsigned borrow) and SF/OF
// (signed) for the full 128-bit subtraction. setb/setae read CF, setl/setge read
// SF==OF. Z reflects only the high half, so `>`/`<=` fold in a separately
// computed equality, exactly as the arm64 machine does.
void xw_cmp(i64 cond, i64 d, i64 d2) {
    i64 dt = walk_depth_type(d);
    if (!iw_is(dt)) { callp(xw_of(MTASK_CMP), cond, d, d2); return; }
    i64 uns = iw_uns(dt);
    i64 rdst = x86_dst_reg(d);
    if (cond == MCOND_EQ || cond == MCOND_NE) {
        i64 c = XC_E;
        if (cond == MCOND_NE) c = XC_NE;
        xw_eq_into(d, d2, XR_RAX, c);
        x86_mov(rdst, XR_RAX);
        x86_dst_done(d, rdst);
        return;
    }
    i64 need = 0;                                  // 1 = and !eq (gt), 2 = or eq (le)
    i64 eqoff = 0;
    if (cond == MCOND_GT) { xw_eq_into(d, d2, XR_RAX, XC_NE); eqoff = 0 - xw_stmp_off();
                            em(X_ST64, XR_RAX, XR_RBP, eqoff); need = 1; }
    if (cond == MCOND_LE) { xw_eq_into(d, d2, XR_RAX, XC_E);  eqoff = 0 - xw_stmp_off();
                            em(X_ST64, XR_RAX, XR_RBP, eqoff); need = 2; }
    xw_ld(XR_RDX, d, IW_HI);                        // t = hi1
    xw_ld(XR_RAX, d, IW_LO);
    xw_ld(XR_RCX, d2, IW_LO);
    e2(X_CMP, XR_RAX, XR_RCX);                      // CF from lo1 - lo2
    xw_ld(XR_RAX, d2, IW_HI);                       // mov keeps CF
    e2(XW_SBB, XR_RDX, XR_RAX);                     // t = hi1 - hi2 - CF
    i64 base = cond;
    if (cond == MCOND_GT) base = MCOND_GE;
    if (cond == MCOND_LE) base = MCOND_LT;
    i64 cc = XC_GE;
    if (base == MCOND_LT) { if (uns) cc = XC_B;  else cc = XC_L; }
    else                  { if (uns) cc = XC_AE; else cc = XC_GE; }
    ei(X_MOVI, XR_RAX, 0, 0);                       // mov keeps the sbb flags
    ins_add(XW_SETCC, XR_RAX, 0, 0, cc, 0, 0);
    if (need == 1) { em(X_LD64, XR_RCX, XR_RBP, eqoff); e2(X_AND, XR_RAX, XR_RCX); }
    if (need == 2) { em(X_LD64, XR_RCX, XR_RBP, eqoff); e2(X_OR, XR_RAX, XR_RCX); }
    x86_mov(rdst, XR_RAX);
    x86_dst_done(d, rdst);
}

void xw_cast(i64 ty, i64 d) {
    i64 src = walk_depth_type(d);
    if (!iw_is(src) && !iw_is(ty)) { callp(xw_of(MTASK_CAST), ty, d); return; }
    if (src == ty) return;
    if (iw_is(src) && iw_is(ty)) return;           // i128 <-> u128: same bits
    if (iw_is(src)) {                              // wide -> integer: the low half, narrowed
        i64 rd = x86_dst_reg(d);
        xw_ld(rd, d, IW_LO);
        i64 w = type_width(ty);
        i64 sgn = type_signed(ty);
        if (w == 4)      { if (sgn) e2(X_MOVSXD, rd, rd); else e2(X_MOV32, rd, rd); }
        else if (w == 2) { if (sgn) e2(X_MOVSXW, rd, rd); else e2(X_MOVZXW, rd, rd); }
        else if (w == 1) { if (sgn) e2(X_MOVSXB, rd, rd); else e2(X_MOVZXB, rd, rd); }
        x86_dst_done(d, rd);
        return;
    }
    i64 r = x86_val_reg(d, XR_RAX);                 // integer -> wide
    x86_mov(XR_RAX, r);
    // A signed source (i64, i32, or a taught i8/i16) sign-extends into the high
    // half; anything else zero-extends. C sign-extends a signed source whatever
    // the wide target's signedness. A narrow value already arrives extended to
    // 64 bits, so cqo replicates rax's bit 63 across rdx.
    if (type_signed(src)) e0(X_CQO);                // sign into rdx:rax
    else                  ei(X_MOVI, XR_RDX, 0, 0); // zero rdx
    xw_st(XR_RAX, d, IW_LO);
    xw_st(XR_RDX, d, IW_HI);
}

void xw_local_load(i64 ty, i64 d, i64 off) {
    if (!iw_is(ty)) { callp(xw_of(MTASK_LOCAL_LOAD), ty, d, off); return; }
    xw_copy(0 - iw_depth(d), XR_RBP, 0 - off, XR_RBP);
}

void xw_local_store(i64 ty, i64 d, i64 off) {
    if (!iw_is(ty)) { callp(xw_of(MTASK_LOCAL_STORE), ty, d, off); return; }
    xw_copy(0 - off, XR_RBP, 0 - iw_depth(d), XR_RBP);
}

void xw_global_load(i64 ty, i64 d, i64 sym) {
    if (!iw_is(ty)) { callp(xw_of(MTASK_GLOBAL_LOAD), ty, d, sym); return; }
    ins_add(X_LEARIP, XR_RCX, 0, 0, 0, 0, sym);
    xw_copy(0 - iw_depth(d), XR_RBP, 0, XR_RCX);
}

void xw_global_store(i64 ty, i64 d, i64 sym) {
    if (!iw_is(ty)) { callp(xw_of(MTASK_GLOBAL_STORE), ty, d, sym); return; }
    ins_add(X_LEARIP, XR_RCX, 0, 0, 0, 0, sym);
    xw_copy(0, XR_RCX, 0 - iw_depth(d), XR_RBP);
}

// a scalar argument's value, read from its frame slot (the caller spills it first)
void xw_arg_scalar_to(i64 reg, i64 d) { em(X_LD64, reg, XR_RBP, 0 - x86_slot_depth(d)); }

// ---- the parameter side ----
void xw_param(i64 ty, i64 i, i64 off) {
    i64 nreg = x86_nargreg;
    if (xw_win) {
        i64 slot = xw_ngrn;                        // one slot per argument on Win64
        xw_ngrn = xw_ngrn + 1;
        if (iw_is(ty)) {                           // a pointer to a copy: copy it in
            if (slot < nreg) {
                xw_copy(0 - off, XR_RBP, 0, x86_argreg_at(slot));
            } else {
                em(X_LD64, XR_RAX, XR_RBP, 16 + x86_shadow + (slot - nreg) * 8);
                xw_copy(0 - off, XR_RBP, 0, XR_RAX);
            }
            return;
        }
        if (slot < nreg) { em(x86_mem_op(ty, 1), x86_argreg_at(slot), XR_RBP, 0 - off); return; }
        em(X_LD64, XR_RAX, XR_RBP, 16 + x86_shadow + (slot - nreg) * 8);
        em(x86_mem_op(ty, 1), XR_RAX, XR_RBP, 0 - off);
        return;
    }
    // SysV
    if (iw_is(ty)) {
        if (xw_ngrn + 2 <= nreg) {
            em(X_ST64, x86_argreg_at(xw_ngrn), XR_RBP, 0 - off);
            em(X_ST64, x86_argreg_at(xw_ngrn + 1), XR_RBP, 0 - off + 8);
            xw_ngrn = xw_ngrn + 2;
            return;
        }
        if (xw_pstk % 2) xw_pstk = xw_pstk + 1;    // 16-byte aligned on the stack
        em(X_LD64, XR_RAX, XR_RBP, 16 + xw_pstk * 8);
        em(X_ST64, XR_RAX, XR_RBP, 0 - off);
        em(X_LD64, XR_RAX, XR_RBP, 16 + (xw_pstk + 1) * 8);
        em(X_ST64, XR_RAX, XR_RBP, 0 - off + 8);
        xw_pstk = xw_pstk + 2;
        return;
    }
    if (xw_ngrn < nreg) {
        em(x86_mem_op(ty, 1), x86_argreg_at(xw_ngrn), XR_RBP, 0 - off);
        xw_ngrn = xw_ngrn + 1;
        return;
    }
    em(X_LD64, XR_RAX, XR_RBP, 16 + xw_pstk * 8);
    em(x86_mem_op(ty, 1), XR_RAX, XR_RBP, 0 - off);
    xw_pstk = xw_pstk + 1;
}

// ---- the caller side ----
// SysV counts each wide argument as two integer registers (both must remain, or
// the whole value goes to memory and the registers stay for a later argument);
// Win64 counts each argument as one slot, a wide one being a pointer to a copy.
i64 xw_stack_units(i64 d, i64 na, i64 retw) {
    i64 nreg = x86_nargreg;
    i64 ngrn = 0;
    if (xw_win && retw) ngrn = 1;
    i64 nstk = 0;
    i64 i = 0;
    loop {
        if (i >= na) break;
        i64 wide = iw_is(walk_depth_type(d + i));
        if (!xw_win && wide) {
            if (ngrn + 2 <= nreg) ngrn = ngrn + 2;
            else { if (nstk % 2) nstk = nstk + 1; nstk = nstk + 2; }
        } else {
            if (ngrn < nreg) ngrn = ngrn + 1;
            else nstk = nstk + 1;
        }
        i = i + 1;
    }
    return nstk;
}

void xw_call(i64 d, i64 na, i64 sym) {
    x86_save_live(d);
    i64 i = 0;
    loop {                                         // spill scalar argument depths
        if (i >= na) break;
        i64 ad = d + i;
        if (!iw_is(walk_depth_type(ad)) && x86_in_reg(ad))
            em(X_ST64, XREG_BASE + ad, XR_RBP, 0 - x86_slot_depth(ad));
        i = i + 1;
    }
    i64 retw = iw_is(walk_ret_type());
    i64 retbuf = 0;
    if (xw_win && retw) retbuf = xw_ctmp_off(0);
    i64 nreg = x86_nargreg;
    i64 nstk = xw_stack_units(d, na, retw);
    i64 back = nstk * 8;
    if (nstk % 2) back = back + 8;                 // 16-byte aligned at the call
    back = back + x86_shadow;
    if (back) ei(X_SPSUB, 0, 0, back);
    i64 ngrn = 0;
    if (xw_win && retw) {                          // the hidden return pointer, arg 0
        em(X_LEA, x86_argreg_at(0), XR_RBP, 0 - retbuf);
        ngrn = 1;
    }
    i64 stk = 0;
    i = 0;
    loop {
        if (i >= na) break;
        i64 ad = d + i;
        i64 wide = iw_is(walk_depth_type(ad));
        if (xw_win) {
            if (wide) {
                i64 tmp = xw_ctmp_off(i + 1);      // a copy the callee owns
                xw_copy(0 - tmp, XR_RBP, 0 - iw_depth(ad), XR_RBP);
                if (ngrn < nreg) { em(X_LEA, x86_argreg_at(ngrn), XR_RBP, 0 - tmp); ngrn = ngrn + 1; }
                else { em(X_LEA, XR_RAX, XR_RBP, 0 - tmp);
                       em(X_ST64, XR_RAX, XR_RSP, x86_shadow + stk * 8); stk = stk + 1; }
            } else {
                if (ngrn < nreg) { xw_arg_scalar_to(x86_argreg_at(ngrn), ad); ngrn = ngrn + 1; }
                else { xw_arg_scalar_to(XR_RAX, ad);
                       em(X_ST64, XR_RAX, XR_RSP, x86_shadow + stk * 8); stk = stk + 1; }
            }
        } else {
            if (wide) {
                if (ngrn + 2 <= nreg) {
                    xw_ld(x86_argreg_at(ngrn), ad, IW_LO);
                    xw_ld(x86_argreg_at(ngrn + 1), ad, IW_HI);
                    ngrn = ngrn + 2;
                } else {
                    if (stk % 2) stk = stk + 1;
                    xw_ld(XR_RAX, ad, IW_LO);
                    em(X_ST64, XR_RAX, XR_RSP, stk * 8);
                    xw_ld(XR_RAX, ad, IW_HI);
                    em(X_ST64, XR_RAX, XR_RSP, (stk + 1) * 8);
                    stk = stk + 2;
                }
            } else {
                if (ngrn < nreg) { xw_arg_scalar_to(x86_argreg_at(ngrn), ad); ngrn = ngrn + 1; }
                else { xw_arg_scalar_to(XR_RAX, ad);
                       em(X_ST64, XR_RAX, XR_RSP, stk * 8); stk = stk + 1; }
            }
        }
        i = i + 1;
    }
    ins_add(X_CALL, 0, 0, 0, 0, 0, sym);
    if (back) ei(X_SPADD, 0, 0, back);
    if (retw) {
        if (xw_win) xw_copy(0 - iw_depth(d), XR_RBP, 0, XR_RAX);   // rax = &return buffer
        else { xw_st(XR_RAX, d, IW_LO); xw_st(XR_RDX, d, IW_HI); }
    } else {
        i64 rd = x86_dst_reg(d);
        x86_mov(rd, XR_RAX);
        x86_dst_done(d, rd);
    }
    x86_restore_live(d);
}

void xw_ret(i64 d) {
    if (!iw_is(walk_depth_type(d))) { callp(xw_of(MTASK_RET), d); return; }
    if (xw_win) {                                  // write through the hidden pointer
        em(X_LD64, XR_RAX, XR_RBP, 0 - xw_retptr);
        em(X_LD64, XR_RCX, XR_RBP, 0 - iw_depth(d));
        em(X_ST64, XR_RCX, XR_RAX, 0);
        em(X_LD64, XR_RCX, XR_RBP, 0 - iw_depth(d) + 8);
        em(X_ST64, XR_RCX, XR_RAX, 8);
        return;                                    // rax already holds the pointer
    }
    xw_ld(XR_RAX, d, IW_LO);                        // SysV: rax:rdx
    xw_ld(XR_RDX, d, IW_HI);
}

// ---- x86 encoding, sizing and the dump ----
void xw_put(uptr e, i64 pc, uptr lab, uptr o) {
    i64 op = ins_op(e);
    if (op < XW_BASE) { callp(xw_of(MTASK_ENCODE), e, pc, lab, o); return; }
    i64 rd = ins_rd(e);
    i64 rn = ins_rn(e);
    i64 im = ins_imm(e);
    if (op == XW_ADC || op == XW_SBB) {            // REX.W 11|19 /r, rm = rd, reg = rn
        i64 opc = 0x11;
        if (op == XW_SBB) opc = 0x19;
        x86_rex(o, 1, rn, rd, 0);
        x86_op(o, opc);
        x86_modrm_rr(o, rn, rd);
        return;
    }
    if (op == XW_MUL) {                            // REX.W f7 /4
        x86_rex(o, 1, 0, rd, 0);
        x86_op(o, 0xf7);
        x86_modrm_rr(o, 4, rd);
        return;
    }
    if (op == XW_SETCC) {                          // 0f 9x /0
        i64 force = 0;                             // REX only for spl/bpl/sil/dil
        if (rd >= 4 && rd < 8) force = 1;          // (rd is always a scratch here)
        x86_rex(o, 0, 0, rd, force);
        x86_op(o, 0x190 + im);
        x86_modrm_rr(o, 0, rd);
        return;
    }
    die("i128/u128 x86: no encoder for a wide opcode");
}

i64 xw_ins_size(uptr e) {
    if (ins_op(e) < XW_BASE) return callp(xw_of(MTASK_INS_SIZE), e);
    set_buf_len(xw_tmp, 0);
    xw_put(e, 0, 0, xw_tmp);
    return buf_len(xw_tmp);
}

i64 xw_reloc_kind(uptr e) {
    if (ins_op(e) >= XW_BASE) return 0 - 1;
    return callp(xw_of(MTASK_RELOC_KIND), e);
}

uptr xw_cond_name(i64 c) {
    if (c == XC_B)  return "b";
    if (c == XC_AE) return "ae";
    if (c == XC_E)  return "e";
    if (c == XC_NE) return "ne";
    if (c == XC_L)  return "l";
    if (c == XC_GE) return "ge";
    return "??";
}

void xw_dump(uptr in) {
    i64 op = ins_op(in);
    if (op < XW_BASE) { callp(xw_of(MTASK_DUMP), in); return; }
    i64 rd = ins_rd(in);
    i64 rn = ins_rn(in);
    i64 im = ins_imm(in);
    if (op == XW_ADC) { out_str(1, "  adc "); xd_reg(rd); out_str(1, ", "); xd_reg(rn);
                        out_str(1, "\n"); return; }
    if (op == XW_SBB) { out_str(1, "  sbb "); xd_reg(rd); out_str(1, ", "); xd_reg(rn);
                        out_str(1, "\n"); return; }
    if (op == XW_MUL) { out_str(1, "  mul "); xd_reg(rd); out_str(1, "\n"); return; }
    if (op == XW_SETCC) { out_str(1, "  set"); out_str(1, xw_cond_name(im));
                          out_str(1, " "); xd_reg(rd); out_str(1, "\n"); return; }
    die("i128/u128 x86: no dump for a wide opcode");
}

// ============================================================================
// Registration.
// ============================================================================
void iw_fill_arm64() {
    iw_tab  = xalloc(MTASK_COUNT * 8);
    iw_orig = xalloc(MTASK_COUNT * 8);
    uptr src = machine_tab("arm64");
    i64 t = 0;
    loop {
        if (t >= MTASK_COUNT) break;
        st64(iw_tab  + t * 8, ld64(src + t * 8));
        st64(iw_orig + t * 8, ld64(src + t * 8));
        t = t + 1;
    }
    machine_slot(iw_tab, MTASK_PROLOGUE,     &wi_prologue);
    machine_slot(iw_tab, MTASK_PARAM,        &wi_param);
    machine_slot(iw_tab, MTASK_PARAM_REG,    &wi_param_reg);
    machine_slot(iw_tab, MTASK_BIN,          &wi_bin);
    machine_slot(iw_tab, MTASK_CMP,          &wi_cmp);
    machine_slot(iw_tab, MTASK_CAST,         &wi_cast);
    machine_slot(iw_tab, MTASK_LOCAL_LOAD,   &wi_local_load);
    machine_slot(iw_tab, MTASK_LOCAL_STORE,  &wi_local_store);
    machine_slot(iw_tab, MTASK_GLOBAL_LOAD,  &wi_global_load);
    machine_slot(iw_tab, MTASK_GLOBAL_STORE, &wi_global_store);
    machine_slot(iw_tab, MTASK_CALL,         &wi_call);
    machine_slot(iw_tab, MTASK_RET,          &wi_ret);
    machine_slot(iw_tab, MTASK_INS_SIZE,     &wi_ins_size);
    machine_slot(iw_tab, MTASK_ENCODE,       &wi_encode);
    machine_slot(iw_tab, MTASK_DUMP,         &wi_dump);
    machine_slot(iw_tab, MTASK_RELOC_KIND,   &wi_reloc_kind);
    machine("arm64", iw_tab);
}

void xw_fill(uptr tab, uptr orig, uptr src, uptr prologue) {
    i64 t = 0;
    loop {
        if (t >= MTASK_COUNT) break;
        st64(tab  + t * 8, ld64(src + t * 8));
        st64(orig + t * 8, ld64(src + t * 8));
        t = t + 1;
    }
    machine_slot(tab, MTASK_PROLOGUE,     prologue);
    machine_slot(tab, MTASK_PARAM,        &xw_param);
    machine_slot(tab, MTASK_BIN,          &xw_bin);
    machine_slot(tab, MTASK_CMP,          &xw_cmp);
    machine_slot(tab, MTASK_CAST,         &xw_cast);
    machine_slot(tab, MTASK_LOCAL_LOAD,   &xw_local_load);
    machine_slot(tab, MTASK_LOCAL_STORE,  &xw_local_store);
    machine_slot(tab, MTASK_GLOBAL_LOAD,  &xw_global_load);
    machine_slot(tab, MTASK_GLOBAL_STORE, &xw_global_store);
    machine_slot(tab, MTASK_CALL,         &xw_call);
    machine_slot(tab, MTASK_RET,          &xw_ret);
    machine_slot(tab, MTASK_INS_SIZE,     &xw_ins_size);
    machine_slot(tab, MTASK_ENCODE,       &xw_put);
    machine_slot(tab, MTASK_DUMP,         &xw_dump);
    machine_slot(tab, MTASK_RELOC_KIND,   &xw_reloc_kind);
}

void iw_fill_x86() {
    xw_tab      = xalloc(MTASK_COUNT * 8);
    xw_orig     = xalloc(MTASK_COUNT * 8);
    xw_tab_win  = xalloc(MTASK_COUNT * 8);
    xw_orig_win = xalloc(MTASK_COUNT * 8);
    xw_fill(xw_tab, xw_orig, machine_tab("x86_64"), &xw_prologue_sysv);
    xw_fill(xw_tab_win, xw_orig_win, machine_tab("x86_64-win"), &xw_prologue_win);
    xw_cur = xw_orig;
    machine("x86_64", xw_tab);
    machine("x86_64-win", xw_tab_win);
}

// idempotent: `<i128>` and `<u128>` both call this, and a taught compiler that
// registers both must not register the types twice
void i128_init() {
    if (ty_i128) return;
    ty_i128 = type_new("i128", 16, 16, TK_WIDE);
    ty_u128 = type_new("u128", 16, 16, TK_WIDE);
    syntax_lit(&iw_lit);
    intrinsic("i128_lo", 1, TY_U64, &iw_i_lo);
    intrinsic("i128_hi", 1, TY_U64, &iw_i_hi);
    intrinsic("u128_lo", 1, TY_U64, &iw_i_lo);
    intrinsic("u128_hi", 1, TY_U64, &iw_i_hi);
    iw_fill_arm64();
    iw_fill_x86();
}
