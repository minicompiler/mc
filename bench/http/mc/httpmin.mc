// httpmin.mc -- the ~100 lines of examples/api/lib/http.mc this benchmark needs,
// copied so the file compiles with the DEFAULT compiler (build/mc1): no
// `class`, no `str`, no rt.mc arena. Response headers are the benchmark contract.
//
// The platform half -- SOL_SOCKET, SO_REUSEADDR and the sockaddr_in layout, the
// only things that differ between Darwin and Linux -- comes from netsys.mc, found
// through an include root: `--include=bench/http/mc/macos` on macOS,
// `--include=bench/http/mc/linux` on Linux (the bench/soak workflow). The
// examples/conc precedent, so one source tree serves both hosts.
#include <prelude>
#include <sys>

#define AF_INET      2
#define SOCK_STREAM  1
#define SA_IN_LEN    16
#define BUFCAP       8192
#define BACKLOG      128
#include "netsys.mc"

extern i32 socket(i64 domain, i64 type, i64 proto);
extern i32 setsockopt(i64 fd, i64 level, i64 opt, uptr value, i64 len);
extern i32 bind(i64 fd, uptr sa, i64 len);
extern i32 listen(i64 fd, i64 backlog);
extern i32 accept(i64 fd, uptr sa, uptr plen);

i64 slen(uptr s) { i64 n = 0; while (ld8(s + n) != 0) { n++; } return n; }
void perr(uptr s) { write(2, s, slen(s)); }

i64 atoi(uptr s) {
    i64 v = 0; i64 i = 0;
    while (ld8(s + i) >= '0' && ld8(s + i) <= '9') { v = v * 10 + (ld8(s + i) - '0'); i++; }
    return v;
}

i64 http_listen(i64 port) {
    u8 sa[SA_IN_LEN];
    u8 one[4];
    i64 fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return 0 - 1;
    st32(one, 1);
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, one, 4);
    sockaddr_in_init(sa, port);
    if (bind(fd, sa, SA_IN_LEN) < 0) { close(fd); return 0 - 1; }
    if (listen(fd, BACKLOG) < 0) { close(fd); return 0 - 1; }
    return fd;
}

// 1 when raw[0..n] holds "\r\n\r\n"
i64 has_header_end(uptr raw, i64 n) {
    i64 i = 0;
    while (i + 4 <= n) {
        if (ld8(raw + i) == '\r' && ld8(raw + i + 1) == '\n' && ld8(raw + i + 2) == '\r' && ld8(raw + i + 3) == '\n') return 1;
        i++;
    }
    return 0;
}

// reads one request (headers only; GET has no body); 1 = ok, 0 = closed/malformed
i64 http_read_request(i64 cfd, uptr raw) {
    i64 n = 0;
    while (!has_header_end(raw, n)) {
        if (n >= BUFCAP - 1) return 0;
        i64 k = read(cfd, raw + n, BUFCAP - 1 - n);
        if (k <= 0) return 0;
        n = n + k;
    }
    st8(raw + n, 0);
    return 1;
}

i64 http_write_all(i64 fd, uptr p, i64 n) {
    i64 i = 0;
    while (i < n) {
        i64 k = write(fd, p + i, n - i);
        if (k <= 0) return 0;
        i = i + k;
    }
    return 1;
}

// the contract: 200, text/plain, 13 bytes, "hello, world\n"
i64 http_respond_close(i64 cfd) {
    uptr r = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\nConnection: close\r\n\r\nhello, world\n";
    return http_write_all(cfd, r, slen(r));
}
// 1 when raw (NUL-terminated) holds `needle` ignoring ASCII case
i64 has_ci(uptr raw, uptr needle) {
    i64 ln = slen(needle);
    i64 i = 0;
    while (ld8(raw + i) != 0) {
        i64 j = 0;
        while (j < ln) {
            i64 a = ld8(raw + i + j); i64 b = ld8(needle + j);
            if (a >= 'A' && a <= 'Z') a = a + 32;
            if (b >= 'A' && b <= 'Z') b = b + 32;
            if (a != b) break;
            j++;
        }
        if (j == ln) return 1;
        i++;
    }
    return 0;
}

// the keep-alive decision, as net/http and Kestrel make it: HTTP/1.1 stays
// open unless `Connection: close`; HTTP/1.0 (what ab speaks) closes unless
// `Connection: keep-alive`, which is then echoed back.
//   0 = close after this response, 1 = keep open (HTTP/1.1), 2 = keep open and say so (HTTP/1.0)
i64 http_keep(uptr raw) {
    if (has_ci(raw, "HTTP/1.0")) {
        if (has_ci(raw, "keep-alive")) return 2;
        return 0;
    }
    if (has_ci(raw, "Connection: close")) return 0;
    return 1;
}

// keep == 1 -> the three headers; keep == 2 -> plus Connection: keep-alive; 0 -> Connection: close
i64 http_respond(i64 cfd, i64 keep) {
    if (keep == 0) return http_respond_close(cfd);
    uptr r = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nhello, world\n";
    if (keep == 2) r = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\nConnection: keep-alive\r\n\r\nhello, world\n";
    return http_write_all(cfd, r, slen(r));
}
