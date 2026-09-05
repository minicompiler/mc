// sys_linux.mc — the OPERATING-SYSTEM half of the Linux system layer, shared by
// both architectures. It is the sibling of src/host_linux.mc and it is split for
// the same reason (0.15.1, the coop/ops patch): the wrappers below the flags are
// raw instruction words, and a word that is a `svc #0` on AArch64 is garbage on
// x86-64. Until this split `<sys_linux>` assembled AArch64 words into any
// x86-64 program that included it, and the program segfaulted.
//
// Nothing here is includable on its own — there is no code in this file at all.
// Include the layer for the architecture you are compiling for:
//
//   #include <sys_linux_aarch64>       // svc #0, the asm-generic call numbers
//   #include <sys_linux_x86_64>        // syscall, the x86-64 call numbers
//
// Each of those includes THIS file first, then its own numbers, its own wrappers
// and lib/io.mc — the same shape src/host_linux_aarch64.mc and
// src/host_linux_x86_64.mc have around src/host_linux.mc. A program that has to
// build for both picks the layer with `[include].paths` and one shim file, the
// way examples/conc picks its thread layer (lib/linux/<arch>/sys_arch.mc, and
// docs/build.md § No libc at all).
//
// Both layers offer the same interface as lib/sys.mc, with no libc at all, and
// both provide `_start`, so the link is `-nostdlib -e _start` and needs neither
// crt1.o nor libc.a. `mc --exe` needs no link at all (M42).
//
// Warning, on both: the error is the RETURN VALUE, a small negative number
// (-errno); there is no carry flag involved. As in sys_svc.mc, the kernel's
// result is handed back raw, with no translation.

// asm-generic/fcntl.h, which is what BOTH architectures use for these four.
// They are NOT the macOS values in lib/sys.mc: O_CREAT is 0x40 here and 0x200
// there, O_TRUNC 0x200 here and 0x400 there.
#define O_RDONLY 0
#define O_WRONLY 1
#define O_CREAT  0x40
#define O_TRUNC  0x200

#define CREAT_FLAGS 0x241             // O_WRONLY | O_CREAT | O_TRUNC
