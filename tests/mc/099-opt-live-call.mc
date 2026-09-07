// 099-opt-live-call.mc — M49 § 4.1: `callp` does NOT exclude a function, and a
// local that is live across a call survives it.
//
// AAPCS64 makes x19..x28 the CALLEE's to preserve, and the pointer target of a
// `callp` is an ordinary function that keeps that promise -- which is what lets
// the allocator leave the 43 `callp` functions of src/mc.mc (the walker's whole
// gen_* family) allocatable. Here the same registers are handed out three
// levels deep, so every level's locals are live across the level below it and
// each one has to come back unchanged.
// expect-exit: 42
// expect-stdout: 6 66 666 42
#include <sys>
#include <prelude>

i64 leaf(i64 a, i64 b) {
    i64 x = a;
    i64 y = b;
    i64 i = 0;
    while (i < 3) { x = x + y; i = i + 1; }
    return x;
}

i64 mid(i64 a) {
    i64 keep = a * 2;
    i64 acc = 0;
    i64 i = 0;
    while (i < 2) { acc = acc + leaf(keep, i); i = i + 1; }
    return acc + keep;       // keep must have survived two calls
}

i64 through(uptr p, i64 a) {
    i64 keep = a + 1;
    i64 got = callp(p, a);   // an INDIRECT call over the same registers
    return got + keep;
}

i64 main() {
    i64 one = leaf(3, 1);            // 3 + 1 + 1 + 1 = 6
    putnum(one); puts(" ");
    i64 two = mid(11);               // keep 22; leaf(22,0)=22, leaf(22,1)=25; 47+22 = 69
    two = two - 3;
    putnum(two - 0); puts(" ");
    i64 three = through(&mid, 11);   // 69 + 12
    putnum(three - 15 + 600); puts(" ");
    i64 r = 42;
    putnum(r); puts("\n");
    return r;
}
