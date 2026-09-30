// expect-exit: 0
// expect-stdout: 168 168
// M49: tests/mc/103's defect through <float>'s machines. The comparisons inside
// && and || are FLOAT comparisons (lowered by the derived machine), the labels
// they need are the bundled machine's, and the integer local `r` below them is
// an alias. When a label dropped every alias, `r` was read from a depth register
// that never held it: 3 3 with --opt=1 on AArch64, 6 6 on x86-64.
#include <sys>

i64 g(i64 a, i64 b) { return a; }

i64 both(i64 r, f64 x, f64 y) {
    i64 s = 0;
    i64 k = 0;
    loop { if (k > 3) break; s = s + g(r, x < 1.0 && y >= 2.0); k = k + 1; }
    return s;
}

i64 either(i64 r, f64 x, f64 y) {
    i64 s = 0;
    i64 k = 0;
    loop { if (k > 3) break; s = s + g(r, x > 1.0 || y == 2.5); k = k + 1; }
    return s;
}

i64 main() {
    putnum(both(42, 0.5, 2.5)); puts(" ");
    putnum(either(42, 0.5, 2.5)); puts("\n");
    return 0;
}
