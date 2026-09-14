// expect-exit: 42
// expect-stdout: sys io 42
// The portable I/O shape on a Windows target, and the one that a `mc --exe` PE
// cannot carry -- this file is the answer to "why does `#include <sys>` run
// through the object road and not through --exe?".
//
// <sys> is the C-LIBRARY layer: it DECLARES open/creat/read/write/close/exit
// and brings io.mc's puts/putnum on top of them. On macOS libSystem exports
// those names and on Linux so does libc, so the declaration is satisfied by the
// system library itself. On Windows there is no such library: kernel32.dll
// exports WriteFile, not write (scripts/sysroot-windows.sh writes the whole
// list), and mc's own Windows layer, lib/sys_windows.mc, is what DEFINES the
// six over kernel32 -- compiled once into winrt.obj.
//
// So on the object road this file links: `write` is an ordinary undefined
// symbol and winrt.obj next to it supplies the definition, which is the
// `kernel32` link mode in scripts/test-windows.sh, and it runs on both Windows
// CI legs. On the `mc --exe` road there is one translation unit and no second
// object, so every undefined symbol is an IMPORT: the PE writer emits
// `write` from kernel32.dll, the loader cannot resolve it, and the image never
// reaches its entry point. scripts/test-windows-exe.sh SKIPS this shape for
// exactly that reason (see its header, § WHY A SUBSET); a self-contained PE
// writes `#include <sys_windows>` + `#include <io>` instead, which is what
// 070-kernel32.mc does.
#include <sys>

i64 main() {
    puts("sys io ");
    putnum(42);
    puts("\n");
    return 42;
}
