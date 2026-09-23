#include "../src/host_macos.mc"
#include "../src/core.mc"

uptr tk_join(uptr a, uptr b) {
    i64 la = cstrlen(a);
    i64 lb = cstrlen(b);
    uptr d = xalloc(la + lb + 1);
    mem_copy(d, a, la);
    mem_copy(d + la, b, lb);
    st8(d + la + lb, 0);
    return d;
}
uptr tk_join3(uptr a, uptr b, uptr c) { return tk_join(tk_join(a, b), c); }
uptr tk_num(i64 v) {
    u8 tmp[24];
    i64 neg = 0;
    if (v < 0) { neg = 1; v = 0 - v; }
    i64 i = 24;
    loop {
        i = i - 1;
        st8(tmp + i, '0' + v % 10);
        v = v / 10;
        if (v == 0) break;
    }
    if (neg) { i = i - 1; st8(tmp + i, '-'); }
    return xstrdup(tmp + i, 24 - i);
}

i64 dollar_expr() {
    i64 line = p_line();
    uptr fl = p_file();
    p_next();                       // the `$`
    if (tok_id(cur) != T_STR) err_at(fl, line, "needs a string literal");
    uptr qstart = p_start();
    uptr qend = p_cp();
    uptr inner = qstart + 1;
    i64 n = (((i64) qend) - ((i64) qstart)) - 2;
    uptr buf = xalloc(n + 3);
    i64 w = 1;
    st8(buf, '"');
    i64 i = 0;
    loop {
        if (i >= n) break;
        st8(buf + w, ld8(inner + i));
        w = w + 1;
        i = i + 1;
    }
    st8(buf + w, '"');
    w = w + 1;
    st8(buf + w, 0);
    i64 d0 = p_depth();
    uptr fname = tk_join3("interpolation hole at ", fl, tk_join3(":", tk_num(line), ""));
    p_push_source(fname, buf, w);
    p_next();
    i64 nd = parse_expr(0);
    if (p_depth() != d0) err_at(fl, line, "depth mismatch");
    return nd;
}

i64 noop_pass(i64 root) { return root; }

i64 my_claim(uptr name) { return 1; }
void my_on_source(uptr name, uptr src, i64 len) { }

void user_init() {
    source_claim(&my_claim);
    on_source(&my_on_source);
    syntax_expr("$", &dollar_expr);
    pass(&noop_pass);
}
