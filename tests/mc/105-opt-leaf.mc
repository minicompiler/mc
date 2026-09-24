// 105-opt-leaf.mc — M49 step E (E.3): a function that makes no call allocates
// the machine's SCRATCH registers first (x0..x7 on AArch64, rdi/rsi on System V)
// and saves none of them.
//
//   `keep`    four 8-byte parameters that stay in the registers they arrived in,
//             two locals in the scratch registers left over, nothing saved;
//   `narrow`  a u8 and an i32 parameter, which may NOT stay where they arrived
//             (the extension would write an argument register the prologue has
//             not finished reading) -- truncation and sign on both roads;
//   `many`    twelve parameters and more live values than there are scratch
//             registers: the rest go to x19..x28 and ARE saved, and the ones
//             past the eighth argument arrived on the stack;
//   `early`   a value returned from inside a loop while the other locals are
//             still live, so the result register is written once, last;
//   `twice`   a function that calls something -- not a leaf -- next to its leaf
//             twin: the same answer, and only the leaf keeps its scratch.
// expect-exit: 42
// expect-stdout: 245 195 2 156 1009 7 7
#include <sys>
#include <prelude>

i64 keep(i64 a, i64 b, i64 c, i64 d) {
    i64 s = 0;
    i64 i = 0;
    while (i < a) {
        s = s + b * i + c - d;
        i = i + 1;
    }
    return s;
}

i64 narrow(u8 a, i32 b, i64 n) {
    i64 s = 0;
    i64 i = 0;
    while (i < n) { s = s + a + b; i = i + 1; }
    return s;
}

i64 many(i64 a, i64 b, i64 c, i64 d, i64 e, i64 f, i64 g, i64 h,
         i64 p, i64 q, i64 r, i64 t) {
    i64 s1 = a + b;
    i64 s2 = c + d;
    i64 s3 = e + f;
    i64 s4 = g + h;
    i64 s5 = p + q;
    i64 s6 = r + t;
    i64 i = 0;
    i64 acc = 0;
    while (i < 2) {
        acc = acc + s1 + s2 + s3 + s4 + s5 + s6 + a + b + c + d + e + f + g + h + p + q + r + t;
        i = i + 1;
    }
    return acc / 2;
}

i64 early(uptr p, i64 n) {
    i64 i = 0;
    i64 last = 0;
    loop {
        if (i >= n) break;
        i64 c = ld8(p + i);
        if (c == 'x') return i * 100 + last;
        last = c - '0';
        i = i + 1;
    }
    return 0 - 1;
}

i64 id(i64 x) { return x; }

i64 twice_call(i64 n) {
    i64 s = 0;
    i64 i = 0;
    while (i < n) { s = s + id(i); i = i + 1; }
    return s;
}
i64 twice_leaf(i64 n) {
    i64 s = 0;
    i64 i = 0;
    while (i < n) { s = s + i; i = i + 1; }
    return s;
}

i64 main() {
    putnum(keep(10, 5, 3, 1)); puts(" ");
    putnum(narrow(300, 0 - 5, 5)); puts(" ");
    putnum(narrow(2, 0, 1)); puts(" ");
    putnum(many(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)); puts(" ");
    putnum(early("0123456789x", 11)); puts(" ");
    putnum(twice_call(4) + 1); puts(" ");
    putnum(twice_leaf(4) + 1); puts("\n");
    return 42;
}
