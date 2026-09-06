// sandbox-exit: 0
// sandbox-stdout: at-path ok
// sandbox-opts: --ro /tmp/mc-c2-ro --at-path
// sandbox-alt-exit: 125
// sandbox-alt-stdout:
// sandbox-alt-opts: --ro /tmp/mc-c2-ro
// sandbox-alt-report: refused: open /tmp/mc-c2-ro/hello.txt
// `--at-path` (M48 C2): every `--ro DIR` is bound at its OWN absolute path
// instead of at /ro0, /ro1, ... The numbering is right for a corpus that is
// told where things are; it is wrong for a tool, which is HANDED host paths by
// its own caller (an editor gives a language server file:///Users/x/proj) and
// cannot be told the tree moved.
//
// The same source runs twice and the two answers are exactly the two
// placements:
//
//   --ro DIR --at-path    /tmp/mc-c2-ro/hello.txt opens: exit 0
//   --ro DIR              that path is under no root of the box, so it is
//                         `refused: open /tmp/mc-c2-ro/hello.txt`, exit 125
//
// The second half is also the proof that the numbering did not move: the
// directory IS in the box, at /ro0, and tests/sandbox/rocwd.mc reads it there.
// scripts/test-sandbox.sh makes /tmp/mc-c2-ro/hello.txt before it runs this.
#include <sys>
#include <io>

extern uptr fopen(uptr path, uptr mode);
extern i64 fread(uptr p, i64 sz, i64 n, uptr f);
extern i32 fclose(uptr f);

i64 main() {
    u8 buf[64];
    uptr f = fopen("/tmp/mc-c2-ro/hello.txt", "r");
    if (f == 0) { puts("at-path MISSING\n"); return 1; }
    i64 n = fread(buf, 1, 63, f);
    fclose(f);
    if (n < 2 || ld8(buf) != 'r') { puts("at-path WRONG\n"); return 1; }
    puts("at-path ok\n");
    return 0;
}
