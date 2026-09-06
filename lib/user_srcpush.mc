// user_srcpush.mc — an on_source handler that pushes a source from inside the
// callback. Broken on purpose: it is the fixture for the one guard the hook
// has.
//
// A handler is called with the frame it is being told about already on the
// stack. Pushing another source there interleaves the announcement of one
// source with the opening of the next, and a handler that pushes
// unconditionally recurses until the arena is gone -- with no diagnostic at
// all, since nothing else in the lexer would notice. lex_push_mem compares the
// frame depth across the call and refuses: `on_source handler pushed a source`.
uptr sp_rt[] = { "i64 sp_extra() { return 1; }\n" };

void sp_source(uptr name, uptr src, i64 len) {
    p_push_source("srcpush runtime", ld64(sp_rt), cstrlen(ld64(sp_rt)));
}

void user_init() {
    on_source(&sp_source);
}
