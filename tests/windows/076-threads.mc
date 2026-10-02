// expect-exit: 0
// expect-stdout: thread result 42
// skip-aarch64: windows/aarch64 has no --exe (pe-exe-arm64 is dormant)
// The real consumer case the pe-exe-x86_64 road must carry: a NATIVE PE that
// creates an OS thread, the thread runs compiled mc code and stores a result,
// main joins and prints it. This is the shape examples/threads/primes.php uses
// in mc-php -- threads compute, main reads and prints -- and the shape
// 075-pe-unwind.mc only PROXIED (it measures the stack walk, not a thread that
// produces output). The mc-php consumer reported this standalone --exe path
// emitting EMPTY output on real Windows x86_64 while the same code works as a
// .dll inside php.exe, so the defect is this backend's process/thread runtime,
// not the thread logic. Run on a real windows-2025 runner (wine is not a
// reliable oracle here: too many missing libs).
#include <sys_windows>
#include <io>

extern uptr CreateThread(uptr sa, i64 stack, uptr start, uptr param, i64 flags, uptr tid);
extern i64 WaitForSingleObject(uptr handle, i64 ms);

i64 shared;

// DWORD WINAPI worker(LPVOID): WINAPI is the default calling convention on x64.
i64 worker(uptr arg) {
    shared = 42;
    return 0;
}

i64 main(i64 argc, uptr argv) {
    uptr h = CreateThread(0, 0, &worker, 0, 0, 0);
    if (h == 0) { puts("no thread\n"); return 1; }
    WaitForSingleObject(h, -1);      // INFINITE: low 32 bits 0xFFFFFFFF
    puts("thread result ");
    putnum(shared);
    puts("\n");
    return 0;
}
