// nulstr.mc -- a module whose `nulstr` expression evaluates to the address of a
// constant that contains an EMBEDDED NUL byte ("N\0survive!").
//
// mc the language forbids \0 inside a string literal (M5.5) precisely because
// the Mach-O object writer put string constants in __cstring, whose type
// S_CSTRING_LITERALS makes external `ld` split the section on NUL -- truncating
// any NUL-bearing constant at the link. A TAUGHT compiler builds the N_STR node
// directly, so it can carry a NUL, which is exactly what a consumer (mc-php)
// does with e.g. addcslashes. This module is that consumer, reduced: its `nulstr`
// word yields a pointer to "N\0survive!" and scripts/check-build.sh (nulstr.toml)
// links the program with real `ld` and checks every byte survives.
//
// The fix routes a NUL-bearing constant to __const/S_REGULAR (non-coalescing);
// NUL-free string literals stay in __cstring.
i64 nul_str() {
    i64 line = p_line();
    uptr fl = p_file();
    p_next();                                    // the `nulstr` token
    uptr b = xalloc(16);
    st8(b + 0, 'N');
    st8(b + 1, 0);                               // the embedded NUL
    st8(b + 2, 's');
    st8(b + 3, 'u');
    st8(b + 4, 'r');
    st8(b + 5, 'v');
    st8(b + 6, 'i');
    st8(b + 7, 'v');
    st8(b + 8, 'e');
    st8(b + 9, '!');
    i64 n = node_new(N_STR, line, fl);
    set_nd_name(n, b);
    set_nd_val(n, 10);                           // length 10, the NUL included
    set_nd_type(n, TY_UPTR);
    return n;
}

void user_init() {
    syntax_expr("nulstr", &nul_str);
}
