// user_dollar.mc -- teko: `$` before `"` is a claimable one-character token.
//
// The lexer emits `$` as its own token (K_DOLLAR) ONLY when the next byte is `"`
// -- string interpolation. Every other `$` is a #rule template hole and never
// reaches here. This module claims the token with syntax_expr("$") and gives
// $"..." a deliberately trivial meaning: it evaluates to the LENGTH of the
// string that follows. A real interpolation would parse the string's contents;
// the point proved here is only that the grammar position exists and a module
// reaches it -- exactly the seam a language like teko needs for `$"..."`.
//
//   build/mc1 --exe lib/mc_dollar.mc -o build/mc-dollar
//   build/mc-dollar --exe prog.mc -o /tmp/p && /tmp/p; echo $?
//
// with prog.mc = `i64 main() { return $"<42 chars>"; }`: 42 here. The default
// compiler refuses the same source ("expression expected"), because with nothing
// registered `$"` is an unclaimed token. scripts/check-surface.sh does exactly
// that, and also proves the change is inert: with no module claiming `$`,
// --dump-ast and every object are byte for byte the pre-change compiler's.
//
// The handler eats its own token (p_next) and then reads the string. The `"` is
// a NORMAL token: the lexer left it for the next lex_next, so p_id() is T_STR
// and p_name() is the decoded bytes -- there is no interpolation syntax in the
// lexer, and there does not need to be.
i64 dol_str() {
    i64 line = p_line();
    uptr fl = p_file();
    p_next();                                    // the `$` token
    if (p_id() != T_STR)
        err_at(fl, line, "$ must be followed by a string");
    i64 len = cstrlen(p_name());                 // \0 is forbidden in a string (M5.5)
    p_next();                                     // the string token
    i64 n = node_new(N_INT, line, fl);
    set_nd_val(n, len);
    set_nd_type(n, TY_I64);
    return n;
}

void user_init() {
    syntax_expr("$", &dol_str);
}
