// f16.mc — half precision taught to `mc` from outside the compiler.
//
// The third generality proof of M24, and the one that is almost free: it needs
// no core line that `<float>` did not already need, and the only thing it adds
// to `<float>`'s machine is what the hardware itself adds -- two `fcvt`s and a
// 16-bit load and store.
//
//   type_new("f16", 2, 2, TK_FLOAT)     where the hardware converts
//   type_new("f16", 2, 2, TK_INT)       where it does not
//
// The WIDTH is what does the work, and it is the same either way: it drives
// glob_place (a global array of eight occupies sixteen bytes), the array-bounds
// arithmetic, and -- through M5 -- a two-byte frame slot.
//
// f16 is a STORAGE type here, deliberately: AArch64 can add two halves directly
// (FEAT_FP16), most targets cannot, and a module that promised `h1 + h2`
// everywhere would be promising a CPU-feature model this compiler does not have
// and should not grow. Arithmetic goes through f32:
//
//   f32 s = f16_to_f32(h);   ...;   h = f32_to_f16(s);
//
// ---- the two roads, and why the KIND is one of the differences ----
//
// This module drives ONE machine: the `arm64` table `<float>` registered. There,
// a half lives in a v register beside every other float, `MTASK_LOCAL_LOAD` and
// `MTASK_GLOBAL_LOAD` already carry `ty` so `ldr h` / `str h` need no task of
// their own, and the four names are `intrinsic` registrations of one instruction
// each. TK_FLOAT is what tells `<float>`'s machine to treat the depth as a float
// -- it is a claim about the MACHINE, and it is only true where this module has
// one.
//
// Anywhere else -- x86-64 in either ABI, and every target a module has not
// taught -- there is no half-precision instruction to name, so:
//
//   * the type is registered TK_INT, which is what a half with no arithmetic
//     unit IS: two bytes of storage the CORE moves, with no float machine
//     involved and no 8-byte `movsd` over a 2-byte global;
//   * nothing is registered on the machine and NO intrinsic is registered;
//   * the module pushes the four identically-named ordinary functions as a
//     second source (`p_push_source`, the `sd_rt` pattern of
//     lib/user_syntax_demo.mc) -- which is what docs/specs/M24.md § Generality
//     asks for: "where it does not, the same registration lowers to a call into
//     a softfloat routine the module pushes as a second source". It is pushed
//     rather than left to the program as a `<f16_rt>` include (the shape
//     lib/float_rt.mc has) because a program cannot include a file on one target
//     and not on another, and the fallback only compiles where f16 is TK_INT.
//
// The same source compiles either way, which is the promise. What the program
// pays on the fallback road is four small functions in every object, and one
// name it may not define itself.
//
// The target, not the host, decides -- a taught compiler cross-compiles, and
// `machine_use` runs AFTER user_init (src/cli.mc), so the machine in effect here
// is always the host's. `[target].arch` is what `mc build` has already read by
// the time user_init runs (M39.5); with no [target] the host answers for itself.
// The one road that is neither -- `--machine=x86_64` or `--backend=coff-obj-x86_64`
// on an aarch64 host, where the flag is read after this decision -- is refused
// by the bundled machine itself: `opcode 303 is not x86-64's: no machine claims
// it` (docs/reference/machine.md § 3).
//
// Depends on <float> being loaded first: f32 is where a half goes to be
// arithmetic, and ldf32/stf32 are the fallback's own bit bridge.

i64 ty_f16 = 0;

// The arm64 band 300..399 (docs/reference/machine.md § 3 is the registry). It
// was 160, which is INSIDE <float>'s 100..199 -- harmless only because the four
// slots below were already bounded at both ends, which is now the rule for every
// derived machine and not this module's private caution.
#define HI_BASE    300
#define HI_CVT_SH  300                // fcvt s, h
#define HI_CVT_HS  301                // fcvt h, s
#define HI_LDR_H   302
#define HI_STR_H   303
#define HI_MAXOP   304                // one past the last: the band ends here

u32 hi_base[] = { 0x1EE24000, 0x1E23C000, 0x7D400000, 0x7D000000 };
uptr hi_name[] = { "fcvt", "fcvt", "ldr", "str" };
i64  hi_mem[]  = { 0, 0, 1, 1 };

i64  hi_base_at(i64 i) { return ld32(hi_base + i * 4); }
uptr hi_name_at(i64 i) { return ld64(hi_name + i * 8); }
i64  hi_mem_at(i64 i)  { return ld64(hi_mem + i * 8); }

uptr hi_tab;
uptr hi_orig;

uptr hi_of(i64 task) { return ld64(hi_orig + task * 8); }

i64 hi_is(i64 t) { return t == ty_f16; }

void hi_local_load(i64 ty, i64 d, i64 off) {
    if (!hi_is(ty)) { callp(hi_of(MTASK_LOCAL_LOAD), ty, d, off); return; }
    i64 rd = fa_dst_reg(d);
    em(HI_LDR_H, rd, REG_FRAME, 0 - off);
    fa_dst_done(d, rd);
}

void hi_local_store(i64 ty, i64 d, i64 off) {
    if (!hi_is(ty)) { callp(hi_of(MTASK_LOCAL_STORE), ty, d, off); return; }
    em(HI_STR_H, fa_val_reg(d, FREG_S1), REG_FRAME, 0 - off);
}

void hi_global_load(i64 ty, i64 d, i64 sym) {
    if (!hi_is(ty)) { callp(hi_of(MTASK_GLOBAL_LOAD), ty, d, sym); return; }
    gen_gaddr(REG_S1, sym);
    i64 rd = fa_dst_reg(d);
    em(HI_LDR_H, rd, REG_S1, 0);
    fa_dst_done(d, rd);
}

void hi_global_store(i64 ty, i64 d, i64 sym) {
    if (!hi_is(ty)) { callp(hi_of(MTASK_GLOBAL_STORE), ty, d, sym); return; }
    i64 r = fa_val_reg(d, FREG_S2);
    gen_gaddr(REG_S1, sym);
    em(HI_STR_H, r, REG_S1, 0);
}

// `fcvt s, h` rounds nothing (every half is exactly a single) and `fcvt h, s`
// rounds to NEAREST, TIES TO EVEN -- which is the case tests/f16 pins down.
void hi_to_f32(i64 d, i64 na) {
    i64 r = fa_val_reg(d, FREG_S1);
    i64 rd = fa_dst_reg(d);
    e2(HI_CVT_SH, rd, r);
    fa_dst_done(d, rd);
}

void hi_from_f32(i64 d, i64 na) {
    i64 r = fa_val_reg(d, FREG_S1);
    i64 rd = fa_dst_reg(d);
    e2(HI_CVT_HS, rd, r);
    fa_dst_done(d, rd);
}

// the two accessors, so a half can be read out of and written into memory the
// way <float>'s ldf32/stf32 do
void hi_ldf(i64 d, i64 na) {
    i64 rn = val_reg(d, REG_S1);
    i64 rd = fa_dst_reg(d);
    em(HI_LDR_H, rd, rn, 0);
    fa_dst_done(d, rd);
}

void hi_stf(i64 d, i64 na) {
    i64 rn = val_reg(d, REG_S1);
    i64 rv = fa_val_reg(d + 1, FREG_S1);
    em(HI_STR_H, rv, rn, 0);
}

// The only test of the band, so the four slots cannot disagree about it.
i64 hi_mine(i64 op) { return op >= HI_BASE && op < HI_MAXOP; }

i64 hi_ins_size(uptr e) {
    if (hi_mine(ins_op(e))) return 4;
    return callp(hi_of(MTASK_INS_SIZE), e);
}

i64 hi_reloc_kind(uptr e) {
    if (hi_mine(ins_op(e))) return 0 - 1;
    return callp(hi_of(MTASK_RELOC_KIND), e);
}

void hi_encode(uptr e, i64 pc, uptr lab, uptr b) {
    i64 op = ins_op(e);
    if (!hi_mine(op)) { callp(hi_of(MTASK_ENCODE), e, pc, lab, b); return; }
    i64 i = op - HI_BASE;
    i64 w = hi_base_at(i);
    if (hi_mem_at(i)) {
        if (ins_imm(e) < 0 || ins_imm(e) % 2 != 0 || ins_imm(e) / 2 > 4095)
            die("f16 memory offset out of range");
        buf_u32(b, w | ((ins_imm(e) / 2) << 10) | (ins_rn(e) << 5) | ins_rd(e));
        return;
    }
    buf_u32(b, w | (ins_rn(e) << 5) | ins_rd(e));
}

void hi_dump(uptr in) {
    i64 op = ins_op(in);
    if (!hi_mine(op)) { callp(hi_of(MTASK_DUMP), in); return; }
    i64 i = op - HI_BASE;
    out_str(1, "  ");
    out_str(1, hi_name_at(i));
    out_str(1, " ");
    if (hi_mem_at(i)) {
        out_str(1, "h"); out_num(1, ins_rd(in));
        out_str(1, ", [");
        fa_dreg(FR_X, ins_rn(in));               // prints `sp` for x31, as the core does
        if (ins_imm(in)) { out_str(1, ", #"); out_num(1, ins_imm(in)); }
        out_str(1, "]\n");
        return;
    }
    if (i == 0) { out_str(1, "s"); out_num(1, ins_rd(in)); out_str(1, ", h"); }
    else        { out_str(1, "h"); out_num(1, ins_rd(in)); out_str(1, ", s"); }
    out_num(1, ins_rn(in));
    out_str(1, "\n");
}

// ---------------------------------------------------------------------------
// The softfloat fallback, for a target this module has no machine for. Pushed
// as a second source at user_init; f16 is TK_INT there, so every line below is
// ordinary integer arithmetic over the core plus <float>'s ldf32/stf32, which
// are the only bit bridge between an f32 depth and its four bytes.
//
// f32 -> f16 rounds to NEAREST, TIES TO EVEN, which is what `fcvt h, s` does and
// what tests/wide/031-f16.mc pins down: 1 + 2^-11 is exactly halfway between the
// halves 0x3c00 and 0x3c01 and must come out 0x3c00, the EVEN one. Subnormals,
// overflow to infinity and NaN are in too, because a conversion that is right on
// three numbers and wrong on the fourth is worse than none.
#define HI_RTLINES 66

uptr hi_rt[] = {
    "f16 f32_to_f16(f32 s) {\n",
    "    u64 r[1];\n",
    "    st64(r, 0);\n",
    "    stf32(r, s);\n",
    "    u64 b = ld32(r);\n",
    "    u64 sign = (b >> 16) & 0x8000;\n",
    "    u64 m = b & 0x7fffff;\n",
    "    i64 x = (b >> 23) & 0xff;\n",
    "    if (x == 255) {\n",
    "        if (m != 0) return sign | 0x7e00 | ((m >> 13) & 0x1ff);\n",
    "        return sign | 0x7c00;\n",
    "    }\n",
    "    i64 e = x - 112;\n",
    "    if (e >= 31) return sign | 0x7c00;\n",
    "    u64 q = 0;\n",
    "    u64 rem = 0;\n",
    "    u64 hb = 0;\n",
    "    if (e <= 0) {\n",
    "        if (e < -10) return sign;\n",
    "        m = m | 0x800000;\n",
    "        i64 sh = 14 - e;\n",
    "        q = m >> sh;\n",
    "        hb = 1 << (sh - 1);\n",
    "        rem = m & ((hb << 1) - 1);\n",
    "    } else {\n",
    "        q = (e << 10) | (m >> 13);\n",
    "        hb = 0x1000;\n",
    "        rem = m & 0x1fff;\n",
    "    }\n",
    "    if (rem > hb) q = q + 1;\n",
    "    if (rem == hb) { if ((q & 1) != 0) q = q + 1; }\n",
    "    return sign | q;\n",
    "}\n",
    "f32 f16_to_f32(f16 h) {\n",
    "    u64 v = h;\n",
    "    u64 sign = (v & 0x8000) << 16;\n",
    "    i64 e = (v >> 10) & 0x1f;\n",
    "    u64 m = v & 0x3ff;\n",
    "    u64 b = 0;\n",
    "    if (e == 31) {\n",
    "        b = sign | 0x7f800000 | (m << 13);\n",
    "        if (m != 0) b = b | 0x400000;\n",
    "    } else {\n",
    "        if (e != 0) {\n",
    "            b = sign | ((e + 112) << 23) | (m << 13);\n",
    "        } else {\n",
    "            if (m != 0) {\n",
    "                i64 sh = 0;\n",
    "                loop {\n",
    "                    if ((m & 0x400) != 0) break;\n",
    "                    m = m << 1;\n",
    "                    sh = sh + 1;\n",
    "                }\n",
    "                b = sign | ((113 - sh) << 23) | ((m & 0x3ff) << 13);\n",
    "            } else {\n",
    "                b = sign;\n",
    "            }\n",
    "        }\n",
    "    }\n",
    "    u64 r[1];\n",
    "    st64(r, 0);\n",
    "    st32(r, b);\n",
    "    return ldf32(r);\n",
    "}\n",
    "f16 ldf16(uptr p) { return ld16(p); }\n",
    "void stf16(uptr p, f16 h) { st16(p, h); }\n"
};

uptr hi_rt_at(i64 i) { return ld64(hi_rt + i * 8); }

uptr hi_rt_text() {
    uptr s = "";
    i64 i = 0;
    loop {
        if (i >= HI_RTLINES) break;
        s = tm_cat(s, hi_rt_at(i));
        i = i + 1;
    }
    return s;
}

// Does this build target the one machine <f16> drives? `mc build` has already
// read [target] by the time user_init runs (M39.5); with no [target] the host
// answers for itself.
i64 hi_hardware() {
    uptr a = drv_arch();
    if (a == 0) a = host_arch();
    return str_eq(a, "aarch64");
}

// Registered on top of whatever machine is named `arm64` at this point -- which,
// with <float> loaded first, is <float>'s. Composition is by DERIVATION and it
// is ordered: risk 4 of docs/specs/M24.md says machine registration is
// last-wins, so a module that stacks on another one copies it rather than the
// bundled table, and says which one it needs.
void f16_init() {
    if (!hi_hardware()) {                         // no half-precision instruction here
        ty_f16 = type_new("f16", 2, 2, TK_INT);   // a half is two bytes of storage
        uptr rt = hi_rt_text();                   // ...and the four names are functions
        p_push_source("f16 runtime", rt, cstrlen(rt));
        return;
    }
    ty_f16 = type_new("f16", 2, 2, TK_FLOAT);
    hi_tab  = xalloc(MTASK_COUNT * 8);
    hi_orig = xalloc(MTASK_COUNT * 8);
    uptr src = machine_tab("arm64");
    i64 t = 0;
    loop {
        if (t >= MTASK_COUNT) break;
        st64(hi_tab  + t * 8, ld64(src + t * 8));
        st64(hi_orig + t * 8, ld64(src + t * 8));
        t = t + 1;
    }
    machine_slot(hi_tab, MTASK_LOCAL_LOAD,   &hi_local_load);
    machine_slot(hi_tab, MTASK_LOCAL_STORE,  &hi_local_store);
    machine_slot(hi_tab, MTASK_GLOBAL_LOAD,  &hi_global_load);
    machine_slot(hi_tab, MTASK_GLOBAL_STORE, &hi_global_store);
    machine_slot(hi_tab, MTASK_INS_SIZE,     &hi_ins_size);
    machine_slot(hi_tab, MTASK_ENCODE,       &hi_encode);
    machine_slot(hi_tab, MTASK_DUMP,         &hi_dump);
    machine_slot(hi_tab, MTASK_RELOC_KIND,   &hi_reloc_kind);
    machine("arm64", hi_tab);
    intrinsic("f16_to_f32", 1, ty_f32, &hi_to_f32);
    intrinsic("f32_to_f16", 1, ty_f16, &hi_from_f32);
    intrinsic("ldf16", 1, ty_f16, &hi_ldf);
    intrinsic("stf16", 2, TY_VOID, &hi_stf);
}
