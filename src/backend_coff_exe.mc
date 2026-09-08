// backend_coff_exe.mc — backends `pe-exe-arm64` and `pe-exe-x86_64`: a Windows
// PE32+ executable, written without lld-link (M42 step 2,
// docs/specs/M42-step2.md).
//
// It is to src/backend_coff.mc what src/backend_elf_exe.mc is to
// src/backend_elf.mc: the same `gen_lower` + `gen_encode_all` in front of it,
// the same sections, symbols and relocations behind it, and then instead of
// handing the relocations to `lld-link` it lays out the image, resolves every
// relocation itself, and writes the import directory + IAT the Windows loader
// fills. It reuses backend_coff.mc's knowledge of a Windows section (the
// characteristics, the `.text`/`.rdata`/`.data`/`.bss` naming) and the arm64 /
// x86_64 machine each architecture already carries.
//
// A PE is COFF's sections wrapped in an image layout, so the differences from
// backend_elf_exe.mc are only where the two formats spell the same idea:
//
//   an import       is a descriptor in the import directory naming its DLL,
//                   plus a hint/name entry, plus one 8-byte slot in the IAT --
//                   where ELF has one .dynsym entry, one .dynstr name and one
//                   .rela.plt JUMP_SLOT against the GOT. The IAT is the GOT.
//   a call to it    goes through a thunk (`jmp [rip+iat]` on x64, adrp/ldr/br
//                   on arm64) exactly as ELF goes through a PLT stub, because a
//                   direct `call`/`bl` reaches code and the IAT slot holds a
//                   pointer. The thunk is resolved to by the relocation.
//   the loader      fills the IAT before the entry runs, so the thunk is a
//                   plain indirect jump -- the DT_BIND_NOW of the PE world,
//                   which is the only binding a PE without a lazy-load
//                   directory ever does.
//
// UNLIKE Linux there is NO static-without-imports form: kernel32 is the only
// way off the process (ExitProcess) and to the command line, so every PE here
// imports kernel32. That is the shape the M42 § Out of scope note predicted.
//
// Two simplifications with the same M11/M42 precedent of refusing the optional
// half of a format (docs/specs/M42-step2.md § 2):
//
//   A FIXED ImageBase (0x140000000) and IMAGE_FILE_RELOCS_STRIPPED, no `.reloc`
//   and no DYNAMICBASE. Every absolute address in the image is known when the
//   segments are placed, so there is nothing to relocate at load; the loader
//   maps at ImageBase or fails. The cost is no ASLR, the same cost ET_EXEC pays
//   in backend_elf_exe.mc, named in docs/reference/objects.md.
//
//   NO base-relocation directory follows from it: the thunks address the IAT
//   RIP-relative (x64) or adrp-relative (arm64), the import tables hold RVAs,
//   and the resolved absolute addresses live only in the IAT, which the loader
//   fills. Nothing in the file needs fixing up.
//
// The entry point: a program that defines `mc_start` itself keeps it
// (`#include <sys_windows_start>`); anything else gets the small stub this file
// synthesizes -- it zeroes argc/argv/envp, calls `main`, and calls ExitProcess
// with the result. ExitProcess is the one import the stub forces (there is no
// exit syscall), exactly as ELF's synthesized _start forces nothing because it
// exits by `svc`.
//
// ALL of the writer's mutable state lives in ONE arena record, `pe`, reached
// through the accessors below -- not ~34 file-scope globals. A bundled writer's
// globals count against the frozen seed's MAXGLOBALS (512) whenever the seed
// compiles a taught compiler that carries this file through <mc/core>, so the
// milestone follows the globals-diet rule src/driver.mc and src/sandbox.mc set:
// one record, accessors, one global.
//
// Depends on arena.mc (buf_*, xalloc, mem_zero, die, die2), on objmodel.mc
// (sections, symbols, relocations, sym_find, sym_ref), on gen_walk.mc
// (gen_lower/gen_encode_all, ivec_at/set_ivec_at), on parse.mc (dylib_count/
// dylib_path, extern_lib_find) and on three files of its own part:
// backend_coff.mc (the Windows section characteristics and coff_sec_size/zf/
// exec), backend_exe.mc (exe_up, exe_segname, exe_collect_undef, undef_sym,
// nundef, exe_undef_index and the three arm64 relocation patchers) and
// backend_elf_exe.mc (ee_fix_x86_pc32 -- a rel32 has no format in it).

#include "../lib/prelude.mc"

// ---- optional header, PE32+ ----
#define PE_MAGIC_PLUS       0x20b
#define PE_OPT_SIZE         240              // magic..directories, PE32+, 16 dirs
#define PE_DOS_SIZE         0x40             // MZ header, e_lfanew at 0x3c
#define PE_HDR_FIXED        0x148            // 0x40 (DOS) + 4 (PE\0\0) + 20 (COFF) + 240 (opt)
#define PE_SHDR_SIZE        40

// IMAGE_FILE_HEADER Characteristics
#define IMAGE_FILE_RELOCS_STRIPPED    0x0001
#define IMAGE_FILE_EXECUTABLE_IMAGE   0x0002
#define IMAGE_FILE_LARGE_ADDRESS_AWARE 0x0020

// DllCharacteristics: only NX_COMPAT. Never DYNAMIC_BASE -- relocs are stripped.
#define IMAGE_DLLCHAR_NX_COMPAT       0x0100
#define IMAGE_SUBSYSTEM_WINDOWS_CUI   3

// section Characteristics (the image subset of backend_coff.mc's; the object's
// alignment bits are meaningless in an image and are not written)
#define PE_SCN_CODE     0x00000020
#define PE_SCN_INIT     0x00000040
#define PE_SCN_UNINIT   0x00000080
#define PE_SCN_EXECUTE  0x20000000
#define PE_SCN_READ     0x40000000
#define PE_SCN_WRITE    0x80000000

// data directory indices
#define PE_DIR_IMPORT   1
#define PE_DIR_IAT      12
#define PE_NDIR         16

#define PE_IMPORT_DESC  20                   // IMAGE_IMPORT_DESCRIPTOR bytes

// ImageBase: the standard x64/arm64 executable base, a 64 KiB multiple so one
// number serves both. Fixed, because relocs are stripped.
#define PE_IMGBASE      0x140000000

#define PE_SEC_ALIGN    0x1000
#define PE_FILE_ALIGN   0x200

// one thunk per import: arm64 adrp/ldr/br padded to 16, x64 jmp*[rip] padded
// to 8 -- the same sizes backend_elf_exe.mc gives its PLT stubs.
#define PE_PLT_A64      16
#define PE_PLT_X64      8

// the synthesized entry, in bytes; its only variables are two call/bl targets.
#define PE_START_A64    20
#define PE_START_X64    23

// ---- kinds of image section, in file order ----
#define PEK_MOD    1                         // one of the module's sections
#define PEK_PLT    2                         // the import thunks
#define PEK_START  3                         // the synthesized entry
#define PEK_IDATA  4                         // import directory + names + IAT

// ---- the state record ----
// scalars
#define PES_MACH      0
#define PES_PLTENT    8
#define PES_STARTSZ   16
#define PES_SYNTH     24                     // 1 when this file writes the entry
#define PES_MAINSYM   32                     // index of _main, when synthesizing
#define PES_EXITSYM   40                     // index of _ExitProcess, when synthesizing
#define PES_ENTRY     48                     // AddressOfEntryPoint
#define PES_PLTRVA    56
#define PES_IDATARVA  64
#define PES_IMGSZ     72                     // SizeOfImage
#define PES_HDRSZ     80                     // SizeOfHeaders
#define PES_IATRVA    88                     // IAT data-directory RVA
#define PES_IATSZ     96                     // IAT data-directory size
#define PES_NPE       104                    // image section count
#define PES_NDLL      112                    // distinct DLL count
// the image section table (one array-pointer each, filled in pe_plan_sections)
#define PES_KIND      120
#define PES_SRC       128                    // module section, or -1
#define PES_NAME      136
#define PES_CHAR      144
#define PES_VSIZE     152
#define PES_RVA       160
#define PES_FOFF      168
#define PES_RAWSZ     176
#define PES_ZF        184
#define PES_OFSEC     192                    // module section -> image index
// the imports (filled in pe_plan_dlls / pe_plan_idata)
#define PES_DLLORD    200                    // ordinal of each distinct DLL
#define PES_DLLNAME   208                    // its name string
#define PES_DLLILT    216                    // offset of its ILT inside .idata
#define PES_DLLIAT    224                    // offset of its IAT inside .idata
#define PES_DLLNM     232                    // offset of its name inside .idata
#define PES_IMPDLL    240                    // DLL index of import k
#define PES_IMPHN     248                    // offset of import k's hint/name
#define PES_IMPIAT    256                    // offset of import k's IAT slot
#define PES_IDATAB    264                    // a Buf, inline (BUF_SIZE = 24)
#define PES_SIZE      288

uptr pe;
void pe_init() { pe = xalloc(PES_SIZE); mem_zero(pe, PES_SIZE); }
// generic accessors over the named offsets above: one pair, not ~66, so the
// writer's function count stays inside the frozen seed's MAXFUNCS when it
// compiles a taught compiler that carries this file. The field is always a
// named #define, never a raw offset at the call site.
i64  pe_g(i64 off)          { return ld64(pe + off); }
void set_pe_g(i64 off, i64 v) { st64(pe + off, v); }



uptr pe_idatab()              { return pe + PES_IDATAB; }   // the Buf lives inline

uptr pe_name_at(i64 i)             { return ld64(pe_g(PES_NAME) + i * 8); }
void set_pe_name_at(i64 i, uptr v) { st64(pe_g(PES_NAME) + i * 8, v); }

// ---- imports ----
// The import name: the compiler's leading `_` dropped, exactly as the object
// writer drops it (a Windows symbol carries no other decoration).
uptr pe_imp_name(i64 k) {
    uptr n = sym_name(sym_at(ivec_at(undef_sym, k)));
    if (ld8(n) == '_') return n + 1;
    return n;
}

// which DLL import k comes from: ordinal 1 is kernel32.dll, ordinal >= 2 is the
// #dylib at index ordinal - 2, exactly as backend_exe.mc's exe_sym_ord.
i64 pe_imp_ord(i64 k) { return extern_lib_find(pe_imp_name(k)); }

uptr pe_ord_name(i64 ord) {
    if (ord == 1) return "kernel32.dll";
    return dylib_path(ord - 2);
}

// The distinct DLLs, ascending by ordinal so the file is reproducible. An
// ordinal only appears if some import uses it, so a program that names no
// #dylib gets exactly one descriptor.
void pe_plan_dlls() {
    i64 cap = dylib_count() + 2;
    set_pe_g(PES_DLLORD, xalloc(8 * cap));
    set_pe_g(PES_DLLNAME, xalloc(8 * cap));
    set_pe_g(PES_DLLILT, xalloc(8 * cap));
    set_pe_g(PES_DLLIAT, xalloc(8 * cap));
    set_pe_g(PES_DLLNM, xalloc(8 * cap));
    set_pe_g(PES_IMPDLL, xalloc(8 * (nundef + 1)));
    set_pe_g(PES_IMPHN, xalloc(8 * (nundef + 1)));
    set_pe_g(PES_IMPIAT, xalloc(8 * (nundef + 1)));
    set_pe_g(PES_NDLL, 0);
    // gather distinct ordinals in ascending order: the space is small (1 plus
    // the #dylib count), so a linear scan for the next-smallest is enough.
    i64 prev = 0;
    loop {
        i64 best = 0;
        i64 k = 0;
        while (k < nundef) {
            i64 o = pe_imp_ord(k);
            if (o > prev && (best == 0 || o < best)) best = o;
            k = k + 1;
        }
        if (best == 0) break;
        set_ivec_at(pe_g(PES_DLLORD), pe_g(PES_NDLL), best);
        set_ivec_at(pe_g(PES_DLLNAME), pe_g(PES_NDLL), pe_ord_name(best));
        set_pe_g(PES_NDLL, pe_g(PES_NDLL) + 1);
        prev = best;
    }
    // map each import to its DLL index
    i64 k = 0;
    while (k < nundef) {
        i64 o = pe_imp_ord(k);
        i64 d = 0;
        while (d < pe_g(PES_NDLL)) {
            if (ivec_at(pe_g(PES_DLLORD), d) == o) { set_ivec_at(pe_g(PES_IMPDLL), k, d); break; }
            d = d + 1;
        }
        k = k + 1;
    }
}

// count of imports belonging to DLL d
i64 pe_dll_count(i64 d) {
    i64 n = 0;
    i64 k = 0;
    while (k < nundef) {
        if (ivec_at(pe_g(PES_IMPDLL), k) == d) n = n + 1;
        k = k + 1;
    }
    return n;
}

// The internal layout of .idata, computed as pure arithmetic so the offsets
// exist before the descriptors that cite them are written: descriptors, then
// each DLL's ILT, then every import's hint/name, then the DLL name strings,
// then each DLL's IAT (last and contiguous, which is what lets one IAT data
// directory cover them all). The result is the length of the section.
i64 pe_plan_idata() {
    i64 off = PE_IMPORT_DESC * (pe_g(PES_NDLL) + 1);
    off = exe_up(off, 8);                     // the ILT/IAT entries are u64
    i64 d = 0;
    while (d < pe_g(PES_NDLL)) {
        set_ivec_at(pe_g(PES_DLLILT), d, off);
        off = off + 8 * (pe_dll_count(d) + 1);
        d = d + 1;
    }
    i64 k = 0;
    while (k < nundef) {
        set_ivec_at(pe_g(PES_IMPHN), k, off);
        off = off + 2 + cstrlen(pe_imp_name(k)) + 1;
        off = exe_up(off, 2);
        k = k + 1;
    }
    d = 0;
    while (d < pe_g(PES_NDLL)) {
        set_ivec_at(pe_g(PES_DLLNM), d, off);
        off = off + cstrlen(ivec_at(pe_g(PES_DLLNAME), d)) + 1;
        off = exe_up(off, 2);
        d = d + 1;
    }
    off = exe_up(off, 8);                     // the IAT entries are u64, and a
                                              // scaled arm64 ldr addresses them
    i64 iat_start = off;
    d = 0;
    while (d < pe_g(PES_NDLL)) {
        set_ivec_at(pe_g(PES_DLLIAT), d, off);
        k = 0;
        while (k < nundef) {
            if (ivec_at(pe_g(PES_IMPDLL), k) == d) {
                set_ivec_at(pe_g(PES_IMPIAT), k, off);
                off = off + 8;
            }
            k = k + 1;
        }
        off = off + 8;                       // the null terminator of this IAT
        d = d + 1;
    }
    set_pe_g(PES_IATRVA, pe_g(PES_IDATARVA) + iat_start);
    set_pe_g(PES_IATSZ, off - iat_start);
    return off;
}

// build the bytes of .idata, in exactly the order pe_plan_idata measured
void pe_build_idata() {
    uptr o = pe_idatab();
    buf_init(o);
    i64 d = 0;
    while (d < pe_g(PES_NDLL)) {                   // the import descriptors
        buf_u32(o, pe_g(PES_IDATARVA) + ivec_at(pe_g(PES_DLLILT), d));
        buf_u32(o, 0);                        // TimeDateStamp
        buf_u32(o, 0);                        // ForwarderChain
        buf_u32(o, pe_g(PES_IDATARVA) + ivec_at(pe_g(PES_DLLNM), d));
        buf_u32(o, pe_g(PES_IDATARVA) + ivec_at(pe_g(PES_DLLIAT), d));
        d = d + 1;
    }
    i64 i = 0;
    while (i < PE_IMPORT_DESC) { buf_u8(o, 0); i = i + 1; }  // null descriptor
    d = 0;
    while (d < pe_g(PES_NDLL)) {                   // each DLL's ILT: RVAs to hint/name
        i64 k = 0;
        while (k < nundef) {
            if (ivec_at(pe_g(PES_IMPDLL), k) == d)
                buf_u64(o, pe_g(PES_IDATARVA) + ivec_at(pe_g(PES_IMPHN), k));
            k = k + 1;
        }
        buf_u64(o, 0);                        // ILT null terminator
        d = d + 1;
    }
    i64 k = 0;
    while (k < nundef) {                      // hint/name: hint 0, then the name
        buf_u16(o, 0);
        buf_put(o, pe_imp_name(k), cstrlen(pe_imp_name(k)) + 1);
        buf_pad(o, 2);
        k = k + 1;
    }
    d = 0;
    while (d < pe_g(PES_NDLL)) {                   // the DLL name strings
        uptr nm = ivec_at(pe_g(PES_DLLNAME), d);
        buf_put(o, nm, cstrlen(nm) + 1);
        buf_pad(o, 2);
        d = d + 1;
    }
    d = 0;
    while (d < pe_g(PES_NDLL)) {                   // each DLL's IAT: the same RVAs
        k = 0;
        while (k < nundef) {
            if (ivec_at(pe_g(PES_IMPDLL), k) == d)
                buf_u64(o, pe_g(PES_IDATARVA) + ivec_at(pe_g(PES_IMPHN), k));
            k = k + 1;
        }
        buf_u64(o, 0);
        d = d + 1;
    }
}

// ---- the image section table ----
void pe_add(i64 kind, i64 src, uptr name, i64 chr, i64 vsize, i64 zf) {
    i64 n = pe_g(PES_NPE);
    set_ivec_at(pe_g(PES_KIND), n, kind);
    set_ivec_at(pe_g(PES_SRC), n, src);
    set_pe_name_at(n, name);
    set_ivec_at(pe_g(PES_CHAR), n, chr);
    set_ivec_at(pe_g(PES_VSIZE), n, vsize);
    set_ivec_at(pe_g(PES_ZF), n, zf);
    set_ivec_at(pe_g(PES_RVA), n, 0);
    set_ivec_at(pe_g(PES_FOFF), n, 0);
    set_ivec_at(pe_g(PES_RAWSZ), n, 0);
    if (src >= 0) set_ivec_at(pe_g(PES_OFSEC), src, n);
    set_pe_g(PES_NPE, n + 1);
}

i64 pe_find_kind(i64 kind) {
    i64 i = 0;
    while (i < pe_g(PES_NPE)) {
        if (ivec_at(pe_g(PES_KIND), i) == kind) return i;
        i = i + 1;
    }
    return 0 - 1;
}

// the image subset of backend_coff.mc's characteristics: no alignment bits (an
// image places sections by SectionAlignment, not by the per-section field).
i64 pe_sec_char(i64 i) {
    if (coff_sec_exec(i)) return PE_SCN_CODE | PE_SCN_EXECUTE | PE_SCN_READ;
    if (coff_sec_zf(i))   return PE_SCN_UNINIT | PE_SCN_READ | PE_SCN_WRITE;
    if (i == isec_cstr)   return PE_SCN_INIT | PE_SCN_READ;
    return PE_SCN_INIT | PE_SCN_READ | PE_SCN_WRITE;
}

// module non-zerofill sections in creation order, then the thunks, then the
// synthesized entry, then .idata, and the zerofill sections last so `.bss` is
// the gap at the end of the image the way it is in every other writer.
void pe_plan_sections() {
    set_pe_g(PES_NPE, 0);
    i64 cap = nsections + 4;
    set_pe_g(PES_KIND, xalloc(8 * cap));
    set_pe_g(PES_SRC, xalloc(8 * cap));
    set_pe_g(PES_NAME, xalloc(8 * cap));
    set_pe_g(PES_CHAR, xalloc(8 * cap));
    set_pe_g(PES_VSIZE, xalloc(8 * cap));
    set_pe_g(PES_RVA, xalloc(8 * cap));
    set_pe_g(PES_FOFF, xalloc(8 * cap));
    set_pe_g(PES_RAWSZ, xalloc(8 * cap));
    set_pe_g(PES_ZF, xalloc(8 * cap));
    set_pe_g(PES_OFSEC, xalloc(8 * (nsections + 1)));
    i64 i = 0;
    while (i < nsections) {
        if (!coff_sec_zf(i))
            pe_add(PEK_MOD, i, coff_sec_name(i), pe_sec_char(i), coff_sec_size(i), 0);
        i = i + 1;
    }
    if (nundef > 0)
        pe_add(PEK_PLT, 0 - 1, ".text0", PE_SCN_CODE | PE_SCN_EXECUTE | PE_SCN_READ,
               pe_g(PES_PLTENT) * nundef, 0);
    if (pe_g(PES_SYNTH))
        pe_add(PEK_START, 0 - 1, ".text1", PE_SCN_CODE | PE_SCN_EXECUTE | PE_SCN_READ,
               pe_g(PES_STARTSZ), 0);
    if (nundef > 0)
        pe_add(PEK_IDATA, 0 - 1, ".idata", PE_SCN_INIT | PE_SCN_READ | PE_SCN_WRITE,
               0, 0);                          // vsize patched after pe_plan_idata
    i = 0;
    while (i < nsections) {
        if (coff_sec_zf(i))
            pe_add(PEK_MOD, i, coff_sec_name(i), pe_sec_char(i), coff_sec_size(i), 1);
        i = i + 1;
    }
}

// ---- addresses ----
// SizeOfHeaders is the DOS header, the PE headers and the section table, on the
// file alignment. Every section VA is on SectionAlignment and every file offset
// on FileAlignment, computed independently -- a section's raw size is the file
// alignment of its virtual size, and a zerofill section has none.
void pe_layout() {
    set_pe_g(PES_HDRSZ, exe_up(PE_HDR_FIXED + PE_SHDR_SIZE * pe_g(PES_NPE), PE_FILE_ALIGN));
    i64 rva = exe_up(pe_g(PES_HDRSZ), PE_SEC_ALIGN);
    i64 fo  = pe_g(PES_HDRSZ);
    i64 i = 0;
    while (i < pe_g(PES_NPE)) {
        i64 va = exe_up(rva, PE_SEC_ALIGN);
        set_ivec_at(pe_g(PES_RVA), i, va);
        if (ivec_at(pe_g(PES_ZF), i)) {
            set_ivec_at(pe_g(PES_FOFF), i, 0);
            set_ivec_at(pe_g(PES_RAWSZ), i, 0);
        } else {
            i64 off = exe_up(fo, PE_FILE_ALIGN);
            i64 raw = exe_up(ivec_at(pe_g(PES_VSIZE), i), PE_FILE_ALIGN);
            set_ivec_at(pe_g(PES_FOFF), i, off);
            set_ivec_at(pe_g(PES_RAWSZ), i, raw);
            fo = off + raw;
        }
        rva = va + ivec_at(pe_g(PES_VSIZE), i);
        i = i + 1;
    }
    set_pe_g(PES_IMGSZ, exe_up(rva, PE_SEC_ALIGN));
    i64 p = pe_find_kind(PEK_PLT);
    if (p >= 0) set_pe_g(PES_PLTRVA, ivec_at(pe_g(PES_RVA), p));
    i = pe_find_kind(PEK_IDATA);
    if (i >= 0) set_pe_g(PES_IDATARVA, ivec_at(pe_g(PES_RVA), i));
}

// A defined symbol resolves to its section VA plus its value; an import
// resolves to its thunk, which is the address every reference to it -- a call,
// or `&ExitProcess` -- must reach, the canonical address a linker gives an
// imported function in a fixed-base image.
i64 pe_sym_addr(i64 sym) {
    uptr s = sym_at(sym);
    if (sym_sect(s) == 0) return PE_IMGBASE + pe_g(PES_PLTRVA) + exe_undef_index(sym) * pe_g(PES_PLTENT);
    return PE_IMGBASE + ivec_at(pe_g(PES_RVA), ivec_at(pe_g(PES_OFSEC), sym_sect(s) - 1)) + sym_value(s);
}

// ---- relocations, resolved in place ----
// Exactly backend_elf_exe.mc's ee_patch_relocs, with pe_sym_addr and the PE
// image base: the patchers encode instructions, and an instruction has no file
// format, so the four arm64 ones are backend_exe.mc's and the x86 rel32 one is
// backend_elf_exe.mc's.
void pe_patch_relocs() {
    i64 i = 0;
    while (i < nsections) {
        uptr s = sec_at(i);
        if (!coff_sec_zf(i)) {
            uptr p = buf_p(sec_data(s));
            i64 base = PE_IMGBASE + ivec_at(pe_g(PES_RVA), ivec_at(pe_g(PES_OFSEC), i));
            i64 j = 0;
            while (j < sec_nrel(s)) {
                uptr r = rel_at(sec_rel(s), j);
                i64 t = rel_type(r);
                i64 pc = base + rel_off(r);
                i64 tg = pe_sym_addr(rel_sym(r));
                if (t == R_BRANCH26)       exe_fix_branch26(p, rel_off(r), pc, tg);
                else if (t == R_PAGE21)    exe_fix_page21(p, rel_off(r), pc, tg);
                else if (t == R_PAGEOFF12) exe_fix_pageoff12(p, rel_off(r), tg);
                else if (t == R_X86_PC32)  ee_fix_x86_pc32(p, rel_off(r), pc, tg);
                else if (t == R_X86_PLT32) ee_fix_x86_pc32(p, rel_off(r), pc, tg);
                else if (t == R_UNSIGNED) {
                    if (rel_len(r) != 3) die("UNSIGNED that does not occupy 8 bytes");
                    st64(p + rel_off(r), tg);
                } else die("relocation not supported in the PE executable");
                j = j + 1;
            }
        }
        i = i + 1;
    }
}

// ---- synthetic content ----
// Thunk k. arm64: adrp x16, iat_slot ; ldr x16, [x16, #lo12] ; br x16, padded
// to 16 with a nop. x64: jmp qword ptr [rip + iat_slot] ; int3 int3. The IAT
// slot holds the callee once the loader has bound it, so the thunk is a plain
// indirect jump.
void pe_put_plt(uptr o) {
    i64 k = 0;
    while (k < nundef) {
        i64 pc = PE_IMGBASE + pe_g(PES_PLTRVA) + k * pe_g(PES_PLTENT);
        i64 slot = PE_IMGBASE + pe_g(PES_IDATARVA) + ivec_at(pe_g(PES_IMPIAT), k);
        if (pe_g(PES_MACH) == IMAGE_FILE_MACHINE_AMD64) {
            buf_u8(o, 0xff);
            buf_u8(o, 0x25);
            buf_u32(o, (slot - (pc + 6)) & 0xffffffff);
            buf_u8(o, 0xcc);
            buf_u8(o, 0xcc);
        } else {
            i64 im = ((slot & ~4095) - (pc & ~4095)) / 4096;
            buf_u32(o, 0x90000010 | ((im & 3) << 29) | (((im >> 2) & 0x7ffff) << 5));
            buf_u32(o, 0xf9400210 | (((slot & 4095) / 8) << 10));   // ldr x16, [x16, #lo]
            buf_u32(o, 0xd61f0200);                                 // br x16
            buf_u32(o, 0xd503201f);                                 // nop
        }
        k = k + 1;
    }
}

// The synthesized entry, when the program brings no mc_start. It zeroes
// argc/argv/envp, calls `main`, and calls ExitProcess with the result -- there
// is no exit syscall, so ExitProcess is the one import forced (pe_exitsym).
// x64 keeps a 0x28 frame: 32 bytes of shadow space plus the 8 that realigns the
// entry's 8-mod-16 rsp to 0 mod 16 before the first call.
void pe_put_start(uptr o, i64 pc) {
    i64 mainv = pe_sym_addr(pe_g(PES_MAINSYM));
    i64 exitv = pe_sym_addr(pe_g(PES_EXITSYM));
    if (pe_g(PES_MACH) == IMAGE_FILE_MACHINE_AMD64) {
        buf_u8(o, 0x48); buf_u8(o, 0x83); buf_u8(o, 0xec); buf_u8(o, 0x28);  // sub rsp,0x28
        buf_u8(o, 0x45); buf_u8(o, 0x31); buf_u8(o, 0xc0);                   // xor r8d,r8d
        buf_u8(o, 0x31); buf_u8(o, 0xd2);                                    // xor edx,edx
        buf_u8(o, 0x31); buf_u8(o, 0xc9);                                    // xor ecx,ecx
        i64 dm = mainv - (pc + 16);
        if (dm >= 2147483648 || dm < 0 - 2147483648) die("main is out of call range");
        buf_u8(o, 0xe8); buf_u32(o, dm & 0xffffffff);                        // call main
        buf_u8(o, 0x89); buf_u8(o, 0xc1);                                    // mov ecx,eax
        i64 de = exitv - (pc + 23);
        if (de >= 2147483648 || de < 0 - 2147483648) die("ExitProcess is out of call range");
        buf_u8(o, 0xe8); buf_u32(o, de & 0xffffffff);                        // call ExitProcess
    } else {
        buf_u32(o, 0xd2800000);                                             // mov x0, #0
        buf_u32(o, 0xd2800001);                                             // mov x1, #0
        buf_u32(o, 0xd2800002);                                             // mov x2, #0
        i64 dm = mainv - (pc + 12);
        if (dm % 4 != 0) die("misaligned main");
        if (dm >= 128 * 1024 * 1024 || dm < 0 - 128 * 1024 * 1024) die("main is out of bl range");
        buf_u32(o, 0x94000000 | ((dm / 4) & 0x3ffffff));                    // bl main
        i64 de = exitv - (pc + 16);
        if (de % 4 != 0) die("misaligned ExitProcess");
        if (de >= 128 * 1024 * 1024 || de < 0 - 128 * 1024 * 1024) die("ExitProcess is out of bl range");
        buf_u32(o, 0x94000000 | ((de / 4) & 0x3ffffff));                    // bl ExitProcess
    }
}

// ---- headers ----
void pe_put_dir(uptr o, i64 rva, i64 size) { buf_u32(o, rva); buf_u32(o, size); }

void pe_put_dos(uptr o) {
    buf_u8(o, 'M'); buf_u8(o, 'Z');
    i64 i = 2;
    while (i < 0x3c) { buf_u8(o, 0); i = i + 1; }
    buf_u32(o, PE_DOS_SIZE);                  // e_lfanew: the PE signature at 0x40
}

void pe_put_coff(uptr o) {
    buf_u16(o, pe_g(PES_MACH));
    buf_u16(o, pe_g(PES_NPE));
    buf_u32(o, 0);                            // TimeDateStamp: 0, determinism
    buf_u32(o, 0);                            // PointerToSymbolTable: none
    buf_u32(o, 0);                            // NumberOfSymbols
    buf_u16(o, PE_OPT_SIZE);
    buf_u16(o, IMAGE_FILE_RELOCS_STRIPPED | IMAGE_FILE_EXECUTABLE_IMAGE
             | IMAGE_FILE_LARGE_ADDRESS_AWARE);
}

// The base of code / sizes are read from the section table: the first
// executable section is BaseOfCode, and the class sums are informational.
i64 pe_code_base() {
    i64 i = 0;
    while (i < pe_g(PES_NPE)) {
        if ((ivec_at(pe_g(PES_CHAR), i) & PE_SCN_EXECUTE) != 0) return ivec_at(pe_g(PES_RVA), i);
        i = i + 1;
    }
    return 0;
}

i64 pe_class_size(i64 flag) {
    i64 sum = 0;
    i64 i = 0;
    while (i < pe_g(PES_NPE)) {
        if ((ivec_at(pe_g(PES_CHAR), i) & flag) != 0) sum = sum + ivec_at(pe_g(PES_RAWSZ), i);
        i = i + 1;
    }
    return sum;
}

void pe_put_opt(uptr o) {
    buf_u16(o, PE_MAGIC_PLUS);
    buf_u8(o, 0); buf_u8(o, 0);               // linker version
    buf_u32(o, pe_class_size(PE_SCN_CODE));   // SizeOfCode
    buf_u32(o, pe_class_size(PE_SCN_INIT));   // SizeOfInitializedData
    buf_u32(o, pe_class_size(PE_SCN_UNINIT)); // SizeOfUninitializedData
    buf_u32(o, pe_g(PES_ENTRY));
    buf_u32(o, pe_code_base());
    buf_u64(o, PE_IMGBASE);
    buf_u32(o, PE_SEC_ALIGN);
    buf_u32(o, PE_FILE_ALIGN);
    buf_u16(o, 6); buf_u16(o, 0);             // OS version 6.0
    buf_u16(o, 0); buf_u16(o, 0);             // image version
    buf_u16(o, 6); buf_u16(o, 0);             // subsystem version 6.0
    buf_u32(o, 0);                            // Win32VersionValue
    buf_u32(o, pe_g(PES_IMGSZ));
    buf_u32(o, pe_g(PES_HDRSZ));
    buf_u32(o, 0);                            // CheckSum: 0 (not a driver)
    buf_u16(o, IMAGE_SUBSYSTEM_WINDOWS_CUI);
    buf_u16(o, IMAGE_DLLCHAR_NX_COMPAT);
    buf_u64(o, 0x1000000);                    // SizeOfStackReserve: 16 MiB
    buf_u64(o, 0x1000);                       // SizeOfStackCommit
    buf_u64(o, 0x100000);                     // SizeOfHeapReserve
    buf_u64(o, 0x1000);                       // SizeOfHeapCommit
    buf_u32(o, 0);                            // LoaderFlags
    buf_u32(o, PE_NDIR);
    i64 i = 0;
    while (i < PE_NDIR) {
        if (i == PE_DIR_IMPORT && nundef > 0)
            pe_put_dir(o, pe_g(PES_IDATARVA), PE_IMPORT_DESC * (pe_g(PES_NDLL) + 1));
        else if (i == PE_DIR_IAT && nundef > 0)
            pe_put_dir(o, pe_g(PES_IATRVA), pe_g(PES_IATSZ));
        else
            pe_put_dir(o, 0, 0);
        i = i + 1;
    }
}

// the 8-byte name field, zero-padded; a name past 8 bytes would need the string
// table (`/off`), which none of the names here reaches.
void pe_put_name8(uptr o, uptr n) {
    i64 k = 0;
    i64 len = cstrlen(n);
    while (k < 8) {
        i64 c = 0;
        if (k < len) c = ld8(n + k);
        buf_u8(o, c);
        k = k + 1;
    }
}

void pe_put_shdr(uptr o, i64 i) {
    pe_put_name8(o, pe_name_at(i));
    buf_u32(o, ivec_at(pe_g(PES_VSIZE), i));       // VirtualSize
    buf_u32(o, ivec_at(pe_g(PES_RVA), i));         // VirtualAddress
    buf_u32(o, ivec_at(pe_g(PES_RAWSZ), i));       // SizeOfRawData
    buf_u32(o, ivec_at(pe_g(PES_FOFF), i));        // PointerToRawData
    buf_u32(o, 0);                            // PointerToRelocations
    buf_u32(o, 0);                            // PointerToLinenumbers
    buf_u16(o, 0);                            // NumberOfRelocations
    buf_u16(o, 0);                            // NumberOfLinenumbers
    buf_u32(o, ivec_at(pe_g(PES_CHAR), i));
}

// the content of one section, at its file offset
void pe_put_section(uptr o, i64 i) {
    i64 k = ivec_at(pe_g(PES_KIND), i);
    if (k == PEK_MOD) {
        uptr s = sec_at(ivec_at(pe_g(PES_SRC), i));
        buf_put(o, buf_p(sec_data(s)), buf_len(sec_data(s)));
    }
    else if (k == PEK_PLT)   pe_put_plt(o);
    else if (k == PEK_START) pe_put_start(o, PE_IMGBASE + ivec_at(pe_g(PES_RVA), i));
    else if (k == PEK_IDATA) buf_put(o, buf_p(pe_idatab()), buf_len(pe_idatab()));
}

// The entry: a program that defines `mc_start` keeps it (`#include
// <sys_windows_start>`); anything else is entered through the synthesized stub,
// which needs `main` and forces the ExitProcess import.
void pe_pick_entry() {
    set_pe_g(PES_SYNTH, 0);
    i64 s = sym_find("_mc_start");
    if (s >= 0 && sym_sect(sym_at(s)) != 0) return;
    set_pe_g(PES_MAINSYM, sym_find("_main"));
    if (pe_g(PES_MAINSYM) < 0 || sym_sect(sym_at(pe_g(PES_MAINSYM))) == 0)
        die("no main and no mc_start: cannot generate an executable");
    set_pe_g(PES_SYNTH, 1);
    set_pe_g(PES_EXITSYM, sym_ref("_ExitProcess"));  // undefined if the program had none
}

void pe_write(uptr path) {
    pe_pick_entry();                          // may add the ExitProcess import
    exe_collect_undef();

    pe_plan_dlls();
    pe_plan_sections();
    // .idata's size is only known once the imports are grouped; size it, then
    // the layout can place every section.
    if (nundef > 0) {
        i64 len = pe_plan_idata();            // fills the DLL/import offsets
        set_ivec_at(pe_g(PES_VSIZE), pe_find_kind(PEK_IDATA), len);
    }
    pe_layout();
    if (nundef > 0) {
        // pe_idata_rva is now known; recompute the internal RVAs and build it
        pe_plan_idata();
        pe_build_idata();
    }

    if (pe_g(PES_SYNTH)) set_pe_g(PES_ENTRY, ivec_at(pe_g(PES_RVA), pe_find_kind(PEK_START)));
    else            set_pe_g(PES_ENTRY, pe_sym_addr(sym_find("_mc_start")) - PE_IMGBASE);

    pe_patch_relocs();

    u8 o[BUF_SIZE];
    buf_init(o);
    pe_put_dos(o);
    buf_u8(o, 'P'); buf_u8(o, 'E'); buf_u8(o, 0); buf_u8(o, 0);
    pe_put_coff(o);
    pe_put_opt(o);
    i64 i = 0;
    while (i < pe_g(PES_NPE)) {
        pe_put_shdr(o, i);
        i = i + 1;
    }
    i = 0;
    while (i < pe_g(PES_NPE)) {
        if (!ivec_at(pe_g(PES_ZF), i)) {
            while (buf_len(o) < ivec_at(pe_g(PES_FOFF), i)) { buf_u8(o, 0); }
            pe_put_section(o, i);
        }
        i = i + 1;
    }
    exe_write_file(path, o);
}

// the backends. Like every writer since M17 step B, each names its machine
// first: the file records the architecture, so the backend knows which
// instruction set this executable is made of. `x86_64-win` is the Win64 ABI
// half of the x86-64 machine, the same one coff-obj-x86_64 uses.
void backend_pe_exe(i64 root, uptr out) {
    machine_use("arm64");
    pe_init();
    set_pe_g(PES_MACH, IMAGE_FILE_MACHINE_ARM64);
    set_pe_g(PES_PLTENT, PE_PLT_A64);
    set_pe_g(PES_STARTSZ, PE_START_A64);
    gen_lower(root);
    gen_encode_all();
    pe_write(out);
}

void backend_pe_exe_x86(i64 root, uptr out) {
    machine_use("x86_64-win");
    pe_init();
    set_pe_g(PES_MACH, IMAGE_FILE_MACHINE_AMD64);
    set_pe_g(PES_PLTENT, PE_PLT_X64);
    set_pe_g(PES_STARTSZ, PE_START_X64);
    gen_lower(root);
    gen_encode_all();
    pe_write(out);
}
