// main.mc - mcsite, the static site generator of docs/specs/M27.md, written in
// mc and built by `mc build site`.
//
//   mcsite [DIR] [--check]
//
// DIR is the directory holding site.toml; with no argument it takes `site` when
// `site/site.toml` exists (running from the repository root) and `.` otherwise
// (running from inside site/). Every other path - the Markdown root, the
// templates, the static files, the output - is written in site.toml and resolved
// against the directory of that file, exactly like mc.toml in `mc build`
// (docs/build.md).
//
// The modules, in dependency order:
//
//   util.mc   strings, lists, paths, directories, HTML escaping, slugs
//   hl.mc     fenced code, and ```mc through the bundled lexer
//   md.mc     the Markdown subset -> HTML
//   tmpl.mc   {{name}} and <!--if name--> over the four templates
//   site.mc   site.toml, sections, pages, navigation, search index, sitemap
//   check.mc  --check: internal links, then site/tools/*.py when python3 is there

#include <mc/arena>
#include <mc/lex>
#include <mc/toml>
#include <prelude>

// The host layer: the shape of `struct dirent`, which is all mcsite needs from
// the system it runs on that is not the same on macOS and on Linux. There is no
// site_host.mc next to this file -- the choice is made from OUTSIDE, by
// `[include].paths` in site/mc.toml (gen/macos) or site/mc.linux.toml
// (gen/linux), the way examples/conc picks its thread layer.
#include "site_host.mc"

#include "util.mc"
#include "hl.mc"
#include "md.mc"
#include "tmpl.mc"
#include "site.mc"
#include "check.mc"

void ms_usage() {
    out_str(2, "usage: mcsite [DIR] [--check]\n");
    out_str(2, "  DIR   the directory holding site.toml (default: site, or .)\n");
    out_str(2, "  --check  validate internal links and run site/tools/*.py\n");
}

// envp is the third parameter both C runtimes pass and the only portable way to
// reach the environment: mcsite hands it to posix_spawnp when --check runs the
// two Python checkers (site/gen/util.mc, ms_envp).
i64 main(i64 argc, uptr argv, uptr envp) {
    ms_envp = envp;
    uptr dir = 0;
    i64 check = 0;
    i64 i = 1;
    loop {
        if (i >= argc) break;
        uptr a = ld64(argv + i * 8);
        if (str_eq(a, "--check")) check = 1;
        else if (str_eq(a, "--help") || str_eq(a, "-h")) { ms_usage(); return 0; }
        else if (ld8(a) == '-') { ms_usage(); return 1; }
        else if (dir == 0) dir = a;
        else { ms_usage(); return 1; }
        i = i + 1;
    }
    if (dir == 0) {
        if (u_file_exists("site/site.toml")) dir = "site";
        else                                 dir = ".";
    }
    sg_build(dir);
    if (check) return ck_run();
    return 0;
}
