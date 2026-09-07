// noperm_tool 0.1.0 -- declares NO permission (M48 § 4.1, the "(none)" row).
//
// It tries to CREATE the file named on argv[1] and reports whether it could. On
// a sandbox host `mc tool run` boxes it with no granted writable root -- its own
// install tree is bound read-only and nothing of the user's is bound at all --
// so a host-visible path is not present in the box and the create fails
// ("denied"). Run directly, with no box (macOS/Windows), it succeeds ("wrote").
// The O_* values are Linux's: the boxed proof runs only on a Linux sandbox host,
// where this program is built and run; elsewhere the write assertion is skipped.
#define O_WRONLY 1
#define O_CREAT 64
#define O_TRUNC 512
extern i64 open(uptr path, i64 flags, i64 mode);
extern i64 write(i64 fd, uptr buf, i64 n);
extern i64 close(i64 fd);

i64 main(i64 argc, uptr argv) {
    if (argc < 2) {
        write(2, "usage: noperm FILE\n", 19);
        return 2;
    }
    uptr path = ld64(argv + 8);
    i64 fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 448);
    if (fd < 0) {
        write(1, "denied\n", 7);
        return 1;
    }
    write(fd, "x", 1);
    close(fd);
    write(1, "wrote\n", 6);
    return 0;
}
