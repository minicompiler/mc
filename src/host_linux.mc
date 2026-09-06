// host_linux.mc — the Linux half of the host layer (M37), shared by both
// architectures. It carries everything that depends on the OPERATING SYSTEM;
// the two files that include it, src/host_linux_aarch64.mc and
// src/host_linux_x86_64.mc, add the three answers that depend on the
// ARCHITECTURE (host_arch, host_machine, host_include).
//
// See src/host_macos.mc for what a host file is and who includes one.
//
// Every routine below is in musl exactly as it is in libSystem, under the same
// name and with the same signature, so the compiler's own code does not change
// shape between the two hosts -- only these declarations do.

// asm-generic/fcntl.h: NOT the macOS values (0x200 / 0x400 there).
#define O_CREAT 0x40
#define O_TRUNC 0x200

// M45: every one of these returns a C `int` (`waitpid` a `pid_t`, which is an
// `int` too), so bits 63..32 of the result are unspecified. The declarations
// stay `i64` for the reason src/arena.mc gives -- this file is in the seed set
// and a narrow declaration would move its codegen away from the frozen seed's
// -- and src/driver.mc reads `waitpid`, the one that can be negative, through
// c_int(). posix_spawnp's result is an errno compared against 0 and ENOENT,
// which is right on a zero-extended value either way.
extern i64 posix_spawnp(uptr pid, uptr file, uptr fa, uptr attr, uptr av, uptr envp);
extern i64 posix_spawn_file_actions_init(uptr fa);
extern i64 posix_spawn_file_actions_addopen(uptr fa, i64 fd, uptr path, i64 flags, i64 mode);
extern i64 posix_spawn_file_actions_destroy(uptr fa);
extern i64 waitpid(i64 pid, uptr status, i64 options);
extern i64 mkdir(uptr path, i64 mode);
extern i64 unlink(uptr path);

// There is no `_NSGetEnviron` here, and linking against musl's `environ` global
// would need a data relocation to an imported symbol that the ELF writer does
// not emit. The environment arrives the way the C runtime has always passed it:
// musl's crt1.o calls `main(argc, argv, envp)`, so x2 already holds it and
// src/main.mc hands it straight over.
uptr host_envp = 0;

void host_init(uptr envp) { host_envp = envp; }

uptr host_environ() { return host_envp; }

uptr host_os()  { return "linux"; }

// host_sys() is NOT here: the system layer a Linux program includes is
// architecture-specific since 0.15.1 -- `svc #0` with the call number in x8 on
// AArch64, `syscall` with it in rax on x86-64 -- so each of the two files that
// include this one answers it (lib/sys_linux.mc says why the split exists).

// `xcrun` is a macOS program: a Linux mc.toml that writes `{sdk}` is an error,
// not a spawn that fails with "cannot run xcrun" (src/driver.mc, drv_sdk).
i64 host_has_sdk() { return 0; }

// M38: what this host appends to the name of an executable it is about to write
// and then run -- nothing here, ".exe" on Windows (src/host_windows.mc).
uptr host_exe_suffix() { return ""; }

// M25: the user's home directory, where the sysroot cache lives
// (`~/.mc/sysroots/<os>-<arch>`, docs/reference/sysroot.md). Same shape as the
// macOS host: there is no `getenv` here either, only the `KEY=VALUE` array
// musl's crt1.o passed to main().
uptr host_home() {
    uptr e = host_environ();
    if (e == 0) return 0;
    i64 i = 0;
    loop {
        uptr s = ld64(e + i * 8);
        if (s == 0) return 0;
        if (mem_eq(s, "HOME=", 5)) return s + 5;
        i = i + 1;
    }
}

// M25: the downloader `mc sysroot fetch` spawns, and its fallback. A
// distribution ships one of the two; the CI runners have both.
uptr host_downloader()     { return "curl"; }
uptr host_downloader_alt() { return "wget"; }

// M48 C2: the first executable called `name` on this host's PATH, as an
// absolute path, or 0 when there is none. It is what `mc sandbox --bin PROG`
// resolves before the box exists -- once I has unshared and pivoted, the
// host's PATH names nothing.
//
// It is in the host layer and not in src/sandbox.mc for the reason host_home()
// is: the environment is the host's, and so is the separator that splits this
// variable (':' here, ';' on Windows). A name that already contains a slash is
// a path and is answered as one, which is what execvp does.
//
// `open`, `close` and c_int are the compiler's own (src/arena.mc), which this
// file may name because a call is bound after the whole unit is parsed -- the
// same reason host_home() may call mem_eq(). The test is "can it be opened for
// reading", which is what the box needs of it: it is about to be bound
// read-only and executed, and a directory would fail the bind.
//
// The c_int() around each open() is not decoration and it was measured (M48 C2,
// the review): `open` returns a C `int`, and on glibc 2.39/aarch64 a failing one
// comes back as 0x00000000ffffffff -- the low word is -1 and the high word is
// zero -- so a raw `fd >= 0` answers TRUE for a file that is not there. Without
// it this function returned the FIRST entry of PATH with the name appended,
// existing or not, and the box then died binding it (`cannot bind a --bin
// program: ENOENT`). glibc 2.43 and musl sign-extend the same result and hide
// the defect; this is the same class as the `lex_readable` miss of M43 step D
// (docs/reference/language.md § 6).
uptr host_which(uptr name) {
    if (name == 0) return 0;
    if (ld8(name) == 0) return 0;
    i64 i = 0;
    loop {
        i64 c = ld8(name + i);
        if (c == 0) break;
        if (c == '/') {
            i64 fd = c_int(open(name, 0, 0));
            if (fd < 0) return 0;
            close(fd);
            return name;
        }
        i = i + 1;
    }
    uptr e = host_environ();
    if (e == 0) return 0;
    uptr path = 0;
    i = 0;
    loop {
        uptr s = ld64(e + i * 8);
        if (s == 0) break;
        if (mem_eq(s, "PATH=", 5)) { path = s + 5; break; }
        i = i + 1;
    }
    if (path == 0) return 0;
    i64 n = cstrlen(path);
    i64 start = 0;
    i = 0;
    loop {
        if (i > n) break;
        if (i == n || ld8(path + i) == ':') {
            if (i > start) {
                uptr cand = tm_cat(tm_cat(xstrdup(path + start, i - start), "/"), name);
                i64 fd = c_int(open(cand, 0, 0));
                if (fd >= 0) { close(fd); return cand; }
            }
            start = i + 1;
        }
        i = i + 1;
    }
    return 0;
}

// M43: the raw system-call shim. Every system call the sandbox issues goes
// through here, because `prctl`, `syscall` and `clone` are VARIADIC in musl and
// this project refuses a variadic extern (M5.6), and because `seccomp`,
// `landlock_*`, `pidfd_*` and `close_range` have no musl wrapper at all. The
// implementation is `sys6` in the architecture file this host includes
// (src/sysno_linux_aarch64.mc / src/sysno_linux_x86_64.mc), which also carries
// the number table host_sysno() reads. The result is the kernel's own: -errno
// on failure, exactly as lib/sys_linux.mc documents.
i64 host_syscall6(i64 n, i64 a, i64 b, i64 c, i64 d, i64 e, i64 f) {
    return sys6(n, a, b, c, d, e, f);
}

// 1 when `mc sandbox run|exec|check` can do anything at all on this host. It is
// not "the box will work" -- that is what `mc sandbox check` measures against
// the running kernel -- only "this operating system is the one the sandbox was
// written for". macOS and Windows answer 0 and print the command to run instead.
i64 host_sandbox_supported() { return 1; }
