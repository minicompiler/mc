// site/gen/linux/site_host.mc — the Linux half of mcsite's host layer.
// site/gen/macos/site_host.mc carries the reasons; this file carries the
// offsets, which are the one thing that differs.
//
// <bits/dirent.h> in musl, and the same record glibc's `struct dirent` is on a
// 64-bit host. It is one field SHORTER than the macOS one -- there is no
// d_namlen -- so d_type and d_name sit two and three bytes lower, and the name's
// length is the distance to its NUL. Reading it at the macOS offsets is what
// made mcsite render 7 pages instead of 87 before this split: every name came
// out truncated or empty, so almost every directory listing looked empty.
//
//   0  d_ino (u64)   8  d_off (i64)   16 d_reclen (u16)
//   18 d_type (u8)   19 d_name (bytes, NUL-terminated)

uptr host_site_os()          { return "linux"; }
i64  host_dirent_type(uptr e)   { return ld8(e + 18); }
uptr host_dirent_name(uptr e)   { return e + 19; }
i64  host_dirent_namlen(uptr e) { return cstrlen(e + 19); }
