// sandbox-exit: 0
// sandbox-stdout: net ok
// sandbox-opts: --allow=net
// sandbox-alt-exit: 125
// sandbox-alt-stdout:
// sandbox-alt-opts:
// sandbox-alt-report: refused: syscall 198 (socket)
// sandbox-alt-report-x86_64: refused: syscall 41 (socket)
// `--allow=net` (M48 C2): the box keeps the HOST's network namespace instead of
// unsharing an empty one, the Landlock ruleset stops handling the network, and
// the measured net delta joins the seccomp profile
// (tools/sandbox/<arch>-<libc>-net.list). Both halves are here:
//
//   with the flag     a whole TCP conversation on loopback -- this one program
//                     is both ends of it -- and exit 0
//   without it        `refused: syscall 198 (socket)`, exit 125, which is what
//                     tests/sandbox/connect.mc has asserted since step C
//
// The port is ephemeral and asked back with getsockname, so nothing here
// collides with anything already listening on the host, and no digit of it
// reaches stdout: the report and the output have to be the same on every run.
#include <sys>
#include <io>

// every one returns a C `int`: i32, so that a -1 is a -1 (M45)
extern i32 socket(i64 domain, i64 type, i64 proto);
extern i32 bind(i64 fd, uptr addr, i64 len);
extern i32 listen(i64 fd, i64 backlog);
extern i32 connect(i64 fd, uptr addr, i64 len);
extern i32 accept(i64 fd, uptr addr, uptr len);
extern i32 setsockopt(i64 fd, i64 lvl, i64 opt, uptr v, i64 n);
extern i32 getsockname(i64 fd, uptr addr, uptr len);
extern i32 shutdown(i64 fd, i64 how);
extern i32 accept4(i64 fd, uptr addr, uptr len, i64 flags);
extern i32 getpeername(i64 fd, uptr addr, uptr len);
extern i32 getsockopt(i64 fd, i64 lvl, i64 opt, uptr v, uptr n);
extern i64 send(i64 fd, uptr b, i64 n, i64 flags);
extern i64 recv(i64 fd, uptr b, i64 n, i64 flags);
extern i64 sendmsg(i64 fd, uptr msg, i64 flags);
extern i64 recvmsg(i64 fd, uptr msg, i64 flags);

i64 main() {
    u8 sa[16];
    u8 one[8];
    u8 len[8];
    u8 buf[8];
    i64 i = 0;
    loop { if (i >= 16) break; st8(sa + i, 0); i = i + 1; }
    st32(one, 1);
    st32(len, 16);
    // struct sockaddr_in: AF_INET, port 0 (the kernel picks one), 127.0.0.1
    st16(sa, 2);
    st8(sa + 4, 127); st8(sa + 5, 0); st8(sa + 6, 0); st8(sa + 7, 1);

    i64 srv = socket(2, 1, 0);                   // AF_INET, SOCK_STREAM
    if (srv < 0) { puts("socket refused\n"); return 1; }
    setsockopt(srv, 1, 2, one, 4);               // SOL_SOCKET, SO_REUSEADDR
    if (bind(srv, sa, 16) < 0) { puts("bind failed\n"); return 1; }
    if (listen(srv, 1) < 0) { puts("listen failed\n"); return 1; }
    if (getsockname(srv, sa, len) < 0) { puts("getsockname failed\n"); return 1; }

    i64 cli = socket(2, 1, 0);
    if (connect(cli, sa, 16) < 0) { puts("connect failed\n"); return 1; }
    i64 s = accept(srv, 0, 0);
    if (s < 0) { puts("accept failed\n"); return 1; }

    if (send(cli, "ping", 4, 0) != 4) { puts("send failed\n"); return 1; }
    st8(buf, 0);
    if (recv(s, buf, 4, 0) != 4) { puts("recv failed\n"); return 1; }
    if (ld8(buf) != 'p') { puts("wrong bytes\n"); return 1; }
    if (send(s, "pong", 4, 0) != 4) { puts("send back failed\n"); return 1; }
    if (recv(cli, buf, 4, 0) != 4) { puts("recv back failed\n"); return 1; }

    // A second conversation, so that every call the net delta is meant to
    // carry is really issued by something: accept4 rather than accept, the two
    // scatter-gather forms a C library may reach for instead of send/recv, and
    // the two questions a program asks about a socket it already has.
    //
    // struct msghdr on LP64: name, namelen (an int with four bytes of padding
    // behind it), iov, iovlen, control, controllen, flags -- 56 bytes, written
    // out field by field like every other record this project hands a kernel.
    u8 msg[56];
    u8 iov[16];
    u8 opt[8];
    i64 cli2 = socket(2, 1, 0);
    if (connect(cli2, sa, 16) < 0) { puts("connect2 failed\n"); return 1; }
    i64 s2 = accept4(srv, 0, 0, 0);
    if (s2 < 0) { puts("accept4 failed\n"); return 1; }

    i = 0;
    loop { if (i >= 56) break; st8(msg + i, 0); i = i + 1; }
    st64(iov, "ping");
    st64(iov + 8, 4);
    st64(msg + 16, iov);
    st64(msg + 24, 1);
    if (sendmsg(cli2, msg, 0) != 4) { puts("sendmsg failed\n"); return 1; }
    st64(iov, buf);
    st64(iov + 8, 4);
    st8(buf, 0);
    if (recvmsg(s2, msg, 0) != 4) { puts("recvmsg failed\n"); return 1; }
    if (ld8(buf) != 'p') { puts("wrong bytes 2\n"); return 1; }

    st32(len, 16);
    if (getpeername(s2, sa, len) < 0) { puts("getpeername failed\n"); return 1; }
    st32(len, 4);
    st32(opt, -1);
    if (getsockopt(cli2, 1, 4, opt, len) < 0) { puts("getsockopt failed\n"); return 1; }
    if (ld32(opt) != 0) { puts("socket error\n"); return 1; }

    shutdown(cli2, 2);
    shutdown(cli, 2);
    close(cli2); close(s2); close(cli); close(s); close(srv);
    puts("net ok\n");
    return 0;
}
