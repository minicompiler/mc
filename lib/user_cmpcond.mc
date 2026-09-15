// user_cmpcond.mc -- the consumer's shape: a module that asks the compiler
// "is this token a comparison?" with ONE argument.
//
// `cmp_cond(op)` is a public name (tests/golden/surface.txt), and this file is
// the gate that says so: PR #92 gave it a second parameter, and every module
// outside src/ that called it -- teko's typeof, verbatim the first function
// below -- stopped compiling with `wrong number of arguments`. A parameter list
// is part of the frozen surface (docs/reference/hooks.md § 8): the two-argument
// form got its own name, `cmp_cond_of`, and this file compiles again.
//
// The pass asserts the MEANING as well as the arity, so a `cmp_cond` restored
// with the wrong half of the table would fail here and not only in a consumer.

// teko_typeof.tk:318, transliterated -- the call that broke.
i64 cc_typeof(i64 op) {
    if (cmp_cond(op) >= 0) return TY_I64;
    return -1;
}

i64 cc_pass(i64 root) {
    if (cc_typeof(K_LT) != TY_I64) die("cmp_cond(K_LT) is not a comparison");
    if (cc_typeof(K_ADD) >= 0)     die("cmp_cond(K_ADD) is a comparison");
    if (cmp_cond(K_GE) != MCOND_GE) die("cmp_cond(K_GE) is not the signed condition");
    // the second half of the table is still reachable, under its own name
    if (cmp_cond_of(K_GE, 1) != MCOND_UGE) die("cmp_cond_of(K_GE, 1) is not the unsigned twin");
    return root;
}

void user_init() {
    pass(&cc_pass);
}
