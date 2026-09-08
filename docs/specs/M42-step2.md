# Spec M42 step 2 -- `mc --exe` for Windows (PE), no external linker

M42 step 1 filled the two Linux executable slots with `src/backend_elf_exe.mc`: a dynamic ELF64
`ET_EXEC` written with no `ld.lld` and no sysroot. It left the two Windows slots at 0, so a
`windows/*` build still requires `[linker]` (`lld-link`) and `mc --exe` on a Windows host has no
direct executable. § Out of scope of `docs/specs/M42.md` deferred PE to "step 2, its own spec".

This is that spec. It fills `target("windows", "aarch64", "coff-obj-arm64", "pe-exe-arm64")` and the
x86_64 pair with a **PE32+ writer**, `src/backend_coff_exe.mc`, so `mc --exe prog.exe` and a
`[project].kind = "exe"` build produce a runnable Windows executable directly, with no `lld-link`.

## What already exists

* `src/backend_coff.mc` (M19/M20) writes COFF **objects** for both Windows architectures: the
  section characteristics, the `.text`/`.rdata`/`.data`/`.bss` naming, the leading-underscore drop,
  `coff_sec_size`/`coff_sec_zf`/`coff_sec_exec`, and the two relocation tables
  (`IMAGE_REL_ARM64_*`, `IMAGE_REL_AMD64_*`). A PE executable is COFF's sections wrapped in an
  image layout, so this file is the input the writer reuses.
* `src/backend_exe.mc` (Mach-O) and `src/backend_elf_exe.mc` (ELF) are the two direct-executable
  writers this one mirrors: segment/section layout, resolving every relocation in place, a PLT-like
  stub and a GOT-like slot per import, and a synthesized entry point. Its four arm64 relocation
  patchers (`exe_fix_branch26`/`exe_fix_page21`/`exe_fix_pageoff12`) and the x86 `ee_fix_x86_pc32`
  are format-neutral (they encode instructions), and the writer reuses them.
* `lib/sys_windows.mc` provides `write`/`open`/`read`/`close`/`creat`/`exit` over seven kernel32
  `extern`s, `win_setup`/`win_argv` (the command-line split), and no crt at all.
  `lib/sys_windows_start.mc` provides `mc_start`, the entry the lld-link path uses.
* `scripts/test-windows.sh` already cross-compiles the suite to COFF objects on macOS and links +
  runs them on the `windows-11-arm` / `windows-2025` CI runners. The runtime oracle for behaviour
  exists.

## Design

### 1. `pe-exe-arm64` and `pe-exe-x86_64`

Two backends over the same `gen_lower` + `gen_encode_all` every writer consumes, registered in
`src/core_writers.mc` and placed in the executable slot the two Windows targets left at 0:

    backend("pe-exe-arm64",  &backend_pe_exe);
    backend("pe-exe-x86_64", &backend_pe_exe_x86);
    target("windows", "aarch64", "coff-obj-arm64", "pe-exe-arm64");
    target("windows", "x86_64", "coff-obj-x86_64", "pe-exe-x86_64");

`x86_64-win` is the Win64 ABI half of the x86-64 machine, the same one `coff-obj-x86_64` uses; each
backend names its machine first (`machine_use`, the M17 step B rule).

### 2. A fixed ImageBase, relocs stripped -- the ET_EXEC of the PE world

Two simplifications, both with the M11/M42 precedent of refusing the optional half of a format:

* **`ImageBase = 0x140000000`, `IMAGE_FILE_RELOCS_STRIPPED`, no `.reloc`, no DYNAMICBASE.** Every
  absolute address in the image is known when the segments are placed, so there is nothing to
  relocate at load; the loader maps at `ImageBase` or fails. `0x140000000` is the standard x64/arm64
  executable base and is normally free. The cost is no ASLR, the same cost `ET_EXEC` pays in
  `backend_elf_exe.mc`, and the same follow-up.
* **The IAT is the only thing the loader fills, before the entry runs** -- the `DT_BIND_NOW` of the
  PE world. A PE with no lazy-load directory binds every import eagerly, so the import thunk is a
  plain indirect jump and there is no resolver.

No base relocation directory follows: the thunks address the IAT RIP-relative (x64) or
adrp/ldr-relative (arm64), the import tables hold RVAs, and the resolved absolute addresses live
only in the IAT, which the loader fills. Nothing in the file needs fixing up at load.

### 3. What the writer emits

A DOS header (64 bytes, `MZ`, `e_lfanew = 0x40`), `PE\0\0`, the COFF file header (`Machine`,
`SectionCount`, `TimeDateStamp = 0`, no symbol table, `SizeOfOptionalHeader = 240`,
`Characteristics = RELOCS_STRIPPED | EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE`), the PE32+ optional
header (`Magic 0x20b`, `AddressOfEntryPoint`, `ImageBase`, `SectionAlignment 0x1000`,
`FileAlignment 0x200`, `Subsystem 3` = console, `DllCharacteristics = NX_COMPAT`,
`SizeOfImage`/`SizeOfHeaders`, `CheckSum = 0`, the 16 data directories -- Import [1] and IAT [12]
populated, the rest zero), the section table, and the sections.

The image sections, in file order:

| section | contents | characteristics |
|---|---|---|
| module sections (`.text`, `.rdata`, `.data`, custom), non-zerofill, in creation order | `gen_encode_all`'s bytes | as `backend_coff.mc` gives them, minus the object-only alignment bits |
| `.text0` | one import thunk per undefined symbol | `CODE \| EXECUTE \| READ` |
| `.text1` | the synthesized entry, when the program brings none | `CODE \| EXECUTE \| READ` |
| `.idata` | import directory + ILT + hint/name + DLL names + IAT | `INIT \| READ \| WRITE` |
| `.bss` (module zerofill), last | -- | `UNINIT \| READ \| WRITE` |

Each section VA is on `SectionAlignment` and each file offset on `FileAlignment`, computed
independently -- a section's raw size is the file alignment of its virtual size, and a zerofill
section has none. `.bss` is last so it is the gap at the end of the image, as in every other writer.

The import directory groups undefined symbols by DLL (ascending ordinal): ordinal 1 is
`kernel32.dll` (the default no `#dylib` and no `[externs]` pattern claims -- `backend_exe.mc`'s
libSystem, ELF's `libc.so`), and an ordinal >= 2 is the `#dylib` at index ordinal - 2. Per DLL: an
`IMAGE_IMPORT_DESCRIPTOR` (`OriginalFirstThunk` = its ILT RVA, `Name` = its DLL-name RVA,
`FirstThunk` = its IAT RVA, `TimeDateStamp`/`ForwarderChain` 0); an ILT and an IAT, each an array of
8-byte entries holding the RVA of an `IMAGE_IMPORT_BY_NAME` (`hint 0` + the name) and terminated by
0. The ILT and IAT hold the same content; the loader overwrites the IAT. The IATs are laid out last
and contiguous, so the IAT data directory [12] covers them all. **ILT and IAT starts are 8-aligned**
so a scaled arm64 `ldr` can address each slot.

Relocations are resolved in place, exactly as `backend_elf_exe.mc` does: a reference to a defined
symbol becomes its final address; a reference to an undefined symbol becomes its thunk address (the
canonical address a linker gives an imported function in a fixed-base image). The four arm64
patchers, the x86 rel32 patcher and `R_UNSIGNED` (an 8-byte absolute store) are the writer's whole
relocation vocabulary, refusing anything else.

An import thunk, arm64: `adrp x16, iat_page ; ldr x16, [x16, #lo12] ; br x16` padded to 16 with a
`nop`; x64: `jmp qword ptr [rip + iat_slot] ; int3 int3`, padded to 8 -- the same sizes
`backend_elf_exe.mc` gives its PLT stubs.

### 4. The entry point, and why Windows has no bare I/O suite

The kernel enters `mc_start`/the entry, not `main`, and there is no crt1-equivalent. Two cases,
decided by whether the program defines `mc_start`:

* **A program that defines `mc_start`** (`#include <sys_windows_start>`, or a wrapper that writes
  one) keeps it. That is how the command line is split: `mc_start` calls `win_setup()` +
  `win_argv()` from `lib/sys_windows.mc`.
* **Anything else** gets the synthesized entry -- a small stub the writer emits (20 arm64 bytes /
  23 x64 bytes) that zeroes `argc`/`argv`/`envp`, calls `main`, and calls `ExitProcess` with the
  result. There is no exit syscall on Windows, so `ExitProcess` is the one import the stub forces
  (`sym_ref("_ExitProcess")`), exactly as ELF's synthesized `_start` forces nothing because it
  exits by `svc`. With neither `main` nor `mc_start`:
  `no main and no mc_start: cannot generate an executable`.

**UNLIKE Linux, there is no static-without-imports form and no bare I/O suite.** `write`/`open`/etc.
are mc wrappers in `lib/sys_windows.mc` (over `WriteFile`/`CreateFileA`/...), NOT DLL exports. A
portable test declares `extern write` (or includes the macOS `lib/sys.mc`); on the lld-link path
that `write` resolves to a separate `winrt.obj`. In a single `--exe` translation unit `write` must
be DEFINED (include `<sys_windows>`), and mc treats an `extern` declaration as a full symbol
definition (`def = 1` in `func_add`, `src/gen_resolve.mc`), so the test's `extern write` and
`<sys_windows>`'s `i64 write(){...}` are `function declared twice`. This is the exact inverse of
Linux, where `write` is a `libc.so` symbol and the bare test `--exe`s directly through a
`JUMP_SLOT`.

Consequences, on the record:

* A program whose I/O is written directly against `<sys_windows>` (no `extern` for the wrapper
  names) is self-contained and `--exe`s. `tests/windows/070`/`071`/`072`/`073` are that shape.
* A pure-compute program (no I/O at all) `--exe`s bare through the synthesized entry.
* A portable I/O test (declares `extern write`, or `#include`s `lib/sys.mc`) does NOT `--exe` on
  Windows; it stays on the lld-link object path (`test-windows`, the existing gate), which is
  unchanged.

So the Windows `--exe` suite is the self-contained subset, and it is REAL: it builds every
self-mode test plus every pure test through the PE writer and RUNS them on the CI runners.

### 5. Determinism

`TimeDateStamp = 0`, `CheckSum = 0`, no symbol table, no clock, no path, no pointer order. Two
builds of the same source are `cmp`-identical.

## Registration and the diagnostic that moves

Filling the two Windows exe slots means `windows` no longer "requires `[linker]`" for
`kind = "exe"`. The `<os> requires [linker]: there is no direct executable` diagnostic
(`docs/reference/diagnostics.md`) now belongs only to a target whose exe slot is still 0 -- a
`target(os, arch, obj, 0)` a module registers -- exactly as M42 step 1 retired it for Linux.
`scripts/check-build.sh`'s `windows without [linker]` case is replaced by a positive PE cross-build.
A `windows` build that HAS a `[linker]` still takes the object + linker road unchanged.

## Files and deltas

| file | delta | |
|---|---|---|
| `src/backend_coff_exe.mc` | +~660 | new; the PE writer, both architectures |
| `src/core_writers.mc` | +5 / -2 | two `backend()` calls, two `target()` slots filled |
| `tools/bundle.list` | +1 | `mc/backend_coff_exe` |
| `scripts/test-windows.sh` | + | a `--exe` mode beside the object mode |
| `.github/workflows/ci.yml` | + | cross-compile the PE `--exe` suite; run it on the two Windows runners |
| `scripts/check-build.sh` | +/- | the windows diagnostic becomes a PE build |
| docs | | `objects.md`, `cli.md`, `build.md`, `guide/50`, `diagnostics.md` |

`stage0/` untouched. The five/six goldens move once (the bundle grows).

## Acceptance

1. **It builds.** Every self-mode test (`tests/windows/070`..`073`) and every pure `tests/*.mc`
   compiled for `windows/aarch64` and `windows/x86_64` through the PE writer, each asserted a PE of
   the right `Machine` with `TimeDateStamp 0`.
2. **It runs.** The `windows-11-arm` and `windows-2025` CI legs EXECUTE the produced `.exe`s, exit
   code and stdout compared against the source's header.
3. **The dynamic case is real.** A test that imports kernel32 (`013-putnum`-style: `write` through
   `<sys_windows>`) shows the import directory + IAT (`llvm-readobj --coff-imports`); a pure test
   shows only the entry's `ExitProcess`.
4. **Determinism.** Two builds of the same source are `cmp`-identical.
5. **macOS/Linux do not move.** `check-obj` 32/32 against the frozen seed, `check-inert` clean
   (PE `--exe` is a new, additive backend), the existing `test-windows` (COFF object + lld-link)
   unchanged.
6. **The Windows diagnostic moves**, not disappears: an exe-slot-0 target still says
   `requires [linker]`.

## Risks

1. **The I/O-extern collision** (§ 4). Contained by scoping the `--exe` suite to the self-contained
   subset and leaving the portable I/O suite on the lld-link path, documented rather than worked
   around.
2. **A misaligned IAT** silently mis-binds through a scaled arm64 `ldr`. Found and fixed during the
   work: the ILT and IAT starts are 8-aligned. Cross-checked with `llvm-objdump -d` that the thunk
   target equals `ImportAddressTableRVA`.
3. **`.pdata`/`.xdata`** stay the accepted M19/M20 gap: no unwind info, so an unwind THROUGH an mc
   frame is undefined. Nothing in the suite unwinds.
4. **No local Windows host.** Validated on macOS with `llvm-readobj`/`llvm-objdump` against
   `lld-link`'s output, and RUN under `wine` in `docker --platform linux/amd64` for x86_64; arm64
   PE execution is the CI runner's job.

## Implementation notes (written while building it)

1. **The IAT alignment bug** (risk 2), found by disassembling the first arm64 build: the IAT started
   at offset 0x54 inside `.idata`, and the thunk's `ldr x16, [x16, #0x50]` (the immediate is scaled
   by 8 and truncates) addressed 0x4050 where the slot was at 0x4054. `pe_plan_idata` now
   `exe_up(off, 8)` before the ILT block and before the IAT block. Every entry is a `u64` and the
   section VA is page-aligned, so aligning the internal offsets is enough.

2. **`callp(&main, ...)` is how a wrapper's `mc_start` calls `main`.** A direct `main(argc, argv, 0)`
   is arity-checked against `main`'s real definition in the same unit (`wrong number of arguments`
   when `main` takes fewer), because `mc_start` and `main` are one translation unit here rather than
   the two objects the lld-link path links. `callp` takes a pointer and arguments and is not
   arity-checked, so `ExitProcess(callp(&main, argc, win_argv(), 0))` calls `main` with three
   arguments in `x0/x1/x2` and `main` reads however many it declares. This is what
   `scripts/test-windows.sh --exe` writes above each self-mode test.

3. **The synthesized entry is exercised bare.** A pure `tests/*.mc` has no `mc_start`, so
   `mc --exe pure.mc` genuinely produces a runnable PE through the synthesized stub, whose only
   import is `ExitProcess`.
