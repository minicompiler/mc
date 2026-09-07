// deps.mc — the READ side of packages (M44 § A1-A6, D12): `[deps]`, `mc.lock`,
// the tree hash, and what answers `#include <pack/file.mc>`.
//
// It lives in <mc/core_build> and not in <mc/core_pkg> on purpose: a compiler
// that will never fetch anything still has to BUILD a project from its lock and
// its `deps/` tree. That is the CI and consumer shape, and it is what makes
// "`mc build` never downloads" a property of the code and not of a promise --
// there is no downloader in this file.
//
// The three things it owns:
//
//   1. the name rule and the reserved names (`mc`, `deps`, `build`);
//   2. `mc.lock`: rows of (name, version, lib, sha256, deps), read, resolved to
//      a directory, and REHASHED on every build (D7, "checked, not trusted");
//   3. `libs_open`, the function pointer src/lex.mc calls for `<name>` -- stage
//      0 the lock road, stage 1 the installed `mc` package.
//
// Everything a package tree can say about itself is read through toml_push /
// toml_pop (M44 § 9): the project's own table is swapped out, the foreign file
// is parsed, what is needed is copied into the flat tables below -- name,
// version, hash, files, in source order, rule 1 of docs/determinism.md -- and
// the project's table comes back.
//
// Depends on arena.mc, sha256.mc, toml.mc, lex.mc and the host layer
// (host_home, host_include). Nothing here writes to <libs>: that is `mc pkg`.

// ---- exit codes ----
// 2 is "the environment is not ready" in the M25 sense: a lock that does not
// describe this tree, a package that was never fetched, a byte that moved. A
// script has to be able to tell it from "your program does not compile", which
// is 1 (docs/reference/cli.md § Exit codes).
void dep_die(uptr msg, uptr det, uptr run) {
    out_str(2, "mc: ");
    out_str(2, msg);
    if (det != 0) {
        out_str(2, ": ");
        out_str(2, det);
    }
    out_str(2, "\n");
    if (run != 0) {
        out_str(2, "  run:   ");
        out_str(2, run);
        out_str(2, "\n");
    }
    _exit(2);
}

// Escape a free-text value for a TOML basic string, so a value read from a
// fetched, attacker-controlled manifest cannot splice a second key or table
// into a file this compiler GENERATES -- the mc.lock, a cache manifest, or an
// install manifest. Without it, `[project].out = "app\"\n[tool]\npermissions =
// [...]\n#"` (tm_str decodes \" and \n) would write a second `[tool]` table
// into ~/.mc/tools/<name>/v<ver>.toml, and toml.mc has no duplicate-table check,
// so a spliced permission would then be read back and granted (M48 C3 review,
// finding 1). tm_str decodes exactly \n \t \r \" \\, so those are what is
// produced here; any other control byte (< 0x20, or DEL) is refused -- a
// generated manifest value is ASCII text and a raw control byte is malformed
// input, not something to smuggle through a doubled quote or a newline.
uptr toml_esc(uptr s) {
    u8 b[BUF_SIZE];
    buf_init(b);
    i64 i = 0;
    loop {
        i64 c = ld8(s + i);
        if (c == 0) break;
        if (c == '\\')      { buf_u8(b, '\\'); buf_u8(b, '\\'); }
        else if (c == '"')  { buf_u8(b, '\\'); buf_u8(b, '"'); }
        else if (c == '\n') { buf_u8(b, '\\'); buf_u8(b, 'n'); }
        else if (c == '\t') { buf_u8(b, '\\'); buf_u8(b, 't'); }
        else if (c == '\r') { buf_u8(b, '\\'); buf_u8(b, 'r'); }
        else if (c < 32 || c == 127) {
            dep_die("a control byte in a value written to a manifest", s, 0);
        } else {
            buf_u8(b, c);
        }
        i = i + 1;
    }
    buf_u8(b, 0);
    return buf_p(b);
}

// ---- the name rule (§ 1) ----
// [a-z][a-z0-9_]*, at most 32 bytes: a bare TOML key, a valid path component on
// all three hosts, and a valid identifier prefix (`geo_init`). Upper case and
// `-` are out so that one spelling is the only spelling.
#define DEP_NAMEMAX 32

i64 dep_name_ok(uptr s) {
    i64 c = ld8(s);
    if (c < 'a' || c > 'z') return 0;
    i64 i = 1;
    loop {
        c = ld8(s + i);
        if (c == 0) break;
        if (i >= DEP_NAMEMAX) return 0;
        if ((c < 'a' || c > 'z') && (c < '0' || c > '9') && c != '_') return 0;
        i = i + 1;
    }
    return 1;
}

// `mc` is the compiler's own package and can never be pinned by a lock: <mc/core>
// is the source of the compiler that is RUNNING, and a taught compiler assembled
// from a foreign one would not be the compiler that built it (A5). `deps` and
// `build` are directories `mc build` writes.
i64 dep_reserved(uptr s) {
    if (str_eq(s, "mc")) return 1;
    if (str_eq(s, "deps")) return 1;
    if (str_eq(s, "build")) return 1;
    return 0;
}

// refuses at the key's own file:line:col, through the project's table
void dep_check_name(uptr section, uptr name) {
    uptr key = tm_cat(section, name);
    if (dep_reserved(name)) toml_err_key(key, "reserved package name");
    if (!dep_name_ok(name)) toml_err_key(key, "invalid package name");
}

// ---- semver (§ 3) ----
// X.Y.Z, and -- since the ops patch of 0.15.1 -- the OPTIONAL pre-release
// suffix SemVer 2.0 § 9 and § 11 describe. The rule, in full:
//
//   * the three numeric fields decide first, as they always did;
//   * a version WITH a pre-release suffix is LOWER than the same X.Y.Z without
//     one -- `1.2.0-rc1 < 1.2.0`, which is what makes a release candidate a
//     candidate and not a release;
//   * two suffixes compare identifier by identifier, dot separated: an
//     all-digit identifier ranks below an alphanumeric one and compares by
//     value, anything else compares byte for byte, and when everything so far
//     is equal the shorter list is the lower one (`1.0.0-rc < 1.0.0-rc.1`);
//   * `+build` metadata is ignored, as the specification requires.
//
// C4 survives and is sharper than before: `0.0.0-dev`, what scripts/set-version.sh
// writes into an unreleased tree, used to compare EQUAL to 0.0.0 and merely
// below 0.0.1; it now compares below 0.0.0 as well, so every release is newer
// than a dev build for the same reason SemVer says so.
// scripts/next-version.sh --gt still compares the numeric core only: it is fed
// git tags, which are releases.
i64 ver_field(uptr s, uptr pi) {
    i64 i = ld64(pi);
    i64 v = 0;
    loop {
        i64 c = ld8(s + i);
        if (c < '0' || c > '9') break;
        v = v * 10 + (c - '0');
        i = i + 1;
    }
    if (ld8(s + i) == '.') i = i + 1;
    st64(pi, i);
    return v;
}

// The pre-release of a version: the bytes after the first `-`, or 0 when there
// is none. A `+` before any `-` means the version carries build metadata and no
// pre-release (`1.2.0+abc-1` is a build, not a candidate).
uptr ver_pre(uptr s) {
    i64 i = 0;
    loop {
        i64 c = ld8(s + i);
        if (c == 0 || c == '+') return 0;
        if (c == '-') return s + i + 1;
        i = i + 1;
    }
}

// its length: up to the `+` that opens build metadata, or to the end
i64 ver_pre_len(uptr p) {
    i64 i = 0;
    loop {
        i64 c = ld8(p + i);
        if (c == 0 || c == '+') break;
        i = i + 1;
    }
    return i;
}

// 1 when this version is a pre-release. This is the whole gate `mc pkg add` and
// `mc update` consult (src/pkg.mc, pkg_newest): a candidate is never chosen for
// you, only asked for by name.
i64 ver_is_pre(uptr s) { return ver_pre(s) != 0; }

// one dot-separated identifier of a suffix, bounded by n
i64 ver_id_len(uptr p, i64 n) {
    i64 i = 0;
    while (i < n) {
        if (ld8(p + i) == '.') break;
        i = i + 1;
    }
    return i;
}

// 1 when every byte of the identifier is a digit (an empty one is not)
i64 ver_id_num(uptr p, i64 n) {
    if (n == 0) return 0;
    i64 i = 0;
    while (i < n) {
        i64 c = ld8(p + i);
        if (c < '0' || c > '9') return 0;
        i = i + 1;
    }
    return 1;
}

i64 ver_id_cmp(uptr a, i64 na, uptr b, i64 nb) {
    i64 da = ver_id_num(a, na);
    i64 db = ver_id_num(b, nb);
    if (da && !db) return -1;             // numeric ranks below alphanumeric
    if (!da && db) return 1;
    uptr pa = a;
    uptr pb = b;
    i64 la = na;
    i64 lb = nb;
    if (da && db) {                       // by value: SemVer forbids leading
        while (la > 1 && ld8(pa) == '0') {  // zeros, so strip them and compare
            pa = pa + 1;                    // length first, then bytes
            la = la - 1;
        }
        while (lb > 1 && ld8(pb) == '0') {
            pb = pb + 1;
            lb = lb - 1;
        }
        if (la < lb) return -1;
        if (la > lb) return 1;
    }
    i64 n = la;
    if (lb < n) n = lb;
    i64 i = 0;
    while (i < n) {
        i64 x = ld8(pa + i);
        i64 y = ld8(pb + i);
        if (x < y) return -1;
        if (x > y) return 1;
        i = i + 1;
    }
    if (la < lb) return -1;               // a prefix is lower than what extends it
    if (la > lb) return 1;
    return 0;
}

i64 ver_pre_cmp(uptr a, i64 na, uptr b, i64 nb) {
    i64 ia = 0;
    i64 ib = 0;
    loop {
        if (ia >= na && ib >= nb) return 0;
        if (ia >= na) return -1;          // fewer identifiers is lower
        if (ib >= nb) return 1;
        i64 la = ver_id_len(a + ia, na - ia);
        i64 lb = ver_id_len(b + ib, nb - ib);
        i64 c = ver_id_cmp(a + ia, la, b + ib, lb);
        if (c != 0) return c;
        ia = ia + la + 1;
        ib = ib + lb + 1;
    }
}

i64 ver_cmp(uptr a, uptr b) {
    i64 ia = 0;
    i64 ib = 0;
    i64 k = 0;
    while (k < 3) {
        i64 x = ver_field(a, &ia);
        i64 y = ver_field(b, &ib);
        if (x < y) return -1;
        if (x > y) return 1;
        k = k + 1;
    }
    uptr pa = ver_pre(a);
    uptr pb = ver_pre(b);
    if (pa == 0 && pb == 0) return 0;
    if (pa == 0) return 1;                // a release outranks its candidates
    if (pb == 0) return -1;
    return ver_pre_cmp(pa, ver_pre_len(pa), pb, ver_pre_len(pb));
}

i64 ver_major(uptr a) {
    i64 i = 0;
    return ver_field(a, &i);
}

// A version string that is about to become a filesystem path component:
// <libs>/<name>/v<version>/ and ~/.mc/tools/<name>/v<version>/. SemVer's charset
// and nothing else -- [0-9A-Za-z.+_-], non-empty, at most 64 bytes, no leading
// dot and no `..` anywhere -- so `version = "../../../../tmp/evil"` cannot stage
// or build a tree outside the package root. `/` and the backslash are excluded
// by the charset. This predates M48 (a crafted [[versions]].version reaches a
// path through `mc pkg sync`/`add` and `mc tool install`), and it is the one
// gate between a registry string and a path (M48 C3 review, finding 3).
i64 dep_ver_ok(uptr v) {
    i64 n = cstrlen(v);
    if (n == 0 || n > 64) return 0;
    if (ld8(v) == '.') return 0;
    i64 i = 0;
    while (i < n) {
        i64 c = ld8(v + i);
        i64 ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z')
                 || (c >= 'A' && c <= 'Z')
                 || c == '.' || c == '+' || c == '_' || c == '-';
        if (!ok) return 0;
        if (c == '.' && i + 1 < n && ld8(v + i + 1) == '.') return 0;
        i = i + 1;
    }
    return 1;
}

// The belt-and-braces guard the four path builders (pkg_libs_dir/manifest,
// tool_dir/manifest_path) call the instant a version becomes a path, whatever
// its source -- a registry row, a lock, or the installed index -- so that no
// road reaches a path with a version dep_ver_ok would refuse.
uptr dep_ver_path(uptr v) {
    if (!dep_ver_ok(v)) dep_die("a version is not usable as a path", v, 0);
    return v;
}

// ---- the state: one arena record, so this file costs two globals ----
#define DP_APPLIED  0                 // 1 once deps_apply has run
#define DP_NPKG     8
#define DP_PKG      16                // PK_SIZE records, in lock order
#define DP_NFILE    24
#define DP_FILECAP  32
#define DP_FILE     40                // FL_SIZE records
#define DP_MCTRIED  48                // 1 once bundle.list was looked for
#define DP_MCN      56
#define DP_MCNAME   64                // uptr per entry
#define DP_MCPATH   72                // uptr per entry
#define DP_MCDIR    80                // <libs>/mc/v<version>/
// Post-M44 review, finding 5: a tree that is being FETCHED is refused with the
// directory still on the disk, so the refusal has to come back to pkg_fetch_one
// -- which unblesses first and dies afterwards -- instead of leaving through
// _exit() from inside the hash. In soft mode dep_soft_die records the first
// problem here and the hash answers 0; everywhere else it is dep_die, as it was.
#define DP_SOFT     88
#define DP_ERRMSG   96
#define DP_ERRDET   104
#define DP_LABEL    112               // what to call a tree nobody locked yet
#define DP_SIZE     120

#define PK_NAME 0
#define PK_VER  8
#define PK_HASH 16                    // the lock's tree hash, 0 when replaced
#define PK_LIB  24                    // what a bare `<pack>` means, 0 when none
#define PK_DIR  32                    // resolved, normalised, trailing '/'
#define PK_MAN  40                    // the cache manifest, 0 when vendored
// M48 § 4.3: what the lock records beyond the tree. `kind` is written only for
// a tool, so 0 here means `lib` and every lock written before this milestone
// reads as one; `permissions` is the set the developer ACCEPTED, in canonical
// form (§ 1.4), and a row without the key is an empty accepted set.
#define PK_KIND  48
#define PK_NPERM 56
#define PK_PERMS 64                   // uptr per entry, sorted
// The index of this package's include root, or -1 for a tool: a tool is not
// compiled into the consumer, so it registers no root at all (§ 4.3) and the
// two tables stop being parallel the moment one row is a tool.
#define PK_ROOT  72
#define PK_SIZE  80

#define FL_PKG  0
#define FL_NAME 8
#define FL_SIZE 16

uptr dp = 0;                          // the record above
uptr dp_libs_opt = 0;                 // --libs-dir DIR

uptr dp_state() {
    if (dp == 0) dp = xalloc(DP_SIZE);
    return dp;
}

i64  dp_npkg()          { return ld64(dp_state() + DP_NPKG); }
uptr dp_at(i64 i)       { return ld64(dp_state() + DP_PKG) + i * PK_SIZE; }
uptr dp_name(i64 i)     { return ld64(dp_at(i) + PK_NAME); }
uptr dp_ver(i64 i)      { return ld64(dp_at(i) + PK_VER); }
uptr dp_hash(i64 i)     { return ld64(dp_at(i) + PK_HASH); }
uptr dp_lib(i64 i)      { return ld64(dp_at(i) + PK_LIB); }
uptr dp_dir(i64 i)      { return ld64(dp_at(i) + PK_DIR); }
uptr dp_man(i64 i)      { return ld64(dp_at(i) + PK_MAN); }
// absent in the lock means `lib`, which is what every row written before M48
// says and what every library says now
uptr dp_kind(i64 i) {
    uptr k = ld64(dp_at(i) + PK_KIND);
    if (k == 0) return "lib";
    return k;
}
i64  dp_is_tool(i64 i)      { return str_eq(dp_kind(i), "tool"); }
i64  dp_nperm(i64 i)        { return ld64(dp_at(i) + PK_NPERM); }
// how many rows are trees this build reads: `verify` and `vendor` count what
// they touched, and a tool is not one of them
i64 dp_nlib() {
    i64 n = 0;
    i64 i = 0;
    while (i < dp_npkg()) {
        if (!dp_is_tool(i)) n = n + 1;
        i = i + 1;
    }
    return n;
}
uptr dp_perm(i64 i, i64 j)  { return ld64(ld64(dp_at(i) + PK_PERMS) + j * 8); }

// the package's directory and the lexer's root for it are one value written in
// two places: the record is what libs_open joins against, the root is what
// lex_root_of matches a path against.
void dp_set_dir(i64 i, uptr dir) {
    // NORMALISED, once, here: lex_root_of compares the root against paths that
    // came out of path_join, which normalises. A --libs-dir the caller wrote
    // with a `//` in it (macOS TMPDIR ends in `/`) would otherwise be a prefix
    // of nothing and the closure rule would silently never fire.
    dir = tm_cat(path_norm(dir), "/");
    st64(dp_at(i) + PK_DIR, dir);
    // M48: a tool row has no root (PK_ROOT is -1) -- nothing it carries is
    // included by anything, so there is nothing to attribute a path to.
    i64 r = ld64(dp_at(i) + PK_ROOT);
    if (r >= 0) lex_set_root_dir(r, dir);
}

i64 dp_find(uptr name) {
    i64 i = 0;
    while (i < dp_npkg()) {
        if (str_eq(dp_name(i), name)) return i;
        i = i + 1;
    }
    return -1;
}

// `geo` out of `geo/vec.mc`, or the whole name when there is no '/'
uptr dep_first(uptr name) {
    i64 n = 0;
    loop {
        i64 c = ld8(name + n);
        if (c == 0 || c == '/') break;
        n = n + 1;
    }
    return xstrdup(name, n);
}

// The file table doubles inside this file instead of going through arena.mc's
// grow(): it is not a compiler table. Its size is the LOCK's -- the developer
// wrote it -- so a growth event carries no information anybody could act on,
// which is the whole point of a `mc limits` row (M23).
void dp_add_file(i64 pk, uptr name) {
    uptr s = dp_state();
    i64 n = ld64(s + DP_NFILE);
    i64 cap = ld64(s + DP_FILECAP);
    if (n >= cap) {
        i64 nc = cap * 2;
        if (nc < 16) nc = 16;
        uptr np = xalloc(nc * FL_SIZE);
        mem_copy(np, ld64(s + DP_FILE), n * FL_SIZE);
        st64(s + DP_FILE, np);
        st64(s + DP_FILECAP, nc);
    }
    uptr e = ld64(s + DP_FILE) + n * FL_SIZE;
    st64(e + FL_PKG, pk);
    st64(e + FL_NAME, name);
    st64(s + DP_NFILE, n + 1);
}

i64 dp_has_file(i64 pk, uptr name) {
    uptr s = dp_state();
    i64 n = ld64(s + DP_NFILE);
    i64 i = 0;
    while (i < n) {
        uptr e = ld64(s + DP_FILE) + i * FL_SIZE;
        if (ld64(e + FL_PKG) == pk && str_eq(ld64(e + FL_NAME), name)) return 1;
        i = i + 1;
    }
    return 0;
}

// ---- containment: what a package may name (post-M44 review, finding 1) ----
// Every path in [package].files is attacker-controlled: it comes out of the
// mc.toml of a tree that was downloaded from a registry row, and it is then
// opened (the tree hash, on EVERY build), copied (`mc pkg vendor`), hashed into
// a manifest and -- before this batch -- unlinked (`pkg_unbless`). Nothing
// checked it, so `files = ["../../../../.ssh/id_rsa"]` read the developer's key
// and `mc pkg vendor` wrote a payload outside the project.
//
// The rule, stated once and applied at every consumer: a files entry is a
// RELATIVE path made of ordinary components. No leading `/`, no `.` and no `..`
// component, no empty component, no backslash (a Windows separator is not a
// component separator here, and letting one through would make the same name
// mean two things on two hosts), and no byte below 0x20 -- which also removes
// the newline that made the hash lines forgeable (finding 3).
//
// `dirok` allows the ONE extra shape an archive member has and a files entry
// never does: a trailing `/`, which is how tar spells a directory.
i64 dep_rel_ok(uptr rel, i64 dirok) {
    i64 n = cstrlen(rel);
    if (n == 0) return 0;
    if (ld8(rel) == '/') return 0;                // absolute
    i64 i = 0;
    while (i < n) {
        i64 c = ld8(rel + i);
        if (c < 32) return 0;                     // control byte, LF included
        if (c == 92) return 0;                    // backslash
        // the characters Windows reserves in a name: `:` (a drive letter, an
        // NTFS stream), `<`, `>`, `"`, `|`, `?`, `*` -- a tar member `C:/x` is
        // absolute to a Windows extractor, and the rule is one rule for the
        // three hosts (Copilot's review of #27)
        if (c == ':' || c == '<' || c == '>' || c == '"' || c == '|' || c == '?' || c == '*') return 0;
        i = i + 1;
    }
    i64 b = 0;
    i = 0;
    loop {
        if (i > n) break;
        if (i == n || ld8(rel + i) == '/') {
            i64 l = i - b;
            // an empty component is `//` or a trailing `/`; the second is a
            // directory member and only an archive may have one
            if (l == 0 && !(dirok && i == n && b > 0)) return 0;
            if (l == 1 && ld8(rel + b) == '.') return 0;
            if (l == 2 && ld8(rel + b) == '.' && ld8(rel + b + 1) == '.') return 0;
            b = i + 1;
        }
        i = i + 1;
    }
    return 1;
}

// The same question asked of the filesystem's own arithmetic, so that a rule
// the component walk somehow let through still cannot escape: the normalised
// join has to start with the normalised directory plus a separator. Belt and
// braces on purpose -- this is the check that would survive a future path_norm.
i64 dep_under(uptr dir, uptr rel) {
    uptr nd = path_norm(dir);
    uptr p = path_join(tm_cat(nd, "/"), rel);     // path_join normalises
    // path_norm answers "." for a directory with no segments -- `.`, `./`,
    // `a/..` -- and path_join then DROPS that segment from the result, so the
    // join of a contained entry does not start with "./" and the prefix test
    // below refused every entry of a package named as `.`. `mc pkg hash .` was
    // `files entry escapes the package: <first entry>`, exit 2, for any package
    // at all. The containment question for that base is the one dep_rel_ok has
    // already answered plus "the join did not become absolute".
    if (str_eq(nd, ".")) return cstrlen(p) > 0 && ld8(p) != '/';
    uptr base = tm_cat(nd, "/");
    i64 n = cstrlen(base);
    if (cstrlen(p) <= n) return 0;
    return mem_eq(p, base, n);
}

// ---- M48 § 1: what a package says about itself, beyond its files ----
// Three questions a manifest answers, read HERE and nowhere else so that the
// lock writer (`mc pkg sync`) and the registry gate (`mc pkg check`) cannot
// drift apart: what KIND of package this is, what its binary is called, and
// which permissions it asks for. Each of them reads the table the caller has
// already parsed (toml_push / toml_parse / toml_pop), so every refusal comes
// out at the offending key's own file:line:col -- inside the PACKAGE's mc.toml,
// which is the file that got it wrong.
//
// The compiler does not enforce a permission: it reads it, prints it, records
// what was accepted, and refuses a manifest that says something it cannot mean.
// Enforcement is `mc tool run`'s box (M48 C3) and, for a library, nothing at
// all -- a library runs inside your program (§ 4.4).

// bytewise `a < b`: the total order every set written into a lock, a plan or an
// index row is sorted by (rule 2 of docs/determinism.md -- a total order over
// unique keys, so there is no tie to break).
i64 dep_str_lt(uptr a, uptr b) {
    i64 i = 0;
    loop {
        i64 x = ld8(a + i);
        i64 y = ld8(b + i);
        if (x != y) return x < y;
        if (x == 0) return 0;
        i = i + 1;
    }
}

// At most 32 rows: a set a person reads at an install prompt, not a policy
// file. The bound is the manifest's, not the lock's -- the lock only ever
// carries what a manifest declared.
#define DEP_MAXPERM 32

// `[package].bin` (§ 1.2): [a-z][a-z0-9_-]*, at most 32 bytes. A hyphen is
// allowed here and in no other name, because this is a FILE name in ~/.mc/bin
// (`mc-lsp`) and not an identifier.
i64 dep_bin_ok(uptr s) {
    i64 c = ld8(s);
    if (c < 'a' || c > 'z') return 0;
    i64 i = 1;
    loop {
        c = ld8(s + i);
        if (c == 0) break;
        if (i >= DEP_NAMEMAX) return 0;
        if ((c < 'a' || c > 'z') && (c < '0' || c > '9') && c != '_' && c != '-') return 0;
        i = i + 1;
    }
    return 1;
}

// A permission path (§ 1.4). No absolute path is ever accepted: the registry
// cannot verify one, it leaks a host's layout into a published manifest, and
// the box cannot promise what it would map to. The four forms are `workspace`,
// `tmp`, `workspace/<rel>` and `home/<rel>`, and `<rel>` is dep_rel_ok's --
// ONE containment rule for every path in every manifest.
i64 dep_perm_path_ok(uptr p) {
    if (str_eq(p, "workspace")) return 1;
    if (str_eq(p, "tmp")) return 1;
    uptr rel = opt_val(p, "workspace/");
    if (rel == 0) rel = opt_val(p, "home/");
    if (rel == 0) return 0;
    return dep_rel_ok(rel, 0);
}

// The `name` of an `exec` or `env` row: a program's basename or a variable's
// name. A space is what makes this a rule and not taste -- the canonical form
// is `<kind> <name>` on one line, so a name carrying a space would be two
// permissions to a reader and one to a comparison.
i64 dep_perm_word_ok(uptr s) {
    i64 n = cstrlen(s);
    if (n == 0 || n > 64) return 0;
    i64 i = 0;
    while (i < n) {
        i64 c = ld8(s + i);
        if ((c < 'a' || c > 'z') && (c < 'A' || c > 'Z') && (c < '0' || c > '9')
            && c != '_' && c != '.' && c != '-') return 0;
        i = i + 1;
    }
    return 1;
}

uptr dep_perm_key(i64 i, uptr k) {
    return tm_cat(tm_cat(tm_cat("permission.", tm_num_str(i)), "."), k);
}

// One row, as the canonical one-liner the lock, the index and the install table
// all carry: `fs.read workspace`, `fs.write workspace/build`, `net`, `exec mc`,
// `env HOME`. `reason` is read only to bound it: it is shown, never compared,
// and never hashed into a decision (§ 1.4).
uptr dep_perm_line(i64 i) {
    uptr kkey = dep_perm_key(i, "kind");
    uptr kind = toml_get(kkey);
    if (kind == 0) toml_err_key(kkey, "missing key");
    uptr pkey = dep_perm_key(i, "path");
    uptr nkey = dep_perm_key(i, "name");
    uptr path = toml_get(pkey);
    uptr name = toml_get(nkey);
    uptr rkey = dep_perm_key(i, "reason");
    uptr reason = toml_get(rkey);
    if (reason != 0 && cstrlen(reason) > 120)
        toml_err_key(rkey, "a permission reason is at most 120 bytes");
    // the kind decides everything else, so it is asked first: `fs.delete` is
    // an unknown KIND, not a kind that takes no path
    i64 isfs = str_eq(kind, "fs.read") || str_eq(kind, "fs.write");
    i64 isword = str_eq(kind, "exec") || str_eq(kind, "env");
    if (!isfs && !isword && !str_eq(kind, "net"))
        toml_err_key(kkey, "a permission kind is fs.read, fs.write, net, exec or env");
    if (isfs) {
        if (name != 0) toml_err_key(nkey, "a fs permission takes a path, not a name");
        if (path == 0) toml_err_key(kkey, tm_cat(kind, " needs a path"));
        if (!dep_perm_path_ok(path))
            toml_err_key(pkey, "a permission path is workspace, tmp, workspace/<rel> or home/<rel>");
        return tm_cat(tm_cat(kind, " "), path);
    }
    if (path != 0) toml_err_key(pkey, tm_cat(kind, " takes no path"));
    if (isword) {
        if (name == 0) toml_err_key(kkey, tm_cat(kind, " needs a name"));
        if (!dep_perm_word_ok(name)) toml_err_key(nkey, "invalid permission name");
        return tm_cat(tm_cat(kind, " "), name);
    }
    if (name != 0) toml_err_key(nkey, "net takes no name");
    return "net";
}

// The whole set of the manifest already parsed: canonical, duplicates
// collapsed, sorted bytewise. The array comes back through `pout` and the count
// is the answer, which is dep_read_files' shape.
i64 dep_read_perms(uptr pout) {
    i64 n = toml_occurrences("permission");
    if (n > DEP_MAXPERM)
        toml_err_key(dep_perm_key(DEP_MAXPERM, "kind"), "at most 32 [[permission]] rows");
    uptr set = xalloc(n * 8 + 8);
    i64 m = 0;
    i64 i = 0;
    while (i < n) {
        uptr line = dep_perm_line(i);
        i64 dup = 0;
        i64 j = 0;
        while (j < m) {
            if (str_eq(ld64(set + j * 8), line)) dup = 1;
            j = j + 1;
        }
        if (!dup) {
            st64(set + m * 8, line);
            m = m + 1;
        }
        i = i + 1;
    }
    i = 1;
    while (i < m) {                             // insertion sort, unique keys
        i64 k = i;
        while (k > 0 && dep_str_lt(ld64(set + k * 8), ld64(set + (k - 1) * 8))) {
            uptr t = ld64(set + k * 8);
            st64(set + k * 8, ld64(set + (k - 1) * 8));
            st64(set + (k - 1) * 8, t);
            k = k - 1;
        }
        i = i + 1;
    }
    st64(pout, set);
    return m;
}

// Re-validate a CANONICAL permission line -- `fs.read workspace`, `fs.write
// workspace/build`, `net`, `exec sh`, `env HOME` -- the shape the lock and the
// install manifest store. It is the inverse of what dep_perm_line produces:
// 1 exactly when this compiler could have written the line from a valid
// [[permission]] row. `mc tool run` runs it over every permission it reads back
// from the install manifest before mapping any to a sandbox flag (M48 C3 review,
// finding 2): a hand-edited or spliced manifest must never grant more than a
// syntactically valid, `..`-free, containment-checked line, and no unrecognized
// string may fall through to "the whole workspace, writable".
i64 dep_perm_line_ok(uptr line) {
    if (str_eq(line, "net")) return 1;
    uptr p = opt_val(line, "fs.read ");
    if (p == 0) p = opt_val(line, "fs.write ");
    if (p != 0) return dep_perm_path_ok(p);
    uptr w = opt_val(line, "exec ");
    if (w == 0) w = opt_val(line, "env ");
    if (w != 0) return dep_perm_word_ok(w);
    return 0;
}

// the index of the first `[project]` key of the manifest already parsed, -1
i64 dep_project_at() {
    i64 i = 0;
    while (i < toml_entries()) {
        if (opt_val(toml_path_at(i), "project.") != 0) return i;
        i = i + 1;
    }
    return -1;
}

// The kind rule (§ 1.1), in one place: no `[project]` at all -- which is every
// manifest published or fixtured before M48 -- is a library; `kind = "obj"` is
// a library that also builds an object of its own; `kind = "exe"` is a tool.
// A `[project]` with NO kind is refused, because `mc build` defaults it to
// `exe` and a library carrying a `[project]` for its own tests would otherwise
// be classified as a tool in silence.
uptr dep_kind_of() {
    i64 pi = dep_project_at();
    if (pi < 0) return "lib";
    uptr k = toml_get("project.kind");
    if (k == 0)
        toml_err_at(pi, "a package's [project] must say kind = \"obj\" or \"exe\"");
    if (str_eq(k, "obj")) return "lib";
    if (str_eq(k, "exe")) return "tool";
    toml_err_key("project.kind", "a package's [project] must say kind = \"obj\" or \"exe\"");
    return 0;
}

// `[package].bin`, checked; 0 when the manifest does not name one.
uptr dep_bin_of() {
    uptr b = toml_get("package.bin");
    if (b != 0 && !dep_bin_ok(b)) toml_err_key("package.bin", "invalid binary name");
    return b;
}

// `geo 1.2.0` for a locked package, the directory for a tree nobody locked
// (`mc pkg hash DIR`, and every tree `mc pkg sync` unpacks).
uptr dep_pkg_what(i64 pk, uptr dir) {
    if (pk >= 0) return tm_cat(tm_cat(dp_name(pk), " "), dp_ver(pk));
    uptr lab = ld64(dp_state() + DP_LABEL);
    if (lab != 0) return lab;
    return dir;
}

// `mc pkg sync` knows the name and version of the tree it has just unpacked
// before any lock does; without this a refusal would name the cache directory.
void dep_hash_label(uptr w) { st64(dp_state() + DP_LABEL, w); }

// The refusal, or the recorded error in soft mode (finding 5).
void dep_soft_die(uptr msg, uptr det) {
    uptr s = dp_state();
    if (ld64(s + DP_SOFT)) {
        if (ld64(s + DP_ERRMSG) == 0) {
            st64(s + DP_ERRMSG, msg);
            st64(s + DP_ERRDET, det);
        }
        return;
    }
    dep_die(msg, det, 0);
}

void dep_hash_soft(i64 on) {
    uptr s = dp_state();
    st64(s + DP_SOFT, on);
    st64(s + DP_ERRMSG, 0);
    st64(s + DP_ERRDET, 0);
    if (!on) st64(s + DP_LABEL, 0);
}

uptr dep_hash_err()    { return ld64(dp_state() + DP_ERRMSG); }
uptr dep_hash_errdet() { return ld64(dp_state() + DP_ERRDET); }

// `mc: geo 1.2.0: files entry escapes the package: ../../../../.ssh/id_rsa`
void dep_file_check(uptr dir, uptr rel, uptr what) {
    if (dep_rel_ok(rel, 0) && dep_under(dir, rel)) return;
    dep_soft_die(tm_cat(what, ": files entry escapes the package"), rel);
}

// ---- the tree hash (D5) ----
// Go's dirhash.Hash1 in plain hex: for `mc.toml` first and then each entry of
// [package].files IN MANIFEST ORDER, one line
//
//     <64 hex of sha256(file bytes)><space><decimal length><colon><path><LF>
//
// The path is LENGTH-PREFIXED (post-M44 review, finding 3). The original shape
// was `<hex><two spaces><path><LF>`, which is Go's dirhash.Hash1 verbatim and
// is not injective: a path carrying a newline writes two lines and the hash
// cannot tell which file list produced them. Go can afford it because its file
// list comes out of a zip it built; here the list is an attacker-controlled
// array in a downloaded mc.toml. A control byte in a files entry is refused
// outright now (dep_rel_ok), so the primitive is gone either way -- the length
// prefix is what makes the FORMAT unable to represent the ambiguity at all.
// scripts/pkg-hash.sh writes the same lines; check-pkg compares the two.
//
// and the tree hash is sha256 of those lines. Content only: no mtime, no mode,
// no directory listing (mc has no opendir -- the author lists the files, which
// is also the vendor-copy list and the build-time boundary), and the bytes are
// taken exactly as they are on disk, LF or CRLF, so a checkout that translates
// line endings changes the hash and says so (.gitattributes `-text`).
// The hex printer and the per-file digest are src/sha256.mc's since M44 step 3
// (hex64, sha256_file): three files print a digest and one of them is a
// fetcher, so the spelling lives beside the function that produces the bytes.

// `dir` carries its trailing '/', so path_join treats it as a directory
uptr dep_in(uptr dir, uptr rel) { return path_join(dir, rel); }

void dep_line(uptr b, uptr dir, uptr rel) {
    uptr p = dep_in(dir, rel);
    if (!lex_readable(p)) {
        dep_soft_die("a file the package lists is missing", p);
        return;
    }
    uptr ln = tm_num_str(cstrlen(rel));
    buf_put(b, sha256_file(p), 64);
    buf_u8(b, ' ');
    buf_put(b, ln, cstrlen(ln));
    buf_u8(b, ':');
    buf_put(b, rel, cstrlen(rel));
    buf_u8(b, '\n');
}

// ---- reading [package].files, once, with every entry checked ----
// The ONE reader of that array. Before this batch each consumer had its own
// copy of the six lines and none of them checked anything, which is why one
// hole was five holes (the hash, the manifest writer, the vendor copy, the
// unbless and the per-file attribution). `what` names the package in a refusal;
// the array comes back through `pnames` and the count is the answer.
i64 dep_read_files(uptr dir, uptr what, uptr pnames) {
    uptr frame = toml_push();
    toml_parse(dep_in(dir, "mc.toml"));
    i64 n = toml_count("package.files");
    uptr names = xalloc(n * 8 + 8);
    i64 i = 0;
    while (i < n) {
        st64(names + i * 8, toml_get_array("package.files", i));
        i = i + 1;
    }
    toml_pop(frame);
    // after the pop, so a refusal cannot leave the project's own table swapped
    // out (M44 § Risks 6) -- it does not matter to _exit, and it does to a
    // soft-mode caller that carries on to unbless the tree
    i = 0;
    while (i < n) {
        dep_file_check(dir, ld64(names + i * 8), what);
        i = i + 1;
    }
    st64(pnames, names);
    return n;
}

// Reads <dir>/mc.toml inside a push/pop: records the package's [package].files
// into the file table and returns the tree hash. Also the one place that reads
// a package manifest at all, so a package that lists nothing hashes its mc.toml
// and no more -- which is a legitimate (and useless) package, not an error.
// Hashes a package tree: <dir>/mc.toml first, then each entry of
// [package].files IN MANIFEST ORDER, through dep_line above. The manifest is
// read inside a push/pop, and the file names are recorded in the file table
// under `pk` -- which is the package's index for a locked tree and -1 for a
// directory nobody locked (`mc pkg hash DIR`, and every tree `mc pkg sync`
// unpacks). Only the entries THIS call added are hashed, so the same table
// serves both and a second call cannot pick up the first one's names.
//
// It is the ONE definition of D5's rule: src/pkg.mc's `hash`, `sync`, `vendor`
// and `check` all come through here, and scripts/pkg-hash.sh is the second
// implementation `make check-pkg` compares it against on every run.
uptr dep_hash_tree(uptr dir, i64 pk) {
    uptr mt = dep_in(dir, "mc.toml");
    if (!lex_readable(mt)) return 0;
    uptr s = dp_state();
    uptr names = 0;
    i64 n = dep_read_files(dir, dep_pkg_what(pk, dir), &names);
    // soft mode: an entry that escapes is reported by the caller, which
    // unblesses the tree first. Nothing was added to the file table.
    if (dep_hash_err() != 0) return 0;
    i64 start = ld64(s + DP_NFILE);
    i64 i = 0;
    while (i < n) {
        dp_add_file(pk, ld64(names + i * 8));
        i = i + 1;
    }

    u8 b[BUF_SIZE];
    buf_init(b);
    dep_line(b, dir, "mc.toml");
    i64 nf = ld64(s + DP_NFILE);
    i = start;
    while (i < nf) {
        dep_line(b, dir, ld64(ld64(s + DP_FILE) + i * FL_SIZE + FL_NAME));
        i = i + 1;
    }
    if (dep_hash_err() != 0) return 0;          // a listed file was missing
    u8 d[32];
    sha256(buf_p(b), buf_len(b), d);
    return hex64(d);
}

// The locked package's tree, hashed and recorded. A package that lists nothing
// hashes its mc.toml and no more -- which is a legitimate (and useless)
// package, not an error.
uptr dep_scan(i64 pk) {
    uptr h = dep_hash_tree(dp_dir(pk), pk);
    if (h == 0)
        dep_die(tm_cat(tm_cat(dp_name(pk), " "), dp_ver(pk)),
                "no mc.toml in the package tree", "mc pkg sync --yes");
    return h;
}

// ---- per-file attribution ----
// The lock pins ONE hash per package (D4), so a mismatch says "something in this
// tree moved" and no more. What names the file is the cache manifest the fetch
// wrote beside the tree, `<libs>/<pack>/v<version>.toml`, with one [[file]] row
// per hashed file -- the same shape src/sysroot.mc writes for a sysroot. A
// vendored tree has no manifest (it was copied by hand or by `mc pkg vendor`),
// so its refusal names the tree.
uptr dep_manifest_bad(i64 pk) {
    uptr man = dp_man(pk);
    if (man == 0) return 0;
    uptr bad = 0;
    uptr frame = toml_push();
    toml_parse(man);
    i64 n = toml_occurrences("file");
    i64 i = 0;
    while (i < n) {
        uptr key = tm_cat(tm_cat("file.", tm_num_str(i)), ".");
        uptr rel = toml_get(tm_cat(key, "path"));
        uptr want = toml_get(tm_cat(key, "sha256"));
        if (rel != 0 && want != 0) {
            // the manifest is mc's own file, but it lives next to a tree a
            // registry wrote and it is read with the same arithmetic: check it
            // with the same rule rather than trust it (post-M44 review)
            if (!dep_rel_ok(rel, 0) || !dep_under(dp_dir(pk), rel)) {
                bad = rel;
                i = n;
            }
            uptr p = dep_in(dp_dir(pk), rel);
            if (bad == 0 && (!lex_readable(p) || !str_eq(sha256_file(p), want))) {
                bad = rel;
                i = n;
            }
        }
        i = i + 1;
    }
    toml_pop(frame);
    return bad;
}

// `geo 1.2.0: vec.mc does not match mc.lock`
void dep_mismatch(i64 pk) {
    uptr what = dep_manifest_bad(pk);
    if (what == 0 && dp_man(pk) != 0) what = "mc.toml";
    if (what == 0) what = "the tree";
    dep_die(tm_cat(tm_cat(tm_cat(dp_name(pk), " "), dp_ver(pk)),
                   tm_cat(tm_cat(": ", what), " does not match mc.lock")),
            0, "mc pkg verify");
}

// ---- <libs>: where an installed package lives ----
// --libs-dir DIR, else host_home()/.mc/libs. Never the working directory: that
// is the M15 stance one level up -- the answer to `<float>` must be a function
// of (this binary, this lock, the installed packages) and of nothing else.
uptr deps_libs_root() {
    if (dp_libs_opt != 0) return dp_libs_opt;
    uptr home = host_home();
    if (home == 0) return 0;
    return tm_cat(home, "/.mc/libs");
}

void deps_set_libs_dir(uptr d) { dp_libs_opt = d; }

// ---- stage 1: the installed `mc` package (A3, A4) ----
// <libs>/mc/v<mc_version()>/ in the REPOSITORY layout, with bundle.list at its
// root as the NAME<TAB>PATH map. Read once, cached; absent is not an error here
// -- a full binary answers every one of these names from its blob and never
// reaches this step.
void dp_mc_load() {
    uptr s = dp_state();
    if (ld64(s + DP_MCTRIED)) return;
    st64(s + DP_MCTRIED, 1);
    uptr root = deps_libs_root();
    if (root == 0) return;
    uptr dir = tm_cat(tm_cat(tm_cat(root, "/mc/v"), mc_version()), "/");
    uptr list = dep_in(dir, "bundle.list");
    if (!lex_readable(list)) return;
    i64 len = 0;
    uptr src = read_file(list, &len);
    // two passes: count the lines, then fill. The manifest is a file the
    // installer wrote, so its size is known before a byte is stored and there
    // is nothing to grow.
    i64 n = 0;
    i64 i = 0;
    while (i < len) {
        if (ld8(src + i) == '\n') n = n + 1;
        i = i + 1;
    }
    uptr names = xalloc(n * 8 + 8);
    uptr paths = xalloc(n * 8 + 8);
    i64 k = 0;
    i64 b = 0;
    i = 0;
    while (i <= len) {
        if (i == len || ld8(src + i) == '\n') {
            i64 t = b;
            while (t < i && ld8(src + t) != 9) { t = t + 1; }
            if (t < i && k < n) {
                st64(names + k * 8, xstrdup(src + b, t - b));
                st64(paths + k * 8, xstrdup(src + t + 1, i - t - 1));
                k = k + 1;
            }
            b = i + 1;
        }
        i = i + 1;
    }
    st64(s + DP_MCN, k);
    st64(s + DP_MCNAME, names);
    st64(s + DP_MCPATH, paths);
    st64(s + DP_MCDIR, dir);
}

uptr dp_mc_open(uptr name, uptr pcanon, uptr plen) {
    dp_mc_load();
    uptr s = dp_state();
    if (ld64(s + DP_MCDIR) == 0) return 0;
    // M37: `<mc/host>` is not an entry, it is the name of THIS compiler's host
    // file -- the same rewrite src/core_bundle.mc does for the blob, so that a
    // generated taught compiler is portable whichever road served it.
    if (str_eq(name, "mc/host")) name = host_include();
    i64 n = ld64(s + DP_MCN);
    i64 i = 0;
    while (i < n) {
        if (str_eq(ld64(ld64(s + DP_MCNAME) + i * 8), name)) {
            uptr p = dep_in(ld64(s + DP_MCDIR), ld64(ld64(s + DP_MCPATH) + i * 8));
            if (!lex_readable(p)) return 0;
            uptr src = read_file(p, plen);
            st64(pcanon, p);
            return src;
        }
        i = i + 1;
    }
    return 0;
}

// ---- why nothing answered (M44 step 4) ----
// src/lex.mc calls this when a `#include <name>` found nothing AND this binary
// carries no bundle -- which is `mc-slim` and nothing else. 0 means "the usual
// message is right": the tree IS installed and the name is simply not one of
// its entries, which is an ordinary unknown-include. Otherwise the answer is
// the sentence the reader needs, and the only one: the libraries of a slim
// compiler are the installed `mc` package, and there is none.
uptr dep_include_hint(uptr name) {
    dp_mc_load();
    if (ld64(dp_state() + DP_MCDIR) != 0) return 0;
    return tm_cat(tm_cat(tm_cat("#include <", name), ">: not bundled in this compiler and mc "),
                  tm_cat(mc_version(), " is not installed: run mc install"));
}

// ---- the opener src/lex.mc calls ----
// stage 0 = the lock road, stage 1 = the installed `mc` package. The once-only
// key handed back for either is the file's NORMALISED PATH -- the same key
// lex_include would record for it -- so a package file reached once as
// `<geo/vec.mc>` and once as a relative "vec.mc" from inside the package is one
// inclusion, exactly as `<mc/core>` and "core.mc" are one entry in the blob.
uptr libs_open(uptr name, i64 stage, uptr pcanon, uptr plen) {
    if (stage != 0) return dp_mc_open(name, pcanon, plen);
    if (dp == 0) return 0;
    i64 pk = dp_find(dep_first(name));
    if (pk < 0) return 0;
    // M48: a tool is a program, not a library. It has no root, so lex.mc never
    // asks -- and it has no resolved directory either, which is why the guard
    // is here and not only in the caller.
    if (dp_is_tool(pk)) return 0;
    uptr rest = 0;
    i64 n = cstrlen(dp_name(pk));
    if (ld8(name + n) == '/') rest = name + n + 1;
    else                      rest = dp_lib(pk);      // a bare <geo>
    if (rest == 0) return 0;
    // The `.mc` src/lex.mc dropped is put back here, and only here: a bundled
    // name never carries one (`mc/lex`, not `mc/lex.mc`) while a file on disk
    // always does. So `<geo/geo.mc>` and `<geo/geo>` are one name and both land
    // on geo.mc, and a payload with another extension -- `<pack/data.txt>` for
    // an #embed -- is found under the name it was written with.
    uptr p = dep_in(dp_dir(pk), rest);
    if (!lex_readable(p)) p = dep_in(dp_dir(pk), tm_cat(rest, ".mc"));
    if (!lex_readable(p)) return 0;
    uptr src = read_file(p, plen);
    st64(pcanon, p);
    return src;
}

// ---- reading mc.lock ----
// The format is docs/reference/packages.md § The lock: one [[package]] per row,
// sorted by name, each with name/version/lib/sha256/deps. Written only by
// `mc pkg`; read here, and checked against the trees on every build.
void dep_read_lock(uptr cfg) {
    uptr lock = path_join(cfg, "mc.lock");
    if (!lex_readable(lock))
        dep_die("mc.lock is stale", 0, "mc pkg sync --yes");
    uptr s = dp_state();
    uptr frame = toml_push();
    toml_parse(lock);
    i64 n = toml_occurrences("package");
    uptr pkgs = xalloc(n * PK_SIZE + PK_SIZE);
    // the edge list, sized exactly: the lock says how many there are
    i64 ne = 0;
    i64 i = 0;
    while (i < n) {
        ne = ne + toml_count(tm_cat(tm_cat("package.", tm_num_str(i)), ".deps"));
        i = i + 1;
    }
    uptr efrom = xalloc(ne * 8 + 8);
    uptr ename = xalloc(ne * 8 + 8);
    i64 k = 0;
    i = 0;
    while (i < n) {
        uptr key = tm_cat(tm_cat("package.", tm_num_str(i)), ".");
        uptr nm = toml_get(tm_cat(key, "name"));
        uptr vr = toml_get(tm_cat(key, "version"));
        if (nm == 0) toml_err_key(tm_cat(key, "name"), "missing key");
        if (vr == 0) toml_err_key(tm_cat(key, "version"), "missing key");
        // a lock row is local but can be hand-edited: a version that would
        // escape <libs>/<name>/v<version>/ is refused before it becomes a path
        if (!dep_ver_ok(vr)) toml_err_key(tm_cat(key, "version"), "not a usable version");
        uptr e = pkgs + i * PK_SIZE;
        st64(e + PK_NAME, nm);
        st64(e + PK_VER, vr);
        st64(e + PK_HASH, toml_get(tm_cat(key, "sha256")));
        st64(e + PK_LIB, toml_get(tm_cat(key, "lib")));
        // M48 § 4.3: the two keys a lock written before this milestone does not
        // have. No `kind` is `lib`, and no `permissions` is an EMPTY ACCEPTED
        // SET -- which is what makes every checked-in lock read as it did.
        st64(e + PK_KIND, toml_get(tm_cat(key, "kind")));
        uptr pmk = tm_cat(key, "permissions");
        i64 npm = toml_count(pmk);
        uptr pms = xalloc(npm * 8 + 8);
        i64 pj = 0;
        while (pj < npm) {
            st64(pms + pj * 8, toml_get_array(pmk, pj));
            pj = pj + 1;
        }
        st64(e + PK_NPERM, npm);
        st64(e + PK_PERMS, pms);
        uptr dk = tm_cat(key, "deps");
        i64 nd = toml_count(dk);
        i64 j = 0;
        while (j < nd) {
            st64(efrom + k * 8, i);
            st64(ename + k * 8, toml_get_array(dk, j));
            k = k + 1;
            j = j + 1;
        }
        i = i + 1;
    }
    toml_pop(frame);
    st64(s + DP_NPKG, n);
    st64(s + DP_PKG, pkgs);
    // The roots and the edges are sized once, from the lock, and never grow.
    // M48: a TOOL row is not one of them -- it is a program the developer
    // installs, never a tree this build reads -- so it takes no root, its
    // edges are dropped, and the two tables are no longer index-parallel with
    // the package table (PK_ROOT is the map, -1 for a tool).
    i64 nroot = 0;
    i = 0;
    while (i < n) {
        if (!dp_is_tool(i)) nroot = nroot + 1;
        i = i + 1;
    }
    lex_pkg_reserve(nroot, ne);
    i64 r = 0;
    i = 0;
    while (i < n) {
        if (dp_is_tool(i)) {
            st64(dp_at(i) + PK_ROOT, -1);
        } else {
            st64(dp_at(i) + PK_ROOT, r);
            lex_add_root(dp_name(i), 0);    // the directory is filled in below
            r = r + 1;
        }
        i = i + 1;
    }
    i = 0;
    while (i < ne) {
        i64 to = dp_find(ld64(ename + i * 8));
        if (to < 0)
            dep_die("mc.lock is stale", ld64(ename + i * 8), "mc pkg sync --yes");
        i64 rf = ld64(dp_at(ld64(efrom + i * 8)) + PK_ROOT);
        i64 rt = ld64(dp_at(to) + PK_ROOT);
        if (rf >= 0 && rt >= 0) lex_add_edge(rf, rt);
        i = i + 1;
    }
}

// ---- where a locked package's tree is (D10') ----
// deps/<pack>/ wins when it is there -- that is the fully offline project, and
// it is a choice the developer made by checking the tree in. Otherwise
// <libs>/<pack>/v<version>/, and ONLY that version: a directory no lock names is
// never opened, so `v1.0.0/` sitting beside `v1.2.0/` cannot change a byte.
void dep_resolve(i64 pk, uptr cfg) {
    uptr e = dp_at(pk);                        // PK_MAN is written straight
    uptr vend = path_join(cfg, tm_cat(tm_cat("deps/", dp_name(pk)), "/mc.toml"));
    if (lex_readable(vend)) {
        // the trailing '/' is re-attached AFTER path_join: path_norm drops it,
        // and a directory without it is a file name to the next join
        dp_set_dir(pk, tm_cat(path_join(cfg, tm_cat("deps/", dp_name(pk))), "/"));
        return;
    }
    uptr root = deps_libs_root();
    if (root != 0) {
        uptr base = tm_cat(tm_cat(tm_cat(root, "/"), dp_name(pk)), tm_cat("/v", dp_ver(pk)));
        // the manifest, beside the tree, is the CLAIM that the directory holds
        // what the lock says -- it is written last by the fetch, so a half
        // extracted tree is "not fetched" and not "does not match"
        uptr man = tm_cat(base, ".toml");
        if (lex_readable(man)) {
            dp_set_dir(pk, tm_cat(base, "/"));
            st64(e + PK_MAN, man);
            return;
        }
    }
    dep_die(tm_cat(tm_cat(dp_name(pk), " "), tm_cat(dp_ver(pk), " is not fetched")),
            0, "mc pkg sync --yes");
}

// ---- [replace] (D11) ----
// A local tree, for development: not pinned, not hashed, and announced, exactly
// as Go's replace directive is and as go.sum omits it.
// Returns 1 when a [replace] applied (the caller then skips dep_resolve and the
// hash check: a replaced package is a local tree the developer vouches for, so
// it needs no fetched copy at the resolved location and no sha256 to match),
// 0 when this name has no [replace] entry.
i64 dep_replace(i64 pk, uptr cfg) {
    uptr p = toml_get(tm_cat("replace.", dp_name(pk)));
    if (p == 0) return 0;
    uptr e = dp_at(pk);
    dp_set_dir(pk, tm_cat(path_join(cfg, p), "/"));
    st64(e + PK_HASH, 0);
    st64(e + PK_MAN, 0);
    out_str(1, "replaced ");
    out_str(1, dp_name(pk));
    out_str(1, ": ");
    out_str(1, p);
    out_str(1, " -- not pinned by mc.lock\n");
    return 1;
}

// ---- the entry point the driver calls ----
// Runs for BOTH halves of `mc build` (the taught compiler and the entry), which
// is why it is in drv_parse and not in drv_apply_config: a compiler-module
// package has to reach the first compilation and a library package the second.
// With no [deps] it returns before reading anything, and the lexer's root table
// stays empty -- so a project without dependencies is byte for byte what it was
// (D24).
void deps_apply(uptr cfg) {
    uptr s = dp_state();
    if (ld64(s + DP_APPLIED)) return;
    st64(s + DP_APPLIED, 1);
    // 1. the names, validated at their own position, before anything is read
    i64 nd = 0;
    i64 i = 0;
    while (i < toml_entries()) {
        uptr k = opt_val(toml_path_at(i), "deps.");
        if (k != 0) {
            dep_check_name("deps.", k);
            nd = nd + 1;
        }
        k = opt_val(toml_path_at(i), "replace.");
        if (k != 0) dep_check_name("replace.", k);
        // M48 § 1.3: `[tools]` is `[deps]`' shape and a tool is resolved in the
        // same MVS graph -- by `mc pkg sync`. A BUILD asks nothing of it: no
        // root, no tree, no lock row consulted, so a project that declares one
        // and never runs `mc pkg` still builds, and one that has both emits the
        // same bytes it emitted before the `[tools]` line was written (D24).
        // The name is still checked at its own position, as `[replace]`'s is.
        k = opt_val(toml_path_at(i), "tools.");
        if (k != 0) dep_check_name("tools.", k);
        i = i + 1;
    }
    if (nd == 0) return;
    // 2. the lock, and the roots it names
    dep_read_lock(cfg);
    // 3. every [deps] minimum has to be met by a row: the lock is the answer to
    //    the manifest, so a manifest that moved makes the lock stale
    i = 0;
    while (i < toml_entries()) {
        uptr k = opt_val(toml_path_at(i), "deps.");
        if (k != 0) {
            i64 pk = dp_find(k);
            if (pk < 0 || ver_cmp(dp_ver(pk), toml_val_at(i)) < 0)
                dep_die("mc.lock is stale", k, "mc pkg sync --yes");
        }
        i = i + 1;
    }
    // 4. each tree resolved, then REHASHED (D7): checked, not trusted. A tool
    //    row is skipped whole: its tree lives under ~/.mc/tools, `mc tool`
    //    owns it, and this build neither opens nor hashes it.
    //    [replace] is consulted FIRST (M52 S1): a name pointed at a local tree
    //    IS that tree, so it is not fetched at the resolved location and not
    //    hashed against the lock. dep_replace sets the directory and zeroes
    //    PK_HASH, so dep_resolve (which would die "is not fetched") is skipped
    //    and the mismatch check below can never fire for it. dep_scan STILL
    //    runs: it reads the local tree's [package].files into the boundary
    //    table (deps_check_files) and requires its mc.toml -- a replaced tree
    //    is vouched for, not unstructured. Its include root and its edges were
    //    registered from the lock in dep_read_lock, so a replaced package is
    //    still #include-able and its own [deps] still hold.
    i = 0;
    while (i < dp_npkg()) {
        if (dp_is_tool(i)) {
            i = i + 1;
            continue;
        }
        if (!dep_replace(i, cfg)) dep_resolve(i, cfg);
        uptr got = dep_scan(i);
        uptr want = dp_hash(i);
        if (want != 0 && !str_eq(got, want)) dep_mismatch(i);
        i = i + 1;
    }
}

// ---- the post-parse boundary (§ 3, last row) ----
// A file the build actually READ under a package root has to be one the package
// declared. That is what makes [package].files a boundary rather than
// documentation: an author who forgets a file ships one that fails loudly at
// the first consumer, and a planted file inside a fetched tree is refused even
// though its bytes are inside the hashed set of none of them.
void deps_check_files() {
    if (dp == 0) return;
    if (lex_root_count() == 0) return;
    i64 i = 0;
    while (i < lex_inc_count()) {
        uptr key = lex_inc_at(i);
        i64 r = lex_root_of(key);
        if (r >= 0) {
            uptr rel = key + cstrlen(lex_root_dir(r));
            if (!str_eq(rel, "mc.toml") && !dp_has_file(r, rel))
                err_at(tm_cat(tm_cat(lex_root_name(r), "/"), rel), 1,
                       tm_cat(tm_cat("not declared in ", lex_root_name(r)),
                              "'s [package].files"));
        }
        i = i + 1;
    }
}

// [registry].url, the index `mc pkg` reads. Nothing in <mc/core_build> fetches,
// so this is only the value; the default lives in src/pkg.mc with the code that
// uses it (M44 § 5).
uptr deps_registry() { return toml_get("registry.url"); }
