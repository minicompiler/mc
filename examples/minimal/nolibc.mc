// nolibc.mc — the entry file of the no-libc variant: main.mc plus the four
// lines of machine code that stand between the kernel and it.
//
// main.mc stays a pure `i64 main() { return 0; }` for every variant; the
// difference here is what wraps it. <sys_linux> plus lib/linux/<arch>/sys_arch.mc provide
// `_start`, which reads argc/argv off the entry stack, calls main and hands
// x0 straight to `exit_group` — so `ld.lld -nostdlib -e _start` needs neither
// crt1.o nor libc.a. Its system calls are plain `svc #0` with the number in
// x8, taught to the compiler by #opcode; nothing here is linked in from
// outside.
//
// The architecture layer also brings in lib/io.mc (strlen/puts/putnum) and
// the six syscall wrappers, and mc emits every function it parses — that dead
// code is most of what this variant weighs. It is still the smallest of the
// four by more than an order of magnitude.
#include <sys_linux>        // the operating-system half: the O_* flags
#include "sys_arch.mc"      // the architecture half, found through [include].paths
                            // (lib/linux/aarch64 in mc.nolibc.toml): _start, the
                            // syscall wrappers, lib/io.mc -- since 0.15.1 (PR #28)
#include "main.mc"
