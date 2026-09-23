#!/bin/sh
# surface-extract.sh [KIND] — M53 step A: THE definition of mc's public surface.
#
# Prints `<kind><TAB><name>`, bytewise-sorted, for all seven kinds -- and for
# the `sym` kind `<kind><TAB><name><TAB><arity>`, the number of parameters the
# definition declares, because a public function's PARAMETER LIST is frozen too
# (docs/reference/hooks.md § 8): PR #92 gave the existing `cmp_cond` a second
# parameter and the inventory, which knew only names, said nothing. With a KIND
# argument (sym flag toml dir bundle lock machine) it prints that kind's names
# alone, one per line -- no arity column -- which is what
# scripts/check-docs.sh consumes.
#
# There is exactly one regex per kind and it lives here: check-docs.sh asks
# "is each one documented?" and check-freeze.sh asks "was each one here last
# time?", and two extractions that must agree are a bug waiting (M53 § 4.1,
# D11). Every list is extracted from the tree, never written down.
#
#   sym      a function a module outside src/ may call: src/*.mc definitions
#            whose name carries one of the 17 published prefixes, plus the
#            exact names no prefix reaches. val_reg/dst_reg/dst_done are three
#            of those: docs/reference/machine.md § 3 publishes them BY NAME as
#            the only three names of a machine's internals that are frozen, and
#            they matched nothing before M53 (§ 1.2a, D2). cmp_cond and
#            cmp_cond_of are two more: gen_walk.mc's answer to "is this token a
#            comparison", which a taught pass reads (the teko consumer does) and
#            which no prefix reaches either.
#            The 1.0.1 widening (the mc-php consumer's second report): a name
#            docs/reference/ documents as a CALLABLE is surface, whatever its
#            spelling. That is the 16 hooks.md § 4 itself calls "the parser's
#            public API. Fixed names" -- parse_expr/parse_stmt/parse_block/
#            parse_params/parse_function, top_add, def_add, param_new,
#            list_append, and the seven lex_* of § 6/§ 7 -- plus the <mc/core>
#            facilities no taught compiler can avoid: the nd_*/set_nd_* AST
#            accessors and node_new, tok_add, word_id, def_find/de_at/de_val,
#            path_join/path_norm, read_file, xalloc/xstrdup, str_eq, cstrlen,
#            err_at/err_at2. Documented internals stay out: lex_next,
#            lex_word_id and the lex_set_*_hook plumbing are named nowhere in
#            docs/reference/ and are not frozen (M53 § 8: a global or an
#            undocumented helper is not surface).
#            program_name/program_version and their readers prog_name/
#            prog_version are four more: the identity a taught compiler shipped
#            as its own binary registers, documented in hooks.md § 4 and reached
#            by no prefix. out_prog(), the stderr helper they feed, is named
#            nowhere in docs/reference/ and is not frozen.
#            The arity is counted from the definition's own parameter list:
#            0 for `()`, otherwise commas + 1.
#   flag     the literals inside a str_eq(x, "--flag") / opt_val(x, "--flag="),
#            plus -o.
#   toml     the toml_*("literal") lookups, plus the two table prefixes the
#            driver walks ([libs] and [externs] have user-chosen key names).
#   dir      the names in src/lex.mc's dir_index(), which IS the table.
#   bundle   a name `#include <…>` resolves: column 1 of tools/bundle.list.
#            One kind for the libraries AND the <mc/*> parts -- a part is named
#            exactly as a library is (D3).
#   lock     a key of an mc.lock or registry index row: the tm_cat(key, "…")
#            literals. A computed TOML path is invisible to the toml regex, so
#            this format was covered by nothing (D4).
#   machine  the machine task contract's version, one line, from the
#            `Contract version N` line of docs/reference/machine.md (D5).
#
# Run from the repository root.
LC_ALL=C
export LC_ALL

sym() {
    grep -hoE '^(void|i64|uptr|u8|u16|u32|u64) +((p_|syntax|type_|pass|backend|machine|sec_|sym_|reloc_add|gen_|on_|decl_|host_|intrinsic|walk_|subcommand|c_|nd_|set_nd_)[A-Za-z_0-9]*|parse_unary|parse_top|parse_expr|parse_stmt|parse_block|parse_params|parse_function|top_add|def_add|def_find|de_at|de_val|param_new|list_append|node_new|do_directive|lex_include|lex_file|lex_set_libs|lex_set_bundle|lex_root_of|lex_root_count|lex_root_name|lex_root_dir|lex_inc_count|lex_inc_at|tok_add|word_id|path_join|path_norm|read_file|xalloc|xstrdup|str_eq|cstrlen|err_at2|err_at|source_claim|program_name|program_version|prog_name|prog_version|val_reg|dst_reg|dst_done|cmp_cond_of|cmp_cond)\([^)]*\)' src/*.mc \
        | sed -E 's/^[a-z0-9]+ +//' \
        | awk -F'[()]' '{ n = $1; p = $2; gsub(/ /, "", p);
                          print n "\t" (p == "" ? 0 : gsub(/,/, ",", p) + 1) }'
}

flag() {
    grep -hoE '(str_eq\([a-z_]+, |opt_val\([a-z_]+, )"--[a-z][a-z-]*=?"' src/*.mc \
        | sed -E 's/.*("--[a-z][a-z-]*=?")/\1/' | tr -d '"'
    echo "-o"
}

toml() {
    grep -hoE 'toml_(get|get_array|count|int|bp|err_key)\("[a-z_.]+"' src/*.mc \
        | sed -E 's/.*"([a-z_.]+)"/\1/'
    grep -hoE 'opt_val\(toml_path_at\(i\), "[a-z_]+\."' src/*.mc \
        | sed -E 's/.*"([a-z_]+)\."/\1/'
}

dir() {
    grep -oE 'mem_eq\("[a-z]+", s,' src/lex.mc | sed -E 's/.*"([a-z]+)".*/\1/'
}

bundle() {
    cut -f1 tools/bundle.list | grep .
}

lock() {
    grep -hoE 'tm_cat\(key, "[a-z0-9]+"' src/pkg.mc src/tool.mc src/deps.mc \
        | sed -E 's/.*"([a-z0-9]+)"/\1/'
}

machine() {
    grep -oE 'Contract version [0-9]+' docs/reference/machine.md | head -1 \
        | sed -E 's/.* //'
}

case "$1" in
    sym) sym | cut -f1 | sort -u ;;
    flag|toml|dir|bundle|lock|machine) "$1" | sort -u ;;
    "")
        for k in sym flag toml dir bundle lock machine; do
            "$k" | sed "s/^/$k	/"
        done | sort -u
        ;;
    *) echo "usage: surface-extract.sh [sym|flag|toml|dir|bundle|lock|machine]" >&2; exit 2 ;;
esac
