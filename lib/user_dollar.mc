// user_dollar.mc -- teko: `$` is a claimable one-character token, created from
// the surface with no change to the core.
//
// `$` is not a core token. Every `$` that begins a #rule template hole ($name,
// $1, $$gensym) is lexed as a hole and never reaches here; every other `$` runs
// the lexer's surface matcher. This module reserves the lexeme with
// syntax_expr("$") -- word_add -> tok_add -- so the matcher finds the
// one-character `$` token, and gives $"..." a deliberately trivial meaning: it
// evaluates to the LENGTH of the string that follows. A real interpolation would
// parse the string's contents; the point proved here is only that the grammar
// position exists and a module reaches it, purely through the surface -- exactly
// the seam a language like teko needs for `$"..."`.
//
//   build/mc1 --exe lib/mc_dollar.mc -o build/mc-dollar
//   build/mc-dollar --exe prog.mc -o /tmp/p && /tmp/p; echo $?
//
// with prog.mc = `i64 main() { return $"<42 chars>"; }`: 42 here. The default
// compiler refuses the same source ("invalid hole"), because with nothing
// registered `$"` matches no token in the lexer. scripts/check-surface.sh does
// exactly that, and also proves the change is inert: with no module claiming
// `$`, --dump-ast and every object are byte for byte the pre-change compiler's.
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
