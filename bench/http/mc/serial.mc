// serial.mc -- the examples/api shape: ONE process, ONE thread, one connection
// at a time, no keep-alive: accept, read, respond (Connection: close), close.
#include "httpmin.mc"

u8 raw[BUFCAP];

i64 main(i64 argc, uptr argv) {
    if (argc < 2) { perr("usage: serial PORT\n"); return 2; }
    i64 fd = http_listen(atoi(ld64(argv + 8)));
    if (fd < 0) { perr("serial: cannot listen\n"); return 1; }
    // (the buffer is a global: a local array of this size is over the frame limit)
    loop {
        i64 cfd = accept(fd, 0, 0);
        if (cfd < 0) continue;
        if (http_read_request(cfd, raw)) http_respond_close(cfd);
        close(cfd);
    }
    return 0;
}
