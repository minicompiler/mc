// 103-opt-exit.mc — M49 step E (E.1): an `if` whose `then` is nothing but a
// `break` or a `continue` lowers as ONE conditional branch to the loop's label.
//
// Every shape the walker's exit_jump accepts, and the ones it must refuse:
//   `levels`  break 1/2 and continue 1/2 out of nested loops, bare and alone in
//             a block, so each jump reaches the right label at the right depth;
//   `cond`    && and || conditions, whose lowering ends in a LABEL -- the fused
//             branch must still test the whole condition, not its last half;
//   `notone`  a `then` with two statements, and an `if` with an `else`: neither
//             is an exit branch and both keep the plain lowering;
//   `wloop`   the prelude's `while`, whose expansion IS `if (!c) break;`.
// The two roads have to agree on every number (scripts/check-opt.sh).
// expect-exit: 42
// expect-stdout: 62 30 6 9 55
#include <sys>
#include <prelude>

i64 levels() {
    i64 acc = 0;
    i64 i = 0;
    loop {
        i = i + 1;
        if (i > 9) break;
        if (i == 3) continue;
        i64 j = 0;
        loop {
            j = j + 1;
            if (j > i) { break; }
            if (j == 2) continue;
            if (i == 7 && j == 5) continue 2;
            if (i == 8 && j == 4) break 2;
            acc = acc + j;
        }
        acc = acc + 100 * (i == 9);
    }
    return acc + i;
}

i64 cond(i64 n) {
    i64 i = 0;
    i64 a = 0;
    loop {
        i = i + 1;
        if (i > 3 && a > 20 || i > n) break;
        a = a + i * 3;
    }
    return a;
}

i64 notone() {
    i64 i = 0;
    i64 a = 0;
    loop {
        i = i + 1;
        if (i > 4) { a = a + 1; break; }
        if (i == 2) break; else a = a + 1;
        a = a + 3;
    }
    return a + i;
}

i64 wloop(u8 lim) {
    i64 i = 0;
    i64 s = 0;
    while (i < lim) { i = i + 1; s = s + i; }
    return s;
}

i64 main() {
    putnum(levels());  puts(" ");
    putnum(cond(100)); puts(" ");
    putnum(notone());  puts(" ");
    putnum(cond(2) - 0); puts(" ");
    putnum(wloop(10)); puts("\n");
    return 42;
}
