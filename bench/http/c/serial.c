/* serial.c -- raw sockets, one process, one thread, one connection at a time,
 * no keep-alive: accept, read one request, respond Connection: close, close.
 * The exact shape of mc/serial.mc. */
#define _GNU_SOURCE   /* memmem on glibc */
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static const char RESP[] =
    "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\nConnection: close\r\n\r\nhello, world\n";

static int read_request(int cfd, char *buf, int cap) {
    int n = 0;
    for (;;) {
        if (n >= 4 && memmem(buf, n, "\r\n\r\n", 4)) return 1;
        if (n >= cap - 1) return 0;
        ssize_t k = read(cfd, buf + n, cap - 1 - n);
        if (k <= 0) return 0;
        n += (int)k;
    }
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: serial PORT\n"); return 2; }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in sa = {0};
#ifdef __APPLE__
    sa.sin_len = sizeof sa;   /* Darwin only; Linux has no sin_len */
#endif
    sa.sin_family = AF_INET;
    sa.sin_port = htons(atoi(argv[1]));
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(fd, (struct sockaddr *)&sa, sizeof sa) < 0) { perror("bind"); return 1; }
    if (listen(fd, 128) < 0) { perror("listen"); return 1; }
    char buf[8192];
    for (;;) {
        int cfd = accept(fd, 0, 0);
        if (cfd < 0) continue;
        if (read_request(cfd, buf, sizeof buf)) {
            size_t off = 0, n = sizeof RESP - 1;
            while (off < n) { ssize_t k = write(cfd, RESP + off, n - off); if (k <= 0) break; off += k; }
        }
        close(cfd);
    }
}
