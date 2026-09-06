// sandbox-exit: 0
// sandbox-stdout: tmp ok
// sandbox-opts: --tmp
// sandbox-alt-exit: 125
// sandbox-alt-stdout:
// sandbox-alt-opts:
// sandbox-alt-report: refused: open /tmp/mc-c2.txt
// `--tmp` (M48 C2): a writable /tmp. It is one mkdir and nothing else, because
// the box's whole root IS a tmpfs (§ 3) -- so the directory is already
// writable, already counted against `--out`, and already dies with the box.
// What the flag adds beside the directory is the Landlock grant and the
// supervisor's root, which is why without it the same open is `refused: open
// /tmp/mc-c2.txt` and not an ENOENT.
#include <sys>
#include <io>

extern uptr fopen(uptr path, uptr mode);
extern i64 fwrite(uptr p, i64 sz, i64 n, uptr f);
extern i64 fread(uptr p, i64 sz, i64 n, uptr f);
extern i32 fclose(uptr f);

i64 main() {
    uptr f = fopen("/tmp/mc-c2.txt", "w");
    if (f == 0) { puts("tmp REFUSED\n"); return 1; }
    fwrite("scratch\n", 1, 8, f);
    fclose(f);
    u8 buf[32];
    uptr r = fopen("/tmp/mc-c2.txt", "r");
    if (r == 0) { puts("tmp UNREADABLE\n"); return 1; }
    i64 n = fread(buf, 1, 31, r);
    fclose(r);
    if (n != 8) { puts("tmp SHORT\n"); return 1; }
    puts("tmp ok\n");
    return 0;
}
