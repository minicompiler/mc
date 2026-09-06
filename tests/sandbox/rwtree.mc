// sandbox-exit: 125
// sandbox-stdout: rw ok
// sandbox-report: refused: open /tmp/mc-c2-up.txt
// sandbox-opts: --rw /tmp/mc-c2-rw
// `--rw DIR` (M48 C2): a directory bound WRITABLE at its own absolute path.
// Two halves, and one run proves both, because a refused call never returns
// (§ 4) -- everything the program printed before it is its whole stdout.
//
//   /tmp/mc-c2-rw/w.txt      created, written and read back: the bind is real,
//                            and scripts/test-sandbox.sh then finds that file
//                            ON THE HOST, which is what "writable" means
//   /tmp/mc-c2-up.txt        one directory up, and refused BY NAME. The parent
//                            exists in the box -- mkdir_p had to make /tmp for
//                            the mount point to hang on -- and it is still not
//                            a root: Landlock grants nothing there and the
//                            supervisor refuses the openat before the kernel
//                            sees it.
//
// The path is a literal because it has to be: `--rw` binds at the path it was
// given, so a program that writes under it knows the name at compile time.
// That is the whole difference from `--ro`'s /roN numbering.
#include <sys>
#include <io>

extern uptr fopen(uptr path, uptr mode);
extern i64 fwrite(uptr p, i64 sz, i64 n, uptr f);
extern i64 fread(uptr p, i64 sz, i64 n, uptr f);
extern i32 fclose(uptr f);

i64 main() {
    uptr f = fopen("/tmp/mc-c2-rw/w.txt", "w");
    if (f == 0) { puts("rw REFUSED\n"); return 1; }
    fwrite("written by the box\n", 1, 19, f);
    fclose(f);

    u8 buf[64];
    uptr r = fopen("/tmp/mc-c2-rw/w.txt", "r");
    if (r == 0) { puts("rw UNREADABLE\n"); return 1; }
    i64 n = fread(buf, 1, 63, r);
    fclose(r);
    if (n != 19) { puts("rw SHORT\n"); return 1; }
    puts("rw ok\n");

    // one directory up: the box ends here, and says so
    uptr up = fopen("/tmp/mc-c2-up.txt", "w");
    if (up) { puts("up WRITABLE\n"); return 1; }
    puts("up refused by errno\n");
    return 1;
}
