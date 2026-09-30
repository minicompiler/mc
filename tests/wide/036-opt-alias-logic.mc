// expect-exit: 0
// expect-stdout: 168 168
// M49: tests/mc/103's defect through <i128>'s machines. The comparisons inside
// && and || are 128-bit (lowered by the derived machine), the labels are the
// bundled machine's, and the integer `r` below them is an alias of a
// callee-saved register. When a label dropped every alias, `r` was read from a
// depth register that never held it: 3 3 with --opt=1 on AArch64, 6 6 on x86-64.
// scripts/check-wide.sh compiles THIS test on both roads.
#include <sys>
i64 g(i64 a, i64 b) { return a; }
i64 both(i64 r, i128 x, i128 y) {
    i64 s = 0;
    i64 k = 0;
    loop { if (k > 3) break; s = s + g(r, x < 7i && y >= 2i); k = k + 1; }
    return s;
}
i64 either(i64 r, i128 x, i128 y) {
    i64 s = 0;
    i64 k = 0;
    loop { if (k > 3) break; s = s + g(r, x > 9i || y == 3i); k = k + 1; }
    return s;
}
i64 main() {
    putnum(both(42, 5i, 3i)); puts(" ");
    putnum(either(42, 5i, 3i)); puts("\n");
    return 0;
}
