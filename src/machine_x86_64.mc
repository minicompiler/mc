// machine_x86_64.mc — the x86-64 machine, M17 step B (System V) and M20 (Win64).
// The task list, the register table and the verification are all in
// docs/reference/machine.md § The x86-64 implementation; what is here is the
// code, with only the reasons that are not obvious from it.
//
// It registers TWO machines, `x86_64` and `x86_64-win`, out of one set of
// functions: the calling convention lives in five places (the argument table,
// x86_param, x86_push_args, x86_reg_args and how much x86_call gives back) and
// nowhere else, so the Win64 table is the SysV table with MTASK_PROLOGUE
// replaced by the one that names the other ABI.
//
// It fills the same thirty-one slots src/machine_arm64.mc fills, so
// src/gen_walk.mc never learns a second instruction set. Four things differ
// from AArch64 and each one is marked below:
//
//   * depths 0..3 in r8..r11 and the rest spilled — those four are what is left
//     once the callee-saved half (rbx, r12..r15) and the argument registers are
//     off the table, for the same reason arm64 never writes x18..x28;
//   * three scratch registers, rax/rcx/rdx, because `idiv` writes rdx, `div`
//     needs it zeroed, and every shift takes its count in cl;
//   * locals at [rbp - off], correct from the first instruction, so
//     MTASK_FRAME_FIX only patches the prologue's `sub rsp`;
//   * one to ten bytes per instruction. x86_put is the ONE encoder: it writes
//     into the section buffer, and MTASK_INS_SIZE runs the same function over a
//     scratch buffer and returns the length. Size and encoding cannot disagree.
//
// Depends on gen_walk.mc (the Ins buffer, ins_add/e0/e2/ei/el/em, slot_new, the
// MTASK_/MOP_/MUN_/MCOND_ vocabulary and MAXDEPTH), on arena.mc (buf_*,
// out_str, out_num, die) and on macho.mc (sym_name, sym_at).

// ---- registers, by their x86 encoding number ----
#define XR_RAX 0
#define XR_RCX 1
#define XR_RDX 2
#define XR_RBX 3
#define XR_RSP 4
#define XR_RBP 5
#define XR_RSI 6
#define XR_RDI 7

#define XREG_BASE 8                   // depths 0..3 in r8..r11
#define XREG_MAX  3
#define XREG_S1   XR_RAX              // spill scratch: left / destination
#define XREG_S2   XR_RCX              // spill scratch: right, and the shift count
#define XREG_TMP  XR_RDX              // the remainder of idiv/div

#define XC_E   4                      // condition codes: the low nibble of setcc/jcc
#define XC_NE  5
// Contract version 6, the unsigned orderings: b(2) ae(3) be(6) a(7). x86
// condition codes come in negation pairs on the low bit of tttn, so `cc ^ 1`
// inverts these exactly as it inverts e/ne, l/ge and le/g.
#define XC_B   2
#define XC_AE  3
#define XC_BE  6
#define XC_A   7

// M49 (contract version 5): the five registers the System V AND the Win64 ABI
// both leave to the callee -- rbx, r12, r13, r14, r15. rdi and rsi are
// callee-saved on Win64 and argument registers 1 and 2 on System V, so a count
// that depended on which prologue last ran would be stale for the first function
// of a unit; two registers are not worth a second code path (D11).
#define XREG_NALLOC 5

// The relocation kinds this machine produces, R_X86_PC32 and R_X86_PLT32, are
// in src/objmodel.mc with the others since M41: the machine emits them and
// src/backend_elf.mc maps them, and those two are different parts
// (<mc/core_machines> and <mc/core_writers>).

// ---- opcodes. 0 is I_LABEL and belongs to the walker, so these start at 1.
// The numbers overlap machine_arm64.mc's I_* on purpose: only one machine ever
// encodes an Ins buffer, and the two vocabularies never meet. ----
#define X_NOP      1                  // erased by the frame fixup, no bytes
#define X_PUSH     2                  // push rd
#define X_PUSHM    3                  // push [rn + imm]
#define X_LEAVE    4
#define X_RET      5
#define X_MOV      6                  // mov rd, rn             (64 bits)
#define X_MOV32    7                  // mov rd, rn             (32 bits, zero-extends)
#define X_MOVI     8                  // mov rd, imm
#define X_LEA      9                  // lea rd, [rn + imm]
#define X_LEARIP  10                  // lea rd, [rip + 0]      + reloc(sym)
#define X_ADD     11
#define X_SUB     12
#define X_AND     13
#define X_OR      14
#define X_XOR     15
#define X_IMUL    16
#define X_CQO     17                  // sign-extend rax into rdx:rax
#define X_ZEDX    18                  // xor edx, edx
#define X_IDIV    19                  // idiv rd
#define X_DIV     20                  // div rd
#define X_SHL     21                  // shl rd, cl
#define X_SHR     22
#define X_SAR     23
#define X_NEG     24
#define X_NOT     25
#define X_CMP     26                  // cmp rd, rn
#define X_TEST    27                  // test rd, rn
#define X_SETCC   28                  // setcc rd, imm = condition
#define X_MOVZXB  29                  // movzx rd, rn (byte)
#define X_MOVZXW  30                  // movzx rd, rn (word)
#define X_JMP     31
#define X_JCC     32                  // jcc label, imm = condition
#define X_CALL    33                  // call rel32             + reloc(sym)
#define X_CALLR   34                  // call rd
#define X_LD8     35
#define X_LD16    36
#define X_LD32    37
#define X_LD64    38
#define X_ST8     39
#define X_ST16    40
#define X_ST32    41
#define X_ST64    42
#define X_SPADD   43                  // add rsp, imm
#define X_SPSUB   44                  // sub rsp, imm
#define X_EMIT    45                  // one raw 32-bit word, little-endian
// M45: the signed halves. movsx/movsxd into a 64-bit register, in both the
// register and the memory form -- the sign-extending twin of movzx/mov r32.
#define X_LDS8    46                  // movsx r64, byte [m]
#define X_LDS16   47                  // movsx r64, word [m]
#define X_LDS32   48                  // movsxd r64, dword [m]
#define X_MOVSXB  49                  // movsx rd, rn (byte)
#define X_MOVSXW  50                  // movsx rd, rn (word)
#define X_MOVSXD  51                  // movsxd rd, rn (dword)
// M49 step E (P5): the ALU with an immediate operand -- 83 /d ib or 81 /d id --
// and the three shifts by a constant, C1 /d ib. `rd op= imm`, two-operand as
// every x86 ALU form is; X_CMPI writes nothing but the flags.
#define X_ADDI    52
#define X_SUBI    53
#define X_ANDI    54
#define X_ORI     55
#define X_XORI    56
#define X_CMPI    57
#define X_SHLI    58
#define X_SHRI    59
#define X_SARI    60
#define X_COUNT   61

// ---- how an opcode is encoded: the form decides which of five shapes, the
// other five columns fill it in. Everything not in a shape is XF_SPEC and has
// its own branch in x86_put. ----
#define XF_SPEC 0
#define XF_FIX  1                     // fixed bytes: opc, `dig` of them
#define XF_RS   2                     // opc /r, reg = rn (the source), rm = rd
#define XF_RD   3                     // opc /r, reg = rd, rm = rn
#define XF_RG   4                     // opc /r, reg = the `dig` extension, rm = rd
#define XF_LD   5                     // opc /r, reg = rd, memory [rn + imm]
#define XF_ST   6                     // the same bytes as XF_LD; only the dump differs
#define XF_MG   7                     // opc /r, reg = `dig`, memory [rn + imm]
#define XF_RI   8                     // step E: 83 /dig ib or 81 /dig id, rm = rd
#define XF_SI   9                     // step E: C1 /dig ib, rm = rd

#define XD_N 6                        // columns per opcode: form w opc dig pre rex

//                 form     w  opc     dig pre   rex
i64 x86_desc[] = {
    XF_SPEC,       0, 0,      0, 0,    0,        // 0  I_LABEL
    XF_SPEC,       0, 0,      0, 0,    0,        // 1  nop
    XF_SPEC,       0, 0,      0, 0,    0,        // 2  push r
    XF_MG,         0, 0xff,   6, 0,    0,        // 3  push [m]
    XF_FIX,        0, 0xc9,   1, 0,    0,        // 4  leave
    XF_FIX,        0, 0xc3,   1, 0,    0,        // 5  ret
    XF_RS,         1, 0x89,   0, 0,    0,        // 6  mov r, r
    XF_RS,         0, 0x89,   0, 0,    0,        // 7  mov rd, rd (32 bits)
    XF_SPEC,       0, 0,      0, 0,    0,        // 8  mov r, imm
    XF_LD,         1, 0x8d,   0, 0,    0,        // 9  lea
    XF_SPEC,       0, 0,      0, 0,    0,        // 10 lea [rip]
    XF_RS,         1, 0x01,   0, 0,    0,        // 11 add
    XF_RS,         1, 0x29,   0, 0,    0,        // 12 sub
    XF_RS,         1, 0x21,   0, 0,    0,        // 13 and
    XF_RS,         1, 0x09,   0, 0,    0,        // 14 or
    XF_RS,         1, 0x31,   0, 0,    0,        // 15 xor
    XF_RD,         1, 0x1af,  0, 0,    0,        // 16 imul
    XF_FIX,        0, 0x4899, 2, 0,    0,        // 17 cqo
    XF_FIX,        0, 0x31d2, 2, 0,    0,        // 18 xor edx, edx
    XF_RG,         1, 0xf7,   7, 0,    0,        // 19 idiv
    XF_RG,         1, 0xf7,   6, 0,    0,        // 20 div
    XF_RG,         1, 0xd3,   4, 0,    0,        // 21 shl by cl
    XF_RG,         1, 0xd3,   5, 0,    0,        // 22 shr by cl
    XF_RG,         1, 0xd3,   7, 0,    0,        // 23 sar by cl
    XF_RG,         1, 0xf7,   3, 0,    0,        // 24 neg
    XF_RG,         1, 0xf7,   2, 0,    0,        // 25 not
    XF_RS,         1, 0x39,   0, 0,    0,        // 26 cmp
    XF_RS,         1, 0x85,   0, 0,    0,        // 27 test
    XF_SPEC,       0, 0,      0, 0,    0,        // 28 setcc
    XF_RD,         1, 0x1b6,  0, 0,    0,        // 29 movzx r, r8
    XF_RD,         1, 0x1b7,  0, 0,    0,        // 30 movzx r, r16
    XF_SPEC,       0, 0,      0, 0,    0,        // 31 jmp
    XF_SPEC,       0, 0,      0, 0,    0,        // 32 jcc
    XF_SPEC,       0, 0,      0, 0,    0,        // 33 call rel32
    XF_RG,         0, 0xff,   2, 0,    0,        // 34 call r
    XF_LD,         1, 0x1b6,  0, 0,    0,        // 35 movzx r, byte [m]
    XF_LD,         1, 0x1b7,  0, 0,    0,        // 36 movzx r, word [m]
    XF_LD,         0, 0x8b,   0, 0,    0,        // 37 mov r32, [m]
    XF_LD,         1, 0x8b,   0, 0,    0,        // 38 mov r64, [m]
    XF_ST,         0, 0x88,   0, 0,    1,        // 39 mov [m], r8  (REX forced: sil/dil)
    XF_ST,         0, 0x89,   0, 0x66, 0,        // 40 mov [m], r16
    XF_ST,         0, 0x89,   0, 0,    0,        // 41 mov [m], r32
    XF_ST,         1, 0x89,   0, 0,    0,        // 42 mov [m], r64
    XF_SPEC,       0, 0,      0, 0,    0,        // 43 add rsp, imm
    XF_SPEC,       0, 0,      0, 0,    0,        // 44 sub rsp, imm
    XF_SPEC,       0, 0,      0, 0,    0,        // 45 raw word
    XF_LD,         1, 0x1be,  0, 0,    0,        // 46 movsx r64, byte [m]
    XF_LD,         1, 0x1bf,  0, 0,    0,        // 47 movsx r64, word [m]
    XF_LD,         1, 0x63,   0, 0,    0,        // 48 movsxd r64, dword [m]
    XF_RD,         1, 0x1be,  0, 0,    0,        // 49 movsx r64, r8
    XF_RD,         1, 0x1bf,  0, 0,    0,        // 50 movsx r64, r16
    XF_RD,         1, 0x63,   0, 0,    0,        // 51 movsxd r64, r32
    XF_RI,         1, 0x81,   0, 0,    0,        // 52 add r, imm
    XF_RI,         1, 0x81,   5, 0,    0,        // 53 sub r, imm
    XF_RI,         1, 0x81,   4, 0,    0,        // 54 and r, imm
    XF_RI,         1, 0x81,   1, 0,    0,        // 55 or r, imm
    XF_RI,         1, 0x81,   6, 0,    0,        // 56 xor r, imm
    XF_RI,         1, 0x81,   7, 0,    0,        // 57 cmp r, imm
    XF_SI,         1, 0xc1,   4, 0,    0,        // 58 shl r, imm8
    XF_SI,         1, 0xc1,   5, 0,    0,        // 59 shr r, imm8
    XF_SI,         1, 0xc1,   7, 0,    0         // 60 sar r, imm8
};

uptr x86_name[] = { "", "nop", "push", "push", "leave", "ret", "mov", "mov32",
    "mov", "lea", "lea", "add", "sub", "and", "or", "xor", "imul", "cqo",
    "xor32", "idiv", "div", "shl", "shr", "sar", "neg", "not", "cmp", "test",
    "set", "movzxb", "movzxw", "jmp", "j", "call", "call", "movzxb", "movzxw",
    "mov32", "mov", "mov8", "mov16", "mov32", "mov", "add", "sub", ".word",
    "movsxb", "movsxw", "movsxd", "movsxb", "movsxw", "movsxd",
    "add", "sub", "and", "or", "xor", "cmp", "shl", "shr", "sar" };

uptr m_x86_64[MTASK_COUNT];           // the task table the walker drives
uptr m_x86_64_win[MTASK_COUNT];       // the same thirty-one entries, Win64 prologue
u8   x86_tmp[BUF_SIZE];               // scratch the size task encodes into
// M49: TWO per-depth vectors in ONE array, as src/machine_arm64.mc does it and
// for the same reason (the frozen seed's MAXGLOBALS is the tight row of
// scripts/check-limits.sh): [0, MAXDEPTH) is the frame slot of a depth and
// [MAXDEPTH, 2*MAXDEPTH) is its ALIAS -- the allocatable register that already
// holds this depth's value, or -1. An alias is set by MTASK_REG_LOAD, which then
// emits nothing at all, and is cleared by every task that produces a new value
// at that depth.
i64  xdslot[MAXDEPTH * 2];            // frame slot of a depth: 0 = not asked for yet
i64  x86_isub = 0;                    // the prologue's `sub rsp, N`, patched last

// M20: the two calling conventions, and the three things that tell them apart.
// The REGISTER PARTITION does not move -- rax, rcx, rdx and r8..r11 are volatile
// in both ABIs, so the depths stay in r8..r11 and the scratch stays rax/rcx/rdx.
// rdi and rsi are callee-saved on Win64 and this machine simply stops naming
// them: they appear only as SysV argument registers 0 and 1.
i64 x86_argreg[] = { XR_RDI, XR_RSI, XR_RDX, XR_RCX, 8, 9 };
i64 x86_argreg_win[] = { XR_RCX, XR_RDX, 8, 9 };

uptr x86_args    = 0;                 // the table in force: set by MTASK_PROLOGUE
i64  x86_nargreg = 0;                 // how many arguments travel in registers
i64  x86_shadow  = 0;                 // bytes the caller reserves below the args

i64 x86_cond[] = { 4, 5, 12, 14, 15, 13,        // MCOND_EQ NE LT LE GT GE, signed
                   2, 6, 7, 3 };               // MCOND_ULT ULE UGT UGE
i64 x86_binop[] = { X_ADD, X_SUB, X_IMUL, 0, 0, 0, 0,   // MOP_*; the four divisions
                    X_AND, X_OR, X_XOR, X_SHL, X_SHR, X_SAR };   // go to x86_divmod
i64 x86_memop[] = { X_LD64, X_ST64, X_LD32, X_ST32, X_LD16, X_ST16, X_LD8, X_ST8,
                    X_LDS32, X_ST32, X_LDS16, X_ST16, X_LDS8, X_ST8 };

i64  x86_argreg_at(i64 i) { return ld64(x86_args + i * 8); }
i64  x86_cond_at(i64 i)   { return ld64(x86_cond + i * 8); }
i64  x86_binop_at(i64 i)  { return ld64(x86_binop + i * 8); }
i64  x86_memop_at(i64 i)  { return ld64(x86_memop + i * 8); }
// A derived machine claims a BAND of the opcode space above X_COUNT and passes
// everything else down to this table (docs/reference/machine.md § 3). Seen from
// here, the rule has a second half: an opcode this machine does not own must be
// REFUSED, not looked up. x86_desc and x86_name are INDEXED by the opcode, so
// every reader of either -- x86_form, the five column reads inside x86_put
// (MTASK_ENCODE and, through the scratch buffer, MTASK_INS_SIZE) and x86_dump --
// used to read past the end of the array for a band nobody claimed. That is what
// <f16>'s HI_* opcodes (300..303) did when an f16 program was compiled for a
// machine <f16> does not drive. The guard sits in the two accessors, which is
// the only place every one of those readers goes through.
void x86_claim(i64 op) {
    if (op >= 0 && op < X_COUNT) return;
    die(tm_cat(tm_cat("opcode ", tm_num_str(op)),
               " is not x86-64's: no machine claims it"));
}
uptr x86_name_at(i64 i)   { x86_claim(i); return ld64(x86_name + i * 8); }
i64  x86_d(i64 op, i64 c) { x86_claim(op); return ld64(x86_desc + (op * XD_N + c) * 8); }
i64  xdslot_at(i64 i)     { return ld64(xdslot + i * 8); }
void set_xdslot_at(i64 i, i64 v) { st64(xdslot + i * 8, v); }
i64  xalias_at(i64 i)     { return ld64(xdslot + (MAXDEPTH + i) * 8); }
void set_xalias_at(i64 i, i64 v) { st64(xdslot + (MAXDEPTH + i) * 8, v); }
// M49: the allocatable register with index r, by its x86 encoding number. The
// set is rbx, r12..r15 -- not contiguous, unlike AArch64's x19..x28, so it takes
// arithmetic rather than a base. A table would read better and would cost one
// more file-level global, which is the frozen seed's tight row.
//
// M49 step E: index XREG_NALLOC + j is scratch register j of a leaf, and it IS
// System V integer argument register j -- rdi, then rsi -- the only volatile
// registers this machine does not already spend on a depth or a scratch.
i64  x86_allocreg_at(i64 r) {
    if (r == 0) return XR_RBX;                   // 3
    if (r == XREG_NALLOC) return XR_RDI;         // 5 -> rdi
    if (r == XREG_NALLOC + 1) return XR_RSI;     // 6 -> rsi
    return r + 11;                               // 1..4 -> r12..r15
}

// M49: every alias forgotten. Called at a LABEL -- a control-flow merge, where a
// value carried in an alias could have arrived by another path -- and after every
// MTASK_REG_STORE, the one place an allocatable register's contents change under
// a live alias. Guarded by walk_opt() so the plain road never even walks the
// array.
void x86_alias_reset() {
    if (walk_opt() == 0) return;
    i64 d = 0;
    loop {
        if (d >= MAXDEPTH) break;
        set_xalias_at(d, 0 - 1);
        d = d + 1;
    }
}

i64 x86_form(i64 op) { return x86_d(op, 0); }

// M45: by WIDTH and, for a load, by KIND -- never by the id. The three signed
// loads sit six slots past their unsigned twin and share the store, which
// truncates and never cares about the sign.
i64 x86_mem_op(i64 t, i64 store) {
    i64 w = type_width(t);
    i64 i = 0;                            // 8 bytes, and any width with no form here
    if (w == 4)      i = 2;
    else if (w == 2) i = 4;
    else if (w == 1) i = 6;
    if (store) return x86_memop_at(i + 1);
    if (i && type_kind(t) == TK_SINT) i = i + 6;
    return x86_memop_at(i);
}

// ---- depth, register and spill ----
i64 x86_slot_depth(i64 d) {
    if (xdslot_at(d) == 0) set_xdslot_at(d, slot_new(8));
    return xdslot_at(d);
}

i64 x86_in_reg(i64 depth) { return depth <= XREG_MAX; }

// the register holding the depth's value; a spilled one is loaded into scratch.
//
// M49: the alias comes first. When MTASK_REG_LOAD has said "depth d IS the value
// of allocatable register r", the value is in r and nowhere else -- no
// instruction was emitted and no frame slot written -- so this is the one
// function that knows where to find it. Contract version 5 makes reading a depth
// through val_reg an OBLIGATION for every machine, derived ones included:
// computing XREG_BASE + d by hand reads a stale r8.
i64 x86_val_reg(i64 depth, i64 scratch) {
    if (xalias_at(depth) >= 0) return xalias_at(depth);
    if (x86_in_reg(depth)) return XREG_BASE + depth;
    em(X_LD64, scratch, XR_RBP, 0 - x86_slot_depth(depth));
    return scratch;
}

i64 x86_dst_reg(i64 depth) {
    if (x86_in_reg(depth)) return XREG_BASE + depth;
    return XREG_S1;
}

// a register the machine may WRITE for depth `d`. x86 is two-operand, so far more
// tasks here than on AArch64 write their own source; an aliased depth is
// materialised out of the local's register first, because the result of `x + 1`,
// of `-x` or of a cast must not land on top of `x` itself.
i64 x86_own(i64 d) {
    if (xalias_at(d) >= 0) {
        i64 rd = x86_dst_reg(d);
        e2(X_MOV, rd, xalias_at(d));
        set_xalias_at(d, 0 - 1);
        return rd;
    }
    return x86_val_reg(d, XREG_S1);
}

void x86_dst_done(i64 depth, i64 rd) {
    // M49: a new value has landed at this depth, so whatever alias it carried is
    // stale. Every value-producing task ends here, which is what makes one line
    // enough.
    set_xalias_at(depth, 0 - 1);
    if (!x86_in_reg(depth)) em(X_ST64, rd, XR_RBP, 0 - x86_slot_depth(depth));
}

// r8..r11 are caller-saved, so the live depths go to the frame around a call
void x86_save_live(i64 depth) {
    i64 d = 0;
    loop {
        if (d >= depth || !x86_in_reg(d)) break;
        // M49: an aliased depth lives in a register the callee preserves, so it
        // needs no frame round trip and its alias survives the call
        if (xalias_at(d) < 0) em(X_ST64, XREG_BASE + d, XR_RBP, 0 - x86_slot_depth(d));
        d = d + 1;
    }
}

void x86_restore_live(i64 depth) {
    i64 d = 0;
    loop {
        if (d >= depth || !x86_in_reg(d)) break;
        if (xalias_at(d) < 0) em(X_LD64, XREG_BASE + d, XR_RBP, 0 - x86_slot_depth(d));
        d = d + 1;
    }
}

void x86_mov(i64 rd, i64 rn) { if (rd != rn) e2(X_MOV, rd, rn); }

// ---- the tasks ----
// The frame record is unconditional (a stack walk depends on it); the reserve is
// a placeholder until x86_frame_fix knows the size.
void x86_prologue_body() {
    i64 d = 0;
    loop {
        if (d >= MAXDEPTH) break;
        set_xdslot_at(d, 0);
        set_xalias_at(d, 0 - 1);                 // M49: nothing aliased yet
        d = d + 1;
    }
    e2(X_PUSH, XR_RBP, 0);
    e2(X_MOV, XR_RBP, XR_RSP);
    x86_isub = nins;
    ei(X_SPSUB, 0, 0, 0);                        // the frame size only at the end
}

// The ABI is named by the prologue, which src/gen_walk.mc's gen_func always runs
// before the first MTASK_PARAM and before any MTASK_CALL, so the three globals
// can never be stale. That is also why the two conventions are two MACHINES and
// not a runtime flag: `--machine=x86_64-win` has to be able to dump the Win64
// sequence, and a flag the backend sets could not.
void x86_prologue() {
    x86_args = x86_argreg;
    x86_nargreg = 6;
    x86_shadow = 0;
    x86_prologue_body();
}

void x86_prologue_win() {
    x86_args = x86_argreg_win;
    x86_nargreg = 4;
    x86_shadow = 32;
    x86_prologue_body();
}

// parameter i goes to its slot without the prologue writing an argument
// register; the ones past the register table were pushed by the caller, above
// rbp -- past the saved rbp and the return address, and on Win64 past the
// 32 bytes of shadow space the caller reserved as well ([rbp+48] for the fifth).
void x86_param(i64 ty, i64 i, i64 off) {
    if (i < x86_nargreg) { em(x86_mem_op(ty, 1), x86_argreg_at(i), XR_RBP, 0 - off); return; }
    em(X_LD64, XR_RAX, XR_RBP, 16 + x86_shadow + (i - x86_nargreg) * 8);
    em(x86_mem_op(ty, 1), XR_RAX, XR_RBP, 0 - off);
}

// `leave` is `mov rsp, rbp; pop rbp`, so the epilogue needs no patching at all
void x86_epilogue() { e0(X_LEAVE); e0(X_RET); }

void x86_frame_fix(i64 frame) {
    set_ins_imm(ins_at(x86_isub), frame);
    if (frame == 0) set_ins_op(ins_at(x86_isub), X_NOP);
}

void x86_const(i64 d, i64 imm) {
    i64 rd = x86_dst_reg(d);
    ins_add(X_MOVI, rd, 0, 0, imm, 0, 0);
    x86_dst_done(d, rd);
}

// rax = rl, extend into rdx, divide, take the quotient or the remainder. rr is
// never rax or rdx: it is a depth register or XREG_S2 (rcx).
void x86_divmod(i64 op, i64 d, i64 d2) {
    i64 rl = x86_val_reg(d, XREG_S1);
    i64 rr = x86_val_reg(d2, XREG_S2);
    x86_mov(XR_RAX, rl);
    if (op == MOP_SDIV || op == MOP_SMOD) { e0(X_CQO); e2(X_IDIV, rr, 0); }
    else                                  { e0(X_ZEDX); e2(X_DIV, rr, 0); }
    i64 src = XR_RAX;
    if (op == MOP_SMOD || op == MOP_UMOD) src = XREG_TMP;
    i64 rd = x86_dst_reg(d);
    x86_mov(rd, src);
    x86_dst_done(d, rd);
}

// ---- M49 step E: the emission-time folds P5 and P6, arm64's in x86's shape ----
// P5: the value one `mov r, imm` just wrote into depth d's own register, when it
// fits a sign-extended imm32; 1 in *ok. The only instruction that can be last and
// write a depth's register is the one that produced the depth's value -- an
// aliased depth emitted nothing.
i64 x86_lone_const(i64 d, uptr ok) {
    st64(ok, 0);
    if (walk_opt() == 0 || xalias_at(d) >= 0 || !x86_in_reg(d) || nins <= ins_base) return 0;
    uptr e = ins_at(nins - 1);
    if (ins_op(e) != X_MOVI || ins_rd(e) != XREG_BASE + d) return 0;
    i64 v = ins_imm(e);
    if (v < 0 - 0x80000000 || v >= 0x80000000) return 0;
    st64(ok, 1);
    return v;
}

// the immediate form of `op`, or 0: every ALU op but the multiply and the four
// divisions, and a shift by 0..63
i64 x86_imm_op(i64 op, i64 k) {
    if (op == MOP_ADD) return X_ADDI;
    if (op == MOP_SUB) return X_SUBI;
    if (op == MOP_AND) return X_ANDI;
    if (op == MOP_OR)  return X_ORI;
    if (op == MOP_XOR) return X_XORI;
    if (k < 0 || k > 63) return 0;
    if (op == MOP_SHL) return X_SHLI;
    if (op == MOP_SHR) return X_SHRI;
    if (op == MOP_SAR) return X_SARI;
    return 0;
}

// x86 is two-operand: the destination is also the left operand, which is what
// dst_reg and val_reg of the SAME depth already return.
void x86_bin(i64 op, i64 d, i64 d2) {
    if (op == MOP_SDIV || op == MOP_UDIV || op == MOP_SMOD || op == MOP_UMOD) {
        x86_divmod(op, d, d2);
        return;
    }
    i64 ok[1];
    i64 k = x86_lone_const(d2, ok);
    i64 iop = 0;
    if (ld64(ok)) iop = x86_imm_op(op, k);
    if (iop) {                                   // P5: the mov is consumed
        set_ins_op(ins_at(nins - 1), X_NOP);
        i64 rt = x86_own(d);
        ei(iop, rt, 0, k);
        x86_dst_done(d, rt);
        return;
    }
    i64 rd = x86_own(d);                         // two-operand: the dest is the left
    i64 rr = x86_val_reg(d2, XREG_S2);
    if (op == MOP_SHL || op == MOP_SHR || op == MOP_SAR) {
        x86_mov(XR_RCX, rr);                     // the count only comes from cl
        e2(x86_binop_at(op), rd, 0);
    } else {
        e2(x86_binop_at(op), rd, rr);
    }
    x86_dst_done(d, rd);
}

void x86_cmp(i64 cond, i64 d, i64 d2) {
    if (cond < 0 || cond >= 10) die("unknown condition");   // a code past this contract
    i64 ok[1];
    i64 k = x86_lone_const(d2, ok);              // P5: cmp r, imm
    if (ld64(ok)) {
        set_ins_op(ins_at(nins - 1), X_NOP);
        i64 rs = x86_val_reg(d, XREG_S1);
        i64 rt = x86_dst_reg(d);
        ei(X_CMPI, rs, 0, k);
        ins_add(X_SETCC, rt, 0, 0, x86_cond_at(cond), 0, 0);
        e2(X_MOVZXB, rt, rt);
        x86_dst_done(d, rt);
        return;
    }
    i64 rl = x86_val_reg(d, XREG_S1);
    i64 rr = x86_val_reg(d2, XREG_S2);
    i64 rd = x86_dst_reg(d);
    e2(X_CMP, rl, rr);
    ins_add(X_SETCC, rd, 0, 0, x86_cond_at(cond), 0, 0);
    e2(X_MOVZXB, rd, rd);                        // setcc writes one byte only
    x86_dst_done(d, rd);
}

i64 x86_bool_pair(i64 d);                        // M49: defined below, with P1

void x86_un(i64 op, i64 d) {
    // M49 P2: `setcc rd, cc; movzx rd, rd` then a logical NOT on the same rd is
    // the same pair with the condition flipped. x86 condition codes are defined
    // in negation pairs (the low bit of tttn), so `cc ^ 1` inverts e/ne, l/ge and
    // le/g alike -- the same inversion P1 applies. Guarded by walk_opt() and by
    // adjacency: an I_LABEL between would BE the last instruction and is not an
    // X_MOVZXB.
    if (op == MUN_LNOT && x86_bool_pair(d)) {
        set_ins_imm(ins_at(nins - 2), ins_imm(ins_at(nins - 2)) ^ 1);
        return;                                  // the boolean stays at depth d, inverted
    }
    i64 rd = x86_own(d);                         // operates in place
    if (op == MUN_NEG)      e2(X_NEG, rd, 0);
    else if (op == MUN_NOT) e2(X_NOT, rd, 0);
    else {
        e2(X_TEST, rd, rd);
        ins_add(X_SETCC, rd, 0, 0, XC_E, 0, 0);
        e2(X_MOVZXB, rd, rd);
    }
    x86_dst_done(d, rd);
}

void x86_bool(i64 d) {
    i64 rd = x86_own(d);
    e2(X_TEST, rd, rd);
    ins_add(X_SETCC, rd, 0, 0, XC_NE, 0, 0);
    e2(X_MOVZXB, rd, rd);
    x86_dst_done(d, rd);
}

// M45: fill the bytes above the type's width -- zero for a TK_INT, the sign for
// a TK_SINT -- by width and kind, never by the id
void x86_cast_reg(i64 rd, i64 ty) {
    i64 w = type_width(ty);
    i64 sgn = type_kind(ty) == TK_SINT;
    if (w == 1) {
        if (sgn) e2(X_MOVSXB, rd, rd);
        else     e2(X_MOVZXB, rd, rd);
    }
    else if (w == 2) {
        if (sgn) e2(X_MOVSXW, rd, rd);
        else     e2(X_MOVZXW, rd, rd);
    }
    else if (w == 4) {
        if (sgn) e2(X_MOVSXD, rd, rd);
        else     e2(X_MOV32, rd, rd);            // a 32-bit mov zeroes the top half
    }
}

void x86_cast(i64 ty, i64 d) {
    i64 rd = x86_own(d);                         // in place -- never the local's own register
    x86_cast_reg(rd, ty);
    x86_dst_done(d, rd);
}

// P6: the address at depth d was just produced -- two-operand -- by
// `add rd, rr` or `add rd, imm` into d's own register, `back` instructions from
// the end, optionally preceded by the `mov rd, rs` that x86_own emits for an
// aliased left operand. Folds it into access `op` of register rt: the index form
// [base + index] (a SIB byte, scale 1) for a register sum, [base + k] for a
// constant one. The base is the mov's source when there is one, or rd itself --
// its value before the add, which is still there, since the add is dropped.
// Returns 1 when folded.
//
// `clob` is the register an instruction BETWEEN the add and the access writes
// (a store's constant value, `back` 1), or -1: an add or a mov that READ it is
// left where it is, since moving the read past the write would read the value.
i64 x86_fold_addr(i64 d, i64 back, i64 op, i64 rt, i64 clob) {
    if (walk_opt() == 0 || xalias_at(d) >= 0 || !x86_in_reg(d) || nins - back <= ins_base) return 0;
    uptr a = ins_at(nins - 1 - back);
    i64 rd = XREG_BASE + d;
    i64 aop = ins_op(a);
    if (ins_rd(a) != rd || (aop != X_ADD && aop != X_ADDI)) return 0;
    if (aop == X_ADD && ins_rn(a) == clob) return 0;
    i64 base = rd;
    if (nins - 2 - back >= ins_base) {
        uptr m = ins_at(nins - 2 - back);
        // not for `add rd, rd`: the index IS rd there, and it must keep the mov
        if (ins_op(m) == X_MOV && ins_rd(m) == rd && ins_rn(m) != clob
                && !(aop == X_ADD && ins_rn(a) == rd)) {
            base = ins_rn(m);
            set_ins_op(m, X_NOP);
        }
    }
    set_ins_op(a, X_NOP);
    if (aop == X_ADD) ins_add(op, rt, base, ins_rn(a) + 1, 0, 0, 0);   // rm = index + 1
    else              em(op, rt, base, ins_imm(a));
    return 1;
}

void x86_load(i64 ty, i64 d) {
    i64 rd = x86_dst_reg(d);
    if (x86_fold_addr(d, 0, x86_mem_op(ty, 0), rd, 0 - 1)) { x86_dst_done(d, rd); return; }
    i64 rp = x86_val_reg(d, XREG_S1);
    em(x86_mem_op(ty, 0), rd, rp, 0);            // zero-extended by construction
    x86_dst_done(d, rd);
}

// P6 for a store: the value at d + 1 was produced AFTER the address, so the add
// is last only when the value emitted nothing (an alias), or second to last when
// it is one `mov r, imm`, which reads no register.
void x86_store(i64 ty, i64 d) {
    i64 back = 0 - 1;
    i64 clob = 0 - 1;
    i64 ok[1];
    if (xalias_at(d + 1) >= 0) back = 0;
    else {
        x86_lone_const(d + 1, ok);
        if (ld64(ok)) { back = 1; clob = XREG_BASE + d + 1; }
    }
    if (back >= 0 && x86_fold_addr(d, back, x86_mem_op(ty, 1), x86_val_reg(d + 1, XREG_S2), clob)) return;
    i64 rp = x86_val_reg(d, XREG_S1);
    i64 rv = x86_val_reg(d + 1, XREG_S2);
    em(x86_mem_op(ty, 1), rv, rp, 0);
}

void x86_local_addr(i64 d, i64 off) {
    i64 rd = x86_dst_reg(d);
    em(X_LEA, rd, XR_RBP, 0 - off);
    x86_dst_done(d, rd);
}

void x86_local_load(i64 ty, i64 d, i64 off) {
    i64 rd = x86_dst_reg(d);
    em(x86_mem_op(ty, 0), rd, XR_RBP, 0 - off);
    x86_dst_done(d, rd);
}

void x86_local_store(i64 ty, i64 d, i64 off) {
    i64 rv = x86_val_reg(d, XREG_S2);
    em(x86_mem_op(ty, 1), rv, XR_RBP, 0 - off);
}

// rip-relative: one instruction, one R_X86_64_PC32 three bytes into it
void x86_sym_addr(i64 d, i64 sym) {
    i64 rd = x86_dst_reg(d);
    ins_add(X_LEARIP, rd, 0, 0, 0, 0, sym);
    x86_dst_done(d, rd);
}

void x86_global_load(i64 ty, i64 d, i64 sym) {
    i64 rd = x86_dst_reg(d);
    ins_add(X_LEARIP, rd, 0, 0, 0, 0, sym);
    em(x86_mem_op(ty, 0), rd, rd, 0);
    x86_dst_done(d, rd);
}

// rax is free here: the value is lowered already and nothing else is live in it
void x86_global_store(i64 ty, i64 d, i64 sym) {
    ins_add(X_LEARIP, XREG_S1, 0, 0, 0, 0, sym);
    i64 rv = x86_val_reg(d, XREG_S2);
    em(x86_mem_op(ty, 1), rv, XREG_S1, 0);
}

// M49: one line, through val_reg. For a spilled depth val_reg loads into the
// scratch it was given -- the argument register itself -- which is exactly the
// `em(X_LD64, r, ...)` this used to do by hand, and for an aliased one it answers
// the allocatable register the walker handed out.
void x86_arg_to(i64 r, i64 d) { x86_mov(r, x86_val_reg(d, r)); }

// The arguments past the register table go on the stack, at [rsp], [rsp + 8]...
// when the call happens. `push` takes its operand straight from memory, so no
// scratch register is spent; one extra 8 is reserved when the count is odd,
// because rsp has to be 16-byte aligned at the call. Returns how much to give
// back after.
//
// M20: the Win64 shadow space is the last thing subtracted, so it ends up
// BELOW the pushed arguments and the fifth argument lands at [rsp+32], which is
// where the callee's x86_param reads it from. The alignment rule is unchanged:
// 8*np + 32 is 0 mod 16 exactly when np is even. This is why the function has to
// return non-zero for a Win64 call with no stack arguments at all -- back is 32.
i64 x86_push_args(i64 dbase, i64 na) {
    i64 nr = x86_nargreg;
    i64 np = 0;
    if (na > nr) np = na - nr;
    i64 bytes = 8 * np;
    if (np % 2) { ei(X_SPSUB, 0, 0, 8); bytes = bytes + 8; }
    i64 i = na - 1;
    loop {
        if (i < nr) break;
        i64 d = dbase + i;
        if (xalias_at(d) >= 0)  e2(X_PUSH, xalias_at(d), 0);
        else if (x86_in_reg(d)) e2(X_PUSH, XREG_BASE + d, 0);
        else                    em(X_PUSHM, 0, XR_RBP, 0 - x86_slot_depth(d));
        i = i - 1;
    }
    if (x86_shadow) { ei(X_SPSUB, 0, 0, x86_shadow); bytes = bytes + x86_shadow; }
    return bytes;
}

// The first ones in ABI order. Writing an argument register that is also a depth
// register cannot clobber a source still to be read, because the table is
// written in ASCENDING index and a depth register's own argument index is
// smaller than its position in the table. SysV: argreg[4] is r8 (depth 0), whose
// index is -dbase <= 0 < 4, and argreg[5] is r9 (depth 1), index 1 - dbase <= 1
// < 5. Win64: argreg[2] is r8, index -dbase <= 0 < 2, and argreg[3] is r9,
// index 1 - dbase <= 1 < 3. tests/windows/071-nested-args.mc is the executable
// proof of the Win64 half, where the margin is smallest.
void x86_reg_args(i64 dbase, i64 na) {
    i64 n = na;
    if (n > x86_nargreg) n = x86_nargreg;
    i64 i = 0;
    loop {
        if (i >= n) break;
        x86_arg_to(x86_argreg_at(i), dbase + i);
        i = i + 1;
    }
}

void x86_call(i64 d, i64 na, i64 sym) {
    x86_save_live(d);
    i64 back = x86_push_args(d, na);
    x86_reg_args(d, na);
    ins_add(X_CALL, 0, 0, 0, 0, 0, sym);
    if (back) ei(X_SPADD, 0, 0, back);
    x86_restore_live(d);
    i64 rd = x86_dst_reg(d);
    x86_mov(rd, XR_RAX);
    x86_dst_done(d, rd);
}

// callp(p, a1..a11): the pointer (argument 0) goes to rax, outside the ABI, and
// has to move BEFORE any argument register is written, because it may itself be
// living in r8..r11.
void x86_callp(i64 d, i64 na) {
    x86_save_live(d);
    x86_arg_to(XR_RAX, d);
    i64 back = x86_push_args(d + 1, na - 1);
    x86_reg_args(d + 1, na - 1);
    e2(X_CALLR, XR_RAX, 0);
    if (back) ei(X_SPADD, 0, 0, back);
    x86_restore_live(d);
    i64 rd = x86_dst_reg(d);
    x86_mov(rd, XR_RAX);
    x86_dst_done(d, rd);
}

void x86_ret(i64 d)  { x86_mov(XR_RAX, x86_val_reg(d, XREG_S1)); }
void x86_jump(i64 l) { el(X_JMP, l); }

// M49: 1 when the last two instructions are the `setcc rd, cc; movzx rd, rd`
// pair x86_cmp, x86_bool and x86_un(LNOT) all end in, writing the depth's own
// register. That pair IS the boolean at depth d, and it is the only shape P1 and
// P2 rewrite -- setcc writes one byte, so the movzx is never separable from it.
i64 x86_bool_pair(i64 d) {
    if (walk_opt() == 0 || xalias_at(d) >= 0 || !x86_in_reg(d)) return 0;
    if (nins < ins_base + 2) return 0;
    uptr z = ins_at(nins - 1);
    uptr s = ins_at(nins - 2);
    if (ins_op(z) != X_MOVZXB || ins_rd(z) != XREG_BASE + d || ins_rn(z) != XREG_BASE + d) return 0;
    if (ins_op(s) != X_SETCC  || ins_rd(s) != XREG_BASE + d) return 0;
    return 1;
}

// M49 P1: `cmp; setcc rd, cc; movzx rd, rd` then a branch on that boolean is one
// `jcc`. Drop the pair (X_NOP generates no bytes and no dump line) and branch on
// the flags the cmp left. take_true selects the sense: JNZ (branch when the
// boolean is true) uses cc, JZ (branch when it is false) uses cc ^ 1. The
// boolean's register is dead after a JZ/JNZ at every walker site (gen_if at depth
// 0, gen_logic overwrites the depth on both paths), so no liveness beyond
// adjacency is needed. No instruction FORM is added: x86_jcond has always ended
// in X_JCC, so the peephole only removes.
i64 x86_fuse_branch(i64 d, i64 l, i64 take_true) {
    if (!x86_bool_pair(d)) return 0;
    i64 cc = ins_imm(ins_at(nins - 2));
    if (take_true == 0) cc = cc ^ 1;
    set_ins_op(ins_at(nins - 1), X_NOP);
    set_ins_op(ins_at(nins - 2), X_NOP);
    ins_add(X_JCC, 0, 0, 0, cc, l, 0);
    return 1;
}

void x86_jcond(i64 d, i64 l, i64 cc) {
    i64 rv = x86_val_reg(d, XREG_S1);
    e2(X_TEST, rv, rv);
    ins_add(X_JCC, 0, 0, 0, cc, l, 0);
}

void x86_jz(i64 d, i64 l)  { if (!x86_fuse_branch(d, l, 0)) x86_jcond(d, l, XC_E); }
void x86_jnz(i64 d, i64 l) { if (!x86_fuse_branch(d, l, 1)) x86_jcond(d, l, XC_NE); }
void x86_label(i64 l)      { x86_alias_reset(); el(I_LABEL, l); }

// ---- M49: the six version 5 tasks -----------------------------------------
// rbx, r12..r15 on BOTH ABIs, and the walker names them by index alone.
i64 x86_reg_count() { return XREG_NALLOC; }

// M49 step E, the version 7 slot: rdi and rsi in a leaf, on System V only. On
// Win64 they are callee-saved and every volatile register is already a depth or
// a scratch, so that table leaves the slot null (machine_x86_64_init).
i64 x86_reg_scratch() { return 2; }

// The save area is ordinary frame slots (docs/specs/M49.md § 4.3), so these two
// are mov forms the encoder already has: the allocator adds no instruction form
// to the sweep, the frame record stays unconditional, `leave` still ends the
// function and a stack walker finds everything at a fixed [rbp - k].
void x86_reg_save(i64 r, i64 off)    { em(X_ST64, x86_allocreg_at(r), XR_RBP, 0 - off); }
void x86_reg_restore(i64 r, i64 off) { em(X_LD64, x86_allocreg_at(r), XR_RBP, 0 - off); }

// argument i straight into its register, READING the ABI registers and never
// writing them. The ones past the table were pushed by the caller above rbp --
// past the saved rbp and the return address, and on Win64 past the 32 bytes of
// shadow space as well ([rbp+48] for the fifth), which is x86_param's own rule.
void x86_param_reg(i64 ty, i64 i, i64 r) {
    i64 rd = x86_allocreg_at(r);
    if (i < x86_nargreg) x86_mov(rd, x86_argreg_at(i));
    else                 em(X_LD64, rd, XR_RBP, 16 + x86_shadow + (i - x86_nargreg) * 8);
    x86_cast_reg(rd, ty);                        // the register holds the extended eight bytes
}

// THE LOAD EMITS NOTHING. It records that depth `d` is the value of the
// allocatable register, and x86_val_reg hands that register to whoever reads the
// depth -- which is what turns "locals in registers" into "the ALU reads the
// local directly".
void x86_reg_load(i64 d, i64 r) { set_xalias_at(d, x86_allocreg_at(r)); }

// 1 when instruction `op` WRITES ins_rd and does not READ it.
//
// This set is much smaller than AArch64's, and the reason is the architecture:
// x86 is two-operand, so `add rd, rn` means rd = rd + rn, and retargeting its
// destination at the local's register would add to a register that does not hold
// the old value. add/sub/and/or/xor/imul/shl/shr/sar/neg/not are all out for that
// reason; every store is out because its rd is its SOURCE; setcc is out because
// it writes one byte only; X_CALLR's rd is the call target and X_IDIV/X_DIV's is
// the divisor. What is left is every form that only writes: the three movs, the
// two leas, the five register movzx/movsx and the seven loads -- which is what a
// local's initialiser, a constant, a global read and a comparison's boolean end
// in.
i64 x86_retarget_ok(i64 op) {
    if (op == X_MOVI || op == X_MOV || op == X_MOV32) return 1;
    if (op == X_LEA  || op == X_LEARIP) return 1;
    if (op == X_MOVZXB || op == X_MOVZXW) return 1;
    if (op == X_MOVSXB || op == X_MOVSXW || op == X_MOVSXD) return 1;
    if (op >= X_LD8 && op <= X_LD64) return 1;
    if (op == X_LDS8 || op == X_LDS16 || op == X_LDS32) return 1;
    return 0;
}

// register r = depth d, truncated to the type's width and extended by its kind.
//
// The rewrite: if the instruction just emitted is the one that PRODUCED this
// depth's value and only wrote it, its destination is retargeted at the local's
// register and no `mov` is emitted at all. It is safe because the value at the
// depth is consumed by this store and by nothing else, and because an I_LABEL
// between would BE the last instruction and is not in the whitelist.
// M49 step E (P8): the two-operand half the rewrite below cannot do. `x = x op y`
// lowers as `mov r8, rx; op r8, y` and then comes here; when those are the last
// two instructions the pair is `op rx, y` in place -- the depth register was
// only ever a copy of rx on its way back into it. Not when the operation reads
// the depth register as its SOURCE (`add r8, r8` is x + x, and its r8 is the
// copy), which is what `srcok` rules out.
i64 x86_inplace_ok(uptr e, i64 dr) {
    i64 op = ins_op(e);
    if (op >= X_ADDI && op <= X_XORI) return 1;
    if (op == X_SHLI || op == X_SHRI || op == X_SARI) return 1;
    if (op == X_NEG || op == X_NOT || op == X_SHL || op == X_SHR || op == X_SAR) return 1;
    if (op == X_ADD || op == X_SUB || op == X_AND || op == X_OR || op == X_XOR || op == X_IMUL)
        return ins_rn(e) != dr;
    return 0;
}

void x86_reg_store(i64 ty, i64 d, i64 r) {
    i64 rd = x86_allocreg_at(r);
    i64 done = 0;
    i64 dr = XREG_BASE + d;
    if (walk_opt() && xalias_at(d) < 0 && x86_in_reg(d) && nins - 2 >= ins_base) {
        uptr e = ins_at(nins - 1);
        uptr m = ins_at(nins - 2);
        if (ins_rd(e) == dr && x86_inplace_ok(e, dr) && ins_op(m) == X_MOV
                && ins_rd(m) == dr && ins_rn(m) == rd) {
            set_ins_op(m, X_NOP);
            set_ins_rd(e, rd);
            done = 1;
        }
    }
    if (done == 0 && xalias_at(d) < 0 && x86_in_reg(d) && nins > ins_base) {
        uptr e = ins_at(nins - 1);
        if (x86_retarget_ok(ins_op(e)) && ins_rd(e) == XREG_BASE + d) {
            set_ins_rd(e, rd);
            // `mov rbx, rbx` is what a depth that already read this same local
            // collapses to. Only the 64-bit mov: `mov32 rbx, rbx` TRUNCATES.
            if (ins_op(e) == X_MOV && ins_rn(e) == rd) set_ins_op(e, X_NOP);
            done = 1;
        }
    }
    if (done == 0) x86_mov(rd, x86_val_reg(d, XREG_S1));
    x86_cast_reg(rd, ty);                        // truncate by width, extend by kind
    x86_alias_reset();                           // an allocatable register just changed
}
void x86_word(i64 w)       { ins_add(X_EMIT, 0, 0, 0, w, 0, 0); }

// the two instructions that always carry a relocation of their own, and how far
// into each one the four-byte field sits
i64 x86_reloc_kind(uptr e) {
    i64 op = ins_op(e);
    if (op == X_CALL)   return R_X86_PLT32;
    if (op == X_LEARIP) return R_X86_PC32;
    return -1;
}

i64 x86_reloc_off(uptr e) {
    i64 op = ins_op(e);
    if (op == X_CALL)   return 1;                // E8 | rel32
    if (op == X_LEARIP) return 3;                // REX.W 8D modrm | disp32
    return 0;
}

// ---- the encoder ----
// A REX prefix is needed for a 64-bit operand, for any register above 7, and for
// an 8-bit operand whose register could otherwise read as ah/ch/dh/bh.
void x86_rex(uptr o, i64 w, i64 r, i64 b, i64 force) {
    if (!w && !force && r < 8 && b < 8) return;
    i64 v = 0x40;
    if (w) v = v | 8;
    if (r >= 8) v = v | 4;
    if (b >= 8) v = v | 1;
    buf_u8(o, v);
}

void x86_op(uptr o, i64 op) {                    // > 0xff is a two-byte 0x0F opcode
    if (op > 0xff) buf_u8(o, 0x0f);
    buf_u8(o, op & 0xff);
}

void x86_modrm_rr(uptr o, i64 reg, i64 rm) { buf_u8(o, 0xc0 | ((reg & 7) << 3) | (rm & 7)); }

// M49 step E (P6): [base + index + disp] through a SIB byte, scale 1. The REX
// prefix gains its X bit for an index above 7; an index is never rsp (it is a
// depth, an allocated or a scratch register), and a base whose low bits are 101
// (rbp, r13) takes a zero disp8, because mod 00 would mean "no base".
void x86_rex_x(uptr o, i64 w, i64 r, i64 x, i64 b, i64 force) {
    if (!w && !force && r < 8 && x < 8 && b < 8) return;
    i64 v = 0x40;
    if (w) v = v | 8;
    if (r >= 8) v = v | 4;
    if (x >= 8) v = v | 2;
    if (b >= 8) v = v | 1;
    buf_u8(o, v);
}

void x86_modrm_sib(uptr o, i64 reg, i64 base, i64 ix, i64 disp) {
    i64 mod = 2;
    if (disp == 0 && (base & 7) != 5) mod = 0;
    else if (x86_fits8(disp))         mod = 1;
    buf_u8(o, (mod << 6) | ((reg & 7) << 3) | 4);
    buf_u8(o, ((ix & 7) << 3) | (base & 7));
    if (mod == 1) buf_u8(o, disp & 0xff);
    if (mod == 2) buf_u32(o, disp);
}

i64 x86_fits8(i64 v) { return v >= 0 - 128 && v <= 127; }

// [base] with no displacement byte at all — mod 00. Not available for rbp and
// r13: with mod 00 their slot means [rip + disp32], which is the form X_LEARIP
// uses.
i64 x86_mod0(i64 base, i64 disp) {
    if (disp != 0) return 0;
    if ((base & 7) == 5) return 0;
    return 1;
}

void x86_modrm_m(uptr o, i64 reg, i64 base, i64 disp) {
    i64 mod = 2;
    if (x86_mod0(base, disp))  mod = 0;
    else if (x86_fits8(disp))  mod = 1;
    buf_u8(o, (mod << 6) | ((reg & 7) << 3) | (base & 7));
    if ((base & 7) == 4) buf_u8(o, 0x24);        // SIB: base only, no index
    if (mod == 0) return;
    if (mod == 1) { buf_u8(o, disp & 0xff); return; }
    buf_u32(o, disp);
}

// mov r, imm in three shapes: 32-bit zero-extending, 32-bit sign-extending, full
void x86_put_movi(uptr o, i64 rd, i64 v) {
    if (v >= 0 && v <= 0xffffffff) {             // mov r32, imm32 zero-extends
        x86_rex(o, 0, 0, rd, 0);
        buf_u8(o, 0xb8 + (rd & 7));
        buf_u32(o, v);
        return;
    }
    if (v >= 0 - 0x80000000 && v < 0x80000000) { // mov r/m64, imm32 sign-extends
        x86_rex(o, 1, 0, rd, 0);
        buf_u8(o, 0xc7);
        x86_modrm_rr(o, 0, rd);
        buf_u32(o, v);
        return;
    }
    x86_rex(o, 1, 0, rd, 0);
    buf_u8(o, 0xb8 + (rd & 7));
    buf_u64(o, v);
}

void x86_put_spimm(uptr o, i64 dig, i64 v) {     // add/sub rsp, imm8 or imm32
    x86_rex(o, 1, 0, XR_RSP, 0);
    if (x86_fits8(v)) {
        buf_u8(o, 0x83);
        x86_modrm_rr(o, dig, XR_RSP);
        buf_u8(o, v & 0xff);
        return;
    }
    buf_u8(o, 0x81);
    x86_modrm_rr(o, dig, XR_RSP);
    buf_u32(o, v);
}

// a label's offset, or 0 while measuring: the two branch forms are fixed width,
// so the size does not depend on the answer
i64 x86_target(uptr lab, i64 l) {
    if (lab == 0) return 0;
    return ivec_at(lab, l);
}

// THE encoder. MTASK_ENCODE calls it with the section buffer, MTASK_INS_SIZE
// with a scratch one, so the size the label pass reserves is by construction the
// number of bytes that will be written.
void x86_put(uptr e, i64 pc, uptr lab, uptr o) {
    i64 op = ins_op(e);
    i64 rd = ins_rd(e);
    i64 rn = ins_rn(e);
    i64 im = ins_imm(e);
    i64 f  = x86_form(op);
    if (op == I_LABEL || op == X_NOP) return;
    if (f) {
        i64 w   = x86_d(op, 1);
        i64 opc = x86_d(op, 2);
        i64 dig = x86_d(op, 3);
        i64 pre = x86_d(op, 4);
        i64 rex = x86_d(op, 5);
        if (f == XF_FIX) {                       // `dig` bytes of `opc`, high first
            i64 i = dig;
            loop {
                if (i <= 0) break;
                i = i - 1;
                buf_u8(o, (opc >> (8 * i)) & 0xff);
            }
            return;
        }
        if (f == XF_RI) {                        // step E: 83 /d ib or 81 /d id
            x86_rex(o, 1, 0, rd, 0);
            if (x86_fits8(im)) { buf_u8(o, 0x83); x86_modrm_rr(o, dig, rd); buf_u8(o, im & 0xff); }
            else               { buf_u8(o, 0x81); x86_modrm_rr(o, dig, rd); buf_u32(o, im); }
            return;
        }
        if (f == XF_SI) {                        // step E: C1 /d ib, and D1 /d for a
            x86_rex(o, 1, 0, rd, 0);             // shift by one -- the shorter form every
            if (im == 1) { buf_u8(o, 0xd1); x86_modrm_rr(o, dig, rd); return; }   // assembler picks
            buf_u8(o, opc);
            x86_modrm_rr(o, dig, rd);
            buf_u8(o, im & 0xff);
            return;
        }
        if (pre) buf_u8(o, pre);
        if ((f == XF_LD || f == XF_ST) && ins_rm(e)) {   // step E: rm is index + 1
            x86_rex_x(o, w, rd, ins_rm(e) - 1, rn, rex);
            x86_op(o, opc);
            x86_modrm_sib(o, rd, rn, ins_rm(e) - 1, im);
            return;
        }
        i64 reg = rd;                            // XF_RD, XF_LD, XF_ST
        i64 rm  = rn;
        if (f == XF_RS) { reg = rn; rm = rd; }
        if (f == XF_RG) { reg = dig; rm = rd; }
        if (f == XF_MG) { reg = dig; }
        x86_rex(o, w, reg, rm, rex);
        x86_op(o, opc);
        if (f == XF_RS || f == XF_RD || f == XF_RG) x86_modrm_rr(o, reg, rm);
        else                                        x86_modrm_m(o, reg, rn, im);
        return;
    }
    if (op == X_PUSH)  { x86_rex(o, 0, 0, rd, 0); buf_u8(o, 0x50 + (rd & 7)); return; }
    if (op == X_MOVI)  { x86_put_movi(o, rd, im); return; }
    if (op == X_LEARIP) {                        // mod 00, rm 101 is [rip + disp32]
        x86_rex(o, 1, rd, 0, 0);
        buf_u8(o, 0x8d);
        buf_u8(o, ((rd & 7) << 3) | 5);
        buf_u32(o, 0);                           // the linker fills it in
        return;
    }
    if (op == X_SETCC) { x86_rex(o, 0, 0, rd, 1); x86_op(o, 0x190 + im);
                         x86_modrm_rr(o, 0, rd); return; }
    if (op == X_JMP) {
        buf_u8(o, 0xe9);
        buf_u32(o, x86_target(lab, ins_label(e)) - (pc + 5));
        return;
    }
    if (op == X_JCC) {
        buf_u8(o, 0x0f);
        buf_u8(o, 0x80 + im);
        buf_u32(o, x86_target(lab, ins_label(e)) - (pc + 6));
        return;
    }
    if (op == X_CALL)  { buf_u8(o, 0xe8); buf_u32(o, 0); return; }  // the reloc carries -4
    if (op == X_SPADD) { x86_put_spimm(o, 0, im); return; }
    if (op == X_SPSUB) { x86_put_spimm(o, 5, im); return; }
    if (op == X_EMIT)  { buf_u32(o, im); return; }
    die("x86 instruction with no encoder");
}

// the same encoder over a scratch buffer whose length is reset, not its capacity
i64 x86_ins_size(uptr e) {
    set_buf_len(x86_tmp, 0);
    x86_put(e, 0, 0, x86_tmp);
    return buf_len(x86_tmp);
}

// ---- text dump ----
uptr x86_rname[] = { "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi",
                     "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15" };

uptr x86_rname_at(i64 i) { return ld64(x86_rname + i * 8); }
void xd_reg(i64 r)  { out_str(1, x86_rname_at(r)); }
void xd_head(uptr m) { out_str(1, "  "); out_str(1, m); out_str(1, " "); }

void xd_num(i64 v) {
    if (v < 0) { out_str(1, "-"); out_num(1, 0 - v); return; }
    out_num(1, v);
}

// step E: `ix` is the index register plus one, 0 for none
void xd_memi(i64 base, i64 ix, i64 off) {
    out_str(1, "[");
    xd_reg(base);
    if (ix) { out_str(1, "+"); xd_reg(ix - 1); }
    if (off >= 0) { out_str(1, "+"); out_num(1, off); }
    else          { out_str(1, "-"); out_num(1, 0 - off); }
    out_str(1, "]");
}

void xd_mem(i64 base, i64 off) {
    out_str(1, "[");
    xd_reg(base);
    if (off >= 0) { out_str(1, "+"); out_num(1, off); }
    else          { out_str(1, "-"); out_num(1, 0 - off); }
    out_str(1, "]");
}

uptr xd_cond(i64 c) {
    if (c == 2)  return "b";
    if (c == 3)  return "ae";
    if (c == 4)  return "e";
    if (c == 5)  return "ne";
    if (c == 6)  return "be";
    if (c == 7)  return "a";
    if (c == 12) return "l";
    if (c == 13) return "ge";
    if (c == 14) return "le";
    if (c == 15) return "g";
    return "??";
}

void xd_word(u64 w) {
    u8 c[1];
    out_str(1, "  .word 0x");
    i64 i = 7;
    loop {
        if (i < 0) break;
        st8(c, ld8("0123456789abcdef" + ((w >> (4 * i)) & 15)));
        out_bytes(1, c, 1);
        i = i - 1;
    }
    out_str(1, "\n");
}

// the same descriptor table decides the operand shape here
void x86_dump(uptr in) {
    i64 op = ins_op(in);
    i64 rd = ins_rd(in);
    i64 rn = ins_rn(in);
    i64 im = ins_imm(in);
    i64 f  = x86_form(op);
    uptr m = x86_name_at(op);
    if (op == X_NOP) return;
    if (op == I_LABEL) { out_str(1, "L"); out_num(1, ins_label(in)); out_str(1, ":\n"); return; }
    if (f == XF_FIX) { out_str(1, "  "); out_str(1, m); out_str(1, "\n"); return; }
    if (f == XF_RS || f == XF_RD) { xd_head(m); xd_reg(rd); out_str(1, ", ");
                                    xd_reg(rn); out_str(1, "\n"); return; }
    if (f == XF_RG) { xd_head(m); xd_reg(rd);
                      if (op == X_SHL || op == X_SHR || op == X_SAR) out_str(1, ", cl");
                      out_str(1, "\n"); return; }
    if (f == XF_LD) { xd_head(m); xd_reg(rd); out_str(1, ", "); xd_memi(rn, ins_rm(in), im);
                      out_str(1, "\n"); return; }
    if (f == XF_ST) { xd_head(m); xd_memi(rn, ins_rm(in), im); out_str(1, ", "); xd_reg(rd);
                      out_str(1, "\n"); return; }
    if (f == XF_RI || f == XF_SI) { xd_head(m); xd_reg(rd); out_str(1, ", "); xd_num(im);
                                    out_str(1, "\n"); return; }
    if (f == XF_MG) { xd_head(m); xd_mem(rn, im); out_str(1, "\n"); return; }
    if (op == X_PUSH)   { xd_head(m); xd_reg(rd); out_str(1, "\n"); return; }
    if (op == X_MOVI)   { xd_head(m); xd_reg(rd); out_str(1, ", "); xd_num(im);
                          out_str(1, "\n"); return; }
    if (op == X_LEARIP) { xd_head(m); xd_reg(rd); out_str(1, ", [rip+");
                          out_str(1, sym_name(sym_at(ins_sym(in)))); out_str(1, "]\n"); return; }
    if (op == X_SETCC)  { out_str(1, "  "); out_str(1, m); out_str(1, xd_cond(im));
                          out_str(1, " "); xd_reg(rd); out_str(1, "\n"); return; }
    if (op == X_JMP)    { xd_head(m); out_str(1, "L"); out_num(1, ins_label(in));
                          out_str(1, "\n"); return; }
    if (op == X_JCC)    { out_str(1, "  j"); out_str(1, xd_cond(im)); out_str(1, " L");
                          out_num(1, ins_label(in)); out_str(1, "\n"); return; }
    if (op == X_CALL)   { xd_head(m); out_str(1, sym_name(sym_at(ins_sym(in))));
                          out_str(1, "\n"); return; }
    if (op == X_SPADD || op == X_SPSUB) { xd_head(m); out_str(1, "rsp, "); xd_num(im);
                                          out_str(1, "\n"); return; }
    if (op == X_EMIT)   { xd_word((u32) im); return; }
    die("x86 instruction with no dump");
}

// ---- registration ----
void x86_task(i64 task, uptr fn) { st64(m_x86_64 + task * 8, fn); }

void machine_x86_64_init() {
    x86_task(MTASK_PROLOGUE,     &x86_prologue);
    x86_task(MTASK_PARAM,        &x86_param);
    x86_task(MTASK_EPILOGUE,     &x86_epilogue);
    x86_task(MTASK_FRAME_FIX,    &x86_frame_fix);
    x86_task(MTASK_CONST,        &x86_const);
    x86_task(MTASK_BIN,          &x86_bin);
    x86_task(MTASK_CMP,          &x86_cmp);
    x86_task(MTASK_UN,           &x86_un);
    x86_task(MTASK_BOOL,         &x86_bool);
    x86_task(MTASK_CAST,         &x86_cast);
    x86_task(MTASK_LOAD,         &x86_load);
    x86_task(MTASK_STORE,        &x86_store);
    x86_task(MTASK_LOCAL_ADDR,   &x86_local_addr);
    x86_task(MTASK_LOCAL_LOAD,   &x86_local_load);
    x86_task(MTASK_LOCAL_STORE,  &x86_local_store);
    x86_task(MTASK_SYM_ADDR,     &x86_sym_addr);
    x86_task(MTASK_GLOBAL_LOAD,  &x86_global_load);
    x86_task(MTASK_GLOBAL_STORE, &x86_global_store);
    x86_task(MTASK_CALL,         &x86_call);
    x86_task(MTASK_CALLP,        &x86_callp);
    x86_task(MTASK_RET,          &x86_ret);
    x86_task(MTASK_JUMP,         &x86_jump);
    x86_task(MTASK_JZ,           &x86_jz);
    x86_task(MTASK_JNZ,          &x86_jnz);
    x86_task(MTASK_LABEL,        &x86_label);
    x86_task(MTASK_WORD,         &x86_word);
    x86_task(MTASK_INS_SIZE,     &x86_ins_size);
    x86_task(MTASK_ENCODE,       &x86_put);
    x86_task(MTASK_DUMP,         &x86_dump);
    x86_task(MTASK_RELOC_KIND,   &x86_reloc_kind);
    x86_task(MTASK_RELOC_OFF,    &x86_reloc_off);
    x86_task(MTASK_REG_COUNT,    &x86_reg_count);
    x86_task(MTASK_REG_LOAD,     &x86_reg_load);
    x86_task(MTASK_REG_STORE,    &x86_reg_store);
    x86_task(MTASK_REG_SAVE,     &x86_reg_save);
    x86_task(MTASK_REG_RESTORE,  &x86_reg_restore);
    x86_task(MTASK_PARAM_REG,    &x86_param_reg);
    x86_task(MTASK_REG_SCRATCH,  &x86_reg_scratch);
    machine("x86_64", m_x86_64);

    // M20: the Win64 machine is the SAME machine with one slot replaced. Every
    // encoder, the size task, the dump and the two relocation tasks are pure
    // functions of the Ins record and are ABI-blind, so copying the table and
    // swapping the prologue is the whole of it.
    i64 t = 0;
    loop {
        if (t >= MTASK_COUNT) break;
        st64(m_x86_64_win + t * 8, ld64(m_x86_64 + t * 8));
        t = t + 1;
    }
    st64(m_x86_64_win + MTASK_PROLOGUE * 8, &x86_prologue_win);
    st64(m_x86_64_win + MTASK_REG_SCRATCH * 8, 0);   // step E: no scratch on Win64
    machine("x86_64-win", m_x86_64_win);
}
