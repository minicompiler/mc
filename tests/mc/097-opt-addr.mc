// 097-opt-addr.mc — M49 § 7.5: a local whose ADDRESS is taken stays in memory.
//
// The allocator's eligibility rule (docs/specs/M49.md § 4.1) refuses any
// declaration res_addr_taken() marks, and this is why: a pointer to a local is
// a pointer to a frame slot, and a register has no address. Written through the
// pointer, the value read back afterwards has to be the value stored -- which
// it would not be if the read came out of a stale register.
//
// It lives in tests/mc/ and not in tests/ only because scripts/check-opt.sh
// runs that directory too; the frozen seed compiles it fine, which is what the
// plain half of every run asserts.
// expect-exit: 42
// expect-stdout: 7 42 99
#include <sys>
#include <prelude>

void bump(uptr p, i64 by) { st64(p, ld64(p) + by); }

i64 main() {
    i64 kept = 0;            // no & of it: a candidate
    i64 taken = 5;           // & of it below: never a candidate
    i64 i = 0;
    while (i < 7) { kept = kept + 1; i = i + 1; }
    bump(&taken, 2);         // taken == 7, through memory
    putnum(taken); puts(" ");
    // the two must not have collided, and `kept` must have survived the call
    i64 sum = 0;
    i = 0;
    while (i < 5) { st64(&taken, taken + kept); i = i + 1; }
    sum = taken;             // 7 + 5*7 = 42
    putnum(sum); puts(" ");
    // a local written only through its address, read only by name
    i64 hidden = 0;
    st64(&hidden, 99);
    putnum(hidden); puts("\n");
    return sum;
}
