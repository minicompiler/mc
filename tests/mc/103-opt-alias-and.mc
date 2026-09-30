// 103-opt-alias-and.mc — M49: a label inside an expression must not drop the
// alias of a depth BELOW it.
//
// With --opt=1, `r` and `s` live in callee-saved registers and reading them is
// an alias (MTASK_REG_LOAD emits nothing). `!x && !y` is gen_logic, the one
// place a label sits inside an expression. The machines used to forget every
// alias at a label, so the argument already evaluated at depth 0 (`r`) and the
// left operand of `+` (`s`) were read from their depth registers, which never
// held them: the call got the loop bound 3 as `r` and the sum restarted, and
// the program printed 3 (6 on x86-64) where the plain road prints 168.
// expect-exit: 42
// expect-stdout: 168 42
#include <sys>

i64 g(i64 a, i64 b) { return a; }

i64 h(i64 r, i64 x, i64 y) {
    i64 s = 0;
    i64 k = 0;
    loop { if (k > 3) break; s = s + g(r, !x && !y); k = k + 1; }
    return s;
}

i64 main() {
    putnum(h(42, 0, 0)); puts(" ");
    putnum(42); puts("\n");
    return 42;
}
