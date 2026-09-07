// tool.mc — `mc tool` (M48 C3): install, list, remove, upgrade, run, box-args.
//
// A tool is a package of `kind = "exe"` (M48 § 1.1). `mc tool install` resolves
// it in the same MVS graph `mc pkg` uses -- its own `[deps]` are libraries --
// shows the plan and the permission table, fetches into <libs>, then stages a
// buildable copy under ~/.mc/tools/<name>/v<ver>/ and builds it by spawning the
// running compiler (the drv_teach precedent: the binary that runs builds the
// next thing). The launcher ~/.mc/bin/<bin> is one line that calls `mc tool
// run`, which is where the box is derived and spawned.
//
// The ONE mapping from a package's permissions to sandbox primitives lives here
// -- `tool_derive` -- and is what both `mc tool run` executes and the hidden
// `mc tool box-args` prints, so there is a single definition of "what `fs.read
// workspace` means", versioned with the compiler (M48 § 4.1, D6). No
// `--unconfined` (the amendment): the same install everywhere, and `run` boxes
// where the host has a sandbox and runs the binary directly where it has none.
//
// It lives in <mc/core_pkg> beside pkg.mc/install.mc and depends on them for
// the index reader, MVS, the fetch, pkg_copy_tree, pkg_write_lock and the
// permission table; on src/driver.mc for drv_spawn/drv_mkdirs/drv_step; and on
// the host layer for host_home/host_getcwd/host_self_path/host_sandbox_supported.
// It costs one global, `tl`, an arena record like pk/dp/sb_state.

// ---- state: one arena record ----
#define TL_BINDIR 0                   // --bin-dir override, 0 = <mc home>/bin
#define TL_WS     8                   // the resolved workspace (§ 3.5)
#define TL_SIZE   16

uptr tl = 0;
uptr tl_state() {
    if (tl == 0) tl = xalloc(TL_SIZE);
    return tl;
}
uptr tl_bindir_opt() { return ld64(tl_state() + TL_BINDIR); }
uptr tl_ws()         { return ld64(tl_state() + TL_WS); }
void set_tl_bindir(uptr d) { st64(tl_state() + TL_BINDIR, d); }
void set_tl_ws(uptr w)     { st64(tl_state() + TL_WS, w); }

// ---- where the roots are ----
// The two roots the developer may override are --libs-dir (src/deps.mc's, the
// fetched trees) and --bin-dir (the launchers). The tools root is neither: it
// is <mc home>/tools, and <mc home> is the parent of <libs> -- so --libs-dir
// $x/l puts the tools under $x/tools and the launchers under $x/bin, which is
// what lets CI run with no HOME (the --sysroot-dir precedent, M48 § 3.2).
uptr tool_dirname(uptr p) {
    i64 last = -1;
    i64 i = 0;
    loop {
        i64 c = ld8(p + i);
        if (c == 0) break;
        if (c == '/') last = i;
        i = i + 1;
    }
    if (last <= 0) return "/";
    return xstrdup(p, last);
}

uptr tool_mc_home() {
    uptr root = deps_libs_root();
    if (root == 0)
        dep_die("nowhere to install a tool", "no --libs-dir and no HOME", 0);
    return tool_dirname(root);
}

uptr tool_tools_root() { return tm_cat(tool_mc_home(), "/tools"); }

uptr tool_bin_dir() {
    uptr o = tl_bindir_opt();
    if (o != 0) return o;
    return tm_cat(tool_mc_home(), "/bin");
}

uptr tool_dir(uptr name, uptr ver) {
    ver = dep_ver_path(ver);
    return tm_cat(tm_cat(tm_cat(tool_tools_root(), "/"), name),
                  tm_cat(tm_cat("/v", ver), "/"));
}

uptr tool_manifest_path(uptr name, uptr ver) {
    ver = dep_ver_path(ver);
    return tm_cat(tm_cat(tm_cat(tool_tools_root(), "/"), name),
                  tm_cat(tm_cat("/v", ver), ".toml"));
}

uptr tool_index_path() { return tm_cat(tool_tools_root(), "/installed"); }

uptr tool_launcher_path(uptr bin) {
    uptr name = bin;
    if (!str_eq(host_exe_suffix(), "")) name = tm_cat(bin, ".cmd");
    return tm_cat(tm_cat(tool_bin_dir(), "/"), name);
}

// ---- the workspace literal (§ 3.5) ----
// The current working directory of the invocation, resolved once. $HOME and /
// are refused without an explicit --workspace: a tool started from the home
// directory would otherwise be granted every file the user owns under the word
// "workspace".
void tool_resolve_ws(uptr override) {
    uptr ws = override;
    if (ws == 0) ws = host_getcwd();
    if (ws == 0) ws = ".";
    ws = path_norm(ws);
    if (override == 0) {
        uptr home = host_home();
        if (home != 0 && str_eq(ws, path_norm(home)))
            dep_die("the workspace is your home directory", ws,
                    "mc tool run NAME --workspace DIR");
        if (str_eq(ws, "/"))
            dep_die("the workspace is the filesystem root", ws,
                    "mc tool run NAME --workspace DIR");
    }
    set_tl_ws(ws);
}

// ---- the ONE permission -> sandbox-flag mapping (§ 4.1, D6) ----
// `path` is a permission path ("workspace", "tmp", "workspace/<rel>",
// "home/<rel>") already validated by dep_perm_line; the resolved host path, or
// 0 for `tmp`.
uptr tool_resolve_path(uptr path) {
    if (str_eq(path, "workspace")) return tl_ws();
    if (str_eq(path, "tmp")) return 0;
    uptr rel = opt_val(path, "workspace/");
    if (rel != 0) return tm_cat(tm_cat(tl_ws(), "/"), rel);
    rel = opt_val(path, "home/");
    if (rel != 0) {
        uptr home = host_home();
        if (home == 0) dep_die("a home/ permission needs a home directory", path, 0);
        return tm_cat(tm_cat(home, "/"), rel);
    }
    // An unrecognized permission path must NEVER fall through to "the whole
    // workspace, writable" (M48 C3 review, finding 2): every caller has already
    // run dep_perm_line_ok / dep_perm_path_ok, so this is a hard error, not a
    // default.
    dep_die("an unrecognized permission path", path, 0);
    return 0;
}

// One canonical permission line -> its sandbox tokens, appended to `av` from
// *pn (append == 1) or printed space-joined on one line (append == 0). When
// appending for a real run, a `fs.write home/<rel>` directory is created first
// (mc has mkdir), because --rw binds a directory that has to exist.
void tool_flags(uptr line, uptr av, uptr pn, i64 append) {
    uptr toks = xalloc(4 * 8);
    i64 nt = 0;
    uptr rd = opt_val(line, "fs.read ");
    uptr wr = opt_val(line, "fs.write ");
    uptr path = rd;
    if (wr != 0) path = wr;
    if (path != 0) {
        if (str_eq(path, "tmp")) {
            st64(toks + nt * 8, "--tmp"); nt = nt + 1;
        } else {
            uptr res = tool_resolve_path(path);
            uptr flag = "--ro";
            if (wr != 0) flag = "--rw";
            if (append && wr != 0 && opt_val(path, "home/") != 0)
                drv_mkdirs(tm_cat(res, "/x"));
            st64(toks + nt * 8, flag);      nt = nt + 1;
            st64(toks + nt * 8, res);       nt = nt + 1;
            st64(toks + nt * 8, "--at-path"); nt = nt + 1;
        }
    } else if (str_eq(line, "net")) {
        st64(toks + nt * 8, "--allow=net"); nt = nt + 1;
    } else {
        uptr e = opt_val(line, "exec ");
        if (e != 0) {
            st64(toks + nt * 8, "--bin"); nt = nt + 1;
            st64(toks + nt * 8, e);       nt = nt + 1;
        } else {
            uptr v = opt_val(line, "env ");
            if (v != 0) {
                st64(toks + nt * 8, "--env"); nt = nt + 1;
                st64(toks + nt * 8, v);       nt = nt + 1;
            }
        }
    }
    if (append) {
        i64 n = ld64(pn);
        i64 j = 0;
        while (j < nt) {
            st64(av + n * 8, ld64(toks + j * 8));
            n = n + 1;
            j = j + 1;
        }
        st64(pn, n);
    } else if (nt > 0) {
        i64 j = 0;
        while (j < nt) {
            if (j > 0) out_str(1, " ");
            out_str(1, ld64(toks + j * 8));
            j = j + 1;
        }
        out_str(1, "\n");
    }
}

// ---- reading a permission set from a tree's mc.toml (box-args) ----
// dep_read_perms parses the [[permission]] rows into the canonical, sorted set;
// tool_flags then maps each. This is box-args's road.
void tool_box_args(uptr cfg, uptr override) {
    if (!lex_readable(cfg)) dep_die("no such mc.toml", cfg, 0);
    tool_resolve_ws(override);
    uptr frame = toml_push();
    toml_parse(cfg);
    uptr perms = 0;
    i64 n = dep_read_perms(&perms);
    i64 i = 0;
    while (i < n) {
        tool_flags(ld64(perms + i * 8), 0, 0, 0);
        i = i + 1;
    }
    toml_pop(frame);
}

// ---- the installed index: one line `<name> <version> <bin>` ----
// mc has no opendir, so `list`, `run` (newest) and `remove` read this one file
// instead of walking ~/.mc/tools. It is rewritten in full on every install and
// remove, so a crash never leaves a half-line (M48 § 3.2, the readdir gap).
uptr tool_line_field(uptr p, i64 s, i64 e, i64 k) {
    i64 i = s;
    i64 f = 0;
    loop {
        i64 fs = i;
        while (i < e && ld8(p + i) != ' ') { i = i + 1; }
        if (f == k) return xstrdup(p + fs, i - fs);
        if (i >= e) return 0;
        i = i + 1;
        f = f + 1;
    }
}

// the newest installed version of `name`, and its bin through `pbin`; 0 if none
uptr tool_newest(uptr name, uptr pbin) {
    st64(pbin, 0);
    uptr path = tool_index_path();
    if (!lex_readable(path)) return 0;
    i64 len = 0;
    uptr p = read_file(path, &len);
    uptr best = 0;
    i64 i = 0;
    while (i < len) {
        i64 s = i;
        while (i < len && ld8(p + i) != '\n') { i = i + 1; }
        uptr nm = tool_line_field(p, s, i, 0);
        if (nm != 0 && str_eq(nm, name)) {
            uptr v = tool_line_field(p, s, i, 1);
            uptr b = tool_line_field(p, s, i, 2);
            if (v != 0 && (best == 0 || ver_cmp(v, best) > 0)) {
                best = v;
                st64(pbin, b);
            }
        }
        i = i + 1;
    }
    return best;
}

// rewrite the index: keep every line except (drop_name, drop_ver) -- both 0
// keeps all -- and, when add_name != 0, append one line. drop_ver 0 with a
// drop_name drops EVERY version of that name (remove).
void tool_index_rewrite(uptr drop_name, uptr drop_ver,
                        uptr add_name, uptr add_ver, uptr add_bin) {
    i64 len = 0;
    uptr p = 0;
    if (lex_readable(tool_index_path())) p = read_file(tool_index_path(), &len);
    u8 b[BUF_SIZE];
    buf_init(b);
    i64 i = 0;
    while (i < len) {
        i64 s = i;
        while (i < len && ld8(p + i) != '\n') { i = i + 1; }
        uptr nm = tool_line_field(p, s, i, 0);
        i64 keep = 1;
        if (nm != 0 && drop_name != 0 && str_eq(nm, drop_name)) {
            if (drop_ver == 0) keep = 0;
            else {
                uptr v = tool_line_field(p, s, i, 1);
                if (v != 0 && str_eq(v, drop_ver)) keep = 0;
            }
        }
        if (keep && i > s) {
            buf_put(b, p + s, i - s);
            drv_put(b, "\n");
        }
        i = i + 1;
    }
    if (add_name != 0) {
        drv_put(b, add_name);
        drv_put(b, " ");
        drv_put(b, add_ver);
        drv_put(b, " ");
        drv_put(b, add_bin);
        drv_put(b, "\n");
    }
    drv_mkdirs(tool_index_path());
    write_file(tool_index_path(), b);
}

// ---- the install manifest, written last (§ 3.1 step 6, the claim) ----
void tool_write_manifest(uptr name, uptr ver, uptr bin, uptr out, uptr sha,
                        i64 nperm, uptr perms) {
    u8 b[BUF_SIZE];
    buf_init(b);
    // Every free-text field is escaped (M48 C3 review, finding 1). `out` above
    // all: it is [project].out read verbatim from an attacker-controlled tree,
    // and a raw newline plus a doubled quote in it would splice a second [tool]
    // table -- with its own `permissions` -- into this manifest, which tool_run
    // would then read back and grant. toml_esc also refuses a control byte.
    drv_put(b, "# written by `mc tool install` -- do not edit\n[tool]\nname        = \"");
    drv_put(b, toml_esc(name));
    drv_put(b, "\"\nversion     = \"");
    drv_put(b, toml_esc(ver));
    drv_put(b, "\"\nbin         = \"");
    drv_put(b, toml_esc(bin));
    drv_put(b, "\"\nout         = \"");
    drv_put(b, toml_esc(out));
    drv_put(b, "\"\nsha256      = \"");
    drv_put(b, toml_esc(sha));
    drv_put(b, "\"\nkind        = \"tool\"\n");
    // the amendment: a fact `mc tool list` shows, not a flag anyone set
    drv_put(b, "sandbox     = ");
    if (host_sandbox_supported()) drv_put(b, "true\n");
    else                          drv_put(b, "false\n");
    drv_put(b, "permissions = [");
    i64 i = 0;
    while (i < nperm) {
        if (i > 0) drv_put(b, ", ");
        drv_put(b, "\"");
        drv_put(b, toml_esc(ld64(perms + i * 8)));
        drv_put(b, "\"");
        i = i + 1;
    }
    drv_put(b, "]\n");
    write_file(tool_manifest_path(name, ver), b);
}

// ---- the launcher: one line, mode 0755 (§ 3.3) ----
// It calls the compiler that installed it, by absolute path, so a tool keeps
// working when `mc` is not on PATH and cannot be run by a different compiler
// than the one that built it (a deviation from the spec's bare `mc`, on record
// in docs/reference/tools.md). The logic is all in `mc tool run`, so the box
// mapping can change without a launcher being regenerated.
void tool_write_launcher(uptr name, uptr bin) {
    uptr self = host_self_path();
    if (self == 0) dep_die("cannot find my own path for the launcher", name, 0);
    u8 b[BUF_SIZE];
    buf_init(b);
    // --libs-dir is embedded so `mc tool run` finds the SAME tools root the
    // install wrote to: the tools root is the parent of <libs>, and a launcher
    // that named only `tool run NAME` would look under the default ~/.mc when
    // the install used --libs-dir/--bin-dir (CI has no HOME). It is not a box
    // flag -- the box mapping is derived at run time from the manifest, § 3.3.
    uptr libs = deps_libs_root();
    if (str_eq(host_exe_suffix(), "")) {
        drv_put(b, "#!/bin/sh\nexec \"");
        drv_put(b, self);
        drv_put(b, "\" tool run ");
        drv_put(b, name);
        if (libs != 0) {
            drv_put(b, " --libs-dir \"");
            drv_put(b, libs);
            drv_put(b, "\"");
        }
        drv_put(b, " -- \"$@\"\n");
    } else {
        drv_put(b, "@\"");
        drv_put(b, self);
        drv_put(b, "\" tool run ");
        drv_put(b, name);
        if (libs != 0) {
            drv_put(b, " --libs-dir \"");
            drv_put(b, libs);
            drv_put(b, "\"");
        }
        drv_put(b, " -- %*\r\n");
    }
    uptr path = tool_launcher_path(bin);
    drv_mkdirs(path);
    i64 fd = c_int(creat(path, MODE_755));
    if (fd < 0) dep_die("cannot write the launcher", path, 0);
    io_write(fd, buf_p(b), buf_len(b));
    close(fd);
}

// 1 when a package's tree is already in <libs>. A tool install never consults
// a project's deps/ (a tool is not vendored into a project) and runs with no
// cfg_file, so it must NOT go through pkg_present/pkg_tree_dir, which join
// against cfg_file() -- 0 here -- and read a project's vendor directory.
i64 tool_present(uptr name, uptr ver) {
    return lex_readable(pkg_libs_manifest(name, ver));
}

// ---- staging and building (§ 3.1 steps 4-5) ----
// The staged tree is the vendored shape the validator builds and `mc build`
// rehashes: mc.toml + [package].files, deps/<lib>/ for every library, and an
// mc.lock. The build is a spawn of the running compiler, which is trusted
// exactly as `mc build` of any project is (M44 Risk 1); the tool it produces is
// what runs boxed later.
void tool_stage(uptr name, uptr ver) {
    uptr dir = tool_dir(name, ver);
    drv_mkdirs(tm_cat(dir, "x"));
    pkg_copy_tree(pkg_libs_dir(name, ver), dir, pkg_what(name, ver));
    i64 i = 0;
    while (i < pk_nsel()) {
        uptr e = pk_sel(i);
        if (!ld64(e + SL_TOOL)) {
            uptr ln = ld64(e + SL_NAME);
            uptr lv = ld64(e + SL_VER);
            uptr ldst = tm_cat(tm_cat(dir, "deps/"), tm_cat(ln, "/"));
            drv_mkdirs(tm_cat(ldst, "x"));
            pkg_copy_tree(pkg_libs_dir(ln, lv), ldst, pkg_what(ln, lv));
        }
        i = i + 1;
    }
    // cfg_file makes pkg_tree_dir see the vendored deps/ under the staged tree;
    // the tool's own row falls through to <libs>, which is where it was fetched
    set_cfg_file(tm_cat(dir, "mc.toml"));
    pkg_write_lock(tm_cat(dir, "mc.lock"));
}

uptr tool_self() {
    uptr self = host_self_path();
    if (self == 0) dep_die("cannot find my own path to build the tool", 0, 0);
    return drv_runnable(self);
}

void tool_build(uptr name, uptr ver) {
    uptr dir = tool_dir(name, ver);
    uptr self = tool_self();
    drv_step("build", tm_cat(dir, "mc.toml"), tm_cat(name, " (in the box's shape)"));
    uptr av = xalloc(6 * 8);
    st64(av + 0, self);
    st64(av + 8, "build");
    st64(av + 16, dir);
    st64(av + 24, "--libs-dir");
    st64(av + 32, deps_libs_root());
    st64(av + 40, 0);
    i64 rc = drv_spawn(self, av, 0);
    if (rc != 0 && rc != 3) dep_die("the tool did not build", pkg_what(name, ver), 0);
}

// ---- the plan loop (shared with pkg_sync's shape) ----
// pk_sel is already the MVS build list; this fills pk_plan with what is not on
// the disk, annotating a tool's line with its binary the way pkg_sync does.
void tool_plan_missing() {
    i64 i = 0;
    while (i < pk_nsel()) {
        uptr e = pk_sel(i);
        uptr name = ld64(e + SL_NAME);
        uptr ver = ld64(e + SL_VER);
        if (!tool_present(name, ver)) {
            i64 r = pkg_row(name, ver);
            if (r < 0) pkg_die1(pkg_what(name, ver), "no such version in the registry");
            uptr row = pk_vr(r);
            if (ld64(row + VR_URL) == 0)
                pkg_die1(pkg_what(name, ver), "the index row has no url");
            uptr what = pkg_what(name, ver);
            if (str_eq(ld64(row + VR_KIND), "tool")) {
                what = tm_cat(pkg_col(what, 24), "tool");
                if (ld64(row + VR_BIN) != 0)
                    what = tm_cat(tm_cat(what, "  bin "), ld64(row + VR_BIN));
            }
            pkg_plan(what, ld64(row + VR_URL), ld64(row + VR_SHA), pkg_libs_dir(name, ver));
        }
        i = i + 1;
    }
}

void tool_fetch_missing() {
    i64 i = 0;
    while (i < pk_nsel()) {
        uptr e = pk_sel(i);
        uptr name = ld64(e + SL_NAME);
        uptr ver = ld64(e + SL_VER);
        if (!tool_present(name, ver)) {
            i64 r = pkg_row(name, ver);
            uptr row = pk_vr(r);
            pkg_fetch_one(name, ver, ld64(row + VR_URL), ld64(row + VR_STRIP),
                          ld64(row + VR_SHA));
        }
        i = i + 1;
    }
}

// ---- the box's per-kind ceilings (§ 4, M48 C3 review, finding 4) ----
// A permission set that maps to more sandbox roots than the box accepts is
// accepted and locked at install but refused at every `mc tool run`
// (`too many --ro directories`, exit 2). These mirror src/sandbox.mc's
// SB_MAXRO / SB_MAXRW / SB_MAXBIN / SB_MAXENV -- copied, not shared, because
// core_pkg (this part) is compiled before core_sandbox and mc-slim omits the
// sandbox entirely. scripts/check-tool.sh drives a set past each so the two
// cannot drift silently. A `tmp` path is `--tmp` (no ceiling) and `net` is
// `--allow=net` (no ceiling), so neither counts.
#define TOOL_MAXRO  16
#define TOOL_MAXRW  16
#define TOOL_MAXBIN  8
#define TOOL_MAXENV  8

// Count the per-kind sandbox roots a canonical permission set maps to and
// refuse it before the user is asked to accept it, naming the kind that
// overflows. Read at install time from the tool's INDEX ROW, so the refusal
// comes before the --yes prompt and before any fetch.
void tool_check_capacity(i64 n, uptr perms) {
    i64 ro = 0;
    i64 rw = 0;
    i64 nbin = 0;
    i64 nenv = 0;
    i64 i = 0;
    while (i < n) {
        uptr line = ld64(perms + i * 8);
        uptr p = opt_val(line, "fs.read ");
        if (p != 0) {
            if (!str_eq(p, "tmp")) ro = ro + 1;
        } else {
            p = opt_val(line, "fs.write ");
            if (p != 0) {
                if (!str_eq(p, "tmp")) rw = rw + 1;
            } else if (opt_val(line, "exec ") != 0) {
                nbin = nbin + 1;
            } else if (opt_val(line, "env ") != 0) {
                nenv = nenv + 1;
            }
        }
        i = i + 1;
    }
    if (ro > TOOL_MAXRO)
        dep_die("too many fs.read permissions for the box", tm_cat(tm_num_str(ro), " (at most 16)"), 0);
    if (rw > TOOL_MAXRW)
        dep_die("too many fs.write permissions for the box", tm_cat(tm_num_str(rw), " (at most 16)"), 0);
    if (nbin > TOOL_MAXBIN)
        dep_die("too many exec permissions for the box", tm_cat(tm_num_str(nbin), " (at most 8)"), 0);
    if (nenv > TOOL_MAXENV)
        dep_die("too many env permissions for the box", tm_cat(tm_num_str(nenv), " (at most 8)"), 0);
}

// ---- install one tool by name (§ 3.1) ----
i64 tool_install(uptr name, uptr ver) {
    pkg_require(name, ver);
    st64(pk_sel(pkg_sel_find(name)) + SL_TOOL, 1);
    pkg_resolve();
    i64 r = pkg_row(name, ver);
    if (r < 0) pkg_die1(pkg_what(name, ver), "no such version in the registry");
    if (!str_eq(ld64(pk_vr(r) + VR_KIND), "tool"))
        pkg_die1(name, "is a library, not a tool: add it to a project's [deps]");
    pkg_check_kinds();
    // capacity pre-flight: refuse a set the box can never run BEFORE the user
    // is asked to accept it (finding 4)
    tool_check_capacity(ld64(pk_vr(r) + VR_PERMN), ld64(pk_vr(r) + VR_PERMP));
    tool_plan_missing();
    // the plan is the prompt, and it carries the permission table (§ 4.2). No
    // accepted set is loaded: an install has no prior lock, so every permission
    // is shown, and there is no host-specific line -- the box is `run`'s.
    i64 ask = pkg_perm_ask();
    if (pk_nplan() > 0 || ask) {
        pkg_print_plan();
        if (ask) pkg_print_perms();
        if (!host_sandbox_supported())
            out_str(1, "note: this host has no sandbox; the permissions above are recorded, not enforced\n");
        if (!pk_yes()) {
            out_str(1, "nothing was installed: re-run with --yes to fetch and to accept the permissions above\n");
            return 0;
        }
        tool_fetch_missing();
    }
    tool_stage(name, ver);
    tool_build(name, ver);
    // the manifest and the launcher: read the built tree's own claims
    uptr dir = tool_dir(name, ver);
    uptr frame = toml_push();
    toml_parse(tm_cat(dir, "mc.toml"));
    uptr out = toml_get("project.out");
    uptr bin = pkg_bin_of("tool");
    uptr perms = 0;
    i64 nperm = dep_read_perms(&perms);
    toml_pop(frame);
    uptr sha = dep_hash_tree(dir, -1);
    tool_write_manifest(name, ver, bin, out, sha, nperm, perms);
    tool_write_launcher(name, bin);
    tool_index_rewrite(name, ver, name, ver, bin);
    out_str(1, "installed ");
    out_str(1, pkg_what(name, ver));
    out_str(1, " (");
    out_str(1, bin);
    out_str(1, ") -> ");
    out_str(1, tool_launcher_path(bin));
    out_str(1, "\n");
    out_str(1, "add ");
    out_str(1, tool_bin_dir());
    out_str(1, " to your PATH\n");
    return 0;
}

// ---- install every [tools] of a project (§ 3.1, second form) ----
i64 tool_install_project(uptr dir) {
    deps_apply(cfg_file());
    i64 any = 0;
    i64 i = 0;
    while (i < dp_npkg()) {
        if (dp_is_tool(i)) {
            tool_install(dp_name(i), dp_ver(i));
            any = 1;
        }
        i = i + 1;
    }
    if (!any) out_str(1, "no tools required by this project\n");
    return 0;
}

// ---- list ----
i64 tool_list() {
    uptr path = tool_index_path();
    if (!lex_readable(path)) {
        out_str(1, "no tools installed\n");
        return 0;
    }
    i64 len = 0;
    uptr p = read_file(path, &len);
    i64 i = 0;
    while (i < len) {
        i64 s = i;
        while (i < len && ld8(p + i) != '\n') { i = i + 1; }
        if (i > s) {
            uptr nm = tool_line_field(p, s, i, 0);
            uptr v = tool_line_field(p, s, i, 1);
            uptr bin = tool_line_field(p, s, i, 2);
            pkg_pad(nm, 16);
            out_str(1, " ");
            pkg_pad(v, 10);
            out_str(1, " ");
            pkg_pad(bin, 16);
            out_str(1, " ");
            // the permissions come from the per-version manifest, so `list` is
            // host-independent (the sandbox state is a manifest fact, not shown
            // in this line) -- tests/golden/tool-list.txt
            uptr man = tool_manifest_path(nm, v);
            if (lex_readable(man)) {
                uptr frame = toml_push();
                toml_parse(man);
                i64 np = toml_count("tool.permissions");
                if (np == 0) out_str(1, "stdio");
                i64 j = 0;
                while (j < np) {
                    if (j > 0) out_str(1, ", ");
                    out_str(1, toml_get_array("tool.permissions", j));
                    j = j + 1;
                }
                toml_pop(frame);
            } else {
                out_str(1, "stdio");
            }
            out_str(1, "\n");
        }
        i = i + 1;
    }
    return 0;
}

// ---- remove ----
i64 tool_remove(uptr name) {
    uptr bin = 0;
    uptr ver = tool_newest(name, &bin);
    if (ver == 0) {
        pkg_die1(name, "is not installed");
    }
    // unlink every installed version's manifest and the launcher of the newest
    i64 len = 0;
    uptr p = read_file(tool_index_path(), &len);
    i64 i = 0;
    while (i < len) {
        i64 s = i;
        while (i < len && ld8(p + i) != '\n') { i = i + 1; }
        uptr nm = tool_line_field(p, s, i, 0);
        if (nm != 0 && str_eq(nm, name)) {
            uptr v = tool_line_field(p, s, i, 1);
            if (v != 0) unlink(tool_manifest_path(name, v));
        }
        i = i + 1;
    }
    if (bin != 0) unlink(tool_launcher_path(bin));
    tool_index_rewrite(name, 0, 0, 0, 0);
    out_str(1, "removed ");
    out_str(1, name);
    out_str(1, "\n");
    return 0;
}

// ---- upgrade ----
// The newest non-yanked, non-pre-release row of the same major, then install
// (§ 3.1). With NAME, that one; without, every installed tool.
i64 tool_upgrade_one(uptr name) {
    uptr bin = 0;
    uptr cur = tool_newest(name, &bin);
    if (cur == 0) pkg_die1(name, "is not installed");
    uptr v = pkg_pick(name, 0, ver_major(cur), ver_is_pre(cur));
    if (ver_cmp(v, cur) <= 0) {
        out_str(1, name);
        out_str(1, " ");
        out_str(1, cur);
        out_str(1, " is the newest\n");
        return 0;
    }
    drv_step("upgrade", name, tm_cat(tm_cat(cur, " -> "), v));
    return tool_install(name, v);
}

i64 tool_upgrade(uptr only) {
    if (only != 0) return tool_upgrade_one(only);
    uptr path = tool_index_path();
    if (!lex_readable(path)) {
        out_str(1, "no tools installed\n");
        return 0;
    }
    // collect the distinct names first: install rewrites the index under us
    i64 len = 0;
    uptr p = read_file(path, &len);
    uptr names = xalloc(len * 8 + 8);
    i64 nn = 0;
    i64 i = 0;
    while (i < len) {
        i64 s = i;
        while (i < len && ld8(p + i) != '\n') { i = i + 1; }
        uptr nm = tool_line_field(p, s, i, 0);
        if (nm != 0) {
            i64 seen = 0;
            i64 j = 0;
            while (j < nn) {
                if (str_eq(ld64(names + j * 8), nm)) seen = 1;
                j = j + 1;
            }
            if (!seen) {
                st64(names + nn * 8, nm);
                nn = nn + 1;
            }
        }
        i = i + 1;
    }
    i = 0;
    while (i < nn) {
        tool_upgrade_one(ld64(names + i * 8));
        i = i + 1;
    }
    return 0;
}

// ---- run (§ 3.3) ----
// The launcher calls this. On a host with a sandbox the box is derived from the
// install manifest's permissions and `mc sandbox exec` is spawned; on a host
// without one the binary runs directly. The exit code is the child's.
i64 tool_run(uptr name, i64 argc, uptr argv, i64 args, uptr ws_override) {
    uptr bin = 0;
    uptr ver = tool_newest(name, &bin);
    if (ver == 0) pkg_die1(name, "is not installed");
    uptr man = tool_manifest_path(name, ver);
    if (!lex_readable(man)) pkg_die1(pkg_what(name, ver), "the install manifest is gone: re-install");
    uptr frame = toml_push();
    toml_parse(man);
    uptr out = toml_get("tool.out");
    i64 np = toml_count("tool.permissions");
    uptr perms = xalloc(np * 8 + 8);
    i64 j = 0;
    while (j < np) {
        st64(perms + j * 8, toml_get_array("tool.permissions", j));
        j = j + 1;
    }
    toml_pop(frame);
    // Re-validate every stored permission before ANY of it is mapped to a
    // sandbox flag (M48 C3 review, finding 2). The install manifest is a file
    // on disk that could have been corrupted or hand-edited; a line that is not
    // one this compiler could itself have written from a valid [[permission]]
    // row -- an injected `fs.write home/../..`, an unrecognized word -- must be
    // refused, never mapped through tool_resolve_path's fallback.
    j = 0;
    while (j < np) {
        if (!dep_perm_line_ok(ld64(perms + j * 8)))
            pkg_die1(pkg_what(name, ver),
                     tm_cat("the install manifest carries an invalid permission: ",
                            ld64(perms + j * 8)));
        j = j + 1;
    }
    if (out == 0) pkg_die1(pkg_what(name, ver), "the install manifest names no binary");
    uptr binpath = path_join(tm_cat(tool_dir(name, ver), "mc.toml"), out);
    i64 nargs = argc - args;
    if (nargs < 0) nargs = 0;

    if (host_sandbox_supported()) {
        tool_resolve_ws(ws_override);
        // <self> sandbox exec <derived flags> <binpath> <args...>
        uptr av = xalloc((nargs + 3 * np + 12) * 8);
        i64 n = 0;
        st64(av + n * 8, tool_self()); n = n + 1;
        st64(av + n * 8, "sandbox");   n = n + 1;
        st64(av + n * 8, "exec");      n = n + 1;
        j = 0;
        u8 pn[8];
        st64(pn, n);
        // The (none) row (§ 4.1): a tool that declares no permission runs with
        // its own install tree bound READ-ONLY at its own path, so it cannot
        // rewrite its own files and there is no granted writable root at all.
        // (The `exec` model still overlays the binary's directory as an
        // ephemeral copy-on-write /src, so the tool's cwd is writable but its
        // writes are discarded and never touch the host tree -- see
        // docs/reference/tools.md.)
        if (np == 0) {
            i64 m = ld64(pn);
            st64(av + m * 8, "--ro");                 m = m + 1;
            st64(av + m * 8, tool_dir(name, ver));    m = m + 1;
            st64(av + m * 8, "--at-path");            m = m + 1;
            st64(pn, m);
        }
        while (j < np) {
            tool_flags(ld64(perms + j * 8), av, pn, 1);
            j = j + 1;
        }
        n = ld64(pn);
        st64(av + n * 8, binpath); n = n + 1;
        j = 0;
        while (j < nargs) {
            st64(av + n * 8, ld64(argv + (args + j) * 8));
            n = n + 1;
            j = j + 1;
        }
        st64(av + n * 8, 0);
        return drv_spawn(tool_self(), av, 0);
    }
    // no box on this host: run the binary directly
    uptr av = xalloc((nargs + 2) * 8);
    i64 n = 0;
    st64(av + n * 8, binpath); n = n + 1;
    j = 0;
    while (j < nargs) {
        st64(av + n * 8, ld64(argv + (args + j) * 8));
        n = n + 1;
        j = j + 1;
    }
    st64(av + n * 8, 0);
    return drv_spawn(drv_runnable(binpath), av, 0);
}

// ---- the dispatch ----
void tool_usage() {
    out_str(2, "usage: mc tool install NAME[@VER] | install [DIR] [--config FILE]\n");
    out_str(2, "       mc tool list | remove NAME | upgrade [NAME] | run NAME [-- ARGS]\n");
    out_str(2, "       [--yes] [--registry URL|DIR] [--libs-dir DIR] [--bin-dir DIR] [--workspace DIR]\n");
}

i64 tool_cmd(i64 argc, uptr argv) {
    if (argc < 3) { tool_usage(); return 1; }
    uptr sub = ld64(argv + 2 * 8);
    uptr pos = 0;
    uptr cfg = 0;
    uptr ws = 0;
    i64 args = argc;                  // index of the first arg after `--`
    i64 i = 3;
    while (i < argc) {
        uptr a = ld64(argv + i * 8);
        if (str_eq(a, "--")) { args = i + 1; i = argc; }
        else if (str_eq(a, "--yes")) pk_set_yes(1);
        else if (str_eq(a, "--config")) {
            if (i + 1 >= argc) die("--config requires an argument");
            i = i + 1;
            cfg = ld64(argv + i * 8);
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
        else if (str_eq(a, "--bin-dir")) {
            if (i + 1 >= argc) die("--bin-dir requires an argument");
            i = i + 1;
            set_tl_bindir(ld64(argv + i * 8));
        }
        else if (str_eq(a, "--workspace")) {
            if (i + 1 >= argc) die("--workspace requires an argument");
            i = i + 1;
            ws = ld64(argv + i * 8);
        }
        else if (ld8(a) == '-') { tool_usage(); return 1; }
        else if (pos == 0) pos = a;
        else die2("too many arguments", a);
        if (i < argc) i = i + 1;
    }

    if (str_eq(sub, "box-args")) {
        if (pos == 0) { tool_usage(); return 1; }
        tool_box_args(pos, ws);
        return 0;
    }
    if (str_eq(sub, "list"))    return tool_list();
    if (str_eq(sub, "remove")) {
        if (pos == 0) { tool_usage(); return 1; }
        return tool_remove(pos);
    }
    if (str_eq(sub, "run")) {
        if (pos == 0) { tool_usage(); return 1; }
        return tool_run(pos, argc, argv, args, ws);
    }
    if (str_eq(sub, "upgrade")) return tool_upgrade(pos);
    if (str_eq(sub, "install")) {
        // NAME[@VER] when it is a registered name; a DIRECTORY when it holds an
        // mc.toml. `install` with no positional installs the tools of `.`.
        if (pos != 0 && lex_readable(path_norm(tm_cat(pos, "/mc.toml")))) {
            pkg_open_config(pos, cfg);
            return tool_install_project(pos);
        }
        if (pos == 0) {
            if (!lex_readable("mc.toml")) { tool_usage(); return 1; }
            pkg_open_config(".", cfg);
            return tool_install_project(".");
        }
        uptr name = pkg_at_name(pos);
        if (dep_reserved(name)) pkg_die1("reserved package name", name);
        if (!dep_name_ok(name)) pkg_die1("invalid package name", name);
        uptr ver = pkg_pick(name, pkg_at_ver(pos), -1, 0);
        return tool_install(name, ver);
    }
    tool_usage();
    return 1;
}
