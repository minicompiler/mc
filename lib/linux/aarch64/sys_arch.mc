// lib/linux/aarch64/sys_arch.mc — one name for "the Linux system layer of the
// architecture this build targets". The lexer cannot switch on an architecture,
// so the choice is made from OUTSIDE the source, by `[include].paths` in mc.toml
// (or `--include=DIR` on the command line) naming lib/linux/aarch64 or
// lib/linux/x86_64. It is examples/conc's lib/macos vs lib/linux, one level down.
#include <sys_linux_aarch64>
