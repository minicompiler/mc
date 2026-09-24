// 100-opt-opcode.mc — M49 § 4.1: a function that writes raw words is left alone.
//
// `#opcode`, `emit()` and `reloc()` put instructions in the stream that NAME
// REGISTERS BY HAND (docs/reference/objects.md § 4, "#opcode names registers"),
// and the walker inserts nothing around them. The allocator therefore refuses
// the whole FUNCTION that contains one -- not the statement, the function --
// using. The proof is that `raw` names no allocatable register on either road
// -- no x19..x28, and (M49 step E) none of x0..x7 as a scratch register either
// -- while `hot` right beside it is allocated. What `raw` does get on the
// optimized road is what names no register but an expression depth's: the
// branch fusion of step B and the exit branch and immediates of step E.
// expect-exit: 42
// expect-stdout: 55 42
// skip-x86_64: the #opcode template is an AArch64 word (movz); the x86-64 machine emits its own instruction set
#include <sys>
#include <prelude>

// movz xd, #imm -- an instruction that names its own destination register.
#opcode movz(rd, imm) 0xD2800000 | (imm << 5) | rd

i64 raw() {
    i64 a = 0;
    i64 i = 0;
    while (i < 4) { a = a + i; i = i + 1; }   // enough uses to score
    movz(0, 55);                              // ...but the function is excluded
}

i64 hot() {
    i64 a = 0;
    i64 i = 0;
    while (i < 4) { a = a + i; i = i + 1; }
    return a + 36;
}

i64 main() {
    putnum(raw()); puts(" ");
    putnum(hot()); puts("\n");
    return hot();
}
