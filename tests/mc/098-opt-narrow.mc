// 098-opt-narrow.mc — M49 § 4.5: a narrow local in a register.
//
// A frame slot of a `u8` truncates at the store (`strb`) and extends at every
// load (`ldrb`); a register does both AT THE STORE and nothing at the load,
// because a register holds the extended eight bytes exactly as a spill slot
// does. The two roads therefore have to agree on every one of these, and a
// `u8` that was assigned 300 has to read back as 44 either way.
//
// It also mixes the narrow locals with a CALL, so the register they live in is
// one the callee promised to preserve.
// expect-exit: 42
// expect-stdout: 44 4294967295 65535 1 2 300 44
#include <sys>
#include <prelude>

i64 twice(i64 x) { return x + x; }

i64 main() {
    u8  b = 300;             // truncated at the store: 44
    u32 w = 0 - 1;           // 4294967295
    u16 h = 0x1ffff;         // 65535
    i32 s = 0 - 1;           // sign-extended: -1, so 0 - s is 1
    i64 acc = 0;
    i64 i = 0;
    // every one of them used enough to be worth a register
    while (i < 3) { acc = acc + b + w + h + i; i = i + 1; }
    putnum(b); puts(" ");
    putnum(w); puts(" ");
    putnum(h); puts(" ");
    putnum(0 - s); puts(" ");            // putnum has no sign: print the magnitude
    s = twice(s);            // -2, after a call that may use the same registers
    putnum(0 - s); puts(" ");
    i64 wide = b;
    wide = 300;
    b = wide;                // truncation again, from a register
    putnum(wide); puts(" ");
    putnum(b); puts("\n");
    if (acc != 3 * (44 + 4294967295 + 65535) + 3) return 1;
    return 42;
}
