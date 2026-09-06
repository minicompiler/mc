// fork1.mc -- the mc registry server's shape (mc-registry/web/server.mc): the
// parent only accepts; every connection is handed to a CHILD forked for it,
// which answers ONE request and exits (Connection: close). Children are reaped
// with waitpid(WNOHANG) each turn and capped at MAXWORKERS live workers.
#include "httpmin.mc"

#define MAXWORKERS 64
#define WNOHANG 1

extern i32 fork();
extern void _exit(i64 code);

i64 live = 0;

i64 c_int_(i64 v) { if (v & 0x80000000) return v | 0xFFFFFFFF00000000; return v & 0xFFFFFFFF; }
void reap(i64 block) {
    u8 status[8];
    loop {
        i64 pid = c_int_(waitpid(0 - 1, status, block));
        if (pid <= 0) return;
        live = live - 1;
        if (block) return;
    }
}

u8 raw[BUFCAP];

i64 main(i64 argc, uptr argv) {
    if (argc < 2) { perr("usage: fork1 PORT\n"); return 2; }
    i64 fd = http_listen(atoi(ld64(argv + 8)));
    if (fd < 0) { perr("fork1: cannot listen\n"); return 1; }
    // (the buffer is a global: a local array of this size is over the frame limit)
    loop {
        reap(WNOHANG);
        while (live >= MAXWORKERS) { reap(0); }
        i64 cfd = accept(fd, 0, 0);
        if (cfd < 0) continue;
        i64 pid = fork();
        if (pid < 0) { close(cfd); continue; }
        if (pid == 0) {
            close(fd);
            if (http_read_request(cfd, raw)) http_respond_close(cfd);
            close(cfd);
            _exit(0);
        }
        close(cfd);
        live = live + 1;
    }
    return 0;
}
