// netsys.mc (macOS) -- the four socket constants and the sockaddr_in layout of
// this platform. Picked by `--include=bench/http/mc/macos`; the Linux twin is
// bench/http/mc/linux/netsys.mc. Everything else in httpmin.mc is portable.
#define SOL_SOCKET   0xFFFF
#define SO_REUSEADDR 4

// struct sockaddr_in on Darwin: sin_len(1) sin_family(1) sin_port(2) sin_addr(4) zero(8)
void sockaddr_in_init(uptr sa, i64 port) {
    i64 i = 0;
    while (i < SA_IN_LEN) { st8(sa + i, 0); i++; }
    st8(sa + 0, SA_IN_LEN);
    st8(sa + 1, AF_INET);
    st8(sa + 2, (port >> 8) & 0xFF);
    st8(sa + 3, port & 0xFF);
    st8(sa + 4, 127); st8(sa + 5, 0); st8(sa + 6, 0); st8(sa + 7, 1);   // 127.0.0.1
}
