// nulstr-app.mc -- compiled by the taught compiler of nulstr.mc. `nulstr` is a
// pointer to the constant "N\0survive!" (10 bytes, a NUL at offset 1). Every
// byte around and after the NUL must survive the object + ld road; exit 42 iff
// it does, else a code naming the first byte that was lost.
// expect-exit: 42
i64 main() {
    uptr p = nulstr;
    if (ld8(p + 0) != 'N') return 1;             // the byte before the NUL
    if (ld8(p + 1) != 0)   return 2;             // the NUL itself
    if (ld8(p + 2) != 's') return 10;            // everything after the NUL
    if (ld8(p + 3) != 'u') return 11;
    if (ld8(p + 4) != 'r') return 12;
    if (ld8(p + 5) != 'v') return 13;
    if (ld8(p + 6) != 'i') return 14;
    if (ld8(p + 7) != 'v') return 15;
    if (ld8(p + 8) != 'e') return 16;
    if (ld8(p + 9) != '!') return 17;
    return 42;
}
