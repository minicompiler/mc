// user_claim_nop.mc — a module whose only registration is source_claim, and
// whose handler claims every source. It is the inertness fixture for the hook,
// the shape lib/user_type_nop.mc has for syntax_type and lib/user_source_nop.mc
// for on_source: with the chain installed and answering 1 everywhere, a
// compiler has to produce exactly the tree and exactly the object a compiler
// without the hook produces. 1 is not "no handler registered" -- the callp
// happens, once per source pushed -- it is the handler claiming it.
i64 cn_claim(uptr name) { return 1; }

void user_init() {
    source_claim(&cn_claim);
}
