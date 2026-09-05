// expect-exit: 3
// expect-stdout: no libc: argc=1
// No libc at all, on BOTH Linux architectures: the system layer gives
// read/write/open/close/exit as raw system calls and provides _start, so the
// link is `ld.lld -nostdlib -e _start` and `mc --exe` writes the binary with no
// link at all.
//
// The layer is architecture-specific -- `svc #0` with the number in x8 on
// AArch64, `syscall` with it in rax on x86-64 -- and the lexer cannot switch on
// an architecture, so the choice is made from OUTSIDE this file: `sys_arch.mc`
// resolves through `[include].paths`, which scripts/test-linux.sh points at
// lib/linux/aarch64 or lib/linux/x86_64 (docs/build.md § No libc at all).
//
// argc is what proves _start really read the entry stack: the kernel hands the
// program exactly one argument here, argv[0].
#include "sys_arch.mc"

i64 main(i64 argc, uptr argv) {
    puts("no libc: argc=");
    putnum(argc);
    puts("\n");
    if (ld8(ld64(argv)) == 0) return 1;      // argv[0] is a non-empty string
    return argc + 2;
}
