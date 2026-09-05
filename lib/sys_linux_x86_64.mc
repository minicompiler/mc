// sys_linux_x86_64.mc — the Linux system layer on x86-64: the same interface as
// lib/sys.mc with no libc at all. lib/sys_linux_aarch64.mc is the other
// architecture and lib/sys_linux.mc is the operating-system half both include.
//
// Linux/x86-64 calling convention for a system call: the number in rax,
// arguments in rdi, rsi, rdx, r10, r8, r9, `syscall`, raw result in rax (a small
// negative value is -errno). The C convention this file's functions are compiled
// under puts their first three parameters in rdi, rsi and rdx already, and not
// one call below needs a fourth, so NOTHING has to move: every wrapper is `mov
// eax, <number>` and `syscall`. Where AArch64 has only `openat` and shuffles
// three registers up by one, x86-64 still has `open` (2) and `creat` (85).
//
// There is no #opcode table of raw AArch64 words here because there cannot be
// one: #opcode folds ONE 32-bit word, and x86 instructions are one to fifteen
// bytes. The shim is written as a BYTE STREAM cut into four-byte words, exactly
// as src/sysno_linux_x86_64.mc writes the sandbox's own shim (M43), with an
// instruction free to straddle a word boundary. The two #opcode forms below are
// the halves of one eight-byte pair:
//
//   sysnum(n)   90          nop                 (padding, so the pair is 2 words)
//               b8 nn 00    mov eax, n          (its first three bytes)
//   syscall2()  00 00       ...                 (the imm32's high half)
//               0f 05       syscall
//
// Every byte comes from
//   llvm-mc -triple=x86_64-linux-musl -x86-asm-syntax=intel --show-encoding
//
// Link with `-nostdlib -e _start`, or let `mc --exe` write the executable.
//
// Warning: as on AArch64, the kernel's result comes back raw. A failure is a
// small negative number, not -1 with an errno somewhere.

#include "sys_linux.mc"

#opcode sysnum(n)   0x0000B890 | (n << 16)   // nop ; mov eax, n  (bytes 1..3)
#opcode syscall2()  0x050F0000               // ...imm32 high half ; syscall

// arch/x86/entry/syscalls/syscall_64.tbl — NOT the asm-generic numbers AArch64
// uses (write is 64 there and 1 here, which is exactly the kind of difference
// that made this file necessary).
#define SYS_READ        0
#define SYS_WRITE       1
#define SYS_OPEN        2
#define SYS_CLOSE       3
#define SYS_CREAT      85
#define SYS_FCHMOD     91
#define SYS_EXIT_GROUP 231

i64 open(uptr path, i64 flags, i64 mode) {
    sysnum(SYS_OPEN);
    syscall2();
}

// creat(path, mode) is open(path, O_WRONLY|O_CREAT|O_TRUNC, mode), and x86-64
// has it as a call of its own: the two arguments are already where it wants them.
i64 creat(uptr path, i64 mode) {
    sysnum(SYS_CREAT);
    syscall2();
}

i64 read(i64 fd, uptr buf, i64 n) {
    sysnum(SYS_READ);
    syscall2();
}

i64 write(i64 fd, uptr buf, i64 n) {
    sysnum(SYS_WRITE);
    syscall2();
}

i64 close(i64 fd) {
    sysnum(SYS_CLOSE);
    syscall2();
}

// `chmod` is a call here too, but the interface lib/io.mc and mc itself use is
// fchmod on an open descriptor, so this is the one that is wrapped.
i64 fchmod(i64 fd, i64 mode) {
    sysnum(SYS_FCHMOD);
    syscall2();
}

void exit(i64 code) {
    sysnum(SYS_EXIT_GROUP);
    syscall2();
}

// ---- entry point ----
// The kernel enters `_start` with rsp pointing at the entry stack:
//
//     [rsp]      argc
//     [rsp + 8]  argv[0] ... argv[argc-1], NULL, envp...
//
// and every register undefined. What this file CANNOT do is what the AArch64
// layer does — `reloc(BRANCH26, "_main"); emit(0x94000000);` — because `emit()`
// writes exactly four bytes, a pending `reloc()` is pinned to the START of that
// word, `gen_word` accepts only the four Mach-O relocation kinds, and an x86
// `call rel32` is five bytes with its field one byte in. That is the same wall
// M20 hit on Windows (lib/sys_windows_start.mc says so at length).
//
// The way out here is cheaper than a second object: `main` is named by a
// PROTOTYPE, not by `extern`. A prototype is satisfied by a definition later in
// the same unit, which is exactly what a program including this file provides,
// so the call goes down the ordinary MTASK_CALL road — R_X86_PLT32, correct by
// construction. Compiled on its own this file is `prototype with no definition`,
// the same message from the seed and from mc, which is what scripts/check-asm.sh
// compares (it is written to tolerate exactly this: "including the files the
// compilers reject").
i64 main(i64 argc, uptr argv);

// rax = &argc on the entry stack. [rbp] is the CALLER's saved rbp, so this
// answers _start's frame pointer, and _start's prologue pushed exactly one
// eight-byte word (`push rbp`) before setting it — argc sits right above.
//
//   48 8b 45 00   mov rax, qword ptr [rbp]
//   48 83 c0 08   add rax, 8
uptr sysl_entry() {
    emit(0x00458B48);
    emit(0x08C08348);
}

// The kernel enters with rsp 16-byte aligned, where an mc function is compiled
// for the 8-mod-16 a `call` leaves behind; after `push rbp` the parity is one
// word off from every other frame in the program. One `sub rsp, 8` puts it back,
// and the epilogue's `leave` would undo it if this function could return.
//
//   48 83 ec 08   sub rsp, 8
i64 _start() {
    emit(0x08EC8348);
    uptr sp = sysl_entry();
    exit(main(ld64(sp), sp + 8));
}

#include "io.mc"
