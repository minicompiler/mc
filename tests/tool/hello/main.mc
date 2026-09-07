// hello_tool 0.1.0 -- copies the file named by argv[1] to stdout (M48 C3).
//
// It is an ordinary program compiled by `mc build` for the host, so it names
// the four libc calls it needs and nothing more: the box `mc tool run` puts it
// in is what decides which files the open() may reach, not the program.
extern i64 open(uptr path, i64 flags, i64 mode);
extern i64 read(i64 fd, uptr buf, i64 n);
extern i64 write(i64 fd, uptr buf, i64 n);
extern i64 close(i64 fd);

i64 main(i64 argc, uptr argv) {
    if (argc < 2) {
        write(2, "usage: hello FILE\n", 18);
        return 2;
    }
    uptr path = ld64(argv + 8);
    i64 fd = open(path, 0, 0);
    if (fd < 0) {
        write(2, "hello: cannot open the file\n", 28);
        return 1;
    }
    u8 buf[512];
    loop {
        i64 n = read(fd, buf, 512);
        if (n <= 0) break;
        write(1, buf, n);
    }
    close(fd);
    return 0;
}
