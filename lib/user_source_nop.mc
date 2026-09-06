// user_source_nop.mc — a module whose only registration is on_source, and whose
// handler does nothing at all with what it is told.
//
// It is the inertness fixture for the source hook, the same shape
// lib/user_type_nop.mc is for syntax_type and lib/user_param_nop.mc is for
// syntax_param: a compiler that announces every source it opens -- the entry at
// registration time, then every `#include`, every bundled name and every
// p_push_source -- has to produce exactly the tree, and exactly the object,
// that a compiler without the hook produces. The callp really happens; what the
// handler does with it is nothing.
i64 sn_seen = 0;

void sn_source(uptr name, uptr src, i64 len) {
    sn_seen = sn_seen + 1;
}

void user_init() {
    on_source(&sn_source);
}
