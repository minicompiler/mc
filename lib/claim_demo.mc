// claim_demo.mc — the two taught words the consumer's collision is about, and
// the source_claim handler that scopes them.
//
// `type` and `out` are ordinary identifiers in the compiler's own sources
// (`<mc/objmodel>` names a parameter `type`, `<mc/macho>` names one `out`), and
// a Tier 3 registration takes its word away from the WHOLE program. So a module
// that teaches either one could not compile the core it was built on until
// source_claim existed: the words apply in the sources the module claims, and
// nowhere else.
//
// Three modules share this file, and they differ by ONE registration:
//   lib/user_claim_demo.mc   the words + source_claim(".tk")   -- the scope
//   lib/user_claim_open.mc   the words alone                   -- the collision
//   lib/user_claim_none.mc   the words + a handler that claims nothing
// The third is the honest edge: a module that claims no source has taught the
// compiler nothing that any source can reach.

// ---- `type NAME NUMBER;` at the top level, as a #define ----
void cd_type() {
    i64 line = p_line();
    uptr fl = p_file();
    p_next();                                    // the `type` word
    uptr nm = p_ident();
    i64 v = p_val();
    p_expect(T_INT, "expected a number in type");
    p_expect(K_SEMI, "expected ; after type");
    def_add(nm, v, line, fl);
}

// ---- `out` in expression position: the constant 1 ----
i64 cd_out() {
    i64 line = p_line();
    uptr fl = p_file();
    p_next();                                    // the `out` word
    i64 n = node_new(N_INT, line, fl);
    set_nd_val(n, 1);
    set_nd_type(n, TY_I64);
    return n;
}

// ---- the claim ----
i64 cd_ends(uptr name, uptr suf) {
    i64 n = cstrlen(name);
    i64 m = cstrlen(suf);
    if (m > n) return 0;
    return mem_eq(name + n - m, suf, m);
}

// this dialect owns the `.tk` files and nothing else: a `#include "x.mc"` from
// one of them is read by the core's rules, which is the whole point
i64 cd_claim_tk(uptr name) { return cd_ends(name, ".tk"); }

// ...and a handler that claims nothing at all
i64 cd_claim_none(uptr name) { return 0; }

void cd_words() {
    syntax("type", &cd_type);                    // a word the core uses as a name
    syntax_expr("out", &cd_out);                 // ...and a second one
}
