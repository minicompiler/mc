// expect-exit: 42
// skip-aarch64: ARM64 PE unwind uses a different .pdata format and windows/aarch64 has no --exe
// The Win64 unwind-info regression test, and the one shape that only the
// pe-exe-x86_64 road exercises (scripts/test-windows-exe.sh picks up every
// tests/windows/*.mc; scripts/test-windows.sh builds only its named 070..074
// list, so the object+lld-link road never sees this one).
//
// mc's one-step PE writer emitted NO exception directory (.pdata/.xdata), so the
// Win64 stack unwinder treated every mc frame as a leaf: it read a wrong return
// address and the walk halted at the first mc frame. A program that merely LOADS
// never notices, but a thread/fiber/exception path that walks the stack dies --
// the defect the mc-php consumer bisected to this backend.
//
// RtlCaptureStackBackTrace (a kernel32 export) IS that stack walk, made
// observable without a crash: it returns the number of frames it could unwind.
// Through a chain of four non-leaf mc frames the walk must reach at least those
// four (c3, c2, c1, main). Before the fix the Win64 unwinder stops at one; with
// a valid .pdata describing each function's `push rbp; mov rbp, rsp` prologue it
// walks the whole chain. So: 42 iff the walk succeeded, else the (too small)
// count -- deterministic on wine and on real Windows.
extern i64 RtlCaptureStackBackTrace(i64 skip, i64 max, uptr out, uptr hash);

i64 slot[64];

i64 c3() { return RtlCaptureStackBackTrace(0, 64, &slot, 0); }
i64 c2() { return c3(); }
i64 c1() { return c2(); }

i64 main() {
    i64 n = c1();
    if (n >= 4) return 42;
    return n;
}
