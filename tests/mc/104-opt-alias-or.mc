// 104-opt-alias-or.mc — the siblings of 103: `||`, a logic as the THIRD
// argument with two aliased ones below it, a logic nested as a right operand,
// and a hoisted global's address (M49 step C, also an alias) below a logic.
// Each column failed with --opt=1 before labels stopped dropping aliases.
//
//   ors     4 x g3(a, b, x || y)        = 4 x (5 + 7 + 1)   = 52
//   nest    4 x (a + (b + (x < 1 || y)))  = 4 x (5 + 7 + 1)   = 52
//   hoist   4 x ld64(tab + 8 * (k == 9 || x == 0))           = 4 x 11 = 44
// expect-exit: 42
// expect-stdout: 52 52 44 42
#include <sys>

i64 tab[2] = { 3, 11 };

i64 g3(i64 a, i64 b, i64 c) { return a + b + c; }

i64 ors(i64 a, i64 b, i64 x, i64 y) {
    i64 s = 0;
    i64 k = 0;
    loop { if (k > 3) break; s = s + g3(a, b, x || y); k = k + 1; }
    return s;
}

i64 nest(i64 a, i64 b, i64 x, i64 y) {
    i64 s = 0;
    i64 k = 0;
    loop { if (k > 3) break; s = s + (a + (b + (x < 1 || y))); k = k + 1; }
    return s;
}

i64 hoist(i64 x) {
    i64 s = 0;
    i64 k = 0;
    loop { if (k > 3) break; s = s + ld64(tab + 8 * (k == 9 || x == 0)); k = k + 1; }
    return s;
}

i64 main() {
    putnum(ors(5, 7, 0, 1)); puts(" ");
    putnum(nest(5, 7, 0, 0)); puts(" ");
    putnum(hoist(0)); puts(" ");
    putnum(42); puts("\n");
    return 42;
}
