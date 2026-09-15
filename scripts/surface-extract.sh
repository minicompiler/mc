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
    grep -hoE '^(void|i64|uptr|u8|u16|u32|u64) +((p_|syntax|type_|pass|backend|machine|sec_|sym_|reloc_add|gen_|on_|decl_|host_|intrinsic|walk_|subcommand|c_)[A-Za-z_0-9]*|parse_unary|parse_top|do_directive|lex_include|source_claim|val_reg|dst_reg|dst_done|cmp_cond_of|cmp_cond)\([^)]*\)' src/*.mc \
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
