// expect-exit: 0
// expect-stdout: 0x401e000000000000 0x40b5850000000000 0x425176592e000000
// M49 step C: a FLOAT literal inside a loop must not be hoisted.
//
// A taught literal is an ordinary `N_INT` node -- <float>'s f64 literal is an
// N_INT whose type is TK_FLOAT and whose val is the IEEE bit pattern -- so the
// loop-invariant hoisting of M49 § 4.8 would happily give it a callee-saved
// INTEGER register and then hand the float machine an integer alias for a value
// that lives in v16..v23. Measured before the guard existed: `acc()` below
// returned 0x56e6e8cc4576e6a1 with --opt=1 where the plain road says
// 0x401e000000000000. `opt_lit_hoistable` is the guard: only a TK_INT/TK_SINT
// literal of the word width or less may take a register.
//
//   acc    2.5 three times        = 7.5              -> 0x401e000000000000
//   mixed  (786.0 + 1.0) * 7 * 1.0 = 5509.0          -> 0x40b5850000000000
//   big    1e9 summed 300 times    = 300000000000.0  -> 0x425176592e000000
//
// Every expected value was produced once by running the PLAIN road, which is the
// reference the differential test in scripts/check-opt.sh compares against.
#include <sys>
#include <prelude>
#include <float_rt>

// the original repro: one f64 literal, one loop
f64 acc() {
    f64 s = 0.0;
    i64 i = 0;
    while (i < 3) {
        s = s + 2.5;
        i = i + 1;
    }
    return s;
}

// two literals in one loop, one of them also read after it, and an integer
// constant big enough to be hoisted for real in the same function
f64 mixed() {
    f64 s = 0.0;
    i64 i = 0;
    while (i < 7) {
        s = s + 786.0;
        s = s + 1.0;
        i = i + 1;
    }
    return s * 1.0;
}

// a nested loop, so the weight is 8^2 and the value is a candidate with a very
// high score -- the shape most likely to win a register
f64 big() {
    f64 s = 0.0;
    i64 i = 0;
    while (i < 30) {
        i64 j = 0;
        while (j < 10) {
            s = s + 1000000000.0;
            j = j + 1;
        }
        i = i + 1;
    }
    return s;
}

i64 main() {
    puthexf(acc());   puts(" ");
    puthexf(mixed()); puts(" ");
    puthexf(big());   puts("\n");
    return 0;
}
