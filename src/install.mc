// install.mc — `mc install`: the compiler's own package, on this disk (M44
// step 4, § B4 as amended by docs/specs/M48.md § 2.6).
//
// A compiler that carries no blob -- `mc-slim`, src/mc_slim.mc -- answers no
// `#include <name>` of its own. The names it does not ship come from the third
// step of the resolution order (docs/reference/packages.md § 2): the installed
// `mc` package, `<libs>/mc/v<mc_version()>/`, with `bundle.list` at its root as
// the NAME<TAB>PATH map. Putting that tree there is all this file does.
//
// M48 § 2.6 is what makes it short: the tree is the `mc` package as the
// registry already publishes it -- the tag archive, `strip = 1`, the
// [package].files list of the root mc.toml, hashed exactly as any other package
// -- so the fetch, the member check, the hash and the cache manifest are
// src/pkg.mc's and src/fetch.mc's, unchanged. There is no second archive and no
// hand-written member list. The one thing that is not a package's own doing is
// the copy of `tools/bundle.list` to the root of the tree, which is what
// src/deps.mc reads and what a repository checkout does not have there.
//
// Two roads, and the second one is the one a developer on a checkout takes:
//
//   mc install [VERSION]            the registry: the `mc` package's own index
//                                   row for exactly that version
//   mc install --from-tree DIR      a checkout: DIR/mc.toml's [package].files,
//                                   copied, hashed, blessed the same way
//
// VERSION defaults to mc_version(), which is the only version this binary's own
// `#include <name>` will ever read: the directory carries the version in its
// name on purpose (§ B4), so two compilers on one machine never share a tree.
//
// The reserved-name rule (src/deps.mc, dep_reserved) forbids `mc` in [deps], in
// [replace] and in `mc pkg add`: a project may not pin the compiler's own
// source, because <mc/core> IS the compiler that is running (M44 § A5). It does
// NOT apply here. This road installs the package for the binary itself, at the
// binary's own version, into a directory nothing else reads -- which is the one
// place where "the `mc` package" means what it says.
//
// It costs no global: everything it needs is a local, and the registry and the
// --yes flag live in src/pkg.mc's record already.

// `<libs>/mc/v<ver>/bundle.list`, from the copy of tools/bundle.list the tree
// carries. src/deps.mc (dp_mc_load) looks for it at the ROOT of the tree, and
// the repository keeps it under tools/ -- so the installed tree has both, and
// the root one is deliberately NOT in [package].files: it must not move the
// hash the registry published (M48 § 2.6).
void ins_bundle_list(uptr dir) {
    uptr from = tm_cat(dir, "tools/bundle.list");
    if (!lex_readable(from))
        dep_die("the mc package carries no tools/bundle.list", dir, 0);
    pkg_copy_file(from, tm_cat(dir, "bundle.list"));
}

// `mc 0.16.0 is installed (/home/x/.mc/libs/mc/v0.16.0/)`
void ins_say_installed(uptr ver, uptr dir) {
    out_str(1, "mc ");
    out_str(1, ver);
    out_str(1, " is installed (");
    out_str(1, dir);
    out_str(1, ")\n");
}

// ---- the checkout road ----
// The tree is copied through the same reader every other package goes through,
// so a [package].files entry that escapes is refused here exactly as it is in
// an archive (post-M44 review, finding 1), and the copy carries mc.toml plus
// the declared files and nothing else. The source is hashed BEFORE the copy and
// the copy is hashed after: a tree that does not hash to what the checkout
// hashes is not the checkout, and saying so costs two lines.
i64 ins_from_tree(uptr ver, uptr from) {
    uptr src = tm_cat(path_norm(from), "/");
    if (!lex_readable(tm_cat(src, "mc.toml")))
        pkg_die1("no mc.toml in", from);
    uptr frame = toml_push();
    toml_parse(tm_cat(src, "mc.toml"));
    uptr nm = toml_get("package.name");
    toml_pop(frame);
    if (nm == 0 || !str_eq(nm, "mc"))
        pkg_die1("not the mc package", from);
    uptr want = dep_hash_tree(src, -1);
    uptr dir = pkg_libs_dir("mc", ver);
    drv_mkdirs(tm_cat(dir, "x"));
    pkg_copy_tree(src, dir, pkg_what("mc", ver));
    uptr got = dep_hash_tree(dir, -1);
    if (!str_eq(got, want)) {
        pkg_unbless(dir);
        dep_die("the copy does not hash like the checkout", from, 0);
    }
    ins_bundle_list(dir);
    pkg_write_manifest("mc", ver, 0, got, dir);
    out_str(1, "package ");
    out_str(1, pkg_what("mc", ver));
    out_str(1, " -> ");
    out_str(1, dir);
    out_str(1, "\n");
    return 0;
}

// ---- the registry road ----
// One row of one index file, fetched by src/pkg.mc's own fetch: download,
// member check, extract, hash, compare, manifest -- in that order, with the
// tree unblessed and no manifest written if any of it refuses (M44 § 4).
i64 ins_from_registry(uptr ver) {
    if (str_eq(ver, mc_version()) && str_eq(ver, "0.0.0-dev"))
        dep_die("mc 0.0.0-dev is a development build: the registry publishes no such version",
                0, "mc install --from-tree .");
    if (!pkg_index_load("mc")) {
        pkg_print_plan();
        out_str(1, "nothing was downloaded: re-run with --yes\n");
        return 0;
    }
    i64 r = pkg_row("mc", ver);
    if (r < 0) pkg_die1("no such version of mc in the registry", ver);
    uptr row = pk_vr(r);
    if (ld64(row + VR_URL) == 0)
        pkg_die1(pkg_what("mc", ver), "the index row has no url");
    uptr dir = pkg_libs_dir("mc", ver);
    pkg_plan(pkg_what("mc", ver), ld64(row + VR_URL), ld64(row + VR_SHA), dir);
    pkg_print_plan();
    if (!pk_yes()) {
        out_str(1, "nothing was downloaded: re-run with --yes\n");
        return 0;
    }
    pkg_fetch_one("mc", ver, ld64(row + VR_URL), ld64(row + VR_STRIP),
                  ld64(row + VR_SHA));
    ins_bundle_list(dir);
    return 0;
}

void install_usage() {
    out_str(2, "usage: mc install [VERSION] [--from-tree DIR] [--yes] [--force] [--registry URL|DIR] [--libs-dir DIR]\n");
}

i64 install_cmd(i64 argc, uptr argv) {
    uptr ver = 0;
    uptr from = 0;
    i64 force = 0;
    i64 i = 2;
    while (i < argc) {
        uptr a = ld64(argv + i * 8);
        if (str_eq(a, "--yes")) pk_set_yes(1);
        else if (str_eq(a, "--force")) force = 1;
        else if (str_eq(a, "--from-tree")) {
            if (i + 1 >= argc) die("--from-tree requires an argument");
            i = i + 1;
            from = ld64(argv + i * 8);
        }
        else if (str_eq(a, "--registry")) {
            if (i + 1 >= argc) die("--registry requires an argument");
            i = i + 1;
            pk_set_registry(ld64(argv + i * 8));
        }
        else if (str_eq(a, "--libs-dir")) {
            if (i + 1 >= argc) die("--libs-dir requires an argument");
            i = i + 1;
            deps_set_libs_dir(ld64(argv + i * 8));
        }
        else if (ld8(a) == '-') {
            install_usage();
            return 1;
        }
        else if (ver == 0) ver = a;
        else               die2("too many arguments", a);
        i = i + 1;
    }
    if (ver == 0) ver = mc_version();
    // Already there means the cache manifest is there: a half-extracted
    // directory has none and is not a tree (src/pkg.mc, pkg_present).
    uptr dir = pkg_libs_dir("mc", ver);
    if (!force && lex_readable(pkg_libs_manifest("mc", ver))) {
        ins_say_installed(ver, dir);
        return 0;
    }
    if (from != 0) return ins_from_tree(ver, from);
    return ins_from_registry(ver);
}
