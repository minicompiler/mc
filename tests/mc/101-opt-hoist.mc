// 101-opt-hoist.mc — M49 § 4.8: loop-invariant constants and symbol addresses.
//
// Inside a loop two kinds of node re-materialise the same bits on every
// iteration: a constant whose immediate needs two or more `movz/movk`, and the
// address of a global array (`adrp` + `add`). Step C gives each one a
// callee-saved register of its own and materialises it ONCE at function entry,
// so the loop body reads a register instead of rebuilding the value.
//
// Three things are asserted here that nothing else in the corpus asserts:
//   `hot`    a constant needing two instructions AND a global array's address,
//            both invariant, both read every iteration -- the value must be what
//            the plain road computes, which is what the differential run in
//            scripts/check-opt.sh compares.
//   `never`  the entry materialisation runs even when the loop is NEVER entered.
//            A hoisted value costs two to four instructions at entry that cannot
//            fault (a symbol address is a relocation, not a load), so the
//            function returns its constant and never touches `tbl`.
//   `mixed`  a hoisted constant read inside the loop AND after it: every use of
//            the value becomes a register read, not only the ones that pay.
// expect-exit: 42
// expect-stdout: 3925082112 1497890816 7 1311768467294899695

#include <sys>
#include <prelude>

#define BIG   0x1234567890ABCDEF            // four movz/movk
#define MASK  0xFFFF0000                    // two: movz #0, movk #0xFFFF lsl 16
i64 tbl[8];

// the shape the benchmark's `mix` and `primes` loops have: an invariant constant
// and an invariant array address, both inside the loop. `tbl` decays to its
// address, which is the adrp+add step C hoists.
i64 hot(i64 n) {
    i64 i = 0;
    i64 a = 0;
    while (i < n) {
        st64(tbl + (i & 7) * 8, i + BIG);
        a = (a + (ld64(tbl + (i & 7) * 8) ^ MASK)) & MASK;
        i = i + 1;
    }
    return a;
}

// the loop is never entered; the entry materialisation still runs
i64 never() {
    i64 i = 0;
    i64 a = 0;
    while (i < 0) {                          // never true
        st64(tbl + (i & 7) * 8, BIG);
        a = a + BIG + ld64(tbl + (i & 7) * 8);
        i = i + 1;
    }
    return a + 7;
}

// BIG is read inside the loop AND after it
i64 mixed() {
    i64 i = 0;
    i64 a = 0;
    while (i < 3) {
        a = a ^ BIG;
        i = i + 1;
    }
    return a ^ BIG ^ BIG;                    // a == BIG after three xors
}

i64 main() {
    putnum(hot(9));   puts(" ");
    putnum(hot(10));  puts(" ");
    putnum(never());  puts(" ");
    putnum(mixed());  puts("\n");
    return 42;
}
