// upgrade.mc — `mc upgrade`: the compiler replaces itself from a release
// (M44 step 5, § D2 as amended by the owner's ruling of 2026-09-06).
//
//   mc upgrade [VERSION] [--yes] [--no-install] [--to PATH]
//              [--registry URL|DIR] [--libs-dir DIR]
//
// The M25 order, which every verb that touches the network in this repository
// follows: resolve, refuse, PLAN, --yes, download, verify BEFORE unpacking,
// act, claim last.
//
// ---- where the binaries are (the asset rule) ----
//
// The registry is a registry of SOURCES (M44 § 5): the `mc` package's index row
// carries the tag ARCHIVE, not the compiled binaries. The binaries live on the
// release the same tag produced, and their address is DERIVED from the row's
// own url rather than written down a second time:
//
//   https://github.com/<o>/<r>/archive/refs/tags/v0.16.0.tar.gz
//     -> https://github.com/<o>/<r>/releases/download/v0.16.0/mc-0.16.0-<target>.tar.gz
//
// and the checksum is that name plus `.sha256`, which is exactly what
// scripts/release-assets.sh writes beside every archive. A url of any other
// shape is refused -- `no binaries known for <url>` -- rather than guessed at:
// a forge that is not GitHub publishes its assets somewhere else, and inventing
// a path would turn a missing feature into a download of the wrong file.
//
// A row whose url is a LOCAL PATH is the second road, and it costs one line:
// the assets sit BESIDE the archive, in the same directory. That is what makes
// this file testable with no network at all (scripts/check-pkg.sh § 33), and it
// is the air-gapped upgrade M44 § Risks 18 asks for -- a directory holding a
// release, plus `--registry DIR`.
//
// Two things are read out of the running binary and not out of a flag, because
// a flag would let a user ask for an archive that cannot run here:
//
//   the TARGET   host_os() + host_arch(), in the release vocabulary
//                (`aarch64` is spelled `arm64` there -- the two vocabularies
//                docs/bootstrap.md records)
//   the FLAVOUR  a binary with no bundle at all is `mc-slim` and fetches
//                `-slim`; anything else fetches the full archive. `bopen_fn`
//                (src/lex.mc) is 0 for exactly that binary, which is the same
//                question src/deps.mc's include hint asks.
//
// ---- what it does not do ----
//
// There is no `--force`. A downgrade is not a mistake to override, it is a
// VERSION named explicitly, and the plan says `downgrade` where it would
// otherwise say `upgrade`. What is refused is the road that picks a version FOR
// you on a tree build: `0.0.0-dev` names no release, so a bare `mc upgrade`
// there is `build from the tree` -- and `mc upgrade VERSION` still works, which
// is what lets the acceptance test run without a release of its own (§ D2's
// rule, and src/install.mc's precedent for the same sentinel).
//
// It also proves nothing about WHO published the archive. The `.sha256` comes
// from the same origin as the tarball: it proves the bytes arrived intact and
// nothing else. The priced follow-up is a signing key (M44 § D3); until it
// ships, docs/reference/packages.md says so in one sentence.
//
// It costs no global: everything is a local, and --yes, --registry and
// --libs-dir go into the records src/pkg.mc and src/deps.mc already keep.

// ---- the release vocabulary ----
// `macos-arm64`, `linux-arm64`, `linux-x86_64`, `windows-arm64`,
// `windows-x86_64`: the five names scripts/release-assets.sh takes as its
// TARGET argument and .github/workflows/release.yml passes it.
uptr upg_target() {
    uptr arch = host_arch();
    if (str_eq(arch, "aarch64")) arch = "arm64";
    return tm_cat(tm_cat(host_os(), "-"), arch);
}

// "" for the full compiler, "-slim" for a binary that carries no bundle at all
// (src/mc_slim.mc). Reading src/lex.mc's pointer directly is the same question
// src/deps.mc's dep_include_hint asks and the only one there is: a slim binary
// differs from a full one by the absence of <mc/core_bundle>, and nothing else
// in the program can see that.
uptr upg_flavour() {
    if (bopen_fn == 0) return "-slim";
    return "";
}

// `mc-0.16.0-macos-arm64.tar.gz`
uptr upg_asset(uptr ver) {
    return tm_cat(tm_cat("mc-", ver),
                  tm_cat(tm_cat("-", upg_target()),
                         tm_cat(upg_flavour(), ".tar.gz")));
}

// the offset of `pat` in `s`, or -1
i64 upg_find(uptr s, uptr pat) {
    i64 pl = cstrlen(pat);
    i64 i = 0;
    loop {
        if (ld8(s + i) == 0) break;
        if (mem_eq(s + i, pat, pl)) return i;
        i = i + 1;
    }
    return -1;
}

// everything up to and including the last `/` of a path or url, or "" when
// there is none (a bare file name: the assets are in the working directory)
uptr upg_dirname(uptr p) {
    return xstrdup(p, fetch_basename(p) - p);
}

// where this version's release assets are, from the index row's url; 0 when
// this file has no rule for that url. See the header for the two roads.
uptr upg_base(uptr url) {
    if (!fetch_is_url(url)) return upg_dirname(url);
    i64 k = upg_find(url, "/archive/refs/tags/");
    if (k < 0) return 0;
    uptr repo = xstrdup(url, k);
    uptr tag = url + k + cstrlen("/archive/refs/tags/");
    if (!fetch_ends(tag, ".tar.gz")) return 0;
    tag = xstrdup(tag, cstrlen(tag) - 7);
    if (cstrlen(tag) == 0) return 0;
    return tm_cat(tm_cat(repo, "/releases/download/"), tm_cat(tag, "/"));
}

// ---- the plan ----
// `upgrade` or `downgrade`, then the two urls and the file that will be
// replaced. The vocabulary is src/pkg.mc's (`url`, `sha256`, `into`), with one
// difference written into the column itself: `sha256` here is the ADDRESS of
// the checksum file, not a digest -- there is nothing to pin in advance,
// because the archive is built by the release and not by the author.
void upg_print_plan(uptr cur, uptr ver, uptr base, uptr dest) {
    uptr what = "upgrade";
    if (ver_cmp(ver, cur) < 0) what = "downgrade";
    out_str(1, what);
    out_str(1, " mc ");
    out_str(1, cur);
    out_str(1, " -> ");
    out_str(1, ver);
    out_str(1, "\nurl    ");
    out_str(1, tm_cat(base, upg_asset(ver)));
    out_str(1, "\nsha256 ");
    out_str(1, tm_cat(tm_cat(base, upg_asset(ver)), ".sha256"));
    out_str(1, "\ninto   ");
    out_str(1, dest);
    out_str(1, "\n");
}

// ---- the swap ----
// A copy, not a rename of the extracted file: <libs> and /usr/local/bin are
// routinely different filesystems and a rename across one fails. The bytes go
// to `<dest>.new`, which is unlinked first so that `creat` really applies mode
// 0755, and only then is that file renamed over `dest`.
//
// Why a rename and not "unlink dest, write dest": a rename is atomic, so there
// is no instant at which the compiler on the PATH is half a file, and it gives
// the destination a NEW INODE -- which is what the macOS kernel needs, because
// overwriting a signed binary IN PLACE makes the next run die with `Killed: 9`
// from the cached signature (CLAUDE.md § M12, src/driver.mc's unlink before
// every write of an executable). The running process keeps the old inode and is
// unaffected either way.
void upg_write_exec(uptr src, uptr dst) {
    i64 len = 0;
    uptr p = read_file(src, &len);
    unlink(dst);
    drv_mkdirs(dst);
    i64 fd = c_int(creat(dst, MODE_755));
    if (fd < 0) dep_die("cannot create", dst, 0);
    i64 off = 0;
    while (off < len) {
        i64 w = write(fd, p + off, len - off);
        if (w <= 0) {
            close(fd);
            dep_die("cannot write", dst, 0);
        }
        off = off + w;
    }
    close(fd);
}

// POSIX on macOS and Linux; lib/sys_windows_host.mc provides it over
// MoveFileExA on a Windows host, where it can replace any file EXCEPT the
// running .exe -- see upg_swap.
extern i64 rename(uptr from, uptr to);

// 1 when this host can replace a file that a running process was loaded from.
// Windows cannot: the image file is held open for the life of the process, so
// `mc upgrade` there writes the new compiler beside the old one and prints the
// one command that finishes the job. Nothing on the two Unix hosts needs a
// special case, and nothing here probes: the answer is a property of the
// operating system this binary was built for.
i64 upg_can_replace_self() {
    return !str_eq(host_os(), "windows");
}

// `<dest>.new` -> `<dest>`, or the sentence a Windows user runs by hand.
// Answers 1 when the compiler at `dest` IS the new one afterwards.
i64 upg_swap(uptr newbin, uptr dest, i64 self) {
    uptr stage = tm_cat(dest, ".new");
    upg_write_exec(newbin, stage);
    if (self && !upg_can_replace_self()) {
        out_str(1, "the new compiler is ");
        out_str(1, stage);
        out_str(1, "\nwindows holds a running .exe open; finish with:\n");
        out_str(1, "  move /y \"");
        out_str(1, stage);
        out_str(1, "\" \"");
        out_str(1, dest);
        out_str(1, "\"\n");
        return 0;
    }
    if (rename(stage, dest) != 0) {
        unlink(stage);
        dep_die("cannot replace", dest, 0);
    }
    return 1;
}

// ---- the extracted binary says what it is ----
// The archive was verified against a checksum served from the same origin, so
// this is not a security check: it is the check that the release named what it
// packaged. An asset built from the wrong tag -- or a directory registry a
// reviewer staged by hand -- is caught here, before anything is replaced.
void upg_check_version(uptr bin, uptr ver, uptr tmpf) {
    u8 av[3 * 8];
    st64(av + 0, bin);
    st64(av + 8, "--version");
    st64(av + 16, 0);
    unlink(tmpf);
    i64 rc = fetch_spawn_to(bin, av, tmpf);
    if (rc != 0) dep_die("the downloaded mc does not run", tm_cat("exit ", tm_num_str(rc)), 0);
    i64 len = 0;
    uptr s = read_file(tmpf, &len);
    while (len > 0 && (ld8(s + len - 1) == '\n' || ld8(s + len - 1) == '\r')) { len = len - 1; }
    st8(s + len, 0);
    unlink(tmpf);
    uptr want = tm_cat("mc ", ver);
    if (!str_eq(s, want))
        dep_die("the downloaded mc reports another version",
                tm_cat(tm_cat(s, ", expected "), want), 0);
}

// ---- the libraries ----
// Spawned, and spawned from the NEW binary: the tree lives at
// <libs>/mc/v<version>/ and the version that names it is the one the compiler
// reports, so the process that must ask is the one that was just installed.
// The exit status is the command's.
i64 upg_install(uptr dest, uptr libs, uptr reg) {
    u8 av[8 * 8];
    i64 n = 0;
    st64(av + n * 8, dest);   n = n + 1;
    st64(av + n * 8, "install"); n = n + 1;
    st64(av + n * 8, "--yes"); n = n + 1;
    if (libs != 0) {
        st64(av + n * 8, "--libs-dir"); n = n + 1;
        st64(av + n * 8, libs);         n = n + 1;
    }
    if (reg != 0) {
        st64(av + n * 8, "--registry"); n = n + 1;
        st64(av + n * 8, reg);          n = n + 1;
    }
    st64(av + n * 8, 0);
    i64 rc = drv_spawn_ok(dest, av, 0);
    if (rc < 0) dep_die("cannot run the new compiler", dest, 0);
    return rc;
}

void upgrade_usage() {
    out_str(2, "usage: mc upgrade [VERSION] [--yes] [--no-install] [--to PATH] [--registry URL|DIR] [--libs-dir DIR]\n");
}

i64 upgrade_cmd(i64 argc, uptr argv) {
    uptr ver = 0;
    uptr to = 0;
    uptr libs = 0;
    uptr reg = 0;
    i64 noinstall = 0;
    i64 i = 2;
    while (i < argc) {
        uptr a = ld64(argv + i * 8);
        if (str_eq(a, "--yes")) pk_set_yes(1);
        else if (str_eq(a, "--no-install")) noinstall = 1;
        else if (str_eq(a, "--to")) {
            if (i + 1 >= argc) die("--to requires an argument");
            i = i + 1;
            to = ld64(argv + i * 8);
        }
        else if (str_eq(a, "--registry")) {
            if (i + 1 >= argc) die("--registry requires an argument");
            i = i + 1;
            reg = ld64(argv + i * 8);
            pk_set_registry(reg);
        }
        else if (str_eq(a, "--libs-dir")) {
            if (i + 1 >= argc) die("--libs-dir requires an argument");
            i = i + 1;
            libs = ld64(argv + i * 8);
            deps_set_libs_dir(libs);
        }
        else if (ld8(a) == '-') {
            upgrade_usage();
            return 1;
        }
        else if (ver == 0) ver = a;
        else               die2("too many arguments", a);
        i = i + 1;
    }
    uptr cur = mc_version();
    // The sentinel refuses the road that CHOOSES for you. `mc upgrade 1.2.3` on
    // a tree build is allowed and does what it says -- the same rule
    // src/install.mc applies to the same string, and what lets `make check`
    // exercise this file without a release of its own.
    if (ver == 0 && str_eq(cur, "0.0.0-dev"))
        dep_die("mc 0.0.0-dev is a development build", "build from the tree", "make mc1");

    // pkg_pick loads the index (printing the plan and stopping when the index
    // itself would have to be downloaded without --yes), validates an explicit
    // version, refuses a yanked one, and otherwise answers the newest
    // non-yanked, non-pre-release row: a candidate is never chosen for you, and
    // -1 is "any major", because a compiler's own major is not a constraint on
    // the compiler.
    uptr want = pkg_pick("mc", ver, -1, 0);
    if (str_eq(want, cur)) {
        out_str(1, "mc ");
        out_str(1, cur);
        out_str(1, " is the newest\n");
        return 0;
    }
    i64 r = pkg_row("mc", want);
    if (r < 0) pkg_die1("no such version of mc in the registry", want);
    uptr url = ld64(pk_vr(r) + VR_URL);
    if (url == 0) pkg_die1(pkg_what("mc", want), "the index row has no url");
    uptr base = upg_base(url);
    if (base == 0) dep_die("upgrade: no binaries known for", url, 0);

    i64 self = to == 0;
    uptr dest = to;
    if (dest == 0) dest = host_self_path();
    if (dest == 0)
        dep_die("cannot find the path of this binary", "name one with --to PATH", 0);

    upg_print_plan(cur, want, base, dest);
    if (!pk_yes()) {
        out_str(1, "nothing was downloaded: re-run with --yes\n");
        return 0;
    }

    uptr root = deps_libs_root();
    if (root == 0)
        dep_die("nowhere to put the download", "no --libs-dir and no HOME", 0);
    uptr dir = tm_cat(tm_cat(root, "/mc/tmp/"), tm_cat(want, "/"));
    uptr asset = upg_asset(want);
    uptr archive = tm_cat(dir, asset);
    uptr sumfile = tm_cat(archive, ".sha256");
    drv_mkdirs(archive);
    pkg_get(tm_cat(base, asset), archive, FETCH_MAXARCHIVE);
    pkg_get(tm_cat(tm_cat(base, asset), ".sha256"), sumfile, FETCH_MAXINDEX);

    // verified BEFORE anything is unpacked, which is the one thing this road
    // can do that `mc pkg`'s cannot (§ 3: a tag archive has no stable bytes, a
    // release asset does)
    uptr wantsum = fetch_sha256_line(sumfile);
    if (wantsum == 0) {
        unlink(archive);
        unlink(sumfile);
        dep_die("not a checksum file", tm_cat(tm_cat(base, asset), ".sha256"), 0);
    }
    uptr gotsum = sha256_file(archive);
    if (!str_eq(gotsum, wantsum)) {
        unlink(archive);
        unlink(sumfile);
        out_str(2, "mc: checksum mismatch for ");
        out_str(2, pkg_what("mc", want));
        out_str(2, "\n  expected ");
        out_str(2, wantsum);
        out_str(2, "\n  got      ");
        out_str(2, gotsum);
        out_str(2, "\n");
        _exit(2);
    }
    unlink(sumfile);

    // one member out of the archive, the binary. scripts/release-assets.sh
    // writes it as `mc` (`mc.exe` on a windows-* target) inside a single
    // directory named after the archive, which --strip-components=1 removes.
    uptr binname = tm_cat("mc", host_exe_suffix());
    uptr stem = xstrdup(asset, cstrlen(asset) - 7);        // without `.tar.gz`
    unlink(tm_cat(dir, binname));
    if (fetch_extract(archive, dir, 1, tm_cat(tm_cat(stem, "/"), binname)) != 0) {
        unlink(archive);
        dep_die("tar could not extract", asset, 0);
    }
    unlink(archive);
    uptr newbin = tm_cat(dir, binname);
    if (!lex_readable(newbin))
        dep_die("the archive carries no compiler", tm_cat(tm_cat(stem, "/"), binname), 0);
    upg_check_version(newbin, want, tm_cat(dir, "version.txt"));

    i64 replaced = upg_swap(newbin, dest, self);
    unlink(newbin);
    if (!replaced) return 0;

    out_str(1, "mc ");
    out_str(1, cur);
    out_str(1, " -> ");
    out_str(1, want);
    out_str(1, " (");
    out_str(1, dest);
    out_str(1, ")\n");
    if (noinstall) return 0;
    return upg_install(dest, libs, reg);
}
