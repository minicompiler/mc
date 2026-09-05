// site.mc - the site itself: site.toml, the sections, the pages, the navigation,
// the outline, the search index, the sitemap and everything written into
// site/public.
//
// Order is fixed everywhere and nothing is derived from a clock or from the
// filesystem's own order (docs/determinism.md): sections come from the `nav`
// array of site.toml, pages from a sorted directory listing plus an optional
// per-section `order`, and the footer's year is a value in site.toml, not the
// system date. Two runs produce byte-identical files.

// ---- configuration ----
uptr sg_dir = 0;                      // the directory holding site.toml
uptr sg_toml = 0;                     // its path, used to resolve every other one
uptr sg_out = 0;                      // where the site is written
uptr sg_docs = 0;                     // the Markdown root
uptr sg_tpldir = 0;
uptr sg_staticdir = 0;
uptr sg_repo = 0;                     // repository root, for edit links and taught=
uptr sg_title = 0;
uptr sg_tagline = 0;
uptr sg_descr = 0;                    // the home page's description, when it has no prose
uptr sg_base = 0;                     // URL prefix, always ending in '/'
uptr sg_origin = 0;                   // scheme and host, for canonical URLs and the sitemap
uptr sg_sep = 0;                      // between a page title and the site title
uptr sg_year = 0;
uptr sg_edit = 0;                     // prefix of a link to the source in the repository
uptr sg_home_src = 0;
i64  sg_search = 1;

// [site].nav_extra: header links this generator does NOT render a page for.
// They are routes of the registry server that serves the same domain
// (/packages, /login), so on a static preview they lead nowhere -- which is why
// they are configuration and not markup, and why --check is told about them by
// name instead of guessing from the shape of the URL.
uptr sg_extra_url;                    // the URLs, for ck_link
uptr sg_extra_html = 0;               // the <a> elements, for {{nav_extra}}

uptr sg_t_base;                       // the four templates, read once
uptr sg_t_page;
uptr sg_t_home;
uptr sg_t_404;

// ---- sections ----
#define SC_ID    0
#define SC_TITLE 8
#define SC_DIR   16                   // on disk, or 0 when the directory is missing
#define SC_URL   24                   // relative to base_url, ending in '/'
#define SC_IDX   32                   // page index of the section's index page
#define SC_SIZE  40

uptr sg_secs;
i64  sg_seccap = 0;
i64  sg_ns = 0;

uptr sc_at(i64 i)     { return sg_secs + i * SC_SIZE; }
uptr sc_id(i64 i)     { return ld64(sc_at(i) + SC_ID); }
uptr sc_title(i64 i)  { return ld64(sc_at(i) + SC_TITLE); }
uptr sc_dir(i64 i)    { return ld64(sc_at(i) + SC_DIR); }
uptr sc_url(i64 i)    { return ld64(sc_at(i) + SC_URL); }
i64  sc_idx(i64 i)    { return ld64(sc_at(i) + SC_IDX); }
void set_sc_idx(i64 i, i64 v) { st64(sc_at(i) + SC_IDX, v); }

// the section whose directory is exactly `dir`, or -1. The internals section's
// directory IS docs/, so a link to docs/ itself lands on it, which is right.
i64 sg_sec_by_dir(uptr dir) {
    i64 i = 0;
    loop {
        if (i >= sg_ns) break;
        if (sc_dir(i) != 0 && str_eq(path_norm(sc_dir(i)), path_norm(dir))) return i;
        i = i + 1;
    }
    return 0 - 1;
}

i64 sg_sec_new(uptr id, uptr title, uptr dir, uptr url) {
    sg_secs = u_grow(sg_secs, sg_ns, &sg_seccap, SC_SIZE);
    uptr e = sc_at(sg_ns);
    st64(e + SC_ID, id);
    st64(e + SC_TITLE, title);
    st64(e + SC_DIR, dir);
    st64(e + SC_URL, url);
    st64(e + SC_IDX, 0 - 1);
    sg_ns = sg_ns + 1;
    return sg_ns - 1;
}

// ---- pages ----
#define PG_SRC   0                    // the .md on disk, or 0 for a generated page
#define PG_SLUG  8
#define PG_SECT  16                   // section index, or -1
#define PG_TITLE 24
#define PG_URL   32                   // relative to base_url; "" is the home page
#define PG_DESC  40
#define PG_BODY  48
#define PG_TOC   56
#define PG_HID   64                   // heading ids, for the search index
#define PG_HTXT  72                   // their texts
#define PG_KIND  80                   // 0 page, 1 section index, 2 home, 3 not found
#define PG_SIZE  88

#define PK_PAGE  0
#define PK_INDEX 1
#define PK_HOME  2
#define PK_404   3

uptr sg_pages;
i64  sg_pgcap = 0;
i64  sg_np = 0;

uptr pg_at(i64 i)    { return sg_pages + i * PG_SIZE; }
uptr pg_src(i64 i)   { return ld64(pg_at(i) + PG_SRC); }
uptr pg_slug(i64 i)  { return ld64(pg_at(i) + PG_SLUG); }
i64  pg_sect(i64 i)  { return ld64(pg_at(i) + PG_SECT); }
uptr pg_title(i64 i) { return ld64(pg_at(i) + PG_TITLE); }
uptr pg_url(i64 i)   { return ld64(pg_at(i) + PG_URL); }
uptr pg_desc(i64 i)  { return ld64(pg_at(i) + PG_DESC); }
uptr pg_body(i64 i)  { return ld64(pg_at(i) + PG_BODY); }
uptr pg_toc(i64 i)   { return ld64(pg_at(i) + PG_TOC); }
uptr pg_hid(i64 i)   { return ld64(pg_at(i) + PG_HID); }
uptr pg_htxt(i64 i)  { return ld64(pg_at(i) + PG_HTXT); }
i64  pg_kind(i64 i)  { return ld64(pg_at(i) + PG_KIND); }
void set_pg_title(i64 i, uptr v) { st64(pg_at(i) + PG_TITLE, v); }
void set_pg_desc(i64 i, uptr v)  { st64(pg_at(i) + PG_DESC, v); }
void set_pg_body(i64 i, uptr v)  { st64(pg_at(i) + PG_BODY, v); }
void set_pg_toc(i64 i, uptr v)   { st64(pg_at(i) + PG_TOC, v); }
void set_pg_hid(i64 i, uptr v)   { st64(pg_at(i) + PG_HID, v); }
void set_pg_htxt(i64 i, uptr v)  { st64(pg_at(i) + PG_HTXT, v); }

i64 sg_page_new(uptr src, uptr slug, i64 sect, uptr url, i64 kind) {
    sg_pages = u_grow(sg_pages, sg_np, &sg_pgcap, PG_SIZE);
    uptr e = pg_at(sg_np);
    st64(e + PG_SRC, src);
    st64(e + PG_SLUG, slug);
    st64(e + PG_SECT, sect);
    st64(e + PG_TITLE, u_title_from_slug(slug));
    st64(e + PG_URL, url);
    st64(e + PG_DESC, "");
    st64(e + PG_BODY, "");
    st64(e + PG_TOC, "");
    st64(e + PG_HID, sl_new());
    st64(e + PG_HTXT, sl_new());
    st64(e + PG_KIND, kind);
    sg_np = sg_np + 1;
    return sg_np - 1;
}

i64 sg_find_src(uptr path) {
    i64 i = 0;
    loop {
        if (i >= sg_np) break;
        if (pg_src(i) != 0 && str_eq(pg_src(i), path)) return i;
        i = i + 1;
    }
    return 0 - 1;
}

// ---- paths ----
// a path written in site.toml -> a path usable from the working directory
uptr sg_path(uptr rel) { return path_join(sg_toml, rel); }

// an on-disk path -> the same path relative to the repository root, or 0
uptr sg_repo_rel(uptr p) {
    if (str_eq(sg_repo, ".")) {
        if (u_starts(p, "/") || u_starts(p, "..")) return 0;
        return p;
    }
    uptr pre = u_cat2(sg_repo, "/");
    if (u_starts(p, pre)) return p + cstrlen(pre);
    return 0;
}

uptr sg_cur_src = 0;                  // source of the page being rendered

// A Markdown link target -> what goes into href, or 0 when the target's scheme
// is refused (u_scheme: `javascript:`, `data:` and everything else that is not
// http/https/mailto) and the caller must not build a link at all. An allowed
// absolute URL is left alone; a `.md` of this site becomes the page's URL; any
// other file of the repository becomes a link to the source, which is the only
// honest thing to do with `[the prelude](../lib/prelude.mc)`.
uptr sg_resolve_link(uptr href) {
    i64 n = cstrlen(href);
    if (n == 0) return href;
    if (ld8(href) == '#') return href;
    if (ld8(href) == '/') return href;
    i64 sch = u_scheme(href);
    if (sch == U_SCHEME_BAD) return 0;
    if (sch == U_SCHEME_ABS) return href;
    uptr frag = "";
    uptr path = href;
    i64 h = u_chr(href, n, 0, '#');
    if (h >= 0) {
        frag = u_slice(href, h, n - h);
        path = u_slice(href, 0, h);
    }
    if (cstrlen(path) == 0) return href;
    if (sg_cur_src == 0) return href;
    uptr disk = path_join(sg_cur_src, path);
    i64 p = sg_find_src(disk);
    if (p >= 0) return u_cat4(sg_base, pg_url(p), "", frag);
    // a link to a DIRECTORY that is a rendered section (`[specs/](specs/)`)
    // resolves to that section's index page, not to the repository
    i64 s = sg_sec_by_dir(disk);
    if (s >= 0) return u_cat4(sg_base, sc_url(s), "", frag);
    uptr rel = sg_repo_rel(disk);
    if (rel != 0 && cstrlen(sg_edit) != 0 && u_file_exists(disk)) {
        return u_cat3(sg_edit, rel, frag);
    }
    return href;
}

// ---- site.toml ----
uptr sg_str(uptr key, uptr dflt) {
    uptr v = toml_get(key);
    if (v == 0) return dflt;
    return v;
}

// `true` / `false` as TOML writes them, or a plain 0/1
i64 sg_flag(uptr key, i64 dflt) {
    uptr v = toml_get(key);
    if (v == 0) return dflt;
    if (str_eq(v, "true")) return 1;
    if (str_eq(v, "false")) return 0;
    return tm_atoi(v);
}

void sg_config(uptr dir) {
    sg_dir = dir;
    sg_toml = u_join(dir, "site.toml");
    if (!u_file_exists(sg_toml)) die2("no such file", sg_toml);
    toml_parse(sg_toml);

    sg_title = sg_str("site.title", "mc");
    sg_tagline = sg_str("site.tagline", "a compiler that compiles itself");
    sg_descr = sg_str("site.description", sg_tagline);
    sg_base = sg_str("site.base_url", "/");
    if (!u_ends(sg_base, "/")) sg_base = u_cat2(sg_base, "/");
    sg_origin = sg_str("site.origin", "");
    loop {                                        // a trailing '/' would double up
        i64 n = cstrlen(sg_origin);
        if (n == 0) break;
        if (ld8(sg_origin + n - 1) != '/') break;
        sg_origin = u_slice(sg_origin, 0, n - 1);
    }
    sg_sep = sg_str("site.title_separator", " - ");
    sg_year = sg_str("site.year", "2026");
    sg_edit = sg_str("site.edit_url", "");
    sg_search = sg_flag("site.search", 1);
    sg_docs = sg_path(sg_str("site.docs", "../docs"));
    sg_out = sg_path(sg_str("site.out", "public"));
    sg_tpldir = sg_path(sg_str("site.templates", "templates"));
    sg_staticdir = sg_path(sg_str("site.static", "static"));
    sg_repo = sg_path(sg_str("site.repo", ".."));
    uptr home = toml_get("site.home");
    if (home != 0) sg_home_src = u_join(sg_docs, home);
    sg_load_nav_extra();                          // needs sg_base
}

// ---- templates and required assets ----
uptr sg_template(uptr name) {
    uptr p = u_join(sg_tpldir, name);
    if (!u_file_exists(p)) die2("missing template", p);
    i64 len = 0;
    return read_file(p, &len);
}

void sg_need_asset(uptr name) {
    uptr p = u_join(sg_staticdir, name);
    if (!u_file_exists(p)) die2("missing static file the templates reference", p);
}

void sg_load_templates() {
    sg_t_base = sg_template("base.html");
    sg_t_page = sg_template("page.html");
    sg_t_home = sg_template("home.html");
    sg_t_404 = sg_template("404.html");
    sg_need_asset("site.css");
    sg_need_asset("favicon.svg");
    sg_need_asset("icon-32.png");
    sg_need_asset("icon-180.png");
    sg_need_asset("social.png");
    if (sg_search) sg_need_asset("search.js");
}

// The header links named by [site].nav_extra, in that order. Each name is a
// [navlink.<name>] table with `title` and `url`; with no nav_extra the
// {{nav_extra}} placeholder is empty and the header is exactly what it was.
// A url with a refused scheme is a hard error here, because unlike a Markdown
// link this one was written by whoever configured the site.
void sg_load_nav_extra() {
    sg_extra_url = sl_new();
    u8 b[BUF_SIZE];
    buf_init(b);
    i64 n = toml_count("site.nav_extra");
    i64 i = 0;
    loop {
        if (i >= n) break;
        uptr id = toml_get_array("site.nav_extra", i);
        uptr title = sg_str(u_cat3("navlink.", id, ".title"), u_title_from_slug(id));
        uptr url = sg_str(u_cat3("navlink.", id, ".url"), u_cat2(sg_base, id));
        if (u_scheme(url) == U_SCHEME_BAD) die2("refused link scheme in site.toml", url);
        sl_add(sg_extra_url, url);
        u_put(b, "    <a href=\"");
        u_esc(b, url);
        u_put(b, "\">");
        u_esc_text(b, title);
        u_put(b, "</a>\n");
        i = i + 1;
    }
    sg_extra_html = u_take(b);
}

// ---- discovery ----
// the sections named by [site].nav, in that order; a section whose directory is
// missing still gets its index page, so the header navigation never 404s
void sg_load_sections() {
    i64 n = toml_count("site.nav");
    i64 i = 0;
    loop {
        if (i >= n) break;
        uptr id = toml_get_array("site.nav", i);
        uptr title = sg_str(u_cat3("section.", id, ".title"), u_title_from_slug(id));
        uptr url = sg_str(u_cat3("section.", id, ".url"), u_cat2(id, "/"));
        if (!u_ends(url, "/")) url = u_cat2(url, "/");
        uptr rel = sg_str(u_cat3("section.", id, ".dir"), id);
        uptr dir = u_join(sg_docs, rel);
        if (str_eq(rel, ".")) dir = sg_docs;
        if (!u_dir_exists(dir)) dir = 0;
        sg_sec_new(id, title, dir, url);
        i = i + 1;
    }
}

// the section's index source: index.md, then README.md, then nothing
uptr sg_section_index_src(i64 s) {
    if (sc_dir(s) == 0) return 0;
    uptr a = u_join(sc_dir(s), "index.md");
    if (u_file_exists(a)) return path_norm(a);
    uptr b = u_join(sc_dir(s), "README.md");
    if (u_file_exists(b)) return path_norm(b);
    return 0;
}

// the pages of a section, in reading order: the slugs listed in `order` first,
// in that order, then everything else sorted by file name
uptr sg_section_files(i64 s) {
    uptr out = sl_new();
    if (sc_dir(s) == 0) return out;
    uptr all = u_listdir(sc_dir(s), DT_REG);
    uptr named = sl_new();
    i64 nord = toml_count(u_cat3("section.", sc_id(s), ".order"));
    i64 i = 0;
    loop {
        if (i >= nord) break;
        uptr want = toml_get_array(u_cat3("section.", sc_id(s), ".order"), i);
        i64 k = 0;
        loop {                                    // by file name or by slug
            if (k >= sl_n(all)) break;
            uptr f = sl_at(all, k);
            if (u_ends(f, ".md") && !sl_has(named, f)) {
                if (str_eq(f, u_cat2(want, ".md")) || str_eq(sg_slug_of(f), want)) {
                    sl_add(out, f);
                    sl_add(named, f);
                    break;
                }
            }
            k = k + 1;
        }
        i = i + 1;
    }
    i = 0;
    loop {
        if (i >= sl_n(all)) break;
        uptr f = sl_at(all, i);
        if (u_ends(f, ".md") && !sl_has(named, f)
            && !str_eq(f, "index.md") && !str_eq(f, "README.md")) {
            sl_add(out, f);
        }
        i = i + 1;
    }
    return out;
}

// "00-getting-started.md" -> "getting-started". The numeric prefix is what puts
// the guide in reading order in a sorted listing (docs/specs/M26.md); it is a
// sorting device, not part of the address.
uptr sg_slug_of(uptr file) {
    uptr name = u_slice(file, 0, cstrlen(file) - 3);
    i64 k = 0;
    loop {
        if (!is_digit(ld8(name + k))) break;
        k = k + 1;
    }
    if (k > 0 && ld8(name + k) == '-' && ld8(name + k + 1) != 0) name = name + k + 1;
    return u_slug(name);
}

void sg_scan() {
    i64 home = sg_page_new(sg_home_src, "index", 0 - 1, "", PK_HOME);
    set_pg_title(home, sg_title);
    i64 s = 0;
    loop {
        if (s >= sg_ns) break;
        i64 ip = sg_page_new(sg_section_index_src(s), sc_id(s), s, sc_url(s), PK_INDEX);
        set_pg_title(ip, sc_title(s));
        set_sc_idx(s, ip);
        uptr files = sg_section_files(s);
        i64 i = 0;
        loop {
            if (i >= sl_n(files)) break;
            uptr f = sl_at(files, i);
            uptr src = path_norm(u_join(sc_dir(s), f));
            if (sg_home_src != 0 && str_eq(src, path_norm(sg_home_src))) { i = i + 1; continue; }
            uptr slug = sg_slug_of(f);
            sg_page_new(src, slug, s, u_cat3(sc_url(s), slug, "/"), PK_PAGE);
            i = i + 1;
        }
        s = s + 1;
    }
    sg_page_new(0, "404", 0 - 1, "404", PK_404);
}

// ---- rendering ----
// the body of a section index nobody wrote by hand: the section's pages, each
// with its first paragraph
uptr sg_index_body(i64 p) {
    i64 s = pg_sect(p);
    u8 b[BUF_SIZE];
    buf_init(b);
    u_put(b, "<h1>");
    u_esc_text(b, sc_title(s));
    u_put(b, "</h1>\n");
    i64 count = 0;
    i64 i = 0;
    loop {
        if (i >= sg_np) break;
        if (pg_sect(i) == s && pg_kind(i) == PK_PAGE) count = count + 1;
        i = i + 1;
    }
    if (count == 0) {
        u_put(b, "<p>This section has no pages yet.</p>\n");
        return u_take(b);
    }
    u_put(b, "<ul>\n");
    i = 0;
    loop {
        if (i >= sg_np) break;
        if (pg_sect(i) == s && pg_kind(i) == PK_PAGE) {
            u_put(b, "<li><a href=\"");
            u_esc(b, u_cat2(sg_base, pg_url(i)));
            u_put(b, "\">");
            u_esc_text(b, pg_title(i));
            u_put(b, "</a>");
            if (cstrlen(pg_desc(i)) != 0) {
                u_put(b, " - ");
                u_esc_text(b, pg_desc(i));
            }
            u_put(b, "</li>\n");
        }
        i = i + 1;
    }
    u_put(b, "</ul>\n");
    return u_take(b);
}

void sg_render_page(i64 p) {
    if (pg_src(p) == 0) return;
    i64 len = 0;
    uptr src = read_file(pg_src(p), &len);
    sg_cur_src = pg_src(p);
    hl_file = pg_src(p);
    md_reset(pg_src(p));
    md_no_h1 = pg_kind(p) == PK_HOME;             // home.html already carries the h1
    uptr body = md_render(src, len);
    set_pg_body(p, body);
    set_pg_toc(p, md_toc_html());
    set_pg_hid(p, md_hid);
    set_pg_htxt(p, md_htext);
    if (md_title != 0 && cstrlen(md_title) != 0) set_pg_title(p, md_title);
    if (md_desc != 0) set_pg_desc(p, md_desc);
    if (pg_kind(p) == PK_HOME && md_h1n != 0) {
        out_str(2, "mcsite: the home content must not have an h1 (home.html has one): ");
        out_str(2, pg_src(p));
        out_str(2, "\n");
    }
    if (pg_kind(p) != PK_HOME && md_h1n > 1) {
        out_str(2, "mcsite: ");
        out_num(2, md_h1n - 1);
        out_str(2, " extra h1 demoted to h2 in ");
        out_str(2, pg_src(p));
        out_str(2, "\n");
    }
    if (pg_kind(p) != PK_HOME && md_h1n == 0) {
        // page.html has no heading of its own, so a document that opens with
        // `## ` gets one built from its title: every page has exactly one h1.
        u8 h[BUF_SIZE];
        buf_init(h);
        u_put(h, "<h1>");
        u_esc_text(h, pg_title(p));
        u_put(h, "</h1>\n");
        u_put(h, pg_body(p));
        set_pg_body(p, u_take(h));
        out_str(2, "mcsite: no h1, one was built from the title: ");
        out_str(2, pg_src(p));
        out_str(2, "\n");
    }
    sg_cur_src = 0;
    hl_file = 0;
}

void sg_render_all() {
    i64 i = 0;
    loop {
        if (i >= sg_np) break;
        sg_render_page(i);
        i = i + 1;
    }
    i = 0;                            // the generated indexes need the titles above
    loop {
        if (i >= sg_np) break;
        if (pg_kind(i) == PK_INDEX && pg_src(i) == 0) set_pg_body(i, sg_index_body(i));
        i = i + 1;
    }
}

// ---- navigation, outline, pager ----
uptr sg_nav(i64 cur) {
    u8 b[BUF_SIZE];
    buf_init(b);
    u_put(b, "<ul class=\"nav-list\">\n");
    i64 s = 0;
    loop {
        if (s >= sg_ns) break;
        i64 ip = sc_idx(s);
        u_put(b, "<li class=\"nav-section\">\n<a class=\"nav-section-title\" href=\"");
        u_esc(b, u_cat2(sg_base, sc_url(s)));
        u_put(b, "\"");
        if (ip == cur) u_put(b, " aria-current=\"page\"");
        u_put(b, ">");
        u_esc_text(b, sc_title(s));
        u_put(b, "</a>\n");
        i64 open = 0;                             // an empty <ul> helps nobody
        i64 i = 0;
        loop {
            if (i >= sg_np) break;
            if (pg_sect(i) == s && pg_kind(i) == PK_PAGE) {
                if (!open) { u_put(b, "<ul class=\"nav-list\">\n"); open = 1; }
                u_put(b, "<li><a href=\"");
                u_esc(b, u_cat2(sg_base, pg_url(i)));
                u_put(b, "\"");
                if (i == cur) u_put(b, " aria-current=\"page\"");
                u_put(b, ">");
                u_esc_text(b, pg_title(i));
                u_put(b, "</a></li>\n");
            }
            i = i + 1;
        }
        if (open) u_put(b, "</ul>\n");
        u_put(b, "</li>\n");
        s = s + 1;
    }
    u_put(b, "</ul>\n");
    return u_take(b);
}

// reading order: the sidebar's order, home and 404 excluded
i64 sg_prev(i64 p) {
    i64 i = p - 1;
    loop {
        if (i < 0) break;
        if (pg_kind(i) == PK_PAGE || pg_kind(i) == PK_INDEX) return i;
        i = i - 1;
    }
    return 0 - 1;
}

i64 sg_next(i64 p) {
    i64 i = p + 1;
    loop {
        if (i >= sg_np) break;
        if (pg_kind(i) == PK_PAGE || pg_kind(i) == PK_INDEX) return i;
        i = i + 1;
    }
    return 0 - 1;
}

// ---- the search form and the tag that loads its script ----
// One placeholder, {{search}}: the form, and a <script src=...> for the code
// that makes it work. The code itself is site/static/search.js, copied verbatim
// into site/public like every other static file.
//
// It is NOT inline, and that is a hard requirement rather than a preference:
// the site is served with `Content-Security-Policy: default-src 'self';
// script-src 'self'`, which refuses an inline <script>, an inline style and
// every on*= attribute. site/tools/checkhtml.py asserts all three over every
// rendered page, so a template that grows one fails the build.
//
// base_url reaches the script through a data attribute, because a static file
// never goes through tmpl.mc. The form starts hidden and the script reveals it,
// so a reader with no JavaScript is never shown a box that cannot search; the
// index is fetched on the first keystroke, never on load.
uptr sg_search_html() {
    if (!sg_search) return u_dup("");
    u8 b[BUF_SIZE];
    buf_init(b);
    u_put(b, "<form class=\"site-search\" role=\"search\" hidden>\n");
    u_put(b, "  <label class=\"visually-hidden\" for=\"site-search-input\">Search the documentation</label>\n");
    u_put(b, "  <input id=\"site-search-input\" type=\"search\" autocomplete=\"off\" placeholder=\"Search\">\n");
    u_put(b, "  <ul class=\"search-results\" hidden></ul>\n");
    u_put(b, "</form>\n");
    u_put(b, "<script src=\"");
    u_esc(b, sg_base);
    u_put(b, "static/search.js\" data-search-base=\"");
    u_esc(b, sg_base);
    u_put(b, "\" defer></script>\n");
    return u_take(b);
}

// ---- writing ----
uptr sg_page_url(i64 p) {
    if (pg_kind(p) == PK_404) return u_cat3(sg_origin, sg_base, "404.html");
    return u_cat3(sg_origin, sg_base, pg_url(p));
}

uptr sg_full_title(i64 p) {
    if (pg_kind(p) == PK_HOME) return u_cat3(sg_title, sg_sep, sg_tagline);
    return u_cat3(pg_title(p), sg_sep, sg_title);
}

#define SG_DESCMAX 200                // bytes of <meta name=description>

uptr sg_desc_of(i64 p) {
    if (cstrlen(pg_desc(p)) != 0) return u_clip(pg_desc(p), SG_DESCMAX);
    if (pg_kind(p) == PK_HOME) return sg_descr;
    return u_cat4(pg_title(p), " - ", sg_title, " documentation.");
}

void sg_write_page(i64 p) {
    uptr c = tp_new();
    tp_set(c, "site_title", u_escaped(sg_title));
    tp_set(c, "base_url", u_escaped(sg_base));
    tp_set(c, "page_title", u_escaped(sg_full_title(p)));
    tp_set(c, "page_description", u_escaped(sg_desc_of(p)));
    tp_set(c, "page_url", u_escaped(sg_page_url(p)));
    tp_set(c, "year", u_escaped(sg_year));
    tp_set(c, "search", sg_search_html());
    tp_set(c, "nav_extra", sg_extra_html);
    tp_set(c, "content", pg_body(p));
    tp_set(c, "nav", "");
    tp_set(c, "toc", "");
    tp_set(c, "prev_url", "");
    tp_set(c, "prev_title", "");
    tp_set(c, "next_url", "");
    tp_set(c, "next_title", "");
    tp_set(c, "edit_url", "");

    uptr tmpl = sg_t_page;
    if (pg_kind(p) == PK_HOME) tmpl = sg_t_home;
    if (pg_kind(p) == PK_404)  tmpl = sg_t_404;
    if (tmpl == sg_t_page) {
        tp_set(c, "nav", sg_nav(p));
        tp_set(c, "toc", pg_toc(p));
        i64 pv = sg_prev(p);
        i64 nx = sg_next(p);
        if (pv >= 0) {
            tp_set(c, "prev_url", u_escaped(u_cat2(sg_base, pg_url(pv))));
            tp_set(c, "prev_title", u_escaped(pg_title(pv)));
        }
        if (nx >= 0) {
            tp_set(c, "next_url", u_escaped(u_cat2(sg_base, pg_url(nx))));
            tp_set(c, "next_title", u_escaped(pg_title(nx)));
        }
        if (pg_src(p) != 0 && cstrlen(sg_edit) != 0) {
            uptr rel = sg_repo_rel(pg_src(p));
            if (rel != 0) tp_set(c, "edit_url", u_escaped(u_cat2(sg_edit, rel)));
        }
    }
    uptr inner = tp_render(tmpl, c);
    tp_set(c, "content", inner);
    uptr html = tp_render(sg_t_base, c);

    u8 out[BUF_SIZE];
    buf_init(out);
    u_put(out, html);
    uptr path = u_join(sg_out, "404.html");
    if (pg_kind(p) != PK_404) path = u_join(sg_out, u_cat2(pg_url(p), "index.html"));
    u_write(path, out);
}

// ---- search index and sitemap ----
void sg_json_str(uptr b, uptr s) {
    i64 n = cstrlen(s);
    i64 i = 0;
    buf_u8(b, '"');
    loop {
        if (i >= n) break;
        i64 c = ld8(s + i);
        if (c == '"')       u_put(b, "\\\"");
        else if (c == '\\') u_put(b, "\\\\");
        else if (c == '\n') u_put(b, "\\n");
        else if (c == '\t') u_put(b, "\\t");
        else if (c == '\r') u_put(b, "\\r");
        else if (c < 32)    u_put(b, " ");
        else                buf_u8(b, c);
        i = i + 1;
    }
    buf_u8(b, '"');
}

void sg_write_search() {
    if (!sg_search) return;
    u8 b[BUF_SIZE];
    buf_init(b);
    u_put(b, "[\n");
    i64 first = 1;
    i64 i = 0;
    loop {
        if (i >= sg_np) break;
        if (pg_kind(i) != PK_404) {
            if (!first) u_put(b, ",\n");
            first = 0;
            u_put(b, "{\"u\":");
            sg_json_str(b, u_cat2(sg_base, pg_url(i)));
            u_put(b, ",\"t\":");
            sg_json_str(b, pg_title(i));
            u_put(b, ",\"s\":");
            if (pg_sect(i) >= 0) sg_json_str(b, sc_title(pg_sect(i)));
            else                 sg_json_str(b, sg_title);
            u_put(b, ",\"d\":");
            sg_json_str(b, pg_desc(i));
            u_put(b, ",\"h\":[");
            i64 k = 0;
            loop {
                if (k >= sl_n(pg_hid(i))) break;
                if (k) u_put(b, ",");
                u_put(b, "{\"i\":");
                sg_json_str(b, sl_at(pg_hid(i), k));
                u_put(b, ",\"t\":");
                sg_json_str(b, sl_at(pg_htxt(i), k));
                u_put(b, "}");
                k = k + 1;
            }
            u_put(b, "]}");
        }
        i = i + 1;
    }
    u_put(b, "\n]\n");
    u_write(u_join(sg_out, "search.json"), b);
}

void sg_write_sitemap() {
    u8 b[BUF_SIZE];
    buf_init(b);
    u_put(b, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    u_put(b, "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n");
    i64 i = 0;
    loop {
        if (i >= sg_np) break;
        if (pg_kind(i) != PK_404) {
            u_put(b, "  <url><loc>");
            u_esc(b, sg_page_url(i));
            u_put(b, "</loc></url>\n");
        }
        i = i + 1;
    }
    u_put(b, "</urlset>\n");
    u_write(u_join(sg_out, "sitemap.xml"), b);
}

// ---- static files ----
void sg_copy_tree(uptr src, uptr dst, i64 depth) {
    if (depth > 4) return;
    u_mkdir(dst);
    uptr files = u_listdir(src, DT_REG);
    i64 i = 0;
    loop {
        if (i >= sl_n(files)) break;
        u_copy_file(u_join(src, sl_at(files, i)), u_join(dst, sl_at(files, i)));
        i = i + 1;
    }
    uptr dirs = u_listdir(src, DT_DIR);
    i = 0;
    loop {
        if (i >= sl_n(dirs)) break;
        sg_copy_tree(u_join(src, sl_at(dirs, i)), u_join(dst, sl_at(dirs, i)), depth + 1);
        i = i + 1;
    }
}

// ---- the build ----
// which fence languages go through the bundled lexer. The contract's default is
// `mc` alone (site/README.md § Code highlighting); a site says otherwise in
// [site].highlight.
void sg_load_langs() {
    i64 n = toml_count("site.highlight");
    if (n == 0) { hl_lang_add("mc"); return; }
    i64 i = 0;
    loop {
        if (i >= n) break;
        hl_lang_add(toml_get_array("site.highlight", i));
        i = i + 1;
    }
}

void sg_build(uptr dir) {
    sg_config(dir);
    hl_init(sg_repo);
    sg_load_langs();
    sg_load_templates();
    sg_load_sections();
    sg_scan();
    sg_render_all();
    u_rmtree(sg_out, 0);
    i64 i = 0;
    loop {
        if (i >= sg_np) break;
        sg_write_page(i);
        i = i + 1;
    }
    sg_write_search();
    sg_write_sitemap();
    sg_copy_tree(sg_staticdir, u_join(sg_out, "static"), 0);
    out_str(1, "mcsite: ");
    out_num(1, sg_np);
    out_str(1, " pages, ");
    out_num(1, sg_ns);
    out_str(1, " sections, ");
    out_num(1, hl_done);
    out_str(1, " fences highlighted (");
    out_num(1, hl_notes);
    out_str(1, " kept plain) -> ");
    out_str(1, sg_out);
    out_str(1, "\n");
}
