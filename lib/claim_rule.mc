// claim_rule.mc — the second half of the source_claim collision: a taught word
// whose lexeme is ALSO the dispatch literal of a `#rule` from <prelude>.
//
// tok_add is idempotent per lexeme, so `syntax_stmt("while", ...)` marks the
// very token entry the prelude's `#rule stmt: while ( expr $c ) block $b`
// dispatches on. Before TE_RULE, that mark hid `while` in every source the
// module did not claim -- the core's own files included -- and the rule could
// never fire there: `while (i < 3) { ... }` lexed as an identifier followed by
// `(`.
//
// The module's `while` is deliberately NOT a loop: it runs the body at most
// once, so which one fired is a number and not a claim.

// while (c) { ... }  ->  if (c) { ... }, in the sources this module claims
i64 cr_while() {
    i64 line = p_line();
    uptr fl = p_file();
    p_next();                                    // the `while` word
    p_expect(K_LPAR, "expected ( after while");
    i64 c = parse_expr(0);
    p_expect(K_RPAR, "expected ) after while condition");
    i64 b = parse_block();
    i64 n = node_new(N_IF, line, fl);
    set_nd_a(n, c);
    set_nd_b(n, b);
    return n;
}

i64 cr_ends(uptr name, uptr suf) {
    i64 n = cstrlen(name);
    i64 m = cstrlen(suf);
    if (m > n) return 0;
    return mem_eq(name + n - m, suf, m);
}

// the same dialect boundary lib/claim_demo.mc draws: the `.tk` files and
// nothing else
i64 cr_claim_tk(uptr name) { return cr_ends(name, ".tk"); }
