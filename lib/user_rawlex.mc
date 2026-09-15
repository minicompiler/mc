// user_rawlex.mc -- mc-php: a module owns a REGION of bytes the core has no
// grammar for, with p_skip_to.
//
// The lexer decides `'` before any handler can be reached: it is the char
// literal, tok_add("'", 1) does not beat it, and a PHP single-quoted string of
// one character is silently an integer while any other length is `unterminated
// char literal`. The answer is not to take `'` away from the core -- it is that
// a handler standing where it already owns the grammar reads the raw bytes
// itself (p_cp() to p_src_end(), which it has been able to do since M45) and
// then says where it stopped.
//
//   q'a php single-quoted string, with a ' problem'
//
// `q` is this module's token; everything from the `'` after it to the matching
// `'` is bytes the core never lexes. The same shape is a `#` comment, a heredoc
// body, or the inline HTML between ?> and <?php -- all four are "a region only
// the module can find the end of".
//
//   build/mc1 --exe lib/mc_rawlex.mc -o build/mc-rawlex
//   build/mc-rawlex --exe prog.mc -o /tmp/p && /tmp/p; echo $?
//
// NOT in tools/bundle.list: a check-script-only demo, like user_dollar.

// q'...' -> the string itself, as an ordinary N_STR node the core lowers into
// __cstring. A newline inside the region is legal and is exactly the case
// p_skip_to has to count: the line of everything after it moves.
i64 rl_str() {
    i64 line = p_line();
    uptr fl = p_file();
    uptr s = p_cp();                        // the first byte the lexer has not read
    if (s >= p_src_end() || ld8(s) != '\'')
        err_at(fl, line, "q must be followed by a single quote");
    uptr e = s + 1;
    loop {
        if (e >= p_src_end()) err_at(fl, line, "unterminated q string");
        if (ld8(e) == '\'') break;
        e = e + 1;
    }
    uptr txt = xstrdup(s + 1, e - (s + 1));
    p_skip_to(e + 1);                       // the region is consumed; lex from here
    p_next();                               // ...which is what this reads
    i64 n = node_new(N_STR, line, fl);
    set_nd_name(n, txt);
    set_nd_val(n, e - (s + 1));
    set_nd_type(n, TY_UPTR);
    return n;
}

void user_init() {
    syntax_expr("q", &rl_str);
}
