// sandbox-exit: 0
// sandbox-stdout: bin ok
// sandbox-opts: --bin true
// sandbox-alt-exit: 125
// sandbox-alt-stdout:
// sandbox-alt-opts:
// sandbox-alt-report: refused: process limit (0)
// `--bin PROG` (M48 C2): the program PROG, found on the HOST's PATH by
// host_which(), bound read-only at /bin/<basename>, with PATH=/bin inside the
// box. It buys three things together, and all three are needed for a spawn to
// happen at all:
//
//   the file      /bin/true is there, and Landlock grants EXECUTE on it
//   the calls     the measured spawn delta joins the profile
//                 (tools/sandbox/<arch>-<libc>-spawn.list)
//   the counters  the run step may create 16 processes instead of 0, and may
//                 execve 1 + <number of --bin> times instead of once
//
// Without the flag the first process this program tries to make is `refused:
// process limit (0)` -- the run step's cap since step C -- so this is also the
// proof that the process counter is what the flag moves, and not a filter
// loophole.
//
// It is fork() and execv() and not posix_spawn(), and the reason is that the
// two C libraries do not agree on what a spawn does FIRST: glibc's clone3 is
// the process-creating call and is refused as `process limit (0)`, musl's
// posix_spawn makes a pipe before it clones and is refused as `syscall 59
// (pipe2)`. A fork is a fork on both, so the sentence is one sentence. The
// measured spawn delta is not narrowed by that choice: scripts/sandbox-trace.sh
// traces posix_spawn as well, which is the wider of the two.
#include <sys>
#include <io>

// waitpid comes from <sys>, which declares it (M14).
extern i64 fork();
extern i64 execv(uptr path, uptr av);
extern void _exit(i64 code);

i64 main() {
    u8 st[8];
    uptr av[2];
    st64(av, "true");
    st64(av + 8, 0);
    st32(st, -1);

    i64 pid = fork();
    if (pid < 0) { puts("fork failed\n"); return 1; }
    if (pid == 0) {
        execv("/bin/true", av);
        _exit(127);                              // only reachable if execv failed
    }
    if (waitpid(pid, st, 0) < 0) { puts("wait failed\n"); return 1; }
    // the child of a successful `true`: exited, code 0
    if (ld32(st) != 0) { puts("bad status\n"); return 1; }
    puts("bin ok\n");
    return 0;
}
