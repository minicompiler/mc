// site/gen/macos/site_host.mc — the macOS half of mcsite's host layer.
//
// mcsite is an ordinary mc program, so what it needs from the system it runs on
// is what any program needs: the shape of `struct dirent`. That is the whole
// file. Everything else mcsite touches -- open/read/write/close, opendir,
// mkdir, posix_spawnp, waitpid -- has the same name and the same signature in
// libSystem and in musl, and the environment arrives as `main`'s third
// parameter on both (it used to be `_NSGetEnviron`, which musl does not have and
// which made an unpatched mcsite fail to load on Linux).
//
// site/gen/linux/site_host.mc is the other one. The lexer cannot switch on an
// operating system, so `[include].paths` in site/mc.toml (or site/mc.linux.toml)
// names one of the two directories and site/gen/main.mc includes
// "site_host.mc" -- the shape examples/conc uses for its thread layer, and the
// one lib/linux/<arch>/sys_arch.mc uses for the Linux system layer.
//
// <sys/dirent.h> on macOS. `readdir` already is the 64-bit-inode entry point on
// arm64 -- there is no $INODE64 suffix here:
//
//   0  d_ino (u64)   8  d_seekoff (u64)   16 d_reclen (u16)
//   18 d_namlen (u16)  20 d_type (u8)     21 d_name (bytes, d_namlen long)

uptr host_site_os()          { return "macos"; }
i64  host_dirent_type(uptr e)   { return ld8(e + 20); }
uptr host_dirent_name(uptr e)   { return e + 21; }
i64  host_dirent_namlen(uptr e) { return ld16(e + 18); }
