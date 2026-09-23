# mc — a self-hosting mini compiler, teachable through its surface

Read `docs/plan.md` before any work: it fixes the language, the teaching surface,
the architecture, the budget, and the milestones. This file only summarizes the operating rules.

## Roles
The user is the owner; the main session is the **architect** and **delegates all creation** to
agents (`.claude/agents/`): `stage0-dev` (C23), `mc-dev` (`.mc` code), `reviewer`, `verifier`,
`docs-writer`, `designer` (site identity/layout/icon), `ts-dev` (VS Code extension). Agents report facts (commands run + output), never assumptions.

## Inviolable rules
- `stage0/*.c` ≤ 3000 lines total (`make budget`). Exceeding it is a build failure.
- stage0 uses **only** `open/read/write/close/_exit` from libc (arena.c). No stdio/malloc/qsort.
- Every file field is written byte by byte in little-endian via `buf_u8/u16/u32/u64`. Never `fwrite(&struct)`.
- Determinism (`docs/plan.md` § Determinism): no pointer hashing, no iterating hash tables for
  output, stable partitioning of symbols, no `__FILE__`/dates/paths, zeroed padding.
- C code has the **same shape** it will have in `.mc`: small functions, flat data in an arena,
  no struct-as-file-layout, no clever textual macros. stage0 will be transliterated 1:1 into `src/*.mc`.
- Comments, messages and docs in English; ASCII identifiers; no emojis.
- Do not look at or copy code from the user's other projects (`~/projects/langs` is off-limits).

## Commands
- `make stage0` → `build/mc0` · `make stage0-san` (sanitizers) · `make budget` · `make test`
- `make mc1` → `build/mc1` · `make check` runs everything · `make test-exe` runs the suite via `--exe`.
- `make bundle` regenerates `src/bundle_data.mc` (generated source) from `tools/bundle.list`;
  run it whenever `lib/*.mc` or a core module changes, BEFORE `make bootstrap`. `make check`
  runs `check-bundle` first and fails loudly if the checked-in bundle is stale.
- `scripts/link.sh OUT IN.o` links with `ld -lSystem` (`ld` is allowed; gcc/cc/clang only for stage0).
  Since M11 it's optional: `build/mc1 --exe prog.mc -o prog` writes the signed executable directly.
- `make check-docs` runs `scripts/check-docs.sh`: no undocumented public symbol/flag/TOML key/
  directive, every fenced ` ```mc ` sample in `docs/` compiled (and run when it declares an
  expectation), every relative link resolving.
- `make site` → `build/mc1 build site` (compiles `site/gen/*.mc` into `build/mcsite`) then
  `build/mcsite site`, which renders `docs/` into `site/public`. `make check-site` adds
  `build/mcsite site --check` (internal links in mc, then `site/tools/checkhtml.py` and
  `contrast.py` when `python3` is there). Both are in `make check`, last.
- Inspection: `otool -hlv X.o`, `otool -r X.o`, `nm -m X.o`; for the executable, `otool -l`,
  `codesign -dvvv`, `codesign --verify --verbose=4`.

## State
- M0 done (manual `.o`, exit 42) · M0.5 done (svc works under dyld; static is killed by the kernel)
- M1 done, verified and reviewed (lexer, Pratt, AST, dumps, constant codegen)
- M2 done, verified and reviewed (locals, calls, extern, ld/st, spill)
- M3 done (globals, arrays, strings, `&x`, `#include`, `#define`, `extern`, arena)
- M4 done (tokenizer in `.mc`; `make check-lex` cross-checks `--dump-tokens` against `src/lexdump.mc`)
- M5 done (4 relocations, `#section`, `#opcode`, `emit()`/`reloc()`, `lib/sys_svc.mc`)
- M5.5 done (`\0` forbidden in a string, `path_join` normalizes `.`/`..`, token carries its file,
  `#define` vs a name, section order, initialized global array, `udiv`, prototype)
  — 2492/3000 lines, `make test` 24/24, `make check-lex` 31/31
- M5.6 done (`reloc()` only attaches to a raw word; `__data` and `#section` with no ALIGN default
  to 16-byte alignment; `MAXSECS`/`MAXPARAMS` only in `mc.h`; `creat` instead of variadic `open`
  when writing a file — `stage0/arena.c`, `lib/sys.mc`, `lib/sys_svc.mc`, `src/arena.mc`;
  `cmp_cond` via table)
  — 2497/3000 lines, `make test` 24/24, `make check-lex` 36/36
- M6 done (`docs/specs/M6-M7.md`): `src/mc.mc` complete (`arena.mc`, `macho.mc`, `lex.mc`, `ast.mc`,
  `parse.mc`, `gen_arm64.mc`, `main.mc`) — 4310 lines of `.mc` against 2678 of C (`stage0/*.c` +
  `mc.h`), a factor of 1.6. `MAXDEFS 512` on both sides (`stage0/parse.c` and `src/parse.mc`).
  stage0 at 2500/3000 lines (`make budget`). `make mc1` builds `build/mc1`; `check-asm` 39/39,
  `check-obj` 24/24, `scripts/test.sh build/mc1` 24/24.
- M7 done (fixed point, `scripts/bootstrap.sh` + `make bootstrap`): `mc0→mc1.o`, `mc1→mc2.o`,
  `mc2→mc3.o`, `cmp mc2.o mc3.o` identical (163632 bytes). Golden recorded in
  `tests/golden/mc2.sha256` (see `tests/golden/README.md` for when to update it).
- M8 done (`docs/bootstrap.md`): `clang` only compiles stage0 (`CC = clang` in the Makefile,
  targets `build/mc0`/`build/mc0-san`); confirmed with `grep -rn clang scripts/ Makefile`. `ld`
  is still used via `scripts/link.sh`. Binaries are not versioned (`build/` in `.gitignore`).
- M9 done (`docs/specs/M9.md`): `#rule stmt:` implemented in stage0 **and** in `src/parse.mc` —
  a linear table indexed by the opening token, items `{literal | nt $name}` with
  `nt ∈ {expr,stmt,block,ident}`, template parsed at definition time (`N_HOLE` for a node, a name
  marker for `ident $x`/gensym), backtracking-free matching, deterministic gensym (`__g<N>` in M9,
  fixed to `$g<N>` in M10 — see the M10 entry),
  `--dump-rules`. `lib/prelude.mc` (36 lines) provides `while`/`for`/`+=`/`-=`/`++`/`--`; tests
  `050`–`054` in the suite and `tests/err/055-keyword.mc` as an error case outside it.
  `src/macho.mc` migrated to the prelude (a leaf module). Out of scope by spec decision:
  `#rule expr:` (reserved), the `type $t` hole and therefore `struct`.
  — stage0 2747/3000 lines; `make check` green: `test` 29/29, `check-lex` 45/45,
  `check-ast` 45/45, `check-asm` 45/45, `check-obj` 29/29, `bootstrap` at a fixed point
  (`mc2.o == mc3.o`, 181504 bytes) and golden re-recorded in `tests/golden/mc2.sha256`.
- M10 done (`docs/specs/M10.md`): **Tier 2 — passes and backends taught through the surface**.
  Core (on both sides): `&name` of a function/extern becomes `uptr` (adrp/add with `PAGE21`+
  `PAGEOFF12`; an undefined symbol when `extern`) and the intrinsic `callp(p, a1..a7)` (args in
  `x0..x6`, `p` in `x16`, `blr x16`, the same live-depth saving as `bl`, `i64` result) —
  `tests/060-callp.mc`. `gen` split into two public halves: `gen_lower(root)` (AST → per-function
  `Ins` buffer, sections, globals, strings and symbols, without encoding) and `gen_encode_all()`,
  plus ~16 accessors (`gen_func_count/gen_ins_at/gen_prel_*`…). Symbol-creation order was
  preserved on purpose: the 29 prior `.o` files come out **byte for byte identical** to `mc0`'s
  pre-M10 output.
  Hooks only in `.mc` (`src/hooks.mc` with `pass`/`backend`, `src/user.mc` → `lib/user_default.mc`);
  the driver calls `user_init()` before parsing, applies the passes over the AST, and picks the
  backend via `--backend=NAME` (default `macho` = `gen_lower`+`gen_encode_all`+`macho_write`).
  Stage0 in C is **not** teachable: it only accepts `--backend=macho` (documented in
  `docs/surface.md` § Tier 2).
  Proof: `lib/backend_arm64.mc` (the `arm64-surface` backend, reimplementing the whole encoder in
  `.mc` on top of the public API) and `lib/pass_demo.mc` (`x * 1` → `x`), wired together by
  `lib/user_demo.mc`; `make check-surface` wires up the demo, rebuilds, and compares — **32/32**
  objects identical to the built-in backend, then reverts `src/user.mc` to the default (the demo
  is opt-in).
  Along with it came three fixes from the M9 review: gensym changed from `__g<N>` to `$g<N>`
  (the lexer never forms an identifier containing `$`, so capture is impossible —
  `tests/056-gensym-nocapture.mc`), a `#rule` whose dispatch literal is a core keyword or type is
  now rejected (`cannot redefine core keyword`), and an overflowed `MAXRULES` now uses `err_at`
  with a position.
  — stage0 2843/3000 lines (M10 cost +89 and the M9 fixes +7, for a total of +96 over 2747);
  `make check` green: `test` 32/32, `check-lex` 54/54, `check-ast` 54/54, `check-asm` 54/54,
  `check-obj` 32/32, `check-surface` 32/32, `bootstrap` at a fixed point (`mc2.o == mc3.o`,
  191368 bytes) and golden re-recorded in `tests/golden/mc2.sha256`.
- M11 done, verified and reviewed; the plan is complete; see `docs/bootstrap.md`
  (`docs/specs/M11.md`): **direct executable (`mc --exe`), no `ld`**. The executable is a
  backend written in `.mc` — `src/backend_exe.mc` (858 lines), registered by default in the
  driver as `macho-exe`, with `--exe` as its alias. It reuses `gen_lower` + `gen_encode_all` (the
  same encoder and the same sections/relocs as the `macho` backend) and does what `ld` used to
  do: segment layout with 16 KiB pages (`__PAGEZERO`/`__TEXT`/`__DATA`/`__LINKEDIT`, one
  `LC_SEGMENT_64` per distinct segname), its own resolution of
  `BRANCH26`/`PAGE21`/`PAGEOFF12`/`UNSIGNED`, `__TEXT,__stubs` + `__DATA,__got` per imported
  symbol with **bind opcodes** (`LC_DYLD_INFO_ONLY`, no lazy/weak/export), **rebase** for every
  `UNSIGNED` (PIE), the 13 load commands (`LC_MAIN`, `LC_LOAD_DYLINKER`, `LC_LOAD_DYLIB
  libSystem`, `LC_UUID` derived from a SHA-256 of the content, `LC_CODE_SIGNATURE`) and an
  **ad-hoc signature** (`CS_SuperBlob`/`CS_CodeDirectory` v0x20400, SHA-256 per 4 KiB page,
  `CS_ADHOC`, `execSeg*`, identifier = the output's basename). `src/sha256.mc` (177 lines) is
  SHA-256 written in the language, checked against `shasum -a 256` on 7 vectors. Fields verified
  one by one against the `ld` reference (`-no_fixup_chains`) — see `docs/macho-notes.md` § M11.
  `--exe` **does not exist in stage0**: the C code is the seed and stays with just
  `--backend=macho`.
  Proofs: `scripts/test-exe.sh` (target `make test-exe`, inside `make check`) runs the whole
  suite via `--exe` — **32/32**, with `codesign --verify` on each binary; `codesign -dvvv` shows
  `flags=0x2(adhoc)`. Self-hosting without `ld`: `build/mc1 --exe src/mc.mc -o build/mc-exe`
  (210835 bytes), `build/mc-exe src/mc.mc -o x.o` identical to `build/mc2.o`, and
  `build/mc-exe --exe src/mc.mc -o build/fix/mc-exe` byte-for-byte identical to `build/mc-exe`
  (the executable's fixed point only holds for the same *basename*: the signature's identifier
  is the output file's name, same as `codesign` — see `docs/bootstrap.md` § M11).
  Along with it came two fixes from the M10 review, both only in `src/`: `MAXFUNCS` went from 512
  to 1024 (the C side was already 1024; with the two new files `mc1 → mc2` would have died with
  `too many functions`) and `user_init()` is now called **after** `tok_init()`/`lex_init()`
  (before that, a `user_init` calling `tok_add` would shift `K_U8..K_EXTERN` and break the core —
  `lib/user_tokadd.mc` plus the new case in `scripts/check-surface.sh` guard against this).
  — stage0 **untouched**, 2843/3000 lines; `make check` green: `test` 32/32, `check-lex` 57/57,
  `check-ast` 57/57, `check-asm` 57/57, `check-obj` 32/32, `check-surface` 32/32, `test-exe` 32/32,
  `bootstrap` at a fixed point (`mc2.o == mc3.o`, 225424 bytes) and golden re-recorded in
  `tests/golden/mc2.sha256` (the `--dump-asm` diff between `mc1` and `mc2` comes out empty).
- Post-M11 batch (review): `reloc(UNSIGNED, "sym")` followed by `emit()`/`#opcode` used to be
  accepted and would record an 8-byte relocation (`length 3`) over a 4-byte word, overwriting the
  following instruction — reproduced on both backends (`otool -r`: `address 00000008, length 3`).
  `gen_word` now rejects it on both sides with the same message, `reloc UNSIGNED requires 8
  bytes: use a global array initializer` (`stage0/gen_arm64.c` +3 lines, `src/gen_arm64.mc` +3);
  `tests/err/062-reloc-unsigned.mc` documents the case (outside `scripts/test.sh`, like `055`).
  Docs: `docs/surface.md` § `emit()`/`reloc()`; the `--exe` trade-off with an undefined symbol
  (`.o` + `ld` refuses at link time; `--exe` builds the binary and `dyld` kills it with
  `Symbol not found`, exit 134) in `docs/bootstrap.md` § M11, `docs/core-language.md` § `extern`
  and `docs/specs/M11.md` § Risks — decision recorded: no heuristic symbol list.
  — stage0 2846/3000 lines; `make check` green: `test` 32/32, `check-lex` 57/57, `check-ast` 57/57,
  `check-asm` 57/57, `check-obj` 32/32, `check-surface` 32/32, `test-exe` 32/32, `bootstrap` at a
  fixed point (`mc2.o == mc3.o`, 225640 bytes; the `--dump-asm` diff between `mc1` and `mc2` comes
  out empty) and golden re-recorded once in `tests/golden/mc2.sha256` — the codegen delta is just
  the new guard in `gen_word` (17 instructions) plus a +1 shift in the `l_strN` indices starting
  from 285.
- Arena at 32 MiB (was 256): `HEAP_SIZE` dropped on both sides (`stage0/arena.c`, `src/arena.mc`)
  because self-compiling only touches 14.5 MiB (`vmmap`; `/usr/bin/time -l build/mc1 src/mc.mc`
  gives a peak RSS of 16744448 bytes = 15.97 MiB). Single codegen delta: the `HEAP_SIZE` immediate
  in `xalloc` (`movk x10, #4096, lsl #16` → `movk x10, #512, lsl #16`); `mc2.o`'s `__bss` went
  from `0x1002ed70` to `0x0202ed70` and `build/mc1`'s from `__DATA vmsize 0x10030000` to
  `0x2030000`. `mc2.o` stays at 225640 bytes (zerofill doesn't take up file space) and golden was
  re-recorded in `tests/golden/mc2.sha256` (`ddc21ac6…b829a` → `f42cda85…39c28`). Overflow fails
  cleanly: `arena exhausted`, exit 1 (a synthetic case of 1000 functions × 12 statements, 14001
  lines; with 11 statements, 13001 lines, it still compiles). `make check` green: `test` 32/32,
  `check-lex`/`check-ast`/`check-asm` 57/57, `check-obj` 32/32, `check-surface` 32/32,
  `test-exe` 32/32, `bootstrap` at a fixed point.
- M12-core done (section A of `docs/specs/M12.md`): **Tier 3 — syntax taught through code**. `.mc`
  only; `stage0/` untouched (2846/3000). `src/core.mc` (41 lines) is the compiler **without**
  `user.mc`, and `src/mc.mc` became `#include "core.mc"` + `#include "user.mc"`: a taught compiler
  is no longer an edit to `src/user.mc` but its own file (`#include "../src/core.mc"` + modules +
  `void user_init()`). `src/astdump.mc` gained `#include "hooks.mc"` because `parse.mc` now
  consults the tables that live there.
  New registries in `src/hooks.mc` (+109 lines): `syntax(word, &f)` (top-level position,
  `MAXSYNTAX 32`), `syntax_stmt(word, &f)` (statement position), and
  `type_alias(name, TY_*)` (`MAXALIAS 64`) — linear tables, last registration wins, and all three
  reject core keywords (`word_add`, tested with `type_alias("if",…)` and
  `syntax_stmt("return",…)`: `cannot redefine core keyword`).
  `src/parse.mc` (+219): `parse_top` consults `syntax_find` before requiring a type and returns 0
  (the handler delivers via `top_add`); `parse_stmt` consults `syntax_stmt_find` before dispatching
  `#rule` and accepts the returned node (0 → an empty `N_BLOCK`); `type_of_token` falls back to
  `alias_find`, which makes the alias apply uniformly in globals, locals, parameters, `extern`,
  casts, and `p_type`.
  Fixed public API: `p_id/p_val/p_name/p_line/p_file/p_next/p_accept/p_expect/p_ident/p_type`,
  `parse_expr(0)/parse_stmt()/parse_block()/parse_params()`, `parse_function(ty,name,params)`,
  `top_add(n)`, `def_add(name,val,line,fl)`, `param_new(ty,name)`, `list_append(head,n)`.
  `#dylib "path"` (`D_DYLIB 8`, at the end of `lex.mc`'s list): a path table
  (`MAXDYLIBS 8`, ordinal = index + 2), `cur_dylib`, `extern_lib_find(name)` (default 1);
  `#dylib ""` reverts to libSystem. `src/backend_exe.mc` (+56) emits one `LC_LOAD_DYLIB` per
  dylib, puts the ordinal in `n_desc`, and swaps in `BIND_SET_DYLIB_ORD_IMM` per symbol. Verified
  against `/usr/lib/libsqlite3.dylib`: `otool -L` shows both, `nm -m` shows `(from libsqlite3)`,
  `dyld_info -fixups` shows the three binds against the right dylibs, and the program prints
  `3051000` (= SQLite 3.51.0, matching the system's `sqlite3 --version`). `.o` + `ld` ignores
  `#dylib` (`ld` refuses with `symbol(s) not found`), as already documented for M11.
  Proofs: `lib/user_syntax_demo.mc` (64 lines: `unless` via `syntax_stmt`, `enum Name { … }` via
  `syntax` generating `#define`s + an alias, `type_alias("bool", TY_U8)`),
  `lib/syntax_demo_test.mc` (uses all three, exits 42), and the entry point `lib/mc_syntax_demo.mc`
  (`#include "../src/core.mc"` + the demo). New case in `scripts/check-surface.sh` (now
  `check-surface.sh MC0 MC1`, and the target depends on `build/mc1`): `mc1 --exe
  lib/mc_syntax_demo.mc`, the binary compiles the test via `--exe`, runs it, and exits 42 — and
  the default compiler **refuses** the same source (`type expected at top level`).
  — `make check` green: `budget` 2846/3000, `test` 32/32, `check-lex` 61/61, `check-ast` 61/61,
  `check-asm` 61/61, `check-obj` 32/32, `check-surface` 32/32 + Tier 3, `test-exe` 32/32,
  `bootstrap` at a fixed point (`mc2.o == mc3.o`, 235960 bytes; `--dump-asm` diff between `mc1` and
  `mc2` empty) and golden re-recorded once in `tests/golden/mc2.sha256`
  (`f42cda85…39c28` → `905f52c1…fbbc4`). Self-hosting without `ld` still holds:
  `build/mc1 --exe src/mc.mc -o build/mc-exe` and `build/mc-exe src/mc.mc` identical to `build/mc2.o`.
- M12 done (section B of `docs/specs/M12.md`): **`examples/api`** — a to-do-list HTTP API with SQLite
  persistence, written using `class`, `interface`, `bool`, and `str` — four things the language
  doesn't have. `src/` and `stage0/` **untouched** by this section: the whole surface comes from
  `examples/api/oop.mc` (482 lines, running inside the compiler through the parser's public API)
  plus `examples/api/mc-api.mc` (20 lines: `#include "../../src/core.mc"` + `oop.mc` +
  `user_init()` with two `syntax` and two `type_alias`). The program: `main.mc` (359 lines) with
  `class Request`/`Response`/`Todo`/`Db`, `interface Handler`, and `class TodoHandler : Handler` /
  `class HealthHandler : Handler`; routing via a linear (prefix, `Handler`) table dispatched
  through the vtable (`callp`, M10) — the main loop never knows which handler it is calling. The
  seven `class`/`interface` declarations become **39** ordinary declarations (`--dump-ast`), with
  `TODO_ID=0 TODO_TITLE=8 TODO_DONE=16 TODO_SIZE=24 HANDLER_HANDLE=0 TODOHANDLER_SIZE=8` checked
  by a program that prints them. Libraries from the other agent: `lib/rt.mc` (a fixed 4 MiB arena,
  strbuf, strings), `lib/http.mc` (sockets, HTTP/1.1 request/response), and `lib/sqlite.mc`
  (`#dylib "/usr/lib/libsqlite3.dylib"` + 13 externs + wrappers). Routes: `GET /health` →
  `{"ok":true}`, `GET /todos` → a JSON list, `POST /todos` (body = title) → `201` with the created
  todo, `DELETE /todos/N` → `{"deleted":N}`, 404 for everything else; arguments `PORT DB_PATH`,
  one connection at a time.
  `examples/api/test.sh` (139 lines) starts the server on a free port with a temporary database,
  hits every route with `curl`, compares body **and** status, checks the final state with the
  system's `sqlite3` (`2|pay bill|0`), and kills the server. `examples/api/Makefile`: `mc-api`,
  `api`, `test-oop`, `test-lib`, `test-api`, `test`, `clean` — no dependency beyond
  `../../build/mc1` (built by the root if missing), `curl`, and `sqlite3`. The root Makefile
  gained `check-examples` (`make -C examples/api test`) inside `make check`.
  Proofs: `build/api` at 55616 bytes, `codesign --verify` OK and `flags=0x2(adhoc)`, `otool -L`
  showing both libSystem **and** libsqlite3, `nm -m` with 13 `_sqlite3_*` symbols
  `(from libsqlite3)`; the default compiler refuses the same source
  (`examples/api/main.mc:27: type expected in parameter` — `str`).
  Operational detail that cost a build: overwriting a signed executable at the same inode makes
  the kernel kill the next run with `Killed: 9`, so the `Makefile` and `test.sh` `rm -f` the
  target before every build. Docs: `examples/api/README.md` (new) and `docs/surface.md` § Tier 3
  gained "The real example: `examples/api`".
  — `stage0/` untouched, 2846/3000; `make check` green end to end: `test` 32/32, `check-lex`
  61/61, `check-ast` 61/61, `check-asm` 61/61, `check-obj` 32/32, `check-surface` 32/32,
  `test-exe` 32/32, `bootstrap` at a fixed point (`mc2.o == mc3.o`) and golden **unchanged**
  (`905f52c1…fbbc4` matches `tests/golden/mc2.sha256`), `check-examples` green.
- M14 done (`docs/specs/M14.md`, `docs/build.md`): **project driver and `mc.toml`**.
  `mc build [DIR] [--config FILE]` reads a TOML file and drives the whole build; the single-file
  CLI (`mc in.mc -o out.o`, `--exe`, `--backend=`, `--dump-*`) is unchanged, and `stage0/` was not
  touched (2846/3000).
  New files: `src/toml.mc` (475 lines — the TOML subset: `[table]`, `[[array of tables]]`, bare/
  quoted/dotted keys, basic strings with `\" \\ \n \t \r`, integers with `+ - _`, booleans,
  multi-line arrays with a trailing comma; every error is `file:line:col: message` and exit 1).
  The result is deliberately a **flat (path, value, type, index) table in source order**, not a
  tree — the same shape as every other table here (`docs/determinism.md` rule 1): array elements
  share a path and carry an index (`include.paths[0]`), `[[x]]` puts the occurrence in the path
  (`server.0.host`), and values are always text. API: `toml_get`, `toml_get_array`, `toml_count`,
  `toml_int`, plus `toml_entries`/`toml_path_at`/`toml_val_at` — that last trio is what makes
  `[libs]`/`[externs]` work, since the driver needs the KEYS of a table.
  `src/tomldump.mc` (66) prints the table — the pretty-printer lives in the DRIVER, not in
  `toml.mc`, because the compiler carries `toml.mc` in every binary and a dump nobody calls is a
  dozen string literals against the seed's `MAXSTRS`; `scripts/check-toml.sh` (66) compares it against
  `tests/toml/*.expect` — 5 well-formed files and 5 malformed ones (`bad-string`, `bad-equals`,
  `bad-header`, `bad-escape`, `bad-value`) whose `.expect` holds the exact `file:line:col`.
  `src/driver.mc` (421) implements `[project] name/entry/out/kind`, `[target] os/arch`
  (macos/aarch64 only — anything else is an error pointing at the offending value),
  `[compiler] core/modules/out`, `[linker] cmd/args`, `[libs]`, `[externs]`, `[include].paths`.
  Every path is relative to the CONFIG's directory. Two shapes: with no `[compiler]` the entry is
  compiled in-process; with it, the driver writes `<compiler.out>.mc` (`#include` of the core plus
  each module, `../`-adjusted because the generated file lives next to the compiler), compiles it
  with `macho-exe`, and **spawns** the result as `<compiler> build DIR --config FILE --entry-only`
  — the compiler's tables are globals built once per process, so two compilations never fit in one
  run; `--entry-only` is the second half and re-reads the same TOML, which is why
  `[include]/[libs]/[externs]` apply either way. `[linker]` substitutes `{out} {obj} {sdk}` inside
  each argument and expands `{libs}` (a whole argument) into one argument per `[libs]` entry, each
  also substituted; `{sdk}` runs `xcrun --show-sdk-path` lazily, capturing stdout with a
  `posix_spawn_file_actions_addopen` on fd 1 into `<out>.sdk`, read back and unlinked. Tools are
  spawned with `posix_spawnp` + `waitpid` (inherited stderr, so their diagnostics pass through;
  non-zero exit -> exit 1). Outputs get their parent directories created and are `unlink`ed before
  writing (the cached-signature `SIGKILL`).
  Support changes (`git diff --numstat`): `src/lex.mc` +38/-1 (`lex_add_include_path`/
  `lex_readable`, extra `#include` roots tried only after the includer's own directory fails; with
  none registered, not even an extra `open` happens), `src/parse.mc` +41/-1
  (`extern_lib_pattern_add`/`extern_pat_match`, `MAXEXTPAT 32`; `extern_lib_find` consults the
  exact `#dylib` table FIRST, so `#dylib` in the source still wins),
  `src/main.mc` +6 (dispatch on `argv[1] == "build"`, after the backends are registered),
  `src/core.mc` +4, `lib/sys.mc` +19 (`posix_spawnp`/`waitpid`/`_NSGetEnviron` for programs;
  documented as having **no** `lib/sys_svc.mc` equivalent — `posix_spawn` is not a syscall, it is
  a libSystem routine marshalling a struct this language cannot lay out).
  Two limits in `src/gen_arm64.mc` (+12/-2) deliberately diverge from the C seed for the first time:
  `MAXSTRS 512 -> 2048` and `MAXGLOBALS 256 -> 512`. Reason (same as MAXFUNCS at M11): stage0 only
  has to compile ONE program, `src/mc.mc` (493 strings, 169 globals — under the C limits, which
  `make bootstrap` keeps proving), while `src/core.mc` + a taught compiler on top of it
  (`examples/api/mc-api.mc` = core + oop) went past 512 strings once `toml.mc`/`driver.mc` joined
  the core. Raising a ceiling only changes behaviour above the old one, so the whole
  check-lex/ast/asm corpus still comes out identical under `mc0` and `mc1`.
  Proofs: `examples/api/mc.toml` (40 lines) — `build/mc1 build examples/api` prints
  `compiler build/mc-api.mc -> build/mc-api` / `compile main.mc -> build/api` and produces both
  binaries (253475 and 55632 bytes, `codesign --verify` OK, `otool -L` with libSystem **and**
  libsqlite3 bound by ordinal from `[libs]`/`[externs]`); `examples/api/test.sh` now compiles with
  `mc build` and all 11 route checks pass; the Makefile keeps working as the by-hand path.
  `tests/proj/` (one program, three configs) + `scripts/check-build.sh` (160) cover
  `[include].paths` (the `#include` only resolves through it), `[libs]`/`[externs]` with **no**
  `#dylib` anywhere, `[linker]` with all four placeholders through real `ld`, `kind = "obj"`, and
  four diagnostics. New `make` targets `check-toml` and `check-build`, both inside `make check`.
  Docs: `docs/build.md` (381, new), `docs/surface.md` § "M14 — the same three things said from
  outside the source", `examples/api/README.md` § 3 and `examples/api/Makefile` header.
  — `stage0/` untouched, 2846/3000; `src/*.mc` 7731 lines; 674/1024 functions in `src/mc.mc`
  (350 of headroom), 489/512 strings and 169/256 globals under the C seed's limits -- the
  string budget is the tight one, and `MAXSTRS` in `stage0/gen_arm64.c` is the ceiling M15 will
  probably have to raise.
  `make check` green end to end: `test` 32/32, `check-lex` 64/64, `check-ast` 64/64, `check-asm`
  64/64, `check-obj` 32/32, `check-surface` 32/32 + Tier 3, `test-exe` 32/32, `check-toml` 8/8,
  `check-build` 10/10, `check-examples` green, `bootstrap` at a fixed point (`mc2.o == mc3.o`,
  267552 bytes; the `--dump-asm` diff between `mc1` and `mc2` is empty) and golden rewritten once
  in `tests/golden/mc2.sha256` (`d92fad26…cb69f` -> `20564a98…f343e`).
- M15 done (`docs/specs/M15.md`, `docs/build.md` § M15, `docs/bootstrap.md` § M15):
  **bundled standard library, `#include <name>`, `#embed`**. The binary alone is the toolchain.
  New: `src/lz.mc` (199, LZ77 both ways, zero dependencies — not even `arena.mc` — so
  `#include <lz>` is enough for a program; deterministic hash chain in bss, reset per call;
  a 3-byte match is refused while a literal run is pending, which is what makes
  `lz_bound(n) = n + n/128 + 8` a true bound), `src/bundle.mc` (229, `bundle_find`/
  `bundle_read` with lazy inflate + cache, and `bundle_emit`, the ONE definition of the
  generated file's format), `src/bundle_data.mc` (generated, 2845 lines / 323997 B),
  `tools/bundle.list` (27 entries) + `tools/bundle.mc` (186) + `tools/lz_test.mc` (151),
  `tests/mc/070-embed.mc`, `071-embed-lz.mc`, `072-include-bundle.mc` (+ 2 data files),
  `scripts/check-mc.sh` (80), `scripts/check-bundle.sh` (55), `scripts/check-standalone.sh` (140).
  Edited: `src/lex.mc` (+88: `fvirt`, `lex_push_mem`, `lex_find_path`, `lex_seen`/`lex_remember`,
  `lex_strip_mc`, `lex_include_bundled`/`lex_include_name`, `D_EMBED`, the `bopen_fn` hook),
  `src/parse.mc` (+88: `#include <name>` and `do_embed`), `src/core.mc`, `src/main.mc`,
  `src/astdump.mc`, `src/driver.mc` (default core = `<mc/core>`), `examples/api/mc-api.mc` +
  `mc.toml` (no more `core = "../../src/core.mc"`), `Makefile`, docs.
  Design notes worth keeping:
  * **The lexer does not tokenize `<name>`.** `#include <mc/core>` is `<`, the lexemes and `>`,
    reassembled in `do_directive`. So `--dump-tokens` stays byte for byte what the frozen
    `stage0/lex.c` produces and `check-lex` keeps comparing the two lexers over the whole tree.
  * **The lexer does not depend on `src/bundle.mc`** either: `main.mc` registers `bundle_open`
    through one function pointer (`lex_set_bundle`), so `src/lexdump.mc` and `src/astdump.mc`
    stay bundle-free and `check-lex`/`check-ast` keep compiling them with `mc0`.
  * **`mc/bundle_data` is regenerated on the fly** from the in-memory blob (the bundle cannot
    contain itself), which is what makes `<mc/core>` complete. Proof:
    `#include <mc/core>` + `#include <user_default>` compiles to an object **identical to
    `build/mc2.o`** (`scripts/check-standalone.sh`).
  * **Relative includes inside a bundled file** resolve by name: join + normalize + drop `.mc`,
    then fall back to the last path component (`mc/driver` → `"../lib/prelude.mc"` → `prelude`).
    `tools/bundle.mc` refuses a manifest with two entries sharing a last component.
  * **`u64` hex elements, not `u8` decimal**, in `bundle_blob`: the parser makes one AST node per
    initializer element and the frozen stage0 has a 32 MiB arena with 72-byte nodes — 134 KB of
    bytes exhausts it (measured), as `u64` it costs ~17k nodes. Hex because an element ≥ 2^63
    would need an unsigned divide to print in decimal.
  — `stage0/` untouched, 2846/3000; `src/*.mc` 11205 lines (2845 of them generated);
  **708/1024 functions** in `src/mc.mc` (316 of headroom), **500/512 strings**, 177/256 globals.
  `make check` green end to end: `test` 32/32, `check-lex` 67/67, `check-ast` 67/67,
  `check-asm` 67/67, `check-obj` 32/32, `check-bundle` (reproducible + fresh), `check-surface`
  32/32 + Tier 3, `test-exe` 32/32, `check-mc` 5/5, `check-standalone` green, `check-toml` 8/8,
  `check-build` 10/10, `check-examples` green, `bootstrap` at a fixed point (`mc2.o == mc3.o`,
  416664 bytes; the `--dump-asm` diff between `mc1` and `mc2` is empty) and golden rewritten once
  (`20564a98…f343e` -> `dea82035…4eb38`).
  Sizes: source 304346 B -> LZ 134604 B (44%), blob 134870 B; `build/mc-exe` 252316 B without
  the blob -> **384419 B** with it.
  **The string budget is now the binding constraint**: the core is at 500/512 and
  `lib/mc_syntax_demo.mc` (which `check-asm` compiles with `mc0`) at 508/512 — four literals of
  headroom for the whole repository. M16 will have to either raise `MAXSTRS` in
  `stage0/gen_arm64.c` (a seed change the owner has to authorize) or put the next milestone's
  messages on a diet.
- M16 done (`docs/specs/M16.md`, `docs/build.md` § Linux targets): **Linux arm64 — ELF64
  objects, a musl link and a system layer with no libc**. `stage0/` untouched (2846/3000): the
  ELF writer is a backend in `.mc`.
  New: `src/backend_elf.mc` (472 lines, backend `elf-obj`) — ELF64 `ET_REL`/`EM_AARCH64` on top of
  `gen_lower` + `gen_encode_all`, the same sections/symbols/relocations the Mach-O writer reads.
  Sections come out null, then the module's in creation order (`__TEXT,__text` -> `.text` AX 4,
  `__TEXT,__cstring` -> `.rodata` A 1, `__DATA,__data` -> `.data` WA 16, `__DATA,__bss` -> `.bss`
  NOBITS WA 16, `#section SEG SECT` -> `.seg.sect` with the leading underscores dropped and
  lowercased, AX when the Mach-O flags say pure-instructions and NOBITS when they say zerofill),
  then one `.rela.X` (SHF_INFO_LINK, `sh_link` = symtab, `sh_info` = X) per section with
  relocations, then `.symtab`/`.strtab`/`.shstrtab` — so a module section index is its ELF index
  minus one and `st_shndx` is `sym_sect` unchanged. Symbols: the compiler's leading `_` dropped
  (`_main` -> `main`), string labels as assembler temporaries (`l_str0` -> `.Lstr0`), STT_FUNC in a
  pure-instructions section / STT_OBJECT otherwise / STT_NOTYPE undefined, and `macho.mc`'s stable
  partition reused verbatim (locals, defined globals, undefined) because that is exactly what ELF
  requires — `sh_info` = 1 + locals. Relocations: `R_BRANCH26` -> `CALL26` (283), `R_PAGE21` ->
  `ADR_PREL_PG_HI21` (275), `R_PAGEOFF12` -> `ADD_ABS_LO12_NC` (277) on an `add` and
  `LDST{8,16,32,64}_ABS_LO12_NC` (278/284/285/286) on an ldr/str by the access width in bits 31:30
  (the same classifier `exe_fix_pageoff12` uses), `R_UNSIGNED` -> `ABS64` (257); sorted by ascending
  offset (stable insertion sort, which is one pass because the encoder already emits them in order)
  and `r_addend` always 0, since the encoder leaves the relocated immediate zeroed.
  `lib/sys_linux.mc` (123): `open`/`creat`/`read`/`write`/`close`/`fchmod`/`exit` as raw `svc #0`
  with the number in `x8` (openat 56 with `AT_FDCWD` = -100 written as `movn x0, #99`, close 57,
  read 63, write 64, fchmod 52, exit_group 94) plus `_start`, written with `#opcode`, which reads
  `argc`/`argv` off the entry stack (`x29 + 16` / `x29 + 24`: the function has no parameters and no
  locals, so the frame is empty and the prologue only moved the 16 bytes of the `stp`), calls `main`
  through `reloc(BRANCH26, "_main")` + `emit(0x94000000)` and ends in exit_group. Bundled as
  `sys_linux` (the spec wrote `<sys/linux>`; the flat name was the instruction that came with the
  task). `O_RDONLY/O_WRONLY/O_CREAT/O_TRUNC` moved out of `lib/io.mc` into each system layer,
  because they are per-system values (`O_CREAT` is 0x200 on macOS and 0x40 on Linux) and a second
  `#define` of the same name is an error.
  Driver (`src/driver.mc` +36/-7): `[target].os` takes `linux`, which swaps the object backend for
  `elf-obj` and makes `[linker]` REQUIRED (`linux requires [linker]: there is no direct executable`);
  new `{sysroot}` placeholder from `[sysroot].path`, resolved against the config's directory like
  every other path. The taught compiler is still built with `macho-exe` — it is a tool that has to
  run on the host.
  Scripts: `scripts/sysroot-linux.sh` (45) fills `build/sysroot/linux-aarch64` with
  `crt1.o crti.o crtn.o libc.a libc.so` from `apk add musl-dev` inside `alpine:3` (3.24.1), cached;
  `scripts/test-linux.sh` (123) generates a Linux `mc.toml` per test in a temp dir, builds it with
  `mc build`, links with `ld.lld` and runs it in `docker run --rm --platform linux/arm64
  -v <repo>:/w -w /w alpine:3` (the repo is the mount because `025-linecount` opens its own source
  by a relative path). `make test-linux` is inside `make check`, guarded: without `ld.lld` or with
  Docker down it prints `test-linux: SKIPPED (...)` and the build stays green.
  `tests/032-svc.mc` carries the only `// skip-linux` header (Darwin syscall numbers in x16 and
  `svc #0x80`); everything else is portable as written, `030-section` and `033-reloc` included.
  `tests/linux/070-nolibc.mc` is the no-libc case: `#include <sys_linux>` linked with
  `-nostdlib -e _start`.
  Verified field by field against `clang --target=aarch64-linux-musl -c` of equivalent C with
  `llvm-readobj`/`llvm-objdump -dr`: header, section flags, `.rela` `sh_flags`/`sh_link`/`sh_info`,
  symtab `sh_link`/`sh_info` and every relocation type agree. The one intentional difference is that
  `mc` always materializes a global address with `adrp` + `add`, so it asks for `ADD_ABS_LO12_NC`
  where clang folds the offset into the load and asks for `LDST64_ABS_LO12_NC`.
  Known limit: the compiler itself does not cross-compile yet — `src/driver.mc` needs
  `posix_spawnp`/`waitpid`/`_NSGetEnviron`, and the last one is libSystem-only.
  — `stage0/` untouched, 2846/3000; `src/*.mc` 12062 lines (3139 of them generated);
  739/2048 functions and 518/2048 strings in `src/mc.mc`. `make check` green end to end:
  `test` 32/32, `check-lex` 69/69, `check-ast` 69/69, `check-bundle` (31 files, blob 148754 B),
  `check-asm` 69/69, `check-obj` 32/32, `bootstrap` at a fixed point (`mc2.o == mc3.o`,
  448416 bytes; the `--dump-asm` diff between `mc1` and `mc2` is empty), `check-surface` 32/32,
  `test-exe` 32/32, `check-mc` 6/6, `check-standalone` green, `check-toml` 9/9, `check-build`
  11/11, **`test-linux` 32/32 on linux/arm64** (1 skipped), `check-examples` green; golden rewritten
  once (`2673c65e...4a3ed5` -> `f20c1332...e14aa0`).
- M21 done (`docs/specs/M21.md`, `docs/surface.md` § M21): **Tier 3 completed — expression and
  operator hooks, source record and replay, hygienic substitution**. All in `src/*.mc`;
  `stage0/` untouched. Delivered in the two gated steps the spec asks for (decision 7.5), each
  with `make check` green and the golden rewritten once.
  * **Step 1 — parser hooks.** `syntax_expr(word, &f)` (`i64 f()` -> node index) dispatched as the
    first thing in `parse_primary`, with the same "consumed no tokens" guard as
    `syntax`/`syntax_stmt` plus a second one, `syntax_expr handler produced no expression`, because
    an expression position has no empty node to fall back on. `syntax_infix(word, prec, &f)`
    (`i64 f(i64 left)`) keeps **no table of its own**: the `#infix` entry gained one column
    (`INF_FN 32`, `INF_SIZE` 32 -> 40), which is what puts a taught operator and a `#infix` one in
    one comparable precedence order; `infix_set` clears the column, so a `#infix` on the token
    drops the handler (`tests/err/066-infix-drops-handler.mc`). A second `syntax_infix` on the same
    token is refused at `user_init` time (`operator already taught: <tok>`, decision 7.3,
    `lib/user_dupop.mc`). `infix_is_taught` was added so `err_name` blames only operators that
    carry a handler, never `+`, and `word_is_taught` now covers all five registrations — its
    message became `name reserved by a syntax/type_alias registration`. `p_start()`/`p_depth()`.
    `--dump-rules` now also lists every infix/prefix operator with precedence, associativity,
    `template` and `handler` (decision 7.2) — a half that exists only in the `.mc` compiler, since
    the frozen `stage0/parse.c` has no handler column to report.
  * **Step 2 — record/replay.** `p_skip_balanced(open, close, &len)` counts depth over **real
    tokens** (so a `}` inside a string or a comment is harmless) and returns the source span,
    delimiters included, reporting an unterminated region at the **opening** token.
    A span is a slice of ONE buffer, so a region whose file ran out in the middle is refused
    (`region crosses a file boundary`) instead of returning a bogus byte range.
    `p_push_source(name, text, len)` is four lines over `lex_push_mem`, with `#include`'s exact
    semantics — which is why error attribution costs **zero** core lines: `err_at` prints
    `lex_file()`, so the module composes `slot__i64__0 instantiated from prog.mc:15` and gets it in
    front of every error inside. `p_subst_reset`/`p_subst_name`/`p_subst_int` live in `src/lex.mc`
    and are applied in `lex_next`'s **identifier branch only**, by exact lexeme: the pending
    entries sit in the slot the next frame will occupy, so the push binds them by construction and
    `lex_pop` clears the slot it vacates (`MAXSUBST 16`, nested frames independent, one slot more
    than `MAXOPEN` because the pending slot of a full stack is index `MAXOPEN`).
    `p_resplit_punct(n)` rewinds `cp` to just after the first `n` bytes of the current punctuation
    token, guarded by `cp == tok_start(cur) + tok_len(cur)` — which is exactly "a token just lexed
    from the source", never a string and never a substituted identifier. `MAXOPEN` 16 -> 32
    (`stage0` stays at 16: it has no `p_push_source` at all, the same kind of documented divergence
    as `MAXSTRS`/`MAXGLOBALS` in `gen_arm64.mc`).
  * **The demo is a toy unrelated to classes and generics**, so generality is proven and not
    asserted: `lib/user_syntax_demo.mc` (67 -> 391) keeps M12's `unless`/`enum`/`bool` and adds
    `bits u32` (a **type** in expression position), `pipe(x, f, g)` (a variable-length list there),
    `.+` (saturating add, lowering to a runtime the module itself pushes as a second source at
    `user_init`), `~>` (a **name** on the right resolved in the module's own field table, plus
    `p ~> len = 3` — which works because `=` is deliberately not in the infix table — and
    `p ~> at(i)`), and `tmpl`/`make`: the body recorded with `p_skip_balanced`, replayed once per
    argument tuple with `p_subst_name`/`p_subst_int`, memoized by the module's own mangled name,
    with `make slot<i64, sum<1, 2>>;` closing on a `>>` that `p_resplit_punct` splits. Two
    handlers (`nop`, `nil`) are broken on purpose and exist only to prove the two guards.
    `lib/syntax_demo_test.mc` (26 -> 65) uses all nine registrations plus a `#infix "<+>"` in the
    same file, and exits 42.
  * **Inert by construction** is the acceptance gate and it holds: with nothing registered every
    `tests/*.mc` object and every `--dump-ast` is byte-identical to `build/mc0`'s — the frozen C
    seed, which has none of this. `scripts/check-surface.sh` (163 -> 302) gained one case per hook,
    the four `tests/err/` cases with their exact message, the duplicate registration, the demo test
    compiled twice byte for byte, and that inertness check.
  — core cost: `src/hooks.mc` +64/-5, `src/parse.mc` +157/-8, `src/lex.mc` +77/-1 = **+298 lines,
  175 of them non-comment** against the spec's ~146/~110 estimate; the excess is `dump_ops`
  (27 lines, decision 7.2, outside the 2.x cost table), the three handler guards and the duplicate
  refusal (~20), the per-frame substitution bookkeeping (~15 over the 40 estimated) and this
  repository’s comment density (109 comments + 14 blank of the 298). New: `lib/user_dupop.mc` (18),
  `tests/err/063-tmpl-attrib.mc`, `064-expr-noadvance.mc`, `065-expr-nonode.mc`,
  `066-infix-drops-handler.mc`; `tools/bundle.list` gained `user_dupop` (30 entries).
  `stage0/` untouched, 2846/3000. `make check` green end to end: `test` 32/32, `check-lex` 68/68,
  `check-ast` 68/68, `check-asm` 68/68, `check-obj` 32/32, `check-bundle` fresh, `check-surface`
  32/32 + every M21 case, `test-exe` 32/32, `check-mc` 6/6, `check-standalone` green,
  `check-toml` 9/9, `check-build` 10/10, `check-examples` green, `bootstrap` at a fixed point
  (`mc2.o == mc3.o`, 442048 bytes; the `--dump-asm` diff between `mc1` and `mc2` is empty) and the
  golden rewritten **twice**, once per step (`e1bfc16e…6548e` then `b2579419…51be6`).
  Sizes: bundle 336730 B of source -> 149952 B of LZ (30 files); `build/mc-exe` 402211 B.
- M16 + M21 merged (2026-09-03): the two milestones were developed in parallel (M16 on a branch,
  M21 in the working tree) and brought together in one tree. They do not overlap in code: M16 is
  `src/backend_elf.mc` + `lib/sys_linux.mc` + the driver's `os = "linux"` route, M21 is
  `src/hooks.mc`/`src/parse.mc`/`src/lex.mc`. Only four files had to be reconciled by hand:
  `CLAUDE.md` § State and `docs/surface.md`'s header (both entries kept, the backend list is now
  three: `macho`, `macho-exe`, `elf-obj`), and the two generated artefacts — `src/bundle_data.mc`
  and `tests/golden/mc2.sha256` — which were discarded on both sides and regenerated
  (`tools/bundle.list` merged on its own: 32 entries, M16's `sys_linux`/`mc/backend_elf` plus
  M21's `user_dupop`). **The numbers in the two entries above are each milestone's own; the
  merged tree's are these.**
  — `stage0/` untouched, 2846/3000; `src/*.mc` 12624 lines (3417 of them generated).
  `make check` green end to end (RC 0): `test` 32/32, `check-lex` 70/70, `check-ast` 70/70,
  `check-bundle` (32 files, raw 360287 B -> LZ 161755 B, blob 162083 B), `check-asm` 70/70,
  `check-obj` 32/32, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 470664 bytes; the
  `--dump-asm` diff between `mc1` and `mc2` is empty), `check-surface` 32/32 + every M21 case,
  `test-exe` 32/32, `check-mc` 6/6, `check-standalone` green, `check-toml` 9/9, `check-build`
  11/11, `test-linux` 32/32 on linux/arm64 (1 skipped: `032-svc`), `check-examples` green.
  Golden rewritten **once** for the merge, after the two gates:
  `b2579419…51be6` (M21) / `f20c1332…e14aa0` (M16) ->
  `0bfa736630cd50ce99671f95990b8b80e79cb1bb6248bdb197be11e948720788`.
  `build/mc-exe` 437011 B.
- M22 done (`docs/specs/M22.md`): **`examples/lang`** — the `lx` language (classes, interfaces,
  generics with `where` constraints, namespaces, `ref` parameters, reference counting) taught to
  `mc` by a prelude. Nothing in `src/`, `stage0/`, `lib/`, `tests/` or `docs/` was touched: the
  whole language is `examples/lang/*.mc` (9 modules, 2810 lines) registering M12/M21 hooks, plus
  `lib/rt.mc` (204, a 4 MiB arena with free lists by size class and `rc_inc`/`rc_dec`) and
  `lib/prelude.lx` (30). `mc build` assembles the taught compiler from `examples/lang/mc.toml` and
  compiles `main.lx` with it; `examples/lang/test.sh` (= `make check-lang`, inside `make check`)
  runs 12 `.lx` tests, the sample, `--dump-asm` (mangled generic instantiations and vtables),
  `--dump-rules`, a byte-for-byte re-compile, and the check that the DEFAULT compiler refuses the
  same source. Deviation on record: `[compiler].core = "lang_core.mc"` (a copy of `src/core.mc`'s
  include list without `bundle_data.mc`/`bundle.mc`/`backend_elf.mc`), because `<mc/core>` plus a
  module of this size exhausted the 32 MiB arena — M23's growable arena removes that cause, but
  the example was left as it was verified. (M21.5 removed the cost itself and DELETED both copies;
  `mc.toml` has no `core` key any more.) Open gaps reported to the architect and kept in
  `examples/lang/README.md` § Limits: `arena exhausted` carries no position, `parse_block()`
  bypasses `syntax_stmt("{")`, `syntax_stmt` cannot own `return`/`break`/`continue`, there is no
  hook for a core-declared local, and `parse_call` hard-codes `TY_I64`.
  — `make check` green with `check-lang` added; golden **not** rewritten by M22.
- M23 done (`docs/specs/M23.md`, `docs/build.md` § limits, `docs/determinism.md` § capacity):
  **dynamic limits — growable tables, one estimate, one tolerance, no ceilings**. `stage0/`
  untouched (2846/3000): the C seed keeps every `MAX*` it had, and the whole change is in `src/`.
  * **Growable tables.** Every `MAX*`-sized array in `src/` became an arena block that doubles on
    demand through one helper, `grow(id, p, n, &cap, elem)` in `src/arena.mc` (+179/-4), called at
    the append site where the `if (n == MAX) die(...)` used to be; `grow_to()` re-sizes the
    parallel arrays that share a counter (the seven `fn_*`, the three `prel_*`, `xs_*`, `xg_*`,
    `syn_*`, `alias_*`, `extlib_*`, `extpat_*`). 34 tables in all, in a fixed registry
    (`T_TOKENS`..`T_HEAP`) that also records estimate / reserve / high-water / growth events.
    Insertion order is untouched by a growth, so nothing the compiler emits can depend on it.
    `MAX*` is gone from `src/` except `MAXPARAMS` (8, the ABI), `MAXDEPTH` (64, the
    `expression too deep` bound) and `MAXBIND`/`MAXRDEPTH`/`MAXITEMS`/`MAXNAMES`, which bound ONE
    `#rule` and size the inline fields of a rule record.
  * **The arena** is the static 32 MiB `heap[]` plus, when it runs out, one `mmap` chunk per
    growth (`extern uptr mmap(...)` in `src/arena.mc`, same prototype added to `lib/sys.mc`).
    Chunks are never moved and never freed, so every pointer stays valid; `arena exhausted` now
    only happens if the kernel refuses.
  * **The estimate** (`src/limits.mc`, 586 lines, new): a byte-level pre-scan of the entry plus
    every include it can reach — relative ones from disk, `<name>` ones from the bundle (inflated
    once and cached, so the lexer pays nothing twice), following only a `#include` that OPENS a
    line (the ones inside `//` comments and inside the string literals `driver.mc` writes are not
    directives). Coefficients, calibrated against `src/mc.mc` and documented in `docs/build.md`:
    `nodes = bytes/11`, `ins = nodes*9/10`, `strings = quotes/3`, `funcs = ") {"`,
    `globals = funcs/3`, `defines = "#define"`, `symbols = funcs+globals+strings`,
    `heap = sum(count*record)*5/3 + 7*bytes`. Measured on `src/mc.mc` (690 KB, 21 files): nodes
    +2%, heap +3%, defines +4%, strings +5%, ins +7%, funcs +13%, symbols +13%, globals +29%,
    includes exact. The token table is deliberately not byte-derived (it holds distinct lexemes).
  * **Remembered usage**: `mc build` writes `build/.mc-usage.toml`, ONE SECTION PER COMPILED
    SOURCE (`[usage."main.mc"]`) — a project with a `[compiler]` compiles two sources of very
    different sizes in two processes and neither should pre-size the other. The next build takes
    the larger of its own section and the static estimate. Capacities only; the output never
    depends on it.
  * **`[limits] tolerance = 0.25`** (default), a float in `[0, 1]`. `src/toml.mc` (+69/-9) reads a
    decimal float as BASIS POINTS (`i64`, `0.25` -> 2500), at most four fraction digits;
    `TV_FLOAT` prints as `bp` in `src/tomldump.mc`. Out of range is
    `examples/api/mc.toml:46:13: tolerance must be between 0 and 1` (`toml_err_val`, no key
    appended); `tests/toml/values.toml` gained five float cases and `tests/toml/bad-float.toml`
    the fifth-digit error.
  * **`mc limits [DIR|FILE.mc]`** and **`mc build --limits`** (`src/driver.mc` +109/-31): one line
    per table with estimate, reserved, used, growth events and a verdict (`ok`, `tight` = used
    over 90% of reserved, `grew`), exit **0 / 3 / 1**. `mc limits FILE.mc` runs the real pipeline
    up to `gen_encode_all()` and writes no object. A project with a `[compiler]` prints two
    reports (compiler first, entry second — the child gets the same flag) and returns the worse
    verdict.
  * **`mc build --fix-limits`** rewrites ONLY the `[limits]` section — the smallest multiple of
    0.05 in `[0, 1]` that would have avoided `grew` and `tight` against the STATIC estimate (what
    a clean checkout has); every other byte of `mc.toml` comes out as it went in. When `1.0` is
    not enough it says so and leaves the file alone (the remembered usage, just written, is what
    covers that case). Never writes without the flag.
  * **`make check-limits`** (`scripts/check-limits.sh`, 85 lines, new, inside `make check`): the
    seed guard the architect lacked at M15 — `mc limits src/mc.mc` against the constants read
    straight out of `stage0/mc.h`/`stage0/*.c`, failing above 90%. Today: tokens 51/2048 (2%),
    defines 454/2048 (22%), funcs 788/2048 (38%), globals 231/512 (45%), strings 539/2048 (26%),
    locals 25/256 (9%) — **16/16 under 90%**.
  Proofs: a generated program with **5000 functions and 5000 string literals** (well past the
  seed's `MAXFUNCS`/`MAXSTRS` of 2048) builds with no TOML change and runs (exit 42); `mc limits`
  gives `grew` on the first build (nodes/strings/ins/heap) and `ok` on the second, whose arena
  high-water also drops from 35 MB to 20 MB. `tolerance = 0` on `examples/api` grows and exits 3;
  `--fix-limits` moves the file from `0.0` to `0.95` and `diff` shows that single line; the next
  run with the usage file deleted exits 0. `tolerance = 1.5` is refused at `mc.toml:46:13`.
  — `stage0/` untouched, 2846/3000; `src/*.mc` 12596 lines (3238 of them generated);
  `make check` green end to end: `test` 32/32, `check-lex` 68/68, `check-ast` 68/68,
  `check-asm` 68/68, `check-obj` 32/32, `check-bundle` (reproducible + fresh, 30 files),
  `check-surface` 32/32 + Tier 3, `test-exe` 32/32, `check-mc` 6/6, `check-standalone` green,
  `check-toml` 10/10, `check-build` 10/10, `check-limits` 16/16, `check-examples` green,
  `bootstrap` at a fixed point (`mc2.o == mc3.o`, 469752 bytes; the `--dump-asm` diff between
  `mc1` and `mc2` is empty) and golden rewritten once
  (`2673c65e...94a3ed5` -> `743302fa...0e3e752ff`).
- M22 + M23 merged (2026-09-03): same situation as M16 + M21 — M22 (`examples/lang`) was in the
  working tree and M23 (dynamic limits) on a branch forked BEFORE the M16 + M21 merge, so the
  three-way apply had to reconcile five files by hand: `CLAUDE.md` § State and `docs/build.md`
  (both entries kept), the `Makefile` (`check-limits` **and** `test-linux`/`check-lang` in
  `check:` and `.PHONY`), `src/driver.mc` (M16's `drv_obj_backend()` with M23's extra `entry`
  argument to `drv_compile`) and `src/lex.mc` — the only semantic one: M23 deleted `MAXOPEN`, and
  M21's four substitution arrays were sized `(MAXOPEN + 1) * MAXSUBST`. They are parallel to the
  frame stack, so they now follow it: `lex_push_mem` re-sizes them with `grow_to` whenever
  `fstack` grows, copying `nopen + 1` slots so the PENDING slot survives the growth. `MAXSUBST`
  stays — it bounds one frame, like `MAXDEPTH`. `src/bundle_data.mc` and `tests/golden/mc2.sha256`
  were kept out of the patch and regenerated. Two tables M23 could not see, because they arrived
  with M16 and M21, were brought under the same rule instead of keeping a ceiling: the ELF section
  table (`src/backend_elf.mc`, `MAXELFSEC 128` gone) is allocated at exactly `2 * nsections + 4`
  slots, and `src/limits.mc` reaches the bundle through the lexer's `bopen_fn` pointer rather than
  calling `bundle_open`, so a taught compiler assembled without `src/bundle.mc` still links —
  which is what `examples/lang/lang_core.mc` was (it gained `#include "../../src/limits.mc"`, its
  only edit; the file is gone since M21.5). **The numbers in the two entries above are each milestone's own; the merged tree's
  are these.**
  — `stage0/` untouched, 2846/3000; `src/*.mc` 13965 lines (3779 of them generated);
  836/2048 functions, 571/2048 strings and 259/512 globals in `src/mc.mc` against the C seed.
  `make check` green end to end (RC 0): `test` 32/32, `check-lex` 71/71, `check-ast` 71/71,
  `check-bundle` (33 files, raw 396273 B -> LZ 179062 B, blob 179400 B), `check-asm` 71/71,
  `check-obj` 32/32, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 523120 bytes; the
  `--dump-asm` diff between `mc1` and `mc2` is empty), `check-surface` 32/32 + every M21 case,
  `test-exe` 32/32, `check-mc` 6/6, `check-standalone` green, `check-toml` 10/10,
  `check-build` 11/11, `check-limits` 16/16 under 90%, `test-linux` 32/32 on linux/arm64
  (1 skipped: `032-svc`), `check-examples` green, `check-lang` green (12 tests + main.lx).
  Golden: the tree goes from `0bfa7366…20788` (the M22 working tree) and `743302fa…e752ff` (the
  M23 branch) to a single new value,
  `94db4b12b772d418ae44399b4ecd984d790c92c2bfb12798a568a70112f11918` — written twice during the
  merge (once for the regenerated bundle, once after the last `src/limits.mc` edit), each time
  only after `diff <(build/mc1 --dump-asm src/mc.mc) <(build/mc2 --dump-asm src/mc.mc)` came out
  empty and `cmp build/mc2.o build/mc3.o` matched.
  `build/mc-exe` 474355 B. M23's own acceptance re-run on the merged tree: a generated program
  with 5000 functions and 5000 string literals builds with no TOML change (`grew`, exit 3, then
  `ok`, exit 0) and exits 42; `mc limits examples/api` is exit 3 cold and exit 0 remembered;
  `tolerance = 1.5` is refused at `examples/api/mc.toml:46:13`.
- M21.5 done (`docs/specs/M21.5.md`, `docs/surface.md` § Tier 3 + `#embed`, `docs/build.md` §
  `[compiler]` / `mc/bundle_data` / limits): **the six follow-ups `examples/lang` exposed.**
  1. **`#embed` costs one AST node.** The payload was one `N_INT` per byte; it is now a single
     `N_BLOB` node (`src/ast.mc`, kind 25) whose `name` is the address and `val` the length, and
     `glob_place` copies the bytes straight into the section (`src/gen_arm64.mc`, +2 lines). The
     objects are byte for byte what they were (`tests/mc/070/071/073` compared against the
     pre-change `build/mc-exe`). That is what makes the bundle embeddable: `bundle_emit` gained a
     `mode` (`src/bundle.mc`) and the copy the BINARY regenerates, `mc/bundle_data`, is now
     `#embed bundle_blob "bundle.bin"` + the index — **40 lines / 989 bytes** instead of 3910
     lines / 445 898 bytes. `mc/bundle.bin` is a second synthetic index (`BUNDLE_BIN`) that serves
     `bundle_blob` itself, with no inflate and no copy; `bundle_bin_size()` rounds it up to a
     multiple of 8 so the `#embed` global has exactly the size `u64 bundle_blob[]` had, and the
     two forms produce the SAME object (`check-standalone`: `<mc/core> + <user_default> ==
     src/mc.mc, byte for byte`).
     **Deviation, on record:** `src/bundle_data.mc` ON DISK keeps the `u64 ... = { ... }` form.
     `dir_names[]` in the frozen `stage0/lex.c` has no `embed` (`build/mc0` on a file with
     `#embed` answers `unknown directive`, exit 1) and `build/mc0 src/mc.mc` is the seed step of
     `make mc1`, so the file stage0 parses cannot use the directive. For the same reason there is
     no `src/bundle.bin` on disk: nothing would read it. `check-bundle` gained the shape guard —
     `<mc/bundle_data>` has to be exactly one `BLOB` node plus the 132-value index — so a revert
     to the array form fails loudly.
  2. **`arena exhausted` names its caller.** `parse.mc`'s `next()` leaves the current token's file
     and line in `ax_file`/`ax_line` (`src/arena.mc`), and `arena_die` prints reserve, estimate,
     the request that did not fit and the position:
     `mc: arena exhausted (12 MiB reserved, 23 MiB estimated, asked 9418352 bytes) while parsing
     src/arena.mc:5 -- raise [limits].tolerance or HEAP_SIZE`. Verified by building a compiler
     with `HEAP_SIZE (12 << 20)` and `mmap` forced to fail. `cannot reserve the arena` prints the
     same line.
  3. **`mc build --compiler-only`** (`src/driver.mc`): builds the taught compiler, prints its path,
     stops. Exclusive with `--entry-only`; without `[compiler].modules` it is the same missing-key
     error. `examples/lang/test.sh` uses it, then `build/mc-lang build DIR --entry-only`.
  4. **`on_stmt(&f)`** (`src/hooks.mc`, table `T_ONSTMT`): `i64 f(i64 n)` called by `parse_stmt`
     after EVERY statement node exists — core or taught — returning the node, a replacement, or 0
     (an empty `N_BLOCK` takes its place). Order is fixed: the `syntax_stmt` handler builds the
     node first, then the hooks in registration order. `parse_stmt` is now a wrapper over
     `parse_stmt_core`, and with `nonstmt == 0` it does not even make the call.
  5. **`parse_block()` dispatches through `syntax_stmt("{")`** when one is registered, so a
     function body and a `#rule`'s `block $b` hole reach the module too; the guard against a
     handler that consumes nothing moved into `stmt_syntax()`, shared with `parse_stmt`.
  6. **Core-declared locals** are observable as the `N_VAR` node `on_stmt` receives; documented as
     the intended way, no separate hook.
  Demos: `lib/user_syntax_demo.mc` gained `sd_count` (`on_stmt`, rewrites nothing) with
  `stmtcount`/`ifcount`, and `sd_block` (`syntax_stmt("{")`, the core's loop plus two lines) with
  `blockdepth`. `scripts/check-surface.sh` gained four cases: `on_stmt-count`, `on_stmt-order` (the
  hook sees the `N_IF` the `unless` handler built), `on_stmt-blockdepth` (nesting 3, only reachable
  through `<prelude>`'s `while` rule body — 1 without the M21.5 dispatch) and the inertness proof
  (`$demo --dump-ast` from `main` on is byte for byte `$mc1 --dump-ast`).
  `examples/lang`: `lang_core.mc` and `lang_main.mc` DELETED, `[compiler].core` dropped so the core
  comes from `<mc/core>`; the scope bookkeeping moved from three hand-written call sites into
  `lg_on_stmt`; `[limits] tolerance = 1.0` so no table doubles mid-build. The taught compiler on
  `<mc/core>`: **80 312 nodes / 21.7 MiB heap (reserve past the 32 MiB static arena) before,
  58 216 nodes / 20.0 MiB inside it after** (`mc limits examples/lang`, grow 0 everywhere,
  `ins` reports `tight`). `examples/lang/test.sh` green, 14 tests + main.lx.
  — `stage0/` untouched, 2846/3000; `src/*.mc` 14291 lines (3910 of them generated).
  `make check` green end to end (RC 0): `test` 32/32, `check-lex` 71/71, `check-ast` 71/71,
  `check-bundle` (33 files, raw 409375 B -> LZ 185361 B, blob 185699 B; `<mc/bundle_data>` is one
  `#embed` node plus the 132-value index; lz round trip 57 cases), `check-asm` 71/71,
  `check-obj` 32/32, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 533360 bytes; the
  `--dump-asm` diff between `mc1` and `mc2` empty), `check-surface` 32/32 + every M21 and M21.5
  case, `test-exe` 32/32, `check-mc` 6/6, `check-standalone` green, `check-toml` 10/10,
  `check-build` 11/11, `check-limits` 16/16 under 90%, `test-linux` 32/32 on linux/arm64,
  `check-examples` green, `check-lang` green. Golden rewritten ONCE, from
  `94db4b12…f11918` to `06157cbe65858ce1f6353f15446112bfe51213dde2c9a5e8c9a3f428117731d5`, only
  after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`.
- M26 done (`docs/specs/M26.md`): **the documentation set**. `docs/README.md` is the map;
  `docs/guide/00..70` is the task-oriented half (getting started, one file, `mc build` +
  `mc.toml`, teaching the compiler, emitting bytes, cross-compiling, the two examples, bootstrap
  and determinism) and `docs/reference/` the exhaustive half (`language`, `directives`, `cli`,
  `toml`, `hooks`, `objects`, `machine`, `diagnostics`, `bundle`) — 4590 lines written against
  the real compiler. `scripts/check-docs.sh` (303 lines, `make check-docs`) enforces three
  things, with every list EXTRACTED from `src/` at run time and never written down in the script:
  coverage (112 public symbols, 14 CLI flags, 16 TOML keys, 10 directives), samples (all 44
  fenced ` ```mc ` blocks compiled; 38 built with `--exe` and RUN with exit code and stdout
  compared, 6 `expect-error` blocks that must fail with the quoted text, 1 through
  `--backend=elf-obj`; a fence may name the compiler that must build it —
  `taught=lib/mc_syntax_demo.mc`, `taught=examples/api`, `taught=examples/lang ext=lx`) and links
  (110 relative links resolve). `reference/diagnostics.md` covers every message extracted from the
  `die`/`die2`/`err_at*`/`err_node`/`expect`/`toml_err*` call sites. `reference/machine.md`
  documents the M17/M24 contract and says plainly that no `machine*` function exists yet.
- M27 done (`docs/specs/M27.md`): **`mcsite`, the static site generator written in mc**.
  `site/gen/` is 3021 lines of `.mc` — `util.mc` (paths, sorted `opendir` listings, `mkdir -p`,
  escaping), `hl.mc` (fenced code; ` ```mc ` through the BUNDLED lexer, `#include <mc/lex>`, so a
  word the surface taught comes out `tok-taught`), `md.mc` (the Markdown subset), `tmpl.mc`
  (`{{name}}` in one pass + `<!--if name-->`), `site.mc` (`site.toml`, sections, nav, outline,
  pager, `search.json`, `sitemap.xml`, static copy), `check.mc` (`--check`) and `main.mc`.
  `mc build site` compiles it into `build/mcsite` (`site/mc.toml`, no `[compiler]`: mcsite
  teaches the compiler nothing, it USES it); `build/mcsite site` renders `docs/` into
  `site/public`. Deterministic: no clock anywhere (the footer year is `[site].year`), `public/`
  rebuilt from scratch, two runs byte-identical (`diff -r` empty). With M26 in the tree: **60
  pages, 5 sections, 40 fences highlighted (4 kept plain), 0 link problems**, `checkhtml.py` 60
  files 0 problems, `contrast.py` 50 pairs 0 below the minimum. `site/preview/*.html` deleted
  (generated artefact; `site/tools/preview.py` still writes it on demand);
  `.github/workflows/site.yml` runs `make mc1` → `mc1 build site` → `mcsite site --check`.
- Post-M27 batch (review): five confirmed findings fixed, four of them in `site/gen/`.
  1. **A link's scheme is checked, not its `://`.** `sg_resolve_link` (`site.mc`), the three
     inline forms in `md.mc` and `ck_link` (`check.mc`) all used `u_find(href, "://") >= 0` to
     mean "external, leave it alone" — so `[x](javascript:alert(1))` shipped as a live `<a>` and
     `javascript://%0aalert(1)//`, which contains that substring, was not even reported by
     `mcsite --check`. `u_scheme()` (`util.mc`, +45 lines) parses the RFC 3986 scheme (skipping
     the control bytes a browser strips) and answers `U_SCHEME_NONE/ABS/BAD`; only `http`,
     `https` and `mailto` are `ABS`. A refused link, image or autolink is **not a link**: its
     source goes out as escaped text with the page named on stderr, and `ck_link` reports
     `refused link scheme` for anything a template or `site.toml` writes.
  2. **`arena exhausted` no longer claims to be parsing when it is not.** `ax_file`/`ax_line`
     (M21.5) were set by `next()` and never cleared, so a failure in a pass, in `gen_lower` or in
     the object writer printed `while parsing FILE:LINE` with the EOF token's line. `parse_unit()`
     clears both on its way out (`src/parse.mc`, +2 lines plus a comment); parse-time failures are
     unchanged. Proved by raising `arena_die` from the top of `gen_lower` (message loses the
     bogus `sample.mc:10`) and from `parse_function` (message keeps `sample.mc:3`).
  3. **Nesting past `MD_MAXDEPTH` degrades instead of vanishing.** `md_quote`/`md_item` recursed
     only under the guard and wrote an empty `<blockquote>`/`<li>` past it — ten levels of `>`
     lost the text of levels 9 and 10 with nothing on stderr and nothing in `--check`. `md_too_deep`
     writes the rest escaped in a `<p>` and names the page.
  4. **An unmatched backtick run is literal in full.** `md_inline` emitted one `` ` `` and
     advanced by 1 on a failed `md_code_close`, so a stray ``` ``` ``` run was retried three times
     until its last backtick paired with an unrelated single one later in the line. It now emits
     all `k` and advances by `k`, which is what `md_plain_into`, `md_close_br` and `md_emph_close`
     already did.
  5. **`check-docs.sh` covers `on_*`.** The prefix allowlist came verbatim from the M26 spec and
     predates M21.5, so `on_stmt`'s whole reference entry could be deleted with the gate still
     printing `ok coverage: 112`. With `on_` added it fails (`FAIL undocumented public symbols:
     on_stmt`) and the real tree reports **113**. `docs/specs/M26.md` records why the list grew.
  Docs: `site/README.md` § The Markdown subset (two rules became four),
  `docs/reference/diagnostics.md` (`while parsing` appears only while parsing), `docs/specs/M26.md`.
  — `stage0/` untouched, 2846/3000. `make bundle` re-run (`src/parse.mc` is `mc/parse` in the
  bundle): 33 files, raw 409828 B -> LZ 185629 B, blob 185967 B. `make check` green end to end
  (RC 0): `test` 32/32, `check-lex` 71/71, `check-ast` 71/71, `check-bundle` (lz round trip 57
  cases), `check-asm` 71/71, `check-obj` 32/32, `bootstrap` at a fixed point (`mc2.o == mc3.o`,
  533680 bytes; the `--dump-asm` diff between `mc1` and `mc2` empty), `check-surface` 32/32,
  `test-exe` 32/32, `check-mc`, `check-standalone`, `check-toml`, `check-build`, `check-limits`,
  `test-linux` 32/32 on linux/arm64, `check-examples`, `check-lang`, `check-docs` (113 symbols,
  14 flags, 16 TOML keys, 10 directives, 44 samples, 110 links), `site` 61 pages / 5 sections /
  40 fences, `check-site` 0 link problems + `checkhtml.py` 61 files 0 problems + `contrast.py` 50
  pairs 0 below the minimum. Two consecutive renders of `site/public` are byte-identical
  (`diff -r` empty) and the real `docs/` tree raises no refused-scheme and no too-deep warning.
  Golden rewritten ONCE, from `06157cbe…7731d5` to
  `8c848b105b838d049290643a320348c14988404fe058014c8ec09851e8ee2b06`, only after the empty
  `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`.
- M31 core ✔ (`docs/specs/M31.md` § 2, the three gaps the concurrency panel found; the example
  `examples/conc` is a separate step). All three are generic and inert for an untaught program.
  1. **`decl_find` and the readers** (`src/parse.mc`, a 75-line block inside the public API section; the file grows +119 in total, the rest being the `on_jump` half):
     `decl_find(name)` walks `unit_head` linearly, in declaration order, and returns the node index
     of the `N_FUNC`/`N_PROTO`/`N_EXTERN`, -1 if none; `decl_ret`, `decl_nparams`,
     `decl_param_type` read it; `decl_valid` is the guard, so an unchecked
     `decl_ret(decl_find(f))` after a -1 gives -1 instead of reading the node table at random.
     Only what has been parsed so far is visible, which is written down rather than hidden.
     No module reads `unit_head` any more.
  2. **`on_jump(&f)`** — `i64 f(i64 n, i64 kind, i64 depth)`, table in `src/hooks.mc` (+44, shaped
     like `on_stmt`'s, arena tag `T_ONJUMP`), three call sites in `parse_stmt_core` through
     `jump_hook`, so the hook runs at node creation, **before** any `on_stmt` hook and before
     another module can rewrite the jump. `blk_depth` counts open blocks: `+1` in `parse_block`,
     and in `stmt_syntax` when the dispatch token is `K_LBRACE` (a module that owns `{` opens a
     block the core never sees) — each block exactly once; `parse_function` rebases it to 0, so
     `depth` is per function. `p_blockdepth()` reads the same counter, which is what makes the
     `depth` argument comparable to something (added beyond the spec's four lines for exactly
     that reason). 0 from a handler drops the jump and an empty `N_BLOCK` takes its place.
     What it does **not** see: a jump another module fabricates never goes through
     `parse_stmt_core`.
  3. **The ABI contract** (`docs/reference/objects.md` § 4, new; cross-referenced from
     `machine.md`): parameters in `x0..x7` untouched by the prologue, `x0` untouched by the
     epilogue, `frame == 0` for a zero-parameter zero-local function with the `stp`/`ldp` pair
     still unconditional, depths `x9..x15`, scratch `x8`/`x16`/`x17`, `x18..x28` never written,
     `callp` (pointer in `x16`, args `x0..x6`, `blr x16`, result `x0`), and the `#opcode`
     fixed-register rule. `scripts/check-surface.sh` asserts each claim against `--dump-asm`:
     six probe functions compared instruction by instruction, `lib/sys_svc.mc`'s `write` the same
     way, and over `src/mc.mc` — **837 functions**, every prologue, `ret` preceded by exactly
     `ldp x29, x30, [sp], #16`, and **0** mentions of `x18..x28` in 58 914 lines.
  Demos in `lib/user_syntax_demo.mc` (468 -> 629 lines): `widen x = f(a);` takes the local's type
  from `decl_ret` and casts each argument to `decl_param_type` (the FFI half: a C callee does not
  narrow its own arguments), and `guard EXPR { ... }` runs one statement on every exit edge —
  the fall-through and each jump inside the body. Ordering is proved by a number: `retcount`, the
  module's count of statements that still looked like an `N_RETURN` when `on_stmt` ran, does not
  move for a guarded jump. Negative cases `tests/err/067`–`070` (unknown callee, void result,
  wrong arity, `break N` out of a guard), each asserted with its exact message.
  Docs: `docs/surface.md` § Tier 3 (seven registrations now) + a new § M31,
  `docs/reference/hooks.md` (`on_jump`, the `decl_*` family, `p_blockdepth`, and `decl_name`,
  which the widened `decl_` prefix in `scripts/check-docs.sh` newly requires),
  `docs/reference/objects.md` § 4, `docs/reference/machine.md`.
  — `stage0/` untouched, 2846/3000. `make bundle` re-run: 33 files, raw 424421 B -> LZ 191969 B,
  blob 192307 B. `make check` green end to end (RC 0): `test` 32/32, `check-lex` 71/71,
  `check-ast` 71/71, `check-bundle` (lz round trip 57 cases), `check-asm` 71/71, `check-obj`
  32/32 (inert), `bootstrap` at a fixed point (`mc2.o == mc3.o`, 543128 bytes; the `--dump-asm`
  diff between `mc1` and `mc2` empty), `check-surface` 32/32 plus the new `decl_find`/`on_jump`
  cases and the nine ABI assertions, `test-exe` 32/32, `check-mc` 6/6, `check-standalone`,
  `check-toml` 10/10, `check-build` 11/11, `check-limits` 16/16 under 90%, `test-linux` 32/32 on
  linux/arm64, `check-examples`, `check-lang` (14 lx tests), `check-desktop`, `check-docs`
  (121 symbols, 14 flags, 16 TOML keys, 10 directives, 44 samples, 112 links), `site` + `check-site`
  (50 contrast pairs, 0 below the minimum). Golden rewritten ONCE, from
  `8c848b105b838d049290643a320348c14988404fe058014c8ec09851e8ee2b06` to
  `b7d47491036452c19d72faba7358b17bbefb20c7f6b4f61ae339c4a14c3c7583`, only after the empty
  `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`. The whole `--dump-asm` delta against the
  previous compiler is the 10 new functions, the `T_*` renumbering (`T_ONJUMP` inserted after
  `T_ONSTMT`), the four functions that gained the counter or the hook call, and `l_strN` index
  shifts — no other body changed.
- M17 step A ✔ (`docs/specs/M17.md` § step A, plus the two core mechanisms decided in
  `docs/specs/M33.md` § 1): **the code generator split into a resolver, a target-independent
  walker and a machine**, with the frozen C seed as the oracle — it is still one monolithic
  generator and its objects and `--dump-asm` had to come out identical.
  1. **`src/gen_resolve.mc`** (536 lines): `gen_resolve(unit)` binds every name and types every
     expression into a **side table indexed by node** (`RES_SIZE 32`: type, kind, decl, flag),
     allocated once from `nnodes` and zeroed. `ND_SIZE` stays 104, no node field was added and
     `--dump-ast` does not move — the 18 `set_nd_type` calls that used to happen as a side effect
     of AArch64 instruction selection are gone. Readers: `res_type`, `res_kind`, `res_decl`,
     `res_local_slot`, `res_bind` (M33's encoding), `res_intrin`, `res_addr_taken` (keyed by the
     DECLARING node, because a local's index is reused across sibling blocks) and
     `res_fn_addr_taken`. It also took over the signature table (`func_add`/`func_find`/`fs_*`)
     and the global table (`global_add`/`global_find`/`glb_*`), with `GLB_SYM` still filled by
     `gen_globals` at placement time — so the symbol creation order, which fixes the symbol table
     and therefore the bytes, did not move. Every name diagnostic moved with it, in the order
     `gen_lower` raised them (signatures, prototypes, globals, then each body).
  2. **`src/gen_walk.mc`** (1031) + **`src/machine_arm64.mc`** (675), from the old
     `src/gen_arm64.mc` (1623). The walker owns the `Ins` buffer, the frame in bytes
     (`slot_new`), the label counter, the loop stack, block scoping, sections, globals, strings,
     symbols and `I_LABEL` (opcode 0, reserved) — and mentions no register. It drives a
     **machine table**: `uptr m_arm64[MTASK_COUNT]`, 30 slots of `&fn` registered with
     `machine("arm64", tab)` in `src/hooks.mc` and called through `callp` (`mach(MTASK_X)`).
     The machine owns the register partition, the spill (`dslot`, `val_reg`/`dst_reg`/`dst_done`,
     `save_live`/`restore_live`), `REG_FRAME`/`fix_frame`, the encoders and the dump.
     `MAXDEPTH`, the register assignment and the spill semantics are unchanged; `frame too large`
     stays in the walker on purpose (M17 § step B asks for diagnostic parity).
     Vocabulary: `MTASK_*` (30), `MOP_*` (13), `MUN_*` (3), `MCOND_*` (6) — named `MTASK_` and not
     `MT_` because `examples/lang/lang_tab.mc` already has `MT_RET`.
     Three deliberate deviations from the spec's sketch, all documented: `m_global_addr`/
     `m_str_addr` are one task (`MTASK_SYM_ADDR`), `m_arg_move` is folded into `MTASK_CALL`/
     `MTASK_CALLP` (which is what lets `callp` put its pointer in `x16` without the walker
     knowing), and `m_prologue(frame, nparams)` is `MTASK_PROLOGUE` + `MTASK_PARAM` +
     `MTASK_FRAME_FIX` because the frame size is only known after the body.
     `gen_lower`, `gen_encode_all`, `gen_dump_asm` and every `gen_*` accessor kept their names and
     their behaviour: `lib/backend_arm64.mc`, `src/backend_exe.mc` and `src/backend_elf.mc` were
     not touched.
  3. **`target(os, arch, obj_backend, exe_backend)`** in `src/hooks.mc`, registered in
     `src/main.mc` (`macos/aarch64 -> macho + macho-exe`, `linux/aarch64 -> elf-obj + none`).
     `src/driver.mc` lost `i64 drv_linux` and both hardcoded lists; the two messages are now built
     FROM the registry (`target_os_list`, `target_arch_list`) and come out byte for byte as
     before — `only macos and linux (see docs/build.md)`, `only aarch64 (see docs/build.md)`,
     `linux requires [linker]: there is no direct executable`. Fixed ceilings (`MAXTARGETS 16`,
     `MAXMACHINES 8`) on purpose: neither table scales with the program, so M23's rule does not
     apply.
  Docs: `docs/reference/machine.md` rewritten as the versioned contract (version 1, the 30 slots
  with signatures, what each side owns, the deviations), `docs/reference/objects.md` § 1b
  (`gen_resolve` and the readers) and its file references, `docs/reference/hooks.md`
  (`machine`/`machine_find`/`machine_use`/`machine_task`/`machine_arm64_init`, `target`),
  `docs/surface.md` § Tier 2 ("the third seam"), `docs/reference/bundle.md` and `docs/build.md`
  (the three new bundle names).
  — `stage0/` untouched, 2846/3000. `make bundle` re-run (35 files, raw 455370 B -> LZ 207275 B,
  blob 207644 B). `make check` green end to end (RC 0): `test` 32/32, `check-lex` 73/73,
  `check-ast` 73/73, `check-bundle` (lz round trip 59 cases), `check-asm` 73/73, `check-obj`
  32/32 against the frozen seed, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 578696 bytes;
  the `--dump-asm` diff between `mc1` and `mc2` empty), `check-surface` 32/32 plus the nine ABI
  assertions (920 functions of `src/mc.mc`, 0 mentions of `x18..x28` in 62 323 lines),
  `test-exe` 32/32, `check-mc` 6/6, `check-standalone`, `check-toml` 10/10, `check-build` 11/11,
  `check-limits` 16/16 under 90%, `check-minimal`, `test-linux` 32/32 on linux/arm64,
  `check-examples`, `check-lang` 14, `check-conc` 21, `check-desktop`, `check-docs`
  (127 symbols, 14 flags, 16 TOML keys, 10 directives, 45 samples, 123 links), `site` +
  `check-site`. Golden rewritten to
  `b2cbbde41f36843c3ef7970a4bd66b631828736771bac0d5df047ded9516375e`, only after the empty
  `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`. Independent proof that nothing moved: a
  copy of `build/mc1` taken BEFORE the refactor and the one after produce byte-identical objects
  for all 32 `tests/*.mc`, for `src/mc.mc` itself, and — through the taught compilers each of them
  builds — for `examples/api/main.mc`, `examples/lang/main.lx`, `examples/conc/main.lx`,
  `examples/desktop/main.mc` and `examples/desktop/main.ui`.
- M17 step B ✔ (`docs/specs/M17.md` § step B): **the x86-64 machine and `linux/x86_64`**.
  `src/machine_x86_64.mc` (775 lines) fills the same task table `machine_arm64.mc` fills, and not
  one line of `src/gen_walk.mc` became architecture-specific: depths 0..3 in `r8..r11` (what is
  left once the callee-saved half and the argument registers are off the table), scratch
  `rax`/`rcx`/`rdx` (`idiv` writes `rdx`, `div` needs it zeroed, every shift counts in `cl`),
  locals at `[rbp - off]` — no frame fixup — arguments in `rdi rsi rdx rcx r8 r9` with the seventh
  and eighth pushed with `push r/m64` (no scratch spent; one extra `sub rsp, 8` when the count is
  odd, for the 16-byte alignment at the `call`), result in `rax`, `callp` with the pointer in
  `rax`, moved BEFORE any argument register because it may itself live in `r8..r11`.
  A descriptor table (`x86_desc`, six columns per opcode) drives **the same** `x86_put` that
  encodes and the dump that prints `--dump-asm`; `MTASK_INS_SIZE` runs `x86_put` over a scratch
  buffer and returns the length, so size and encoding cannot disagree by construction.
  **Machine contract: version 2** (`docs/reference/machine.md`) — one new slot,
  `MTASK_RELOC_OFF(e) -> bytes`. Version 1 assumed a relocation patches the instruction from its
  first byte, which is true of every fixed-width encoding and false of x86 (`call rel32` +1,
  `lea r,[rip+d32]` +3). AArch64 answers 0 and its objects did not move a byte.
  ELF x86-64 inside the same `src/backend_elf.mc` (`elf_em`, `R_X86_64_64/PC32/PLT32`, addend −4 on
  both pc-relative kinds because a `rel32` counts from the END of its field); backend
  `elf-obj-x86_64`; `target("linux", "x86_64", "elf-obj-x86_64", 0)` in `main.mc`. **The object
  backend is what picks the machine** (`machine_use` as its first statement), not a fifth column on
  `target()`: the format already records the architecture, and an AST-consuming backend (wasm)
  needs no machine at all. `--machine=NAME` covers the `--dump-*` modes, which never reach a
  backend. `// skip-x86_64:` on `031-opcode`, `033-reloc` and `tests/linux/070-nolibc.mc` — the
  three that write instructions by hand. `scripts/sysroot-linux.sh --arch x86_64` (alpine
  linux/amd64), `scripts/test-linux.sh --arch x86_64`, the `make test-linux-x86_64` target inside
  `make check` (self-skipping without Docker/ld.lld) and the `linux-x86_64` CI leg on
  `ubuntu-latest` (docs/plan.md § Rule for every new target).
  **The seed needed more arena**: `build/mc0 src/mc.mc` was dying with `arena exhausted` with every
  `MAX*` under 57% — what was full is `HEAP_SIZE` in `stage0/arena.c` (32 MiB, chosen in `517685f`
  when self-compiling touched 14.5 MiB; `nodes_grow` doubles and never frees, ~18.9 MB of dead
  arrays alone). Raised to 64 MiB — capacity, not behaviour: no generated byte changes.
  `scripts/check-limits.sh` gained the seventeenth row, the heap, measured as the max RSS of a real
  `build/mc0` run (`docs/build.md` § The seventeenth row).
  — `make check` green end to end (RC 0, zero FAIL): `test` 32/32, `check-lex` 74/74, `check-ast`
  74/74, `check-bundle` (lz 60 cases), `check-asm` 74/74, `check-obj` **32/32 identical to the
  frozen seed**, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 622792 bytes; the `--dump-asm`
  diff between `mc1` and `mc2` empty), `check-surface` 32/32 plus the nine ABI assertions
  (996 functions, 0 mentions of `x18..x28` in 67 051 lines), `test-exe` 32/32, `check-mc` 6/6,
  `check-standalone`, `check-toml` 10/10, `check-build` 11/11, `check-limits` **17/17** (heap
  29 Mi/64 Mi = 46%), `check-minimal`, `test-linux` 32/32 on linux/aarch64,
  **`test-linux-x86_64` 29/29 on linux/x86_64** (4 skipped), `check-examples`, `check-lang`,
  `check-conc`, `check-desktop`, `check-docs` (129 symbols, 15 flags, 16 TOML keys, 10 directives,
  45 samples, 131 links), `site` + `check-site`. Golden rewritten once to
  `9c34d8d63af895a7d382c9d24e4f7e56298f133ef6f8b15c3a3940c00774a09c`, only after the empty asm diff
  and `cmp build/mc2.o build/mc3.o`. Bundle regenerated (36 files, raw 489036 -> LZ 221119, blob
  221506 B); `tools/bundle.list` gained `mc/machine_x86_64`.
  Encoder cross-check: the **948 distinct instructions** the machine emits while compiling
  `src/mc.mc` for x86-64 re-assemble byte-identically under `llvm-mc -triple=x86_64-linux-musl`,
  and the relocations match `clang --target=x86_64-linux-musl -c` of equivalent C
  (`R_X86_64_PC32` at instruction+3, `R_X86_64_PLT32` at instruction+1, both with addend −4),
  inspected with `llvm-objdump -dr` and `llvm-readobj`.
- M37 done (`docs/specs/M37.md`, `docs/guide/90-linux-host.md`, `docs/bootstrap.md` § The Linux
  chain, `docs/build.md`, `docs/ci.md`): **`mc` hosted on Linux (aarch64 and x86_64)**.
  `stage0/` untouched (2848/3000): the C seed emits Mach-O only and stays macOS-first, so a Linux
  host does not bootstrap from clang -- it bootstraps from a published (or cross-built) `mc`.
  1. **The host layer.** `src/core.mc` is host-neutral; everything the COMPILER needs from the
     system it RUNS on is one file the entry point includes before the core --
     `src/host_macos.mc` (72), `src/host_linux.mc` (41, the OS half) plus
     `src/host_linux_aarch64.mc` / `src/host_linux_x86_64.mc` (7 each, the three architecture
     answers), with entries `src/mc_linux.mc` (15) and `src/mc_linux_x86_64.mc` (9). It answers
     `host_os/host_arch/host_machine/host_sys/host_include/host_environ/host_init/host_has_sdk`
     and declares `posix_spawnp`/`posix_spawn_file_actions_*`/`waitpid`/`mkdir`/`unlink` (same
     names in musl) plus `O_CREAT`/`O_TRUNC`, the two values that differ. `_NSGetEnviron` was the
     single blocker: musl has no equivalent, so the Linux host takes the `envp` the C runtime
     passes and `main` became `main(argc, argv, envp)`, handing it to `host_init()` first thing.
     `src/arena.mc` stayed host-neutral on purpose (so `lexdump`/`tomldump`/`tools/bundle.mc`/
     `site/gen` need no host file): its one non-portable value, the anonymous-mapping flag, is now
     `0x1022` -- `MAP_PRIVATE|MAP_ANON` on macOS and `MAP_PRIVATE|MAP_ANONYMOUS` on Linux, each
     with one ignored bit, measured on both.
     What the layer decides: `[target]` with no section = the host pair; `mc x.mc -o x.o` uses the
     host's OBJECT backend (was hardcoded `macho`); the dumps start on `host_machine()`; and
     `mc build` links the taught compiler with the host's exe backend when it has one and with
     `[linker]` when it does not. `backend_macho`/`backend_exe` now call `machine_use("arm64")`
     first, like every backend since M17 -- without it an x86_64-hosted `mc` lowered Mach-O with
     the x86 machine. New flags: `mc --host` (os/arch/sys) and `--include=DIR`.
     Bundle: `mc/host_macos`, `mc/host_linux`, `mc/host_linux_aarch64`, `mc/host_linux_x86_64`
     (40 entries) plus the synthetic **`<mc/host>`**, resolved in `src/main.mc`
     (`host_bundle_open`) to the running compiler's own host file -- which is what `mc build`
     writes above `#include <mc/core>`, so one `mc.toml` teaches a macOS compiler on macOS and a
     Linux one on Linux.
  2. **The chain.** `src/mc.linux-aarch64.toml` / `src/mc.linux-x86_64.toml` cross-build
     `build/mc-linux-arm64` (730168 B) and `build/mc-linux-x86_64` (726184 B) from macOS (ELF,
     musl, `ld.lld`); `make mc-linux` / `mc-linux-x86_64`. `scripts/bootstrap-linux.sh [SEED]`
     (232) is the Linux fixed point -- seed -> `mc1l` -> `mc2l` -> `mc3l`, `cmp`, golden
     `tests/golden/mc2-linux-<target>.sha256`, then the whole suite natively. With no argument it
     takes `build/mc-linux-<target>`, else a release asset (`gh release download` or curl of
     `mc-<VER>-linux-<arch>.tar.gz`), **unpacked only after the SHA-256 matches**; it refuses a
     seed whose `mc --host` is not `linux/<this machine>` and checks that `mc1l` and `mc2l` agree
     on `--dump-asm`. `scripts/link-linux.sh`, `scripts/link-host.sh` (uname dispatch) and
     `scripts/build-exe.sh` (`--exe` on macOS, object + linker on Linux) are what let the same
     cross-check scripts run on both hosts.
  3. **The Makefile switches on `uname -s`.** `REF`/`MC` name the two compilers a cross-check uses
     -- `mc0`/`mc1` on macOS, `mc1l`/`mc2l` on Linux. Linux `check` = `budget bootstrap-linux
     check-lex check-ast check-asm check-obj check-bundle check-mc check-toml check-limits
     check-skipped`, and `check-skipped` prints one line per macOS-only target with its reason.
     `make check-linux-host` (macOS, self-skips without Docker) cross-builds both compilers and
     runs the whole thing per architecture inside `alpine:3`, ending with the **cross proof**.
  4. **Examples.** `examples/conc`'s platform layer split into `lib/macos/thread.mc` (libdispatch
     semaphores) and `lib/linux/thread.mc` (`sem_init`/`sem_wait`/`sem_post`, all-zero pthread
     initializers, `getauxval(AT_HWCAP)` for the LSE probe), picked by `[include].paths` --
     `mc.toml` vs the new `mc.linux.toml` -- and by `--include=` for the single-file CLI.
     `examples/api/mc.linux.toml` links SQLite statically and is documented as NOT exercised
     (the musl sysroot is `apk add musl-dev`, four files, no SQLite).
  5. **CI/releases**, in the same "compile here, link there" shape the suite legs already use --
     GitHub's `macos-15` runners have **no Docker**, so the musl sysroot (four files out of
     `alpine:3`) cannot exist there and neither can a link. `ci.yml`: the macOS job cross-COMPILES
     both Linux compilers to ELF objects (`make mc-linux-obj` / `mc-linux-x86_64-obj`, the new
     `src/mc.linux-{aarch64,x86_64}-obj.toml` with `kind = "obj"` -- `drv_entry` returns before
     the `[linker]` requirement, so neither config has one) and uploads them with `build/mc2.o`;
     the two jobs `mc on linux/arm64 host` (ubuntu-24.04-arm) and `mc on linux/x86_64 host`
     (ubuntu-latest) link the object under `MC_SYSROOT=/usr/lib/<arch>-linux-musl` with
     `scripts/link-linux.sh` (which runs `ld.lld` and nothing else when the four files are there),
     then run `make check SEED=...` plus the cross proof. The object is byte-identical to the one
     the executable configs write, so `make mc-linux` stays the local road. `release.yml` has the
     same split: `build` (macOS) uploads `mc-linux-objects`, `build-linux` (a two-entry matrix on
     the two Ubuntu runners) links each object, proves it with `scripts/bootstrap-linux.sh` and
     packages it, and `publish` needs both -- three tarballs. `build-future-hosts` keeps
     `if: false` with only the Windows entries.
  — Acceptance, measured here: macOS `make check` green end to end (RC 0) -- `test` 32/32,
  `check-lex`/`check-ast`/`check-asm` 80/80, `check-obj` **32/32 identical to the frozen seed**,
  `bootstrap` at a fixed point (`mc2.o == mc3.o`, `--dump-asm` diff empty), `check-surface` 32/32,
  `test-exe` 32/32, `check-mc` 6/6, `check-standalone` (`<mc/host> + <mc/core> + <user_default> ==
  src/mc.mc`, byte for byte), `check-toml` 10/10, `check-build` 11/11, `check-limits` 17/17 under
  90%, `check-minimal`, `test-linux` 32/32, `test-linux-x86_64` 29/29, `check-examples`,
  `check-lang`, `check-conc` 21, `check-desktop`, `check-docs` (138 symbols, 17 flags, 16 TOML
  keys, 10 directives, 46 samples, 153 links), `site` 69 pages + `check-site`. Golden rewritten
  ONCE, to `e958ceab11064dd16fc3306937744c744548bfff49b323d09bc1a7baf942adbe`, after the empty asm
  diff. `make check-linux-host` green for both architectures (RC 0): fixed point
  `mc2l.o == mc3l.o` (817280 B on aarch64, 757112 B on x86_64), goldens
  `55402bcb…cfe9e7` and `9c142589…5f8f7`, suites 32/32 and 29/29 native, `check-lex/ast/asm`
  80/80, `check-obj` 31/31 and 29/29 (the rest skipped by `// skip-` header), and the **cross
  proof**: `mc2l --backend=macho src/mc.mc` is byte for byte the macOS `build/mc2.o` on both.
  Known gaps, on record: on Linux `check-build`, `check-examples`, `check-lang`, `check-conc`,
  `check-desktop`, `check-docs`, `site` and `check-surface` are skipped with a printed reason --
  each builds `--exe` binaries or macOS dylibs -- and `check-lex`/`check-ast` there compare the
  compiler against itself rather than against the frozen C oracle.
- M19 done (`docs/specs/M19.md`, `docs/build.md` § Windows targets,
  `docs/guide/50-cross-compile.md` § Windows on ARM): **Windows on ARM — COFF objects, a kernel32
  system layer, `lld-link`**. `stage0/` untouched (2848/3000, unchanged since M17 step B raised its
  `HEAP_SIZE`): the COFF writer is a backend in `.mc`, and the machine is the same `arm64` macOS uses — this is a new file FORMAT, not a new
  instruction set.
  New: `src/backend_coff.mc` (375 lines, backend `coff-obj-arm64`) — the third writer over
  `gen_lower` + `gen_encode_all`. One COFF section per module section in creation order, so the
  1-based `SectionNumber` **is** the module's `sym_sect` and nothing is renumbered
  (`__TEXT,__text` -> `.text` `CODE|EXECUTE|READ`, `__TEXT,__cstring` -> `.rdata` `INIT|READ`,
  `__DATA,__data` -> `.data` `INIT|READ|WRITE`, `__DATA,__bss` -> `.bss` `UNINIT` with
  `SizeOfRawData` = zsize and `PointerToRawData` = 0, `#section SEG SECT` -> `.seg.sect` with the
  ELF writer's lowercasing). Alignment is not a field: it is `(log2 + 1) << 20` inside
  `Characteristics`. Symbols are 18 bytes with **no auxiliary records**, no leading underscore
  (`_main` -> `main`, like ELF), `l_strN` -> `$str.N` (STATIC), `Type 0x20` in a pure-instructions
  section, EXTERNAL for globals and undefined, and macho.mc's `sym_order` reused so the three
  writers stay comparable. Relocations are 10 bytes with **no addend field** — COFF is Mach-O's
  shape here, not ELF's — sorted by ascending offset (`elf_rel_order`, which has nothing ELF in
  it): `BRANCH26` 0x0003, `PAGEBASE_REL21` 0x0004, `PAGEOFFSET_12A` 0x0006 on an `add` /
  `PAGEOFFSET_12L` 0x0007 on an ldr/str (the same classifier `elf_pageoff12` and
  `exe_fix_pageoff12` use), `ADDR64` **0x000E**. `TimeDateStamp` is 0, never the clock, and a
  section with 65535 relocations or more is refused with a message instead of written wrong
  (65535 is the overflow SENTINEL, not a count — corrected in the post-M19 review batch below).
  Two long-name encodings, and they are NOT the same: a section name past 8 bytes is `/` plus the
  decimal offset as text, a symbol name past 8 bytes is four zero bytes plus that offset as a
  u32 — using the section form for a symbol makes `llvm-readobj` print `/17` where a name belongs
  (found and fixed during the work).
  `lib/sys_windows.mc` (190): `open`/`creat`/`read`/`write`/`close`/`exit` over seven kernel32
  `extern`s (`GetStdHandle`, `WriteFile`, `ReadFile`, `CreateFileA`, `CloseHandle`,
  `ExitProcess`, `GetCommandLineA`), all non-variadic. There is **no syscall instruction anywhere**
  — Windows has no stable system-call numbers and the documented boundary is the DLL — so unlike
  `lib/sys_svc.mc`/`lib/sys_linux.mc` this layer is ordinary mc code. Descriptors 0/1/2 go through
  `GetStdHandle`; `open`/`creat` hand back the HANDLE and the others take it back unchanged (safe:
  a real handle is never 0, 1 or 2). It provides the entry point too, `mc_start`, which splits
  `GetCommandLineA()` into argc/argv (spaces and tabs separate, `"` toggles) and calls `main`
  through a raw `bl` in a two-parameter shim — x0/x1 are already right and the prologue does not
  touch them (`docs/reference/objects.md` § 4) — so the link carries no crt object at all.
  **It deliberately does not `#include "io.mc"`**, the one divergence from `sys_linux.mc`: on Linux
  the wrappers come out of `libc.a`, an archive the linker takes members from; here they come out
  of an object linked NEXT TO the program, and a second copy of `strlen`/`puts`/`putnum` would be a
  duplicate symbol for every test that includes `lib/sys.mc`. A program that includes the layer
  directly adds `#include <io>` (`tests/windows/070-kernel32.mc` does).
  `scripts/sysroot-windows.sh` (81): writes `kernel32.def` and builds `kernel32.lib` with
  `llvm-dlltool -m arm64`. An import library is a list of names, so there is **no download, no
  mingw and no Windows SDK**; cached like the musl one, `make sysroot-windows` runs it.
  `scripts/test-windows.sh` (346): the same split shape as `test-linux.sh`. `--build-only OUTDIR`
  writes one `.obj` per test (`kind = "obj"`), the `.expect`, the `manifest`, the `skipped` list
  and the two files the other half cannot make — `winrt.obj` (the compiled layer) and
  `kernel32.lib`; `--run-only OUTDIR` needs `lld-link` and nothing else. Two link modes:
  `kernel32` (test + winrt.obj + kernel32.lib, the way musl resolves the same externs) and `self`
  (the source already includes `<sys_windows>`). The default mode is what `make test-windows` runs:
  cross-compile everything, assert every object is an arm64 COFF with TimeDateStamp 0, and link
  three of them with `lld-link`; nothing is executed here.
  Driver: `target("windows", "aarch64", "coff-obj-arm64", 0)` in `src/main.mc` and **nothing else**
  — M17's registry already made `[target].os = "windows"` require `[linker]` and already builds
  both diagnostics from the table. `src/hooks.mc` (+36/-33) only changed to make the list read as
  English with three entries: `tgt_word` became `tgt_walk`/`tgt_list`, a two-pass walk that knows
  the total before the first word, so the message is `only macos, linux and windows (see
  docs/build.md)` and not `macos and linux and windows`. `scripts/check-build.sh` gained the
  windows-without-`[linker]` case and its old "invalid os" example moved from `windows` to `haiku`
  (12/12).
  CI: `Cross-compile the suite for windows/arm64` + the `windows-arm64-objects` artifact on the
  macOS job, and the leg `Link and run the suite (windows/arm64)` on `windows-11-arm` — a tool-facts
  step that looks for a preinstalled `lld-link` first, then a cached download of the LLVM
  Windows-on-ARM release (tarball, falling back to the `woa64.exe` installer), then
  `test-windows.sh --run-only` under bash. It fails loudly rather than skipping: it is the only
  place a Windows binary is ever executed. After merge the architect adds it to the required checks
  (`docs/plan.md` § Rule for every new target).
  Deviations from the spec text, on record: `IMAGE_REL_ARM64_ADDR64` is **0x000E**, not the 0x0001
  the spec wrote (0x0001 is ADDR32) — verified against clang's own objects; `SetFilePointer` is not
  declared, because nothing in `lib/io.mc` or the suite seeks, and an unused `extern` would only be
  an undefined symbol; `os = "windows"` needs no `{sysroot}` work in the driver because M17 already
  generalised it. Not skipped, against the spec's guess: `031-opcode` and `033-reloc` are AArch64
  words and BRANCH26 and this target is AArch64, so they cross-compile and link like everything
  else — `032-svc` is the only `// skip-windows:`.
  Validation on this host: `llvm-readobj --file-headers --sections --symbols --relocs` of
  `013-putnum.obj` against `clang --target=aarch64-windows-msvc -c` of equivalent C agrees on
  Machine, SizeOfOptionalHeader, Characteristics, the four section characteristic words, storage
  classes, `ComplexType: Function`, `IMAGE_SYM_UNDEFINED` and every relocation type;
  `lld-link /machine:arm64 /subsystem:console /entry:mc_start /nodefaultlib` produces
  `001-return42.exe`, `013-putnum.exe` and `070-kernel32.exe`, each an
  `IMAGE_FILE_MACHINE_ARM64` PE with `Subsystem: IMAGE_SUBSYSTEM_WINDOWS_CUI` and the seven
  kernel32 imports; a full `mc build` with `[linker] cmd = "lld-link"` produces the same thing
  through the driver.
  — `stage0/` untouched, 2848/3000; `src/*.mc` 17511 lines. `make bundle` re-run (38 files, raw
  511899 -> LZ 232981, blob 233396 B; `tools/bundle.list` gained `mc/backend_coff` and
  `sys_windows`). `make check` green end to end (RC 0): `test` 32/32, `check-lex` 76/76,
  `check-ast` 76/76, `check-bundle` (lz round trip 62 cases), `check-asm` 76/76, **`check-obj`
  32/32 identical to the frozen seed**, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 644680
  bytes; the `--dump-asm` diff between `mc1` and `mc2` is empty), `check-surface` 32/32 + inert,
  `test-exe` 32/32, `check-mc` 6/6, `check-standalone`, `check-toml` 10/10, `check-build` 12/12,
  `check-limits` 17/17 under 90%, `check-minimal`, `test-linux` 32/32 on linux/aarch64,
  `test-linux-x86_64` 29/29 on linux/x86_64, **`test-windows` 32/32 objects + 3 linked
  executables** (1 skipped), `check-examples`, `check-lang`, `check-conc`, `check-desktop`,
  `check-docs` (130 symbols, 15 flags, 16 TOML keys, 10 directives, 45 samples, 139 links),
  `site` + `check-site`. Golden rewritten once to
  `be65caca70bd805edd91ed366792591e869f3ff8d3b4def5c75ebf97ca80197e`, only after the empty asm diff
  and `cmp build/mc2.o build/mc3.o`.
- Post-M19 batch (review): three confirmed findings, two fixed in code and one recorded as a scope gap.
  1. **`win_split` handed out an out-of-bounds argv pointer once the command line filled `win_cmd`.**
     `lib/sys_windows.mc` guarded the per-character copy (`o < WIN_CMDMAX - 1`) and the terminator
     (`o < WIN_CMDMAX`) but not the pointer store, so once `o` reached `WIN_CMDMAX` (2048) every
     later argument got the SAME pointer `win_cmd + 2048` — one byte past the array, never written
     and never NUL-terminated, which is what `open(argv[1], ...)` in `tests/025-linecount.mc` would
     read. Reproduced by lifting `win_split` verbatim into a harness compiled natively
     (`3000 * 'x'` + `" y z"`): before, `nargs=3` with args 1 and 2 both at offset 2048 and both
     flagged out of bounds; after, `nargs=1` and every pointer inside the array. The fix is one
     line, `if (o >= WIN_CMDMAX) break;` next to the existing `if (n >= WIN_MAXARG) break;` — the
     command line truncates at the byte ceiling instead of one past it. Clamping `o` instead would
     leave every later argument aliased to the same trailing slot. Ordinary command lines are
     byte-identical (`prog.exe a b`, quoted regions, runs of spaces).
  2. **The `NumberOfRelocations` ceiling was off by one against the PE/COFF sentinel.**
     `src/backend_coff.mc` refused `nr > 0xffff`, but 65535 is not a count: it is the sentinel that
     says the real count is in the `VirtualAddress` of an extra leading `IMAGE_RELOCATION`, with
     `IMAGE_SCN_LNK_NRELOC_OVFL` in `Characteristics` (LLVM's own WinCOFF writer flags overflow at
     `>= 0xffff`). Reproduced with two generated programs of 65534 and 65535 `bl` calls: before,
     both compiled and `llvm-readobj` reported `RelocationCount: 65535` with the OVFL bit clear —
     the overflow form written as a plain count. Now `nr >= 0xffff` fails with `mc: 65535 or more
     relocations in one section: .text` (exit 1) and the 65534-relocation object is byte-identical
     to the one the old compiler produced.
  3. **No `.pdata`/`.xdata`** — accepted M19 gap, not fixed. `clang --target=aarch64-windows-msvc -c`
     of a non-leaf function emits both sections; `coff-obj-arm64` emits neither, for any function
     (verified with `llvm-readobj --sections` on the two objects). Windows on ARM64 has no
     frame-pointer fallback, so without a `RUNTIME_FUNCTION` record the OS unwinder treats an mc
     frame as a leaf whose return address is still in `x30`. Nothing in the language raises or
     catches and `/nodefaultlib` links no C runtime, so nothing in the suite unwinds and the
     `windows-11-arm` leg cannot see it; it matters when something else unwinds THROUGH an mc frame
     (a hardware fault, a `RaiseException` from an `extern`, a debugger's stack walk). The packed
     unwind encoding cannot describe mc's prologue when the frame is small enough that MSVC would
     fold the allocation into the `stp`, so doing it properly means the full unwind codes plus one
     `IMAGE_REL_ARM64_ADDR32NB` per function — a milestone of its own. Written down in
     `docs/reference/objects.md` § No `.pdata`/`.xdata`, `docs/build.md` § Windows targets and
     `docs/specs/M19.md` § Out of scope.
- M20 done (`docs/specs/M20.md`, `docs/build.md` § Windows targets,
  `docs/guide/50-cross-compile.md` § Windows, `docs/reference/objects.md` § 4c,
  `docs/reference/machine.md`): **Windows x64 — COFF AMD64 relocations, the Win64 ABI as a second
  x86-64 machine, and an architecture-neutral entry shim**. `stage0/` untouched (2848/3000).
  1. **`x86_64-win`, a second machine out of the same file** (`src/machine_x86_64.mc` +83/-17,
     775 -> 841). `m_x86_64_win` is a copy of `m_x86_64` with ONE slot replaced, `MTASK_PROLOGUE`;
     the other thirty entries are literally the same `&fn`, because `MTASK_INS_SIZE`,
     `MTASK_ENCODE`, `MTASK_DUMP`, `MTASK_RELOC_KIND` and `MTASK_RELOC_OFF` are pure functions of
     the `Ins` record and are ABI-blind. The convention lives in three globals — the argument table
     (`rcx rdx r8 r9`), `x86_nargreg` (6 / 4) and `x86_shadow` (0 / 32) — set by that prologue,
     which `gen_func` always runs before the first `MTASK_PARAM` and before any `MTASK_CALL`, so
     they can never be stale. `x86_param` reads argument `i >= nargreg` at
     `16 + shadow + (i - nargreg) * 8`, i.e. `[rbp+48]` for the fifth Win64 parameter;
     `x86_push_args` subtracts the shadow **last**, so it lands below the pushed arguments and the
     fifth argument is at `[rsp+32]` — which is why it must return non-zero (32) even for a call
     with no stack arguments. The alignment rule is unchanged (`8*np + 32` is 0 mod 16 iff `np` is
     even). **The register partition does not move**: `rax`, `rcx`, `rdx` and `r8..r11` are
     volatile in both ABIs, so depths stay in `r8..r11` and scratch stays `rax`/`rcx`/`rdx`;
     `rdi`/`rsi` become callee-saved and the machine simply stops naming them. Two machines and not
     a runtime flag because `--machine=x86_64-win` has to be able to DUMP the Win64 sequence.
  2. **`coff-obj-x86_64`** (`src/backend_coff.mc` +62/-10, 380 -> 432; `src/main.mc` +2):
     `i64 coff_machine`, the exact counterpart of `elf_em`, set by each entry point and deciding
     both the header value (`IMAGE_FILE_MACHINE_AMD64` 0x8664) and the relocation table.
     `R_X86_PLT32` and `R_X86_PC32` both map to `IMAGE_REL_AMD64_REL32` 0x0004, `R_UNSIGNED`
     (len 3) to `IMAGE_REL_AMD64_ADDR64` **0x0001** — not ARM64's 0x000E. **No addend anywhere and
     none needed**: `IMAGE_REL_AMD64_REL32` is defined from the byte FOLLOWING the four-byte field
     (`S + A - (P + 4)`) where ELF's `R_X86_64_PC32` computes `S + A - P` from its start, so the
     `-4` `elf_rel_addend` writes is already inside COFF's definition; `A` is the in-place content
     and the encoder leaves both fields zero. `REL32_1..5` are never needed — both relocated
     instructions put their disp32 at the very end. `backend_coff_x86` names `x86_64-win` as its
     first statement, which is how the ABI is reached without `target()` growing a fifth column
     (the M17 step B rule). `target("windows", "x86_64", "coff-obj-x86_64", 0)`.
  3. **The entry shim split** (`lib/sys_windows_start.mc`, new, 41 lines; `lib/sys_windows.mc`
     +21/-20). M19's `win_call_main` was `reloc(BRANCH26, "_main"); emit(0x94000000);` — a raw
     AArch64 `bl`, the only architecture-specific line in the layer — and it could NOT be
     re-encoded for x86-64: `emit()` writes exactly four bytes, a pending `reloc()` is pinned to
     the START of that word, `gen_word` accepts only the four Mach-O kinds, and an x86
     `call rel32` is five bytes with its field one byte in. The raw words were DELETED, not
     doubled: `mc_start` moved to its own bundled file (`<sys_windows_start>`), compiled once into
     `winstart.obj` and linked into EVERY Windows executable, where `main` is an ordinary `extern`
     reached through `MTASK_CALL`. `lib/sys_windows.mc` keeps the wrappers and `win_split` and
     gains `win_setup()`/`win_argv()`, so the file a program INCLUDES never names `main`.
     `tools/bundle.list` 42 -> 43 entries.
  4. **Scripts and tests.** `scripts/sysroot-windows.sh` unchanged (it already took
     `--arch x86_64`). `scripts/test-windows.sh` (+59/-30, 350 -> 379): `x86_64` ->
     `-machine:x64` and the `IMAGE_FILE_MACHINE_AMD64` assertion on the object AND on the linked
     `.exe`; two-level `skip_reason` copied from `test-linux.sh` (`// skip-windows:` then
     `// skip-<arch>:`, so no test needed a new header); `winstart.obj` built alongside
     `winrt.obj` and present in BOTH branches of `link_one` — the `self` mode now means "no
     `winrt.obj`", not "nothing next to it". The dash form of the lld-link options stays (MSYS
     rewrites a leading `/out:` under Git Bash). `Makefile`: `sysroot-windows-x86_64` and
     `test-windows-x86_64`, the latter in `check`, `.PHONY` and `check-skipped`.
     `tests/windows/071-nested-args.mc` (31) is `f(a, b, g(x, y), h(z))` and the same through
     `callp`: the executable proof that writing `r8`/`r9` — argument registers 3 and 4 on Win64
     AND depth registers 0 and 1 — never clobbers a source still to be read, because the table is
     written in ascending index and every depth register's own argument index is smaller than its
     position in it. `tests/windows/072-six-params.mc` (38) reads a fifth and sixth parameter at
     `[rbp+48]`/`[rbp+56]` and calls the seven-argument `CreateFileA`: the shadow space against a
     real Win64 callee that uses its home space. Both are portable and both legs run them.
  5. **CI** (`.github/workflows/ci.yml` +86): the macOS job cross-compiles for windows/x86_64 and
     uploads `windows-x86_64-objects`; `Link and run the suite (windows/x86_64)` on
     `windows-latest` links and RUNS the suite. `release.yml` untouched — no Windows-hosted `mc`
     here, that is M38. After the merge the architect adds the job to the `main` branch protection
     contexts (`docs/ci.md` § Branch protection).
  Encoder cross-check: the **967 distinct instructions** the Win64 machine emits while compiling
  `src/mc.mc` for windows/x86_64 (76533 in all) re-assemble byte-identically under
  `llvm-mc -triple=x86_64-windows-msvc`, and the 9361 pc-relative displacements it wrote were
  checked against `target - (address + length)`. Header, sections, symbols and relocation types
  match `clang --target=x86_64-windows-msvc -c` of equivalent C field for field
  (`Machine: IMAGE_FILE_MACHINE_AMD64 (0x8664)`, `main` as `Function`/`External` with no aux
  record, `IMAGE_REL_AMD64_REL32` at instruction+1 for a `call` and instruction+3 for a
  `lea r,[rip+d32]`, both with the field zero in place); the differences are mc's `TimeDateStamp`
  0 and the sections clang adds and mc does not (`.debug$S`, `.llvm_addrsig`, the section-def
  symbols). `.pdata`/`.xdata` stay the accepted M19 gap, now recorded for x64 in the same section.
  — `stage0/` untouched, 2848/3000; `src/*.mc` 18169 lines (5185 of them generated).
  `make bundle` re-run BEFORE bootstrapping: 43 files, raw 533478 -> LZ 245893, blob 246397 B.
  `make check` green end to end (RC 0, zero FAIL): `test` 32/32, `check-lex` 83/83,
  `check-ast` 83/83, `check-bundle` (lz round trip 67 cases), `check-asm` 83/83, `check-obj`
  **32/32 identical to the frozen seed**, `bootstrap` at a fixed point (`mc2.o == mc3.o`,
  663416 bytes; the `--dump-asm` diff between `mc1` and `mc2` is empty), `check-surface` 32/32,
  `test-exe` 32/32, `check-mc` 6/6, `check-standalone`, `check-toml` 10/10, `check-build` 12/12,
  `check-limits` 17/17 under 90%, `check-minimal`, `test-linux` 32/32 on linux/aarch64,
  `test-linux-x86_64` 29/29 on linux/x86_64, **`test-windows` 34/34 objects for windows/aarch64
  (1 skipped) and `test-windows-x86_64` 32/32 for windows/x86_64 (3 skipped)**, 3 executables
  linked with `lld-link` in each, `check-examples`, `check-lang`, `check-conc`, `check-desktop`,
  `check-docs` (140 symbols, 17 flags, 16 TOML keys, 10 directives, 46 samples, 163 links),
  `site` 71 pages + `check-site` (0 link problems, 71 files 0 problems, 50 contrast pairs 0 below
  the minimum). Independent inertness proof: a copy of `build/mc1` taken BEFORE the milestone and
  the one after produce a byte-identical `--dump-asm` over `src/mc.mc` for arm64 and for
  `--machine=x86_64`.
  Goldens rewritten ONCE, all three in the same commit, only after the empty `--dump-asm` diff and
  `cmp build/mc2.o build/mc3.o`: `tests/golden/mc2.sha256`
  `6674d967…591b6d40` -> `6deafb02493e63f59eaa9c12627dcd63f0d9bbda1a0e22be852fc36616ef3bad`, and
  the two Linux ones re-recorded by deleting them and running `make check-linux-host` —
  `mc2-linux-arm64.sha256` `017325eb2de7548f32fea83caad8383db0d813c9094cd23644bee3c6af826ff8`,
  `mc2-linux-x86_64.sha256` `3b93e1887585e8d38d62421a1451bd66a9f4752c7006fb2e67b6bb300852dfce`.
  `build/mc-exe` 600211 B.
- M38 done (`docs/specs/M38.md`, `docs/guide/95-windows-host.md`, `docs/bootstrap.md` § The
  Windows chain, `docs/ci.md` § M38): **`mc` hosted on Windows, arm64 and x64**. `stage0/`
  untouched (2848/3000). Four steps, one commit each.
  1. **Stack parameters 9..12, `MAXPARAMS` 8 -> 12 in `src/`** (Decision 1). `CreateProcessA`
     takes ten parameters, so the host layer could not even be declared. The arm64 machine gained
     the caller half (`a64_stack_args`: arguments 9..12 at `[sp, #0..#24]`, written BEFORE
     `x0..x7` so the stores can still read the depth registers and use `x16` for a spilled one)
     and the callee half (`a64_param` reads `[x29 + 16 + 8*(i-8)]`, since the frame record moved
     sp by 16). **Deviation from the spec's sketch, on record:** the outgoing area is NOT a
     `sub sp` around the call the way `x86_push_args` does it — every frame slot is addressed
     through the fictitious `REG_FRAME` base that `fix_frame()` only turns into `sp + (frame -
     off)` at the END of the function, so an sp that moved inside the body would make every
     spilled depth read the wrong address. It is reserved at the bottom of the FRAME instead
     (`a64_frame_fix` adds 16 or 32 bytes, `die("frame too large")` guards the 12-bit immediate)
     and the stores name `REG_SP`, which `fix_frame` leaves alone. `a64_callp` spreads its
     arguments over `x0..x7` and the stack for the same reason. `src/machine_x86_64.mc` needed
     nothing: `x86_push_args`/`x86_param` were already general (SysV 7th+, Win64 5th+ above the
     shadow space). The seed keeps 8 — `stage0` only compiles `src/mc.mc`, which has no function
     with more than eight parameters — a documented divergence like `MAXSTRS`/`MAXGLOBALS`.
     `tests/mc/080-twelve-params.mc` (sum12/pick12 direct, sum11/pick11 through `callp`, sum10
     with two CALLS in stack positions, `u8`/`u16`/`u32` on the stack path, a nested 12-argument
     call) runs on **all five targets**; `scripts/check-surface.sh` gained the callee-side and
     caller-side ABI assertions. Inertness proved: `--dump-asm` diffs EMPTY for `arm64`,
     `x86_64` and `x86_64-win` over `src/mc.mc` and the whole `tests/*.mc` + `lib/*.mc` corpus,
     and `check-obj` 32/32 identical to `mc0`.
  2. **The host layer.** `src/host_windows.mc` (58) + `host_windows_{aarch64,x86_64}.mc` +
     `mc_windows{,_x86_64}.mc`, the Linux pair's shape. `lib/sys_windows_host.mc` (244, bundled
     as `sys_windows_host`, compiled into `mcrt.obj`) is the fifteen POSIX names the compiler
     declares `extern`, over kernel32: `posix_spawnp` (MSVCRT quoting, `STARTUPINFOA` 104 B and
     `PROCESS_INFORMATION` 24 B in `u8` arrays through `st*`/`ld*`, `CreateProcessA` with
     `lpApplicationName = 0` so PATH and `.exe` are searched for us), `waitpid`
     (`WaitForSingleObject` + `GetExitCodeProcess`, `(code & 255) << 8` — Windows has no signals,
     so the shape `drv_spawn` reads is exact), `mmap` over `VirtualAlloc` (`src/arena.mc`
     untouched: `arena_map` already rounds to 64 KiB, `VirtualAlloc`'s granularity),
     `mkdir`/`unlink`/`_exit`, `chmod` returning 0, and the three
     `posix_spawn_file_actions_*` stubs. `host_exe_suffix()` joined the host interface
     (`""` / `".exe"`) and `drv_teach` uses it at every site where `[compiler].out` names a
     BINARY. `lib/sys_windows_start.mc` passes 0 as `main`'s third argument.
     `scripts/sysroot-windows.sh`'s `.def` went from seven names to thirteen. Because
     `check-ast`/`check-asm` compile every `lib/*.mc` with the seed AND with `mc1` and compare,
     `lib/sys_windows_host.mc` carries a `// seed-skip:` header with the reason and both scripts
     report it — the same argument that put `tests/mc/` in a directory of its own.
  3. **The chain.** `src/mc.windows-{aarch64,x86_64}{,-obj}.toml`, `scripts/link-windows.sh`
     (105) and `scripts/bootstrap-windows.sh` (280). The sysroot holds all three files a link
     needs and the program does not provide — `kernel32.lib`, `winstart.obj`, `mcrt.obj` — because
     a literal `[linker].args` path is resolved against the working directory and not against the
     config. The Makefile's host switch is three-way (`WINHOST` is a `findstring` over
     MINGW/MSYS/CYGWIN), `REF`/`MC` become `build/mc1w.exe`/`build/mc2w.exe`, `check` is the
     subset `budget bootstrap-windows check-lex check-ast check-asm check-obj check-bundle
     check-mc check-toml check-limits check-skipped`, and every check script that had a Linux
     branch got a Windows one. `.gitattributes` with `* -text` (Decision 11).
  4. **CI and releases.** The macOS job cross-compiles the two COFF compiler objects and the two
     sysroots and uploads `mc-windows-hosts`; the jobs `mc on windows/arm64 host`
     (`windows-11-arm`) and `mc on windows/x86_64 host` (`windows-2025`) link, ask `--host`, run
     `make check SEED=…` and the cross proof against `build/mc2.o`. `core.autocrlf=false` before
     the checkout, `MSYS2_ARG_CONV_EXCL='*'`, `choco install make`. The M20 x64 suite leg moved to
     `windows-2025` (Decision 9). `release.yml`: `build-future-hosts` deleted, `build-windows`
     (a two-entry matrix) in its place, `publish` needs all three producers — **five** assets,
     `mc.exe` inside the two Windows tarballs (`scripts/release-assets.sh`).
  — `stage0/` untouched, 2848/3000; bundle 47 files (raw 552780 -> LZ 257678, blob 258262 B).
  `make check` green end to end on macOS; `make check-linux-host` green on both architectures
  (RC 0), 33/33 on linux/aarch64 and 30/30 on linux/x86_64 with `080-twelve-params` included;
  `make test-windows` 35/35 and `make test-windows-x86_64` 33/33 objects cross-compiled and
  linked here. Cross-built and LINKED on this Mac with `lld-link`, no undefined symbols:
  `build/mc-windows-arm64.exe` 542208 B (`IMAGE_FILE_MACHINE_ARM64`) and
  `build/mc-windows-x86_64.exe` 589312 B (`IMAGE_FILE_MACHINE_AMD64`).
  **Five goldens rewritten in one commit**, each only after its own criterion: `mc2.sha256`
  `6deafb02…ef3bad` -> `28550e3912ed5012a16b7d6e5bad5ba3032a90e66364ed1a0954653bb94fd4a8`
  (empty `--dump-asm` diff between mc1 and mc2, `cmp mc2.o mc3.o`, 676560 B); the two Linux ones
  deleted and re-recorded by `make check-linux-host` —
  `mc2-linux-arm64.sha256` `113261108524194371c66e31257caa841ca01f9e396b4f53257e4a89a2fa5d78`,
  `mc2-linux-x86_64.sha256` `542893ebbd9f0da7f1ad4a77aeebb42e80884dc46f99a12d4956ce7781ea8934`;
  and the two NEW Windows ones computed on macOS as the SHA-256 of the cross-compiled object,
  which is by construction the object the Windows-hosted compiler must write —
  `mc2-windows-arm64.sha256` `b652e5d5db7177ee9b34938ba6400342c1479ffee86cdc3bbc60c1440e0d75ef`
  (689869 B), `mc2-windows-x86_64.sha256`
  `db21c424ebb68e8805ad8229f1e493377fd25e626c9b7609df762cfef467e4c6` (708729 B), and `build/mc2`
  produces both byte for byte as `build/mc1` does.
  **What only the Windows runners can prove**: that the kernel32 shims BEHAVE — a spawn, a wait,
  an exit code, a `VirtualAlloc`ed arena — and therefore the fixed point, the suite and the cross
  proof on a real Windows machine. Nothing Windows executes on this Mac.
- M39 done (`docs/specs/M39.md`, `docs/guide/97-a-new-architecture.md`): **an architecture taught
  from the surface** -- `examples/kernel`, a bare-metal RISC-V 64 micro-kernel compiled by a taught
  compiler and booted under QEMU. **`git diff --stat src/ stage0/ lib/ tests/` is empty**: that is
  the milestone. Everything is under `examples/kernel/` (2563 lines):
  `machine_riscv64.mc` (780) fills the same 31 slots `src/machine_arm64.mc` and
  `src/machine_x86_64.mc` fill -- depths 0..3 in `t3..t6`, scratch `t0`/`t1` and `t2` reserved for
  address materialisation, arguments `a0..a7` with 9..12 at `[s0 + 16 + 8*(i-8)]`, locals at
  `[s0 - off]`, an epilogue that starts with `mv sp, s0` and is therefore NEVER patched, and two
  module-private relocation kinds (32, 33) each carried by ONE fused 8-byte `Ins`
  (`auipc`+`addi`, `auipc`+`jalr`) so the walker's one-relocation-per-instruction rule is not bent
  (D4). Addressing is pc-relative because `lui t2, 0x80000` sign-extends to
  `0xFFFFFFFF80000000`, which is wrong at exactly the base a `virt` board loads at (D3).
  RV's store displacement is a SIGNED 12-bit field (2047) against the walker's 4095, so the
  MACHINE pays (G7): above 2047 the offset goes through `t2`, which is what makes `V_ADDI`, the
  eight memory forms and the frame reserve variable-length and what makes running the real encoder
  for `MTASK_INS_SIZE` mandatory. `image.mc` (246) is `backend("rv-image", ...)`: sections placed
  from `IMG_BASE 0x80000000` in creation order, bss past the file, every symbol rebased, the three
  relocation kinds resolved in place, six symbols synthesized (`_bss_start`/`_bss_end`/
  `_data_start`/`_data_end`/`_data_lma`/`_stack_top`) and raw bytes out -- no header, no
  signature. `kernel_syntax.mc` (117) teaches `mmio` / `csrw` / `csrr(...)` / `yield`.
  `lib/sys_bare.mc` (148), `lib/trap.mc` (95), `lib/sched.mc` (90), `main.mc` (90),
  `tests/sweep.mc` (177), `mc-kernel.mc` (30), `mc.toml` (62), `test.sh` (502), `README.md` (226).
  **Two deviations from the spec's sketch, both on record.** (1) The reset stub is
  `li sp, _stack_top` + `j _start`, padded to a fixed 32 bytes, not `jal x0, _start` alone: a
  RISC-V hart comes out of reset with every register zero and the compiler's frame record is
  unconditional, so `_start`'s own `sd ra, 8(sp)` would fault on the kernel's first instruction.
  (2) **The context switch is TWO instructions, not the ~25 the spec priced** -- `sd s0, 0(a0)` +
  `ld s0, 0(a1)` -- because `s1..s11` are never written, `ra`/`s0` are already on the suspended
  task's stack (the unconditional record), and `sp` is derived from `s0` by the epilogue. It was
  written and QEMU-tested FIRST, by hand in assembler, before the machine existed (risk 4).
  Proof: `boot / trap / t0 t1 x5 / ok`, **exit 0**, and the same kernel with `halt(42)` **exit 42**
  (QEMU 11.0.1 here, 8.2.2 on `ubuntu-latest`); two builds `cmp`-identical; the default compiler
  refuses both halves (`unknown backend: rv-image`, `type expected at top level`); seven ABI
  assertions over `--dump-asm --machine=riscv64` (25 functions, 0 mentions of `s1..s11`/`gp`/`tp`
  in 751 lines); the llvm-mc sweep -- **234 + 262 + 1057 distinct instructions re-assembled byte
  for byte, 0 mismatches**, and 58 + 34 + 34 pc-relative pairs plus 51 + 53 + 3253 branches checked
  against a placement recomputed independently from `--dump-syms`, 0 wrong. `make check-kernel` is
  inside `make check` and self-skips without QEMU; the `baremetal-riscv64` CI leg on
  `ubuntu-latest` boots the image the macOS job uploads.
  Gaps priced and NOT taken: G1 (`mc build` cannot drive a bare target -- `[target]` is resolved
  before `user_init()`; deferred to M39.5), G2 (`reloc()`'s four hard-coded kinds), G3 (a second
  relocation per instruction, which `linux/riscv64` ELF would need), G7 (kept in the machine on
  purpose). G9 taken as documentation only (D7): `docs/reference/hooks.md`'s recipe told a module
  to call `machine_task`, which writes `m_arm64` BY NAME -- corrected, along with "Four are
  registered" -> five.
  Post-M39 review, two confirmed findings, both fixed inside `examples/kernel/` (`src/`, `lib/`,
  `tests/` and `stage0/` still untouched -- acceptance 11 holds).
  1. **A jump the machine could not encode was truncated, not refused.** `rv_put_j` masks its
     argument into `jal`'s SIGNED 21-bit field, and `V_J` plus the `jal` half of the `V_JZ`/`V_JNZ`
     pair handed it `target - pc` unchecked -- so a jump past 1 MiB came out silently wrong, the
     one class `src/machine_arm64.mc` spends `br_off` (`branch too far`) on and the one class no
     later gate catches. `rv_jal_off(target, pc, real)` (+13 lines in
     `examples/kernel/machine_riscv64.mc`) dies with `riscv jal out of range`; `real` is
     `lab != 0`, so only the ENCODE pass checks -- `MTASK_INS_SIZE` measures with no label vector
     and both forms are fixed width. Reproduced first: one `if` over 40 000 statements (1.4 MiB of
     code) built a 1442680-byte image whose jump disassembles as `j -657148` where the target is
     +1440004, and QEMU stopped it with `unexpected trap, mcause=2`, exit 2; with the guard the
     same source is `mc: riscv jal out of range`, exit 1. `build/kernel.bin` is byte-identical
     before and after (`cmp`), and still boots to `ok`, exit 0. `test.sh` step 6b asserts it (the
     source generated with `awk`, 0.7 s), and fails with the pre-fix compiler.
  2. **`test.sh`'s `mc limits` step accepted exit 3 as a pass.** Exit 3 is M23's code for "a table
     grew OR is tight", so the one automated check of acceptance 9 could not fail. It is now two
     phases, the shape M23 recorded for `examples/api`: **cold**, where the COMPILER half must show
     no `grew` line (that is what `[limits] tolerance = 1.0` buys) and the exit code must be 0 or
     3; then `mc build` to record the usage, and **remembered**, where both halves must be exit 0
     with `grow 0` in every table. Verified to fail on both paths by setting `tolerance = 0.0`.
     On record, because acceptance 9's literal "grow 0" holds only in the remembered form: the
     ENTRY half's static estimate is a function of source BYTES, and `main.mc` is 90 lines whose
     taught words and `#rule` prelude expand into about five times the nodes those bytes predict
     (nodes 401 estimated, 1914 used) -- a factor no tolerance in `[0, 1]` covers.
     `examples/kernel/mc.toml`, `examples/kernel/README.md` § Limits and `docs/build.md` § M39 all
     say so now instead of "at 1.0 nothing grows".
  -- `stage0/` untouched, 2846/3000; goldens NOT rewritten (`src/` untouched, so nothing can
  move); `make bundle` not needed (`lib/` untouched). Docs: `docs/guide/97-a-new-architecture.md`
  (new), `docs/reference/machine.md` (the riscv64 column, the third division answer, the G7
  obligation, and -- from the review -- the jump-range row and the rule that a machine whose field
  is too small says so with a diagnostic), `docs/reference/hooks.md` (the two corrections),
  `docs/build.md` § M39, `docs/surface.md`, `docs/README.md`, `docs/ci.md`,
  `examples/kernel/README.md`.
- M39.5 done (`docs/specs/M39.md` § Gaps G1, decision D2): **`mc build` with a module-registered
  `[target]`** -- the deferral form and nothing else. `drv_run` keeps `[target].os`/`.arch` as the
  strings the file wrote (`drv_os`/`drv_arch`) and no longer consults the registry; `drv_entry`
  passes a ROLE (`DRV_ROLE_OBJ` / `DRV_ROLE_EXE`) where it used to pass
  `drv_obj_backend()`/`drv_exe_backend()`; and `drv_backend_for(role)` resolves the pair inside
  `drv_parse`, **after `user_init()`** (so a target a module registered counts) and **before
  `parse_unit()`** (so an unknown pair is still reported ahead of anything wrong in the source).
  The two diagnostics stay built from the registry and the
  `<os> requires [linker]: there is no direct executable` check moved with them, all three
  byte-identical; `drv_teach`'s independent lookup of the HOST pair is untouched; there is no
  second user entry point (`mc` has no weak definitions -- a `user_targets()` would break every
  taught compiler until it grew an empty body).
  Cost in `src/`: **18 added / 15 removed code lines** in `src/driver.mc` (41/15 with comments) --
  the spec priced ~25.
  One behavioural consequence, on record in `docs/reference/diagnostics.md`: an unknown `[target]`
  is now reported after the entry has been opened and lexed, so the `compile x -> y` step line
  comes first. `scripts/check-build.sh` already asserted the LAST line of output, so the three
  `[target]` messages did not move; what had to change is where those three diag configs live
  (`tests/proj/build/d.toml`, `entry = "../app.mc"`) so the entry exists -- with an unopenable
  entry the first error would now be `cannot open`. 16/16 checks, messages unchanged.
  `examples/kernel` is the consumer, and G1 was the only thing standing between it and `mc build`:
  `mc.toml` gained `[target] os = "none" / arch = "riscv64"` with `entry = "main.mc"`,
  `out = "build/kernel.bin"`, `kind = "exe"`; `mc-kernel.mc`'s `user_init` gained
  `target("none", "riscv64", "rv-image", "rv-image")` -- `rv-image` in **both** roles because a
  bare board has no separable object step, and in the EXE slot so `kind = "exe"` needs no
  `[linker]`. `mc build examples/kernel` is now the whole build (compiler, then the spawned child
  with `--entry-only`), and the image it writes is **byte for byte** the one the single-file CLI
  wrote before the change (3304 bytes, `cmp` against a copy taken from the pre-M39.5 tree);
  `test.sh` asserts that equality on every run and gained a fourth refusal case
  (`mc1 build examples/kernel --entry-only` -> `only macos, linux and windows (see
  docs/build.md): target.os`). `.github/workflows/ci.yml`'s "Build the bare-metal RISC-V images"
  step is `build/mc1 build examples/kernel`; the halt(42) variant keeps the single-file CLI,
  since it is not `[project].entry`.
  Inertness (the M17-step-A protocol): a copy of `build/mc1` taken BEFORE the change writes
  byte-identical objects for all 32 `tests/*.mc` **and for `src/mc.mc` itself**, and -- through
  the taught compilers each of them builds -- byte-identical artefacts for `examples/api`
  (55632 B), `examples/lang` (35350 B), `examples/conc` (54342 B) and `examples/desktop`
  (37444 B). Nothing the compiler emits moved; the goldens moved only because `src/driver.mc` and
  the bundle did.
  -- `stage0/` untouched, 2848/3000; `make bundle` re-run before bootstrapping (`src/driver.mc` is
  bundled as `mc/driver`). `make check` green end to end (RC 0): `test` 32/32, `check-lex`/
  `check-ast`/`check-asm` (92/92, 91/91, 91/91 files), `check-obj` **32/32** against the frozen
  seed, `check-bundle`, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 749344 bytes; the
  `--dump-asm` diff between `mc1` and `mc2` is **empty**), `check-surface` 32/32, `test-exe`
  32/32, `check-mc` 7/7, `check-standalone`, `check-toml` 10/10, `check-build` **16/16**,
  `check-stubs` 9/9, `check-limits` 17/17 under 90%, `test-linux` 33/33, `test-linux-x86_64`
  30/30, `test-windows` 35/35 + 33/33 cross-compiled, `check-examples`, `check-lang`,
  `check-conc`, `check-desktop`, **`check-kernel` OK (0 skipped)** -- QEMU 11.0.1 prints the exact
  transcript and exit 0, `halt(42)` gives exit 42 -- `check-docs` (144 symbols, 18 flags, 17 TOML
  keys, 10 directives, 47 samples, 220 links), `site` + `check-site`.
  The five goldens rewritten **once**, in the same commit, only after the empty `--dump-asm` diff
  and `cmp build/mc2.o build/mc3.o`: `mc2.sha256`
  `92b04f72...82f903` -> `5836c1fd132a57fad34e9883b1749c47256ef01f33e75c5d4ffb4e66c61c0344`, the
  Linux pair re-recorded by `make check-linux-host` (Docker, both arches, each after its own fixed
  point) and the Windows pair cross-computed per `tests/golden/README.md`.
  Docs: `docs/build.md` § M39 / M39.5 (rewritten), `docs/reference/toml.md` § `[target]`
  ("a pair the compiler or one of its modules registered"), `docs/reference/diagnostics.md`,
  `docs/guide/97-a-new-architecture.md` (four registrations now, and the gap removed from "what
  this does not buy yet"), `examples/kernel/README.md` + `mc.toml`, `docs/specs/M39.md` (G1 marked
  taken, with the real line count).
- Post-M39.5 batch (review): the two findings the PR review raised, both confirmed by reading and
  both about a backend slot a module can leave at 0. Only `src/driver.mc` changed (+35/-6, 12 of
  them code).
  1. **`drv_backend_for(DRV_ROLE_OBJ)` handed a null to `backend_find`.** `target(os, arch, 0,
     exe)` is a legitimate registration -- it is what a board whose flat image IS the artefact
     writes -- and asking such a target for an object (`kind = "obj"`, or `kind = "exe"` with a
     `[linker]`, which goes through the object step) returned `tgt_obj_at() == 0` unchecked;
     `backend_find` compares that against every registered name with `str_eq` and dereferenced it.
     Reproduced on the pre-fix compiler: the spawned child died of **SIGSEGV (exit 139)** with the
     `compile app.mc -> build/app-toy.o` step line as its last word, and `mc build` reported
     nothing but exit 1. Now `toy/toy has no object backend: use kind = "exe"` through
     `toml_err_key("target.os", ...)`, at the value's own position and exit 1 -- the mirror of the
     `<os> requires [linker]: there is no direct executable` message the empty EXE slot has always
     had.
  2. **`mc sysroot stub` never resolved `[target]`.** That path reaches `drv_parse` directly
     (`src/sysroot.mc`), not through `drv_compile`, so `drv_bname` was never one of the M39.5 role
     markers and the resolution inside `drv_parse` was skipped: a foreign `[target].os` came out
     of the stub writer as `mc: no stub writer for: haiku: a static libc is code, not a name list`
     and an unregistered arch was not diagnosed at all. A third marker, **`DRV_ROLE_NONE`**, is
     set on that path: `drv_backend_for` runs the two registry checks and returns 0 without
     touching a slot -- deliberately not `DRV_ROLE_OBJ`, since a `.tbd`/`.def` needs the os and
     the arch and never a backend, so a target with no object backend still stubs. `mc sysroot
     stub` and `mc build` now print the same message, same `file:line:col`, same exit 1, checked
     side by side.
  Proofs, all in `scripts/check-build.sh` (16/16 -> **21/21**): `tests/proj/noobj.mc` is the whole
  taught compiler (`target("toy", "toy", 0, "macho-exe")`, the only way to get a 0 into a slot,
  since every target `src/main.mc` registers has an object backend), `noobj.toml` asserts the new
  message as the exact last line (`tests/proj/noobj.toml:19:8: toy/toy has no object backend: use
  kind = "exe": target.os`), `toy.toml` is the same project with the fix the message names --
  `kind = "exe"`, built through the taught target and RUN, so the advice is proved and not
  asserted -- plus a `[target].arch` diagnostic in build mode and the two `sysroot stub` ones. The
  `diag` helper gained one variable (`diag_cmd`) so both subcommands go through the same
  assertion. `check-stubs` stays 9/9: the `no stub writer for: linux` case is a REGISTERED target
  and reaches the writer exactly as before.
  Docs: `docs/reference/diagnostics.md` (the new row, plus the note that `mc sysroot stub` runs
  the same resolution -- and the § 10 table, split in two by M39.5's paragraph, put back together),
  `docs/reference/hooks.md` § `target()` (what a 0 in EITHER slot means; the stale "`mc build`
  will not reach it yet" paragraph, which M39.5 had already made false, rewritten),
  `docs/reference/toml.md` § `[target]`, `docs/reference/sysroot.md` § 7, `docs/build.md`
  § M39 / M39.5, `docs/specs/M39.md` § G1.
  -- `stage0/` untouched, 2848/3000; `make bundle` re-run (`src/driver.mc` is bundled as
  `mc/driver`): 50 files, raw 616002 -> LZ 286592, blob 287208 B. `make check` green end to end
  (RC 0, zero FAIL, 3m54s): `test` 32/32, `check-lex` 92/92, `check-ast` 91/91, `check-asm` 91/91,
  `check-obj` 32/32 against the frozen seed, `check-bundle` (reproducible + fresh), `bootstrap` at
  a fixed point (`mc2.o == mc3.o`, 750704 bytes; the `--dump-asm` diff between `mc1` and `mc2` is
  **empty**), `check-surface` 32/32 + inert, `test-exe` 32/32, `check-mc` 7/7, `check-standalone`,
  `check-toml` 10/10, **`check-build` 21/21**, `check-stubs` 9/9, `check-sysroots` (13 rows),
  `check-limits` **17/17 under 90%** (the tightest is `globals` 330/512 = 64%),
  `check-minimal`, `test-linux` 33/33, `test-linux-x86_64` 30/30, `test-windows` 35/35 +
  33/33 cross-compiled,
  `check-examples`, `check-lang` 14, `check-conc` 21, `check-desktop`, `check-kernel`
  (`mc build examples/kernel` -> 3304 B, QEMU 11.0.1 transcript and exit 0),
  `check-docs` (144 symbols, 18 flags, 17 TOML keys, 10 directives, 47 samples, 224 links),
  `site` + `check-site` (77 files, 0 problems; 50 contrast pairs, 0 below the minimum).
  The five goldens rewritten **once more**, superseding the values in the entry above, only after
  the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`: `mc2.sha256`
  `5836c1fd...c0344` -> `d73a2861da0233e9c99b17ab3ace4104a97d21f0113f08251be024d4e849b79b`, the
  Linux pair re-recorded by `make check-linux-host` (Docker, both arches, each after its own fixed
  point) and the Windows pair cross-computed per `tests/golden/README.md`.
- M43 step B ✔ (`docs/specs/M43.md` § Implementation notes -- step B, ten numbered kernel
  corrections): **the box and the supervisor, without seccomp/Landlock (step C).**
  `src/sandbox_box.mc` (440) and `src/sandbox.mc` (1280); `scripts/test-sandbox.sh`;
  `tests/sandbox/*.mc` (clean, forever, sleeper, eightgib, shadow, connect, forkbomb, rocwd).
  What the kernel decided: **four processes, not three** -- P (supervisor), I (unshares the six
  namespaces, builds the tree, `pivot_root`s), **J** (pid 1 of the pid namespace, runs one C per
  step: an init that exits accepts no new process, and a second `unshare(CLONE_NEWPID)` is EINVAL),
  C (the step). Maps: `0 <uid> 1` unprivileged and **`0 0 65536`** for root, no `setuid` -- `0 65534
  1` alone left the caller unmapped (`mkdirat` EOVERFLOW) and `+ 1 0 1` broke overlay copy-up on a
  root-owned lower (the inode owner must be mapped; `CAP_DAC_OVERRIDE` does not help); the cost is
  that `RLIMIT_NPROC` does not bind for root (`copy_process` exempts `INIT_USER`), documented with
  "run it unprivileged" as the answer. Overlay needs `userxattr` inside a user namespace, and it
  mounts on virtiofs (Lima) and ext4 (VPS), root and unprivileged -- the priced ro-`/src` + `/out`
  fallback is implemented and no cell reached it. `RLIMIT_AS`/`NPROC`/`STACK` are set by C right
  before `execve` (in I they would cap the box's own arena and refuse its own fork); the compile
  step gets `NPROC 16` because `mc build` spawns the compiler it taught. Soft = hard `RLIMIT_CPU`
  is SIGKILL, not SIGXCPU, and rusage lands a shade under the cap (1.997 s for 2), so J's cpu
  verdict carries 100 ms of slack; the wall-clock line is P's because killing J kills the reporter.
  Two options the corpus forced: `--root DIR` (with `/src` at the source's own directory,
  `#include "../lib/sys.mc"` resolved to `/lib/sys.mc` -- nine tests) and `--config NAME`
  (`examples/lang` needs `mc.linux.toml`/`mc.linux-gnu.toml` without `[target]`); `--report FILE`
  writes the file AND stderr. **Globals: 422/512** -- one global (`sb_state`, an arena record with
  `SB_*` accessors) for the whole milestone; step A's sixteen became the record.
  Measured (Ubuntu 26.04, 7.0.0-30, Lima aarch64 + VPS x86_64, root and unprivileged; plus
  `alpine:3 --privileged` on 6.12): isolation cases 8/8 in every cell, the suite 31/31 and 29/29
  through `mc sandbox run` with identical exit/stdout, `mc sandbox exec` on static AND dynamic
  M42 binaries with only `/lib` bound, `examples/lang` taught and run inside (`13 25 12 box`),
  host tree untouched; `clean.mc` byte-identical to the unsandboxed run; `forever.mc` `killed: cpu
  limit (2 s)` exit 124 at 2.006 s; `sleeper.mc` `killed: wall clock (5 s)` exit 124 at 5.01 s;
  `eightgib.mc`'s `malloc(8 GiB)` returns 0 under `RLIMIT_AS`; `shadow.mc` gets ENOENT (`/etc` does
  not exist -- the NAMED `refused: open` is step C's); `connect.mc` ENETUNREACH from the empty
  netns; `forkbomb.mc` `forked 0` unprivileged (EAGAIN on the first clone) and 200 as root;
  unprivileged with the stock sysctl: `sandbox: cannot mount /: EACCES (apparmor restricts
  unprivileged user namespaces: ...)`, exit 126. **Overhead per box: 1.37/1.43 ms aarch64,
  4.12/4.98 ms x86_64** (root/unprivileged). Reports deterministic (`cmp` equal, no digit run >= 4),
  no `/tmp/.mc-box*` left, `find -newer` empty outside `build/`.
  -- `stage0/`, `lib/`, `tests/*.mc` untouched; bundle 84 files (blob 454822 B); `make check` RC 0
  with `test-sandbox` 49 ok / 1 skipped inside it (delegating to Lima from macOS); `check-obj`
  32/32; fixed point 1050240 B; `check-limits` 17/17; four Linux cells RC 0; `check-inert`
  identical everywhere. Goldens rewritten once: `mc2.sha256`
  `675d62a48b1ca5d1f04649a2b88aa151da8fec53654dcd5ea3e0790ffe1ef0fd`, Linux `bee69954…46dea4` /
  `97c888a8…7251ca`, Windows `edd2d619…e0776` / `08a6d675…6e0a`. Not yet: the CI job (acceptance
  10), exit 125 and every `refused:` line (step C).
- M43 step C ✔ (`docs/specs/M43.md` § Implementation notes -- step C, fourteen kernel/libc facts):
  **the two walls and the explain channel.** `src/seccomp.mc` (600): the BPF builder
  (`ld[arch]`/`jeq host_audit_arch()` -- a new host-layer answer, not a constant -- `/ld[nr]/jge
  0x40000000 -> KILL (x32)/one JEQ per profile entry/the clone flag block/ret USER_NOTIF`),
  Landlock with the ABI probed at runtime (**abi 8** measured, floor 4; masks per level, 12-byte
  packed `path_beneath`, O_PATH fds; a rule on a FILE may not carry `READ_DIR`, EINVAL), installed
  by C in the marked spot: Landlock, the per-step rlimits, then seccomp with `NEW_LISTENER`.
  **The listener road, decided by measurement**: two `pidfd_getfd` hops (C -> J -> P), because C's
  pid is a number in the box's namespace that P only learns from the first notification; Yama
  `ptrace_scope` = 1 on both hosts and both hops are parent -> descendant, same uid. The explain
  channel in P (`src/sandbox.mc` +180): `ppoll` over status pipe + listener, `NOTIF_RECV`/`SEND`/
  `ID_VALID`, `process_vm_readv` page by page; the § 4 table plus `fork`/`vfork` in the
  process-creating set; `sn_names[]` in `src/sysno.mc` indexed by the same `SN_*` as the number
  table (one table, two columns). **A refused call is killed and NOT answered** (deviation from
  § 4): answering woke the step and `shadow errno=13`/`socket refused` appeared on some runs only.
  **Profiles measured, not written**: `scripts/sandbox-trace.sh` (386) with `strace -fc` OUTSIDE the
  box (tracing the box records `unshare`/`mount`/`pivot_root`, and once a filter exists the
  measurement is circular), `tools/sandbox/*.list` (12), `src/sandbox_profiles.mc` (198, generated,
  in `SN_*` terms): compile musl 18/19, glibc +8/+7; program musl 16/17, glibc +9/+9; threads
  delta 5 (aarch64/x86_64). `--check` green on four cells both ways and exit 1 on a deliberate extra
  entry. `strace -c` DROPS `exit_group` -- a profile without it refuses every program at its last
  instruction. musl on x86_64 forks with `fork` (57). glibc's loader needs `/etc/ld.so.cache`
  bound AND granted by Landlock, else its fallback path hits `madvise` (aarch64, 1 run in 12) or
  `newfstatat` (x86_64, every dynamic program, probing `glibc-hwcaps/x86-64-v4/`). The process cap
  needs `RLIMIT_NPROC` (128) looser than P's counter (64) or the kernel's EAGAIN wins. Unprivileged
  copy-up needs owner AND group mapped.
  Acceptance 2, every line, per cell (Lima aarch64 root+unprivileged, VPS x86_64 root+unprivileged,
  x86_64 glibc by hand): `refused: open /etc/shadow` -- **before the kernel answers ENOENT**, the
  notification fires on `openat` entry (the step-B compiler prints `shadow errno=2` on the same
  source); `refused: syscall 198 (socket)` / `41`; `refused: syscall 220 (clone)` / `57 (fork)`
  musl / `56 (clone)` glibc; `refused: process limit (64)` with `--allow=threads`; `refused: mmap
  8589934592 bytes over the cap (268435456)`; all exit 125; `killed:` lines unchanged (124);
  `clean.mc` byte-identical with the program profile installed. Host process count and available
  memory unchanged, asserted by the script. Suites 31/31 and 29/29 through the box, `exec` 2/2
  incl. a `PT_INTERP` binary, `examples/lang` inside with **`compile: execve 2`** (`mc build` execs
  the compiler it wrote, which compiles the entry in-process; 3 kept as the ceiling). Five cells
  **52/52/50/50/50 ok, 0 failed**. Overhead with the filter: 1916 us vs 1619 us per box on aarch64
  (**+297 us, +21%**); on the VPS inside the noise.
  -- `stage0/`, `lib/`, `tests/*.mc` untouched; bundle 86 files (blob 478358 B); `make check` RC 0
  (`check-lex`/`ast`/`asm` 134/134, `check-obj` 32/32, fixed point 1099928 B, `check-limits` 17/17
  with **globals 432/512**, `test-sandbox` 52 ok / 1 skipped); four Linux cells RC 0; `check-inert`
  identical everywhere. Goldens rewritten once: `mc2.sha256`
  `bb48b0b27df913fcaa54b60a59da3a0e9c3cf219d0f474f731adb7b9b7bf6075`, Linux `394ce144…34579` /
  `8c9c7fab…167c17`, Windows `f2d9b228…ad4ff6` / `3596c00b…15e98e`. Not yet: the CI job
  (acceptance 10) and `docs/guide/99-sandbox.md` (step D).
- M43 step D ✔ (`docs/specs/M43.md` § Implementation notes -- step D): **the CI job, the guide,
  the last acceptance items.** Two jobs in `.github/workflows/ci.yml`, `The sandbox (linux/arm64)`
  (`ubuntu-24.04-arm`) and `The sandbox (linux/x86_64)` (`ubuntu-latest`), `needs: check`: the
  macOS job cross-compiles FOUR executables (`mc-linux{,-x86_64}{,-gnu}`, `mc build` writes the
  dynamic ELF itself since M42) into `mc-linux-sandbox`; each job flips
  `kernel.apparmor_restrict_unprivileged_userns` both ways and asserts `mc sandbox check` in each
  state, runs the unprivileged cell and the root cell (`scripts/ci-sandbox-cell.sh`, 70 lines: a
  skip on a runner is a failure unless it is a test's own `// skip-linux:` header, and `0 failed`
  is required), `scripts/sandbox-trace.sh --check` with `strace`, and `docker run` WITHOUT
  `--privileged` (`userns: EPERM`, `run` -> `cannot unshare: EPERM`, exit 126). Both contexts go
  into the required checks after the merge (`docs/ci.md` § Branch protection).
  **The runners' answers** (kernel `6.17.0-1022-azure`, glibc 2.39, Landlock **abi 7**): sysctl = 1
  -> `userns: restricted (apparmor)` exit 1; sysctl = 0 -> `userns: ok` **exit 0** -- the cell no
  local oracle could measure. Suites 52/50 ok, 0 failed, per cell; box cost ~2.1-2.2 ms.
  **Two defects only CI could find**, both fixed here: (1) a profile is a UNION over glibc versions
  (2.39 needs `rt_sigaction` and `clone`) -- `sandbox-trace.sh` gained `--union`/`--strict`, and
  `--check` fails only on "the trace has a call the table lacks", reporting the reverse as `note`;
  (2) **`lex_readable` (`src/lex.mc`) was the one `open` in `src/` without `c_int()`** (an M45 D8
  miss): on a glibc host a failing `open` returns `0x00000000ffffffff`, so every missing file was
  "readable" and `mc build` on a fresh tree died with `cannot open: build/.mc-usage.toml`; it also
  affected `[include].paths`. One line.
  `docs/guide/99-sandbox.md` (205 lines, 2 samples compiled and not run, with the reason on the
  page); `docs/reference/sandbox.md` complete (the four CI cells in § Hosts, the union rule, the
  Docker-Desktop `fakeowner` finding); `check-parts` gained acceptance 9's second half (a compiler
  without `<mc/core_sandbox>` prints no `sandbox` usage line and refuses `mc sandbox` as
  `cannot open: sandbox`). Oracles cleaned (VPS `/root/m43`, `mcbox` user, Lima `/tmp`; sysctl
  back to 1 on both).
  -- `stage0/`, `lib/`, `tests/*.mc` untouched; bundle 86 files (blob 478867 B); `make check` RC 0
  (`check-lex`/`ast`/`asm` 134/134, `check-obj` 32/32, fixed point 1100464 B, empty `--dump-asm`
  diff, `check-limits` 17/17, `test-sandbox` 52 ok / 1 skipped, `check-docs` 192 symbols / 33 flags
  / 50 samples / 318 links, site 87 pages); four Linux cells RC 0; `check-inert` against a `mc1`
  from 3966268 identical everywhere. Goldens rewritten (twice in this step: the union, then the
  `lex.mc` line), final: `mc2.sha256`
  `f8b05c08c9f06a14ba17ae3f329f240396ff5dc2473c07c445a4013feba173e1`, Linux `d8bdbeeb…da6b59` /
  `ed7c7f61…fd08dd`, Windows `4de1c3c9…d48cf3` / `7da0aa71…1c0d01`. Draft PR #23: three CI
  rounds, the last two **14/14 green**.
- M43 review batch ✔ (`docs/specs/M43.md` § Implementation notes -- the review): the security
  review's HIGH finding, **reproduced before it was fixed**. The COMPILE profile listed `clone`
  (and `clone3` in the glibc variant) as a plain ALLOW -- the arg-checked clone block was emitted
  only under `--allow=threads` -- so a program reachable from an untrusted tree (`mc build` runs
  `[linker].cmd` from the source's own `mc.toml`: `/src/bomb`, `PATH=/`, `/src` writable and
  executable) forked freely with no `refused:` line: `forked 12` unprivileged, `forked 200` as
  root, and `nsclone.mc` created a USER NAMESPACE inside the box (`cloned 4`). Rule now: **a
  process-creating call is never a plain ALLOW in any profile** -- `clone`/`clone3`/`fork`/`vfork`
  always reach P (`sb_notified`), any `CLONE_NEW*` bit is `refused: clone with namespace flags`
  (for `clone3` the first u64 of `clone_args` read with `process_vm_readv`; unreadable ->
  `refused: clone3 with unreadable arguments`), the rest counted per step -- compile **16**, run
  0, `--allow=threads` 64 -- as `refused: process limit (N)`; `RLIMIT_NPROC` stays the second
  wall (compile 32, so the named one wins). The generated profiles say
  `// SN_CLONE  notified, never allowed`. New cases `tests/sandbox/linkbomb/` (the hostile
  `mc.toml`), `nsclone.mc`, `nsclone3.mc`; `forkbomb.mc`'s three per-libc headers collapsed into
  one line. LOW: `sb_num` stops at 10^12 with maxima 86400 s / 1048576 MiB / 65536 MiB and minimum
  1 (`--mem 0` used to SIGSEGV the compile step). INFO: `landlock: abi N (no scoped signals below
  6)`. The docs' "compile-step forks" residual paragraph is gone because it is no longer true.
  Measured: Lima aarch64 glibc root+unprivileged 55/55, VPS x86_64 musl root+unprivileged 53/53,
  x86_64 glibc by hand, CI four cells 55/55 x2 + 53/53 x2; host process count 134 -> 134 in every
  case; `sandbox-trace.sh --check` green everywhere. `make check` RC 0, `check-obj` 32/32,
  `check-inert` identical, four Linux cells RC 0; goldens rewritten once: `mc2.sha256`
  `9e7b803f127cb6f1e059c1e6572a629bfa909cfbecbfae18b01abd1fd7a2d431`, Linux `182a4c6d…036679` /
  `e63d09bc…d99ffa`, Windows `dcaac914…4256c3` / `dfaf002c…a97b861`. PR #23 CI 14/14.
- M44 step 2 ✔ (`docs/specs/M44.md` § Implementation notes -- step 2; Amendment § A1-A3, A5, A6,
  D1'/D2'/D10'/D24): **angle brackets are libraries, quotes are my files.** `tok_add(".", 1)`
  appended LAST in `tok_init` (no id moves; `examples/lang`'s own `tok_add(".")` lands on the same
  id); `lex_include_name` is three steps through two pointers -- the lock road (`lopen_fn`,
  `lex_set_libs` from `mc_build_init()`), the bundle (`bopen_fn`, unchanged), the installed `mc`
  package (`<libs>/mc/v<mc_version()>/` + the `bundle.list` map) -- a trailing `.mc` stripped from
  every `<...>` name, `<pack>` alone = the lock row's `lib`, the once-only key for a disk-served
  name its NORMALISED path (no `getcwd` here), never the working directory, never an unlocked
  directory; `lex_root_of` + the edge list + the closure test for `#include` and `#embed`.
  `src/deps.mc` (662): the name rule and the reserved set (`mc`, `mc/...`, `deps`, `build`),
  `[deps]`/`[replace]`/`[registry]`, the lock READER, the tree hash, `libs_open` (vendored
  `deps/<pack>/` wins, then `<libs>/<pack>/v<version>/`), semver, the refusals (`mc.lock is stale`
  with the M25 `run:` block, `<pack> <ver>: <file> does not match mc.lock`, `is not fetched`,
  and -- vendored trees have no manifest for per-file attribution -- `the tree does not match
  mc.lock`). `src/toml.mc` re-entrant (`toml_push`/`toml_pop`, `toml_occurrences`);
  `src/driver.mc` `--libs-dir` (default `host_home()/.mc/libs`), `drv_apply_deps` for both halves,
  `<...>` modules verbatim. Cost **999 added lines in `src/`, 677 code** (spec ~543); globals
  432 -> **439/512**. **What did not survive**: `check-lex` cannot stay 100% -- `--dump-tokens`
  processes no directive, so `lib/syntax_demo_test.mc`'s taught `.+` operator now lexes `.` `+` where the
  seed says `unexpected character` (M44 risk 17, measured); a new `// lex-skip:` header (NOT
  `seed-skip:`, which `check-asm`/`check-ast` also honour and which would have dropped the file from
  two gates that still compare it byte for byte) -- 135/135 identical, 3 skipped. Two silent path
  bugs only a fixture found: `path_norm` drops a trailing slash and macOS `TMPDIR` ends in `/`, so
  every package root was a prefix of nothing and the closure rule never fired -- `dp_set_dir`
  normalises once. Fixtures `tests/pkg/` (mathx 1.0.0, geo 1.2.0, teach, bad, float 1.3.0, app,
  app-float, `nobundle.mc` = every part but `<mc/core_bundle>`, which is what `mc-slim` will be);
  `scripts/check-pkg.sh` **31/31** inside `make check`, under a `curl`/`wget`/`tar` shim that exits
  97 if invoked: acceptance 5-11, 18, 19 measured as the spec spells them, and step 3 of A3 --
  `<mc/host>` + `<mc/core>` + `<user_default>` served from a hand-laid `<libs>/mc/v0.0.0-dev/`
  compiles to an object `cmp`-identical to `build/mc1 src/mc.mc`. `make check` RC 0 (`check-obj`
  32/32, `check-ast`/`asm` 137/137, fixed point 1154264 B, `check-docs` 196 symbols / 35 flags /
  24 TOML keys / 349 links), four Linux cells RC 0, `check-inert` identical everywhere (D24: no
  `[deps]`, no change). Goldens rewritten once (after the rebase onto 167d540 re-recorded step 1's):
  `mc2.sha256` `9e00398d7338ad9b53654c7f07e0d16ff21319e79c915b2ac473d20e1411420a`, Linux
  `67f062a4…7a02fd` / `3c93e81f…debe70`, Windows `2858b236…3f5959` / `c75e23fd…b909322`.
- M44 step 3 ✔ (`docs/specs/M44.md` § Implementation notes -- step 3; draft § 4-§ 8, D21): **the
  write and network side.** `src/fetch.mc` (169): `fetch_get` (an `https://` source spawns the
  host downloader with M25's flags, anything else is a LOCAL PATH copied -- what makes the suite
  need no network and prices a private registry at zero), `fetch_extract`, `fetch_sha256_line`;
  `src/sysroot.mc` lost 122 lines and delegates (`check-sysroots`/`check-stubs` unchanged).
  `hex64` could NOT live in `fetch.mc` (`deps.mc` prints a hash before `driver.mc`, which
  `fetch.mc` needs): `hex64`/`sha256_file` moved to `src/sha256.mc`, one spelling of a digest
  instead of three. `src/pkg.mc` (1387) in the new part `<mc/core_pkg>` (`src/core_pkg.mc`):
  the index reader (`<registry>/index/<name>.toml`, `--registry URL|DIR`, `[registry].url`,
  default `https://minicompiler.dev/registry` -- **the owner decided the same day that a package
  SERVER at minicompiler.dev, in the private `minicompiler/mc-registry`, PRODUCES this exact layout
  from public git URLs validated in the sandbox; the compiler gains no client code**), MVS with
  the two-majors refusal and yanked rows skipped, the lock WRITER (sorted, `lib`/`deps` from the
  archive's own `mc.toml`, `sha256` the tree hash), the archive fetch in M25's order (download,
  extract, HASH AND COMPARE, manifest last, unlink on refusal), `vendor`, `add` (one `[deps]` line
  by `lim_fix_write`'s method), `list`, `verify`, `hash`, `check`, and top-level `mc update`
  (D21: inside its major -- `go get -u` does not cross one; `mc pkg add NAME` with no `@` takes
  the newest non-yanked of any major). `dep_hash_tree(dir, pk)` is the ONE definition of D5's
  hash for `mc build`, `mc pkg hash|sync|vendor|check`. `sync` with nothing to download
  completes without `--yes`; `check` compares against the registry's published copy for
  immutability. Cost **1673 added lines in `src/`, 1268 code** (spec ~880; the cache-manifest
  writer, `check`'s immutability half, `vendor`, the plan table); **globals 440/512**.
  `scripts/check-pkg.sh` 31 -> **63/63**, all offline: a DIRECTORY registry the script builds
  (tarballs from `tests/pkg/src`, `url` = local file, `sha256` from `scripts/pkg-hash.sh` -- so the
  two hash implementations cross-check), fixtures `mathx-1.1.0/2.0.0/2.0.1 (yanked)`, `plot`,
  `heavy` (the other major), `sync/`, `major/`, `add/`; goldens `tests/golden/pkg-list.txt`,
  `tests/pkg/sync/mc.lock.expect`; `check-parts` covers `<mc/core_pkg>`. Rebased onto 8c31a0e
  (#26): no code overlap. `make check` RC 0 (`check-obj` 32/32, fixed point 1228304 B, empty
  `--dump-asm` diff, `check-docs` 197 symbols / 36 flags / 27 TOML keys / 358 links, site 89
  pages), four Linux cells RC 0, `check-inert` identical. Goldens rewritten once: `mc2.sha256`
  `cede0b38…07284`, Linux `e4c876dd…dbc02` / `3f036b4d…d2012`, Windows `70a2259d…68309` /
  `98cf8605…4fde5`. Steps 4-5 (the slim binary, `mc install`, `mc upgrade`) follow the site, per
  the owner's sequencing of 2026-09-05.
- M44 review batch ✔ (`docs/specs/M44.md` § Implementation notes -- the supply-chain review): the
  reviewer's CRITICAL, **reproduced before it was fixed**: `[package].files` of a dependency went
  to `path_join`/`path_norm` uncontained (`path_join` DISCARDS its base on an absolute `rel`;
  `path_norm` resolves `..` with no floor) -- arbitrary READ on every `mc build` (`files =
  ["../../../payload.txt"]` hashed, rc 0), arbitrary WRITE by `mc pkg vendor` (a payload landed
  outside the project), arbitrary DELETE on a hash MISMATCH (`pkg_unbless` re-read the just-refused
  tree and unlinked what it listed: a registry row with a wrong `sha256` deleted a canary two
  directories up -- the attacker never needs a hash that passes). Rule now: ONE reader of
  `package.files`, `dep_read_files()`, behind `dep_rel_ok` (no empty/absolute, no `.`/`..`/empty
  component, no backslash, no byte < 0x20) + `dep_under` (normalised-join prefix) ->
  `<pack> <ver>: files entry escapes the package: <entry>`, exit 2; `pkg_unbless` deletes what the
  EXTRACTION wrote (the member table) and never reads that list again. HIGH: `fetch_extract`
  trusted `tar` (a symlink member to `/etc/hosts` was vendored into `deps/`): `fetch_check_members`
  lists twice (names, then the type column) and refuses links, absolute or `..` members and anything
  leaving `dest` after `--strip-components` (`member escapes the archive` / `archive member is a
  link`, exit 2, archive unlinked), every listed regular file checked afterwards; NOT done, on
  record: the extraction still names no members (a member with a space cannot travel on argv).
  MEDIUM: the hash line is now injective (`<hex> <len>:<path>\n`; control bytes refused; a forgery
  was not constructible anyway because line 1 digests `mc.toml`, where the list lives -- measured);
  `pkg_check_immutable` no longer skips without `--yes` on a URL registry and distinguishes a 404
  (`curl -f` 22 / `wget` 8 = new) from any other failure (`cannot read the published index`).
  LOW: the missing-file failure now unblesses first ("collect the error", `dep_hash_soft`);
  size caps 64 MiB archive / 1 MiB index (`larger than the cap`). Copilot's review of #27 added
  the characters Windows reserves in a name to `dep_rel_ok` (`:` `<` `>` `"` `|` `?` `*` -- `C:/x`
  is absolute to a Windows extractor; one rule for the three hosts). `check-pkg` 63 -> **80/80**
  (four escaping shapes each with a canary asserted untouched, the cross-directory vendor case,
  the wrong-hash unbless, three crafted archives, the `check` refusals, a 68 MB archive, the line
  shape). Cost: `deps.mc` +106 code, `fetch.mc` +197, `pkg.mc` +46. `make check` RC 0 (`check-obj`
  32/32, empty `--dump-asm` diff, `check-lex` 143/143 (3 skipped), `check-docs` 197 symbols),
  four Linux cells RC 0, `check-inert` identical. Goldens rewritten (final, after the Copilot
  fix and the lex-skip wording): `mc2.sha256` `5d2db5f9e94d33422d6d812d1143dc1cdd9f3bc2a1e8727a6ea113060e67ae55`, Linux
  `9161fb1b…e17f8d` / `1ea7dc83…90d1cb`, Windows `831a422a…64b068` / `6224c4a9…9b570b` -- all
  five in the scripts' `hash  file` format.
- `mc --exe`: an executable's exports survive its own zerofill (0.16.x patch; reported by the
  mc-php consumer with a reproducer, `docs/macho-notes.md` § M11 § Segment layout). `stage0/`
  untouched (2848/3000); the whole code change is **`src/backend_exe.mc` +49/-32, 37 of the added
  lines neither comment nor blank**, and **zero new public names** (`check-freeze` 423 entries,
  unchanged).
  **The defect**, reproduced before anything was written: an `mc --exe` host that `dlopen`s a
  flat-namespace bundle (`clang -bundle -flat_namespace -undefined suppress`) referencing a symbol
  the host DEFINES worked with a 16000-byte `__bss` and failed with a 16384-byte one --
  `symbol not found in flat namespace '_mc_answer'` -- while the binary itself still ran.
  **The mechanism.** `mc` writes no export trie (`LC_DYLD_INFO_ONLY`'s `export_off` is 0), so
  `dyld` resolves the bundle's undefined symbols against the classic `LC_SYMTAB`, and it only
  reads that table when `__LINKEDIT`'s offset from the mach header **in memory** equals its offset
  **in the file**. `exe_layout` advanced `vm` by `vmsize` and `fo` by `filesize` independently
  (which is what keeps a 32 MiB `__bss` out of the file), so one whole page of zerofill in
  `__DATA` put `__LINKEDIT` at `vmaddr 0x10000c000` with `fileoff 32768` -- a 16 KiB skew -- and
  every symbol the binary exported became invisible. Measured in both directions rather than
  argued: `ld`'s OWN output with its `export_off`/`export_size` patched to 0 and re-signed fails
  identically with a 16 KiB `__bss` (`ld` never hits it because it always emits
  `LC_DYLD_EXPORTS_TRIE`) and works without one; and `mc`'s failing binary, patched so that
  `__LINKEDIT.vmaddr - __TEXT.vmaddr == __LINKEDIT.fileoff`, finds the symbol with the same symbol
  table and the same `LC_DYSYMTAB`.
  **The fix is the layout, not a trie.** `exe_plan_sections` now groups sections by
  **(segname, zerofill)** and emits every zerofill-only segment FIRST, below `__TEXT`, with
  `fileoff 0 / filesize 0`; from `__TEXT` on, no segment has `vmsize > filesize`, so VM and file
  advance in lockstep and the skew is 0 by construction. A module with a `__bss` therefore gets a
  second `LC_SEGMENT_64` also named `__DATA` (the section keeps its own `segname`, so `nm -m`
  still says `(__DATA,__bss)`). Three places that assumed `__TEXT` was group 0 follow it:
  `exe_layout`'s header offset, `LC_MAIN`'s `entryoff` (now `addr(_main) - __TEXT.vmaddr`) and
  `exe_sig`'s `execSegBase`/`execSegLimit`. Placing the zerofill AFTER `__LINKEDIT` also works
  (measured) but would need the linkedit's size before the relocations are patched; padding the
  file to `filesize == vmsize` is what the 32 MiB `heap[]` forbids.
  **Measured**: the four `--bss` sizes of the consumer's probe (8192, 16000, 16384, 65536) all
  return 42; `build/mc-exe` comes out at the same 1.2 MB with a zerofill `__DATA` of
  `vmsize 0x2064000 / filesize 0` at `0x100000000` and `__TEXT` at `0x102064000`, runs, and
  compiles `src/mc.mc` to an object identical to `build/mc1`'s; `codesign --verify` and
  `nm -m`/`otool -l` are clean. A program with no zerofill (`tests/021-strings.mc`) is
  byte-identical to before. `examples/api`'s binary is the **same 55632 bytes**, differing from
  byte 17 (`ncmds`) on -- the load commands and the addresses in them, nothing else.
  Gate: `scripts/test-exe.sh` gained two macOS-only cases (self-skipping without `clang`),
  `bss-exports` (the host + the clang bundle, exit 42) and `bss-exports-mc` (the compiler's own
  32 MiB `__bss`: `__LINKEDIT` skew 0 and `nm -g` showing ` T _lex_next`). Proved to have teeth:
  with a `build/mc1` from `main` the script is **32/34, exit 1**, both new cases failing
  (`exit 4` -- `dlopen` itself refuses the bundle); with the fix, **34/34**.
  -- `make bundle` re-run BEFORE bootstrapping (60 files, raw 1256996 -> LZ 570125, blob
  570899 B). `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test`
  32/32, `check-lex`/`check-ast`/`check-asm` 108/108, `check-obj` **32/32 identical to the frozen
  seed** and 32/32 `arm64-surface` against `macho`, `check-bundle` (lz round trip 125 cases),
  `bootstrap` at BOTH fixed points (`mc2.o == mc3.o`, 1456184 B; `mc2o.o == mc3o.o`) with the
  cross-road identity (`build/mc2o src/mc.mc == build/mc2.o`) and **both `--dump-asm` diffs
  between `mc1` and `mc2` empty**, `check-surface` 32/32, `check-opt` 76/76, **`test-exe` 34/34
  via `--exe`**, `check-mc`, `check-standalone`, `check-parts`, `check-libroot` 11/11,
  `check-toml`, `check-build`, `check-pkg` 200/200, `check-tool` 31/31, `check-sysroots`,
  `check-stubs`, `check-limits` 17/17 under 90%, `check-minimal`, `test-linux` 57/57 and
  `test-linux-x86_64` 53/53, the four `--exe` cells, `test-windows` 59/59 and
  `test-windows-x86_64` 55/55 objects cross-compiled, `check-examples`, `check-lang`,
  `check-conc`, `check-desktop`, `check-float`, `check-wide`, `check-kernel`, `check-avr`,
  `test-sandbox` 73 ok / 0 failed / 1 skipped, `check-docs` (211 symbols, 50 flags, 36 TOML keys,
  10 directives, 52 samples, 588 links), **`check-freeze` 423 entries unchanged**, `site` 100
  pages + `check-site` + `check-site-linux` 21/21. `make check-linux-host` **RC 0 over all four
  cells** (aarch64 and x86_64 x musl and gnu), each after its own plain AND optimized fixed point
  and with the cross proof green.
  `scripts/check-inert.sh <mc1 from main 210af6b> build/mc1`: **33 objects identical on the plain
  road and 33 with `--opt=1`** (`tests/*.mc` and `src/mc.mc`) -- the object writers are untouched
  -- plus `examples/kernel`'s flat image identical; the four taught examples whose artefact is a
  Mach-O EXECUTABLE (`api`, `lang`, `conc`, `desktop`) differ, which is the fix, at the same file
  size.
  **All ten goldens rewritten once**, each only after its own criterion: `mc2.sha256`
  `dcbc2711...5a1443` -> `6db8b89bea7d0f3e7052b5c99093e614b9c4a13641dbfafbf8d28dc5c50a9596`,
  `mc2-opt.sha256` `5c23323e3c383b2c9671e60bfb696878ecc04fa3e57bae72f6a37d505da7635f` (both by
  `scripts/bootstrap.sh`, after the two empty `--dump-asm` diffs and the two `cmp`s); the four
  Linux ones deleted and re-recorded by `make check-linux-host` -- `mc2-linux-arm64`
  `570cf9e2f6a5068a6894db05f2d9ce26316c5a5246909f126fd003469a24b499`, `mc2-linux-arm64-opt`
  `bf31b307ffd99f21f09cfd8810f1a7c17c1a273fb3ebac7c95d4b8e45ea68831`, `mc2-linux-x86_64`
  `3202ed8dfb8302b1c14dc4337a3651affa41360062f78bdd89acd88a2325eb8e`, `mc2-linux-x86_64-opt`
  `fe138b78765fa21ac0f704bbda2eeee54da4ad3e1fe3816cf7b4718635d0a295`; the four Windows ones
  cross-computed on macOS per `tests/golden/README.md` -- `mc2-windows-arm64`
  `fc4d366df3964c3e5d3111e57eb9cdbe605d5c57c413a75cbc30cefc24204c6c` (1491507 B),
  `mc2-windows-arm64-opt`
  `2274b27c8291f885bc01222530f5990ca8ebe16dd6c26af50511940b0f8f3a02` (1432515 B),
  `mc2-windows-x86_64`
  `0d5f4bb6b1eae630335a7c065a956ba40ef850e69f65194feeada37e9f29f1bf` (1547503 B),
  `mc2-windows-x86_64-opt`
  `327b4988a5e18c746e41e2626d7a8f3aaa8333064f4290580336fa51756f4dfa` (1475047 B), the two plain
  ones also written byte for byte by `build/mc2`.
- Next: M18 or M24 (`docs/plan.md`); M40 (the word-size sweep AVR/PIC need) is
  named in `docs/plan.md`; M13 stays in the backlog (`docs/specs/M13.md`:
- M24 step A ✔ (`docs/specs/M24.md` § M1-M6, M8 and decision D5): **Tier 4 -- the inert half.
  A primitive the core has never heard of.** All in `src/`; `stage0/` untouched (2848/3000).
  A primitive the core has never heard of.** All in `src/`; `stage0/` untouched (2848/3000, byte for byte what main has).
  The rule the whole milestone rests on is a number: **a type id below `TY_MAX` (7) is a core type
  and behaves exactly as it always has, byte for byte; an id at or above it was registered by a
  module, and every core decision about it is delegated.**
  * **M1, the type registry** (`src/ast.mc`, `src/hooks.mc`): `type_new(name, width, align, kind)
    -> ty`, with `type_count`/`type_width`/`type_align`/`type_kind`/`type_name` falling through to
    it above `TY_MAX` and unchanged below. `TK_INT/TK_FLOAT/TK_WIDE/TK_OPAQUE` is what a MACHINE
    dispatches on; the core reads only width and align. A growable arena block (`T_TYPES`) holding
    only the registered types, so the core ladder is untouched. The word is reserved through the
    same `word_add` and entered in the same table `type_alias` writes, so `type_of_token` needed
    NO line and the name is valid in all seven type positions at once; `type_alias`'s guard
    widened from `TY_MAX` to `type_count()`. No keyword and no directive: `tok_init` is untouched,
    `K_U8..K_EXTERN` do not shift, `check-lex` keeps comparing the two lexers.
  * **M2, the literal's type survives resolve** (`src/gen_resolve.mc`): `res_expr`'s `N_INT` arm
    answered `TY_I64` unconditionally and threw a taught literal's type away before the walker or
    any machine could see it.
  * **M3, the three fold guards** (`src/parse.mc`): `fold_unary`, `fold_binary` and `fold_cast`
    return early on a type at or above `TY_MAX`. Without them `1.5 + 2.5` would fold to an INTEGER
    add of two bit patterns and produce an infinity at compile time, silently.
  * **M4, the depth type** (`src/gen_walk.mc`): `walk_depth_type(d)` and `walk_ret_type()`, a
    `MAXDEPTH` array reset per function. **Not a task slot** -- no signature moves, and a machine
    that never reads it emits byte for byte what it emitted before. The five re-announcement sites
    the spec lists are covered in ONE place instead: `gen_expr` became a wrapper that writes
    `res_type(n)` into the depth before the dispatch and again after, and saves/restores
    `walk_ret` around each child, so a comparison, `gen_logic`'s shortcut, `MUN_LNOT`, a cast, an
    intrinsic load and a call are all handled by the same two lines.
  * **M5, the frame slot is the type's width** (`src/gen_walk.mc`, 2 lines): `slot_new(8)` ->
    `slot_new(type_width(ty))` for a scalar local and for a parameter. Provably byte-identical for
    the seven core types, since `slot_new` rounds `(size + 7) & ~7`.
  * **M6, `syntax_lit(&f)`** (`src/hooks.mc`, `src/parse.mc`): the one grammar position Tier 3
    cannot reach, short-circuited by `nonlit == 0`. The handler returns a node or 0 ("the core
    handles this one"). The decimal-to-binary conversion lives in the MODULE, so `lex_number` and
    therefore `--dump-tokens` are exactly what the frozen `stage0/lex.c` produces. **Deviation,
    +8 lines over the spec's M6:** the handler also needs to say where its literal ended, so
    `p_take_lit(q)` and `p_src_end()` were added beside `p_resplit_punct`, under the same "a token
    just lexed from the source being read" guard.
  * **M8, deriving a machine** (`src/gen_walk.mc` for `machine_slot`, `src/hooks.mc` for
    `machine_tab`): `machine_task` writes the GLOBAL `m_arm64` by name, so the recipe
    `docs/reference/hooks.md` published corrupted arm64's own table. Both are built and the doc is
    corrected with them, including the one trap: delegate through a PRISTINE second copy, never
    through the table you patched. `machine_slot` lives in `gen_walk.mc` beside the `MTASK_*` list
    it bounds-checks, and because `src/astdump.mc` includes `hooks.mc` without `gen_walk.mc`.
  * **D5**: a `machine()` registration that shadows an existing name reuses that name's slot.
  Proofs, all in `scripts/check-surface.sh`: a taught `fix` (16.16 fixed point) and `pair`
  (16 bytes) in `lib/user_syntax_demo.mc` with a `syntax_lit` handler reading `1.5` out of the raw
  source -- a parameter, a cast and the literal in one program (exit 42); two `pair` locals
  reserving 32 bytes of frame where two `i64` reserve 16; the fold guards through `+`, `-`, `~`,
  `!` and a cast measured on `--dump-asm` (`fold()` runs after `--dump-ast`), with the control that
  core literals still fold; `type_new("if", ...)` refused with `cannot redefine core keyword: if`
  (`lib/user_dupty.mc`); `lib/user_lit_nop.mc` -- a module whose only registration is `syntax_lit`
  and whose handler answers 0 -- producing byte-identical `--dump-ast` AND objects over the whole
  `tests/` corpus; and `lib/machine_probe.mc`, a machine derived from `arm64` that changes no
  instruction and asserts the depth-type contract on every task over the whole of `src/mc.mc`:
  **32137 tasks, 40238 depths, object byte-identical to the bundled machine's**.
  `scripts/check-lex.sh` gained the `seed-skip` escape `check-asm.sh`/`check-ast.sh` already had
  (risk 6 / D6), unused today. New `scripts/check-inert.sh`: the M17-step-A proof as a script.
  — core cost, measured (`git diff --numstat`, added lines / added lines that are neither a
  comment nor blank): `ast.mc` +58/37, `hooks.mc` +117/45, `parse.mc` +41/15, `gen_resolve.mc`
  +11/5, `gen_walk.mc` +73/34 = **300 added lines, 136 of code**, against the spec's 132 for this
  half. The 164 lines of comment are this repository's density, not extra mechanism.
  `stage0/` untouched, 2848/3000 -- `git diff` against the base commit is empty.
  **The gate is that nothing moves, and it held.** `make check` green end to end (RC 0):
  `test` 32/32, `check-lex` 93/93 (1 skipped), `check-ast` 93/93, `check-asm` 93/93, `check-obj`
  **32/32 identical to the frozen seed**, `check-bundle` (52 files), `bootstrap` at a fixed point
  (`mc2.o == mc3.o`, `--dump-asm` diff between `mc1` and `mc2` empty), `check-surface` 32/32 plus
  every M24 case, `test-exe` 32/32, `check-mc` 7/7, `check-standalone`, `check-toml`,
  `check-build`, `check-limits` **17/17 under 90%**, `check-minimal`, `test-linux` 33/33,
  `test-linux-x86_64` 30/30, `test-windows`, `test-windows-x86_64`, `check-examples`,
  `check-lang`, `check-conc`, `check-desktop`, `check-docs` (155 symbols, 17 flags, 16 TOML keys,
  10 directives, 47 samples, 196 links), `site` 75 pages, `check-site` 0 link problems.
  Plus `scripts/check-inert.sh`: the compiler from before the step and the one after produce
  **byte-identical objects for all 32 `tests/*.mc`, for `src/mc.mc`, and -- through the taught
  compiler each of them builds -- for `examples/api`, `examples/lang`, `examples/conc` and
  `examples/desktop`**. All five goldens rewritten once.
  Docs: `docs/reference/machine.md` (contract **version 3**, § 3 and § 4 rewritten -- the old
  thirteen `mf_*` float slots and `#machine` are DROPPED, with the three reasons recorded),
  `docs/reference/hooks.md` (§ 3 is now six word registrations and three node hooks; the
  derivation recipe corrected), `docs/reference/language.md` § 2 and § 11,
  `docs/reference/diagnostics.md`, `docs/reference/bundle.md`, `docs/build.md`, and the new
  `docs/guide/96-a-new-primitive.md`.
- M24 step B ✔ (`docs/specs/M24.md` § M7, M9 and decisions D1-D3): **`intrinsic` and
  `--dump-machine`.** Still all in `src/`; `stage0/` untouched (2848/3000, byte for byte what main has), and still inert -- no
  test in the corpus registers anything, so `check-obj` stays 32/32 against the frozen seed and the
  pre/post compilers produce byte-identical objects everywhere.
  * **M7, `intrinsic(name, nargs, ty, &f)`** (`src/gen_resolve.mc` +74/45 code, `src/gen_walk.mc`
    +32/22, `src/arena.mc` +7): a NAMED HARDWARE INSTRUCTION applied to values the allocator
    placed. One row inserted between `opc_find` and `func_find` in the dispatch `res_call` and
    `gen_call` already run in that order, so a core intrinsic can never be shadowed
    (`cannot shadow a core intrinsic: ld64`, refused at registration) and every existing
    diagnostic keeps its order; an ordinary function of the same name IS shadowed, which is
    written down. The handler gets `(d, nargs)` with the arguments already lowered to depths
    `d..d+nargs-1` and `walk_depth_type` filled in. The registry lives in `src/gen_resolve.mc`
    beside `intrin_id` and the `IN_*` list it must refuse to shadow -- the same reason
    `machine_slot` lives in `gen_walk.mc`, and because `src/astdump.mc` includes `hooks.mc`
    without either.
    **D2**: `val_reg(d, scratch)`, `dst_reg(d)` and `dst_done(d, reg)` are published as contract
    **version 3** and are the only three names of a machine's internals that are; delegation to a
    built-in task goes through the copied table pointer, so no `a64_*` name is frozen.
  * **M9, `--dump-machine`** (`src/main.mc` +59/43, `src/hooks.mc` +28/15): per registered
    machine, one line per task with the ORIGIN of the slot -- `bundled <machine>` or `taught`, and
    `(current)` on the one the walker would drive. There is no runtime symbol table, so the origin
    is read from a SNAPSHOT (`machine_freeze()`, taken by `main()` before `user_init`) and not
    from a symbol name; a snapshot and not just a count, because a module that re-registers
    `arm64` reuses that name's registry slot (D5) and the registry no longer remembers what was
    there. It stops right after `user_init()`: a machine table is not a function of the source.
  * **D3/`#machine` stays dropped**, with the three reasons in `docs/reference/machine.md` § 4.
  Proofs (`scripts/check-surface.sh`): `rbit(x)` -- AArch64 bit reversal registered as an
  intrinsic in `lib/user_syntax_demo.mc` -- on an arbitrary expression AND at a spilled depth
  (two programs, exit 42 each); `intrinsic("ld64", ...)` refused (`lib/user_dupintrin.mc`); and the
  observable-override proof the old § 4 asked of `#machine`, delivered without the directive:
  `lib/user_badmach.mc` replaces ONE slot so that `+` lowers as a subtraction, `v(50) + v(8)`
  answers **42 instead of 58**, and `--dump-machine` reports exactly one `taught` slot, on the
  `arm64` row, across three machines -- while the stock compiler reports none.
  — core cost: **200 added lines, 130 of code** (`gen_resolve.mc` +74/45, `main.mc` +59/43,
  `gen_walk.mc` +32/22, `hooks.mc` +28/15, `arena.mc` +7/5), against the spec's 55 + 40 = 95.
  The excess is the `--dump-machine` snapshot (D5 made a counter insufficient), the four
  registration guards, and the `mtask_names[]` table the dump prints from.
  `make check` green end to end (RC 0), same numbers as step A plus `check-docs` at 162 symbols
  and 18 CLI flags; `scripts/check-inert.sh` identical everywhere; all five goldens rewritten once.
  Docs: `docs/reference/hooks.md` (`intrinsic` and the lookup family, `machine_freeze`),
  `docs/reference/cli.md` (§ "the six dumps", with the `--dump-machine` example),
  `docs/reference/machine.md` § 3 and § 4, `docs/reference/diagnostics.md`,
  `docs/reference/bundle.md`, `docs/guide/96-a-new-primitive.md`.
- M24 step 1 ✔ (`docs/specs/M24.md` § "Step 1 -- `<float>`, the first library"):
  **`f32` and `f64`, taught to `mc` from outside the compiler.** `git diff src/` for this step is
  **empty** apart from the generated `src/bundle_data.mc`; `stage0/` untouched, 2848/3000 -- `git diff` against the base commit is empty.
  * `lib/float.mc` (432): `type_new` for `f64` (8, 8, TK_FLOAT), `f32` (4, 4) and `f64raw` (8, 8,
    TK_INT -- the same bytes as an integer, so `(f64raw) x` is one `fmov`/`movq` and a NaN can be
    written down in a language with no NaN literal); the `syntax_lit` handler; and eight
    `intrinsic` registrations (`ldf32 ldf64 stf32 stf64 sqrt_f64 fabs fmin fmax`).
    **The decimal-to-binary conversion is correctly rounded and written in integers**, because the
    compiler that runs it has no floats: the literal is the exact rational `U/V`, and a 2048-bit
    big integer in fixed arrays takes the quotient with one guard bit and lets the remainder decide
    the tie. `f32` is produced by running the same routine with a 24-bit significand, never by
    narrowing an `f64`, so there is no double rounding. Verified bit for bit on `0.1 + 0.2`
    (...334, not ...333), pi to fifteen digits, `1e308`, the smallest **subnormal** `5e-324`,
    `1e20` and an exact value.
  * `lib/machine_arm64_float.mc` (669) and `lib/machine_x86_64_float.mc` (775): two derived
    machines, 21 slots each, everything else delegating through a pristine copy. Float depths in
    `v16..v23` (never the callee-saved `v8..v15`) / `xmm8..xmm13` on SysV / `xmm0..xmm5` on Win64,
    where `xmm6..xmm15` are callee-saved. The **whole ABI comes out of `walk_depth_type`**: two
    counters on AAPCS64 and SysV, one shared position on Win64, and the overflow in argument order.
    `walk_ret_type()` is what tells `MTASK_CALL` what the call returns, since by then depth `d`
    holds argument 0.
    Two things worth keeping: the AArch64 float conditions are `mi/ls/gt/ge/eq`, never `lt/le`, so
    a NaN makes all six ordered predicates false; on x86-64 `<` and `<=` SWAP their operands and
    use `a`/`ae` for the same reason, and only `==`/`!=` need the parity mask.
  * `lib/user_float.mc` (17) is the `[compiler] modules` entry, `lib/mc_float.mc` (12) the
    standalone one, and `lib/float_rt.mc` (71) the RUN-TIME half a program includes -- `putf64`
    (fixed precision, half-up, `nan`/`inf` by bit pattern, a hex fallback past 2^63),
    `fmt_f64` and `puthexf`. It is a separate include and NOT a source the module pushes:
    pushing it would put a call to `write` into every program the taught compiler compiles,
    including `lib/sys_windows_start.mc`, which has no system layer at all. It is the first user of
    the `seed-skip` escape step A added to `scripts/check-lex.sh` -- it spells float literals, so
    the frozen seed cannot lex it, and it says so in its own header.
  * `tests/float/` (12 files) and `scripts/check-float.sh` (369), inside `make check`. Every test
    is **bit-exact**: it stores with `stf64`, reads back with `ld64` and prints sixteen hex digits
    against a value recorded in its header (produced once by `python3`, so the suite has no python3
    dependency).
  Results, the same twelve sources on every leg: **macos/aarch64 12/12, linux/aarch64 12/12,
  linux/x86_64 12/12** (run for real in Docker), **windows/aarch64 11/11 and windows/x86_64 11/11
  objects linked** with `lld-link` (1 skipped: `extern f64 sqrt` -- there is no C runtime on that
  target). `.github/workflows/ci.yml` puts the float objects into the SAME four artifacts the
  suites use, so the two Windows jobs and the two Linux jobs RUN them.
  **The llvm-mc sweep**, mandatory for a machine that lands in `lib/`: every distinct float
  instruction the two machines emit over the whole corpus, fed back through the assembler --
  **37 (mach-o arm64), 37 (elf aarch64), 181 (elf x86_64), 166 (coff x86_64), 0 mismatches**.
  `sqrt(2.0)` through `extern f64 sqrt(f64)` -- the case that is flatly unreachable without M24,
  because `MTASK_CALL` could not be told an argument was a double -- comes back
  `0x3ff6a09e667f3bcd`, bit for bit what the `sqrt_f64` intrinsic produces and what libm produces.
  `make check` green end to end (RC 0), with `check-float` added: `test` 32/32, `check-lex`
  101/101 (2 skipped), `check-ast` 101/101, `check-asm` 101/101, `check-obj` **32/32 identical to
  the frozen seed**, `check-bundle` (61 files), `bootstrap` at a fixed point, `check-surface`
  32/32, `test-exe` 32/32, `check-limits` 17/17 under 90%, `test-linux` 33/33,
  `test-linux-x86_64` 30/30, `check-float` ok, `check-examples`, `check-lang`, `check-conc`,
  `check-desktop`, `check-docs`, `site` + `check-site`. `scripts/check-inert.sh` between the
  step-B compiler and this one: identical everywhere. All five goldens rewritten once.
  Docs: `docs/guide/96-a-new-primitive.md` § 5 (`<float>`, worked), `docs/build.md`,
  `docs/reference/bundle.md` § `<float>`, `docs/reference/language.md`, `docs/ci.md`.
- M24 step 2 ✔ (`docs/specs/M24.md` § Generality, and the architect's addition (a)):
  **the three modules that prove the principle.** For all three, `git diff src/` is **empty**
  apart from the generated `src/bundle_data.mc`; `stage0/` untouched, 2848/3000 -- `git diff` against the base commit is empty. The gate is
  `make check-wide` (`scripts/check-wide.sh`, 170 lines), inside `make check`.
  * **`lib/i128.mc` (438)** -- a 128-bit integer. `type_new("i128", 16, 16, TK_WIDE)`, and the
    value lives in **ONE depth backed by a 16-byte slot**: a value spanning two depths would
    collide with `gen_binary`'s `depth + 1` and `gen_call`'s `depth + i`, which is the walker's own
    arithmetic and what `MTASK_DEPTH_SPAN` would be for. Carry survives memory residency because
    neither `ldr` nor `str` touches NZCV: `adds`/`adc`, `subs`/`sbc`, `mul`/`umulh`. The compare is
    the one place a 128-bit operation is not "the 64-bit one twice" -- `subs`/`sbcs` leave N and V
    right but Z reflects only the high half, so equality is computed separately and
    `gt = ge && !eq`, `le = lt || eq`. The literal `123i` goes through a **module-private global
    with an `N_BLOB` initializer** (`MTASK_CONST` and `N_INT`'s val are one `i64` each) whose name
    carries `$`, so it cannot collide with anything a program wrote. A 16-byte argument arrives in
    an AAPCS64 **even register pair**. AArch64 only, and it says so.
  * **`lib/f16.mc` (240)** -- half precision as a STORAGE type, on top of `<float>`'s machine:
    four slots (`ldr h`/`str h` and the two `fcvt`s), two intrinsics and two accessors, and
    nothing else. That is only possible because `<float>`'s `fa_is_float` was generalised in the
    same commit from `t == ty_f64 || t == ty_f32` to **`type_kind(t) == TK_FLOAT`** -- which is
    what `kind` is for, and what lets one float machine carry f64, f32 and somebody else's half
    with the same register file, spill, ABI and return position. `f32` became `type_width(t) == 4`
    for the same reason, and `fa_need_ds` refuses arithmetic on a width this machine has no
    instructions for instead of doing it quietly.
    The acceptance case is round-to-nearest-**ties-to-even**: 1 + 2^-11 is exactly halfway between
    the halves `0x3c00` and `0x3c01` and goes to the even one; a round-half-up conversion would
    answer `0x3c01`. `f16 tbl[8]` is **16 bytes of `__bss`**, checked in the object.
    Deviation on record: the spec asks for the software fallback to be exercised "by building
    x86-64 without F16C". `mc`'s x86-64 machine never had F16C -- VEX encoding is `examples/avx`'s
    subject -- so what is delivered is the ARM64 hardware path, with the module stating that on a
    machine without the instruction the identically-named ordinary functions are called instead
    (an intrinsic shadows a function of the same name and nothing else does).
  * **`examples/avx/` (avx.mc 300, main.mc 45, README.md)** -- ONE AVX instruction named by its
    encoding. `type_new("v8f32", 32, 32, TK_OPAQUE)`, `intrinsic("vaddps", 2, ...)` whose two
    operands arrive at depths the core chose, `val_reg`/`dst_reg`/`dst_done` to find them, and the
    module's own **VEX bytes** -- two-byte `C5` when nothing outside the low eight registers is
    named and three-byte `C4` otherwise, which is the rule `llvm-mc` follows and what makes the
    re-assembly an equality: **11 distinct VEX instructions, byte for byte**. Depths 0..5 in
    `ymm0..ymm5`, spilled from 6 into 32-byte slots with `vmovups`, because the frame is 16-byte
    aligned and a 32-byte aligned spill is unreachable. It is NOT executed here: this host has no
    AVX machine and no emulator guaranteed to have it; the README says which VEX forms are
    reachable and which are not, and that is the open problem only a real x86-64 CI leg can close.
  `check-wide` output: i128 and f16 both run and exit 0 with their expected stdout, the default
  compiler refuses both sources, 5 literal globals each an `N_BLOB` of 16 bytes and 16 bytes apart
  in the object, the `adds`/`adc` pair in `--dump-asm`, the even register pair, the 16-byte array,
  `fcvt h16, s16`, the AVX object, and the sweep.
  `make check` green end to end (RC 0) with `check-wide` added; `check-float` still ok on all five
  legs after the kind-based generalisation (12/12, 12/12, 12/12, 11/11, 11/11 and the four sweeps).
  All five goldens rewritten once. Docs: `docs/guide/96-a-new-primitive.md` § 5,
  `docs/reference/bundle.md` § "The generality proofs", `examples/avx/README.md` (new).
- M41 done (`docs/specs/M41.md` + its § Implementation notes, `docs/guide/98-recreating-the-compiler.md`,
  `docs/reference/bundle.md` § The parts of the core, `docs/reference/hooks.md` § 7,
  `docs/reference/machine.md` § 6): **`<mc/core>` becomes composable, and a recreated compiler is
  smaller than `mc` by exactly what it omits.** `stage0/` untouched (2848/3000); everything is in
  `src/`, `lib/`, `scripts/`, `site/gen/` and `docs/`. Four gated commits, `make check` green after
  each one.
  * **Two splits, byte-neutral by construction** (commit 1). `src/macho.mc` became
    `src/objmodel.mc` (321 lines: the three record layouts, `R_*`/`S_*`/`TEXT_FLAGS`, `sec_new`,
    `sym_new`, `sym_set_value`, `reloc_add`, `sym_class`, `sym_order`, `out_name16`, `dump_syms`)
    plus `src/macho.mc` (172: the `MH_*`/`LC_*`/`N_*`/`CPU_*` defines and `macho_write`), and
    `src/main.mc` became `src/cli.mc` + a `main()`. Both are single cuts, so the function
    DEFINITION ORDER of the whole program did not move: with the bundle held at its pre-split
    content, `build/mc1 src/mc.mc` produced `build/mc2.o` byte for byte
    (`c1249acab30099cb52fe4ebdc1c547a0b2fc2e2cbdc2032390c88bf6bdf563a2`). `src/astdump.mc` now
    includes `objmodel.mc` alone -- it never needed a writer.
  * **Five parts, and `src/core.mc` is their sum** (commit 2): `src/core_min.mc` (arena lz objmodel
    lex ast parse gen_resolve gen_walk hooks cli), `core_machines.mc`, `core_writers.mc`,
    `core_build.mc`, `core_bundle.mc`, then `main.mc` -- six `#include` lines, so the full assembly
    IS the parts. `main.mc` (36 lines) calls `host_init`, `mc_machines_init()`,
    `mc_writers_init()`, `mc_bundle_init()`, `mc_build_init()` and hands over to
    `i64 mc_main(i64 argc, uptr argv, uptr envp)`, which is `src/cli.mc`'s and therefore
    `<mc/core_min>`'s. Four `if`s in that file became registrations (`src/hooks.mc` +119):
    `machine_use_if` (the host's machine, when it exists), `backend_default` (the default object
    backend when there is no target registry), `subcommand(name, fn, usage)` (the eighth registry;
    `build`/`limits`/`sysroot` are `<mc/core_build>`'s, each carrying its own usage line, and
    `drv_usage()` is now `subcommand_usage()`), and `on_plan` (M23's `lim_plan`). Plus the
    architect's addition (b): `no machine registered` before `gen_lower`. `src/driver.mc`: a
    `[compiler].core` starting with `<` is emitted verbatim, which is how a project asks for a part.
  * **Removal and one override** (commit 3), all inert with nothing declared: `type_disable(ty)`
    (a bitmask in `src/ast.mc`, one test at the head of `type_of_token` --
    `u32: removed by this compiler`, at the token; it removes the WORD from the surface, not the
    type from the model), `intrinsic_disable(name)` (a fixed 32-entry table, one test at the head
    of `res_call`, so core and taught intrinsics are refused the same way), and
    `type_set_width(ty, w)`, which accepts `TY_UPTR` alone. M40 § 1b C1/C3/C4/C5:
    `type_width(TY_UPTR)` reads `ty_uptr_w`, `slot_new`'s granule is `walk_word()`, the three
    roundings to 16 are `align_up(v, walk_align())` and a string in a `uptr[]` initializer writes
    `w` zero bytes with an `R_UNSIGNED` of length log2(w).
  * **The gate** (commit 4): `scripts/check-parts.sh` (`make check-parts`, inside `make check`)
    proves five things -- the two spellings `cmp` equal (849856 bytes); each part compiles on
    `<mc/core_min>` ALONE; the measured table; the two refusals; the width. That per-part case is
    not in the spec's acceptance list and it earned its keep at once: **four names had to move**
    for the parts to be parts -- `tm_cat` and `tm_num_str` (`toml.mc` -> `arena.mc`), `MODE_755`
    (`backend_exe.mc` -> `arena.mc`) and `R_X86_PC32`/`R_X86_PLT32` (`machine_x86_64.mc` ->
    `objmodel.mc`). `site/gen/util.mc` lost its own `MODE_755` for the same reason.
  **Measured** (`sh scripts/check-parts.sh`, and the cumulative spellings behind
  `docs/guide/98-recreating-the-compiler.md` § 3):

  | spelling | `__text` | `__cstring` | `__data` | on disk |
  |---|---|---|---|---|
  | `<mc/core_min>` + probe machine + null writer | 147 224 | 7 034 | 2 496 | **219 417** |
  | + `<mc/core_machines>` | 183 664 | 7 795 | 6 224 | 260 543 |
  | + `<mc/core_writers>` | 232 712 | 8 683 | 6 640 | 315 934 |
  | + `<mc/core_build>` | 289 484 | 15 093 | 6 936 | 395 820 |
  | + `<mc/core_bundle>` | 293 180 | 15 454 | 374 800 | 760 013 |
  | `mc` itself | 292 968 | 15 443 | 374 800 | **759 875** |

  A compiler with one machine and one writer of its own is **29% of `mc`** -- of the 540 KB it does
  not pay, 364 KB is the bundle blob and 146 KB is code.
  Probes: `lib/user_core_min.mc` (a two-slot probe machine and a null writer), `user_nold64.mc`,
  `user_nou32.mc`, `user_uptr2.mc`, `user_badwidth.mc` -- files in `lib/`, deliberately NOT
  bundled (they are fixtures; bundling them would move the blob and the five goldens for something
  no compiler includes).
  **Inertness**, in M17 step A's protocol: `scripts/check-inert.sh` between the compiler before
  each step and the one after -- 33 objects identical (`tests/*.mc` and `src/mc.mc`) and the five
  taught examples (`api`, `lang`, `conc`, `desktop`, `kernel`) identical through the compiler each
  side builds. `examples/kernel` was the one Acceptance 3 named and the script did not run: it is
  untouched and still includes `<mc/core>`, and it is now asserted like the other four -- the
  widest of the five, since its module registers a machine, a backend and an `os`/`arch` pair the
  running compiler does not have, and its artefact is a flat image where one byte shows.
  — `make check` green end to end (RC 0, 0 FAIL): `test` 32/32, `check-lex` 120/120 (2 skipped),
  `check-ast` 120/120, `check-bundle` (75 files, raw 776601 -> lz 364543, blob 365449 B),
  `check-asm` 120/120, `check-obj` 32/32 against the frozen seed, `bootstrap` at a fixed point
  (`cmp mc2.o mc3.o`; the `--dump-asm` diff between `mc1` and `mc2` empty), `check-surface` 32/32,
  `test-exe` 32/32, `check-mc` 7/7, `check-standalone`, **`check-parts`**, `check-toml` 10/10,
  `check-build` 21/21, `check-sysroots`, `check-stubs` 9/9, `check-limits` 17/17 under 90%,
  `check-minimal`, `test-linux` 33/33, `test-linux-x86_64` 30/30, `test-windows`,
  `test-windows-x86_64`, `check-examples`, `check-lang`, `check-conc`, `check-desktop`,
  `check-float`, `check-wide`, `check-kernel`, `check-docs` (178 symbols, 19 flags, 17 TOML keys,
  10 directives, 47 samples, 243 links), `site` (80 pages) + `check-site`. `make check-linux-host`
  green on both architectures. The five goldens were rewritten once **per commit** (four times, not
  once): every commit that touches `src/` regenerates `src/bundle_data.mc`, which is part of
  `src/mc.mc`, so `build/mc2.o` moves in each of them -- recorded in `docs/specs/M41.md`
  § Implementation notes 9, each rewrite after an empty `--dump-asm` diff and a passing
  `cmp build/mc2.o build/mc3.o`.
- M41.5 done (`docs/specs/M41.5.md`, `docs/surface.md` § M41.5, `docs/reference/hooks.md` § 3):
  **a module can participate in a function's parameter list.** `stage0/` untouched (2848/3000;
  `git diff main -- stage0/` is empty). `parse_params` was the one position on the parse path with
  no hook at all -- `syntax` fires on a declaration's FIRST token and `word_add` refuses the core
  type words, so nothing keyed by a word can ever be reached from `i64`. The consumer (the `ngen`
  port of teko, written against `docs/`) is blocked on two things that are parameters and nothing
  else: `i64 f(i64 x, i64 y = 10)` and `i64 g(params i64 xs)`. The owner chose the HOOK over the
  features: neither default parameters nor variadics are in the language.
  * **`syntax_param(&f)`** (`src/hooks.mc` +52/-0, 19 code lines): `i64 f()` -> the index of an
    `N_PARAM`, or **0 = "the core handles this one"**. Growable table (`grow`), arena tag
    `T_SYNPARAM` inserted after `T_ONJUMP` (`src/arena.mc` +16/-13 -- one new `#define`, one name,
    one seed, and the twelve renumbered tags; `T_COUNT` 38 -> 39, and `mc limits` gains a
    `syntax_param` row). Handlers run in registration order, the first non-zero answer wins, and
    `nsynp == 0` short-circuits the whole branch the way `nonstmt`/`nonjump`/`nonlit` do.
    Consulted at the HEAD of `parse_params`'s loop, right after the `K_RPAR` test and **before
    `type_of_token`** -- which is the entire point: a parameter opening with a taught word has to
    get there before the core demands a type, and a parameter with a trailer has to be read WHOLE
    (`p_type()`, `p_ident()`, then `p_accept(K_ASSIGN)` + `parse_expr(0)`) by whoever records the
    trailer. Named `syntax_param` and not `on_param`: the `on_*` family runs after a node exists
    and cannot consume tokens.
    Two guards, both at the parameter's own position: `syntax_param handler consumed no tokens:
    <word>` (the `stmt_syntax` precedent, cursor AND token start compared) and `syntax_param
    handler did not return a parameter` (index out of range included) -- that node goes straight
    into a list `gen_lower` walks by `nd_type`/`nd_name`, so anything else is a wrong frame layout
    later rather than a diagnostic here. `MAXPARAMS` and `at most 12 parameters` still apply to
    what the handler returns.
  * **`p_decl_name()`** (`src/parse.mc` +64/-11, 33 code lines, with `param_syntax`): the name of
    the top-level declaration being parsed, 0 outside one. Set by `parse_top` **and by
    `parse_extern`** (a deviation from the design's literal text, on record in the spec § 6: an
    `extern` is a top-level declaration and it calls `parse_params`) the moment the name is read,
    cleared by `top_add`. The storage is called `cur_decl` because `decl_name(uptr msg)` is already
    a function in `parse.mc`.
  * Proofs, all in `lib/user_syntax_demo.mc` (707 -> 850) and `scripts/check-surface.sh`:
    (a) `i64 f(i64 x, i64 y = 10)` with the module recording the default and completing `f(1)`
    from a `pass()` with `decl_find`/`decl_nparams` -- exit 42; (b) `i64 sum2(params i64 xs)`,
    the taught word lowering to `PARAM type=uptr name=xs`, exit 42, and the default compiler
    refusing both sources (`expected ) in the parameter list`, `type expected in parameter`);
    (c) `p_decl_name()` with teeth -- `f` and `g` differ ONLY in the default at the same parameter
    index, and the tree shows `INT val=10` in one call and `INT val=30` in the other, which a
    module ignoring `p_decl_name()` could not produce; (d) `tests/err/071-param-noadvance.mc` and
    `072-param-nonparam.mc` with their exact messages and the two fixture handlers `sd_pnop`/
    `sd_pbad` (the `sd_nop`/`sd_nil` shape); (e) inertness -- `lib/user_param_nop.mc` +
    `lib/mc_param_nop.mc`, a module whose ONLY registration is `syntax_param` and whose handler
    answers 0 for every parameter of every function: `--dump-ast` and objects byte-identical over
    the whole `tests/` corpus.
  * `examples/lang/README.md` said "At most 8 parameters"; `MAXPARAMS` has been 12 since M38 and
    the example has no ceiling of its own (`lang_expr.mc`, `lang_stmt.mc` test against
    `MAXPARAMS`). Corrected to 12 slots / at most 10 arguments besides `self`.
  -- core cost: **132 added lines, 66 of them neither comment nor blank** (`parse.mc` +64/33,
  `hooks.mc` +52/19, `arena.mc` +16/14, twelve of those last being the renumbered tags).
  `make bundle` re-run BEFORE bootstrapping (`tools/bundle.list` gained `mc_param_nop` and
  `user_param_nop`): **77 files, raw 789698 -> LZ 369888, blob 370822 B**, `<mc/bundle_data>` one
  `#embed` node plus a 308-value index. `make check` green end to end (RC 0, zero FAIL):
  `budget` 2848/3000, `test` 32/32, `check-lex` 122/122 (2 skipped), `check-ast` 122/122,
  `check-asm` 122/122, `check-obj` **32/32 identical to the frozen seed**, `check-bundle`
  (reproducible + fresh, lz round trip 101 cases), `bootstrap` at a fixed point (`mc2.o == mc3.o`,
  857240 bytes; the `--dump-asm` diff between `mc1` and `mc2` is **empty**), `check-surface` 32/32
  + every M41.5 case, `test-exe` 32/32, `check-mc` 7/7, `check-standalone`, `check-parts`,
  `check-toml` 10/10, `check-build` 21/21, `check-stubs` 9/9, `check-limits` 17/17 under 90%,
  `check-minimal`, `test-linux` 33/33, `test-linux-x86_64` 30/30, `test-windows` 35/35 +
  `test-windows-x86_64` 33/33 cross-compiled, `check-examples`, `check-lang` 14, `check-conc` 21,
  `check-desktop`, `check-float`, `check-wide`, `check-kernel` (QEMU 11.0.1, exit 0),
  `check-docs` (**180 symbols**, 19 flags, 17 TOML keys, 10 directives, 47 samples, 243 links),
  `site` 81 pages + `check-site` (0 link problems).
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from 752d385): **33
  objects identical** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for
  `examples/api`, `examples/lang`, `examples/conc`, `examples/desktop` and `examples/kernel`
  through the taught compiler each of them builds.
  The five goldens rewritten **once**, only after the empty `--dump-asm` diff and
  `cmp build/mc2.o build/mc3.o`: `mc2.sha256` `779f272d...31f9e` ->
  `17adb08037b7afb30e31c81ed252a6bb6555ffc46831df54c7d5c0969f4d24ce`; the Linux pair deleted and
  re-recorded by `make check-linux-host` (Docker, both arches, each after its own fixed point
  `mc2l.o == mc3l.o` and with the cross proof green) --
  `mc2-linux-arm64.sha256` `7fefed77dafb84ad04bdeee737cdfa5bc1df70112a685a1e1e52eac265b5bdff`,
  `mc2-linux-x86_64.sha256` `912613369fedc29bd8c58c42ad973b1da08c0e9c06a828e4a6bed7d76689c05d`;
  the Windows pair cross-computed per `tests/golden/README.md` --
  `mc2-windows-arm64.sha256` `2aed564c9a9f37c891adb124b01c49d5a5f28abf02d3c69a937faae4142d32ce`
  (872667 B), `mc2-windows-x86_64.sha256`
  `a41a3c727bf13094f3a1907ce7592704e032aa12244339b964afccba4dec4784` (891291 B).
- M41.5, second follow-up (`docs/specs/M41.5.md` §§ 8-11, `docs/reference/hooks.md` §
  `syntax_infix`, `docs/surface.md` § "M41.5 -- and a core operator"): **a module may teach a CORE
  operator.** `stage0/` untouched (2848/3000). The defect the same `ngen` consumer exposed:
  `syntax_infix("+", 9, &h)` was ACCEPTED -- `word_add` refuses only `K_U8..K_EXTERN`, and `+` is
  `K_ADD`, punctuation outside that range -- and then silently UNDONE, because `parse_unit()` ran
  `ops_init()` as its first statement, after `user_init()`, and `infix_set`'s last line is
  `set_ie_fn(e, 0)` (M21's rule that a `#infix` drops the handler). Reproduced with a handler whose
  body is an unconditional `die()`: before, the compiler built fine and `i64 main() { return 1 + 2; }`
  compiled and exited **3**; after, `mc: probe: the + handler fired`, exit 1.
  * **The owner's decision was permit, not refuse**, consistent with M24 already letting a module
    replace the machine slot that lowers `+` (`lib/user_badmach.mc`).
  * **The fix is five code lines**: `i64 ops_ready = 0;` plus a two-line guard at the top of
    `ops_init()` (`src/parse.mc`) and one `ops_init();` call at the head of `syntax_infix`
    (`src/hooks.mc`) -- 30 added lines in `src/`, **4 of them neither comment nor blank**.
    Placement: NOT `src/cli.mc` (another branch is editing it heavily, and "before `user_init()`"
    is three call sites, not one -- `cli.mc`, `driver.mc`, `limits.mc`, with `astdump.mc` parsing
    without one at all); the table is an initialisation, not a phase, so it is built ON FIRST USE
    and the first consumer triggers it. The guard also removes a latent bug: `ops_init` used to
    re-fill the table on every `parse_unit`, which would have undone a `#infix` and every
    `syntax_infix` if any process ever parsed two units.
  * **The precedence question, decided and tested: the module's `prec` wins.** `syntax_infix`
    re-declares the entry exactly as `#infix` does, so a module that wants the core's grouping
    repeats the core's number (`docs/reference/language.md` § 3). M21's rule is untouched (a
    `#infix "+"` in the SOURCE still drops the handler) and the duplicate refusal stays -- the
    FIRST registration on a core operator is allowed, because a core operator carries no handler
    to override.
  * Proofs, `lib/user_coreop.mc` + `lib/mc_coreop.mc` (the `user_badmach`/`mc_badmach` shape) and
    `scripts/check-surface.sh` (+121/-20): the taught `+` lowers `a + b` to a call `plus(a, b)`
    the PROGRAM provides -- `v(50) + v(8)` is **58** with `build/mc1` and **42** with
    `build/mc-coreop`, and `--dump-ast` holds `CALL type=i64 name=plus` with no `op=+`; `*` taught
    at **3** instead of the core's 10 makes `55 - 6 * 7` parse as `star(55 - 6, 7)` = **42**
    against **13** for the stock compiler; `--dump-rules` prints `infix + prec 9 left handler`,
    `infix * prec 3 left handler`, `infix - prec 9 left`; a `#infix "+" 9 left $1 - $2` in a source
    that defines no `plus` compiles and exits 42 (the handler would have died with
    `unknown function: plus`); and `lib/user_dupcoreop.mc` gives `mc: operator already taught: +`
    at `user_init` time -- the old dupop block became a `dup_case` helper run for `.+` and for `+`.
    No `tests/err/` case was added: the change introduces no new message, and
    `066-infix-drops-handler.mc` passes unchanged with its exact text. The three new `lib/` files
    are NOT in `tools/bundle.list`, following the M41 precedent for check-script-only modules
    (`user_badwidth`, `user_uptr2`, `user_nou32`, `user_nold64`, `user_core_min`).
  -- inertness: `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from the
  branch's HEAD before the edit) -- **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus
  byte-identical artefacts for `examples/api`, `examples/lang`, `examples/conc`,
  `examples/desktop` and `examples/kernel`. `make bundle` re-run BEFORE bootstrapping (77 files,
  raw 791608 -> LZ 370822, blob 371756 B). `make check` green end to end (**RC 0, zero FAIL**):
  `test` 32/32, `check-lex` 125/125 (2 skipped), `check-ast` 125/125, `check-asm` 125/125,
  `check-obj` **32/32 identical to the frozen seed**, `check-bundle` (lz round trip 101 cases),
  `bootstrap` at a fixed point (`mc2.o == mc3.o`, 858304 bytes; the `--dump-asm` diff between
  `mc1` and `mc2` is **empty**), `check-surface` 32/32 + the five new core-operator cases + inert,
  `test-exe` 32/32, `check-mc` 7/7, `check-standalone`, `check-parts`, `check-toml` 10/10,
  `check-build` 21/21, `check-stubs` 9/9, `check-limits` 17/17 under 90%, `check-minimal`,
  `test-linux` 33/33, `test-linux-x86_64` 30/30, `test-windows` 35/35 + `test-windows-x86_64`
  33/33 cross-compiled, `check-examples`, `check-lang` 14, `check-conc` 21, `check-desktop`,
  `check-float`, `check-wide`, `check-kernel` (QEMU 11.0.1, exit 0), `check-docs` (180 symbols,
  19 flags, 17 TOML keys, 10 directives, 47 samples, 244 links), `site` 81 pages + `check-site`
  (0 link problems). The five goldens rewritten once, only after the empty `--dump-asm` diff and
  `cmp build/mc2.o build/mc3.o`: `mc2.sha256` `17adb080...4d24ce` ->
  `0883ef0cedc2f388fa6937452e62d9c0deecbfa81e52b91b64d16526b930bae1`; the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `58fef265ba539e386c114f427cc60fffb355b8fa390d38e1a89f85e73609ff2b`,
  `mc2-linux-x86_64.sha256`
  `6361d20d6e08e9b57e142dbadfed08e608a43147de324c563c45c2b944132eff` (each after its own
  `mc2l.o == mc3l.o` and with the cross proof against the macOS `build/mc2.o` green); the Windows pair cross-computed per
  `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `2ccfc7b850fcd7c17e88ec1b152aaaa399cc12ddc4c53445caf057fd9ef88ebe` (873735 B),
  `mc2-windows-x86_64.sha256`
  `bfe9e7540023050a1af5684f787f430f5e5faba36ce374a74f74f9b935d45477` (892351 B).
- Post-M41.5 batch (review, `docs/specs/M41.5.md` § 12): the three findings the PR review raised.
  The whole code change is `src/parse.mc` **+45/-2, 19 of the added lines neither comment nor
  blank**; `stage0/` untouched (2848/3000, `git diff origin/main -- stage0/` empty). Rebased onto
  `origin/main` 611671a first (PR #15 + #14): the only conflicts were generated or aggregated
  files -- `src/bundle_data.mc` and the five goldens (regenerated/re-recorded below),
  `examples/lang/README.md`, where main had made the same "8 parameters -> 12" correction, so this
  branch's commit `f40fbab` became empty and was dropped. `CLAUDE.md`, `docs/surface.md`,
  `docs/reference/hooks.md` and `docs/reference/diagnostics.md` auto-merged with both sides' text
  (main added no § State entry of its own in those two PRs).
  1. **A `syntax_param` handler that consumed tokens and then returned 0 was believed** (HIGH).
     `param_syntax()` ran the "consumed no tokens" guard only on the non-zero answer, so 0 --
     "the core handles this one" -- was taken at face value with the cursor already moved.
     Reproduced with a handler that reads `peat i64 x` and the comma after it and answers 0:
     `i64 f(peat i64 x, i64 y, i64 z)` came out of `--dump-ast` as a **two-parameter** `f(y, z)`,
     compiled clean, linked, and returned 42 for `f(4, 2)` -- a three-parameter declaration
     running with the wrong arity, no diagnostic anywhere. The guard now compares the cursor AND
     the token start on **both** answers: `syntax_param handler consumed tokens and returned 0:
     <word>`, at the parameter's own position, with the word copied from the token the handler was
     GIVEN (`xstrdup(t0, l0)`) rather than from `cur_name()`, which by then names something else.
     **`syntax_lit` had the same latent shape** (M24) and is fixed in the same commit: a handler
     that moved the cursor with `p_take_lit` and then declined left `parse_primary` building its
     `N_INT` out of a token whose span no longer covers what was read -- `return 7q;` compiled
     clean and exited **7**, the `q` swallowed. Now `syntax_lit handler consumed tokens and
     returned 0: <literal>`. Both checks are at the END of the handler chain, not per handler:
     `run_syntax_param`/`run_syntax_lit` live in `src/hooks.mc`, which is included before
     `src/parse.mc` and cannot see `cp` or `cur` -- so the two broken fixtures are registered LAST
     in `lib/user_syntax_demo.mc` (`sd_peat`, `sd_leat`), and their headers say why.
  2. **`p_decl_name()` was blind inside a handler that owns the declaration** (MEDIUM).
     `cur_decl` was set only by `parse_top`/`parse_extern` -- the two places the CORE reads a
     name -- so a `syntax` handler that parses a container and declares each member with the
     public `parse_params()` + `parse_function()` got the enclosing declaration's name, or 0, for
     every member, while `docs/reference/hooks.md` recommends keying `syntax_param` bookkeeping by
     exactly that value. Two changes: `parse_function(ty, name, params)` sets `cur_decl = name`
     for the duration of the body and **restores** the previous value (a module may nest a
     declaration through `p_push_source`), and `void p_set_decl_name(uptr name)` joins the public
     API for a handler that reads the member's name itself. Proof in the demo:
     `capsule Name { ... }` (named `capsule` and not `box` because `lib/syntax_demo_test.mc`
     already declares a global `box`, and a `syntax` registration reserves its word program-wide)
     declares two members carrying a default at the **same** parameter index with different
     values; `--dump-ast` shows `INT val=10` in one call and `INT val=30` in the other and the
     program exits 42. With the `p_set_decl_name` line commented out, the same source dies with
     the module's own `a default parameter needs a named declaration`.
  3. **The documented message text was missing its detail** (LOW). All four
     `consumed no tokens` messages are `err_at2` calls and print `: <word>`;
     `docs/reference/diagnostics.md` wrote all four without it. The four rows -- plus
     `syntax_expr handler produced no expression` and `syntax_infix handler produced no
     expression`, `err_at2` too -- now carry the suffix, so the table matches the runtime.
  New: `tests/err/073-param-consumed-zero.mc` (the arity repro itself: the source that used to
  compile clean and exit 42) and `tests/err/074-lit-consumed-zero.mc`, each asserted with its
  exact message in `scripts/check-surface.sh`, which also gained the `capsule` case and its two
  `--dump-ast` assertions and now refuses all three `syntax_param` sources with the default
  compiler. `lib/user_syntax_demo.mc` +79/-2: `sd_peat`, `sd_leat`, `sd_capsule`.
  -- `make bundle` re-run BEFORE bootstrapping (77 files, raw 802395 -> LZ 375334, blob 376268 B).
  `make check` green end to end (RC 0, zero FAIL): `budget` 2848/3000, `test` 32/32, `check-lex`
  125/125 (2 skipped), `check-ast` 125/125, `check-bundle` (reproducible + fresh, lz round trip
  101 cases), `check-asm` 125/125, `check-obj` **32/32 identical to the frozen seed**, `bootstrap`
  at a fixed point (`mc2.o == mc3.o`, 864584 bytes; the `--dump-asm` diff between `mc1` and `mc2`
  is **empty**), `check-surface` 32/32 + 109 ok lines (every M21/M24/M31/M41.5 case plus the four
  new ones) + inert, `test-exe` 32/32, `check-mc` 7/7, `check-standalone`, `check-toml` 10/10,
  `check-build` 29/29, `check-stubs` 9/9, `check-limits` 17/17 under 90%, `check-minimal`,
  `test-linux` 33/33, `test-linux-x86_64` 30/30, `test-windows` 35/35 + `test-windows-x86_64`
  33/33 objects cross-compiled, `check-examples`, `check-lang`, `check-conc`, `check-desktop`,
  `check-float`, `check-wide`, `check-kernel` (QEMU 11.0.1, `build/kernel.bin` 3304 B),
  `check-docs` (181 symbols, 19 flags, 17 TOML keys, 10 directives, 47 samples, 247 links),
  `site` 81 pages + `check-site` (0 link problems). `scripts/check-inert.sh` between a `build/mc1`
  built from the rebased HEAD before the edit and the one after: **33 objects identical**
  (`tests/*.mc` + `src/mc.mc`) and the five taught examples identical too
  (`examples/api`, `lang`, `conc`, `desktop`, `kernel`).
  `make check-linux-host` green for both architectures (RC 0), each after its own
  `mc2l.o == mc3l.o` and with the cross proof (`mc2l --backend=macho src/mc.mc` byte for byte the
  macOS `build/mc2.o`) green on both.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `0883ef0c...30bae1` -> `6766ee56750f9a8f5337f8d901d4196e114477c0552812cc1d34694ab574a5a4`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted
  and re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `eda566cd2559486324a5199e80e80f9770002ba556e4e657f11ab2ece07e5af9`,
  `mc2-linux-x86_64.sha256`
  `a95ec2516cffe9059456a3a1d0863ba91b5dda6efa435bd06016804b4023ea59`; the Windows pair
  cross-computed per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `96841b9071b542a8f7b5bd83106b8f7209a18dfc3fccbbf56718c23a665cf2d9` (880099 B),
  `mc2-windows-x86_64.sha256`
  `0163654105ea20cf13faf88203a7fecefa7ff41664f20ed5f0d5b8737fdd5e73` (898911 B), both also
  produced byte for byte by `build/mc2`.
- M42 done (`docs/specs/M42.md`, incl. its new § Implementation notes): **`elf-exe` and
  `elf-exe-x86_64` -- a dynamic ELF64 `ET_EXEC` writer, so `--exe` works on Linux and a Linux
  `mc build` needs no `[linker]` and no sysroot.** `stage0/` untouched (2848/3000).
  `src/backend_elf_exe.mc` (956 lines, ~500 of them code) is to `src/backend_elf.mc` what
  `src/backend_exe.mc` is to `src/macho.mc`: the same `gen_lower` + `gen_encode_all` in front,
  the same sections/symbols/relocations behind, and then instead of handing the relocations to
  `ld.lld` it lays out the segments, resolves everything in place and writes the loader's tables.
  `ET_EXEC` at `0x400000` (not PIE: no `R_*_RELATIVE`, and no ASLR -- documented, priced as a
  follow-up); `DT_BIND_NOW` + `DF_1_NOW` (no lazy binding, no PLT0, no resolver); `PT_PHDR`,
  `PT_INTERP`, one `PT_LOAD` per Mach-O segment name (the grouping `backend_exe.mc` already uses,
  so a `#section` with its own segment gets its own load), `PT_DYNAMIC`, `PT_GNU_STACK` **RW and
  never X**; `p_align` 64 KiB on aarch64 and 4 KiB on x86-64 (§ Risks 3). One PLT stub
  (`adrp x16 / ldr x17 / br x17 / nop`, or `jmp qword ptr [rip+got] / int3 / int3`) and exactly
  one 8-byte GOT slot per import; a real SysV `DT_HASH` (`nbucket = nchain = 1 + imports`).
  **`JUMP_SLOT` is the only dynamic relocation kind in the file**: a reference to an import -- a
  call, and equally `&write` in an expression (the global-initializer form the spec first cited,
  `uptr p[] = { &write }`, is not syntax this language has: it is `initializer must be constant`)
  -- resolves in place to its stub, which is the canonical address a
  linker gives an imported function in a non-PIE executable, so no `GLOB_DAT` is needed (mc
  imports functions, never data). Relocations are patched with `backend_exe.mc`'s four patchers:
  they encode instructions, and an instruction has no file format.
  **The static case is the degenerate case, decided by COUNTING imports and never by a flag**:
  with none there is no `PT_INTERP`, no `PT_DYNAMIC`, no `.dynsym`/`.dynstr`/`.hash`/`.rela.plt`,
  no PLT and no GOT.
  Deviations, all in § Implementation notes: **section headers ARE written** (plus a full
  `.symtab`/`.strtab` with final addresses -- no loader reads them, but `llvm-readelf`, `llvm-nm`,
  `llvm-objdump -d` and a debugger do); the **entry point** is the program's own `_start` when it
  has one (`<sys_linux>`) and otherwise a synthesized `.text.mcstart` -- 7 AArch64 instructions
  (28 B) or 34 x86-64 bytes -- that reads argc/argv/envp off the entry stack, calls `main` and
  exits by **raw `exit_group` syscall**, so it costs no import; both segments are page-padded in
  the file so `p_offset == p_vaddr (mod p_align)` holds by construction; `DT_NEEDED` is emitted
  for the default library even when every import is claimed by a `#dylib`, as `macho-exe` always
  emits `LC_LOAD_DYLIB` for libSystem.
  **Two TOML keys, not one** (decision 6 asked for the interpreter path; glibc needs a second
  name): `[target].interp` and `[target].libc`, musl by default
  (`/lib/ld-musl-<arch>.so.1`, `libc.so`), glibc one config line away
  (`/lib/ld-linux-aarch64.so.1` or `/lib64/ld-linux-x86-64.so.2`, `libc.so.6`). `src/driver.mc`
  reads them into two globals declared in `src/objmodel.mc` and NOT in the writer, because
  `<mc/core_build>` may be assembled without `<mc/core_writers>` and must still compile
  (`scripts/check-parts.sh` § 1b).
  One more core edit, forced: `lim_seeds[T_BACKENDS]` 8 -> 16 in `src/arena.mc`, because that
  table is full before the pre-scan can size it (every built-in is registered from `main()`) and
  `<mc/core_writers>` now registers eight, so `examples/kernel` reported `grew`. Capacity only.
  `mc limits src/mc.mc` says `backends 0 16 8 0 ok`.
  **`--exe` is NOT this milestone's edit any more**: the post-M41 review batch (#15) already made
  `src/cli.mc` resolve the host pair through the `target()` registry, after `user_init()`, and
  refuse a 0 slot; M42's own first draft resolved it during argv parsing (before `user_init()`,
  so a module's registration was silently ignored) and was dropped in the rebase. What M42 changes
  is only which slots are non-zero -- the two Linux ones -- and `tests/proj/noexe.mc`, which
  re-registers the host pair with 0 in the exe slot, still passes.
  Gates: `scripts/test-linux.sh` gained an **`--exe` mode** beside the object+link mode -- same
  corpus, same Docker oracle, both architectures, both split halves (`--build-only` writes
  executables, `--run-only` just runs them) -- which **moves `~/.mc/sysroots/linux-*` and
  `build/sysroot/linux-*` aside for the duration and puts them back**, so the no-sysroot claim is
  proved by the script and not by the report. It adds four assertions the object mode cannot make:
  `013-putnum` shows `PT_INTERP` + `DT_NEEDED` + a `JUMP_SLOT` and `001-return42` shows none of
  the three, `GNU_STACK` is RW and never E on every binary, and two builds are `cmp`-identical.
  `tests/linux/071-errno-malloc.mc` goes past the § 0 probe: a failing libc call whose `errno` it
  reads (TLS) plus `malloc` and stdio, run under **musl (`alpine:3` 3.24.1) AND glibc
  (`ubuntu:latest` = Ubuntu 26.04 LTS, glibc 2.43) on both architectures -- `errno=2 malloc ok`,
  exit 0, four for four**. It uses `fopen` and not `open`, but NOT for the reason first written
  here: the claim that glibc's failing `open` hands back `0x00000000ffffffff` was **re-measured on
  all four cells and does not reproduce** -- every one of them returns `0xffffffffffffffff` and
  `fd >= 0` is false. What survives is that both ABIs leave the bits above a 32-bit return value
  unspecified and mc has no narrow return types, so the hazard is latent; `fopen` is kept because
  it returns a full pointer and drags stdio in, which is more start-up state to prove.
  `scripts/test-exe.sh` is host-aware (`codesign` only on macOS, `// skip-<host>` honoured), so
  **`make check` on a Linux host runs `test-exe`** -- the whole suite through `mc --exe`, natively.
  `scripts/check-build.sh` lost the `linux requires [linker]` diagnostic (it is gone for Linux and
  still there for Windows) and gained `tests/proj/linux-exe.toml` / `linux-exe-x86.toml`: both
  architectures asserted down to `e_type`/`e_machine` with `od`, plus determinism -- **31/31**
  with the post-M41 cases.
  `Makefile`: `test-linux-exe` and `test-linux-x86_64-exe` inside `make check`, guarded on Docker
  alone. `.github/workflows/ci.yml`: the macOS job cross-compiles both `--exe` suites into the new
  `linux-arm64-exes` / `linux-x86_64-exes` artifacts and each Linux leg runs them with nothing
  linked.
  **Both libcs, everywhere** (post-merge review): `scripts/test-linux.sh` gained `--libc musl`
  (default, `alpine:3`) and `--libc glibc` (`ubuntu:latest`), which writes `[target].interp` /
  `[target].libc` into the generated config and picks the container; `native` now also asks
  whether the host HAS that loader, so a glibc runner falls back to Docker for the musl set
  instead of failing on `no such file or directory`. Without this the new CI legs -- which run
  `--exe --run-only` NATIVELY on the Ubuntu runners -- would have failed on every binary:
  reproduced under `ubuntu:latest`, `exec ...: no such file or directory`, exit 255. Both
  Makefile targets run both libcs and the CI legs run the glibc set natively and the musl set in
  `alpine:3`.
  **`mc --exe` still writes musl** and cannot be told otherwise: the two names are TOML keys and
  the writer's default is a constant, because a probe of the machine would make one source produce
  different bytes on two hosts (`docs/determinism.md`). That is written down in
  `docs/specs/M42.md` § Implementation notes 12, in `docs/reference/cli.md` and in
  `docs/guide/90-linux-host.md` § 3, and the three scripts that need a runnable binary on the host
  --  `scripts/test-exe.sh`, `scripts/build-exe.sh` and `scripts/bootstrap-linux.sh` -- take the
  `mc build` road when the loader on the disk says the host is glibc, and say which road they
  took. Measured: `test-exe.sh` is **31/31 via `mc build`** inside `ubuntu:latest` and **31/31 via
  `--exe`** inside `alpine:3`, with the same glibc- and musl-hosted compilers.
  **The self-hosting proof**: `src/mc.linux-aarch64.toml` and `src/mc.linux-x86_64.toml` DROPPED
  their `[linker]` and `[sysroot]`, and `make mc-linux` / `mc-linux-x86_64` no longer depend on
  `sysroot-linux` -- cross-building `mc` for a Linux host from macOS now needs nothing installed.
  `make check-linux-host` now runs **two cells per architecture, one per libc**, and is green for
  all four (RC 0). The musl cell is what it was -- `make check SEED=...` inside `alpine:3` plus
  the cross proof. The glibc cell is new (post-merge review, the owner's "dynamic support even if
  only in tests" applied to the COMPILER): `src/mc.linux-{aarch64,x86_64}-gnu.toml` cross-build
  `mc` for a glibc host from macOS -- the musl config plus `interp` and `libc`, nothing else --
  and inside `ubuntu:latest` **with nothing installed in the container** (no `make`, no `lld`, no
  `musl-dev`) `scripts/bootstrap-linux.sh --libc glibc` takes it to its own fixed point, runs the
  whole suite through `mc --exe`, and does the same cross proof.
  `scripts/bootstrap-linux.sh` gained `--exe` and `--libc` for that: with them every stage is
  written by the previous compiler through `mc build` and there is no linker in the chain at all.
  Its default is unchanged -- `ld.lld` plus the musl sysroot -- because the SEED may be a
  published release older than M42.
  **The golden is the same file on both roads**: an ELF `ET_REL` records no interpreter, so the
  musl chain and the glibc chain must write the same `mc2l.o`, and they do.
  Windows is untouched and still refuses `--exe`; this milestone filled two of the four zero slots.
  -- `stage0/` untouched, 2848/3000 (`git diff origin/main -- stage0/` is empty); `make bundle`
  re-run before bootstrapping (78 files, raw 840956 -> LZ 391459, blob 392412 B;
  `tools/bundle.list` gained `mc/backend_elf_exe`).
  `make check` RC 0, zero FAIL: `test` 32/32, `check-lex`/`check-ast`/`check-asm` 126/126
  (2 skipped), `check-obj` **32/32 identical to the frozen seed**, `bootstrap` at a fixed point
  (`mc2.o == mc3.o`, 917008 B; the `--dump-asm` diff between `mc1` and `mc2` is **empty**),
  `check-surface` 32/32 + inert, `test-exe` 32/32 via `--exe`, `check-mc` 7/7,
  `check-standalone`, `check-parts`, `check-toml` 10/10, `check-build` **31/31**, `check-stubs`
  9/9, `check-sysroots`, `check-limits` 17/17 under 90%, `check-minimal`,
  `test-linux` 34/34 + **`test-linux-exe` 37/37 musl and 37/37 glibc**,
  `test-linux-x86_64` 31/31 + **`test-linux-x86_64-exe` 34/34 musl and 34/34 glibc**,
  `test-windows` 35/35, `test-windows-x86_64` 33/33, `check-examples`, `check-lang`, `check-conc`,
  `check-desktop`, `check-float`, `check-wide`, `check-kernel` (QEMU 11.0.1), `check-docs`
  (183 symbols, 19 flags, 19 TOML keys, 10 directives, 47 samples, 261 links), `site` 82 pages +
  `check-site` 0 link problems. `scripts/check-inert.sh` between a `build/mc1` built from
  `origin/main` and this one: **identical everywhere** (33 objects including `src/mc.mc`, and the
  five taught examples -- api, lang, conc, desktop, kernel).
  `make check-linux-host` RC 0 over all four cells: fixed point `mc2l.o == mc3l.o`
  (1161024 B on aarch64, 1076360 B on x86_64), the musl cells' `make check` with
  `test-exe` 31/31 and 29/29 and `check-obj` 31/31 and 29/29, the glibc cells' suites 35/35 and
  32/32 natively through `mc --exe`, and the cross proof on all four.
  All five goldens rewritten, each only after its own criterion: `mc2.sha256`
  `d73a2861...e849b79b` -> `7baa684a571a2cb4ed95c025a00ae813314b1cbd055623961b2015e69bc9b2c5`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`);
  the Linux pair deleted and re-recorded by `make check-linux-host` --
  `mc2-linux-arm64.sha256` `af2bbca7118274b64b1abb497999586a9c68dec118d84377d153bc6f09de000d`,
  `mc2-linux-x86_64.sha256` `978be8d6fa896601fd495bdec58b3f6941d135867613de05cde6db9ccb1a9724`,
  each verified a second time by the glibc cell of its architecture;
  the Windows pair cross-computed per `tests/golden/README.md` --
  `mc2-windows-arm64.sha256` `dc900682e98b6af721692ba95f10a5590d8f5007bca7a68db63c4c13dfa420b4`
  (934590 B), `mc2-windows-x86_64.sha256`
  `20f22777b8e907407b6b7a4938e3bf0a37555af364fbff6a1295beeb41248788` (953722 B), both also
  produced byte for byte by `build/mc2`.
  Docs: `docs/reference/objects.md` § 8b (new, the layout field by field with the `llvm-readelf`
  cross-check), `docs/reference/toml.md` § `[target]`, `docs/reference/cli.md`,
  `docs/reference/bundle.md`, `docs/build.md` § Linux targets (rewritten),
  `docs/guide/50-cross-compile.md`, `docs/guide/90-linux-host.md` § 3 (rewritten),
  `docs/bootstrap.md` (the standalone claim now says on which hosts it holds -- and, since the
  post-merge review, that `ld-musl-<arch>.so.1` exists only on musl distributions and the default
  is a CHOICE), `docs/ci.md`.
  Post-merge review, all of it recorded in `docs/specs/M42.md`: the `--exe` draft dropped for
  `main`'s (a), `lim_seeds[T_BACKENDS]` reconciled BY NAME after M41.5 inserted `T_SYNPARAM`
  before it -- index 31, not 30, and a textual merge would have put the 16 on `syntax_param` with
  no conflict to show for it (b), the two libcs everywhere (d), `ubuntu:latest` (26.04, glibc
  2.43) as the glibc oracle in place of `debian:bookworm-slim` and the four-cell run redone on it
  (e), the compiler itself built dynamically against glibc and taken to its own fixed point (f),
  note 5's unreachable `uptr p[] = { &write }` corrected (g), and note 10's `open` claim
  re-measured and **not reproduced** (h).
- Post-M42 patch (owner's two decisions, 2026-09-04; `docs/specs/M42.md` note 12 CLOSED,
  `docs/build.md` § Linux targets): **the target belongs to the developer -- one vocabulary for
  the Linux matrix, and `mc --exe` can say it.** `stage0/` untouched (2848/3000, `git diff main --
  stage0/` empty).
  1. **`[target].libc` stopped being a soname and became a FAMILY**: `gnu` or `musl`, and the
     family names the `PT_INTERP` path and the `DT_NEEDED` soname TOGETHER (`gnu` ->
     `/lib/ld-linux-aarch64.so.1` or `/lib64/ld-linux-x86-64.so.2` + `libc.so.6`; `musl`, the
     default -> `/lib/ld-musl-<arch>.so.1` + `libc.so`). They always travel together and a file
     that names them one at a time is a file that can name half a libc. The M42 spelling is
     refused WITH the migration in the message -- `libc must be gnu or musl (a soname is not a
     value: gnu is libc.so.6, musl is libc.so)` -- and the two configs that used it,
     `src/mc.linux-<arch>-gnu.toml`, each lost a key. `[target].interp` stays as the explicit
     loader-path override.
  2. **`[target].link = "dynamic" | "static"`** is new. `static` does NOT select the static image
     -- the import count still does, exactly as M42 wrote it -- it **asserts** it: a program that
     imports a libc symbol is refused with `static link with a libc needs [linker]: see
     docs/build.md -- static linking (M46)` instead of being handed a dynamic binary it did not
     ask for. With a `[linker]` present the driver takes the object+linker road as before and the
     key never reaches the writer.
     The refusal is raised by the WRITER (only the import set answers it) and reported at the
     KEY's `file:line:col` -- `dyn_die(key, msg)` in `src/objmodel.mc` calls a reporter the
     driver installs (`dyn_err_fn = &toml_err_key`) and falls back to `die()` on the CLI road.
     A writer must not know what TOML is and a `mc.toml` diagnostic must not lose its position;
     this is the one line that satisfies both.
  3. **Three CLI flags mirror the three keys**: `--libc=gnu|musl`, `--link=dynamic|static`,
     `--interp=PATH` (`src/cli.mc`), last one wins. **No probe of the host, ever** -- the default
     stays the constant musl, because one source must give one answer on every machine
     (`docs/determinism.md`); the probing belongs to the SCRIPTS. Off Linux, with no `--backend=`
     naming a writer, each is refused (`mc: --libc applies to a linux target`) rather than
     ignored. The TOML refusal uses the same condition, `[target].os != linux && host != linux`
     -- not `[target]` alone -- because a taught compiler is a binary for the HOST, so on a Linux
     host the keys still describe the compiler `mc build` writes.
  4. **One vocabulary everywhere.** `scripts/test-linux.sh`, `scripts/bootstrap-linux.sh` and
     `scripts/check-linux-host.sh` take `--libc musl|gnu`; the value `glibc` is refused with the
     rename spelled out. `scripts/test-exe.sh` and `scripts/build-exe.sh` LOST their `mc build`
     detour entirely (-46 lines between them): they are `mc --exe --libc=$(probe)` now, which is
     what decision (1) was for. The Makefile and `.github/workflows/ci.yml` pass `--libc gnu`.
  -- core cost: `src/objmodel.mc` +48/-11 (24 code), `src/driver.mc` +40/-10 (19 code),
  `src/cli.mc` +33/-2 (20 code), `src/backend_elf_exe.mc` +26/-8 (9 code).
  New: `tests/proj/lin-libc.mc` and four configs (`linux-musl`, `linux-gnu`, `linux-static`,
  `linux-static-linker`); `scripts/check-build.sh` +217 lines -- **the whole matrix, both roads,
  with no Docker**: musl/dynamic and gnu/dynamic built and read with `llvm-readelf` (`PT_INTERP`
  + `DT_NEEDED`), none/static with neither program header, gnu|musl/static through `[linker]`
  (object + spawn, `echo` standing in for `ld.lld`), the four CLI cases (`--libc=gnu`,
  `--libc=musl`, `--interp=` overriding, the last flag winning) and seven refusals verbatim.
  `make check-build` 21/21 -> **47/47**.
  -- `make bundle` re-run before bootstrapping (78 files, raw 848230 -> LZ 395264, blob 396217 B).
  `make check` green end to end (RC 0, zero FAIL): `test` 32/32, `check-lex` 126/126 (2 skipped),
  `check-ast`/`check-asm` 126/126, `check-obj` **32/32 identical to the frozen seed**,
  `check-bundle`, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 925176 B; the `--dump-asm` diff
  between `mc1` and `mc2` is **empty**), `check-surface` 32/32, `test-exe` **32/32 via `--exe`**,
  `check-mc`, `check-standalone`, `check-toml`, **`check-build` 47/47**, `check-stubs`,
  `check-limits` 17/17 under 90%, `test-linux` 34/34 and `test-linux-x86_64` 31/31, the four
  `--exe` cells **37/37 (aarch64 musl, alpine:3), 37/37 (aarch64 gnu, ubuntu:latest), 34/34
  (x86_64 musl) and 34/34 (x86_64 gnu)**, `test-windows` / `test-windows-x86_64`, `check-float`,
  `check-wide`,
  `check-examples`, `check-lang`, `check-conc`, `check-desktop`, `check-kernel`, `check-avr`,
  `check-docs` (183 symbols, 22 flags, 20 TOML keys, 10 directives, 47 samples, 277 links),
  `site` 84 pages + `check-site` (0 link problems, 84 files 0 problems, 50 contrast pairs 0 below
  the minimum). `scripts/check-inert.sh` against a `build/mc1` built from `main`: **33 objects and
  all five taught examples byte-identical** -- the keys and the flags are inert when nobody writes
  them. `make check-linux-host` RC 0, all four cells: fixed point `mc2l.o == mc3l.o` on both
  architectures under musl AND under gnu, the suite native through `mc --exe` (35/35 aarch64,
  32/32 x86_64 on the gnu cells) and the cross proof against the macOS `build/mc2.o` in each.
  The five goldens rewritten once, each only after its own criterion: `mc2.sha256`
  `7baa684a...b2c5` -> `2b919a15f9509a10c6a26e795a9107b8cff8c064077895132de27c75f9913601`, the
  Linux pair deleted and re-recorded by `make check-linux-host`
  (`d899ec57...8117`, `d1fa7e6c...deb9`) and the Windows pair cross-computed per
  `tests/golden/README.md` (`0ea0599b...d97c`, `c5364e3a...74d3`).
- Post-M42 review (2026-09-05, two findings from the PR review, one gated commit;
  `docs/specs/M42.md` note 12 § Reviewed again): **a flag that is read by nobody is refused, and
  the "Linux has no direct executable" row is retired.** `stage0/` untouched (2848/3000,
  `git diff origin/main -- stage0/` empty).
  1. **The three flags were accepted on the OBJECT road and did nothing.** The patch's gate was
     `linkflag && bname == 0 && host != linux`, so a Linux host took `mc x.mc -o x.o --libc=gnu`
     and every host took `--backend=elf-obj --libc=gnu`. Reproduced before the fix with `cmp`:
     the object built with the flag and the object built without it are **byte for byte
     identical** (`--libc=gnu`, `--interp=`, `--link=static`, all three). Only
     `src/backend_elf_exe.mc` reads `dyn_libc`/`dyn_interp`/`dyn_static` -- `PT_INTERP` and
     `DT_NEEDED` are program-header fields and an object has neither.
     The gate is now three questions in `src/cli.mc`, moved to just after `user_init()`:
     `applies to an executable: a --dump-* mode writes none` (a dump returns before any backend,
     with or without `--exe`), `applies to an executable: use --exe` (the object road), and the
     original `applies to a linux target` (`--exe` off Linux). What counts as an executable writer
     is asked of the TARGET REGISTRY, never of the name: **`backend_is_exe(name)`**
     (`src/hooks.mc`) is 1 when some `target()` names it in its exe slot, so a target a
     module registered from `user_init()` answers for its own writer -- which is why the gate had
     to move after `user_init()`, and the price of the move is that an unreadable entry reports
     `cannot open` first (the same trade M39.5 accepted for `[target]`).
     `src/cli.mc` +33/-9 (8 code) and `src/hooks.mc` +23/-0 (10 code).
     `scripts/check-build.sh` +59/-10, **47/47 -> 53/53**: six refusals
     verbatim (the three flags on `--backend=elf-obj`, the default road with neither `--exe` nor
     `--backend=`, and a dump mode with and without `--exe`), plus, on a Linux host only, the two
     positives `--exe --libc=gnu` -> `libc.so.6` and `--exe --libc=musl` -> `libc.so`. The
     `--backend=elf-exe --libc=…` cases are unchanged and still pass.
     Verified on a real Linux host (`alpine:3`, linux/arm64, `build/mc-linux-arm64`): the object
     road is `mc: --libc applies to an executable: use --exe` (exit 1), the dump road is
     `mc: --libc applies to an executable: a --dump-* mode writes none` (exit 1), and
     `--exe --libc=gnu` writes `/lib/ld-linux-aarch64.so.1` + `libc.so.6` while `--exe
     --libc=musl` writes `/lib/ld-musl-aarch64.so.1` + `libc.so` and RUNS (`hi`, exit 0).
     On record: `--backend=macho-exe --libc=gnu` is still accepted and ignored -- an exe slot
     answers yes, and a Mach-O executable has no interpreter to name. That is the boundary the
     accept condition draws, and it is documented.
  2. **`linux requires [linker]: there is no direct executable` retired as a Linux fact.** Since
     M42 filled the two Linux exe slots the message belongs to any target whose exe slot is 0 --
     `windows/aarch64` and `windows/x86_64` today, or `target(os, arch, obj, 0)` from a module.
     `docs/reference/diagnostics.md` § 10's row rewritten as `<os> requires [linker]: …`, § 9's
     sibling row corrected (`linux` was on that list), and three more stale places found by the
     same grep: `docs/reference/hooks.md` § `target()` still showed
     `target("linux", "aarch64", "elf-obj", 0)` in its code sample and called `exe = 0` "what
     `os = "linux"` and `os = "windows"` do", and `docs/guide/90-linux-host.md` still told the
     reader to run `scripts/bootstrap-linux.sh --libc glibc` and `test-linux.sh --exe --libc
     glibc` -- a value those scripts REFUSE since the patch commit -- and still said `mc --exe`'s
     interpreter "cannot be told otherwise from a command line". Also documented: the new
     refusals in `docs/reference/cli.md` (a three-row table), `docs/build.md` § the matrix,
     `docs/guide/50-cross-compile.md` § the object road, and `backend_is_exe` in
     `docs/reference/hooks.md`.
  -- `make bundle` re-run before bootstrapping (78 files, raw 850657 -> LZ 396299, blob 397252 B).
  `make check` green end to end (**RC 0, zero FAIL**, 5m08s): `test` 32/32, `check-lex` 126/126
  (2 skipped), `check-ast`/`check-asm` 126/126, `check-obj` **32/32 identical to the frozen
  seed**, `check-bundle`, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 926848 B; the
  `--dump-asm` diff between `mc1` and `mc2` **empty**), `check-surface` 32/32, `test-exe` 32/32
  via `--exe`, `check-mc` 7/7, `check-standalone`, `check-toml` 10/10, **`check-build` 53/53**,
  `check-stubs` 9/9, `check-limits` 17/17 under 90%, `test-linux` 34/34 and `test-linux-x86_64`
  31/31, `test-windows` 35/35 and `test-windows-x86_64` 33/33 objects, `check-float`,
  `check-wide`, `check-examples`, `check-lang` 18, `check-conc` 21, `check-desktop`,
  `check-kernel`, `check-avr`, `check-docs` (**184** symbols, 22 flags, 20 TOML keys, 10
  directives, 47 samples, 281 links), `site` 85 pages + `check-site` (0 link problems).
  `scripts/check-inert.sh` against a `build/mc1` built from `origin/main`: **33 objects and all
  five taught examples byte-identical** -- the new gate refuses only what the old one accepted and
  ignored. `make check-linux-host` RC 0, all four cells (musl and gnu x aarch64 and x86_64):
  fixed point `mc2l.o == mc3l.o` in each, the suite native through `mc --exe` and the cross proof
  against the macOS `build/mc2.o`.
  The five goldens rewritten once, each after its own criterion: `mc2.sha256`
  `2b919a15…3601` -> `61404319507a811f17d464062670096152ff5c2c08e3607bf2dc14d66a6653f2` (after
  the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`), the Linux pair deleted and
  re-recorded by `make check-linux-host`
  (`54a31181bff8483b493415643de1ce3371c3157aea553ec406204e7b6e8334b6` and
  `d1cdca0320413cb4abd74750e6efc1b54154dfe8dabaca01178b2af68a1e9dfe`, each inside its own
  container and only after its own fixed point) and the Windows pair cross-computed per
  `tests/golden/README.md`
  (`fdaa573611f5c90677d799346173114ff50a4fb3435ba0d1ef65a75e98dbc75e` and
  `63962f990b853564a4926d1216a25e017faa47477477af5e84c7c506e18ef32b`, and `build/mc2` writes both
  byte for byte as `build/mc1` does).
- M45 step 1 (the mechanism) ✔ (`docs/specs/M45.md` § Amendment + § Implementation notes):
  **`i32`, and a call returns what it declares** -- the mechanism half, INERT. `stage0/` untouched
  (`git diff stage0/` empty).
  * **`i32` is registered by the core, not a keyword.** `core_types_init()` (`src/hooks.mc`) calls
    `type_new("i32", 4, 4, TK_SINT)` before `user_init()`, so the word arrives through exactly the
    M24 mechanism a module uses -- the alias table, `word_add`, `type_of_token`'s last arm --
    `TY_MAX` stays 7, `tok_init` is untouched and `src/lexdump.mc` still lexes `i32` as identifier
    1, byte for byte what the frozen `stage0/lex.c` does. **Three call sites, not the one the spec
    named**: `mc build` (`src/driver.mc`) and `mc limits` (`src/limits.mc`) run their own
    tok_init/lex_init/user_init and would otherwise leave `ty_i32` at 0 -- found by
    `type_disable(ty_i32)` in `examples/avr` disabling `TY_VOID`.
  * **`TK_SINT`, a fifth kind**, appended so `TK_INT..TK_OPAQUE` keep 0..3, and
    `type_signed(t) = t == TY_I64 || type_kind(t) == TK_SINT` (`src/ast.mc`) as the ONE place
    signedness is written down. The core now reads `kind` in exactly three places -- `type_signed`,
    `fold_taught` and `walk_narrow` -- and nothing tests an id. What that buys is measured, not
    asserted: `type_new("i16", 2, 2, TK_SINT)` in `lib/user_syntax_demo.mc` is **one line** and
    gets `ldrsh`, `sxth`, signed `/ % >>`, a signed comparison and a narrowed call result.
  * **The fold guards key on kind (D17).** `fold_taught` is `k != TK_INT && k != TK_SINT`, and
    `fold_cast`'s three masks became a width-and-kind rule (byte-identical for `u8`/`u16`/`u32`).
    So `fix` -- `lib/user_syntax_demo.mc`'s `TK_INT` -- now folds like a core literal, which is
    what `check-surface`'s M24 fold case asserts; the non-folding half moved onto `<float>`'s
    `f64` (`fadd`/`fneg`/`fcmp` all survive) in the same case.
  * **The walker narrows through the existing `MTASK_CAST`, no new slot** (D4/D5/D7'):
    `walk_narrow(t)` admits a `TK_INT`/`TK_SINT` of width < 8 except `uptr`, and `gen_call` issues
    `set_walk_depth_type(depth, rt)` + `MTASK_CAST(rt, depth)` after `MTASK_CALL`, `N_RETURN`
    issues one before `MTASK_RET` from `walk_fn_ret`. The `set_walk_depth_type` line is
    load-bearing and was proved so: without it `extern i32 ilogb(f64 x)` lowers as
    `fcvtzu x9, d16` -- a float register that never held the value -- and with it as `sxtw x9, w9`
    (`tests/float/022-int-return.mc`). **Deviation:** the RETURN side does NOT rewrite the depth
    type before its cast, only after; there `dtype[0]` already describes the value `gen_value`
    produced, which is the SOURCE a derived machine needs.
  * **Contract version 4** (`docs/reference/machine.md`): no slot, no signature change. The bump
    is the obligation -- every `ty`-carrying slot dispatches on `type_width` and `type_kind`,
    never on the id; zero-fill for `TK_INT`, sign-fill for `TK_SINT`; a machine that will not
    implement it says `type_disable(ty_i32)`. Four machines updated: `src/machine_arm64.mc`
    (`I_LDRSB/LDRSH/LDRSW`, `I_SXTB/SXTH/SXTW`), `src/machine_x86_64.mc` (`X_LDS8/16/32`,
    `X_MOVSXB/W/D`, both forms), `lib/backend_arm64.mc` (the surface encoder, same rows) and
    `examples/kernel/machine_riscv64.mc` (`lb`/`lh`/`lw`, `srai` through a new funct6 column,
    `sext.w` as `V_ADDIW`); `examples/avr/mc-avr.mc` calls `type_disable(ty_i32)` instead.
  * **Acceptance 1 was MEASURED before anything changed** and is in `docs/specs/M45.md`
    § Implementation notes 1. `open`/`close(-1)`/`waitpid(-1)` return a full 64-bit -1 on musl and
    glibc, both architectures, and on macOS -- **the spec's `open` claim did not reproduce**. The
    defect class does: `atoi("-1")` is `0x00000000ffffffff` on musl (both arches) and
    `strcmp("a","b")` is on glibc/x86_64, so `< 0` is FALSE through the pre-milestone compiler; on
    macOS an ordinary `int m45_neg(void){return -1;}` compiled by clang (`mov w0, #-0x1; ret`)
    reads back `0x00000000ffffffff` too. That measurement is why `lib/sys.mc` keeps its `i64`
    declarations (§ 5's row, decided by measurement) and why `tests/linux/072` declares three
    functions rather than one.
  — **Inertness is the gate and it held where the milestone claims it.**
  `scripts/check-inert.sh` between the `build/mc1` of `6fab014` and this one: **33 objects
  identical** (`tests/*.mc` + `src/mc.mc`) and `lang`/`conc`/`desktop` identical through the taught
  compiler each builds; `examples/kernel`'s image (3304 B) and `examples/avr`'s ELF compared by
  hand, pre compiler + pre machine against post + post -- **identical** (the script's kernel case
  cannot run across this milestone: the pre compiler's bundle has no `TK_SINT`).
  **Correction (review, 2026-09-05): `examples/api` is a `DIFF`, not an `ok`** -- the entry here
  and `docs/specs/M45.md` § Implementation notes 3 both said `ok` and were wrong. The corpus grep
  that found "no narrow-declared callee anywhere" is over SOURCE TEXT, and a Tier 3 module can
  declare a narrow function without writing one: `examples/api/oop.mc`'s `class` handler builds
  `u8 todo_done(uptr self)` out of AST nodes for the field `bool done;` (`bool` is
  `type_alias("bool", TY_U8)`). D5 then applies on both sides, which is the design. Measured:
  `--dump-asm` of `examples/api/main.mc` through the taught `mc-api` each compiler builds differs
  by **exactly two instructions**, both `and x9, x9, #255` -- one after the `ldrb w9, [x9]` that is
  `todo_done`'s body (the return side, `walk_fn_ret`), one after the `mov x9, x0` that follows
  `bl _todo_done` (the call side, `res_type`). Both are no-ops on the value -- `ldrb` already
  zero-extends -- so `build/api` is the same 55632 bytes and the eleven route checks stay green.
  Read the rule as: the return-side and call-side narrowing move bytes for EVERY narrow-returning
  function, written or synthesized, and a grep over sources cannot enumerate the synthesized ones. Sweep: 16 distinct new instructions re-assemble byte for
  byte under `llvm-mc` on each of mach-o arm64, elf aarch64, coff aarch64, elf x86-64 and coff
  x86-64; `examples/kernel`'s own sweep goes 262 -> 285 with 0 mismatches, plus a scratch run with
  `i8`/`i16` registered (62, 0 mismatches, `lb`/`lh`/`srai` present).
  New: `tests/mc/090-i32-basic.mc`, `091-i32-cast.mc`, `092-i32-div.mc` (`INT_MIN / -1` is
  2147483648 on every machine, no `#DE`), `093-i32-return.mc`, `tests/linux/072-int-return.mc`,
  `tests/windows/073-int-return.mc`, `tests/float/022-int-return.mc`;
  `scripts/test-linux.sh`/`test-windows.sh` run `tests/mc/0[89]*.mc` on every target;
  `scripts/sysroot-windows.sh` gained `GetFileAttributesA`.
  Cost in `src/`: **234 added lines, 128 of them code** (86 of the 128 in the two machines).
  `make check` green end to end (RC 0, zero FAIL, 5m09s), `make check-linux-host` green on both
  architectures with the cross proof. All five goldens rewritten once: `mc2.sha256`
  `7baa684a…9b2c5` -> `77a973a294e24c9ec4df0b95e021dead8525178288371e75a60336a02a87d1b9`,
  `mc2-linux-arm64` `167b37cb6c0b71b0a4d1046700afa5e3a9299337c11b7e22f3ff63af0df9dcdf`,
  `mc2-linux-x86_64` `067cfbc824ec1fbdabdccddee85aab1d454b6945e8dacb4dabe388a98e6087a2`,
  `mc2-windows-arm64` `f778e38a8fcfb32626a0b0f6fa786d6c122bbc8506ba95eb68534369d67e161d`,
  `mc2-windows-x86_64` `73c904a1a70fd5791f78d76b874572c571d42180de53f5878ea500ae7117fa88`.
- M45 step 2 (the declarations) ✔ (`docs/specs/M45.md` § 5 + § Implementation notes 4):
  **the truthful declarations, and the one place D8 did not survive contact with the code.**
  `stage0/` untouched.
  * **D8 as written is incompatible with `check-asm`.** § 5 asks `src/*.mc` and the seed-compiled
    libraries to declare an `int` result as `u32`. Implemented literally, `make check` came back
    **RC 2 with 23 FAILs** and `check-asm` at 103/126: that script compares `mc0 --dump-asm`
    against `mc1 --dump-asm` over `tests/ lib/ src/`, and a narrow declaration makes `mc1` emit a
    `mov w9, w9` the frozen seed has no way to emit -- **27 of them over `src/mc.mc`, and nothing
    else**. Both escapes are closed by the task's own rules (no `seed-skip` in the seed set,
    `stage0/` frozen). Resolution: **D8's own named alternative** -- `c_int()` alone in the seed
    set, `i32` everywhere else. Not weaker: `c_int(v)` is the low 32 bits sign-extended from bit
    31, so it is right whether the callee left the sign there or not, on every host and under
    every seed; what is lost is only that the declaration would have carried the information.
  * `c_int()` in `src/arena.mc` and four call sites: `c_int(open(...))` and `c_int(creat(...))` in
    `read_file`/`write_file`, `c_int(open(...))` in `src/sysroot.mc`, `c_int(creat(...))` in
    `src/backend_exe.mc`, and `c_int(waitpid(...))` at **both** sites in `src/driver.mc` -- the
    same latent defect as `open`, and the one a spawned tool's `pid_t` would hit. The host layers
    and `lib/sys_windows*.mc` keep their declarations with the reason written in a comment; the
    `& BOOL_MASK` masks stay (D9).
  * **`lib/sys.mc` stays `i64` BY MEASUREMENT** (Acceptance 1c), with the numbers in its header:
    libSystem's wrappers hand back a full 64-bit -1 for `open`, `close(-1)` and `waitpid(-1)`.
    The header also says what is not true of an ordinary C function, and
    `docs/reference/language.md` § `extern` says a program wanting the truthful declaration writes
    its own `extern i32 open(...)`.
  * **`i32` where the seed never looks**: `examples/api/lib/sqlite.mc` (11 declarations;
    `sqlite3_last_insert_rowid` stays `i64`), `examples/api/lib/http.mc` (5, and its three `< 0`
    tests are now sound), `examples/api/tests/lib_test.mc`, `examples/conc/lib/{macos,linux}/
    thread.mc` (12 each), `examples/desktop/lib/gtk.mc` + `main.mc` -- where **both `(u32)` casts
    are gone**, because the declaration now says what the cast used to.
    `examples/api/test_sqlite_lib.mc` was left alone and the reason recorded: nothing builds it and
    it does not compile (`call to unknown function` -- `sqlite3_libversion_number` is declared
    nowhere).
  — Measured: `check-inert` between the pre-milestone `build/mc1` and this one keeps **the 33 core
  objects identical** (that is what leaving the seed set alone buys) while `api`/`conc`/`desktop`
  now REFUSE to build under the old compiler, which is the fix; `bl _sqlite3_step` is followed by
  `sxtw x9, w9`; the `--dump-asm` diff over `src/mc.mc` between the two compilers is **empty**, so
  the golden moves because `c_int` is a new function and not because instruction selection did;
  and a pre-M45 compiler -- what a published release is -- produces **byte-identical objects** for
  `src/mc_windows.mc`, `src/mc_windows_x86_64.mc`, `src/mc_linux.mc` and `src/mc_linux_x86_64.mc`,
  so both foreign chains bootstrap from 0.12.0 unchanged. `mc-linux-arm64` (musl) and
  `mc-linux-arm64-gnu` (glibc) both answer `mc: cannot open`, exit 1.
  `make check` RC 0, zero FAIL, `check-asm` back at 126/126 and `check-obj` 32/32;
  `make check-linux-host` RC 0 on both architectures with the cross proof on musl and glibc.
  Goldens rewritten a second time: `mc2.sha256`
  `0c26544589966095fc795ffcf7f7cb0602495229f8bae7f72a35ed64def62fec`,
  `mc2-linux-arm64` `06165599f9de9e3413e4a05e1371fdc26ef02494615d1c1da76916b26beded44`,
  `mc2-linux-x86_64` `02eec99d84119a077c806ca14230bfa58aba63affd4591efbf06b3b54ed94893`,
  `mc2-windows-arm64` `57b2a7e174f6be3f3ca8063d503a8dffc7fd650cbce2e4b83d41ce0540879ce6`,
  `mc2-windows-x86_64` `24b994e706bc37d9533898331da538fdab4814ee1097f78fe04e8ac2e5a2bb45`.
- M45 step 3 ✔ (`docs/specs/M45.md` § Implementation notes 5): **`p_cp()` public** -- the lexer's
  cursor, for a handler that scans raw source forward. Not part of the spec; asked for alongside it
  because the ngen consumer hit it. `p_start()` is where the CURRENT TOKEN starts, and on a token
  `p_subst_name()` replaced, `subst_apply` swaps `tok_start`/`tok_len` for the REPLACEMENT string,
  which lives in the arena -- so a `syntax_lit`-style scan from `p_start()` inside a
  `p_push_source` frame reads the arena lexeme and not the source. One line in `src/parse.mc`
  beside `p_start()`/`p_src_end()`, a row and a caveat paragraph in
  `docs/reference/hooks.md` § Record and replay, and a `check-surface` case
  (`p_cp-under-substitution`) built on three new demo registrations: `srcbyte` (`ld8(p_cp())`),
  `srcbyte0` (`ld8(p_start())`) and `probe NAME;`, which pushes
  `i64 NAME() { return W  * 1000 + V; }` with `W -> srcbyte` and `V -> srcbyte0` so both run on
  SUBSTITUTED tokens. The four numbers: 59 and 115 in ordinary source (where the two positions
  agree), then **32** from `p_cp()` -- the space that really follows `W` in the pushed text -- and
  **115** from `p_start()`, the arena copy of `"srcbyte0"`, where the source holds `V` (86).
  Inert: `check-inert` between the step-2 compiler and this one is identical everywhere, all five
  taught examples included, and the `mc1`/`mc2` `--dump-asm` diff over `src/mc.mc` is empty; the
  goldens move only because `p_cp` is a new function. `make check` RC 0, zero FAIL;
  `make check-linux-host` RC 0 on both architectures. Goldens rewritten a third time:
  `mc2.sha256` `60b21acb8c61fdfea8803c3ec8bda15341ab9aef36f78f6f4425038fafc8db6c`,
  `mc2-linux-arm64` `89fab268edeccb94f86c3b9f98f1d4206464cc40bf0306f4a1a8297cafdae37d`,
  `mc2-linux-x86_64` `68b2c57d1b9ac8787abce3647ac545c70978376247010f7af6fda3637bf12659`,
  `mc2-windows-arm64` `2877458c375b72018b2b9a62d30bb30cd7ee84488a938a1bcacf05653388f3b8`,
  `mc2-windows-x86_64` `97e02abd56e1e11d595d54f2586437f56bb45596e2c0cf2b5a852a5ab2c3629f`.
- Post-M45 batch (review, `docs/specs/M45.md` § Implementation notes 6): the four findings the
  reviewer of the branch raised. One is a correction to the record, one is a documentation gap the
  gate could not see, one is a name that was wrong about the hardware, and one is a real defect a
  consumer hit. `stage0/` untouched (2848/3000). The only compiled change is
  **`src/parse.mc` +15/-2, 3 of the added lines code**.
  1. **The record was wrong about commit 1's inertness in `examples/api`** -- corrected in
     `docs/specs/M45.md` (§ 3 of the Design and § Implementation notes 3) and in the M45 step 1
     entry above, both of which said `ok taught examples/api`. Reproduced first, with `mc1.pre`
     rebuilt from `6fab014` and `mc1` from `9e27e06`: `DIFF taught examples/api -> build/api`. The
     reason is the general one and matters more than the row: **the grep that established "no
     narrow-declared callee anywhere in the corpus" is over SOURCE TEXT, and a Tier 3 module can
     declare a narrow function without writing one.** `examples/api/oop.mc`'s `class` handler
     builds a getter per field out of AST nodes (`oop_getter` -> `oop_func(ty, ...)`), so
     `bool done;` in `class Todo` -- `bool` being `type_alias("bool", TY_U8)` -- is a declaration
     of `u8 todo_done(uptr self)` that no grep over `examples/` can find. D5 then applies on both
     sides, by design. Measured: `--dump-asm` of `examples/api/main.mc` through the taught `mc-api`
     each compiler builds differs by **exactly two instructions**, both `and x9, x9, #255` -- one
     after the `ldrb w9, [x9]` that IS `todo_done`'s body (the return side, `walk_fn_ret`), one
     after the `mov x9, x0` that follows `bl _todo_done` (the call side, `res_type`). Both are
     no-ops on the value, since `ldrb` already zero-extends; `build/api` is the same 55632 bytes.
     What is identical and stays identical: the 33 objects (`tests/*.mc` + `src/mc.mc`), `lang`,
     `conc`, `desktop`, `kernel` and the AVR image. D5 is not weakened -- the cast is the design.
  2. **`c_int` was not in `docs/reference/`.** Acceptance 8 promised it documented; it existed only
     in the spec and in this file, and `scripts/check-docs.sh`'s symbol regex had no prefix that
     reached it. Documented in `docs/reference/language.md` § 6, right after the `extern` rule that
     tells a program to declare `i32` -- with the exact contract (the low 32 bits sign-extended
     from bit 31; correct whether the callee sign-extended, zero-extended or left rubbish above;
     pure arithmetic, so no machine support) and the reason `src/` uses it instead of a narrow
     declaration (the frozen seed cannot spell `i32`, and `u32` would make `mc1` emit an extension
     the seed cannot, which `check-asm` compares over exactly those files) -- and cross-referenced
     from `docs/reference/hooks.md` § The host layer, where the `open`/`creat`/`waitpid`
     declarations it exists for are described. The extraction regex gained `c_`, the same widening
     `on_` and `decl_` got (`docs/specs/M26.md`); `c_int` is the only symbol it adds. Verified in
     both directions: with the two mentions renamed, `check-docs` prints
     `FAIL undocumented public symbols`; with them, `docs ok: 187 symbols`.
  3. **`rv_if7[]` was a funct6.** RV64I's shift-immediate forms take a 6-bit shamt (bits 25:20), so
     the differentiator above it is a funct6 at bits 31:26, not the funct7 the register forms carry
     at 31:25. The one value in the column, `0x20 << 5`, lands on bit 30 -- exactly where
     `0x10 << 6` lands -- so the encoding was right and only the name and the shift were wrong; a
     second, multi-bit value would have been misplaced. Renamed to `rv_if6`/`rv_if6_at`, `0x10`,
     `<< 6` (`examples/kernel/machine_riscv64.mc` +12/-8, all comment but three lines).
     `examples/kernel/build/kernel.bin` is **`cmp`-identical before and after** (3304 bytes, same
     compiler, both machines) and `make check-kernel` is green with QEMU 11.0.1. The kernel corpus
     has no `srai` at all -- it comes only from `rv_cast`'s sign-extension pair, which needs a 1-
     or 2-byte `TK_SINT` -- so the arm was re-proved on the scratch compiler of § Implementation
     notes 3 (`mc-kernel` + `type_new("i16", 2, 2, TK_SINT)` + `i8`): **36 distinct instructions,
     0 mismatches** under `llvm-mc -triple=riscv64 -mattr=+m`, with `srai t3, t3, 48` =
     `135e0e43` and `srai t4, t4, 56` = `93de8e43`.
  4. **`p_skip_balanced` refused a region that ends flush with the end of an included file**
     (reported by the teko/ngen consumer). The frame depth was compared AFTER the lookahead
     `next()` that follows the closing delimiter, and `lex_next` pops an exhausted `#include` frame
     BEFORE it produces a token -- so a perfectly balanced region whose `}` was the include's last
     token left `nopen` one lower and came out as `region crosses a file boundary`. It is now
     sampled at the CLOSER, inside the loop (`i64 dend`), which is exactly the "both delimiters
     live in one buffer" the rule always meant; an `#include` opened and closed inside the region
     still moves `nopen` up and back down and is still fine, and a region that really does cross is
     still refused, with the same message at the same position (the OPENING token). Reproduced
     first: a `tmpl t<T, N> { ... }` alone in `tpl.mc`, `#include`d, was refused at `tpl.mc:1`;
     with the fix it compiles and the program exits 42. Two new cases in
     `scripts/check-surface.sh` -- `p_skip_balanced-include-eof` (compiled with the demo compiler
     and RUN) and `p_skip_balanced-cross` (the message asserted by suffix, since `$TMPDIR` may end
     in a slash and the compiler prints the path it opened, normalized). **The message had no test
     at all before.** Docs: `docs/reference/hooks.md` § Record and replay,
     `docs/reference/diagnostics.md` and `docs/surface.md`.
  -- `make bundle` re-run BEFORE bootstrapping (`src/parse.mc` is `mc/parse`): 78 files, raw
  861794 -> LZ 402157, blob 403110 B. `make check` green end to end (**RC 0, zero FAIL, 5m01s**):
  `budget` 2848/3000, `test` 32/32, `check-lex` 126/126 (2 skipped), `check-ast` 126/126,
  `check-asm` 126/126, `check-obj` **32/32 identical to the frozen seed**, `check-bundle`,
  `bootstrap` at a fixed point (`mc2.o == mc3.o`, 931696 B; the `--dump-asm` diff between `mc1` and
  `mc2` is **empty**), `check-surface` 32/32 + 116 ok lines including the two new ones,
  `test-exe` 32/32, `check-mc` 11/11, `check-standalone`, `check-parts`, `check-toml` 10/10,
  `check-build` 31/31, `check-stubs` 9/9, `check-sysroots`, `check-limits` 17/17 under 90%,
  `check-minimal`, `test-linux` 39/39, `test-linux-x86_64` 36/36, `test-linux-exe` 42/42 musl +
  42/42 glibc, `test-linux-x86_64-exe` 39/39 + 39/39, `test-windows` 40/40 objects,
  `test-windows-x86_64` 38/38, `check-examples`, `check-lang`, `check-conc`, `check-desktop`,
  `check-float`, `check-wide`, `check-kernel` (QEMU 11.0.1, exit 0), `check-docs`
  (**187 symbols**, 19 flags, 19 TOML keys, 10 directives, 48 samples, 275 links), `site` 85 pages
  + `check-site` 0 link problems.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = the branch's HEAD compiler, before these
  edits): **33 objects identical** (`tests/*.mc` + `src/mc.mc`) and all five taught examples
  identical -- `api`, `lang`, `conc`, `desktop` and `kernel`. Item 4 is the only change to a
  compiled byte in `src/`, and it changes no byte the compiler EMITS.
  `tests/golden/mc2.sha256` rewritten once, only after the empty `--dump-asm` diff and
  `cmp build/mc2.o build/mc3.o`: `60b21acb...c8db6c` ->
  `26c9a7c8070e64471bafecfeb42917ba43dec6e2413374a5ea25b0ebc9923c06`. The four foreign goldens are
  deliberately NOT re-recorded here: they move with the same `src/parse.mc` edit and the same
  bundle, and the architect asked for one re-recording after the rebase.
- M45 rebased onto `origin/main` e4a4c40 (PR #21, `[target].libc` as a family) and the five
  goldens re-recorded once, which is the "one re-recording after the rebase" the entry above
  defers to. Six files conflicted and each was resolved by reading both sides: `CLAUDE.md`
  (main's post-M42 entry kept AND the M45 entries after it, M45 last), `docs/specs/M45.md`
  (main's corrected defect paragraph -- the one the spec PR re-measured -- plus this branch's
  § Implementation notes), `src/bundle_data.mc` and the five `tests/golden/*.sha256`
  (regenerated / re-recorded below). `src/cli.mc`, `src/driver.mc`, `src/hooks.mc`,
  `src/objmodel.mc`, `scripts/test-linux.sh`, `docs/reference/{diagnostics,hooks,objects}.md`
  auto-merged and were read to confirm BOTH sides survived: `core_types_init()` at its three call
  sites (`cli.mc:254`, `driver.mc:339`, `limits.mc:586`, each before `user_init()`) next to
  main's `linkflag` gating through `backend_is_exe` and its `dyn_interp`/`dyn_libc` globals; the
  `c_` prefix still in `scripts/check-docs.sh`'s symbol regex; `test-linux.sh` carrying main's
  `--libc musl|gnu` vocabulary with M45's `tests/mc/0[89]*.mc` loop and `072-int-return` written
  in it. `src/arena.mc`'s tag list was checked BY NAME rather than by position (the M42 lesson):
  `T_SYNPARAM 30`, `T_BACKENDS 31`, `T_COUNT 39`, and `lim_seeds[31] = 16` is still on
  `backends` -- only this branch touched the file, so nothing moved.
  -- `make bundle` re-run FIRST (78 files, raw 871568 -> LZ 407042, blob 407995 B), then
  `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test` 32/32,
  `check-lex` 126/126 (2 skipped), `check-ast` 126/126, `check-asm` 126/126, `check-obj`
  **32/32 identical to the frozen seed**, `check-bundle`, `bootstrap` at a fixed point
  (`mc2.o == mc3.o`, 941576 B; the `--dump-asm` diff between `mc1` and `mc2` is **empty**),
  `check-surface` 32/32 + 116 ok lines, `test-exe` 32/32, `check-mc` 11/11, `check-standalone`,
  `check-parts` (the five parts + `<mc/main>` == `<mc/core>`, 941576 B), `check-toml` 10/10,
  `check-build` **53/53** (main's `[target].libc`/`link` cases plus M45's), `check-sysroots`,
  `check-stubs` 9/9, `check-limits` 17/17 under 90%, `check-minimal`, `test-linux` 39/39,
  `test-linux-x86_64` 36/36, `test-linux-exe` 42/42 musl + 42/42 gnu,
  `test-linux-x86_64-exe` 39/39 + 39/39 -- so the M45 corpus (`090..093`, `072-int-return`) runs
  on the `--exe` legs main added, on both libcs -- `test-windows` 40/40 objects,
  `test-windows-x86_64` 38/38, `check-examples`, `check-lang`, `check-conc`, `check-desktop`,
  `check-float` (13/13 macos, 13/13 linux/aarch64, 13/13 linux/x86_64, 11/11 + 11/11 windows
  objects), `check-wide`, `check-kernel` (QEMU 11.0.1, `kernel.bin` 3304 B, exit 0), `check-avr`
  (simavr + QEMU, `avr.elf` 15255 B), `check-docs` (**188 symbols**, 22 flags, 20 TOML keys,
  10 directives, 48 samples, 287 links), `site` 85 pages + `check-site` 0 link problems.
  `make check-linux-host` RC 0 over all four cells -- linux/aarch64 musl (suite 39/39,
  `test-exe` 31/31 via `--exe --libc=musl`, `check-obj` 31/31), linux/aarch64 gnu (40/40
  natively), linux/x86_64 musl (36/36, `test-exe` 29/29, `check-obj` 29/29), linux/x86_64 gnu
  (37/37) -- each after its own `mc2l.o == mc3l.o` and with the cross proof
  (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`) green.
  Inertness against `origin/main` e4a4c40, measured over e4a4c40's OWN tree (the pre compiler
  cannot read this branch's `examples/`, which now declare `extern i32`): **33 objects identical**
  (`tests/*.mc` + `src/mc.mc`), `lang`, `conc`, `desktop` and `kernel` identical through the
  taught compiler each side builds, and `DIFF` on `examples/api` alone -- the two synthesized
  `and x9, x9, #255` of the review batch above, confirmed here by diffing `--dump-asm` of
  `examples/api/main.mc` through each taught `mc-api`: exactly two added instructions, nothing
  else.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `26c9a7c8...923c06` -> `90ce56dcfc6f3c7a785013871b5df9f8ad6ed36ad24acb28256e60385435ee38`
  (empty `--dump-asm` diff + `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` --
  `mc2-linux-arm64.sha256` `8cb319f2648b2a1eb37dcdc19b46290ca111ad7543482fbd349c6c2bcb415856`,
  `mc2-linux-x86_64.sha256` `c0882f93933469e066ba73f461fe2be4caa13de558d09ba534955b0a80e19b93`,
  each recorded in its musl cell and re-verified by the gnu cell of the same architecture;
  the Windows pair cross-computed per `tests/golden/README.md` --
  `mc2-windows-arm64.sha256` `2c55021d3a87ebb087165f77d03fbf8d96f58bb6e4cfb428328f05c909382eab`
  (959407 B), `mc2-windows-x86_64.sha256`
  `af21fe6f17f6d0ca13554b122536178688284f759b990cc8ebb1ccb336ed947f` (978891 B), both also
  written byte for byte by `build/mc2`.
- Post-M45 Windows batch (the four Windows CI legs, `docs/specs/M45.md` § Implementation notes 7):
  the two findings only a Windows runner could see, and the local gate widened so the first of
  them cannot hide again. `stage0/` untouched (2848/3000); nothing in `src/` changed except the
  regenerated `src/bundle_data.mc`.
  1. **`tests/windows/073-int-return.mc` was in the wrong link mode.** `scripts/test-windows.sh`
     put it in the `self` list, and `self` means exactly one thing -- *the source includes
     `<sys_windows>` and therefore must NOT have `winrt.obj` next to it*. 073 deliberately does
     not include the layer (it declares the three kernel32 entry points it uses), but
     `winstart.obj` is in EVERY link line (M20) and its `mc_start` calls `win_setup`/`win_argv`,
     which live in `lib/sys_windows.mc` = `winrt.obj`: `lld-link: error: undefined symbol:
     win_setup` / `win_argv`, on both architectures. It is now a `kernel32` link; its own
     `extern`s resolve from the import library and none of its names (`wr`, `puti`, `nbuf`,
     `nio`, `main`) collides with the layer's. One list, read by both halves of the split through
     `$split/manifest`, so `--build-only` and `--run-only` moved together.
  2. **`close(-1)` answered 0 on Windows and -1 everywhere else.** `lib/sys_windows.mc`'s `close`
     handed anything outside 0..2 to `CloseHandle`, and `(HANDLE)-1` is not only
     `INVALID_HANDLE_VALUE`: it is the **pseudo-handle** `GetCurrentProcess()` returns, and
     `CloseHandle` on a pseudo-handle SUCCEEDS -- so `tests/mc/093-i32-return.mc` printed
     `-1 44 -32768 1 0` where the four other targets print `-1 44 -32768 1 1`. A defect of the
     LAYER, not of the test (a POSIX close of an invalid descriptor is -1/EBADF): `close` now
     refuses a negative descriptor itself, with the pseudo-handle reason on the line.
     `lib/sys_windows_host.mc` needed nothing -- it `#include`s `lib/sys_windows.mc` and has no
     `close` of its own. 093's header carried the false claim in prose and was corrected with the
     fix. **Only the Windows runners can prove the new behaviour**; here it is proved to compile,
     to link in every mode, and to change nothing else.
  3. **The gate.** The default mode of `scripts/test-windows.sh` linked THREE objects out of
     forty -- one per mode -- so a test in the wrong mode was invisible locally. An undefined
     symbol is a property of the pair `(object, mode)` and `lld-link` is on this machine, so the
     default mode now links **every object in the manifest with its recorded mode**, keeps the
     `IMAGE_FILE_MACHINE_*` assertion per linked `.exe` and reports the count: **40 executables
     linked for windows/aarch64, 38 for windows/x86_64**, nothing executed. Proved to have teeth
     by putting 073 back in the `self` list -- `make test-windows` then fails with the exact CI
     message and passes with the classification fixed. The `--run-only` half is unchanged.
     Widening it paid twice: it reported `undefined symbol: GetFileAttributesA` on a
     `build/sysroot/windows-aarch64` populated BEFORE M45 added that name, so
     `scripts/sysroot-windows.sh` now compares the generated `kernel32.def` with the one on disk
     instead of caching on the mere existence of `kernel32.lib` (CI never saw it: it builds the
     sysroot fresh every run).
  -- `make bundle` re-run BEFORE bootstrapping (`lib/sys_windows.mc` is bundled as `sys_windows`):
  78 files, raw 872055 -> LZ 407340, blob 408293 B. `make check` green end to end (**RC 0, zero
  FAIL**): `budget` 2848/3000, `test` 32/32, `check-lex` 126/126 (2 skipped), `check-ast` 126/126,
  `check-asm` 126/126, `check-obj` **32/32 identical to the frozen seed**, `check-bundle`,
  `bootstrap` at a fixed point (`mc2.o == mc3.o`, 941880 B; the `--dump-asm` diff between `mc1`
  and `mc2` is **empty**), `check-surface` 32/32 + 139 ok lines, `test-exe` 32/32, `check-mc`
  11/11, `check-standalone`, `check-parts`, `check-toml` 10/10, `check-build` 53/53,
  `check-sysroots` (13 rows), `check-stubs` 9/9, `check-limits` 17/17 under 90%, `check-minimal`,
  `test-linux` 39/39, `test-linux-x86_64` 36/36, `test-linux-exe` 42/42 musl + 42/42 gnu,
  `test-linux-x86_64-exe` 39/39 + 39/39, **`test-windows` 40/40 objects and 40 linked**,
  **`test-windows-x86_64` 38/38 and 38 linked**, `check-examples`, `check-lang`, `check-conc`,
  `check-desktop`, `check-float`, `check-wide`, `check-kernel` (`kernel.bin` 3304 B),
  `check-avr`, `check-docs` (188 symbols, 22 flags, 20 TOML keys, 10 directives, 48 samples,
  287 links), `site` 85 pages + `check-site` 0 link problems. `make check-linux-host` RC 0 over
  all four cells (aarch64 musl 39/39 and gnu 40/40, x86_64 musl 36/36 and gnu 37/37), each after
  its own `mc2l.o == mc3l.o` and with the cross proof green.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = the branch's HEAD before this batch):
  **33 objects identical** (`tests/*.mc` + `src/mc.mc`) and byte-identical artefacts for
  `examples/api`, `lang`, `conc`, `desktop` and `kernel` -- the change is in `lib/` and in a
  script, and the compiler emits exactly what it emitted.
  The five goldens rewritten **once**, each only after its own criterion -- the blob is the only
  thing that moved: `mc2.sha256` `90ce56dc...35ee38` ->
  `922c9feea7b755c03dc06fbdb4bb8067d4badff87438956ef7319cd3c2e2a444` (empty `--dump-asm` diff +
  `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and re-recorded by
  `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `957067bb9a8ca5d06c944f57b6a3944e43cf11077cc9e9597c0c8423e54fbd39`,
  `mc2-linux-x86_64.sha256`
  `26b1183013227288e1439cd2ada1a9c644fc729f7d453a5fd0e2a700725464aa`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `979336224f09e50f1b3cae3deb38984897aea55451950dca91519b256fbfa728` (959711 B),
  `mc2-windows-x86_64.sha256`
  `e4aa4ebe060c4ad36f55af6c5e19257aa38fdca78e731da834d040f3ee74cdcb` (979195 B), both also
  written byte for byte by `build/mc2`.
- M43 step A ✔ (`docs/specs/M43.md` § Implementation notes -- step A): **the syscall shim, the
  number tables and `<mc/core_sandbox>`**, proved before anything uses them (the M39/M42 probe
  discipline). `src/sysno.mc` (the `SN_*` enum, 60 names + `SN_ABSENT`) shared by the four host
  files -- ONE file, not four copies (deviation 1); `src/sysno_linux_aarch64.mc` (`sys6` as eight
  `#opcode` words, `mov x8,x0` first so the number is read before x0 moves) and
  `src/sysno_linux_x86_64.mc` (six `emit()` words = the 24 bytes `llvm-mc` assembles for
  `mov rax,rdi ... mov r9,[rbp+16]; syscall`, verified BEFORE the file was written); the host layer
  gained `host_syscall6`, `host_sysno(sn)` (the per-architecture table read, so `sandbox.mc` names
  no number and does no offset access) and `host_sandbox_supported()` (macOS/Windows answer -38 /
  an all-absent table / 0). `src/core_sandbox.mc` is the sixth part; `src/sandbox.mc` holds the
  option parser, `check` and the refusals (macOS/Windows: the Lima command, exit 126 for all three
  verbs; Linux `run`/`exec`: `not in this step`, exit 126). `scripts/check-shim.sh`
  (`make check-shim`): `getpid` through the shim == libc's, `openat` of a missing file == -2, a
  `write`, and a six-argument `mmap` at offset 4096 -- the only proof that parameter 7 reaches the
  kernel -- **rc 0 on linux/aarch64 (Lima mc-k7) and linux/x86_64 (the VPS), root and unprivileged**.
  `check-surface` asserts the eight AArch64 words, `check-parts` the six x86-64 words and that
  `<mc/core_min>` + `<mc/core_sandbox>` stands alone.
  **What did not survive contact with the kernel** (Ubuntu 26.04, 7.0.0-30, both arches):
  (1) with `kernel.apparmor_restrict_unprivileged_userns = 1` an unconfined process's
  `unshare(NEWUSER|NEWNS|NEWPID|NEWNET|NEWIPC|NEWUTS)` SUCCEEDS -- the kernel transitions it into
  the `unprivileged_userns` profile and the denial comes at the box's first `mount` (EACCES,
  `capable sys_admin` in dmesg) and at `sethostname` (EPERM); so `userns:` is a TWO-stage probe
  (unshare, then a mount in the child's private namespace), the step-B supervisor's first
  diagnostic is `cannot mount: EACCES`, and a deployment's AppArmor profile must grant `userns,`
  AND `mount,`. The sysctl = 0 cell is unmeasured here (the CI cell will close it).
  (2) `/proc/filesystems` lists only LOADED filesystems: the VPS has `overlay.ko.zst` and no engine
  that loaded it, and a child user namespace cannot `request_module`, so `check` says
  `overlay: not loaded (modprobe overlay)`. (3) Landlock is ABI 8 on this baseline (floor 4).
  (4) `check` exits 126, not 1, where the sandbox is refused outright. (5) **`MAXGLOBALS` of the
  frozen seed is the tight row: 420/512 -> 437/512 (85%)**, `check-limits` fails at 90% (460), and
  step B adds the BPF builder, the notif records and the profiles -- so the sandbox state lives in
  ONE arena record with accessors, at most 12 new globals, and the two ELF writers (87 globals
  between `backend_elf_exe`/`backend_exe`/`backend_elf`) are the global diet to take when needed.
  -- `stage0/`, `lib/`, `tests/*.mc` untouched; `make bundle` re-run (83 entries); `make check`
  RC 0 (`check-lex`/`ast`/`asm` 131/131, `check-obj` 32/32, fixed point 976696 B, `check-limits`
  17/17, four Linux cells RC 0, `check-docs` 191 symbols / 32 flags); `check-inert` identical
  everywhere (a registered subcommand emits nothing). Goldens rewritten once: `mc2.sha256`
  `aab9ae12a7ba7904f6667f45fe63460974295a12d0dd5f21c359b3ed6b97bd79`, Linux
  `57a959a5…28b613` / `ae26b4cb…224555`, Windows `938c4e93…568a25` / `04642639…4860d2`.
- `continue N` done (coop patch for teko/ngen, owner-approved): **the mirror of `break N`.**
  `stage0/` untouched (2848/3000). `continue;` has meant "the innermost loop" since the core had
  loops and `break N;` has had a level since M2; the consumer lowers a switch as a ONE-ITERATION
  `loop` whose arms leave it, so an arm that wants the enclosing loop's next round had no way to
  say it -- `break` falls into the code after the switch, `continue` restarts the switch itself.
  * **The level is stored only when it was written.** `src/parse.mc` reads an optional `T_INT`
    after `continue` and leaves `nd_val` at **0** when there is none, so a plain `continue;`
    builds the node the pre-level compiler built, byte for byte, and `dump_node` (which prints
    `val=` only when it is non-zero) prints nothing for it. `src/gen_walk.mc` reads 0 as 1. That
    is the whole inertness argument: `break;` defaults to 1 in the parser and can, `continue;`
    cannot, because 0 is what "absent" has to mean on a node the seed also builds.
  * Diagnostics: `continue expects a positive level` from the parser (`continue 0;`, at the
    statement's position, the `break 0;` message mirrored) and `continue out of range` from the
    walker (the depth is only known while lowering, like `break out of range`).
    `continue outside loop` is untouched and still comes FIRST, because it says the more useful
    thing when there is no loop at all.
  * **Cost: 23 added lines in `src/`, 11 of them neither comment nor blank** (`parse.mc` +15/7,
    `gen_walk.mc` +8/4, one of those four being the changed `lcont_at(nloops - lv)`).
  * Two modules read a jump's level to decide how many scopes to release and both tested for
    `N_BREAK` before reading `nd_val`, so a `continue N` would have released one loop's worth
    instead of N: `examples/lang/lang_stmt.mc` and `examples/conc/conc_stmt.mc` now read the value
    for either jump and clamp it, which is inert for every source that writes no level (0 clamps
    to 1, exactly what the old code hardcoded) -- `check-inert` proves it on both examples.
  Proofs: `tests/mc/094-continue-level.mc` (the consumer's shape: a one-iteration inner loop used
  as a switch, `continue 2` from an arm, the outer loop advancing and the statement after the
  switch skipped) and `tests/mc/095-continue-one.mc` (`continue 1;` == `continue;`, and a level
  counts enclosing LOOPS and not enclosing blocks -- `continue 3` from inside two `if` blocks).
  Both are portable to all five targets, picked up by the `tests/mc/0[89]*` globs in
  `scripts/test-linux.sh` and `scripts/test-windows.sh` and by `scripts/check-mc.sh`, which also
  asserts that the frozen seed REFUSES them (`expected ; after continue`) -- the reason they live
  in `tests/mc/`. `tests/err/075-continue-zero.mc` and `076-continue-range.mc` are asserted with
  their exact message in `scripts/check-surface.sh`, with the DEFAULT compiler (the feature is
  core, not taught, so `err_case` gained an optional third argument).
  -- `make bundle` re-run before bootstrapping (86 files, raw 1028411 -> LZ 482665, blob 483745 B).
  `make check` green end to end (**RC 0, zero FAIL**): `test` 32/32, `check-lex`/`check-ast`/
  `check-asm` 135/135 (2 skipped), `check-obj` **32/32 identical to the frozen seed**,
  `check-bundle`, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 1108184 bytes; the `--dump-asm`
  diff between `mc1` and `mc2` is **empty**), `check-surface` 32/32 + the two new `err_case` rows,
  `test-exe` 32/32, `check-mc` **15/15** (11 tests + 4 seed refusals), `check-standalone`,
  `check-parts`, `check-toml`, `check-build` 53/53, `check-stubs` 9/9, `check-limits` 17/17 under
  90%, `check-minimal`, `test-linux` 41/41 and `test-linux-exe` 44/44 musl + 44/44 gnu,
  `test-linux-x86_64` 38/38 and 41/41 + 41/41, `test-windows` **42/42** and
  `test-windows-x86_64` **40/40** objects cross-compiled (094/095 among them), `check-examples`,
  `check-lang`, `check-conc`, `check-desktop`, `check-float`, `check-wide`, `check-kernel`,
  `check-avr`, `check-sandbox` 55 ok, `check-docs` (196 symbols, 33 flags, 20 TOML keys, 10
  directives, 51 samples, 320 links), `site` + `check-site`. `make check-linux-host` RC 0 over all
  four cells (fixed point `mc2l.o == mc3l.o`, 1394856 B on aarch64 and 1303384 B on x86_64; suites
  41/41 and 38/38 musl, 42/42 and 39/39 gnu native; the cross proof green on all four).
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main`):
  **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for
  `examples/api`, `lang`, `conc`, `desktop` and `kernel` -- the corpus writes no level, so nothing
  it emits could move.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `aab9ae12...b97bd79` -> `897b18875ff43f3baee95036db3651269ed2dba4c764185a12882b43c5fcdf7d`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `3544cfff8f7fa37710ccd65e76d952d4e3dfdbbc753706e301d02f83a6199e31`,
  `mc2-linux-x86_64.sha256`
  `0888bb6627ca2e778e54522794337bc6c0ec842decbb07f156fa3976ee41cef2`; the Windows pair
  cross-computed per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `b4b7bbc873f4a28865492c44a9992e09d279191bddb3f348c5a8fb78523b44f0` (1129998 B),
  `mc2-windows-x86_64.sha256`
  `7fe8f0832ebe7cc3a037d76e142c20435e015fe109edf2de51bb01cb51923e06` (1158890 B), both also
  written byte for byte by `build/mc2`.
  Docs: `docs/reference/language.md` § 3 (the grammar and the three messages),
  `docs/reference/diagnostics.md` (two new rows), `docs/core-language.md` (including what a level
  means inside a prelude `for`, whose step it skips for the same reason a bare `continue` does --
  measured, not assumed), `docs/guide/10-single-file.md`, `docs/reference/objects.md`, and
  `docs/reference/hooks.md` § `on_jump`, which is where the 0 matters to somebody else: the hook
  sees the `N_CONTINUE` **before** any level check, so a handler reading its level must read 0 as 1
  and may see a level the function's loop depth does not support.
- `syntax_type` done (coop patch for teko/ngen, owner-approved): **a module participates in the
  TYPE position.** `stage0/` untouched (2848/3000). The sibling of M41.5's `syntax_param`, and it
  comes from the same consumer: `T[]`, an element type spelled by the CORE and a container spelled
  by the module. `type_new` cannot buy it -- the word that opens the type is `i64`, and `word_add`
  refuses the core type words, so no keyed table can ever fire there.
  * **`void syntax_type(uptr fn)`** (`src/hooks.mc` +47/19 code, arena tag `T_SYNTYPE` after
    `T_SYNPARAM` -- `T_COUNT` 39 -> 40, `lim_names`/`lim_seeds` reconciled BY NAME, the M42
    lesson, and `mc limits` gains a `syntax_type` row). Handler `i64 f(i64 ty)`: it receives the id
    the core just read, may consume a SUFFIX it owns (`[]`, `?`, `*`) and answers another type id,
    typically one of its own `type_new`; **0 = "not mine"** and the core keeps `ty`. Registration
    order, first non-zero wins, and `nsyntype == 0` short-circuits the whole thing.
  * **One helper, six call sites** (`src/parse.mc` +59/28 code): `take_type(ty)` consumes the type
    word -- the `next()` each site used to make for itself -- and then offers the position to the
    chain, so `p_type()`, a local (`parse_var`), a cast, a parameter (`parse_params`), an `extern`
    and a top-level declaration are one line each and cannot drift apart.
  * **Three guards**, at the TYPE WORD's own position (the word is copied out before `next()`
    moves off it) and run ONCE after the whole chain, not per handler -- the post-M41.5 review's
    rule, which is why the broken fixtures are registered LAST:
    `syntax_type handler consumed tokens and returned 0: <word>` (declining is only sound from
    where the handler was called; otherwise the core reads the rest of the declaration from the
    middle of a type), `syntax_type handler consumed no tokens: <word>` and `syntax_type handler
    returned an invalid type: <word>` (`< 0` or `>= type_count()`; that id goes straight into
    `type_width`/`type_align`/`type_kind`).
  * **Cost: 126 added lines in `src/`, 61 of them neither comment nor blank** (`parse.mc` +59/28,
    `hooks.mc` +47/19, `arena.mc` +20/14, twelve of those last being the renumbered tags and the
    two seed rows). Three new globals -- the seed's `MAXGLOBALS` goes from 432/512 to **435/512
    (84%)**.
  * **The contract the teko session asked about, now written down** (`docs/reference/hooks.md`
    § 3): `type_new(w)` and `syntax_expr(w)` on the same word coexist BY CONSTRUCTION -- `tok_add`
    is idempotent, the two tables are consulted at disjoint grammar positions, and the one place
    they meet (the cast `(w)`) resolves to the type because `parse_primary` tests `type_of_token`
    first.
  Proofs: `lib/user_syntax_demo.mc` teaches `i64[]` (`type_new("i64[]", 8, 8, TK_INT)` -- a
  pointer-sized handle, and a lexeme the lexer can never form, which is why the spelling is free)
  and `scripts/check-surface.sh` compiles one source that uses it in ALL SIX source positions --
  a global, an `extern`, a return type, a parameter, a local and a cast -- runs it (`40 + 2`
  through `memcpy`, exit 42) and counts the nine `type=i64[]` nodes in `--dump-ast`. `sd_param`
  now reads its type with `p_type()` instead of `p_next()`, which is what puts the parameter
  position on the same path; and because that handler claims every typed parameter, the CORE's own
  `parse_params` site is proved by a second module, `lib/user_typearr.mc` (12 lines, `syntax_type`
  and nothing else), which compiles the same source to the same 42 and the same nine nodes. The
  default compiler refuses both halves (`name expected at top level`, and `variable name expected`
  for `i64[] xs;` in a local). `tests/err/077-type-consumed-zero.mc`, `078-type-noadvance.mc` and
  `079-type-badid.mc` are asserted with their exact message (fixtures `sd_teat`/`sd_tnop`/`sd_tbad`,
  each keyed on a `u8`/`u16`/`u32` followed by `[`, a shape no ordinary source has).
  **Inert by construction**: `lib/user_type_nop.mc` + `lib/mc_type_nop.mc` -- a module whose ONLY
  registration is `syntax_type` and whose handler answers 0 for every type word -- produce
  byte-identical `--dump-ast` and objects over the whole `tests/` corpus.
  -- `make bundle` re-run before bootstrapping (86 files, raw 1036368 -> LZ 485658, blob 486738 B;
  the four new `lib/` fixtures are deliberately NOT in `tools/bundle.list`, the M41 precedent for
  check-script-only modules). `make check` green end to end (**RC 0, zero FAIL**): `test` 32/32,
  `check-lex`/`check-ast`/`check-asm` 139/139 (2 skipped), `check-obj` **32/32 identical to the
  frozen seed**, `check-bundle`, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 1113264 bytes;
  the `--dump-asm` diff between `mc1` and `mc2` is **empty**), `check-surface` 32/32 + the six new
  `syntax_type` cases, `test-exe` 32/32, `check-mc` 15/15, `check-standalone`, `check-parts`,
  `check-toml` 10/10, `check-build` 53/53, `check-stubs` 9/9, `check-limits` **17/17 under 90%**,
  `check-minimal`, `test-linux` 41/41 and `test-linux-exe` 44/44 musl + 44/44 gnu,
  `test-linux-x86_64` 38/38 and 41/41 + 41/41, `test-windows` 42/42 and `test-windows-x86_64`
  40/40 objects cross-compiled, `check-examples`, `check-lang`, `check-conc`, `check-desktop`,
  `check-float`, `check-wide`, `check-kernel`, `check-avr`, `check-sandbox` 55 ok, `check-docs`
  (**197 symbols**, 33 flags, 20 TOML keys, 10 directives, 51 samples, 321 links), `site` 87 pages
  + `check-site` (0 link problems). `make check-linux-host` RC 0 over all four cells.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main`):
  **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for
  `examples/api`, `lang`, `conc`, `desktop` and `kernel`.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `897b1887...5fcdf7d` -> `8a84d434a26ff6163149645b4390107543ae1e4b9c515ac84b001b1b868b918f`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `df620903bd5cd48a69c586d2583cdf04a7eae0cb92598b9a9a71e91b470053f6`,
  `mc2-linux-x86_64.sha256`
  `14dc5fc814f1c82a59561b99b91313473032194aa976a75e003a649266d0c793`; the Windows pair
  cross-computed per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `7711f4866bda984f75029f0bcafa0c24b7b9ba729ae781e1956616604704263b` (1135198 B),
  `mc2-windows-x86_64.sha256`
  `d733d2aa7f07fda9fb551384a80084e8da2870c70b01a540fe7c5bde609f2b08` (1163986 B), both also
  written byte for byte by `build/mc2`.
  Docs: `docs/reference/hooks.md` (§ 3 is now six word registrations + **five** hooks that claim
  none, the `syntax_type` section with the six sites and the three guards, and the coexistence
  contract), `docs/reference/diagnostics.md` (three rows), `docs/surface.md` (the nine
  registrations, and a § "The type position"), `docs/reference/language.md` § 2 ("A suffix on a
  type word the core owns").
- M44 step 1 ✔ (`docs/specs/M44.md` § Implementation notes -- step 1; decision D20, the architect's
  addition (f)): **the baked version.** `src/version.mc` (`uptr mc_version()` = the literal
  `0.0.0-dev`, the sentinel; 33 lines, one of code), included by `src/core_min.mc` before `cli.mc`
  and bundled as `mc/version` -- so a taught compiler reports the version of the binary that built
  it, proved in both directions (`0.0.0-dev` -> `0.0.0-dev`, `9.9.9` -> `9.9.9`); `mc --version`
  prints `mc <version>` (no `v`: the tag owns the `v`, and this is the string `release-assets.sh`
  and a future `[deps]` minimum carry); `scripts/set-version.sh VERSION` rewrites the one literal
  and runs `make bundle`, refusing anything but `X.Y.Z[-suffix]` -- it CANNOT delegate the whole
  string to `next-version.sh`, which rejects every suffix on purpose while the sentinel itself is
  suffixed (deviation 1); `scripts/check-bundle.sh` guards the sentinel (a tree where
  `set-version.sh` ran FAILS naming it, after the staleness check so a stale-and-versioned tree is
  reported as stale first); `release.yml`'s "Build the compiler" split in three (seed, bake, build)
  so all five shipped binaries carry the tag from one call. Cost: **53 added lines in `src/`, 9 of
  them code**; globals unchanged at 432/512 (a string literal, not a global). `make check` RC 0
  (`check-obj` 32/32, fixed point 1109608 B, `check-docs` 196 symbols / 34 flags), four Linux cells
  RC 0, `check-inert` identical everywhere. Goldens rewritten once: `mc2.sha256`
  `8e5e127dd96e0d125fd8757b662e6bca61b661d415cdd7349afc9791be14e544`, Linux `6002790c…344380` /
  `1ca2ea58…b15516`, Windows `478e2f28…a50520` / `6d49bfc6…3e70f05`.
- Coop/ops patch (0.15.1, six items; the mc site is served on Linux by a server written in mc,
  `minicompiler/mc-registry`, and that is what found the first four).
  1. **mcsite runs on Linux.** `site/gen/check.mc` declared `extern uptr _NSGetEnviron()`, which
     musl does not have, so an mcsite linked against musl failed to LOAD (`Error relocating
     build/mcsite: _NSGetEnviron`); the environment is now `main`'s third parameter, kept in
     `ms_envp` and handed to `posix_spawnp` -- no host file needed for it. `site/gen/util.mc` read
     `struct dirent` at the macOS offsets and the Linux record is one field shorter (no
     `d_namlen`), so every listing came out truncated or empty and an unpatched mcsite rendered
     **7 pages instead of 87** with no error anywhere: the three fields now come from a host layer,
     `site/gen/macos/site_host.mc` and `site/gen/linux/site_host.mc` (four lines each), picked by
     an `[include]` root the way `examples/conc` picks its thread layer. `site/mc.toml` dropped
     `[target]` (M37: the host pair) and `site/mc.linux.toml` is the same file with `gen/linux`;
     `make site` picks by `uname -s` (`SITECFG`). `scripts/check-site-linux.sh` /
     `make check-site-linux` (inside `make check`, self-skipping without Docker) cross-builds the
     Linux compiler from this tree and runs `mc build site`, the render and `--check` inside
     `alpine:3` on both architectures, asserting that `site/public` comes out **byte for byte the
     macOS render** -- 11/11, 89 pages, 101 files, `diff -r` empty. Beyond the gate, the same
     equality under glibc **with python3 present**, so `checkhtml.py` and `contrast.py` really are
     spawned through the new `ms_envp`: Ubuntu 26.04 aarch64 in Lima and `ubuntu:latest` x86_64 in
     Docker.
  2. **No inline `<script>`**: the server's policy is `default-src 'self'; script-src 'self'`. The
     search code moved verbatim into `site/static/search.js`, loaded with
     `<script src="/static/search.js" data-search-base="/" defer>` -- a data attribute and not a
     template substitution, because a file in `static/` is copied verbatim and never goes through
     `tmpl.mc`. `site/tools/checkhtml.py` now fails a page carrying an inline `<script>`, a
     `style=` attribute or an `on*=` handler (verified to fail on one carrying each); the site had
     no style and no handler to begin with and had 89 inline scripts. Search was then driven
     against the real `search.json` in a DOM stub: the form is revealed, the index is fetched from
     `base + 'search.json'`, `relocation` gives three hits with their heading anchors, Escape
     clears them.
  3. **The header gains `Packages` (`/packages`) and `Sign in` (`/login`)**, after `Examples` and
     before the search box. They are routes of the registry server, not pages this generator
     renders, so they are `[site].nav_extra` plus one `[navlink.<name>]` table each and
     `{{nav_extra}}` is empty without them; `mcsite --check` is told their URLs BY NAME and skips
     exactly those, so every other unrendered URL is still a broken link.
  4. **`<sys_linux>` splits by architecture.** Its wrappers and `_start` were AArch64 `svc #0`
     words, so on x86-64 the same file assembled them into the program and it segfaulted on its
     first system call (`tests/linux/070-nolibc.mc` carried `// skip-x86_64:`). Now
     `lib/sys_linux.mc` is the OS half (the four `O_*` flags, no code), `lib/sys_linux_aarch64.mc`
     is every previous line unchanged -- **the object it compiles to is byte for byte the one the
     old name produced**, checked mach-o and elf -- and `lib/sys_linux_x86_64.mc` is the same seven
     calls over `syscall` (read 0, write 1, open 2, close 3, creat 85, fchmod 91, exit_group 231).
     x86-64 needs no register shuffling at all: the first three parameters of a C call and the
     first three arguments of a system call are the same registers, so each wrapper is `nop; mov
     eax, N; syscall`, two `#opcode` words. `_start` could not copy the AArch64 trick of reaching
     `main` through `reloc(BRANCH26, "_main")` + `emit()` -- `emit()` writes exactly four bytes, a
     pending `reloc()` is pinned to the START of that word, `gen_word` accepts only the four
     Mach-O kinds, and an x86 `call rel32` is five bytes with its field one byte in (M20's wall) --
     so it names `main` with a **prototype**, which a definition later in the same unit satisfies,
     and the call is an ordinary `R_X86_PLT32`. Compiled alone the file is `prototype with no
     definition`, identically from the seed and from `mc`, which is what `scripts/check-asm.sh`
     was written to compare. `sysl_entry()` is two hand-encoded words answering `&argc` on the
     entry stack from the caller's saved `rbp`, and one more puts the stack parity back.
     The layer is chosen from outside the source (`lib/linux/{aarch64,x86_64}/sys_arch.mc`, one
     line each, through `[include].paths`, which `scripts/test-linux.sh` writes into every config
     it generates). `host_sys()` moved into the two architecture host files
     (`sys_linux_aarch64` / `sys_linux_x86_64`). **070-nolibc now runs on both legs**, and the
     x86-64 leg also runs an `llvm-mc` sweep: 12 distinct hand-encoded instructions, byte for byte.
  5. **Semver pre-releases** (`src/deps.mc`, `src/pkg.mc`). `ver_cmp` ignored the `-suffix`, so
     `1.2.0-rc1` compared EQUAL to `1.2.0`. SemVer 2.0 § 11 is now implemented in full -- numeric
     fields first, a pre-release below the same X.Y.Z without one, then identifier by identifier
     (numeric below alphanumeric, numeric by value, else ASCII, a prefix below what extends it),
     `+build` ignored -- and the specification's own chain holds
     (`1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta < 1.0.0-beta.2 <
     1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0`). C4 is sharper: `0.0.0-dev` now compares below `0.0.0`
     as well as below `0.0.1`. Go's rule for CHOOSING: `pkg_newest`/`pkg_pick` take a `pre` flag
     that is 0 for `mc pkg add NAME` and for a plain `mc update`, so a candidate is never chosen
     for you -- it enters only when named (`mc pkg add mathx@2.1.0-rc1`, which does not reach
     `pkg_newest`) or when the `[deps]` minimum is already one; MVS never picks "newest" so it can
     only reach a candidate some row names outright; a registry with nothing but candidates says
     `only pre-release versions are registered: name one, NAME@VERSION`. Fixtures
     `mathx-2.1.0-rc1` and `mathx-2.1.0` plus five cases in `scripts/check-pkg.sh` (85/85).
  -- `stage0/` untouched, 2848/3000. `make bundle` re-run before bootstrapping (93 files, raw
  1167060 -> lz 546631, blob 547793 B; `tools/bundle.list` gained `sys_linux_aarch64` and
  `sys_linux_x86_64`). `make check` green end to end (**RC 0, zero FAIL**): `test` 32/32,
  `check-lex` 145/145 (3 skipped), `check-ast` 146/146, `check-asm` 146/146, `check-obj`
  **32/32 identical to the frozen seed**, `check-bundle`, `bootstrap` at a fixed point
  (`mc2.o == mc3.o`, 1260760 B; the `--dump-asm` diff between `mc1` and `mc2` is **empty**),
  `check-surface` 32/32 + inert, `test-exe` 32/32, `check-mc` 15/15, `check-standalone`,
  `check-parts`, `check-toml` 10/10, `check-build` 53/53, `check-pkg` **85/85**, `check-sysroots`,
  `check-stubs` 9/9, `check-limits` **17/17 under 90%** (the tightest is `globals` **444/512 =
  86%**, 16 under the 460 budget; `funcs` 1642/2048 = 80%), `check-minimal`, `test-linux` 41/41 on
  linux/aarch64 and **39/39 on linux/x86_64 with 070-nolibc among them**, `test-windows` 42/42 +
  `test-windows-x86_64` 40/40 objects, `check-examples`, `check-lang`, `check-conc`,
  `check-desktop`, `check-float`, `check-wide`, `check-kernel`, `check-avr`, `check-docs`
  (197 symbols, 36 flags, 27 TOML keys, 10 directives, 51 samples, 361 links), `site` 89 pages +
  `check-site` (0 link problems, 89 files 0 problems, 50 contrast pairs 0 below the minimum),
  **`check-site-linux` 11/11**, `test-linux-exe` 44/44 musl + 44/44 gnu, `test-linux-x86_64-exe`
  42/42 musl + 42/42 gnu, `test-sandbox` 55 ok.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `main` a3303fd):
  **33 objects identical** (`tests/*.mc` and `src/mc.mc`) and byte-identical artefacts for
  `examples/api`, `examples/lang`, `examples/conc`, `examples/desktop` and `examples/kernel`
  through the taught compiler each side builds. `make check-linux-host` green over all four cells
  (musl and glibc x aarch64 and x86_64), each after its own `mc2l.o == mc3l.o` and with the cross
  proof against the macOS `build/mc2.o`.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `5d2db5f9...67ae55` -> `e6359eb6f3a2c7f7a4511859f2dfb2dd629494860e2d85fa0e49df1c8594dfb5`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `51b5c5dda382bb7127e26c7f9b1747a6ad354ab95f152c967a11e0835a6da9ab`,
  `mc2-linux-x86_64.sha256`
  `5c8702e1379410d8c9753d9621daa45092c4f1a7b3d15220a7203377e87ba140` (each confirmed a second
  time by the glibc cell of its architecture); the Windows pair cross-computed per
  `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `7b7059ba6145ec0836ff97f938294eb861898e9ea66c4a12ad0daf9c1c97a1ba` (1287028 B),
  `mc2-windows-x86_64.sha256`
  `67a23742efc58941dc9bfa4b3b1203d70b7183603e7ac18601e5ec210a4a4845` (1322720 B), both also
  produced byte for byte by `build/mc2`.
- Sandbox forkbomb flake fixed (`docs/specs/M43.md` § Implementation notes -- the forkbomb flake,
  `docs/reference/sandbox.md`): **a refused call was released by the listener before the kill
  landed.** The CI job `The sandbox (linux/arm64)`, root cell, case `forkbomb (alt)`
  (`--allow=threads`, cap 64) failed twice in about ten runs of PR #27 and #29 with
  `stdout [forked 64], want []` while the report line `refused: process limit (64)` was correct.
  Reproduced on the Lima oracle (`mc-k7`, Ubuntu 26.04, kernel 7.0.0-30, aarch64, glibc) with a
  compiler built from `origin/main`, 100 runs of the single case per cell: **14/100 as root,
  13/100 unprivileged**, the report right every time. The mechanism, measured and not guessed: a
  refused notification is deliberately left unanswered (step C note 12), but a pending
  notification is ALSO released when its LISTENER goes away, and the kernel releases it with
  **ENOSYS** -- a copy of `forkbomb.mc` printing `__errno_location()` answered `forked 64 errno
  38` on every failing run, never `EAGAIN`. P closes the listener in `sb_go` as soon as
  `sb_supervise()` returns, and the supervisor loop ends when the status pipe closes, ~1 ms after
  the kill; the kill itself reaches the STEP only through `zap_pid_ns_processes()` in J's exit
  path. A timestamped trace of a failing iteration shows `refuse` / `after kill_box` /
  `status pipe closed -> break` / `sb_go: close the listener` inside the same millisecond, with
  the step still alive; a 2 s sleep in `sb_refuse` after the kill gave 0/60, which proves the
  ordering from the other side.
  The fix makes the order explicit and is **25 code lines in `src/sandbox.mc` and
  `src/seccomp.mc`, nothing removed**: `sb_refuse` SIGKILLs the task whose call it is
  (`sb_kill_pid`, using `seccomp_notif.pid`, which the kernel translates into the READER's pid
  namespace -- the same number `process_vm_readv` already takes), then the box, and only then lets
  the notification go -- `sb_wait_gone(SB_GONE_MS)` waits for **POLLHUP** on the listener, which
  is exactly `filter->users == 0`, asking for NO events so that a notification queued behind the
  refused one cannot wake it; bounded at two seconds, the grace the wall clock already uses.
  After the fix, same oracle, both cells, **200 iterations each: 0 with stdout, 0 with a wrong
  report**; `scripts/test-sandbox.sh` **55 ok, 0 failed, 1 skipped** in the root cell and in the
  unprivileged one; `sh scripts/sandbox-trace.sh --check` green (the profile lists were not
  touched). `stage0/` untouched (2848/3000), `lib/` and `tests/` untouched.
  -- `make bundle` re-run BEFORE bootstrapping (93 files, raw 1170795 -> LZ 548311, blob 549473 B).
  `make check` green end to end (**RC 0, zero FAIL**, 7m59s): `test` 32/32, `check-lex` 145/145
  (3 skipped), `check-ast`/`check-asm` 146/146, `check-obj` **32/32 identical to the frozen
  seed**, `check-bundle`, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 1263304 B; the
  `--dump-asm` diff between `mc1` and `mc2` is **empty**), `check-surface` 32/32, `test-exe`
  32/32, `check-mc`, `check-standalone`, `check-parts`, `check-toml`, `check-build`,
  `check-pkg` 85/85, `check-stubs`, `check-sysroots`, `check-limits` **17/17 under 90%**,
  `test-linux` 41/41 + `test-linux-x86_64` 39/39, the four `--exe` cells 44/44 + 44/44 + 42/42 +
  42/42, `test-windows` 42/42 and `test-windows-x86_64` 40/40 objects cross-compiled (11/11 each
  linked), `check-examples`, `check-lang` 18, `check-conc` 21, `check-desktop`, `check-float`,
  `check-wide`, `check-kernel`, `check-avr`, **`test-sandbox` 55 ok / 0 failed / 1 skipped**
  (delegated to Lima), `check-docs` (197 symbols, 36 flags, 27 TOML keys, 10 directives, 51
  samples, 361 links), `site` 89 pages + `check-site`. `make check-linux-host` RC 0 over all four
  cells (aarch64 musl 41/41 and gnu 42/42, x86_64 musl 39/39 and gnu 40/40), each after its own
  `mc2l.o == mc3l.o` and with the cross proof against the macOS `build/mc2.o` green.
  `scripts/check-inert.sh` against a `build/mc1` built from `origin/main`: **33 objects identical**
  (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for `examples/api`, `lang`, `conc`,
  `desktop` and `kernel` -- a sandbox fix emits no different byte.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `e6359eb6...94dfb5` -> `6e8eccf15dd071925d13eb146a05e888cff6f25572b60a0ca7a7f191a8c641fe`; the
  Linux pair deleted and re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `3789cc6d5cb4f4109b323de831d85e6a815142a7e46ff507a42ad2cbdcba3f80`,
  `mc2-linux-x86_64.sha256`
  `ace3d74575d71b4151ec0d10e6fa3caf28cb56c993b107c49820993b86fcb557`; the Windows pair
  cross-computed per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `babc44ca1dec8dcaf2dc0f6507a3abe9fce48a283b8887684964208740fd5701` (1289613 B),
  `mc2-windows-x86_64.sha256`
  `f6594f109a2eb58b48073042aeaa7127125f74735c137185b336e77e1a0103de` (1325521 B), both also
  written byte for byte by `build/mc2`.
- `on_source` done (coop patch for teko/ngen, owner-approved): **a module is told about every
  source the lexer pushes.** `stage0/` untouched (2848/3000, `git diff origin/main -- stage0/`
  empty). The consumer's case: ngen gets free declaration order from a lexical pre-scan, which it
  can run on the entry and on the files IT opens -- but a `#include "x.tk"` the CORE resolves is
  invisible, because `do_directive` is internal and pushes without telling anybody.
  * **`void on_source(uptr fn)`** (`src/hooks.mc` +52/19 code): handler
    `void f(uptr name, uptr src, i64 len)`, growable table (`grow`), arena tag `T_ONSOURCE`
    inserted after `T_ONJUMP` (`src/arena.mc` +21/-18, 16 code -- `T_COUNT` 40 -> 41, the eleven
    tags after it renumbered and `lim_names`/`lim_seeds` reconciled BY NAME, the M42 lesson: the
    16 that belongs to `backends` travelled with it, and `mc limits` gains an `on_source` row).
    Handlers run in registration order and answer nothing -- this is an announcement, not a
    decision.
  * **One call site, and it covers every road.** `lex_push_mem` is the single funnel: the entry
    (`lex_init` -> `lex_push`), a relative `#include` (`lex_include` -> `lex_push`), a bundled one
    (`lex_include_bundled`), a package one (`lex_include_libs`) and `p_push_source`. The call is
    the LAST thing `lex_push_mem` does, so `cp`/`cend`/`cline` already describe the new frame and
    a handler reading `lex_file()` sees the source it is being told about.
  * **The table is in `hooks.mc`, the call cannot be** (`src/lex.mc` +60/31 code): `src/lexdump.mc`
    includes the lexer with `arena.mc` and nothing else, so the lexer must not name a symbol of
    `hooks.mc`. It is M15's bundle shape exactly -- `lex_set_source_hook(&run_on_source)`, one
    function pointer, stored by the first registration; with nothing registered the pointer is 0
    and there is not even a `callp`.
  * **The entry file IS announced, and a module need not scan it by hand.** `lex_init` pushes it
    BEFORE `user_init()` runs (`src/cli.mc`, `src/driver.mc` and `src/limits.mc` all in that
    order), so the natural call has already happened when a handler can first exist. `on_source`
    closes that by replaying, at registration time and to the newly registered handler ALONE, in
    push order, every source already open -- so the rule is one sentence: *a handler sees every
    source pushed after it registers, plus the ones already open when it registers*, and it holds
    for a registration made during parsing too. That is what the two new frame fields are for:
    `OF_SRC`/`OF_LEN` (`OF_SIZE` 32 -> 48) keep the buffer a frame was pushed with untouched while
    `cp` walks it, so a replay hands over the WHOLE source and not the bytes still unread.
  * **The one guard, and it was measured before it was written.** A handler runs with the frame it
    is being told about already on the stack; a push from inside the callback interleaves the
    announcement of one source with the opening of the next, and a handler that pushes
    unconditionally recursed until the process stack was gone -- reproduced with
    `lib/user_srcpush.mc`, **SIGSEGV, exit 139, no diagnostic at all**. A frame-depth comparison
    after the call cannot see it (the call never returns), so the guard is a re-entrancy flag
    (`shook_busy`) tested at the HEAD of `lex_push_mem`: the push itself is the error, on the
    first one, and the message names the source the handler tried to push --
    `mc: on_source handler pushed a source: srcpush runtime`, exit 1.
  * **Cost: 133 added lines in `src/`, 66 of them neither comment nor blank** (`lex.mc` +60/31,
    `hooks.mc` +52/19, `arena.mc` +21/16, twelve of those last being the renumbered tags and the
    two seed rows). Five new globals -- the seed's `MAXGLOBALS` goes from 444/512 to
    **449/512 (87%)**.
  Proofs: `lib/user_syntax_demo.mc` (+55) counts the sources and joins their names
  (`syntax_expr("srccount")`, `syntax_expr("srcnames")`, the latter building an `N_STR` node), and
  `scripts/check-surface.sh` (+115) compiles one program that reads both back and prints them --
  **`<entry>|box runtime|<dir>/inc.mc|prelude`, exit 42** (`srccount` 4 + 40 - 2): the entry
  (replay), the source the demo module itself pushes at the end of `user_init`, a relative
  `#include` the CORE resolved and a bundled `#include <prelude>` the core resolved, in push
  order. The default compiler refuses the same source (`onsrc.mc:6: unknown name`). The guard is
  asserted with its exact message through `lib/mc_srcpush.mc`. **Inert by construction**:
  `lib/user_source_nop.mc` + `lib/mc_source_nop.mc` -- a module whose ONLY registration is
  `on_source` and whose handler does nothing -- produce byte-identical `--dump-ast` and objects
  over the whole `tests/` corpus. The four new `lib/` fixtures are NOT in `tools/bundle.list`
  (the M41 precedent for check-script-only modules).
  -- `make bundle` re-run BEFORE bootstrapping (`src/lex.mc`, `src/hooks.mc` and `src/arena.mc`
  are bundled): 93 files, raw 1178425 -> LZ 551503, blob 552665 B. `make check` green end to end
  (**RC 0, zero FAIL**, 8m14s): `budget` 2848/3000, `test` 32/32, `check-lex` 149/149 (3 skipped),
  `check-ast` 150/150, `check-asm` 150/150, `check-obj` **32/32 identical to the frozen seed**,
  `check-bundle`, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 1268832 bytes; the `--dump-asm`
  diff between `mc1` and `mc2` is **empty**), `check-surface` 32/32 + the four new `on_source`
  cases, `test-exe` 32/32, `check-mc` 15/15, `check-standalone`, `check-parts`, `check-toml` 10/10,
  `check-build` 53/53, `check-pkg` 85/85, `check-stubs` 9/9, `check-sysroots` (13 rows), `check-limits`
  **17/17 under 90%**, `check-minimal`, `test-linux` 41/41 and `test-linux-x86_64` 39/39,
  `test-linux-exe` 44/44 musl + 44/44 gnu and 42/42 + 42/42 on x86_64, `test-windows` 42/42 and
  `test-windows-x86_64` 40/40 objects cross-compiled, `check-examples`, `check-lang`,
  `check-conc`, `check-desktop`, `check-float`, `check-wide`, `check-kernel` (QEMU 11.0.1),
  `check-avr`, `test-sandbox` 55 ok / 0 failed / 1 skipped, `check-docs` (**198 symbols**,
  36 flags, 27 TOML keys, 10 directives, 51 samples, 361 links), `site` 89 pages + `check-site`
  (0 link problems) + `check-site-linux` 11/11. `make check-linux-host` RC 0 over all four cells
  (aarch64 musl 41/41 and gnu 42/42, x86_64 musl 39/39 and gnu 40/40), each after its own
  `mc2l.o == mc3l.o` and with the cross proof green.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main`):
  **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for
  `examples/api`, `lang`, `conc`, `desktop` and `kernel`.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `6e8eccf1...c641fe` -> `bbf735bd3bdb58948221c945d7652be2e21980f1dc57a169e217f72f7fd6326b`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `f71dda4d84313e40b1a2d205a0c0314cfd61747b4dfda2fe09a76461304f5868`,
  `mc2-linux-x86_64.sha256`
  `24ed180c0538715675ac1c35332ebc51506d39c9beaa21dac9c4bb659551b1c9`; the Windows pair
  cross-computed per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `a39a9f4d363882c58ba80b406c586f9838bf9b683443cdbaddcec71bfd2ffe2d` (1295230 B),
  `mc2-windows-x86_64.sha256`
  `54a3b2536ee550154add7e1f4c869c16861dfb6522e778fdfb8ea80fc5ffd208` (1330894 B), both also
  written byte for byte by `build/mc2`.
  Docs: `docs/reference/hooks.md` (§ 1's pipeline, § 3 is now six word registrations + **six**
  hooks that claim none, and an `on_source` section with the four roads, the entry-file rule and
  the guard), `docs/reference/diagnostics.md` (one row, § 5), `docs/surface.md` (the ten
  registrations, and a § "Every source the lexer pushes").
- M47 S5, compiler side ✔ (`docs/specs/M47-S5.md`, `docs/reference/packages.md` § 11,
  `docs/ci.md` § `publish-to-registry`): **this repository is a package, and every release
  announces itself to the registry.** `stage0/` untouched (2848/3000).
  * **`mc.toml` at the root**: `[package] name = "mc"` (M44's D15': the whole bundle at the
    compiler's version), `lib = "src/core.mc"` (a bare `#include <mc>` is the compiler without
    `user_init` -- what `[compiler].core` defaults to and what every taught compiler here
    includes; it carries its own `main()`), and `files` = `cut -f2 tools/bundle.list | LC_ALL=C sort -u`
    plus the **two files that list cannot name** -- `src/bundle_data.mc` (the blob has no row in
    a bundle of itself; without it the closure rule refuses the build, measured) and
    `tools/bundle.list` (the `NAME<TAB>PATH` map an installed tree reads). 95 entries, in
    **byte order** -- under a UTF-8 locale macOS collates `_` before `.`, which CI (the only
    macOS in this loop with a locale set) caught as a drift the developer's shell could not see.
    **No `[project]`**, on purpose: `make` builds this repository and the five real project
    configs are `src/mc.<target>.toml`, so `mc build .` at the root is
    `mc.toml: missing key: project.entry` and nothing in `scripts/` reads a config there.
  * **`release.yml` gained `publish-to-registry`** (`needs: publish`, `ubuntu-latest`,
    `contents: read`, 20 min, `continue-on-error: false`): one step,
    `minicompiler/register-action@v1` with the tag. No secret, no checkout -- the whole request
    is the repository's public URL. A job and not a step because § 13b makes a GitHub **Release**
    the thing the validator looks for, and because a refused announcement must not unmake a
    published release. **The first run will be red**: `minicompiler/mc` is not registered yet and
    the registry answers 404 `not registered` until the owner registers it on
    https://minicompiler.dev/me.
  * **One compiler fix**, reproduced first on an untouched fixture: `dep_under` refused every
    entry when the package directory was `.`. `path_norm` answers `"."` for a directory with no
    segments and `path_join` then DROPS that segment, so the join of a contained entry never
    began with `"./"` and the prefix test could not match --
    `mc pkg hash .` was `mc: ./: files entry escapes the package: mathx.mc`, exit 2, **for any
    package at all**. `src/deps.mc` +8 code lines; the four escaping shapes are still refused
    with `.` as the base and every other base is byte for byte what it was.
    `scripts/pkg-hash.sh`'s `files_of` also learned the multi-line array (its own comment said it
    could not read one); the thirteen fixture hashes did not move.
  * **Measured**: the root package's tree hash is
    `930d9e1c5099d1d5c332c83ecb392cdbddc5ebf50cb9ced7c3e633b14c729eab`, and the
    compiler and `scripts/pkg-hash.sh` agree on it. A consumer outside the tree -- `[deps]`, the
    tree vendored at `deps/`, an entry that is four `#include`s -- builds a **1 153 024-byte
    compiler** that answers `mc 0.0.0-dev` and writes an object for `src/mc.mc` **byte for byte**
    the one `build/mc1` writes (1 269 016 B); dropping `src/bundle_data.mc` from the manifest
    turns that into `mcpkg/src/bundle_data.mc:1: not declared in mcpkg's [package].files`.
  * **Three findings for the registry, none fixed here** (`docs/specs/M47-S5.md` § 3):
    (1) `mc` is reserved on every consumer road -- `[deps]`, `[replace]`, `mc pkg add` and
    `mc pkg check` of the index file this repository would produce all answer
    `reserved package name`, so the registry's own gate cannot be run on `index/mc.toml`;
    (2) the bundle's namespace is not the package's -- `<mc/core>` is `src/core.mc` out of the
    blob and `<pkgdir>/core.mc` through a locked package, and `<mc/host>` has no meaning there at
    all; (3) **§ 4.2's `check.mc` cannot include every `files` entry**: written verbatim it is
    `deps/mcpkg/src/sandbox_profiles.mc:36: initializer must be constant`, and four independent
    classes of alternative were each reproduced (the lib needs a host layer first; two host
    layers are `duplicate #define` on `O_CREAT`; two system layers likewise; a non-source payload
    is `type expected at top level`). Recommended instead: an optional `[package].check` array of
    translation units, each compiled on its own, defaulting to the `lib` -- inert in the compiler,
    one loop in the validator.
  * **Priced, not built** (`docs/specs/M47-S5.md` § 4): the standalone libraries of `lib/` as
    packages of their own. Each is a DIRECTORY move (`dep_rel_ok` refuses `..`): `lib/float/`,
    `lib/i128/`, `lib/f16/`, `lib/prelude/`, `lib/io/`, `lib/sys_linux/`, `lib/sys_windows/`, and
    `rt`/`http`/`sqlite`, which are not bundled at all and live under `examples/api/lib/`.
    What does NOT move: the bundled names (`bundle.list` is `NAME<TAB>PATH`; only the PATH column
    changes) and therefore **the blob and the five goldens** -- `tools/bundle.mc` writes names and
    bytes and "no path, date or address reaches the blob". What breaks: the `lib/*.mc` glob in
    `check-lex`/`check-ast`/`check-asm`, the paths `check-float`/`check-wide`/`check-surface`
    name, and ~15 places in `docs/`. The one real question -- a package nested inside the `mc`
    package -- is already answered by `lex_root_of`, which keeps the LONGEST matching root, but no
    fixture has ever nested one. ~150 changed lines plus the moves; **zero** if the libraries go
    to a separate repository instead. The owner decides.
  -- `make bundle` re-run before bootstrapping (93 files, raw 1179047 -> LZ 551813, blob
  552975 B). `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test`
  32/32, `check-lex` 149/149 (3 skipped), `check-ast`/`check-asm` 150/150, `check-obj`
  **32/32 identical to the frozen seed**, `check-bundle`, `bootstrap` at a fixed point
  (`mc2.o == mc3.o`, 1269320 B; the `--dump-asm` diff between `mc1` and `mc2` is **empty**),
  `check-surface` 32/32, `test-exe` 32/32, `check-mc` 15/15, `check-standalone`, `check-parts`,
  `check-toml` 10/10, `check-build` 53/53, **`check-pkg` 93/93** (the M47-S5 section is the last
  nine), `check-stubs` 9/9, `check-sysroots`, `check-limits` 17/17 under 90 percent,
  `check-minimal`,
  `test-linux` 41/41, `test-linux-x86_64` 39/39, `test-linux-exe` 44/44 musl + 44/44 gnu,
  `test-linux-x86_64-exe` 42/42 + 42/42, `test-windows` 42/42 and `test-windows-x86_64` 40/40
  objects cross-compiled, `check-examples`, `check-lang`, `check-conc`, `check-desktop`,
  `check-float`, `check-wide`, `check-kernel`, `check-avr`, `test-sandbox` 55 ok / 0 failed /
  1 skipped, `check-docs` (198 symbols, 36 flags, 27 TOML keys, 10 directives, 51 samples,
  365 links), `site` 90 pages + `check-site` 0 link problems.
  `make check-linux-host` RC 0 over all four cells (musl and gnu x aarch64 and x86_64), each
  after its own `mc2l.o == mc3l.o` and with the cross proof green.
  `scripts/check-inert.sh <mc1 from origin/main> build/mc1`: **33 objects identical**
  (`tests/*.mc` + `src/mc.mc`) and byte-identical artefacts for `examples/api`, `lang`, `conc`,
  `desktop` and `kernel` -- a root `mc.toml`, a workflow job and a containment fix emit no byte.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `bbf735bd...6326b` -> `6a689f82b978b310f0143950b50705650afa66fef0c76f49221d6481951a50b9`
  (empty `--dump-asm` diff + `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `dbc8f498e78fc023e0eec4e279f9de4ac596cf1f8cc71ff0aa1060667c8f5129`,
  `mc2-linux-x86_64.sha256`
  `92c6451658d92bb12f0fa8dc30828988c112a32dbd5d5ba4eb6e51ff12456764`; the Windows pair
  cross-computed per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `baf4b5ebefa616775e35199ed45cf880a6ec30373656e4386965fa660d2eee05` (1295746 B),
  `mc2-windows-x86_64.sha256`
  `4c1b54c5099a12cbffa4b6547e24891caf4f46f467bffe877a92c3eb9e021227` (1331426 B), both also
  written byte for byte by `build/mc2`.
- Post-S5 follow-up (three findings from the registry's validator rehearsal, `minicompiler/mc-registry`
  PR #7 / its `docs/spec-M47.md` § 22): **a compile-only box ends `done`, and the `mc` package
  ships the unit it declares.** `stage0/` untouched (2848/3000); the whole compiled change is
  `src/sandbox.mc` +24/-1 and `src/sandbox_box.mc` +1/-2, **8 added lines that are neither comment
  nor blank**.
  1. **`mc sandbox run` exited 126 after a compile that succeeded.** Two shapes have no run step
     -- a project whose `[project].kind` is not `"exe"` (which is exactly what the validator
     writes: a unit may or may not carry `main`, so the wrapper asks for an object) and a
     `--dump-*`, which IS the output. Reproduced on the Lima oracle (`mc-k7`, Ubuntu 26.04,
     kernel `7.0.0-30-generic`, aarch64, glibc) with the compiler of `origin/main` a87e9b5:
     `sandbox: compile: exit 0` / `sandbox: the box ended without a status`, **exit 126**, where
     the same entry with `kind = "exe"` is exit 0. The box's step loop knew to stop
     (`if (!str_eq(sb_kind(), "exe")) break;`) and `sb_note_exit(SB_STEP_COMPILE, 0)` set no
     terminal status, so `sb_go`'s `else if (!sb_done())` fired. Fixed at the root with ONE
     predicate and two readers, which is what makes them unable to drift again:
     `sb_has_run_step()` in `src/sandbox.mc` (`exec` -> 1, a dump -> 0, else
     `str_eq(sb_kind(), "exe")`), read by `sandbox_box.mc`'s loop and by `sb_note_exit`, which now
     ends the box with rc 0. **No new report line**: a one-step box's report is
     `sandbox: compile: exit 0` and nothing else, because a bare `exit 0` after it would say a
     program ran. Gate: `scripts/test-sandbox.sh` § 2c over the new `tests/sandbox/objproj/` (one
     entry, three configs) asserts all four corners -- `kind = "obj"` and `--dump-ast` end 0 with
     `compile: exit 0` as the report's LAST line and no `ended without a status` anywhere, the
     same entry with `kind = "exe"` still gets its run step, and a compile that FAILS in a
     one-step box is still `compile: exit 1`, exit 1. Measured after the fix: **60 ok / 0 failed /
     1 skipped** on the Lima cell and **58 ok / 0 failed / 3 skipped** under
     `docker run --privileged alpine:3` (musl, aarch64), against 55 and 53 before. On the
     registry's side it deletes `jb_box_ok`'s exit-126 exemption.
  2. **The `mc` package declared a check unit it did not ship.** `[package].check` names
     `src/mc_linux_x86_64.mc`, and neither that file nor the `src/user.mc` it includes had a
     `tools/bundle.list` row, so neither was in `files` -- and the tree hash covers `files` and
     nothing else. Both added (byte order, `LC_ALL=C`), **97 entries**;
     `scripts/check-pkg.sh` § 30a's extras list grew from two to four with its comment, and a new
     § 30b' asserts that every `[package].check` unit is on disk AND declared. Proved by a local
     rehearsal in the shape `web/job.mc` writes -- `kind = "obj"`,
     `[target] os = "linux" arch = "x86_64"`, the tree **vendored** at `deps/pkgcheck/`
     (`mc` cannot be a `[deps]` key; `pkgcheck` is the registry's own local name) holding
     `mc.toml` plus every `files` entry and nothing else, an `mc.lock` row with the tree hash, and
     `check.mc` = `#include <pkgcheck/src/mc_linux_x86_64.mc>`: with this branch's manifest it is
     `exit 0` and an ELF 64-bit LSB relocatable x86-64 of **1 494 016 bytes**; with
     `origin/main`'s it is `pkgcheck/src/mc_linux_x86_64.mc:1: not declared in pkgcheck's
     [package].files`, exit 1. The `[replace]` spelling the instruction named was tried first and
     is not usable (`mc: pkgcheck 0.0.0-dev is not fetched`, exit 2 -- `[replace]` is consulted
     after the tree is resolved, the registry's own § 18 finding). Tree hash of the final tree,
     `mc pkg hash .` == `sh scripts/pkg-hash.sh .` ==
     `770d6e1c103d12f297fa586d4cf7d44555cea7fa0d841e58e9770f294fed6196`.
     **Recommendation, not taken here**: `src/mc_linux.mc` as a SECOND check unit. It compiles on
     an x86_64 worker in the same shape (measured: exit 0, `build/check.o` 1 494 032 bytes, an
     x86-64 object) -- nothing in a host file is architecture-gated at compile time -- and it is
     the only path to `src/host_linux_aarch64.mc` and `src/sysno_linux_aarch64.mc`, which are in
     `files` and are compiled by no check today. It costs one more box per tag (~1.5 s of the
     ~1.6 s job) and one more `files` entry.
  3. **Docs.** `docs/reference/packages.md` gained the `[package].check` section (the key the
     compiler ignores and the registry reads; default = the lib alone; each unit compiled on its
     own; must be in `files`; it takes part in the tree hash because `mc.toml` is line 1 of the
     digest) and § 11's four-extras correction; `docs/reference/sandbox.md` § The report says a
     `compile: exit N` is the TERMINAL status when there is no run step, with the transcript;
     `docs/specs/M43.md` gained § Implementation notes -- the compile-only box;
     `docs/specs/M47-S5.md` gained § 5, the outcome (the rehearsal table, the second-unit
     recommendation, and the registry's § 22.5 caps -- CPU 1.39 s of 60, wall 1.48 s of 180,
     90 716 KiB of 512 MiB, an output of 1 595 016 B of 64 MiB, the two-tag job in 1631 ms);
     `docs/ci.md` documents `publish-to-registry`'s two explicit inputs (`registry:
     https://next.minicompiler.dev`, `index: https://pkg.minicompiler.dev`) and that both lines
     are deleted at the apex flip -- the apex is still GitHub Pages and answers 405 to
     `POST /poll`.
  -- `make bundle` re-run before bootstrapping (93 files, raw 1180351 -> LZ 552350, blob
  553512 B). `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test`
  32/32, `check-lex` 149/149 (3 skipped), `check-ast`/`check-asm` 150/150, `check-obj` **32/32
  identical to the frozen seed**, `check-bundle`, `bootstrap` at a fixed point
  (`mc2.o == mc3.o`, 1270064 B; the `--dump-asm` diff between `mc1` and `mc2` is **empty**),
  `check-surface` 32/32 + inert, `test-exe` 32/32, `check-mc` 15/15, `check-standalone`,
  `check-parts`, `check-toml` 10/10, `check-build` 53/53, **`check-pkg` 94/94**, `check-sysroots`
  (13 rows), `check-stubs` 9/9, `check-limits` 17/17 under 90% (globals 449/512 = 87%),
  `check-minimal`, `test-linux` 41/41, `test-linux-x86_64` 39/39, `test-linux-exe` and
  `test-linux-x86_64-exe` (musl and gnu), `test-windows` 42/42 + `test-windows-x86_64` 40/40
  objects cross-compiled, `check-examples`, `check-lang`, `check-conc`, `check-desktop`,
  `check-float`, `check-wide`, `check-kernel`, `check-avr`, **`test-sandbox` 60 ok / 0 failed /
  1 skipped**, `check-docs` (198 symbols, 36 flags, 27 TOML keys, 10 directives, 51 samples,
  366 links), `site` 90 pages + `check-site` (0 link problems, 90 files 0 problems, 50 contrast
  pairs 0 below the minimum). `make check-linux-host` RC 0 over all four cells (musl and gnu x
  aarch64 and x86_64), each after its own `mc2l.o == mc3l.o` and with the cross proof green.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main`
  a87e9b5): **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts
  for `examples/api`, `lang`, `conc`, `desktop` and `kernel` -- `src/sandbox.mc` emits nothing.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `6a689f82...a50b9` -> `4bcf3cd82142872232b7ebc55703aed580fa062c824de776873b4c80e917df06`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `672ee2d3ddbc4bbccbaa839729978abdabe1312b0b51f1068a37844702fd9cd1`,
  `mc2-linux-x86_64.sha256`
  `c32e130e9b123171a080138fd4d8c58c89c6f18cea38f8cf899be28ae728c4a2`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `103a3221398be254ffe19b2d7d6c79274b37ad37c82def83d75df48dbbeefa76` (1296500 B),
  `mc2-windows-x86_64.sha256`
  `b0af8baca4044bfacb26b50cd00e2b45cb58c2701f9986c6b1bfa3ce2cefce81` (1332236 B).
- `source_claim` done (coop patch for teko/ngen, owner-approved): **a module's taught words apply
  only in the sources the module claims.** `stage0/` untouched (`git diff origin/main -- stage0/`
  empty). The defect the consumer measured: a word registration enters the token table through
  `word_add` and stops lexing as an identifier in EVERY source, the core's own files included, so a
  compiler assembled from the five parts plus the teko module could not compile `<mc/objmodel>`
  (`mc/objmodel:293: name reserved by a syntax/type_alias registration: type` -- `type` has 23 sites
  in the core, `out` 43). Renaming them defers the next collision; the vocabulary of a dialect is
  open and the core's is fixed.
  * **`void source_claim(uptr fn)`** (`src/hooks.mc`): handler `i64 f(uptr name)`, 1 for a source
    this dialect owns. Growable table, arena tag `T_SRCCLAIM` inserted after `T_SYNTYPE`
    (`src/arena.mc`, `T_COUNT` 41 -> 42, `lim_names`/`lim_seeds` reconciled BY NAME -- the M42
    lesson: the seed 16 belongs to `backends`, which moved from index 33 to 34; `mc limits` gains a
    `source_claim` row). Handlers run in registration order and **any 1 claims the source**; with
    none registered every source is claimed, which is what every compiler did before, byte for byte.
  * **The answer is computed ONCE per frame**, in `lex_push_mem` right after `cp`/`cend` describe
    the new source and before the `on_source` announcement, and kept in the frame record
    (`OF_CLAIMED`, `OF_SIZE` 48 -> 56) -- the identifier branch reads it per lexeme, so it must not
    be a call. **The replay decision is `on_source`'s, in the other direction**: `lex_init` pushes
    the entry before `user_init()` runs, so `source_claim` **re-asks the whole chain for every frame
    still open** (`lex_reclaim_sources`), in push order, at registration time. The whole chain and
    not just the new handler, so that "any 1 claims it" stays true of a frame decided earlier. The
    rule, documented: *every source pushed after a handler registers is decided with it, and every
    source already open is decided again.* Same guard as `on_source` and for the same reason
    (measured SIGSEGV): a claim handler that pushes is `source_claim handler pushed a source:
    <name>`.
  * **The scoped/unscoped rule, as written**: the mark is per TOKEN ENTRY (`TE_TAUGHT`, `TE_SIZE`
    32 -> 40 -- the one field stage0's `TokEnt` does not have, a deliberate divergence like
    `MAXSTRS`/`MAXPARAMS`), set by **`word_add` alone** -- and not an id threshold, because the two
    roads interleave: a `#rule` in a source adds tokens while a taught compiler parses. So the six
    word registrations are scoped (`syntax`, `syntax_stmt`, `syntax_expr`, `syntax_infix`,
    `type_alias`, `type_new`) and `#token`/`#infix`/`#prefix`/`#rule` are **not** -- they come from
    a directive in a source and belong to whoever included it, which is what keeps `<prelude>`'s
    `while` and `for` working in the core itself. `intrinsic()` claims a call name, not a lexeme, so
    it is not scoped either. Only the **identifier branch** is scoped: a taught OPERATOR carries the
    mark and nothing changes for it, since punctuation cannot collide with a name. And **the core's
    own `i32`** goes through `word_add` too (M45's `type_new`), so `core_types_init()` un-marks it
    in the same line it registers it -- a core primitive is not something a module taught; without
    that one line a `.tk`-claiming module would have scoped `i32` out of every `.mc` file.
  * Enforcement is one helper, `lex_word_id`, at the two places the identifier branch resolves a
    lexeme (`lex_next` and `subst_apply`, so a `p_subst_name` replacement is scoped like anything
    else); `word_id` itself stays a plain table lookup, because a module asking for the id of a word
    (`examples/lang` does) is asking the registry, not lexing a source.
  * **The defect, fixed with it**: `subcommand_usage()` printed every ROW while `subcommand_find`
    dispatches back to front, so a module re-registering `build` had the name listed twice and the
    entry that would never run described. It now prints **one line per name, in first-registration
    order, with the text of the last registration** -- the two ends of the table on purpose: the
    order keeps `build`/`limits`/`sysroot` byte for byte where they were, the text keeps the listing
    a description of the compiler that exists.
  Proofs, all in `scripts/check-surface.sh` (**139 ok lines**) over `lib/claim_demo.mc` -- the two
  colliding words (`syntax("type")`, `syntax_expr("out")`) shared by three compilers that differ by
  ONE registration: (a) `main.tk` uses the taught words and `#include`s a `side.mc` whose parameters
  are named `type` and `out` -- compiles and exits **42**; (b) the same program through
  `lib/user_claim_open.mc` (the words, no `source_claim`) is
  `side.mc:3: name reserved by a syntax/type_alias registration: type`; (c) `lib/user_claim_none.mc`
  (a handler that claims nothing) refuses `main.tk` itself with `type expected at top level` -- a
  module that claims no source has taught the compiler nothing any source can reach, which is the
  rule and not an exception; (d) the point of the hook: the claiming compiler compiles **`src/mc.mc`
  from disk AND `<mc/host>` + `<mc/core>` + `<user_default>` from the bundle, to objects byte for
  byte the ones the untaught compiler writes**, while the unscoped one dies on
  `mc/objmodel:293` -- the consumer's report, reproduced and fixed; (e) inertness:
  `lib/user_claim_nop.mc` (only registration `source_claim`, claiming everything) gives
  byte-identical `--dump-ast` and objects over the whole `tests/` corpus; (f) the subcommand fix,
  through a recreated compiler (`<mc/host>` + `<mc/core_min>` + its own `main`, since `user_init`
  runs after the dispatch): `demo` registered twice prints **one** usage line, the second text, and
  `mc demo` exits 42. The nine `lib/*claim*` fixtures are deliberately NOT in `tools/bundle.list`
  (the M41 precedent for check-script-only modules). `scripts/check-docs.sh` gained `source_claim`
  as a fifth EXACT name, so the gate covers it (**199 symbols**).
  -- cost in `src/`: **217 added lines, 111 of them neither comment nor blank** (`lex.mc` +120/63,
  `hooks.mc` +77/34 -- 9 of those the subcommand fix --, `arena.mc` +20/14, twelve of the last
  being the renumbered tags and the two seed rows). Five new globals: the seed's `MAXGLOBALS` goes
  from 449/512 to **454/512 (88%)**, `check-limits` fails at 90%.
  `make bundle` re-run BEFORE bootstrapping (93 files, raw 1188987 -> LZ 555913, blob 557075 B).
  `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test` 32/32,
  `check-lex` 158/158 (3 skipped), `check-ast`/`check-asm` 159/159 (2 skipped), `check-obj` **32/32
  identical to the frozen seed**, `check-bundle`, `bootstrap` at a fixed point (`mc2.o == mc3.o`,
  1276936 bytes; the `--dump-asm` diff between `mc1` and `mc2` is **empty**), `check-surface` 32/32
  + the six new cases + inert, `test-exe` 32/32, `check-mc` 15/15, `check-standalone`,
  `check-parts`, `check-toml` 10/10, `check-build` 53/53, `check-stubs` 9/9, `check-sysroots`,
  `check-limits` **17/17 under 90%**, `check-minimal`, `test-linux` 41/41, `test-linux-x86_64`
  39/39, the four `--exe` cells 44/44 + 44/44 + 42/42 + 42/42, `test-windows` 42/42 and
  `test-windows-x86_64` 40/40 objects cross-compiled and linked, `check-examples`, `check-lang`,
  `check-conc`, `check-desktop`, `check-float` (13/13 macos, 13/13 linux/aarch64, 13/13
  linux/x86_64, 11/11 + 11/11 windows objects), `check-wide`, `check-kernel`, `check-avr`,
  `test-sandbox` 60 ok / 1 skipped, `check-docs` (199 symbols, 36 flags, 27 TOML keys, 10
  directives, 51 samples, 368 links), `site` + `check-site`.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main` ed3ae34):
  **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for
  `examples/api`, `lang`, `conc`, `desktop` and `kernel` -- nothing in the corpus registers a claim,
  so nothing it emits could move. `make check-linux-host` RC 0 over all four cells (aarch64 and
  x86_64, musl and gnu), each after its own `mc2l.o == mc3l.o` and with the cross proof green.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `4bcf3cd8...17df06` -> `f4a841bcf1fc680e1007e1c9a421e4d52f2c91300d4fc6dde08034e333db1083`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `23a73d36ab003d0f7e767bdb89bc01d545300a0a77e5393ac2ceca577bdca431`, `mc2-linux-x86_64.sha256`
  `fa119b12592eb7e30700a59b2887c4de16850867d2f796f957e783143b999b0b`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `a920e766c767a1d0dd0b93309069111611f5b164dc9a20b7f181b3cbe5dd1824` (1303515 B),
  `mc2-windows-x86_64.sha256`
  `b7c77f88893ab4ac58fff6bfbb8baddafbb532967a861eda9bce18ccf9d6a354` (1339163 B).
  Docs: `docs/reference/hooks.md` (§ 3 is now six word registrations + **seven** hooks that claim
  none, the `source_claim` section with the scoped/unscoped table, the replay rule and the two
  interactions -- `on_source` and `#rule`; `subcommand_usage`'s rule in § 7),
  `docs/reference/diagnostics.md` (one new row, and the `name reserved` row now names the escape),
  `docs/reference/cli.md` (the usage listing), `docs/surface.md` (§ "Where a module's words
  apply", and the registration table).
- The default registry is `https://pkg.minicompiler.dev` (2026-09-06; `docs/specs/M44.md` § 4
  Deviations): **one string literal, and the mismatch it closes.** `pkg_default_registry()` in
  `src/pkg.mc` answered `https://minicompiler.dev/registry` and `mc pkg` reads
  `<registry>/index/<name>.toml`, while the deployed server serves the index at
  `https://pkg.minicompiler.dev/index/<name>.toml` -- so `mc pkg sync|add|check` with no
  `--registry` and no `[registry].url` asked for a path that answered the site's static 404
  (measured: `curl -o /dev/null -w %{http_code}` gives `404 text/html` for
  `https://minicompiler.dev/registry/index/mc.toml` and `404 text/plain` for
  `https://pkg.minicompiler.dev/index/mc.toml`, which is the registry saying "no such package" --
  no version is published yet). The literal now names the canonical host: the one the rows' own
  `url` and archive addresses already point at, and the one `MCREG_PKG_BASE` sets on the server.
  **The registry moved first** (`minicompiler/mc-registry` PR #11: the site host answers
  `/registry/index/<name>.toml` with the registry host's own handler -- same generator, same
  `application/toml`, same `public, max-age=300`, same 404 -- an alias and not a second layout),
  so a compiler older than this change is not stranded by the flip.
  Measured here with the new `build/mc1`, no `--registry`, no `[registry].url`:
  `fetch  index mathx` / `url    https://pkg.minicompiler.dev/index/mathx.toml`, and with `--yes`
  the downloader is spawned against exactly that URL.
  Docs: `docs/reference/packages.md` (which also records the alias), `docs/reference/toml.md`,
  `docs/reference/cli.md`, `docs/build.md`, `docs/guide/25-packages.md`, `docs/specs/M44.md` § 4,
  and `docs/guide/27-publishing.md` § 10, whose "until the compiler's default is updated to match,
  name the registry explicitly" workaround (merged as #38 while this branch was in flight) is
  replaced by the fact -- no `--registry` is needed, and an older compiler keeps working through
  the alias.
  No global was added (`check-limits` still reports `globals 454/512, 88%`), and nothing the
  compiler emits moved: `scripts/check-inert.sh` against a `build/mc1` built from `origin/main`
  f6c6c3d is **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts
  for `examples/api`, `lang`, `conc`, `desktop` and `kernel` -- the five goldens move only through
  the string and the bundle.
  `make bundle` re-run before bootstrapping (93 files, raw 1189363 -> LZ 556103, blob 557265 B).
  `make check` **RC 0, zero FAIL**: `budget` 2848/3000, `test` 32/32, `check-lex` 158/158
  (3 skipped), `check-ast`/`check-asm` 159/159, `check-obj` **32/32 identical to the frozen seed**,
  `check-bundle`, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 1277128 B; the `--dump-asm` diff
  between `mc1` and `mc2` is **empty**), `check-surface` 32/32, `test-exe` 32/32 via `--exe`,
  `check-mc`, `check-standalone`, `check-parts`, `check-toml` 10/10, `check-build`,
  **`check-pkg` 94/94**, `check-sysroots` (13 rows), `check-stubs` 9/9, `check-limits`
  **17/17 under 90%**, `check-minimal`, `test-linux` 41/41 and `test-linux-x86_64` 39/39,
  the four `--exe` cells 44/44 + 44/44 + 42/42 + 42/42, `test-windows` 42/42 and
  `test-windows-x86_64` 40/40 objects cross-compiled and linked, `check-examples`, `check-lang`,
  `check-conc`, `check-desktop`, `check-float`, `check-wide`, `check-kernel`, `check-avr`,
  `test-sandbox` 60 ok / 0 failed / 1 skipped, `check-docs` (199 symbols, 36 flags, 27 TOML keys,
  10 directives, 51 samples, 382 links), `site` 91 pages + `check-site` 0 link problems
  (numbers from the run after the rebase onto `da506ce`, which brought
  `docs/guide/27-publishing.md` in).
  `make check-linux-host` **RC 0 over all four cells** (aarch64 musl/gnu, x86_64 musl/gnu), each
  after its own `mc2l.o == mc3l.o` and with the cross proof
  (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`) green.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `f4a841bc...db1083` -> `322c18093d78ef18853b9493ef261c0d29ac36c3cd247c391d8a740cdbc29581`
  (empty `--dump-asm` diff + `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `d04e0e50d603d90dd3ee8f209fbb45bf8ea0ddb11936fb2f794a0973f38cc24b`,
  `mc2-linux-x86_64.sha256`
  `379c9f96701dc47a878961c9e4f4c2cac848d6ac7fd4760c92080b4368d81784`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `fa601d8fa1ebee27fc9b598b15b3f60b3889d32efe62aef4a87edf85be6a913c` (1303703 B),
  `mc2-windows-x86_64.sha256`
  `bebd088c036e53c8a00932693f83fffbfbac0c24899b63ea4dc700db60ae1a6a` (1339351 B), both also
  written byte for byte by `build/mc2`.
- `source_claim`, the second half (coop patch for teko/ngen, owner-approved): **a lexeme that is
  also a `#rule`/`#token`/`#infix` literal stays a word in unclaimed sources.** `stage0/` untouched
  (2848/3000, `git diff origin/main -- stage0/` empty). The defect the consumer hit after PR #37,
  reproduced in a pristine worktree at `origin/main` before anything was written: `tok_add` is
  idempotent per lexeme, so `syntax_stmt("while", &h)` marks the very token entry `<prelude>`'s
  `#rule stmt: while ( expr $c ) block $b` dispatches on, and `lex_word_id` then hid `while` in
  every source the module did not claim -- the core's own files included. A program that
  `#include <prelude>` and writes `while (i < 7) { ... }` came out of the taught compiler as
  **`plain.mc:6: expected ; after expression`, exit 1** (the word lexed as an identifier, the
  condition as a call, and then `{` arrived where the `;` was expected), while the default compiler
  ran the same file to exit 42. PR #37's brief only covered distinct lexemes.
  * **A second bit in the same field, not a second field.** `TE_TAUGHT` (offset 32 of a TokEnt,
    `TE_SIZE` unchanged at 40) now carries `TE_TAUGHT_BIT 1` -- set by `word_add`, what
    `source_claim` scopes -- and `TE_RULE_BIT 2`, set on the DIRECTIVE road by one helper in
    `src/parse.mc`, `tok_add_dir`, at the three `tok_add` call sites that are a directive
    (`do_rule`'s pattern literal, `#token`, `#infix`/`#prefix`). The two roads are not exclusive,
    so neither bit speaks for the other: `tok_set_taught` preserves bit 2 (`core_types_init`'s
    un-marking of `i32` still works), and `tok_set_rule` marks only a **word** entry -- a
    punctuation lexeme is never resolved through `lex_word_id`, so the bit would have nothing to
    say about `{` or `+=` and could only surprise a `syntax_stmt("{")`.
  * **The lexer stops hiding it, the parser keeps scoping it.** `lex_word_id` returns the id for a
    `TE_RULE` lexeme in any source (the rule has to fire where the module does not reach), and one
    helper, `taught_here(tok)` = `lex_claimed() || !tok_is_rule(tok)`, guards the three
    module-handler dispatches -- `parse_top` (`syntax_find`), `parse_stmt_core`
    (`syntax_stmt_find`) and `parse_primary` (`syntax_expr_find`). The `*_find` functions
    themselves are untouched, so `word_is_taught` and `parse_block`'s `syntax_stmt(K_LBRACE)` case
    are exactly what they were. `syntax_infix` needs nothing: an operator is punctuation and never
    goes through `lex_word_id`, and M21's "a `#infix` on the token drops the handler" stays.
    Out of scope, written down: a word that is both a `#rule` literal and a taught TYPE
    (`type_alias`/`type_new`) -- `type_of_token` is not consulted through `taught_here`.
  * **Cost: 88 added lines in `src/`, 35 of them neither comment nor blank**
    (`git diff --numstat src/`, ignoring the generated `src/bundle_data.mc`: `src/lex.mc` +56/-12,
    `src/parse.mc` +32/-6). **Zero new globals** -- `check-limits` still reports
    `globals 454/512, 88%`, the same row as before the patch.
  Proof (`scripts/check-surface.sh`, three new `ok` lines) over `lib/claim_rule.mc` +
  `lib/user_claim_rule.mc` + `lib/mc_claim_rule.mc`: a module that registers
  `syntax_stmt("while", &cr_while)` -- a `while` that is **not a loop**, it runs its body at most
  once -- and `source_claim` for `.tk` alone. One program in two files: the unclaimed `.mc` file
  `#include <prelude>` and exits **42** under the taught compiler AND under `build/mc1` (the
  prelude's loop), the claimed `.tk` file with the same six lines exits **6** (the module's `if`),
  and `--dump-tokens` of the unclaimed file is byte for byte the default compiler's -- the bit
  changes a dispatch, never a token. The three new `lib/` fixtures are deliberately NOT in
  `tools/bundle.list` (the M41 precedent for check-script-only modules, which the PR #37 claim
  fixtures already follow).
  -- `make bundle` re-run BEFORE bootstrapping (`src/lex.mc` and `src/parse.mc` are bundled):
  93 files, raw 1192948 -> LZ 557673, blob 558835 B. `make check` green end to end (**RC 0, zero
  FAIL**): `budget` 2848/3000, `test` 32/32, `check-lex` 161/161 (3 skipped), `check-ast` 162/162,
  `check-asm` 162/162, `check-obj` **32/32 identical to the frozen seed**, `check-bundle`,
  `bootstrap` at a fixed point (`mc2.o == mc3.o`, 1279840 bytes; the `--dump-asm` diff between
  `mc1` and `mc2` is **empty**), `check-surface` 32/32 + the three new source_claim cases + inert,
  `test-exe` 32/32, `check-mc` 15/15, `check-standalone`, `check-parts`, `check-toml` 10/10,
  `check-build` 53/53, `check-pkg` 94/94, `check-stubs` 9/9, `check-sysroots`, `check-limits`
  **17/17 under 90%** (globals 454/512 = 88%, unchanged), `check-minimal`, `test-linux` 41/41 and
  `test-linux-x86_64` 39/39, the four `--exe` cells 44/44 + 44/44 + 42/42 + 42/42,
  `test-windows` 42/42 and `test-windows-x86_64` 40/40 objects cross-compiled, `check-examples`,
  `check-lang` 18, `check-conc` 21, `check-desktop`, `check-float`, `check-wide`, `check-kernel`
  (QEMU 11.0.1), `check-avr`, `test-sandbox` 60 ok / 0 failed / 1 skipped, `check-docs`
  (199 symbols, 36 flags, 27 TOML keys, 10 directives, 51 samples, 382 links), `site` 91 pages +
  `check-site` 0 link problems + `check-site-linux` 11/11.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main`
  9c74738): **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts
  for `examples/api`, `lang`, `conc`, `desktop` and `kernel` -- nothing in the corpus registers a
  claim, so `taught_here` answers 1 everywhere and the bit is never read.
  `make check-linux-host` **RC 0 over all four cells** (aarch64 musl 41/41 and gnu 42/42, x86_64
  musl 39/39 and gnu 40/40), each after its own `mc2l.o == mc3l.o` and with the cross proof
  (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`) green.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `322c1809...c29581` -> `4d9ca0735ae746d351e0368d9fb4dd9af572264b8a37a4dc594833c16463ad45`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `276bd9a13171adee5d1b8a4090189413b96dba6b81619f65a613559eb455abba`,
  `mc2-linux-x86_64.sha256`
  `5f2b89327e5d0b746ff6867b62e39cdbcf80ae24e461628ccb67720d709b292e`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `b73a72b1d109366d43e9e6ab1709bf4fd44e2cb4fdc30d3c36773c23fafcfe86` (1306476 B),
  `mc2-windows-x86_64.sha256`
  `18708fe4c2287d901796da8637bee5a297667a68f93b2349ccb95b7182aca498` (1342256 B), both also
  written byte for byte by `build/mc2`.
  Docs: `docs/reference/hooks.md` § `source_claim` (the table row, and a new "a lexeme both roads
  created" paragraph: the directive's bit wins in the lexer, the module's bit still scopes the
  handler), `docs/surface.md` § "Where a module's words apply".
- `machine()`: a registration no longer steals the current machine (coop patch for teko/ngen,
  owner-approved). `stage0/` untouched (2848/3000, `git diff origin/main -- stage0/` empty).
  The defect, reported by the consumer with a `--dump-machine` transcript and **reproduced in a
  pristine worktree of `origin/main` before anything was written**: `machine()` ended with an
  unconditional `mach_tab = tab;`, so EVERY registration became the machine the walker drives --
  a re-registration of an existing name included (M24's D5 reuses the name's slot, and moved the
  current with it). `src/cli.mc` selects the HOST's machine (`machine_use_if(host_machine())`)
  BEFORE `user_init()`, so a module that derives all three bundled machines under their own names
  -- which is what teaching a type family looks like, one derived copy per name, and exactly what
  `<float>` does -- left the LAST one in effect. Measured on this macOS/aarch64 host with a
  fixture that changes not one slot: `machine x86_64-win (current)` where the stock compiler says
  `machine arm64 (current)`, and `mc x.mc --dump-asm` printing **Win64 x86-64** (`push rbp` /
  `mov [rbp-8], rcx`) for a program the same compiler builds correctly with `--exe`. `mc build`
  never saw it, because every backend calls `machine_use` as its first statement (M37); the raw
  single-file road -- no `[target]`, no backend for a dump -- did.
  * **The rule, and it is the NARROWER of the two the brief offered, by measurement.** A
    registration becomes current when there is no machine yet, when the name is **new**, or when
    it **replaces the name that is current**; a registration of some other REGISTERED name does
    not. The strict form ("a new name does not become current either") was implemented first and
    **`make check-kernel` failed with it**: `examples/kernel/test.sh:423` asks the taught compiler
    for `--dump-syms` with no `--machine=`, and the kernel's `__TEXT,__text` came out **2400 bytes
    / 83 relocations** (the host's arm64) where the riscv64 machine writes **3184 / 58**, so the
    sweep's independently recomputed pc-relative displacements disagreed -- `main.mc: 0 byte
    mismatches, 35 wrong displacements`, `tests/sweep.mc: 25`, `800 generated functions: 39`,
    3 FAILED, against `examples/kernel: OK` on `origin/main`. A compiler taught a target the host
    does not have has exactly one machine that can be meant; taking it away would make every such
    compiler name it on every dump. The measurement is written into the doc comment above
    `machine()`, not just here.
  * **Cost: 51 added lines in `src/`, 4 of them neither comment nor blank**
    (`git diff --numstat src/`, ignoring the generated `src/bundle_data.mc`: `src/hooks.mc`
    +43/-5, `src/cli.mc` +8/-6 -- the second file is comment only). **Zero new globals** (`cur` is
    a local): `check-limits` still reports `globals 454/512, 88%`, the same row as before.
  Proof (`scripts/check-surface.sh`, four new `ok` lines) over `lib/user_remach.mc` +
  `lib/mc_remach.mc`: a module whose `user_init` copies and re-registers all three bundled
  machines under their own names, in the order `arm64`, `x86_64`, `x86_64-win`, changing NO slot.
  (1) `--dump-machine` shows `machine arm64 (current)`; (2) `--dump-asm` of a small program is
  **byte for byte** `build/mc1`'s (pre-fix it was x86-64 text); (3) the derived compiler still
  builds and runs a program with `--exe` (exit 42); (4) `--machine=x86_64` still selects it
  explicitly. `lib/user_badmach.mc`'s M24 case is untouched and green -- it replaces one slot of
  `arm64`, which IS current, so it stays current and `v(50) + v(8)` is still 42. The two new
  `lib/` fixtures are deliberately NOT in `tools/bundle.list` (the M41 precedent for
  check-script-only modules).
  -- `make bundle` re-run BEFORE bootstrapping (`src/hooks.mc` and `src/cli.mc` are bundled):
  93 files, raw 1195703 -> LZ 558997, blob 560159 B. `make check` green end to end (**RC 0, zero
  FAIL**): `budget` 2848/3000, `test` 32/32, `check-lex` 163/163 (3 skipped), `check-ast` 164/164
  (2 skipped), `check-asm` 164/164, `check-obj` **32/32 identical to the frozen seed**,
  `check-bundle` (lz round trip 117 cases), `bootstrap` at a fixed point (`mc2.o == mc3.o`,
  1281320 bytes; the `--dump-asm` diff between `mc1` and `mc2` is **empty**), `check-surface`
  32/32 + the four new `machine()` cases + inert, `test-exe` 32/32, `check-mc` 15/15,
  `check-standalone`, `check-parts`, `check-toml` 10/10, `check-build` 53/53, `check-pkg` 94/94,
  `check-stubs` 9/9, `check-sysroots` (13 rows), `check-limits` **17/17 under 90%**
  (globals 454/512 = 88%), `check-minimal`, `test-linux` 41/41 and `test-linux-x86_64` 39/39,
  the four `--exe` cells 44/44 + 44/44 + 42/42 + 42/42, `test-windows` 42/42 and
  `test-windows-x86_64` 40/40 objects cross-compiled (42 and 40 linked with `lld-link`),
  `check-examples`, `check-lang` 18, `check-conc` 21, `check-desktop`, `check-float` (13/13 on
  each of the three run legs, 11/11 + 11/11 windows objects, four llvm-mc sweeps), `check-wide`,
  **`check-kernel` OK (0 skipped)** -- the gate the strict rule broke -- `check-avr` OK,
  `test-sandbox` 60 ok / 0 failed / 1 skipped, `check-docs` (199 symbols, 36 flags, 27 TOML keys,
  10 directives, 51 samples, 383 links), `site` 91 pages + `check-site` 0 link problems +
  `check-site-linux` 11/11.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main`
  ff74346): **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts
  for `examples/api`, `lang`, `conc`, `desktop` and `kernel` -- nothing in the corpus registers a
  second machine under a name another machine already has.
  `make check-linux-host` **RC 0 over all four cells** (aarch64 musl 41/41 and gnu 42/42, x86_64
  musl 39/39 and gnu 40/40), each after its own `mc2l.o == mc3l.o` and with the cross proof
  (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`) green.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `4d9ca073...63ad45` -> `2c6efc3229f3395a68018afcc55bac0997770a8501106d9a39cb75524eb95573`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted
  and re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `60082c7e3753c8e82651616d982346214a3d4037de1b9b7933444511b6cf62e9`,
  `mc2-linux-x86_64.sha256`
  `b69836286c23e38fa8644059f78ddb8673e8038ecf572d7911725df2ee6f8490`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `9657897e62c7e61e2e3fa2881f19e2b7e39df6f9302bfb17eecfa15d55f4cd98` (1307956 B),
  `mc2-windows-x86_64.sha256`
  `bcdfff8a8a44d51c9c08ec101a2c75fcd81d3f7c284b9e6538cc3722419d54cc` (1343760 B), both also
  written byte for byte by `build/mc2`.
  Docs: `docs/reference/hooks.md` § `machine`/`machine_use` (the four-row table of what a
  registration does to the machine in effect, and the `machine_use_if(host_machine())` correction
  two paragraphs down), `docs/reference/machine.md` § 1 (which stated the old rule twice).
- The driver's state in one arena record (globals diet, C0): **twelve file-level globals in
  `src/driver.mc` became one**, in the shape `src/sandbox.mc` uses for `sb_state`. Capacity work
  only -- nothing the compiler emits changes. The reason is a number: the frozen seed's
  `MAXGLOBALS` is 512, `scripts/check-limits.sh` fails at 90% (460), and `src/mc.mc` was at
  **454/512 (88%)** with M48 still to land.
  `cfg_file drv_sdk_cache drv_target drv_os drv_arch drv_stubs_cache drv_unit drv_stub_mode
  drv_bname drv_static drv_lim_mode drv_tol` are now the twelve `DRV_*` fields of a 96-byte
  record `drv_state` points at, allocated on first use by `drv_rec()` (`xalloc` + `mem_zero`) --
  which is also where the two non-zero starting values live, `DRV_TARGET` -1 and `DRV_TOL` 2500,
  so a reader that runs before any TOML was parsed sees exactly what the initialized globals
  held. Each global kept its name as the accessor (`drv_os()` to read, `set_drv_os(v)` to write),
  so every call site reads the same. Three files were touched, because two of the twelve are read
  from outside `driver.mc` and always were: `src/pkg.mc` (`cfg_file`, 9 sites, including the
  `set_cfg_file(cfg)` in `pkg_open_config`) and `src/sysroot.mc` (`cfg_file` twice and
  `set_drv_stub_mode(1)` in `sysroot_cmd`). Both are in parts that include `driver.mc`
  (`<mc/core_build>`, `<mc/core_pkg>`), and every part still stands on its own -- `check-parts`
  is green.
  -- cost (`git diff --numstat` on `src/`, the generated `src/bundle_data.mc` excluded):
  `driver.mc` +116/-62, `pkg.mc` +9/-9, `sysroot.mc` +3/-3 = **128 added lines, 104 of them
  neither comment nor blank**. The seed's rows move as expected: **globals 454/512 (88%) ->
  443/512 (86%)**, exactly -11 (twelve replaced by one), and `funcs` 1673 -> 1698 / `lowered`
  1657 -> 1682, the 25 new functions being 12 readers, 12 writers and `drv_rec`.
  **The inertness proof is the whole point and it held.**
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main`
  0884e93): **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts
  for `examples/api`, `lang`, `conc`, `desktop` and `kernel`, each through the taught compiler its
  own side builds (`--compiler-only` then `--entry-only`). The plain `mc build` road was measured
  separately for the same reason and agrees: `build/api` 55632 B, `build/lang-demo` 36214 B,
  `build/conc-demo` 55206 B and `build/kernel.bin` 3304 B are `cmp`-identical between the two
  compilers. `diff <(mc1.pre --dump-asm src/mc.mc) <(mc1 --dump-asm src/mc.mc)` is **empty** --
  that dump is of the SOURCE each compiler is given, and both compile the same tree identically.
  What did move is the compiler's own body, and it is confined: compiling `origin/main`'s
  `src/mc.mc` and this tree's with the same compiler gives **25 new function labels** (the
  accessors and `drv_rec`), **none removed**, and of the 1657 functions both trees have, **24
  differ** -- the 15 in `driver.mc`, 3 in `sysroot.mc` and 6 in `pkg.mc` that read or write one of
  the twelve, and nothing else.
  -- `stage0/` untouched, 2848/3000. `make bundle` re-run BEFORE bootstrapping (`src/driver.mc` is
  bundled as `mc/driver`): 93 files, raw 1198910 -> LZ 560054, blob 561216 B.
  `make check` green end to end (**RC 0, zero FAIL**): `test` 32/32, `check-lex` 163/163
  (3 skipped), `check-ast`/`check-asm` 164/164, `check-obj` **32/32 identical to the frozen
  seed**, `check-bundle` (lz round trip 117 cases), `bootstrap` at a fixed point
  (`mc2.o == mc3.o`, 1283768 bytes; the `--dump-asm` diff between `mc1` and `mc2` is **empty**),
  `check-surface` 32/32 + inert, `test-exe` 32/32, `check-mc` 15/15, `check-standalone`,
  **`check-parts`** (the parts + `<mc/main>` == `<mc/core>`, 1283768 B; all six parts stand alone),
  `check-toml` 10/10, **`check-build` 53/53**, **`check-pkg` 94/94**, `check-stubs` 9/9,
  `check-sysroots` (13 rows), **`check-limits` 17/17 under 90% (globals 443/512, 86%)**,
  `check-minimal`, `test-linux` 41/41 and `test-linux-x86_64` 39/39, the four `--exe` cells
  44/44 + 44/44 + 42/42 + 42/42, `test-windows` 42/42 and `test-windows-x86_64` 40/40 objects
  cross-compiled and linked, `check-examples`, `check-lang` 18, `check-conc` 21, `check-desktop`,
  `check-float` (13/13 macos, 13/13 linux/aarch64, 13/13 linux/x86_64, 11/11 + 11/11 windows
  objects), `check-wide`, `check-kernel` (QEMU 11.0.1), `check-avr`, `test-sandbox` 60 ok /
  0 failed / 1 skipped, `check-docs` (199 symbols, 36 flags, 27 TOML keys, 10 directives,
  51 samples, 383 links), `site` 91 pages + `check-site` 0 link problems + `check-site-linux`
  11/11. `make check-linux-host` RC 0 over all four cells (aarch64 musl 41/41 and gnu 42/42,
  x86_64 musl 39/39 and gnu 40/40), each after its own `mc2l.o == mc3l.o` and with the cross proof
  against the macOS `build/mc2.o` green.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `2c6efc32...b95573` -> `38470e10413085868ee9dab94f42639f79d92a8e7853a49a55fe228c1dd6de2a`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `3eefd537966783595b8e2045570e7b1d01939057f3e6ecf00c8263401a52d6ab`,
  `mc2-linux-x86_64.sha256`
  `6b5b78348fb1c8eba1f5f06f6ead872023df9ba15b4d507e825e4abc317e7054`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `4a8e99ca9a9c480b0bd75d144058f56a0577f3df2d94dbf4212c5210a4d088c2` (1310361 B),
  `mc2-windows-x86_64.sha256`
  `d7c8e3e17d7c19abd4b77175405502a6b00fd0cece5ed307ddd5ab2736009ee1` (1347401 B), both also
  written byte for byte by `build/mc2`.
  Docs: nothing in `docs/reference/` named any of the twelve; `docs/build.md` § M39.5 mentioned
  `drv_os`/`drv_arch` and now says `drv_os()`/`drv_arch()`, two fields of the driver's state
  record. `docs/specs/M25.md` and `docs/specs/M39.md` are left as they are -- a spec records the
  tree of its own day.
  Seen and NOT done here: `src/deps.mc` carries **one** file-level global beside its `dp` record
  (`dp_libs_opt`, `--libs-dir`), which is a saving of 1; `src/pkg.mc` and `src/fetch.mc` carry
  none beside `pk` and `fx`. The cheap diets left are elsewhere and bigger -- the three object
  writers, `backend_elf_exe.mc` 38, `backend_exe.mc` 27 and `backend_elf.mc` 17, which is the 82
  the M43 step A entry already named.
- A cast on a `callp` declares its return type; `<float>`'s arm64 machine maps the four
  single-precision conversions (coop patch for the teko/ngen consumer, owner-approved). Two
  defects, one in `src/` and one in `lib/`, plus a third the second one uncovered.
  `stage0/` untouched (2848/3000, `git diff origin/main -- stage0/` empty).
  1. **`callp` was typed `TY_I64` unconditionally** (`src/gen_resolve.mc`), so `walk_ret_type()`
     said "integer" for every indirect call and `<float>`'s `fa_result`/`fx_result` never moved
     `d0`/`xmm0` into the destination -- the pointer's own bits stayed at the depth and the
     arithmetic around the call read them. Measured before anything changed, with a `mc-float`
     built from `origin/main` 900c569: `f64 dbl(f64 x) { return x * 2.0; }` and
     `f64 nested = 1.0 + callp(&dbl, 2.0);` printed **`3.0` / `0x4008000000000000`** where 5.0 was
     the answer. **The contract is that a cast applied DIRECTLY to a `callp` DECLARES what the
     call returns**: there is no callee to read a signature from, and a cast is the only syntax in
     the language that names a type inside an expression. Three code lines in the `N_CAST` arm of
     `res_expr` -- if the operand is an `N_CALL` bound to `RK_INTRIN`/`IN_CALLP`, `set_res_type` it
     to the written type -- and `1.0 + (f64) callp(&dbl, 2.0)` is `0x4014000000000000`. A `callp`
     with no cast is still `TY_I64`, which is what makes the change inert.
     The narrow half follows from it, in `gen_callp` (`src/gen_walk.mc`): `walk_narrow(res_type(n))`
     then `set_walk_depth_type(depth, rt)` + `MTASK_CAST`, gen_call's M45 block verbatim and in the
     same order, because after `MTASK_CALLP` the depth still describes the POINTER -- argument 0 --
     and a derived machine reads that as the cast's source type. On the value it changes nothing
     today (`lower_expr`'s `N_CAST` arm issues its own `MTASK_CAST` whatever the operand's type is,
     and both the core cast and `fa_cast`'s delegation narrow correctly); what it buys is that the
     call's own depth carries its declared type the way a direct call's has since M45. It costs one
     idempotent `sxtw` on `(i32) callp(...)`, a construct nothing in the corpus writes.
  2. **`fa_w` did not map the single-precision conversions** (`lib/machine_arm64_float.mc`). The
     AArch64 machine picks the single form of an operation by walking a fixed distance in its own
     opcode table; the arithmetic pair, the neg/abs/sqrt/mov range, the compares, the load and the
     store were mapped and the four conversions were not, so `FI_SCVTF_S`/`FI_UCVTF_S`/
     `FI_FCVTZS_S`/`FI_FCVTZU_S` existed and were never chosen. Measured pre-fix:
     `i64 main() { f32 y = 2.5f; return (i64)(y * 10.0f); }` emitted **`fcvtzs x9, d16`** on a
     register holding a single and exited **0** instead of 25. Both pairs sit two rows above their
     own double form, so the fix is two lines; after it the same source is `fcvtzs x9, s16`,
     exit 25. `fx_w2` in `lib/machine_x86_64_float.mc` already mapped `FX_CVTSI_D -> FX_CVTSI_S`
     and `FX_CVTT_D -> FX_CVTT_S`, which is why the x86-64 leg was right -- **no omission there**,
     confirmed by dumping the two new tests with `--machine=x86_64` (`cvtsi2ss`, `cvttss2si`).
  3. **Uncovered by (2): the two `_S` cvtf rows carried the wrong encoding.** `FI_SCVTF_S` and
     `FI_UCVTF_S` were `0x1E220000`/`0x1E230000` -- `scvtf s, w` and `ucvtf s, w`, a 32-bit SOURCE
     -- while their `fa_rdk`/`fa_rnk` columns (and therefore `--dump-asm`) said `s, x`. Invisible
     while the rows were unreachable; the first run of the fixed mapping printed `(f32) 0xffff...`
     as `0x4f800000` (2^32, the low half converted) instead of `0x5f800000` (2^64).
     `llvm-mc -triple=arm64-apple-darwin` says `scvtf s16, x9` is `0x9E220000` and `ucvtf s16, x9`
     `0x9E230000`; with those two words the sweep re-assembles every one of them byte for byte,
     which is exactly the check that would have caught the original error had the rows been live.
  4. **Then CI found the Win64 half of the same call** (`lib/machine_x86_64_float.mc`, the leg
     `Link and run the suite (windows/x86_64)`, the only red one): `023-callp-f64` answered
     `0x4000000000000000 ... 0x4070000000000000` -- columns 1 and 3 gave back the callp's own
     ARGUMENT. `fx_call`/`fx_callp` restored the live depths and only then moved the result out of
     `xmm0`, and on Win64 the float depths are `xmm0..xmm5` (`xmm6..xmm15` are callee-saved), so
     depth 0's register **is** the return register: `movsd xmm0, [rbp-8]` overwrote what the callee
     had just returned and `movsd xmm1, xmm0` copied the caller's own 1.0 into the result depth --
     `1.0 + callp(&dbl, 2.0)` = 2.0, and the eight-deep column 255 + 1 = 256.0, both exactly the
     bytes CI printed. The fix is the order, in both slots: `fx_result(d)` BEFORE
     `fx_restore_live(d)`. SysV (`xmm8..xmm13`), AArch64 (`v16..v23` against `d0`) and every
     integer half (`rax` is nobody's depth) could not show it, which is why one order now serves
     all four. Scanning the whole float corpus for the pattern -- a restore of `xmm0` between a
     `call` and the move that reads it -- finds exactly two sites, both in `023`, both only under
     `--machine=x86_64-win`, and none after the fix. `tests/float/025-live-depth-call.mc` is the
     DIRECT-call sibling nothing covered (the same defect: pre-fix it shows the pattern three
     times on `x86_64-win` and nowhere else); `docs/reference/machine.md` § 3 states the rule.
  Proofs. `tests/float/023-callp-f64.mc` (the consumer's repro; a `callp` at a SPILLED float depth
  -- eight live float depths, so `v16..v23` are saved around the `blr` and the result goes to the
  frame with `str d`; two float arguments; and an `f32` result through `(f32) callp(...)`),
  `tests/float/024-f32-cvt.mc` (all six conversions naming an f32 -- `(i64)`, `(u64)`, `(f32) i64`,
  `(f32) u64`, `(f64) f32`, `(f32) f64` -- each bit-recorded, with `(i64)(2.5f * 10.0f) == 25` as
  the exit code) and `tests/mc/096-callp-i32.mc` (`(i32)`/`(u32)` on a callp whose callee returns
  `0x12345678_0000002a`; a regression guard, not a repro, and it says so in its header). The two
  float tests run on all five legs through `scripts/check-float.sh`, 096 on all five through
  `check-mc`/`test-linux`/`test-windows`.
  -- cost (`git diff --numstat`, added lines / added lines that are neither comment nor blank):
  `src/gen_resolve.mc` +17/3, `src/gen_walk.mc` +12/5, `lib/machine_arm64_float.mc` +7/4 =
  **36 added lines, 12 of them code**. **Zero new globals**: `check-limits` reports
  `globals 443/512, 86%`, the same row the globals-diet entry above left.
  `make bundle` re-run BEFORE bootstrapping (93 files, raw 1201128 -> LZ 561071, blob 562233 B).
  `make check` green end to end (**RC 0, zero FAIL**, 21m25s): `budget` 2848/3000, `test` 32/32,
  `check-lex` 163/163 (3 skipped), `check-ast`/`check-asm` 164/164, `check-obj` **32/32 identical
  to the frozen seed**, `check-bundle` (lz round trip 117 cases), `bootstrap` at a fixed point
  (`mc2.o == mc3.o`, 1285176 bytes; the `--dump-asm` diff between `mc1` and `mc2` is **empty**),
  `check-surface` 32/32 + 185 ok lines + inert, `test-exe` 32/32, `check-mc` **16/16**,
  `check-standalone`, `check-parts`, `check-toml` 10/10, `check-build` 53/53, `check-pkg` 94/94,
  `check-stubs` 9/9, `check-sysroots`, `check-limits` **17/17 under 90%**, `check-minimal`,
  `test-linux` 42/42 and `test-linux-x86_64` 40/40, the four `--exe` cells 45/45 (aarch64 musl),
  45/45 (aarch64 gnu), 43/43 (x86_64 musl) and 43/43 (x86_64 gnu), `test-windows` 43/43 objects
  and 43 linked, `test-windows-x86_64` 41/41 and 41 linked, `check-examples`, `check-lang`,
  `check-conc`, `check-desktop`, **`check-float` ok on all five legs** (macos/aarch64 15/15,
  linux/aarch64 15/15, linux/x86_64 15/15, windows/aarch64 13/13 objects, windows/x86_64 13/13,
  2 skipped each), `check-wide` ok, `check-kernel`, `check-avr`, `test-sandbox` 60 ok / 0 failed /
  1 skipped, `check-docs` (199 symbols, 36 flags, 27 TOML keys, 10 directives, 52 samples,
  384 links), `site` 91 pages + `check-site` 0 link problems + `check-site-linux` 11/11.
  **The llvm-mc sweep is the gate for (2) and (3)** and it moved: measured on the unmodified tree
  (13 float tests) **37 (mach-o arm64), 37 (elf aarch64), 182 (elf x86_64), 166 (coff x86_64)**;
  with the two new tests and the fixed machine, **58, 58, 230, 213 distinct instructions
  re-assemble byte for byte, 0 mismatches**, `scvtf s, x` / `ucvtf s, x` / `fcvtzs x, s` /
  `fcvtzu x, s` among them.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main` 900c569
  before the first edit): **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus
  byte-identical artefacts for `examples/api`, `lang`, `conc`, `desktop` and `kernel` through the
  taught compiler each side builds -- the corpus writes no cast on a `callp`, so nothing it emits
  could move. `make check-linux-host` RC 0 over all four cells (aarch64 musl: suite 42/42, `check-mc` 12/12,
  `test-exe` 31/31 via `--exe --libc=musl`; aarch64 gnu 43/43 native; x86_64 musl 40/40, 12/12,
  29/29; x86_64 gnu 41/41 native), each after its own `mc2l.o == mc3l.o` (1612704 B and
  1511480 B) and with the cross proof against the macOS `build/mc2.o` green.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `38470e10...d6de2a` -> `ec50f3e7fc6ad3b9793f2d9d18c54488a8f6a63ec4adab4966bf6a3fbde67723`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256` `5cfac08fd359eeebaaf74c09175e0f586a2b8ddeb577b9671a222f8c5e5be702`,
  `mc2-linux-x86_64.sha256` `67374f73001de2115e7acb89e7147f8bd535b58fb8b9366231cb16a1f57f577c`, each after its own `mc2l.o == mc3l.o` and with the cross
  proof green; the Windows pair cross-computed per `tests/golden/README.md` --
  `mc2-windows-arm64.sha256`
  `2c16fdd6dd8e0986a46c6d19109b2a8712d18507f134a54cdb4902317c9770f9` (1311785 B),
  `mc2-windows-x86_64.sha256`
  `406f23e154ed35c388ef97d4108f352a433d90e63ca3878d393c55355125e9fb` (1348945 B).
  **Re-measured after (4)**, and these numbers supersede the ones above: `make bundle` re-run
  BEFORE bootstrapping (93 files, raw 1201703 -> LZ 561413, blob 562575 B); `make check` green end
  to end (**RC 0, zero FAIL**, 5m34s + the golden re-record) -- `budget` 2848/3000, `test` 32/32,
  `check-lex` 163/163 (3 skipped), `check-ast`/`check-asm` 164/164, `check-obj` **32/32 identical
  to the frozen seed**, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 1285512 bytes; the
  `--dump-asm` diff between `mc1` and `mc2` is **empty**), `check-surface` 185 ok lines,
  `test-exe` 32/32, `check-mc` 16/16, `check-limits` 17/17 under 90%, `test-linux` 42/42 and
  `test-linux-x86_64` 40/40, the four `--exe` cells 45/45 + 45/45 + 43/43 + 43/43,
  `test-windows` 43/43 objects and 43 linked, `test-windows-x86_64` **41/41 and 41 linked**,
  **`check-float` ok on all five legs with the new test** (macos/aarch64 16/16, linux/aarch64
  16/16, linux/x86_64 16/16, windows/aarch64 14/14 objects, windows/x86_64 14/14, 2 skipped
  each) and the sweep at **60 (mach-o arm64), 60 (elf aarch64), 249 (elf x86_64), 232 (coff
  x86_64) distinct instructions, 0 mismatches**, `check-wide`, `check-kernel`, `check-avr`,
  `test-sandbox` 60 ok / 0 failed / 1 skipped, `check-docs` (199 symbols, 36 flags, 27 TOML keys,
  10 directives, 52 samples, 385 links), `site` 91 pages + `check-site` + `check-site-linux`
  11/11. `scripts/check-inert.sh /tmp/premain/build/mc1 build/mc1` (pre = a `mc1` built from
  `origin/main` 900c569): **33 objects identical** plus byte-identical `api`, `lang`, `conc`,
  `desktop` and `kernel`. `make check-linux-host` RC 0 over all four cells (aarch64 musl 42/42 +
  `test-exe` 31/31, aarch64 gnu 43/43, x86_64 musl 40/40 + 29/29, x86_64 gnu 41/41), each after
  its own `mc2l.o == mc3l.o` (1613040 B and 1511816 B) and with the cross proof green.
  The five goldens rewritten once more: `mc2.sha256`
  `6ba7098da052867e5bad23f5aa019da224d7b51eeb643c998b5a4bf2a684c936`, `mc2-linux-arm64.sha256`
  `7b1c5d2b2f193e639972e11a707a90ae7c2856c058499589d3508cbf8e4e09de`,
  `mc2-linux-x86_64.sha256`
  `37a6996b71833036d217119875795c5be869c68da4d475d00007cebd4d9139ea` (both re-recorded by
  `make check-linux-host`), and the Windows pair cross-computed per `tests/golden/README.md` --
  `mc2-windows-arm64.sha256`
  `b049c700c1c4b292cc1e5804815302989df066a90ff0fa2f3c5bbfe97efd5584` (1312121 B),
  `mc2-windows-x86_64.sha256`
  `8c6c1870547f4b641acf09638574ae2c5d2d489436171dd9b9583b34e446c3f1` (1349281 B).
  Docs: `docs/reference/language.md` § 6 and § 7 (the cast contract, with a sample that runs),
  `docs/reference/machine.md` § 3 ("Where a `callp`'s answer comes from" and, since (4), "Take the
  result before you restore" beside it), `docs/reference/bundle.md` § `<float>` (what the two
  machines map, the four conversions named). No message was added, so
  `docs/reference/diagnostics.md` is untouched.
- M48 C1 ✔ (`docs/specs/M48.md` § 1, § 4.2, § 4.3, § 1.8 + its § Implementation notes -- C1;
  acceptance § 9 items 2 and 3): **`[[permission]]`, `[tools]` and the kind, read by the compiler
  and recorded in the lock.** `stage0/` untouched (2848/3000). Nothing is enforced here and nothing
  is installed: C1 is the FORMAT -- what a manifest may say, what an index row carries, what
  `mc pkg sync` shows before it fetches, and what `mc.lock` records as accepted. The sandbox
  primitives (C2) and `mc tool` (C3) are the milestones that make a permission bite.
  * **The kind is `[project]`'s and is written nowhere else** (`dep_kind_of`, `src/deps.mc`):
    no `[project]` -- every package published or fixtured so far, `mc`'s own root manifest
    included -- or `kind = "obj"` is a library; `kind = "exe"` is a tool; a `[project]` with no
    `kind` line is refused at its own position with `a package's [project] must say kind = "obj"
    or "exe"`, because `mc build` defaults that key to `exe` and a library carrying a `[project]`
    for its tests would otherwise be classified as a program to install. `[package].bin`
    (`[a-z][a-z0-9_-]*`, <= 32 bytes -- the one name in a manifest that may carry a hyphen,
    because it is a FILE name) defaults to the basename of `[project].out`.
  * **`[[permission]]`** (`dep_perm_line`/`dep_read_perms`): five kinds (`fs.read`, `fs.write`,
    `net`, `exec`, `env`), four path forms (`workspace`, `tmp`, `workspace/<rel>`, `home/<rel>`,
    with `<rel>` through the existing `dep_rel_ok` -- one containment rule for every path in every
    manifest), at most 32 rows, `reason` at most 120 bytes. **No absolute path is ever accepted.**
    Each row becomes one canonical line, duplicates collapse, the set is sorted bytewise
    (`dep_str_lt`, which `pkg_name_lt` now calls too). Every refusal is at the offending key's own
    `file:line:col` inside the PACKAGE's mc.toml, and the kind is asked FIRST, so `fs.delete` is
    an unknown kind and not "a kind that takes no path".
  * **`[tools]` is `[deps]`' shape and the same MVS graph** -- a tool's own `[deps]` are libraries
    -- but what it names is a program. `deps_apply` validates the NAME at its position and does
    nothing else (a project whose only table is `[tools]` reads no lock and opens no file);
    `pkg_read_deps` turns the rows into requirements with `SL_TOOL` marking which table asked, and
    that mark is the lock's `kind` and the "tools required by this project" block. A name in both
    tables, a library under `[tools]` (`net: is a library: name it under [deps]`) and a tool under
    `[deps]` are each refused.
  * **A tool registers no include root** (§ 4.3, D24). `dep_read_lock` used to register one root
    per lock row, index-parallel with the package table; the two stop being parallel and `PK_ROOT`
    is the map, **-1 for a tool**, edges to a tool dropped, `deps_apply` skipping the row whole --
    no resolve, no hash, no open. `libs_open` and `pkg_vendor` answer for it the same way.
  * **The install table** (§ 4.2): after MVS and before any download, the plan carries a
    `permissions` block with ONE fixed sentence per kind, the `(declared by the author; a library
    runs inside your program)` caveat on a library row, the trust sentence risk 4 words, the
    `tools required by this project` block, and
    `nothing was downloaded: re-run with --yes to fetch and to accept the permissions above`.
    The set shown is the INDEX ROW's -- on the screen before a byte is fetched -- and the set
    written into the lock is the fetched TREE's; the two cannot disagree without the tree hash
    disagreeing first.
  * **The accept rule** (§ 4.3): before rewriting the lock, each package's set is compared with the
    OLD lock's row of the same name, whatever version it pinned. Not a subset -> unaccepted; a name
    the old lock lacks -> unaccepted; a row with no `permissions` key -- every lock written before
    this milestone -- is an EMPTY ACCEPTED SET, which is what makes `tests/pkg/*/mc.lock` read as
    they did. A `sync` with nothing to download but an unaccepted set also stops.
    **Deviation, on record** (§ Implementation notes 4): the block is printed only when at least
    one unaccepted set is NON-EMPTY, and it then lists every unaccepted row, `(none: stdio only)`
    included -- read literally, § 4.2 would make the first `sync` of every existing project print
    "to accept the permissions above" where there is nothing to accept. Measured consequence:
    `tests/pkg/sync`'s plan is byte for byte what it was.
  * **The lock** gains `kind` (tools only), `bin` (tools only) and `permissions` (always, sorted,
    `[]` included), and every key of a row is padded to 11 -- the width of `permissions`.
    `mc pkg list` gains the permissions column (`stdio` or the canonical set) and `tool` as the
    road of a row no build opens; `mc pkg list --long` prints the reasons, read out of the TREES
    and never out of the lock.
  * **`mc pkg check` re-derives five more keys from the archive** (`kind`, `bin`, `licence`,
    `permissions`, `tools`): a row is what a consumer reads before fetching, so an under-declared
    row asks for consent to the wrong thing. Both sets are canonical and sorted, so equality is
    position by position. A manifest refused DURING a fetch is refused before the tree is blessed
    (`pkg_read_meta`, called after the hash and before `pkg_write_manifest`), so the next build
    says `is not fetched` and not "a package that says something impossible".
  -- cost (`git diff --numstat` on `src/`, the generated `src/bundle_data.mc` excluded):
  `deps.mc` **+291/-7**, `pkg.mc` **+497/-37** = **788 added lines, 580 of them neither comment nor
  blank**, against the spec's +90/+170. The excess is named in § Implementation notes 1: the lock
  writer's re-alignment (~30 changed lines), `pkg_check_archive`'s five new comparisons (~45, not
  priced at all) and the permission block's five small functions (~90, because "fixed text per
  kind" means the text lives in one place). **Globals unchanged at 443/512 (86%)**: every new table
  is a field in `dp` (`PK_KIND`, `PK_NPERM`, `PK_PERMS`, `PK_ROOT`) or in `pk` (`PKS_NACC`,
  `PKS_ACC`, `PKS_LONG`, seven `VR_*` columns).
  New: `tests/pkg/src/tool-0.1.0` (`kind = "exe"`, `bin = "hello-tool"`, `licence`, `fs.read
  workspace` + `net`), `tests/pkg/src/net-1.0.0` (a LIBRARY declaring `net`) and `net-1.1.0` (the
  same, plus `exec sh` -- the accept rule's case), `tests/pkg/perm` (the project, with `obj.toml`
  and `notools.toml`, its `mc.lock.expect`); `scripts/check-pkg.sh` +261/-3, section 31, **94/94 ->
  114/114**.
  -- `make bundle` re-run BEFORE bootstrapping (`src/deps.mc` and `src/pkg.mc` are bundled as
  `mc/deps` and `mc/pkg`): 93 files, raw 1229830 -> LZ 571389, blob 572551 B. `make check` green
  end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test` 32/32, `check-lex` 163/163
  (3 skipped), `check-ast`/`check-asm` 164/164, `check-obj` **32/32 identical to the frozen seed**,
  `check-bundle`, `bootstrap` at a fixed point (`mc2.o == mc3.o`, 1319608 bytes; the `--dump-asm`
  diff between `mc1` and `mc2` is **empty**), `check-surface` 32/32 + inert, `test-exe` 32/32,
  `check-mc` 15/15, `check-standalone`, `check-parts`, `check-toml` 10/10, `check-build` 53/53,
  **`check-pkg` 114/114**, `check-stubs` 9/9, `check-sysroots` (13 rows), **`check-limits` 17/17
  under 90% (globals 443/512, 86%)**, `check-minimal`, `test-linux` 41/41 and `test-linux-x86_64`
  39/39, the four `--exe` cells 44/44 + 44/44 + 42/42 + 42/42, `test-windows` 42/42 and
  `test-windows-x86_64` 40/40 objects cross-compiled and linked, `check-examples`, `check-lang`,
  `check-conc`, `check-desktop`, `check-float`, `check-wide`, `check-kernel`, `check-avr`,
  `test-sandbox` 60 ok / 0 failed / 1 skipped, `check-docs` (**199 symbols, 37 flags, 31 TOML keys**,
  10 directives, 51 samples, 386 links), `site` 92 pages + `check-site` 0 link problems +
  `check-site-linux` 11/11. `make check-linux-host` RC 0 over all four cells (aarch64 musl 41/41
  and gnu 42/42, x86_64 musl 39/39 and gnu 40/40), each after its own `mc2l.o == mc3l.o` and with
  the cross proof against the macOS `build/mc2.o` green.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main`
  900c569): **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts
  for `examples/api`, `lang`, `conc`, `desktop` and `kernel` -- nothing in the corpus declares a
  permission or a tool, so nothing it emits could move.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `38470e10...d6de2a` -> `352aad73b7c55d088db6ab92d478837976507d1d815becdadba9a24fd42d8670`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `b9a6ce760bf977381ddf522db22f25f75d7980de1bd08036a884d94e7688902c`,
  `mc2-linux-x86_64.sha256`
  `b4e93acd1bd1427e7394dbe8cf7de75f7989c70d5eb9b4a8f92dfd4293ab98fb`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `fbaa14ba79f307f39c839d6acc5303755f78107ff84a0940834e4eb093162ad4` (1347580 B),
  `mc2-windows-x86_64.sha256`
  `1d16fdb7e6c08c07a9e5882d2ae51eeb0496ffa93312c4375553eb9b050ee590` (1386828 B), both also
  written byte for byte by `build/mc2`.
  Two goldens re-recorded once and each line explained (§ Implementation notes 8):
  `tests/pkg/sync/mc.lock.expect` (every key re-padded 8 -> 11 columns, each row gains
  `permissions = []`) and `tests/golden/pkg-list.txt` (each line gains one word, `stdio`).
  The four hand-written `tests/pkg/*/mc.lock` were deliberately NOT re-recorded: they are the
  compatibility case, and `check-pkg` asserts that they still carry neither key and that the chain
  builds with them.
  Docs: `docs/specs/M48.md` (the spec verbatim, both amendments, + § Implementation notes -- C1),
  `docs/reference/packages.md` (§ 3 the kind, `bin`, `licence` and `[[permission]]` with the trust
  box; § 4 the lock's three new keys and the accept rule; § 10 the install table and the five keys
  `mc pkg check` compares), `docs/reference/toml.md` (`[tools]`, `package.bin`, `package.licence`,
  `[[permission]]`, the kind rule), `docs/reference/cli.md` (`--long`, `--yes`'s second meaning,
  the `list` and `sync` rows), `docs/reference/diagnostics.md` (ten new rows).
- M48 C1 rebased onto `origin/main` 0648e1a (PR #43, the typed `callp` cast + `<float>`'s arm64
  single-precision conversions) and the five goldens re-recorded once. **No source file
  conflicted**: the two milestones do not overlap in code -- #43 is `src/gen_resolve.mc`,
  `src/gen_walk.mc` and the two float machines, C1 is `src/deps.mc` and `src/pkg.mc` -- so the
  only conflicts were `CLAUDE.md` § State (both entries kept, main's callp entry first, then C1's)
  and the six generated/aggregated files, discarded on both sides and regenerated:
  `src/bundle_data.mc` (`make bundle` re-run FIRST -- 93 files, raw 1232623 -> LZ 572748, blob
  573910 B) and the five `tests/golden/*.sha256`. `docs/reference/cli.md` and
  `docs/reference/diagnostics.md` auto-merged (#43 touched neither: it added no message and its
  docs are `language.md`/`machine.md`/`bundle.md`).
  `make check` green end to end on the merged tree (**RC 0, zero FAIL**, 11m07s): `budget`
  2848/3000, `test` 32/32, `check-lex` 163/163 (3 skipped), `check-ast`/`check-asm` 164/164
  (2 skipped), `check-obj` **32/32 identical to the frozen seed**, `check-bundle` (reproducible +
  fresh), `bootstrap` at a fixed point (`mc2.o == mc3.o`, 1321352 bytes; the `--dump-asm` diff
  between `mc1` and `mc2` is **empty**), `check-surface` 32/32 + 178 ok lines + inert, `test-exe`
  32/32, `check-mc` **16/16** (#43's `096-callp-i32` among them), `check-standalone`,
  `check-parts`, `check-toml` 10/10, `check-build` 53/53, **`check-pkg` 114/114**, `check-stubs`
  9/9, `check-sysroots` (13 rows), **`check-limits` 17/17 under 90% (globals 443/512, 86%)**,
  `check-minimal`, `test-linux` 42/42 and `test-linux-x86_64` 40/40, the four `--exe` cells 45/45
  (aarch64 musl) + 45/45 (aarch64 gnu) + 43/43 (x86_64 musl) + 43/43 (x86_64 gnu), `test-windows`
  43/43 objects and 43 linked, `test-windows-x86_64` 41/41 and 41 linked, `check-examples`,
  `check-lang` 18, `check-conc` 21, `check-desktop`, **`check-float` ok on all five legs with
  #43's tests in the tree** (macos/aarch64 16/16, linux/aarch64 16/16, linux/x86_64 16/16,
  windows/aarch64 14/14 objects, windows/x86_64 14/14, 2 skipped each) and the sweep at
  **60 (mach-o arm64), 60 (elf aarch64), 249 (elf x86_64), 232 (coff x86_64), 0 mismatches**,
  `check-wide`, `check-kernel`, `check-avr`, `test-sandbox` 60 ok / 0 failed / 1 skipped,
  `check-docs` (199 symbols, 37 flags, 31 TOML keys, 10 directives, 52 samples, 388 links),
  `site` 92 pages + `check-site` + `check-site-linux` 11/11.
  `make check-linux-host` RC 0 over all four cells (aarch64 musl: suite 42/42, `check-obj` 31/31,
  `check-mc` 12/12, `test-exe` 31/31 via `--exe --libc=musl`, `check-limits` 17/17; aarch64 gnu
  43/43 native; x86_64 musl 40/40, 29/29, `check-obj` 29/29; x86_64 gnu 41/41 native), each after
  its own `mc2l.o == mc3l.o` (1659584 B and 1555936 B) and with the cross proof
  (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`) green.
  `scripts/check-inert.sh <mc1 from origin/main 0648e1a> build/mc1`: **33 objects identical**
  (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for `examples/api`, `lang`, `conc`,
  `desktop` and `kernel` -- C1 declares no permission and no tool in the corpus, so nothing the
  compiler emits could move.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `831e6eba566c169edf191eb39f841012d1f46e22da6cc1fb2aee686bce0a4cb1` (after the empty
  `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and re-recorded by
  `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `275428778d0be9c9006841abe0af5cd3d6e3f533bf8f8f54c5e242c83e32ec3e`,
  `mc2-linux-x86_64.sha256`
  `adcdaa39db9f670b3b355416d705f0ad05697a2f3cf866e4be75c1349a342c03`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `a87935d902824b19f6ff460ec110efbc49b0ddaf6f41f89809fc5fcf52c4a6d6` (1349340 B),
  `mc2-windows-x86_64.sha256`
  `b7eee4078bdd1d79da19a4508f7c1825600becd7fff0b171f0a087e6726003af` (1388708 B), both also
  written byte for byte by `build/mc2`.
- M48 C2 ✔ (`docs/specs/M43.md` § Implementation notes -- the C2 primitives; the M48 spec § 3.4,
  § 6.1): **six sandbox primitives -- `--rw`, `--ro --at-path`, `--tmp`, `--allow=net`, `--bin`,
  `--env`.** Each is a mount, a namespace, an environment entry or a profile row, and not one of
  them knows what a permission is; what a package's `[[permission]]` rows map onto them is C3's
  question. They apply to `mc sandbox run` and to `exec` alike -- they are properties of the box
  and the box is one box, so for `run` the compile step sees them too -- and only the counters
  distinguish the steps. `stage0/` untouched (2848/3000).
  1. **`--rw DIR`**: bound WRITABLE at its own absolute path (`sb_mkdir_p` makes every component
     on the box tmpfs, then `MS_BIND|MS_REC` and *no* read-only remount), Landlock's full
     filesystem mask on it, and a root the supervisor counts. **`--rw /` and `--rw $HOME` are
     refused and there is no flag that lifts it** -- the decision the task left open: the only
     caller is a derived permission set that can never legitimately hand it either, and a mistake
     that hands it one is `rm -rf` with a sandbox's name on it. `--ro /` is not refused (reading
     is what that flag is for).
  2. **`--at-path`**: every `--ro DIR` at its own absolute path instead of `/ro0`. One flag for
     the invocation, because a caller that speaks host paths speaks them for all of them.
     Without it the numbering is byte for byte what it was.
  3. **`--tmp`**: one `mkdir`. The box's root already IS the tmpfs, so the directory is already
     writable, already counted against `--out` and already dies with the box; what the flag adds
     beside it is the Landlock grant and the root.
  4. **`--allow=net`**: the one `unshare` asks for five namespaces instead of six
     (`SB_CLONE_BOX_NET`), the Landlock ruleset stops *handling* the network (handling it and
     granting nothing would refuse exactly what was asked for), and the measured net delta joins
     the profile.
  5. **`--bin PROG`**: `host_which(PROG)` walks the host's `PATH` (new, in the host layer, as the
     task asked -- the environment is the host's and so is the separator; macOS and Windows answer
     0 and say why, since `mc sandbox` refuses on both before it could ask), the program is bound
     read-only at `/bin/<basename>`, `PATH=/bin`, Landlock `EXECUTE|READ_FILE` on the file, the
     spawn delta, and the run step's counters move to **16** processes and **1 + nbin** execve's
     (`RLIMIT_NPROC` follows at 32, looser than the counted 16, so the named refusal arrives
     before the kernel's EAGAIN).
  6. **`--env NAME`**: `NAME=<the host's value>` in the box's environment; a variable the host does
     not have arrives **empty**, which is not an error -- a `--env` that stopped the box would
     make every optional setting of a tool mandatory.
  **Zero new state globals** (the task's constraint): three flags and three lists became fields of
  `sb_state`, and `SB_ENV` grew from three slots to sixteen, shifting every offset after it by 104
  bytes. `check-limits` reports **globals 445/512 (86%)** against 443 -- the two are `sbp_net` and
  `sbp_spawn`, the GENERATED profile tables, the same kind of data `sbp_threads` already was.
  **One string per root**: `sb_box_ro_at(i)` is read by the mount, by the Landlock rule and by
  `sb_path_ok`, and `sb_resolve_paths()` rewrites the three lists with absolute answers in P
  before the fork -- so the two walls and the sentence cannot disagree about where the box ends.
  **The two deltas are measured, never typed**, and they are ONE file each --
  `tools/sandbox/net.list` and `tools/sandbox/spawn.list`, shared across (architecture, libc),
  because that is how `sbp_net`/`sbp_spawn` are consumed and because a shared name answers what
  `--check` compares against on a host that could never write its own copy. Always unioned, never
  replaced. Measured: **net 15** (`accept accept4 bind connect getpeername getsockname getsockopt
  listen recvfrom recvmsg sendmsg sendto setsockopt shutdown socket`), **spawn 6** (`clone clone3
  getuid pipe2 read wait4`, of which `clone`/`clone3` go into the table as a COMMENT -- no profile
  allows a call that makes a process; what is left is `wait4` for both libcs plus `getuid`,
  `pipe2` and `read` for musl, whose `posix_spawn` makes a pipe and reads the child's errno out of
  it). The net probe is `tests/sandbox/nettrip.mc` ITSELF, so the profile is measured over exactly
  the program the suite then runs in the box; the spawn probe is a `posix_spawn` program the
  script writes, because `binexec.mc` forks (below) and `posix_spawn` is the wider measurement.
  **A defect the new cases found and fixed**: writing a file through stdio was `refused: syscall
  29 (ioctl)` on **every musl host** -- musl's `__fdopen` asks `ioctl(TIOCGWINSZ)` of a writable
  stream and its `__stdio_write` is a `writev`, and every `fopen` in the traced corpus was a READ.
  The `libc.mc` probe gained a write-mode `fopen`/`fwrite`/`fclose` and
  `tools/sandbox/aarch64-musl-program.list` gained `ioctl` and `writev`. **Not fixed for
  `x86_64-musl`**: no host reachable from this Mac can trace it (see the cells below), the CI
  runners are glibc, and one `--union` run on such a host fixes it with the FAIL message already
  saying so.
  **`tests/sandbox/binexec.mc` forks rather than `posix_spawn`s, measured**: glibc's `clone3` is
  refused as `process limit (0)` and musl's `posix_spawn` makes a pipe first and is refused as
  `syscall 59 (pipe2)`, so the expectation would have needed a line per (arch, libc), one of which
  is unmeasurable here. A fork is a fork on both.
  New: `tests/sandbox/rwtree.mc` (ONE run proves both halves -- the file it writes is found ON THE
  HOST by the script, and one directory up is `refused: open /tmp/mc-c2-up.txt`; a refused call
  never returns, so `rw ok` is the whole of its stdout), `nettrip.mc`, `binexec.mc`, `envread.mc`,
  `atpath.mc`, `tmpwrite.mc`, each with an allowed run and a refused one. `scripts/test-sandbox.sh`
  gained `sandbox-alt-stdout` and the arch/libc lookups for `sandbox-alt-report` that the main run
  already had, plus the three `/tmp/mc-c2-*` fixtures (outside the repository, because `--rw`
  writes for real and acceptance 6 says nothing under it may be newer than the marker; `chmod
  0777`, because CI runs the same script unprivileged and then as root on one machine).
  -- cost (`git diff --numstat` on `src/`, the generated `src/bundle_data.mc` excluded):
  `sandbox.mc` +271/175 (about 30 of those the renumbered `#define` offsets), `sandbox_box.mc`
  +95/52, `host_linux.mc` +59/43, `seccomp.mc` +46/28, `sysno.mc` +33/19,
  `sysno_linux_aarch64.mc` +17/15, `sysno_linux_x86_64.mc` +16/15, `host_macos.mc` and
  `host_windows.mc` +9/1 each = **555 added lines, 349 of them neither comment nor blank**; plus
  `scripts/sandbox-trace.sh` +113, `scripts/test-sandbox.sh` +42 and the generated
  `sandbox_profiles.mc` +36.
  **Cells measured** (the x86_64 ones could not be run -- the VPS is production and Docker
  Desktop's amd64 emulation reports `landlock: absent / seccomp: notif absent / pidfd: absent`,
  with `strace` decoding nothing): linux/aarch64 **glibc 2.43** on Ubuntu 26.04 / kernel 7.0.0-30
  (Lima `mc-k7`), **root** and **unprivileged** (`kernel.apparmor_restrict_unprivileged_userns`
  flipped to 0 and restored to 1) -- `test-sandbox` **73 ok, 0 failed, 1 skipped** in each,
  against 60 before; linux/aarch64 **musl** on Alpine 3 under `docker run --privileged` --
  **71 ok, 0 failed, 3 skipped**. `sh scripts/sandbox-trace.sh --check` green on all three cells,
  both directions, only `note` lines. Box cost unchanged (5.5-6.9 ms per box on the Lima cell).
  -- `make bundle` re-run BEFORE bootstrapping: 93 files, raw 1222681 -> LZ 570028, blob 571190 B.
  `make check` green end to end (**RC 0, zero FAIL**): `test` 32/32, `check-lex` 163/163
  (3 skipped), `check-ast`/`check-asm` 164/164, `check-obj` **32/32 identical to the frozen seed**,
  `check-bundle` (lz round trip 117 cases), `bootstrap` at a fixed point (`mc2.o == mc3.o`,
  1304504 bytes; the `--dump-asm` diff between `mc1` and `mc2` is **empty**), `check-surface`
  32/32 + inert, `test-exe` 32/32 via `--exe`, `check-mc`, `check-standalone`, **`check-parts`**
  (the parts + `<mc/main>` == `<mc/core>`, 1304504 B; `<mc/core_min>` + `<mc/core_sandbox>` stands
  alone), `check-toml`, `check-build`, **`check-pkg` 94/94**, `check-stubs`, `check-sysroots`,
  **`check-limits` 17/17 under 90% (globals 445/512, 86%)**, `check-minimal`, `test-linux` 41/41
  and `test-linux-x86_64` 39/39, the four `--exe` cells 44/44 + 44/44 + 42/42 + 42/42,
  `test-windows` 42/42 objects (42 linked) and `test-windows-x86_64` 40/40 (40 linked),
  `check-examples`, `check-lang`, `check-conc`, `check-desktop`, `check-float`, `check-wide`,
  `check-kernel`, `check-avr`, **`test-sandbox` 73 ok / 0 failed / 1 skipped**, `check-docs`
  (**200 symbols, 41 flags**, 27 TOML keys, 10 directives, 51 samples, 385 links), `site` 91 pages
  + `check-site` + `check-site-linux` 11/11.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main`
  900c569): **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts
  for `examples/api`, `lang`, `conc`, `desktop` and `kernel` -- nothing in the corpus writes one of
  the six flags, so nothing it emits could move.
  `make check-linux-host` RC 0 over all four cells (aarch64 musl 41/41 and gnu 42/42, x86_64 musl
  39/39 and gnu 40/40), each after its own `mc2l.o == mc3l.o` and with the cross proof against the
  macOS `build/mc2.o` green.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `38470e10...d6de2a` -> `76bd29dea48262c113e33c59686dcb97b2daa371f6a136b250c1039e778ab0cd`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `dab7d5d92b32b8268254cb0e2b4ee6e7dd23499f228628c142d70a75bed3b4b7`,
  `mc2-linux-x86_64.sha256`
  `a2c7ebc8373b8bbbf64f58c8a3725fa90dd81f1be058f8211888e78ee078a1db`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `7aeff614274168d9b8178015bffeed23d671c4806b3a259106ba8b03504c2be1` (1331611 B),
  `mc2-windows-x86_64.sha256`
  `6ce0b9705b4a3eaaf98ee89a55ff8d596a5101e2db33124e56139c2bf6dfd354` (1369763 B), both also
  written byte for byte by `build/mc2`.
  Docs: `docs/reference/sandbox.md` § The primitives (new) plus the tree, the profiles and the
  interface, `docs/reference/cli.md` § 3c (six rows and the four refusals),
  `docs/guide/99-sandbox.md` § 5 "Letting a little of the world in" (the later sections
  renumbered), `docs/reference/hooks.md` (`host_which()`), `docs/specs/M43.md`.
  **The CI fix (both sandbox cells failed on PR #44, and the three local cells could not see it):**
  `host_which` tested a candidate with a raw `open(cand, 0, 0) >= 0`, and `open` returns a C
  `int` -- on **glibc 2.39**, which is what `ubuntu-24.04-arm` and `ubuntu-latest` run, a failing
  one comes back as `0x00000000ffffffff`, so the test was TRUE for a file that is not there and
  the function answered the FIRST entry of `PATH` with the name appended. `--bin true` resolved to
  `/usr/local/sbin/true`, which does not exist, and the box died binding it: `sandbox: cannot bind
  a --bin program: ENOENT`, exit 126. The fix is `c_int()` at both `open` sites in
  `src/host_linux.mc` (+13/-3, 2 of them code) -- the same M45 D8 class as the `lex_readable` miss
  of M43 step D, and the last two `open`s in `src/` that were still raw. Reproduced first in
  `docker run --privileged --platform linux/arm64 ubuntu:24.04` (glibc 2.39, merged-usr, the
  runner's shape), where `strace` shows `openat("/usr/local/sbin/true") = -1 ENOENT` and then
  `mount("/usr/local/sbin/true", ...) = -1 ENOENT`; a probe compiled against each libc gives
  `raw lo32=4294967295 hi32=0 raw fd>=0:1 c_int fd>=0:0` on glibc 2.39 (**aarch64 and x86_64**)
  and `hi32=4294967295 fd>=0:0` on glibc 2.43 and on musl -- which is exactly why Lima (Ubuntu
  26.04, glibc 2.43) and `alpine:3` were green. Cells after the fix: ubuntu:24.04 container
  **root 72 ok / 0 failed / 2 skipped** and **unprivileged 72 ok / 0 failed / 2 skipped** (the two
  skips are `032-svc`'s own header and the `readelf` the container has not; CI installs binutils
  and gets 73/1), Lima glibc 2.43 **root and unprivileged 73 ok / 0 failed / 1 skipped**,
  `alpine:3` musl **71 ok / 0 failed / 3 skipped** -- `binexec` and `binexec (alt)` ok in every
  one. The x86_64 box still cannot be run from this Mac (Docker Desktop's amd64 emulation reports
  `landlock: absent / seccomp: notif absent / pidfd: absent`), but the defect and the fix are the
  glibc int-return ABI in ONE shared file, and the probe measures it on x86_64 too.
  `make check` RC 0 again (`check-obj` 32/32, `check-lex` 163/163, `check-ast`/`check-asm`
  164/164, fixed point 1304984 B with an **empty** `--dump-asm` diff, `check-parts`,
  `check-limits` **17/17 under 90%, globals 445/512 (86%) -- unchanged, no new global**,
  `check-docs` 200 symbols / 41 flags / 385 links, `site` 91 pages, `test-sandbox` 73 ok);
  `make check-linux-host` RC 0 over all four cells; `scripts/check-inert.sh` against a `mc1` built
  from `origin/main` 0648e1a: **33 objects identical** plus all five taught examples.
  The five goldens rewritten once more, superseding the values above -- `mc2.sha256`
  `76bd29de...8ab0cd` -> `4dfacf7fdf3592886762632d4cf9973ad9ecbc292ac9ac743569a5fb455140b5`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `9284c26c06e247f4f9713878df784362959d6e64d3865adab85dd5be98386542`,
  `mc2-linux-x86_64.sha256`
  `bf78bad80121cc68468b0789f705ddad5c136d24a5daee73cf280395022acf6f`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `d59542470d567a90dc969ca98a05fb8566a1bf32e08288984fb2bbcbc5bbae06` (1332091 B),
  `mc2-windows-x86_64.sha256`
  `f756b2efa7c1a1b5cd26fcb6b5738a6c310b7347e00d9d43f5c1e3a0422e9cd4` (1370243 B), both also
  written byte for byte by `build/mc2`.
- M48 C2 rebased onto `origin/main` b0c76a3 (PR #43, the typed `callp` cast + `<float>`'s arm64
  single-precision conversions; PR #45, M48 C1 -- `[[permission]]`, `[tools]` and the kind) and
  the five goldens re-recorded once. **No source file conflicted**: the three milestones do not
  overlap in code -- #43 is `src/gen_resolve.mc`, `src/gen_walk.mc` and the two float machines,
  C1 is `src/deps.mc` and `src/pkg.mc`, C2 is `src/sandbox*.mc`, `src/seccomp.mc`,
  `src/sysno*.mc` and the three `src/host_*.mc` -- so the only conflicts were `CLAUDE.md` § State
  (every entry kept: main's callp entry, C1's and C1's rebase entry, then C2's) and the six
  generated/aggregated files, discarded on both sides and regenerated: `src/bundle_data.mc`
  (`make bundle` re-run FIRST -- 93 files, raw 1257081 -> LZ 583197, blob 584359 B) and the five
  `tests/golden/*.sha256`. `docs/reference/cli.md` auto-merged with both sides' text (C1's
  `mc pkg sync`/`list` columns and `--long`, C2's six `mc sandbox` primitive rows and the four
  refusals), and so did `docs/reference/hooks.md` and `docs/reference/sandbox.md`.
  `make check` green end to end on the merged tree (**RC 0, zero FAIL**): `budget` 2848/3000,
  `test` 32/32, `check-lex` 163/163 (3 skipped), `check-ast`/`check-asm` 164/164 (2 skipped),
  `check-obj` **32/32 identical to the frozen seed**, `check-bundle` (reproducible + fresh, lz
  round trip 117 cases), `bootstrap` at a fixed point (`mc2.o == mc3.o`, 1342520 bytes; the
  `--dump-asm` diff between `mc1` and `mc2` is **empty**), `check-surface` 32/32 + 146 ok lines +
  inert, `test-exe` 32/32, `check-mc` 16/16, `check-standalone`, `check-parts` (the parts +
  `<mc/main>` == `<mc/core>`, 1342520 B), `check-toml` 10/10, `check-build` 53/53,
  **`check-pkg` 114/114**, `check-stubs` 9/9, `check-sysroots` (13 rows),
  **`check-limits` 17/17 under 90% (globals 445/512, 86%)**, `check-minimal`, `test-linux` 42/42
  and `test-linux-x86_64` 40/40, the four `--exe` cells 45/45 (aarch64 musl) + 45/45 (aarch64
  gnu) + 43/43 (x86_64 musl) + 43/43 (x86_64 gnu), `test-windows` 43/43 objects and 43 linked,
  `test-windows-x86_64` 41/41 and 41 linked, `check-examples`, `check-lang` 18, `check-conc` 21,
  `check-desktop`, **`check-float` ok on all five legs** (macos/aarch64 16/16, linux/aarch64
  16/16, linux/x86_64 16/16, windows/aarch64 14/14 objects, windows/x86_64 14/14, 2 skipped each)
  with the sweep at **60 (mach-o arm64), 60 (elf aarch64), 249 (elf x86_64), 232 (coff x86_64),
  0 mismatches**, `check-wide`, `check-kernel` (`kernel.bin` 3304 B), `check-avr` (`avr.elf`
  15255 B), **`test-sandbox` 73 ok / 0 failed / 1 skipped** (delegated to Lima `mc-k7`,
  glibc/aarch64 -- C2's six primitives among them), `check-docs` (200 symbols, 42 flags, 31 TOML
  keys, 10 directives, 52 samples, 392 links), `site` 92 pages + `check-site` (0 link problems) +
  `check-site-linux` 11/11.
  `make check-linux-host` RC 0 over all four cells (aarch64 musl: suite 42/42, `check-obj` 31/31,
  `check-mc` 12/12, `test-exe` 31/31 via `--exe --libc=musl`, `check-limits` 17/17; aarch64 gnu
  43/43 native; x86_64 musl 40/40, `check-obj` 29/29, `test-exe` 29/29; x86_64 gnu 41/41 native),
  each after its own `mc2l.o == mc3l.o` (1686248 B and 1582168 B) and with the cross proof
  (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`) green.
  `scripts/check-inert.sh <mc1 from origin/main b0c76a3> build/mc1`: **33 objects identical**
  (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for `examples/api`, `lang`,
  `conc`, `desktop` and `kernel` -- C2 is the sandbox and the host layer's `host_which`, and
  nothing the compiler emits could move.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `044387b8920c959944621aa4d727a23311c7078d7ebf45b0640d0326cc0fe03a` (after the empty
  `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and re-recorded by
  `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `dc09357a0769936f376aed2363585a5a483e75f6fa3377d6a4c213eb5a415453`,
  `mc2-linux-x86_64.sha256`
  `0ad83b3a81c783e2bcdc5a3e3303d34c83144c6d54f5a7b857cc43a1a7a8e101`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `85ea59403cf3932a5da522336175a58c02634ca1fcc2f5b70134789f09d6b574` (1371026 B),
  `mc2-windows-x86_64.sha256`
  `4e77010e2463929ed2fb8d07568a6abfea4b929c9e3dfc1f373ae09ba49fe707` (1411502 B), both also
  written byte for byte by `build/mc2`.
- M48 C2, the windows/x86_64 CI finding (`docs/specs/M48.md` § Implementation notes -- C2;
  `docs/reference/objects.md` § 4c): **`fold` recursed on the sibling chain, so the stack depth was
  the LENGTH of a list.** C2 was green on macOS, on all four Linux cells and on
  `mc on windows/arm64 host`, and red -- twice, deterministically -- on **`mc on windows/x86_64
  host`**: the cross-compiled compiler linked, said `windows/x86_64`, compiled a small program,
  lexed and PARSED its own source (exit 0 each) and then died with no output at all while
  COMPILING it. Nothing C2 wrote is at fault.
  * **The static pass named the shape and ruled out the code.** `--dump-asm --machine=x86_64-win`
    of `src/mc_windows_x86_64.mc` from `origin/main` b0c76a3 and from the branch, with the
    `l_strN` indices normalised: **1712 functions in common, 53 different, every one of them
    `sb_*`**, plus 33 new. Per-symbol disassembly of the two COFF objects agrees -- **every core
    function's machine code is byte for byte identical**. `sub rsp, N` maxima identical (1152,
    under a page: no `__chkstk` question), section sizes, symbol counts and 14457 relocations all
    far from any ceiling. So the compiler's own code did not change; only its data and the source
    it was fed.
  * **The oracle was `wine` under `--platform linux/amd64`** (a Debian 12 image, `wine` 8.0),
    which runs the Windows binary at full Rosetta speed: main's compiler reproduces its CI
    success (exit 0, `mc-windows-x86_64.obj` **1388708 bytes**, the CI byte count) and C2's
    reproduces the failure in 1.1 s. `WINEDEBUG=+seh` named it -- `EXCEPTION_STACK_OVERFLOW`,
    `c00000fd`, `stack 0x20000-0x21000-0x820000`, all 8 MiB gone. Two cross runs settled where the
    fault lives: **the C2 binary compiles main's source (exit 0) and main's binary crashes on C2's
    source (exit 1)** -- the INPUT, not the code.
  * **The cause.** `fold` (`src/parse.mc`) ended with `i64 nx = fold(nd_next(n));`. A sibling
    chain is a list and a global array initializer is one node per element, so the stack depth was
    the length of the longest list in the program. `src/bundle_data.mc` is exactly that shape --
    the M21.5 deviation keeps `u64 bundle_blob[] = { ... }` on disk, because the frozen seed's
    lexer has no `#embed`. main: **71739** elements. C2, whose bundle carries the new sandbox
    sources: **73045**. `fold`'s frame is 64 bytes of locals, so per level that is 8 (return
    address) + 8 (saved `rbp`) + 64 + **32, the Win64 shadow space held across the recursive
    call** = **112 bytes**, against **80** under AAPCS64 and SysV, which have no shadow space.
    71739 x 112 = 7.66 MiB, fits; 73045 x 112 = 7.80 MiB plus the callers, does not. `fold` runs
    on the compile road only -- `src/cli.mc` returns for `--dump-ast` on the line above it --
    which is why the parse smoke passed. Measured with a generated `u64 big[] = { ... }` and
    nothing else in the file: **windows/x86_64 took 74000 elements and failed at 75000;
    linux/x86_64 took 100000 and SIGSEGVed at 120000; macOS arm64 SIGSEGVed at 150000.** Every
    host had the defect; the 40% bigger Win64 frame is only what made it arrive first.
  * **The fix is `src/parse.mc` +30/-16, 8 of the added lines code**: `fold` walks the SIBLING
    chain with a loop and keeps the recursion for the CHILDREN, so the depth is the nesting and
    nothing else. It always answered the node it was given, so `set_nd_next(n, nx)` was a no-op
    and the loop is the same traversal in the same order. After it, **400000 elements compile on
    windows/x86_64**. Zero new globals (`check-limits`: globals **445/512, 86%**).
  * **The gate**, `scripts/check-mc.sh` (+41): a **150000-element** chain generated with `awk`,
    compiled with the host compiler, linked and run (exit 42). Generated and not committed because
    150000 elements is 300 KB of source; it is the one program in that script the repository does
    not carry. It is there and NOT in `tests/windows/` because that corpus is cross-compiled on
    macOS and only LINKED and RUN on Windows -- it would never touch the Windows-hosted compiler's
    stack -- and `check-mc` is in the Windows and Linux `make check` subsets, so the case runs on
    every host. Proved to have teeth: with the pre-fix compiler it is
    `FAIL long-list (compilation: )`, the empty message being the SIGSEGV.
  * **Not done, on record**: the linker's default 8 MiB stack reserve is left alone
    (`scripts/link-windows.sh` still passes no `-stack:`). Raising it would have hidden this one
    instance on one host and left the defect everywhere else.
  -- `stage0/` untouched, 2848/3000. `make bundle` re-run BEFORE bootstrapping (`src/parse.mc` is
  `mc/parse`): 93 files, raw 1258075 -> LZ 583749, blob 584911 B. `make check` green end to end
  (**RC 0, zero FAIL**): `test` 32/32, `check-lex` 163/163 (3 skipped), `check-ast`/`check-asm`
  164/164, `check-obj` **32/32 identical to the frozen seed**, `check-bundle` (lz round trip 117
  cases), `bootstrap` at a fixed point (`mc2.o == mc3.o`, 1343032 bytes; the `--dump-asm` diff
  between `mc1` and `mc2` is **empty**), `check-surface` 32/32 + inert, `test-exe` 32/32,
  **`check-mc` 17/17** (16 + the new long-list case), `check-standalone`, `check-parts`,
  `check-toml` 10/10, `check-build` 53/53, `check-pkg` 114/114, `check-stubs` 9/9,
  `check-sysroots`, `check-limits` **17/17 under 90%**, `check-minimal`, `test-linux` 42/42 and
  `test-linux-x86_64` 40/40, the four `--exe` cells, `test-windows` and `test-windows-x86_64`,
  `check-examples`, `check-lang`, `check-conc`, `check-desktop`, `check-float`, `check-wide`,
  `check-kernel`, `check-avr`, `test-sandbox` 73 ok / 0 failed / 1 skipped, `check-docs`,
  `site` 92 pages + `check-site` + `check-site-linux` 11/11.
  `make check-linux-host` RC 0 over all four cells, each after its own `mc2l.o == mc3l.o`
  (1686712 B on aarch64, 1582648 B on x86_64) and with the cross proof green; `check-mc` is
  **13/13** there, so the new case runs on the Linux hosts too.
  `scripts/check-inert.sh <mc1 from origin/main b0c76a3> build/mc1`: **33 objects identical**
  (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for `examples/api`, `lang`, `conc`,
  `desktop` and `kernel` -- the traversal order did not change, so nothing the compiler emits
  moved.
  **The Windows chain was run here, under Wine**, which is more than the cross-computation the
  goldens' README asks for: stage 1 -> 2 -> 3 with `lld-link` on the macOS side and each compiler
  run under `wine`, **`cmp build/mc2w.obj build/mc3w.obj` equal** (1411990 B), and
  `mc2w.exe --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o` -- the exact criterion
  the CI leg applies.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `044387b8...0fe03a` -> `3f0cec7ae9c1ad366ab43dd22883bf317746ced0e7335d22e5466d5d9dfcefd6`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted
  and re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `81e1fda80daef969c1c5fa3176c44a405e0962bd9bce5de9c032b617d8cc2bfa`,
  `mc2-linux-x86_64.sha256`
  `2a92672a43d0cab6c4fb00078a3268490932fa4964ed568073d6aa9b1ab0048f`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `0333405bdabec4e0e804300366b53f615e33a7640a1f7f577477ca628da93cfc` (1371526 B),
  `mc2-windows-x86_64.sha256`
  `8b42d0ca3879fa5e2164ddffe44f439b7a10dfd8368680fa530745073566d571` (1411990 B), the second of
  which the Wine-hosted `mc2w.exe` also wrote byte for byte.
- M44 step 4 ✔ (`docs/specs/M44.md` § Implementation notes -- step 4; the amendment's § B4/B5 as
  **M48 § 2.6 rewrote them**): **`mc install` -- the compiler installs its own package tree, and
  the slim binary.** `stage0/` untouched (2848/3000).
  * **`src/install.mc`** (174 lines, 111 of them neither comment nor blank), in `<mc/core_pkg>`
    and not `<mc/core_build>` as § B4 wrote: since M48 § 2.6 the tree comes from the `mc` package's
    OWN index row, so it needs the index reader, the fetch and the hash, all of which are
    `src/pkg.mc`'s. **Zero new globals for it** -- everything is a local or already lives in
    `pk_state()`.
    `mc install [VERSION] [--from-tree DIR] [--yes] [--force] [--registry URL|DIR] [--libs-dir DIR]`.
    The registry road is `pkg_index_load("mc")` -> `pkg_row` -> `pkg_plan` -> `pkg_fetch_one`,
    unchanged, so the plan, the member check, the hash-and-compare and the unbless-on-mismatch are
    the ones every package gets; `--from-tree` hashes the source, copies `mc.toml` +
    `[package].files` through the ONE reader that checks containment, hashes the copy and requires
    the two to agree. Then, on both roads, `tools/bundle.list` is copied to the ROOT of the tree --
    what `dp_mc_load` reads, deliberately not a `files` entry so it cannot move the published hash.
    **`VERSION` is a positional and a real feature**, not a test-only override: an
    `MC_INSTALL_VERSION` env var and a `--version` flag were both considered and dropped (a second
    way to configure the compiler; a collision with the global `--version`). `0.0.0-dev` refuses
    the registry road and names the other one (`run: mc install --from-tree .`, exit 2).
    **The reserved-name rule is untouched**: `mc` is still refused in `[deps]`, `[replace]` and
    `mc pkg add` -- `check-pkg` § 11 asserts all three in the same run that installs from a row in
    § 32 -- because this road installs the compiler's own package FOR THE BINARY ITSELF, at its own
    version, into a directory no project resolves through.
  * **The slim flavour.** `src/core_slim.mc` (`<mc/core_slim>`) is `core_min` + `core_machines` +
    `core_writers` + `core_build` + `core_pkg` + `main_slim.mc`; `src/main_slim.mc`
    (`<mc/main_slim>`) is `src/main.mc` without `mc_bundle_init()` and `mc_sandbox_init()`. Five
    entries (`src/mc_slim.mc` and one per cross target) and four `src/mc.<target>-slim-obj.toml`
    configs, each its full sibling with `entry` changed; `make mc-slim` builds `build/mc-slim`.
    `tests/pkg/nobundle.mc` was DELETED -- it existed only until this file did -- and
    `scripts/check-pkg.sh` § 15 now probes with `src/mc_slim.mc`.
    **Deviation, on record:** `<mc/core_sandbox>` is left out as well as `<mc/core_bundle>` (the
    part list the task named). It is defensible -- a Linux supervisor is not part of compiling
    anything -- but it makes the flavour two differences rather than one; going back to "slim is
    `mc` minus the blob" is one `#include` and one call in `src/main_slim.mc`.
  * **The refusal a slim binary owes its user** cost one global and one function pointer:
    `lex_set_libs(openfn, hintfn)`, asked ONLY when `bopen_fn == 0` (a binary with no bundle at
    all), answered by `src/deps.mc`'s `dep_include_hint`, which returns 0 when the `mc` package IS
    installed -- so `unknown bundled include` is byte for byte what it was everywhere else, and
    `check-pkg` asserts that for the full binary in the same section.
    `prog.mc:1: #include <prelude>: not bundled in this compiler and mc 0.0.0-dev is not installed:
    run mc install`. The alternative (a third `stage` on `libs_open` returning a message instead of
    a source) was dropped: it would make one pointer mean two things to save one global.
  * **The pre-scan had to learn the second road, and that is where M48 § 2.6's open question got
    its number.** `ps_bundled` (`src/limits.mc`) reached the bundle through `bopen_fn` and nothing
    else, so a slim compiler estimated **32 nodes** for a project whose sources are all `<...>`:
    ten growths on `nodes`, nine on `ins`, and 95 MB of heap for a build the full compiler does in
    44. It now falls back to `lopen_fn` stage 1 with `virt = 0` (that source came off the
    filesystem, so its relative includes are paths) -- inert for a full binary, whose bundle
    answers first. With it, `mc-slim build tests/pkg/std --limits` is **`ok`, grow 0 everywhere**.
    The same numbers answer M48 § 2.6: compiling `<mc/core>` costs **175 244 nodes / 104 MB** out
    of an installed tree against **101 194 / 44 MB** out of the blob, because the installed
    `src/bundle_data.mc` is the checked-in mode-0 array and the copy a binary regenerates from its
    own blob is mode 1 (`#embed`). It costs memory and nothing else, the estimate covers it, and
    step 4 does NOT rewrite the file: the rewrite needs a blob to emit from, and the binary that
    would need it most is exactly the one with none.
  * **Release.** `scripts/release-assets.sh --slim` names the archive
    `mc-<ver>-<target>-slim.tar.gz` (§ B5's spelling) and writes one extra `INSTALL.txt`
    paragraph; the binary inside is still `mc`/`mc.exe`, so `publish`'s `dist/mc-*.tar.gz` glob
    needed no change. `release.yml`: the macOS job builds `dist/mc-slim` and cross-compiles four
    slim objects into the two artifacts the full ones already travel in; each Linux and Windows leg
    links its slim object beside the full one and packages it. **Ten archives per release**, five
    full and five slim. The slim binaries are packaged and NOT bootstrapped (the fixed point is a
    property of the compiler; the slim one is the full one minus a data section), and
    `bootstrap-linux.sh`/`bootstrap-windows.sh` keep taking the FULL tarball as their seed.
    `mc-libs-<ver>.tar.gz` is not produced: that name is `mclib`'s now (M48 § 2.6).
  -- cost in `src/`: **167 added code lines** (install.mc 111, core_slim 6, main_slim 8, the five
  entries 3 each, `lex.mc` +9, `limits.mc` +8, `deps.mc` +6, `core_pkg.mc` +3, `core_build.mc` +1);
  `globals` **445 -> 446 / 512 (87%)**, the one being `lhint_fn`. `tools/bundle.list` gained
  `mc/core_slim`, `mc/install` and `mc/main_slim` (96 entries) and `mc.toml`'s `[package].files`
  went to 100 -- the repository's tree hash is now
  `18e1ecdf923803a86f9709f3d18bdb505b5ebc55863f6dd2df677c8f6b07a7ce`.
  Measured (macOS arm64): the slim compiler is **534 179 bytes against 1 225 843** for the full
  one, 44%, with `__DATA,__data` **8 608 against 605 104**; `<mc/host>` + `<mc/core_slim>` +
  `<user_default>` and `src/mc_slim.mc` produce the same 659 400-byte object.
  `make bundle` re-run before bootstrapping (96 files, raw 1 271 758 -> LZ 591 407, blob 592 606 B).
  `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test` 32/32,
  `check-lex` 171/171 (3 skipped), `check-ast`/`check-asm` 172/172, `check-obj` **32/32 identical
  to the frozen seed**, `check-bundle`, `bootstrap` at a fixed point (`mc2.o == mc3.o`; the
  `--dump-asm` diff between `mc1` and `mc2` is **empty**), `check-surface` 32/32 + inert,
  `test-exe` 32/32, `check-mc`, `check-standalone`, **`check-parts`** (with the new § 4a, the slim
  assembly), `check-toml`, `check-build`, **`check-pkg` 130/130** (§ 32 is `mc install` and
  `mc-slim`, end to end and offline), `check-stubs`, `check-sysroots`, `check-limits`
  **17/17 under 90%**, `test-linux` 42/42 and `test-linux-x86_64` 40/40, the four `--exe` cells
  45/45 + 45/45 + 43/43 + 43/43, `test-windows` 43/43 and `test-windows-x86_64` 41/41 objects,
  `check-examples`, `check-lang`, `check-conc`, `check-desktop`, `check-float`, `check-wide`,
  `check-kernel`, `check-avr`, `test-sandbox` 73 ok / 1 skipped, `check-docs` (200 symbols, 44
  flags, 31 TOML keys, 10 directives, 52 samples, 422 links), `site` 93 pages + `check-site` +
  `check-site-linux` 11/11. `make check-linux-host` RC 0 over all four cells (aarch64 and x86_64 x
  musl and gnu), each after its own `mc2l.o == mc3l.o` and with the cross proof green.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `3f0cec7a...cefd6` -> `63eaf37bab7bbc9046750475fe7e21f1cf3037e6674b98c94629fcb0797c610e`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `fee8986333779e67878d736a1774c7316cda6c672f0f43244c8c042f93397376`,
  `mc2-linux-x86_64.sha256`
  `6e3370bcfc626ca2d4b007f2bf39aa7b18bc73d84529f73f6cd0acdd3ff483cf`; the Windows pair
  cross-computed per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `5dca72555d855de35dbf48967b4008c47f554ab448c9fb57de0b14fa30c4ba7a` (1 386 391 B),
  `mc2-windows-x86_64.sha256`
  `40fd6a58a30ff331caceedbc7961b164e23e9c2712cb8744b261b922d9a87f31` (1 427 083 B).
  Docs: `docs/reference/cli.md` § 3e, `docs/reference/packages.md` § 2 (the installed layout) and
  § 11 (the install road), `docs/reference/bundle.md` (§ The slim flavour, and `install` in the
  `<mc/core_pkg>` row), `docs/reference/diagnostics.md` (a `mc install` table),
  `docs/build.md` § M44 (the two flavours), `docs/bootstrap.md` (why a seed is the full flavour),
  `docs/ci.md` (ten tarballs), `docs/specs/M44.md` § Implementation notes -- step 4.
- M49 step A ✔ (`docs/specs/M49.md` § 10, step 1; the spec is the owner-ratified one, copied in
  verbatim): **the flag, the walker's own record, the second golden and the two roads.** All in
  `src/`; `stage0/` untouched (2848/3000, `git diff origin/main -- stage0/` empty). The optimizer
  itself is a NO-OP in this step, and that is the point: `--opt=1` has to be provably inert before
  anything hangs off it.
  * **`--opt=N` and `-O`** (`src/cli.mc` +25/-3, 12 code): `N` in {0, 1}, `-O` an alias for
    `--opt=1` parsed as its own `str_eq` (a bare `-O` is not a `--` literal, so
    `scripts/check-docs.sh` cannot enumerate it and it is documented by hand), the last one wins,
    `--opt=2` is `mc: --opt must be 0 or 1: 2`. Applied ONCE, `set_walk_opt(optn)` right after the
    `no machine registered` check, so the three roads below it -- `--dump-asm`, `--dump-syms` and
    the backend -- all honour it and a backend a module registered gets it through the same
    `gen_lower`.
  * **`[project].opt = 0|1`** (`src/driver.mc` +35/-2, 22 code): the flag wins over the key
    (`DRV_OPT`, -1 = not given, `DRV_SIZE` 96 -> 104 -- zero new globals), and it applies to the
    ENTRY and to nothing else. The taught compiler is a TOOL this build runs, not the artefact it
    was asked for, so it is always built on the plain road -- which is what makes the compiler
    `mc build` writes reproducible whatever the key says. A `--opt=` written on the command line is
    forwarded to the child that compiles the entry (`av` 10 -> 12 slots); the key needs no
    forwarding, the child re-reads the same TOML.
  * **The walker diet, and where the level lives** (`src/gen_walk.mc` +101/-21, 60 code): the four
    `reloc()`-pending globals -- `pend_type`, `pend_sym`, `pend_node`, `prel_base`, read by no
    other file (`grep -rlw` over `src lib examples`) -- became one arena record, `wk`, behind one
    pointer. **`globals` 445 -> 442** on the seed's row (`sh scripts/check-limits.sh`), which is
    what pays for D1's own record. `walk_opt()` is a FIELD of that record and a FUNCTION, not a
    task slot: the M24 precedent, no signature moves.
  * **Contract version 5, six null slots** (`docs/reference/machine.md`): `MTASK_REG_COUNT`,
    `REG_LOAD`, `REG_STORE`, `REG_SAVE`, `REG_RESTORE`, `PARAM_REG`, `MTASK_COUNT` 31 -> 37, six
    names in `mtask_names[]`, and the **null-slot rule** -- for slots 31 and up the walker reads
    the entry itself (`mach_opt`) and treats 0 as "this machine does not do this". `walk_reg_count()`
    answers 0 when the slot is null OR when `walk_opt()` is 0. `--dump-machine` prints `-` for a
    null slot, which is neither `bundled` nor `taught`; measured on the stock compiler: six `-`
    rows per machine, three machines.
  * **The second golden and the cross-road identity** (`scripts/bootstrap.sh` +60): after the plain
    chain, `mc1 -O -> mc2o.o`, `mc2o -O -> mc3o.o`, `cmp`, `tests/golden/mc2-opt.sha256`, and then
    the line that makes the milestone falsifiable -- `mc2o src/mc.mc` (plain) `cmp`-equal to
    `build/mc2.o`. The whole block self-skips with a message when the compiler under test does not
    accept `--opt=`, so a bootstrap from a pre-M49 seed still runs stages 1-3.
    **The step-A proof is a number: `mc2-opt.sha256` and `mc2.sha256` hold the SAME hash**,
    `49cde6dc655fa7367304406ac120b19e6faa3017048bfce7f88071b1094e2d97` -- the optimized road wrote
    byte for byte the plain object.
  * **`scripts/check-opt.sh`** (`make check-opt`, inside `make check`, 66/66): every
    `tests/*.mc` and `tests/mc/*.mc` compiled plain AND with `--opt=1`, both linked, both RUN, exit
    code and stdout compared with each other and with the source's `expect-*` header; the 16
    `tests/float/*.mc` through a `--opt=1` float compiler; `examples/lang` and `examples/conc`
    built both ways and run, `examples/api` and `examples/desktop` built both ways; and the
    null-slot proof -- `examples/kernel`'s image (3304 B) and `examples/avr`'s ELF (15255 B)
    **`cmp`-identical on both roads with no edit to either machine**. It also prints the
    `--dump-asm` identity: at this step **44 of 44 corpus programs are byte-identical between
    `--dump-asm` and `--dump-asm --opt=1`**, and 0 changed.
    `scripts/check-inert.sh` gained the second road (both compilers probed with `--opt=0 --version`
    first, so a PRE from before M49 makes it the one-road script it was).
  -- cost in `src/`: **161 added lines, 94 of them neither comment nor blank**
  (`gen_walk.mc` +101/60, `driver.mc` +35/22, `cli.mc` +25/12), against the spec's ~140 estimate.
  `make bundle` re-run BEFORE bootstrapping (93 files, raw 1265800 -> LZ 586908, blob 588070 B).
  `make check` green end to end (**RC 0, zero FAIL**, 12m04s): `budget` 2848/3000, `test` 32/32,
  `check-lex`/`check-ast`/`check-asm` at their counts, `check-obj` **32/32 identical to the frozen
  seed**, `check-bundle`, `bootstrap` at a fixed point on BOTH roads (`mc2.o == mc3.o`,
  `mc2o.o == mc3o.o`, and `mc2o-plain.o == mc2.o`; the `--dump-asm` diff between `mc1` and `mc2` is
  **empty**), `check-surface` 32/32 + the nine ABI assertions + inert, **`check-opt` 66/66**,
  `test-exe` 32/32, `check-mc` 17/17, `check-standalone`, `check-parts`, `check-toml`,
  `check-build`, `check-pkg`, `check-sysroots`, `check-stubs`, `check-limits` **17/17 under 90%
  (`globals` 442/512 = 86%, `funcs` 1777/2048 = 86%)**, `check-minimal`, `test-linux` 42/42 and
  `test-linux-x86_64` 40/40, the four `--exe` cells 45/45 + 45/45 + 43/43 + 43/43,
  `test-windows` / `test-windows-x86_64`, `check-examples`, `check-lang`, `check-conc`,
  `check-desktop`, `check-float`, `check-wide`, `check-kernel`, `check-avr`, `test-sandbox`
  73 ok / 0 failed, `check-docs` (202 symbols, 43 flags, 32 TOML keys, 10 directives, 52 samples,
  415 links), `site` 94 pages + `check-site` + `check-site-linux` 94 pages.
  `make check-linux-host` RC 0 over all four cells (musl and gnu x aarch64 and x86_64), each after
  its own `mc2l.o == mc3l.o` and with the cross proof green.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main`
  63e3e86): **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts
  for `examples/api`, `lang`, `conc`, `desktop` and `kernel`.
  **Six goldens** now, each rewritten once and only after its own criterion: `mc2.sha256`
  `3f0cec7a...cefd6` -> `49cde6dc655fa7367304406ac120b19e6faa3017048bfce7f88071b1094e2d97`, the NEW
  `mc2-opt.sha256` with the same value, the Linux pair deleted and re-recorded by
  `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `63592d3f02c8f70ae22b1b1ecd7d7dbd580a34c4293c3638171a14809e79f8e8`, `mc2-linux-x86_64.sha256`
  `912777926828869fc91f8b759e0502ea2b07c0eef3e61d82986dc42a63fd14da` -- and the Windows pair
  cross-computed per `tests/golden/README.md`, `mc2-windows-arm64.sha256`
  `0e76d1c11f8dd128fc7576199ab45e6ce5d10acf8eb5bf9803cc97073fa09d86` (1378307 B) and
  `mc2-windows-x86_64.sha256`
  `e786e5fe5b43cdf2aa119e909e19df0341c6d21c6968a81fb5fc6e70cccbb9e4` (1419183 B), both also
  written byte for byte by `build/mc2`.
  Docs: `docs/specs/M49.md` (the ratified spec, verbatim, plus § Implementation notes),
  `docs/reference/cli.md` (`--opt=N`, `-O`), `docs/reference/toml.md` (`project.opt`),
  `docs/reference/machine.md` (version 5, the six slots, the null-slot rule, `walk_opt`/
  `walk_reg_count`), `docs/bootstrap.md` § The optimized chain, `docs/determinism.md` § Two roads,
  `tests/golden/README.md`.
- M49 step D1 ✔ (`docs/specs/M49.md` § 3-5 and § 10, step 2): **the arm64 register allocator.**
  All in `src/` and `lib/`; `stage0/` untouched (2848/3000). The plain road is byte for byte what
  it was -- `check-obj` 32/32 against the frozen seed, `check-inert` identical everywhere -- and
  the optimized road is a second, self-consistent compiler.
  * **The pre-pass** (`src/gen_walk.mc` +287/-1, 213 code): `opt_scan(f)` walks a function's body
    once, in node order, before a single instruction is emitted, replaying exactly the block-scope
    push/pop `res_func` and `gen_func` do so that a use's local INDEX resolves to its DECLARING
    node. It scores each candidate at `8^depth` capped at `8^3`, keeps candidates in declaration
    order, and selects "the highest score not yet taken, first in declaration order on a tie",
    threshold 3 -- no hashing, no sorting, no pointer compared. State is ONE arena record with a
    fixed inline width (`OPT_MAX 128`), and that width is a CAPACITY: a function with more locals
    in scope is left alone and still compiles on the plain road's rules.
    Eligibility, as the spec writes it: a parameter or a scalar local, kind `TK_INT`/`TK_SINT` and
    width <= 8, **not `res_addr_taken`**, in a function with **no `RK_OPCODE` call and no
    `emit()`/`reloc()`**. `callp` does NOT exclude a function (D5) -- AAPCS64 makes `x19..x28` the
    callee's to preserve, and excluding them would exclude the walker's own `gen_*` family.
    The answer goes into the resolver's side table (`RES_SIZE` 32 -> 40, `RES_REG` keyed by the
    declaring node) and comes back out through `LOC_SIZE` 32 -> 40, `LOC_REG` on the walker's own
    `Local`.
  * **What `gen_func` emits, and the one deviation from the spec's § 4.3 sketch, on record**: the
    **saves come BEFORE the parameters**, not after. `MTASK_PARAM_REG` writes the allocatable
    register, so saving after it would save the parameter and hand the caller its own callee-saved
    register back changed. A save reads `x19..x28` and writes the frame, so it cannot disturb an
    argument register and the ABI claim "the prologue never writes `x0..x7`" holds unchanged. The
    save area is ordinary frame slots (`slot_new`), which is what keeps the frame record
    unconditional, the epilogue `add sp`/`ldp`/`ret`, `x0` untouched by it, and **adds no
    instruction form at all** -- measured: the set of distinct mnemonics in `src/mc.mc`'s object is
    THE SAME on both roads, and the **2284 distinct instructions of the optimized object
    re-assemble byte for byte** under `llvm-mc -triple=aarch64-apple-macos` (1326 on the plain
    road), 0 mismatches.
  * **The arm64 machine** (`src/machine_arm64.mc` +150/-9, 81 code): `a64_reg_count()` = **10**
    (`x19..x28`; `x18` is Apple's platform register and is never allocated), the six v5 tasks, the
    **alias table** and the **store rewrite**. `dslot` became `dslot[MAXDEPTH * 2]` -- two
    per-depth vectors in one array, because the seed's `MAXGLOBALS` is the tight row.
    `MTASK_REG_LOAD` **emits nothing** and records `dalias[d]`; `val_reg` answers it (which is the
    version 5 obligation), `dst_done` clears it in one line for every value-producing task,
    `a64_own` materialises an aliased depth out of the local's register before an in-place task
    (`a64_un`, `a64_cast`) would overwrite it, `save_live`/`restore_live` SKIP an aliased depth
    (its value is in a register the callee preserves), and every alias is dropped at a
    `MTASK_LABEL` and after every `MTASK_REG_STORE`. The store rewrite retargets the instruction
    just emitted when it wrote the depth's own register, behind a whitelist that excludes every
    STORE (whose `rd` is its SOURCE) and `movz`/`movk` (chains of up to four writing one register).
  * **Two obligations found by RUNNING the code**, both now in `docs/reference/machine.md` § 5:
    (1) read a depth through `val_reg`, never as `REG_BASE + d` -- `lib/machine_arm64_float.mc`
    did that in `fa_save_live` and in its stack-argument path and is corrected (+36/-4);
    (2) **a machine that overrides `MTASK_PARAM` MUST override `MTASK_PARAM_REG`**. The bundled one
    reads argument `i` out of `x_i`; `fa_param` walks its own NGRN/NSRN counters, so from the
    second parameter on `i` and the register part company. Inheriting it put the WRONG REGISTER in
    the local -- measured, `tests/float/019-putf64.mc` printed `0. -1.3 0.4` where it prints
    `3.500 -1.25 0`. `fa_param_reg` and `wi_param_reg` (`lib/i128.mc`, whose counter skips a
    register for the even-pair rule) were written for it.
  * **Measured on `bench/mc/bench.mc`** (this host, Apple M4, macOS 26.6.2, best of 5, interleaved
    with the reference): the whole workload **1.157 s -> 0.749 s** against `clang -O2` 0.523 s, so
    the ratio goes from **2.21x to 1.43x** with the allocator alone. Per phase: `mix`
    **0.722 -> 0.316** (the spec projected 0.38 for the allocator alone and 0.28 with the peephole;
    the alias table and the store rewrite are what land it between the two), `primes`
    **0.300 -> 0.265**, `fib` **0.197 -> 0.197** (expected: its cost is the call count). Steps B
    (the peephole) and C (hoisting) are what the spec sizes for 1.3x and are not in this commit.
    Instruction counts of `--dump-asm bench.mc`: **370 -> 330** in total, `_mix` 68 -> 57, `_primes`
    91 -> 77, `_fib` 32 -> 30, and the `mix` loop BODY 50 -> 24 per iteration with **no memory
    traffic at all**.
    The optimizer's own cost: `mc --opt=1 src/mc.mc -o x.o` is **1.020 s against the plain road's
    1.020 s, +0%** (the bound was +30%, the target +10%), and the `-O`-built compiler does the same
    work in **0.879 s, 14% faster**. Code size: `src/mc.mc`'s `__text` **471 368 -> 437 044 B,
    -7.3%** -- smaller, not bigger, because two instructions per allocated register is less than
    the frame traffic they remove.
  * **Proofs.** `scripts/check-opt.sh` **70/70** (44 corpus programs run on both roads, 16 float
    tests through a `--opt=1` float compiler, `examples/lang` and `examples/conc` built both ways
    and RUN with the same exit and stdout, `api`/`desktop` built both ways, and the null-slot proof
    -- `examples/kernel`'s image 3304 B and `examples/avr`'s ELF 15255 B **`cmp`-identical on both
    roads with no edit to either machine**). Of the 44 corpus programs, **11 are byte-identical
    between `--dump-asm` and `--dump-asm --opt=1`** (no candidate) and 33 change.
    `scripts/check-surface.sh` gained the **tenth ABI assertion**: per function over
    `--dump-asm --opt=1 src/mc.mc`, every `x19..x28` the body mentions is in the set stored right
    after the prologue AND in the set loaded right before `add sp` -- **1787 functions, 3011
    allocated registers, every one saved and restored, `x18` named nowhere**; the plain-road
    sentence "`x18..x28` never appear in 127 113 lines" is unchanged.
    `lib/machine_probe.mc` (+50/-1) asserts from the other side: **0 v5 slot calls on the plain
    road** (`pr_v5` dies if one happens), **20541 on the optimized road**, every register index
    inside `0..count-1`, every `REG_SAVE` matched by a `REG_RESTORE` in the same function, and the
    object identical to the bundled machine's on BOTH roads.
    New tests `tests/mc/097-opt-addr.mc` (a local written through `&x` stays in memory),
    `098-opt-narrow.mc` (`u8`/`u16`/`u32`/`i32` in registers: truncation and sign at the store,
    across a call), `099-opt-live-call.mc` (locals live across a direct and an INDIRECT call,
    three levels deep) and `100-opt-opcode.mc` (a function with `#opcode` is left alone -- its
    lowering is IDENTICAL on both roads, while `hot()` beside it differs by 39 lines).
    `scripts/check-mc.sh` gained the two-level `// skip-<os>:` / `// skip-<arch>:` header every
    other runner already honoured -- found by `make check-linux-host`, where 100's AArch64 word is
    garbage on x86_64 and the test segfaulted; the globs of `test-linux.sh` and `test-windows.sh`
    grew a `tests/mc/1*.mc` arm for the same tests.
  -- cost: **452 added lines in `src/`, 301 of them neither comment nor blank**
  (`gen_walk.mc` +287/213, `machine_arm64.mc` +150/81, `gen_resolve.mc` +15/7) plus **105 in
  `lib/`, 62 code** (`machine_probe.mc` +50/36, `machine_arm64_float.mc` +36/14, `i128.mc` +19/12),
  against the spec's ~450 estimate for D1.
  `make bundle` re-run BEFORE bootstrapping (93 files, raw 1290004 -> LZ 597055, blob 598217 B).
  `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test` 32/32,
  `check-obj` **32/32 identical to the frozen seed**, `bootstrap` at a fixed point on BOTH roads
  (`mc2.o == mc3.o`, `mc2o.o == mc3o.o`, **`mc2o-plain.o == mc2.o`** -- the cross-road identity
  over all 1787 functions -- and the `--dump-asm` diff between `mc1` and `mc2` **empty**),
  `check-surface` 32/32 + 147 ok lines including the tenth assertion, **`check-opt` 70/70**,
  `test-exe` 32/32, `check-mc` **21/21**, `check-standalone`, `check-parts`, `check-toml`,
  `check-build`, `check-pkg`, `check-stubs`, `check-sysroots`, `check-limits`
  **17/17 under 90% (`globals` 443/512 = 86%, `lowered` 1787/2048 = 87%, `heap` 56Mi/64Mi = 87%)**,
  `check-minimal`, `test-linux` 46/46 and `test-linux-x86_64` 43/43, the four `--exe` cells
  49/49 + 49/49 + 46/46 + 46/46, `test-windows` 47/47 objects + 47 linked and
  `test-windows-x86_64` 44/44 + 44 linked, `check-examples`, `check-lang`, `check-conc`,
  `check-desktop`, `check-float`, `check-wide`, `check-kernel`, `check-avr`, `test-sandbox`,
  `check-docs` (202 symbols, 43 flags, 32 TOML keys, 10 directives, 52 samples, 423 links),
  `site` 95 pages + `check-site` + `check-site-linux`.
  `make check-linux-host` RC 0 over all four cells (musl and gnu x aarch64 and x86_64), each after
  its own `mc2l.o == mc3l.o` and with the cross proof green.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = the step-A compiler, whose optimizer was
  a no-op): **the plain road identical everywhere** -- 33 objects (`tests/*.mc` + `src/mc.mc`) and
  all five taught examples -- and the second road reports a difference for all 33, which is what
  this commit is for and what the script now prints as a separate line.
  **Six goldens rewritten once**, each only after its own criterion: `mc2.sha256`
  `49cde6dc...4e2d97` -> `48e4f8220ec575d9a2aa8d03f97d17d6a30d64b3f86a2aa82a8cd30711f04a1f`,
  `mc2-opt.sha256` -> `2ace479241274ff2e9ce48cea482e66a3b943a7d65b420020b23acca8a4fa480` (the two
  are DIFFERENT now, which is the whole difference between step A and this one), the Linux pair
  deleted and re-recorded by `make check-linux-host` --
  `mc2-linux-arm64.sha256` `c1df79f3daadeb90d6a1898a3a6d95bf164df75beed4630da036a37687921ca2`,
  `mc2-linux-x86_64.sha256` `f1673204aea4b1a4d5e70f1c6df8e655db3aa0bded6eb77b869b6909d0e6ff13` --
  and the Windows pair cross-computed per `tests/golden/README.md` --
  `mc2-windows-arm64.sha256` `fa17a8164ab34d9b2a030783442f81217bb10ae70978144fc172bb439f9d5324`
  (1399339 B), `mc2-windows-x86_64.sha256`
  `b5869fd559a8f2c2bfa8a42dff29eaa29d5a02883834d2bad89ec4d2e64536d9` (1441987 B), both also
  written byte for byte by `build/mc2`.
  Docs: `docs/reference/machine.md` (the two obligations and § What the arm64 allocator does),
  `docs/reference/objects.md` § 4 (the `x18` / `x19..x28` rows rewritten, and the withdrawn
  runtime-state sentence), `docs/reference/diagnostics.md` (three rows),
  `docs/guide/15-optimizing.md` (new: what qualifies, what disqualifies a function, the measured
  table, and what `-O` never changes) + its row in `docs/README.md`.
  Not in this commit, and named: step B (the `cset`/`cmp`/`cset`/`cbz` -> `b.cond` peephole),
  step C (loop-invariant hoisting) and D2 (x86-64 and Win64, where the six slots are still null and
  `--opt=1` is accepted and does nothing).
  **Rebased onto `origin/main` 3d8eef4** (PR #50, M44 step 4 -- `mc install`, `src/core_slim.mc`,
  `src/main_slim.mc`, the `lex_set_libs` hint, `check-pkg` § 32, `mc.toml` at 100 files; PR #51,
  docs). **No source file conflicted**: the two milestones do not overlap in code -- M44 step 4 is
  `src/install.mc`, `src/core_pkg.mc`, `src/core_slim.mc`, `src/main_slim.mc`, `src/lex.mc`,
  `src/limits.mc` and `src/deps.mc`, M49 is `src/cli.mc`, `src/driver.mc`, `src/gen_walk.mc`,
  `src/gen_resolve.mc` and `src/machine_arm64.mc` -- so the only conflicts were `CLAUDE.md` § State
  (once per commit; every entry kept, main's M44 step 4 first, then M49 step A and D1, with main's
  more recent `- Next:` line, which already records step 4 as done) and the generated/aggregated
  files, discarded on both sides and regenerated: `src/bundle_data.mc` (`make bundle` re-run FIRST
  -- 96 files, raw 1304499 -> LZ 604813, blob 606012 B) and the goldens. `Makefile`,
  `docs/bootstrap.md`, `docs/reference/cli.md` and `docs/reference/diagnostics.md` auto-merged and
  were read to confirm both sides survived: `check-opt` in `check:`, in `.PHONY` and in both
  `check-skipped` lists beside main's `mc-slim`/`mc-*-slim-obj` targets; `--opt=N`/`-O` and
  `mc install` § 3e in the same CLI page; the `--opt must be 0 or 1` row and the `mc install` table
  in the same diagnostics page. `tools/bundle.list` (96 entries, main's `mc/core_slim`,
  `mc/install` and `mc/main_slim` present) and `mc.toml` (100 `files`) are main's, byte for byte --
  M49 bundles no new file. **The slim flavour builds and honours `-O`**: `make mc-slim` gives a
  552212-byte binary, `mc-slim -O --exe` runs (exit 42) and `mc-slim -O x.mc -o x.o` is `cmp`-equal
  to `build/mc1 -O`'s object; `check-parts` § 4a is green (`<mc/host>` + `<mc/core_slim>` +
  `<user_default>` == `src/mc_slim.mc`, 673496 bytes).
  `make check` green end to end on the merged tree (**RC 0, zero FAIL**, 14m39s): `budget`
  2848/3000, `test` 32/32, `check-lex` 171/171 (3 skipped), `check-ast`/`check-asm` 172/172,
  `check-obj` **32/32 identical to the frozen seed**, `check-bundle` (reproducible + fresh),
  `bootstrap` at BOTH fixed points -- `mc2.o == mc3.o` (1384768 bytes; the `--dump-asm` diff
  between `mc1` and `mc2` is **empty**) and `mc2o.o == mc3o.o`, with the cross-road identity
  (`build/mc2o src/mc.mc == build/mc2.o`) -- `check-surface` 32/32, **`check-opt` 70/70**,
  `test-exe` 32/32, `check-mc` 21/21, `check-standalone`, `check-parts` (the parts + `<mc/main>`
  == `<mc/core>`, 1384768 B, and the slim assembly), `check-toml` 10/10, `check-build` 53/53,
  **`check-pkg` 130/130**, `check-sysroots` (13 rows), `check-stubs` 9/9, `check-limits`
  **17/17 under 90%** (globals 444/512, 86%), `check-minimal`, `test-linux` 46/46 and
  `test-linux-x86_64` 43/43, the four `--exe` cells 49/49 (aarch64 musl) + 49/49 (aarch64 gnu) +
  46/46 (x86_64 musl) + 46/46 (x86_64 gnu), `test-windows` 47/47 and `test-windows-x86_64` 44/44
  objects cross-compiled, `check-examples`, `check-lang`, `check-conc`, `check-desktop`,
  `check-float` (the four sweeps 60 / 60 / 249 / 232 distinct instructions, 0 mismatches),
  `check-wide`, `check-kernel`, `check-avr`, `test-sandbox` 73 ok / 0 failed / 1 skipped,
  `check-docs` (202 symbols, 45 flags, 32 TOML keys, 10 directives, 52 samples, 444 links),
  `site` 95 pages + `check-site` (0 link problems) + `check-site-linux` 11/11.
  `make check-linux-host` RC 0 over all four cells (aarch64 musl: suite 46/46, `check-mc` 17/17,
  `test-exe` 31/31 via `--exe --libc=musl`; aarch64 gnu 47/47 native; x86_64 musl 43/43,
  `check-mc` 16/16, `test-exe` 29/29; x86_64 gnu 44/44 native), each after its own
  `mc2l.o == mc3l.o` (1736832 B on aarch64, 1631416 B on x86_64) and with the cross proof
  (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`) green.
  `scripts/check-inert.sh <mc1 from origin/main 3d8eef4> build/mc1` on the plain road (the
  reference compiler does not know `--opt`, so the script is the one-road script it always was):
  **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for
  `examples/api`, `lang`, `conc`, `desktop` and `kernel` through the taught compiler each side
  builds.
  The six goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `438ba8ce2e91375f0333320434ef2b96db3c35b4c6d4453158663bc046002397` and `mc2-opt.sha256`
  `a4938aa1b81f3b9d87592ad9d2b6aaaade7875e1a95c99da618a629cde316bef`, both recorded by
  `make bootstrap` after the empty `--dump-asm` diff and the two `cmp`s; the Linux pair deleted and
  re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `087a8245bf8db83adeb3373dfbba973ea20ff9f05b0cdc68e66f85834f1e695b`,
  `mc2-linux-x86_64.sha256`
  `30debd3c7b8ac974bc58ef386595e4ef6f341f155c8d425b6832dbe911cd7156`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `1770fef14e0fb0e2ee1e8e5989fe3ac5894a82b804da53ccbf5aad283237f101` (1414204 B),
  `mc2-windows-x86_64.sha256`
  `13ff1133fe67905fa8494d4c1619c5e96318a005e624ea1714e44288ffdaaed6` (1457076 B), both also
  written byte for byte by `build/mc2`.
- M44 step 5 ✔ (`docs/specs/M44.md` § D2 + § Implementation notes -- step 5): **`mc upgrade` -- the
  compiler replaces itself from a release, verified by the release's own sha256.** `stage0/`
  untouched (2848/3000, `git diff origin/main -- stage0/` empty); **zero new globals**
  (`check-limits` reports `globals 446/512` before and after).
  `src/upgrade.mc` (407 lines, 253 code, in `<mc/core_pkg>` beside `install.mc`):
  `mc upgrade [VERSION] [--yes] [--no-install] [--to PATH] [--registry URL|DIR] [--libs-dir DIR]`,
  in the M25 order -- resolve, refuse, PLAN, `--yes`, download, verify BEFORE unpacking, act,
  claim last.
  * **The version comes out of the REGISTRY, not out of a `LATEST` file** (deviation from § D2
    point 1, and the reason `release.yml` is untouched): `pkg_pick("mc", VERSION, -1, 0)` is the
    whole resolution -- step 3 already built the index reader -- so the newest non-yanked,
    non-pre-release row wins, a candidate is never chosen for you, and a private or staged
    registry works for `upgrade` for free.
  * **The asset url is DERIVED from the row's own url**, because a registry of SOURCES carries the
    tag archive and nothing else: `https://github.com/<o>/<r>/archive/refs/tags/<tag>.tar.gz` ->
    `https://github.com/<o>/<r>/releases/download/<tag>/mc-<ver>-<target>[-slim].tar.gz`, with the
    checksum at that name plus `.sha256` -- exactly what `scripts/release-assets.sh` writes. Any
    other url is `mc: upgrade: no binaries known for: <url>`, exit 2, refused rather than guessed
    at. **A row whose url is a LOCAL PATH puts the assets beside it**, which is § Risks 18's
    air-gapped upgrade at one line and what makes the gate offline. `<target>` is `host_os()` +
    `host_arch()` in the release vocabulary (`aarch64` -> `arm64`) and the flavour is `-slim` when
    `bopen_fn == 0`; neither is a flag.
  * **Two checks after the download, answering different questions**: the `.sha256` is verified
    before `tar` is spawned (the one thing this road can do that `mc pkg`'s cannot -- a release
    asset has stable bytes, a tag archive does not), and then the extracted compiler is RUN once
    (`mc --version`, through `fetch_spawn_to`) and must answer the version that was asked for,
    which catches an asset built from the wrong tag. Neither is provenance: the checksum comes
    from the same origin as the archive, and `docs/reference/packages.md` § 11 now says so.
  * **The swap is write-`.new` + mode 0755 + `rename`** (the task's ruling over § D2 point 5's
    unlink-and-write): atomic, so the compiler on a PATH is never half a file, and still a NEW
    INODE, which is what the macOS cached-signature `Killed: 9` needs. On **Windows** a running
    `.exe` cannot be replaced, so the new compiler is left as `<dest>.new` and the `move /y` line
    is printed -- proved by reading; the Windows CI legs cross-compile and link, they do not run
    `mc upgrade`. `rename` itself IS implemented there (`lib/sys_windows_host.mc` +22/-4, over
    `MoveFileExA` with `MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED`), so `--to PATH` works.
  * **`host_self_path()`** is the one new host answer (`_NSGetExecutablePath` / `readlink
    /proc/self/exe` / `GetModuleFileNameA`, never `argv[0]`), +18/8, +16/8, +16/8 in the three host
    files, with the buffer `xalloc`ed so it costs no global. `scripts/sysroot-windows.sh`'s
    `kernel32.def` gained `GetModuleFileNameA` and `MoveFileExA` (18 names).
  * **No `--force`**: a downgrade is a `VERSION` named explicitly and the plan says
    `downgrade mc 9.9.9 -> 1.0.0`. The one refusal is the road that CHOOSES on a tree build --
    `mc: mc 0.0.0-dev is a development build: build from the tree` + `run: make mc1`, exit 2 --
    while `mc upgrade VERSION` is allowed there (§ D2 point 2's own rule, `src/install.mc`'s
    precedent), which is what lets the gate cost one extra compile instead of two.
  * The libraries are installed by **spawning the new binary** (`<dest> install --yes`) unless
    `--no-install`; its exit status is the command's.
  -- cost: **466 added lines in `src/`, 280 of them neither comment nor blank**
  (`upgrade.mc` 407/253, the three host files 50/24, `core_pkg.mc` 9/3); outside `src/`,
  `lib/sys_windows_host.mc` +22/-4, `scripts/sysroot-windows.sh` +2, `tools/bundle.list` +1
  (`mc/upgrade`, 97 entries), `mc.toml` +1 (`src/upgrade.mc` in `[package].files`, byte order),
  `scripts/check-pkg.sh` +231.
  Gate: `scripts/check-pkg.sh` § 33, **offline like everything above it** -- the fixture is a
  compiler built from THIS tree with one line of `src/version.mc` changed to `9.9.9`, packaged by
  `scripts/release-assets.sh` into a directory that also holds the source tarball the index rows
  point at; four rows (`1.0.0`, `9.9.9`, `10.0.0-rc1`, `11.0.0 yanked`) so "the newest" has
  something to skip. Twelve assertions: the dev refusal, the plan compared byte for byte, the
  GitHub derivation and the other-forge refusal, a tampered archive (nothing written, no download
  left behind), an asset built from the wrong tag, the happy path (`cmp` against the packaged
  binary, `codesign --verify`, an empty download directory), the install road, `is the newest`,
  the downgrade plan, a yanked version named by hand, and the **self-replacement with no `--to`**
  -- inode before and after, and the replaced file reporting `mc 9.9.9`. `check-pkg` 145/145.
  `make bundle` re-run BEFORE bootstrapping: 97 files, raw 1291986 -> LZ 602252, blob 603462 B.
  `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test` 32/32,
  `check-lex` 172/172 (3 skipped), `check-ast`/`check-asm` 173/173, `check-obj` **32/32 identical
  to the frozen seed**, `check-bundle`, `bootstrap` at a fixed point (`mc2.o == mc3.o`,
  1381120 bytes; the `--dump-asm` diff between `mc1` and `mc2` is **empty**), `check-surface`
  32/32, `test-exe` 32/32, `check-mc` 17/17, `check-standalone`, `check-parts`, `check-toml`
  10/10, `check-build` 53/53, **`check-pkg` 145/145**, `check-stubs` 9/9, `check-sysroots`,
  `check-limits` **17/17 under 90%** (globals 446/512, funcs 1785/2048), `check-minimal`,
  `test-linux` 42/42 and `test-linux-x86_64` 40/40, the four `--exe` cells 45/45 + 45/45 + 43/43 +
  43/43, `test-windows` 43/43 and `test-windows-x86_64` 41/41 objects cross-compiled,
  `check-examples`, `check-lang`, `check-conc`, `check-desktop`, `check-float`, `check-wide`,
  `check-kernel`, `check-avr`, `test-sandbox` 73 ok / 0 failed / 1 skipped, `check-docs`
  (**201 symbols**, 46 flags, 31 TOML keys, 10 directives, 52 samples, 437 links), `site` +
  `check-site`. `make check-linux-host` RC 0 over all four cells (aarch64 musl 45/45 and gnu
  43/43, x86_64 musl 43/43 and gnu 41/41), each after its own `mc2l.o == mc3l.o` and with the
  cross proof against the macOS `build/mc2.o` green.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main`
  3d8eef4): **33 objects identical** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts
  for `examples/api`, `lang`, `conc`, `desktop` and `kernel`.
  The five goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `63eaf37b...7c610e` -> `63af66e9c281dc3a65fb5b2540ef33ae240e225024da2b474adb5e1904d1b5f5`
  (after the empty `--dump-asm` diff and `cmp build/mc2.o build/mc3.o`); the Linux pair deleted
  and re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `895b9569232cdfd47fbe09616cd76e0ea810b3313f0536a1fad96419ff13dc7b`,
  `mc2-linux-x86_64.sha256`
  `9500e870fdebf90018c806ba05aa0be6d17265c7aa5f49436d3699a4efe6085b`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `6a0156735a2a298a002a145cb4e28688602c6ff43e23167398c0f8ea161245ce` (1410951 B),
  `mc2-windows-x86_64.sha256`
  `b55d093c97d56ec6c60f8c7a61570697fcf7d8ea957d89baa151732c371b2bed` (1452531 B).
  Docs: `docs/reference/cli.md` § 3f (new, plus the usage block at the top refreshed -- it claimed
  "four entry points" and printed a stale list), `docs/reference/packages.md` § 11
  (`mc upgrade` -- the binary, not the source; the asset rule; what the checksum proves and what
  it does not), `docs/reference/diagnostics.md` (a `mc upgrade` table, ten rows),
  `docs/reference/hooks.md` § 6 (`host_self_path()`), `docs/reference/bundle.md`
  (`<mc/install>`, `<mc/upgrade>`, the catalogue count 83 -> 97), `docs/bootstrap.md`
  § Keeping an installed `mc` up to date, `docs/guide/00-getting-started.md`
  § Keeping it up to date, `docs/specs/M44.md` § Implementation notes -- step 5 (eleven notes,
  every deviation on record).
  Rebased onto `origin/main` 86df6e38 (M49 steps A+D1 -- the `--opt`/`-O` flag, the arm64
  register allocator and the sixth golden `mc2-opt.sha256` -- in the tree). No source file
  conflicted (M49 is `src/gen_walk.mc`/`src/machine_arm64.mc`/`src/gen_resolve.mc`/`src/cli.mc`'s
  flag/`src/driver.mc`; M44 step 5 is `src/upgrade.mc` + the host files + `src/core_pkg.mc`): the
  conflicts were `CLAUDE.md` § State (both kept -- M49's two entries in order, then this one),
  `docs/reference/cli.md` (the usage line -- HEAD's, which adds `[--opt=N|-O]` to the line step 5
  refreshed -- plus § 3f `mc upgrade`, both survive), and the six generated/aggregated files
  regenerated below. `docs/reference/diagnostics.md`, `docs/bootstrap.md` and the `Makefile`
  auto-merged and were read to confirm both sides survived (M49's `check-opt`/`mc2-opt` and M44's
  `mc upgrade`/`## 3f`). `make bundle` re-run FIRST: 97 files, raw 1324727 -> LZ 615658, blob
  616868 B (bigger than step 5's own 603462 because M49 grew the bundled sources). `make check`
  green end to end (**RC 0, zero FAIL**): `check-obj` **32/32 identical to the frozen seed**,
  `check-opt` **70/70** (both roads, taught examples and the null-slot `kernel`/`avr` identical on
  each), **`check-pkg` 145/145**, `check-surface` 32/32, `check-limits` 17/17 under 90%,
  `test-sandbox` 73 ok / 0 failed / 1 skipped, `check-docs` (203 symbols, 47 flags, 32 TOML keys,
  10 directives, 52 samples, 453 links); the plain fixed point `mc2.o == mc3.o` (1408432 B) with an
  **empty** `--dump-asm` diff, the optimized fixed point `mc2o.o == mc3o.o` (1374400 B) with an
  **empty** `--dump-asm --opt=1` diff, and the cross-road identity `mc2o-plain.o == mc2.o`.
  `scripts/check-inert.sh <mc1 from origin/main 86df6e38> build/mc1`: **33 objects identical on
  both roads** (`tests/*.mc` and `src/mc.mc`) plus byte-identical `examples/api`, `lang`, `conc`,
  `desktop` and `kernel`. `make check-linux-host` RC 0 over all four cells (aarch64 musl suite
  46/46 + `test-exe` 31/31, aarch64 gnu 47/47 native, x86_64 musl 43/43 + 29/29, x86_64 gnu 44/44
  native), each after its own `mc2l.o == mc3l.o` (1767048 B on aarch64, 1659648 B on x86_64) and
  with the cross proof (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`)
  green on both libcs. **All six goldens re-recorded once** after the rebase, each only after its
  own criterion: `mc2.sha256`
  `634ddcdb6cf65489972d62a904442f801f2db08974f005fe6a1f76261c2d5790`, `mc2-opt.sha256`
  `ed6897d4f850379f78f4118df0c3e6470622f3fe47e0b3e0498f5b9bf49b70a5` (after the two empty
  `--dump-asm` diffs and `cmp build/mc2.o build/mc3.o` / `cmp build/mc2o.o build/mc3o.o`); the
  Linux pair deleted and re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `afee3e3e5e3804ce3bcf76537aeb38c4ea7d31234e48f18610360410044521ce`, `mc2-linux-x86_64.sha256`
  `a9773aacffcf416e71e52964e344578f6dde5a704722ece21a8238e3d2742eab`; the Windows pair
  cross-computed per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `a32337b358a4ff99cc3d04aaea3b3430f816a635a8bad29ec342df3b04a70e6d` (1438768 B),
  `mc2-windows-x86_64.sha256`
  `a46610ae39a65010de24f2e3e01fe742fdc0f72f9b935d1c2a4625a817897f5f` (1482524 B).
- Bootstrap decoupling + M48 C3 done (2026-09-07): **the seed compiles the minimal core; the full compiler
  self-hosts on the dynamic arena** (PR #54, `release:skip`, byte-neutral) and **`mc tool`** (PR #55, patch 0.15.21).
  `stage0/` UNTOUCHED throughout (2848/3000) -- the owner's rule: never touch stage0, not even for capacity; the seed
  is decoupled instead. WHY: `build/mc0 src/mc.mc` already used **58-59 MiB of the fixed 64 MiB seed arena (~92%)**
  before C3, and C3 pushed it to ~67 -- the fixed seed was a ceiling about to bind with or without C3. The owner
  directed dynamic capacity (pre-scan + growth), which `src/` has since M23 (mmap arena); only `mc0` (frozen C) had a
  fixed arena and cannot gain one without editing stage0.
  * **Decoupling** (#54): `src/mc_seed.mc` (a new bootstrap entry = `host_macos` + `<mc/core_min>` + `machine_arm64`
    + `macho`/`backend_macho` + a `main`, relative includes only -- mc0 has no bundle). `scripts/bootstrap.sh` now
    runs `mc0 src/mc_seed.mc -> mc_seed; mc_seed src/mc.mc -> mc1; mc1 -> mc2 -> mc3`. `mc0`'s peak dropped from
    56.9 MiB to **15.1 MiB (76% free)**; `mc_seed` compiling the full `src/mc.mc` peaks at **96.4 MiB via the M23
    mmap arena**, past the old 64 MiB ceiling. BYTE-NEUTRAL and proven so: `mc0(src/mc.mc) == mc_seed(src/mc.mc)`
    byte for byte (same codegen), the fixed point holds, and the five goldens were **UNCHANGED** by #54. Only
    macos/aarch64 converted (the four foreign targets bootstrap from a full `mc`, no fixed-arena seed).
    `scripts/check-limits.sh` re-pointed: the seed guard now measures `src/mc_seed.mc` (what mc0 compiles -- 17/17,
    tightest `globals` 268/512 = 52%, heap 15Mi/64Mi = 23%), and the full `src/mc.mc` gets an informational,
    un-gated `mc limits` dynamic-arena report. `check-surface.sh`'s five taught-compiler build sites moved
    `mc0 -> mc_seed` (same codegen; the decoupling completion C3's size forced).
  * **C3 `mc tool`** (#55): `src/tool.mc` in `<mc/core_pkg>`, one `subcommand("tool", ...)` -- `install NAME[@VER]` /
    `install [DIR]` / `list` / `remove` / `upgrade [NAME]` / `run NAME [-- ARGS]` + a hidden `box-args <mc.toml>`.
    `tool_box_argv`/`tool_flags` is the ONE permission->sandbox mapping (`fs.read`->`--ro --at-path`,
    `fs.write`->`--rw`, `tmp`->`--tmp`, `net`->`--allow=net`, `exec`->`--bin`, `env`->`--env`; `workspace` = cwd,
    refusing `$HOME`/`/`), reused by `run` and `box-args`. The M48 AMENDMENT (owner): **no `--unconfined`** -- the
    install manifest records `sandbox = true|false` and `mc tool run` boxes on Linux (`host_sandbox_supported()`,
    via `mc sandbox exec` + the C2 primitives) and runs the binary direct on macOS/Windows, same install everywhere.
    `~/.mc/tools/<name>/v<ver>/` staged + `mc build`-built, the `v<ver>.toml` manifest last, the launcher
    `~/.mc/bin/<bin>`; `--bin-dir`/`--libs-dir` override the roots (no HOME for CI). Fits the frozen seed via the
    decoupling (mc_seed's dynamic arena compiles the full src/mc.mc+C3), NO stage0 change, NO diet.
  * **Two fixes C3 exposed**: `posix_spawn_file_actions_t` is 8 bytes on macOS but ~80 on glibc/musl and its `_init`
    memsets the whole struct, so `u8 fa[8]` was a latent stack-corrupting bug on Linux (SIGSEGV) -- `fa[128]` in
    `src/fetch.mc` and `src/driver.mc` (the latter affects `mc build`'s spawn). And `check-surface.sh` prints/warns
    which seed compiler it used instead of a silent `mc_seed -> mc1` fallback.
  * **Security review (reviewer) found a privilege-escalation BLOCKER, fixed and re-proven**: a malicious tool
    package's `[project].out`, written UNESCAPED into the install manifest, could splice a second `[tool]
    permissions = [...]` (TOML basic strings decode `\"`/`\n`; `toml.mc` has no duplicate-table detection), and
    `tool_run` handed stored permissions to `tool_flags` UNVALIDATED -- granting sandbox access the user never saw or
    accepted. Two independent fixes: `toml_esc()` (`src/deps.mc`, escapes `\ " \n \t \r`, refuses other control
    bytes) applied at EVERY TOML-from-untrusted-input writer (`tool_write_manifest`, `pkg_write_manifest`,
    `pkg_write_lock`, `pkg_dep_line` -- swept, no others); and `tool_run` re-validates every stored permission through
    `dep_perm_line_ok` BEFORE the host branch (refuses on every host), the `tool_resolve_path` fallback now a hard
    error. Plus: `[[versions]].version` validated (`dep_ver_ok`) before it builds a path (`version = "../.."` staged
    outside `~/.mc/tools` -- predates C3, reachable via `mc pkg sync`); a capacity pre-flight at install
    (`DEP_MAXPERM` 32 > the box's `SB_MAXRO/RW` 16 / `SB_MAXBIN/ENV` 8 -- refuse before `--yes`); and the spec's
    "(none)" row implemented (a zero-permission tool boxes `--ro <tree> --at-path`, with the documented residual that
    `mc sandbox exec`'s copy-on-write `/src` stays writable-but-ephemeral).
  -- `stage0/` untouched, 2848/3000. `make check` RC 0 (`check-obj` 32/32 identical to the frozen seed; bootstrap at
  a fixed point on `mc0 -> mc_seed -> mc1 -> mc2 -> mc3`, plain and `-O`, empty `--dump-asm` diff; `check-inert`
  identical -- C3 is a new subcommand, inert; `check-limits` 17/17 on `src/mc_seed.mc`; `check-tool` 27/27;
  `check-pkg` 145/145; `check-parts`/`check-standalone`/`check-docs` green; `test-sandbox` 73 ok). `make
  check-linux-host` RC 0 (both arches, both libcs; the boxed `mc tool run` refuses a read outside `fs.read
  workspace`, exit 125). Six goldens re-recorded once by #55 (C3 + bundle move them; #54 left them unchanged);
  the reviewer's blocker fix re-recorded them again -- final: `mc2` `8af48539...c5247f`, `mc2-opt` `03a98303...85b121`,
  `mc2-linux-arm64` `7783fc35...da1ae2`, `mc2-linux-x86_64` `a5aff526...cdab1b`, `mc2-windows-arm64` `85784c86...6d2b56`,
  `mc2-windows-x86_64` `f9d2e86f...253bc9`. Docs: `docs/reference/tools.md` (new), `cli.md` § 3g, `toml.md` § `[tool]`,
  `hooks.md` (`host_getcwd`), `packages.md`, `diagnostics.md`. The M48 spec's `mclib`/LSP references are superseded
  (stdlib is M52; the LSP is M28).

- M49 step B ✔ (`docs/specs/M49.md` § 6, § 10 row B): **the arm64 machine-private peephole
  (P1 + P2)** -- `cmp; cset; JZ/JNZ` fuses to one `b.<cond>`, and a `cset` feeding a logical NOT
  flips its condition in place. `stage0/` untouched (2848/3000, `git diff main -- stage0/` empty).
  All in `src/machine_arm64.mc`, **39 added / 3 removed, 22 of the added lines neither comment nor
  blank**; **zero globals added** -- the peephole holds no state, it reads `nins` and
  `ins_at(nins - 1)` -- `build/mc1 limits src/mc.mc` reports `globals 446/512` on this branch and
  **446 on `main`**, with `lowered` 1905 -> 1906, the one new function being `a64_fuse_branch`.
  (§ 9.8 asks for "at or below 443/512"; 443 was the count at step A and `main` has been at 446
  since -- step B moves it by 0.) The gated seed guard `check-limits` is **17/17 under 90%**, its
  tightest row `globals 268/512 = 52%` on `src/mc_seed.mc`.
  * **P1** (`a64_jz`/`a64_jnz`, through the shared `a64_fuse_branch`): when `walk_opt() != 0`, the
    depth is unaliased and in a register, and the last emitted `Ins` is a `cset rd, cc` with
    `rd == REG_BASE + d`, that `cset` becomes `I_NOP` (which generates no word) and a `b.<cond>`
    branches on the flags the preceding `cmp` left -- `b.cc` for `JNZ` (branch when the boolean is
    true), `b.<cc ^ 1>` for `JZ` (branch when it is false). The negation of every `C_*` pair
    (EQ 0 / NE 1, GE 10 / LT 11, GT 12 / LE 13) is exactly `cc ^ 1`, the same inversion the `cset`
    encoder already applies. Guarded by adjacency in `a64_reg_store`'s shape (`nins > ins_base`,
    the opcode compared), so an `I_LABEL` between would BE the last `Ins` and fails the test.
  * **P2** (`a64_un`, `MUN_LNOT`): when the last `Ins` is a `cset rd, cc` on the depth's own
    register, `set_ins_imm(e, ins_imm(e) ^ 1)` flips it in place and the LNOT emits nothing --
    instead of the `cmp #0; cset eq` the plain lowering costs.
  * **One defect the step made observable, fixed with it**: `I_BCOND` was encoded, dumped and in
    `lib/backend_arm64.mc` since M17, but no task had ever emitted it, so its dump line was dead
    code -- and it went through `d_head`, which appends the mnemonic/operand space, so the first
    `--dump-asm` of a fused branch read **`b. lt L4`**, which no assembler accepts and which
    contradicts the `cmp; b.lt` this branch documents. One line (`out_str(1, "  b.")` instead of
    `d_head("b.")`); it is the dump path only, and the proof is that the `--exe` binaries of the
    three benchmark phases are **`cmp`-identical before and after it** (same basename: M11's
    signature identifier).
  * **The sweep** (§ 9.6), `build/mc1 --opt=1 src/mc.mc` against its own plain object, under
    `llvm-mc`/`llvm-objdump -triple=arm64-apple-macos`: **2381 distinct non-pc-relative
    instructions re-assemble byte for byte, 0 mismatches**; **25558 pc-relative displacements
    decoded out of the raw word and checked against the target the disassembler printed, 0 wrong**
    (3033 of them `b.<cond>`: ne 1415, lt 719, eq 449, ge 298, le 115, gt 37); the set of distinct
    mnemonics goes **32 -> 38** and the difference is **exactly the six `b.<cond>` forms, with none
    removed**; and each of the six, assembled to an object with `imm19 = 2`, is byte for byte the
    encoder's own `0x54000000 | (imm19 << 5) | cc` (`b.eq` 0x54000040, `b.ne` 41, `b.ge` 4a,
    `b.lt` 4b, `b.gt` 4c, `b.le` 4d).
  * **The plain road does not move** -- the three proofs, since the goldens DO move (the compiler's
    own source grew, so `src/bundle_data.mc` and therefore `build/mc2.o` move through the blob, the
    M41 precedent): `check-obj` **32/32 objects identical to the frozen seed**;
    `diff <(build/mc1 --dump-asm src/mc.mc) <(build/mc2 --dump-asm src/mc.mc)` **empty** (and the
    same diff with `--opt=1` on both sides is empty too); and
    `scripts/check-inert.sh <mc1 from main c7b8cfc> build/mc1` -- **33 objects identical**
    (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for `examples/api`, `lang`,
    `conc`, `desktop` and `kernel` through the taught compiler each side builds. On the OPTIMIZED
    road the same script reports a difference for **19 of the 32 tests and for `src/mc.mc`** --
    every program whose lowering contains a comparison feeding a branch, which is what this step
    is for.
  * **Fixed points and the cross-road identity** (`make bootstrap`, inside `make check`): plain
    `mc2.o == mc3.o` (1532648 B), optimized `mc2o.o == mc3o.o` (1478504 B), and
    **`build/mc2o src/mc.mc == build/mc2.o`** -- the optimized compiler computes exactly the
    compiler the plain one computes. The optimizer's own cost (§ 9.3): `mc1 --opt=1 src/mc.mc`
    1.119 s against the plain road's 0.954 s (**1.17x**, bound 1.3x), and the optimized compiler
    compiles `src/mc.mc` plain in **0.855 s**, faster than `mc1`'s 0.954 s.
  * **The workload** (this host, Apple M4, `build/mc1 --exe --opt=1`, wall clock, best of 7 for the
    phases and 5 for the whole, each interleaved with its reference): `mix` **0.21 s** (gate
    <= 0.28), `primes` **0.19 s** (gate <= 0.21), `fib` **0.13 s** (gate <= 0.18) -- all three met;
    the whole workload **0.55 s** against the plain road's 0.78 s and `clang -O2`'s 0.42 s
    (**1.31x**). Step B's OWN share, measured against a `mc1` built from `main` (allocator only,
    same three sources, interleaved): `mix` 0.22 -> 0.21, `primes` 0.20 -> 0.19, `fib` 0.13
    unchanged, the whole 0.56 -> 0.55 -- **1 to 5%, at the edge of a 10 ms timer**, which is
    § 1.2's own prediction ("P1 + P2 alone, 0": the loops are latency-bound on the frame traffic
    the allocator already removed). What the peephole moves plainly is the instruction count:
    `--dump-asm` of `bench/mc/bench.mc` goes **370 (plain) -> 330 (allocator) -> 312**, and `_mix`'s
    condition `cmp x21, x10; cset x9, lt; cmp x9, #0; cset x9, eq; cbz x9, L3` becomes
    `cmp x21, x10; b.lt L4`. Step B does NOT close the milestone's 1.3x -- that is step C's gate.
    Code size (§ 9.9): `__text` of `src/mc.mc` **478 944 B with `--opt=1` against 533 076 B plain**.
  * `check-opt` **72/72** (every `tests/*.mc` and `tests/mc/*.mc` compiled, linked and run on both
    roads with the same exit code and stdout; 18 `tests/float/*.mc` under `--opt=1`;
    `examples/lang` and `conc` with the same stdout on both roads; `api` and `desktop` built both
    ways), with the `--dump-asm` identity for candidate-free programs at **10 of 48** (001, 002,
    003, 022, 023, 031, 033, 043, 056, 061) and 38 changed. `check-surface` 32/32 plus **150 ok**,
    including the tenth ABI assertion with `--opt=1` (**1906 functions, 3435 allocated registers,
    every one saved and restored, `x18` never named**) and `lib/machine_probe.mc` on both roads
    (**66739 tasks, 0 v5 slot calls plain, 23619 with `--opt=1`, object identical to the bundled
    machine's**). `examples/kernel`'s image (3304 B) and `examples/avr`'s ELF (15255 B) are
    `cmp`-identical on both roads with no edit to either machine (the null-slot rule).
  -- `make bundle` re-run BEFORE bootstrapping (101 files, raw 1453368 -> LZ 666436, blob
  667687 B). `make check` green end to end (**RC 0, zero FAIL**, 11m55s): `budget` 2848/3000,
  `test` 32/32, `check-lex` 177/177 (5 skipped), `check-ast` 178/178, `check-asm` 178/178,
  `check-obj` **32/32 identical to the frozen seed** and 32/32 `arm64-surface` against `macho`,
  `check-bundle`, `bootstrap` at both fixed points (plain `mc2.o` 1538944 B, optimized `mc2o.o`
  1481488 B) with the cross-road identity, `check-surface`
  32/32, **`check-opt` 72/72**, `test-exe` 32/32, `check-mc` 21/21, `check-standalone`,
  `check-parts`, `check-toml` 10/10, `check-build` 55/55, `check-pkg`, `check-tool`,
  `check-sysroots` (13 rows), `check-stubs` 9/9, `check-limits` **17/17 under 90%**,
  `check-minimal`, `test-linux` 46/46 and `test-linux-x86_64` 43/43, the four `--exe` cells 49/49
  (aarch64 musl) + 49/49 (aarch64 gnu) + 46/46 (x86_64 musl) + 46/46 (x86_64 gnu),
  `test-windows` 47/47 and `test-windows-x86_64` 44/44 objects cross-compiled, `test-windows-x86_64-exe`
  24/24 PE tests, `check-examples`, `check-lang`, `check-conc`, `check-desktop`, `check-float`,
  `check-wide`, `check-kernel`, `check-avr`, `test-sandbox` 73 ok / 0 failed / 1 skipped,
  `check-docs` (206 symbols, 49 flags, 35 TOML keys, 10 directives, 52 samples, 475 links),
  `site` + `check-site` + `check-site-linux`. `make check-linux-host` **RC 0 over all four cells**
  (aarch64 musl: suite 46/46, `test-exe` 31/31; aarch64 gnu 47/47 native; x86_64 musl 43/43,
  `test-exe` 29/29; x86_64 gnu 44/44 native), each after its own `mc2l.o == mc3l.o` and with the
  cross proof (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`) green.
  **All six goldens rewritten once**, each only after its own criterion: `mc2.sha256`
  `fbb80de1...54d3ad` -> `f140a7dc02c70543a2e8408970c7be42a9332681fbc13100f3da29e37fb5f131` and
  `mc2-opt.sha256` `a9ce5e1b...92c710c` ->
  `03a049d8548eae6688068a30a7397a8342ab8afac61fbdc3cadec786bc9a4bb6` (both recorded by
  `make bootstrap`, after the empty `--dump-asm` diff and the two `cmp`s); the Linux pair deleted
  and re-recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `159cf862a17abfc89319fa0e16782b32472c5e6a19f9effc40c22eb4f60cac4f`,
  `mc2-linux-x86_64.sha256`
  `78d3ba7baeb3ea5edd22e45d597441e694179e21cd4c5fecb4cf967cf2846cf7`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the Windows pair cross-computed
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `22afd188b8f50de7d2738af9cec244d3eed91aa1523223b42f211b3a26d40079` (1 566 900 B),
  `mc2-windows-x86_64.sha256`
  `47e7e9330a10a33c00add98c7936f3a6ecbc20101de46f850c29b1ef2d57652e` (1 620 348 B), both also
  written byte for byte by `build/mc2`.
  Docs: `docs/reference/machine.md` § What the arm64 allocator does (P1 and P2 beside P3/P4, the
  "`b.<cond>` is the one new form" note and the measured paragraph), `docs/specs/M49.md` § 10 row B
  marked LANDED with the real line count and the real numbers. `docs/comparison.md` and
  `bench/RESULTS.md` stay for step C, which owns the milestone's headline ratio (§ 8).
- M49 step C ✔ (`docs/specs/M49.md` § 4.8, § 10 row C, + its new § Implementation notes -- step C):
  **loop-invariant hoisting** -- a constant that costs two or more instructions and the address of a
  global, taken once at function entry instead of on every iteration. All in `src/gen_walk.mc`; no
  machine was edited, and `stage0/` is untouched (2848/3000, `git diff main -- stage0/` empty).
  * **What a candidate is.** Inside a loop (nesting depth >= 1) two node kinds re-materialise the
    same bits every iteration: an `N_INT` whose immediate needs a `movz` plus at least one `movk`
    (`(((u64) v) >> 16) != 0` -- unsigned, so a negative `i64` counts), and an `adrp`+`add` of a
    GLOBAL, which is a global array's decay or `&global`. Each DISTINCT value is recorded once, in
    first-occurrence order -- constants by VALUE, globals by their INDEX in the global table, so
    nothing is hashed and no pointer is compared -- scored with D1's own `8^depth` capped at `8^3`,
    and selected with D1's own loop: highest score not yet taken, first occurrence on a tie,
    threshold 3. They take the registers the LOCALS left (§ 4.8's order), so a local never loses one
    to a constant.
  * **Only an INTEGER literal may take a register, and that is the one defect this step had.**
    A taught literal is an `N_INT` too: `<float>`'s `f64` literal is an `N_INT` whose type is
    `TK_FLOAT` and whose `val` is the IEEE bit pattern. The first implementation keyed on the
    IMMEDIATE alone and hoisted one into `x19..x28`, handing the float machine an integer alias for
    a value that lives in `v16..v23` -- reproduced with a three-line probe through
    `build/mc-float`: `0.0 + 2.5` three times came out **`0x56e6e8cc4576e6a1` with `--opt=1` where
    the plain road says `0x401e000000000000`**. The guard is `opt_lit_hoistable(n)` -- `type_kind`
    is `TK_INT` or `TK_SINT` and `type_width <= 8`, exactly what `opt_eligible` asks of a local,
    which also excludes a 16-byte `TK_WIDE` literal -- and it is ONE predicate read by the pre-pass
    AND by the use site, so the two cannot disagree about which literals a register stands for.
    `tests/float/028-lit-in-loop.mc` (three shapes: the original repro, two literals in one loop
    with one also read after it, and a literal two loops deep where the score is `8^2`) is the
    gate, on both roads and on all five legs through `check-float` and `check-opt`. The GLOBAL half
    has no such hazard and it was probed rather than assumed: an `f64 tab[8]` indexed inside a loop
    gives `0x4030000000000000` on both roads, because an array's decay is typed `uptr` whatever its
    elements are.
  * **The one place a use is rewritten is the use site**, three of them: `lower_expr`'s `N_INT` arm,
    `gen_ident`'s global-array arm and `gen_addr`'s `RK_GLOBAL` arm each ask `opt_hreg(kind, key)`
    and issue `MTASK_REG_LOAD` instead when the answer is a register. Every use in the function is
    rewritten, not only the ones inside the loop: the register holds exactly that value for the
    whole function, which `mixed()` in the test asserts. Entry materialisation is
    `set_walk_depth_type(0, TY_I64)` + `MTASK_CONST`/`MTASK_SYM_ADDR` at depth 0 +
    `MTASK_REG_STORE(TY_I64, 0, r)`, emitted AFTER the parameters -- the mirror of D1's
    saves-before-parameters deviation, and for the same reason: the parameters must leave `x0..x7`
    before anything else writes a depth register. It runs **even when the loop is never entered**,
    which cannot fault (a symbol address is a relocation, a constant is an immediate) and which
    `never()` in the test asserts.
  * **Deviation from § 4.8, on record**: a STRING literal's address and a FUNCTION's address are NOT
    hoisted. Both must be keyed by a symbol index and both CREATE their symbol on first use
    (`str_sym` also appends the bytes to `__cstring`), so hoisting one moves symbol creation and
    literal placement from mid-function to entry -- deterministic, but bytes moved for a gain § 1.2
    never measured. A global's symbol already exists when `gen_func` runs (`gen_globals` is earlier
    in `gen_lower`) and `glb_sym` is a plain read. Also on record: the test is
    `tests/mc/101-opt-hoist.mc`, since D1 had taken 097-100.
  * **Cost: 173 added / 8 removed lines in `src/`, 107 of the added lines neither comment nor
    blank**, all in `src/gen_walk.mc` (the spec priced ~80). **Zero new globals** -- the candidate list is
    four more columns of the existing `opt` arena record (`OPT_HMAX 32`, a capacity in D1's sense:
    past it a value is not considered and the function still compiles) -- so
    `build/mc1 limits src/mc.mc` reports `globals 446/512` **before and after**, and `lowered` goes
    1906 -> 1913, the seven being `opt_big_imm`, `opt_hoist_use`, `opt_hreg` and four readers.
  * **The plain road does not move** (the three proofs; the goldens DO move, because
    `src/gen_walk.mc` is bundled and `src/bundle_data.mc` is part of `src/mc.mc`):
    `check-obj` **32/32 objects identical to the frozen seed**;
    `diff <(build/mc1 --dump-asm src/mc.mc) <(build/mc2 --dump-asm src/mc.mc)` **empty** (and empty
    with `--opt=1` on both sides); and `scripts/check-inert.sh build/mc1.pre build/mc1`
    (pre = a `mc1` built from `main` e789f84) -- **33 objects identical** (`tests/*.mc` and
    `src/mc.mc`) plus byte-identical artefacts for `examples/api`, `lang`, `conc`, `desktop` and
    `kernel` through the taught compiler each side builds. On the OPTIMIZED road the same script
    reports a difference for exactly **three** of the 33 -- `020-globals`, `025-linecount` and
    `src/mc.mc` -- the only corpus programs with a hoistable value in a loop.
  * **Both fixed points and the cross-road identity** (`make bootstrap`): plain
    `mc2.o == mc3.o` (1538120 B), optimized `mc2o.o == mc3o.o` (1480680 B), and
    **`build/mc2o src/mc.mc == build/mc2.o`** -- the `-O`-built compiler computes byte for byte the
    compiler the plain one computes.
  * **The sweep** (§ 9.6), `build/mc2o.o` under `llvm-objdump`/`llvm-mc -triple=arm64-apple-macos`:
    **2413 distinct non-pc-relative instructions re-assemble byte for byte, 0 mismatches** (25520
    pc-relative instructions counted and not re-assembled). **0 new instruction forms**, measured
    twice: the optimized object's mnemonic set is 39 against the plain object's 33 and the
    difference is exactly step B's six `b.<cond>`, and against the STEP-B optimized object
    (`build/mc1.pre --opt=1`) step C adds **nothing** and removes nothing.
  * **The milestone's number** (§ 9.2), this host (Apple M4, macOS 26.6.2), wall clock from one
    `python3` process, best of nine with the binaries interleaved: the whole workload **0.548 s
    against `clang -O2`'s 0.420 s = 1.30x**, from the plain road's 0.793 s. It is **at** the gate
    rather than under it -- three runs at growing repetition counts gave 1.297x (best of 11),
    1.305x (best of 9) and 1.291x (best of 15), so the host's own ~2% spread straddles it. All three
    PER-PHASE figures are met with margin: `mix` **0.216 s** (ceiling 0.28) -- **parity with
    `clang -O2`'s 0.215** -- `primes` **0.202 s** (ceiling 0.21) and `fib` **0.132 s**
    (ceiling 0.18). Step C's OWN share, measured against a `mc1` built from `main` e789f84 with the
    same sources interleaved: whole 0.551 -> 0.548, `mix` 0.220 -> 0.216, `primes` 0.205 -> 0.202,
    `fib` unchanged -- 1 to 2%, at the edge of a 10 ms timer, which is what § 1.2 predicted for
    everything after the allocator (these loops are latency-bound on the dependent `mul`/`add`
    chain). What moves plainly is the loop body: `mix` 50 on the plain road and 24 after
    step B -> **18 instructions per iteration**, with no memory traffic and no constant costing more
    than the one `movz` a shift count is worth, `_primes`' sieve inner loop 7, and the
    `--dump-asm` of the workload 312 -> 319 lines (the entry cost). Code size: `src/mc.mc`'s
    `__text` **535 720 B plain -> 480 420 B with `--opt=1`, -10.3%**; the workload binary's `__text`
    1 480 -> 1 276 B against `clang -O2`'s 1 320.
    The optimizer's own cost (§ 9.3): `mc1 --opt=1 src/mc.mc` **0.807 s against the plain road's
    0.814 s** (bound 1.3x), and the `-O`-built compiler does the same plain work in **0.744 s**.
  * **Proofs.** `tests/mc/101-opt-hoist.mc` (a constant needing four `movz/movk` and a global
    array's address both hoisted in one loop; a loop that is NEVER entered, whose entry code still
    runs; and a constant read inside the loop AND after it), portable to all five targets and picked
    up by the `tests/mc/1*.mc` globs of `test-linux.sh`/`test-windows.sh` and by `check-mc`.
    `scripts/check-opt.sh` **75/75** -- the differential run on both roads for every corpus program,
    19 `tests/float/*.mc` under `--opt=1` (028 among them), `examples/lang` and `conc` with the same stdout on both
    roads, `api`/`desktop` built both ways, the null-slot proof (`examples/kernel`'s image 3304 B
    and `examples/avr`'s ELF 15255 B `cmp`-identical on both roads, no machine edited), plus the new
    **hoist assertion**: `hot`'s loop has `adrp 2 movk 5` on the plain road and **`adrp 0 movk 0`**
    with `--opt=1`, with the values built once at entry (`adrp 1, movk 4`). Proved to have teeth by
    running the same script with the step-B compiler: `FAIL hoist: loop plain adrp 2 movk 5, opt
    adrp 2 movk 5`, 74/75. `--dump-asm` identity for candidate-free programs: **10 of 48**.
    `check-surface` 32/32 plus the tenth ABI assertion with `--opt=1` (**1913 functions, 3532
    allocated registers, every one saved and restored, `x18` never named**; `x18..x28` never appear
    in 144356 lines of the plain lowering) and `lib/machine_probe.mc` on both roads (**67144 tasks /
    0 v5 slot calls plain, 67302 / 24217 with `--opt=1`, object identical to the bundled
    machine's**).
  -- `make bundle` re-run BEFORE bootstrapping (101 files, raw 1460054 -> LZ 668738, blob 669989 B).
  `make check` green end to end (**RC 0, zero FAIL**), measured on this tree: `budget` 2848/3000,
  `test` 32/32, `check-lex` 177/177 (5 skipped), `check-ast`/`check-asm` 178/178, `check-obj`
  **32/32 objects identical to the frozen seed**, 32/32 `mc1` vs `mc2` and 32/32 `arm64-surface`
  against `macho`, `check-bundle`, `bootstrap` at both fixed points with the cross-road identity,
  `check-surface` 32/32, **`check-opt` 75/75**, `test-exe` 32/32 via `--exe`, `check-mc` 22/22,
  `check-standalone`, `check-parts`, `check-toml` 10/10, `check-build` 55/55, `check-pkg` 177/177,
  `check-tool` 27/27, `check-sysroots` (13 rows), `check-stubs` 9/9, `check-limits`
  **17/17 under 90%** (the seed guard on `src/mc_seed.mc`; the tightest row is `globals`
  268/512 = 52%, and `build/mc1 limits src/mc.mc` reports `globals 446/512` unchanged),
  `check-minimal`, `test-linux` 47/47 on linux/aarch64 and 44/44 on linux/x86_64, the four `--exe`
  cells 50/50 (aarch64 musl) + 50/50 (aarch64 gnu) + 47/47 (x86_64 musl) + 47/47 (x86_64 gnu),
  `test-windows` 48/48 and `test-windows-x86_64` 45/45 objects cross-compiled with
  `test-windows-x86_64-exe` 24/24 PE tests, `check-examples`, `check-lang`, `check-conc`,
  `check-desktop`, `check-float` (16/16 objects linked per Windows leg), `check-wide`,
  `check-kernel`, `check-avr`, `test-sandbox` 73 ok / 0 failed / 1 skipped, `check-docs`
  (206 symbols, 49 flags, 35 TOML keys, 10 directives, 52 samples, 475 links before this step's
  doc edits), `site` 97 pages + `check-site` (0 link problems) + `check-site-linux` 21/21.
  The two macOS goldens rewritten twice in this step -- once for the hoisting and once for the
  float guard -- final values `mc2.sha256`
  `f140a7dc...5f131` -> `bac73c5cc766cb4466061849de5a6609d9c92b6a7e7265b11f2a22e25a32e3fe` and
  `mc2-opt.sha256` `03a049d8...a4bb6` ->
  `41bc8f64d9c3c46b86b3beeabb5456175c7cda7616fe20e5f0ca78ef9b0fa752`, each recorded by
  `make bootstrap` after the two empty `--dump-asm` diffs, `cmp build/mc2.o build/mc3.o`,
  `cmp build/mc2o.o build/mc3o.o` and the cross-road identity. The four FOREIGN goldens rewritten
  with them: the Linux pair deleted and re-recorded by `make check-linux-host` (RC 0 over all four
  cells -- aarch64 musl and gnu, x86_64 musl and gnu -- each after its own `mc2l.o == mc3l.o`
  (1928880 B on aarch64, 1817384 B on x86_64) and with the cross proof `mc2l --backend=macho
  src/mc.mc` byte for byte the macOS `build/mc2.o` green in all four) --
  `mc2-linux-arm64.sha256` `a6ee33003e3dbbdab5b4cc843785223dd5ebbd4eaa540a4217a4abb780987e75`,
  `mc2-linux-x86_64.sha256` `7c6f0a5044a5f05b3596553d6a3f981006e9f3072fd968edacfd8ca2228fbffb`,
  each recorded in its musl cell and re-verified by the gnu cell of the same architecture; the
  Windows pair cross-computed per `tests/golden/README.md` --
  `mc2-windows-arm64.sha256` `827dc98c42841ed3310784425695f628f2cda4d8d2155546e134cdee2c4c6984`
  (1573289 B), `mc2-windows-x86_64.sha256`
  `5294811c13acb6b7966502ef2153e7275a8280bf3c12363812fdece9a64d456a` (1627309 B).
  One flake on record and NOT step C's: the first of the two full `make check` runs after the float
  guard failed on `test-sandbox`'s `forever` case (`killed: signal 9 (SIGKILL)` where the report
  wants `killed: cpu limit (2 s)`, exit 137 against 124) -- the 100 ms of rusage slack the M43 step B
  entry documents, inside the Lima VM. The case is green on the re-run and on the final `make check`
  (73 ok, 0 failed), and step C cannot reach it: the sandbox compiles on the PLAIN road, which
  `check-inert` proves byte-identical.
  Docs: `docs/reference/machine.md` § What the arm64 allocator does (the hoisted pseudo-locals, what
  is not hoisted and why, and the measured paragraph rewritten),
  `docs/guide/15-optimizing.md` (§ What it does gained the invariant half; § What it costs is now a
  three-column table with `clang -O2` beside both roads), `docs/specs/M49.md` (§ 10 row C marked
  LANDED with the real line count, plus § Implementation notes -- step C, seven notes),
  `docs/comparison.md` § Reading the numbers and § Where to improve item 1 (both rewritten from
  ESTIMATE to MEASUREMENT: "estimated target: within 1.3x" is now "measured: 1.30x"),
  `bench/RESULTS.md` § A1 (new, the `-O` block with its own method) and § C (three rows).
  Not in this step, and named: **D2**, the same allocator for the x86-64 and Win64 machines, where
  the six v5 slots are still null and `--opt=1` is accepted and does nothing.
- M49 step D2 ✔ (`docs/specs/M49.md` § 4.7, § 10 row 5, + its new § Implementation notes -- step D2):
  **the register allocator, the peephole and hoisting on the two x86-64 machines** -- the step that
  CLOSES the milestone, because `--opt=1` now means the same thing on every target `mc` ships. All
  in `src/machine_x86_64.mc` and the two derived x86 machines in `lib/`; `src/gen_walk.mc` needed
  **nothing at all** (which is the M17 split's own claim, tested), and `stage0/` is untouched
  (2848/3000, `git diff main -- stage0/` empty).
  * **Five registers, the same five on both ABIs.** `x86_reg_count()` answers 5 -- `rbx`, `r12`,
    `r13`, `r14`, `r15` -- and `m_x86_64_win` gets them through the table copy, so Win64 leaves
    `rdi`/`rsi` alone (D11: they are argument registers 1 and 2 on System V, and a count that
    depended on which prologue last ran would be stale for the first function of a unit). Depths
    stay in `r8..r11`, scratch stays `rax`/`rcx`/`rdx`. The set is not contiguous, so
    `x86_allocreg_at(r)` is arithmetic (`r == 0 ? 3 : r + 11`) and NOT a table: a five-entry global
    array put `build/mc1 limits src/mc.mc` at `globals 447/512`, and it is **446/512 unchanged**
    with the arithmetic. The alias vector went into `xdslot`, `MAXDEPTH -> MAXDEPTH * 2`, the way
    `src/machine_arm64.mc` does it -- **zero new file-level globals in the whole step**.
  * **`jcc rel32` is not a new form, and § 4.7 was wrong about it.** The spec says the peephole
    "needs the `jcc rel32` row, one `x86_desc` line"; it does not -- `x86_jz` has ended in `X_JCC`
    since M17 step B, so the row, the encoder branch, `MTASK_INS_SIZE`, `MTASK_RELOC_OFF` and the
    dump were all there and already swept. **Step D2 adds no instruction form at all.** What it adds
    is four new CONDITION VALUES of that form: `jl` `0f 8c`, `jge` `0f 8d`, `jle` `0f 8e`, `jg`
    `0f 8f`, beside the `je`/`jne` the plain road already emitted -- each checked against
    `llvm-mc -filetype=obj`'s own bytes.
  * **The store rewrite is a much smaller whitelist, and the reason is the architecture.** x86 is
    two-operand: `add rd, rn` means `rd = rd + rn`, so retargeting its destination at the local's
    register would add to a register that does not hold the old value. The eleven forms that make
    AArch64's rewrite pay are all OUT, along with `neg`/`not`/`imul`/the shifts, every store (its
    `rd` is its SOURCE), `setcc` (one byte), `call r` (the target) and `idiv`/`div` (the divisor).
    What is left is every form that only WRITES -- three `mov`s, two `lea`s, five register
    `movzx`/`movsx`, seven loads -- so `x = x + 1` costs one `mov` here where it costs none on
    AArch64, while `x = <const>`, `x = g`, `x = *p` and `x = a < b` cost none on either. Only the
    64-bit `mov` collapses to `X_NOP` when retargeted onto its own source: `mov32 rbx, rbx` is a
    TRUNCATION, not a no-op. For the same two-operand reason **four tasks** need `x86_own(d)` to
    materialise an aliased depth first (`MTASK_BIN`, `_UN`, `_BOOL`, `_CAST`) where AArch64 needs
    two, and `x86_arg_to` became one line, `x86_mov(r, x86_val_reg(d, r))`.
  * **P1/P2 over the pair x86 needs for a boolean.** `setcc rd, cc` + `movzx rd, rd` (setcc writes
    one byte, so the `movzx` is never separable): P1 drops both and branches on the `cmp`'s flags
    instead of emitting `test rd, rd; jcc`, with `cc ^ 1` for `JZ` -- x86 condition codes are
    defined in negation pairs (the low bit of `tttn`), so one xor inverts `e`/`ne`, `l`/`ge` and
    `le`/`g` alike; P2 flips the condition in place for `MUN_LNOT` and emits nothing.
  * **Hoisting came free**, as § 4.8 says it would: it is walker-side, so filling the six slots is
    all it took.
  * **Four `XREG_BASE + d` reads in `lib/` were the version 5 obligation coming due**, and all four
    are corrected: `fx_save_live`, `fx_restore_live` and `fx_push_args`
    (`lib/machine_x86_64_float.mc`) plus `xw_call`'s argument spill (`lib/i128.mc`). Both derived x86
    machines also owed `MTASK_PARAM_REG` -- `fx_param_reg` and `xw_param_reg` -- for three DIFFERENT
    reasons behind one rule: the float machine walks its own NGRN/NSRN counters on System V, shares
    one slot counter between the integer and float files on Win64, and `xw_param` counts slots of its
    own because a 16-byte value takes two registers on System V and a pointer on Win64.
    `examples/avx/avx.mc` needed nothing (it already read through `x86_val_reg`), and
    `examples/kernel`'s riscv64 and `examples/avr`'s AVR are null-slot machines that never see an
    alias.
  * **The tenth ABI assertion was VACUOUS since D1, and writing its x86 twin is what found it.**
    `scripts/check-surface.sh` matched registers with `/x(19|2[0-8])\y/`; `\y` is a GNU `awk` word
    boundary that the `awk` on macOS and the one in `alpine:3` both ignore, so `used` was empty for
    every function and the check could not fail (verified directly: the loop never matches). The x86
    twin has no `\y`, worked at once, and reported 2895 "violations" -- every one a false positive
    (`lea r9, [rip+l_str1330]` contains `r13`), which is what exposed the arm64 side. Two more
    mistakes came out with it: the arm64 save/restore patterns required `[sp, #`, so the slot at
    offset 0 (`str x20, [sp]`) was never recorded as saved, and `pro` was cleared by the frame record
    three lines before the first save could arrive. All three sweeps are real now:
    **arm64 1929 functions / 3556 allocated registers, x86_64 1929 / 2860, x86_64-win 1929 / 2860**,
    every one saved after the prologue and restored before `leave`/`add sp`, `x18` named nowhere, and
    `rdi`/`rsi` named **0** times on Win64 (against 15 810 on System V, where they are arguments 1
    and 2 -- so that half of D11's claim is `x86_allocreg_at`'s range, `{3,12,13,14,15}` by
    construction).
  * **The `--opt=1` pass on the four foreign legs is one variable and one loop per script**:
    `optkey` writes `opt = 1` into the generated `[project]` (`scripts/test-linux.sh`,
    `scripts/test-windows.sh`, a third argument to a new `build_float_obj` in
    `scripts/check-float.sh`), and every `tests/mc/09[4-9]*`, `tests/mc/1*` and `tests/float/*` case
    becomes a SECOND artefact named `<name>-opt` in the same manifest, judged against the same
    `expect-*` header. **`.github/workflows/ci.yml` needed no change**: the legs are `--build-only`
    on macOS and `--run-only` on the runner, so the new objects travel in the artifacts that already
    existed and the run half picks them up from the manifest -- which is the only place a `--opt=1`
    binary is ever EXECUTED for `x86_64`, `x86_64-win` or `arm64`-on-Windows.
  * **Ten goldens.** `scripts/bootstrap-linux.sh` and `scripts/bootstrap-windows.sh` each grew the
    second chain `bootstrap.sh` has had since step A -- `mc1l -O -> mc2lo.o`, `mc2lo -O -> mc3lo.o`,
    `cmp`, the golden, then `mc2lo` on the PLAIN road compared with `mc2l.o` (the cross-road
    identity) -- self-skipping when the seed does not accept `--opt=`. The four new files are
    `mc2-linux-arm64-opt`, `mc2-linux-x86_64-opt`, `mc2-windows-arm64-opt`, `mc2-windows-x86_64-opt`.
  -- cost, `git diff --numstat main` (the generated `src/bundle_data.mc` excluded):
  `src/machine_x86_64.mc` **+218/-18, 110 of the added lines neither comment nor blank**;
  `lib/machine_x86_64_float.mc` +35/-3 and `lib/i128.mc` +27/-1, **40 code**; scripts +337/-41
  (`check-surface.sh` +91/-8, `check-float.sh` +64/-33, `bootstrap-linux.sh` +64,
  `bootstrap-windows.sh` +61, `test-linux.sh` +35, `test-windows.sh` +22). The spec priced ~110 for
  `src/` and the x86 half came in at exactly that.
  **The plain road does not move, on all THREE machines** (the gate; the goldens move only because
  `src/machine_x86_64.mc` is bundled and `src/bundle_data.mc` is part of `src/mc.mc`):
  `build/mc1.pre --backend=elf-obj-x86_64 src/mc.mc` and `build/mc1`'s are `cmp`-**identical**, and
  so are the two `coff-obj-x86_64` objects; `diff` of `--dump-asm`, of `--dump-asm --machine=x86_64`
  and of `--dump-asm --machine=x86_64-win` between the two compilers over `src/mc.mc` is **empty**
  in all three; `check-obj` **32/32 identical to the frozen seed**; and
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `main` db93361) --
  **33 objects identical on BOTH roads** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts
  for `examples/api`, `lang`, `conc`, `desktop` and `kernel`.
  **The sweep**: the four x86 objects of `src/mc.mc` through `llvm-mc`
  (`-triple=x86_64-linux-musl` and `-triple=x86_64-windows-msvc`) -- plain **1339 (System V) /
  1337 (Win64)** distinct instructions re-assemble byte for byte, optimized **1666 / 1643**,
  **0 mismatches** in all four; the pc-relative forms (`jmp`/`jcc`/`call rel32` and
  `lea r, [rip+d]`, whose operand llvm-objdump prints as an absolute address) are reduced to
  (mnemonic, the bytes before the four-byte field) and go 4 -> 8 per ABI, the four additions being
  exactly the four new `jcc` conditions; the mnemonic set goes 38 -> 42 on each, delta
  `{jg, jge, jl, jle}`.
  **Performance is NOT measured** (§ 10 row 5): there is no x86-64 machine in this repository's
  development loop and a reproducible cell is M50's job. The one number available is instruction
  count: `--dump-asm --machine=x86_64 src/mc.mc` goes **148 042 -> 130 846 lines (-11.6%)** with
  `--opt=1`, with **20 700** mentions of `rbx`/`r12..r15` against **0** on the plain road; the
  objects go 1.7 MiB -> 1.7 MiB (ELF) and 1.6 -> 1.5 MiB (COFF).
  `make check` green end to end (RC 0, zero FAIL): `budget` 2848/3000, `test` 32/32,
  `check-lex`/`check-ast`/`check-asm` at their counts, `check-obj` **32/32 identical to the frozen
  seed**, `check-bundle`, `bootstrap` at BOTH fixed points (plain `mc2.o == mc3.o` 1550032 B,
  optimized `mc2o.o == mc3o.o` 1492272 B, the cross-road identity `mc2o src/mc.mc == mc2.o`, and
  both `--dump-asm` diffs between `mc1` and `mc2`/`mc2o` **empty**), `check-surface` **154 ok / 0
  FAIL** including the three real ABI sweeps, `check-opt` 75/75, `test-exe` 32/32, `check-mc`,
  `check-standalone`, `check-parts`, `check-toml`, `check-build`, `check-pkg`, `check-tool`,
  `check-stubs`, `check-sysroots`, `check-limits` **17/17 under 90%** (the seed guard is
  `src/mc_seed.mc`: globals 268/512 = 52%; `src/mc.mc` itself is `globals 446/512`, unchanged),
  `check-minimal`, **`test-linux` 55/55 on linux/aarch64 and 51/51 on linux/x86_64** (the `-opt`
  cases among them; `100-opt-opcode` skipped on x86_64, its `#opcode` word being an AArch64 one),
  the four `--exe` cells, `test-windows` / `test-windows-x86_64` objects cross-compiled and linked,
  `check-examples`, `check-lang`, `check-conc`, `check-desktop`, **`check-float` ok on all five
  legs with both roads** (macos/aarch64 19/19, linux/aarch64 **38/38**, linux/x86_64 **38/38**,
  windows/aarch64 34/34 and windows/x86_64 34/34 objects linked) and its four sweeps at 61 / 70 /
  311 / 293 distinct instructions, 0 mismatches, `check-wide`, `check-kernel`, `check-avr`,
  `test-sandbox` 73 ok / 0 failed / 1 skipped, `check-docs` (**206 symbols**, 49 flags, 35 TOML
  keys, 10 directives, 52 samples, 476 links), `site` + `check-site`.
  `make check-linux-host` RC 0 over all four cells (aarch64 musl and gnu, x86_64 musl and gnu), each
  after its own PLAIN fixed point AND its own OPTIMIZED one, each with its own cross-road identity
  and with the cross proof (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`)
  green.
  **The ten goldens**, each recorded only after its own criterion: `mc2.sha256`
  `e965d181727a77ba1a863c032cea6412d23b4962a2f722bd8bf9935a37f80682` and `mc2-opt.sha256`
  `968037e8f8539896100d24fea34e87e0c9da7b4a44b670df66d9feef8dd6f0d6` (after the two empty
  `--dump-asm` diffs and the two `cmp`s); the four Linux ones deleted and re-recorded by
  `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `1fee89282756dc78ae481ca001bd12c5e50fd220d3f6179e17d01a4506b50052`,
  `mc2-linux-arm64-opt.sha256`
  `7028d5a22f5335fc6e6c412a6e7459fa763d39a9e2c74b3d205a9dc109e2a44b`,
  `mc2-linux-x86_64.sha256`
  `35b37fdc67b31a46a6d0fe60a07dfbe1b5373b67a8927e5d6357354ed71b1af4`,
  `mc2-linux-x86_64-opt.sha256`
  `44ff42f03e24fc3a8e8545070d117a7ad9c3c4df3b78e3779ba190344cff1d86`, each recorded in its musl cell
  and re-verified by the gnu cell of the same architecture; the four Windows ones cross-computed on
  macOS per `tests/golden/README.md`, with `--opt=1` added for the two new ones --
  `mc2-windows-arm64.sha256`
  `991a1963da104f99105ecc7c57b057d7673690cb0d6bfe602c57d3f809fe2169`,
  `mc2-windows-arm64-opt.sha256`
  `d099f12e9c6a9e64fa6ade80027dc290e86d3be7aa19f58cbcbc7cb4d2b0892f`,
  `mc2-windows-x86_64.sha256`
  `e43583c1bce51fd0fd05211d59929685f972a00f60cc8912539d55937d462af5`,
  `mc2-windows-x86_64-opt.sha256`
  `f95c976c1f02a7ea5dc6556f34760cd6373c215d9ad477fb6e34c480fce796c8`.
  Docs: `docs/reference/machine.md` (§ "What the x86-64 allocators do (step D2)", the two version 5
  obligations brought up to date, the allocatable row in the x86 table), `docs/reference/objects.md`
  § 4b and § 4c (the callee-saved rows on both ABIs, and the corrected arm64 numbers with the
  vacuity finding on record), `docs/guide/15-optimizing.md` ("on every target `mc` ships", and that
  the measured table is AArch64's), `docs/bootstrap.md` § "The same chain on every foreign host",
  `tests/golden/README.md` (ten goldens and how the two new Windows ones are cross-computed),
  `docs/ci.md`, `docs/specs/M49.md` (row 5 LANDED with the real line count, + twelve implementation
  notes).
  **M49 is closed**: A, D1, B, C and D2 are all landed; E (small-leaf inlining, constant
  propagation) stays deferred to its own spec with its own measurement.
- The cpu-cap verdict survives host contention (`docs/specs/M43.md` § Implementation notes -- the
  cpu-verdict flake, `docs/reference/sandbox.md` § The report): **a measured fraction, not a typed
  slack.** `stage0/` untouched (2848/3000, the diff against `origin/main` for `stage0/` is empty).
  Two M49 pull requests hit it in `make check` -- `scripts/test-sandbox.sh`'s `forever` case, a
  program that spins past its 2 s CPU cap, intermittently reported `killed: signal 9 (SIGKILL)`
  where the header asks for `killed: cpu limit (2 s)`.
  * **The mechanism was documented and the number was not.** `RLIMIT_CPU` is soft = hard, so the
    kernel's cap arrives as SIGKILL (step B's measurement) and J tells it from a program that died
    for its own reasons by the rusage of that step alone -- which comes back UNDER the cap, because
    the accounting the kill was decided on is not the accounting `wait4` reports. Step B measured
    1.997 s for a 2 s cap on a quiet host and wrote `us + 100000 >= cap`.
  * **That shortfall is PROPORTIONAL to the cap.** Measured on the Lima oracle (Ubuntu 26.04,
    kernel 7.0.0-30, aarch64, glibc, 4 CPUs) with a temporary fourth field on the `S` line carrying
    `us`, as the worst `cap - rusage` of each cell over **220 runs**: cap 1 s -> **9.34%**, cap 2 s
    -> **9.14%** quiet (66.8 ms .. 182.9 ms, n=40), 7.70% with 4 spinners, 9.23% with 8, 9.14% with
    16, cap 4 s -> **9.10%** (max 363.8 ms), cap 8 s -> **9.13%** (max 730.3 ms). A ceiling of
    about **9.3% of the cap**, flat across a cap that varies by 8x and a load that varies from idle
    to four spinners per CPU. A tenth of a second is 5% of a 2 s cap and 0.1% of a day, so the old
    rule sat below the ceiling at the one cap it was measured at: **quiet, 25 of 40 runs were
    correct here**, and 31 of 40 with four spinners. Host load moves the distribution around inside
    that band and was never the cause -- four spinners came out BETTER than idle.
  * **The rule is a fraction**: `sig == SB_SIGKILL && us * 4 >= sb_time() * 3000000` -- a step that
    spent three quarters of its CPU budget and then died of SIGKILL spent all of it, three quarters
    being **2.7x** the worst shortfall ever measured. SIGXCPU stays proof on its own. The SIGKILL
    gate is new and costs nothing (`RLIMIT_CPU` delivers no other signal here), and it buys one
    thing: a segfault inside the last quarter of the budget now reads as a segfault where the
    unconditional comparison would have called it a cap.
    **Residual**: a step that kills ITSELF with SIGKILL that late reads as a cpu cap. A kill from
    outside cannot reach the decision -- P's kills (the wall clock, a refusal) take J down with the
    box through `zap_pid_ns_processes()`, and J is the only process that writes an `S` line.
  * **Past eight spinners the wall clock wins, correctly**: with 16 spinners on 4 CPUs the program
    gets ~4/17 of a CPU, so 2 CPU-seconds need ~8.5 s of wall and the default `--wall 5` fires
    first (`killed: wall clock (5 s)`, exit 124). That is the right answer, which is why the
    acceptance range is four to eight; with `--wall 30` the cpu verdict is **30/30 at 16 spinners**.
  -- cost: **one code line** in `src/sandbox_box.mc` (+31/-5 by line count, the other 30 added lines
  being the measurement written into the doc comment). Zero new globals; `check-limits` **17/17
  under 90%**, unchanged. `make bundle` re-run BEFORE bootstrapping (101 files, raw 1476608 -> LZ
  675947, blob 677198 B). Acceptance on the Lima oracle after the fix: `forever` **40/40 correct
  with 4 spinners** and **40/40 with 8** (before: 7/12, and 25/40 quiet), `sleeper` and every
  `refused:` case unchanged, `scripts/test-sandbox.sh` **73 ok, 0 failed, 1 skipped** as root AND
  unprivileged, and `sh scripts/sandbox-trace.sh --check` green (the profile lists were not
  touched; the sysctl was flipped to 0 for the unprivileged cell and restored to 1).
  `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `check-obj` **32/32
  identical to the frozen seed**, `check-bundle`, `bootstrap` at BOTH fixed points
  (`mc2.o == mc3.o`, `mc2o.o == mc3o.o`) with the cross-road identity
  (`build/mc2o src/mc.mc == build/mc2.o`) and **both `--dump-asm` diffs between `mc1` and `mc2`
  empty** (plain and `--opt=1`), `check-surface` 32/32, `check-opt`, `test-exe` 32/32,
  `check-standalone`, `check-parts`, `check-limits` 17/17 under 90%, `test-sandbox` 73 ok / 0
  failed / 1 skipped, `check-site-linux` 21/21, `check-docs` (206 symbols, 49 flags, 35 TOML keys,
  10 directives, 52 samples, 476 links).
  `make check-linux-host` RC 0 over **all four cells** (aarch64 and x86_64 x musl and gnu), each
  after its own `mc2l.o == mc3l.o` and with the cross proof (`mc2l --backend=macho src/mc.mc` byte
  for byte the macOS `build/mc2.o`) green.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main`
  075dbec): **33 objects identical on the plain road and 33 on `--opt=1`** (`tests/*.mc` and
  `src/mc.mc`) plus byte-identical artefacts for `examples/api`, `lang`, `conc`, `desktop` and
  `kernel` -- the sandbox emits nothing, so nothing the compiler writes could move.
  **All ten goldens rewritten once**, each only after its own criterion -- the blob is what moved:
  `mc2.sha256` `e965d181...f80682` ->
  `75ddb416e234c30e8dd3694d392975d7392cb5be15dffd026ddc9995394ddadc`, `mc2-opt.sha256`
  `d590a967cfeecb5f02798f23828fd6ebc0f7c5913f072374df4b8718a33f30ae`, both recorded by
  `scripts/bootstrap.sh` after the two fixed-point comparisons and the two empty `--dump-asm`
  diffs; the four Linux ones deleted and re-recorded by `make check-linux-host` --
  `mc2-linux-arm64.sha256`
  `94719d464d32f6f518a91698cbe7413735b248b049548f38388cadd1c19a1519`,
  `mc2-linux-arm64-opt.sha256`
  `9b247032a177b2751262aa9d0bf650ecd39bf4eb91e6471ddf23e4cff04fe7a3`,
  `mc2-linux-x86_64.sha256`
  `1ce8389b769aa0a2950639a2d2389ca413ce5b0c53d149c6023fff3500a6c684`,
  `mc2-linux-x86_64-opt.sha256`
  `14d7d64184bb127ab5134ec047fb39f05d7c4733f89ba0b125306f1a0bc94899`; the four Windows ones
  cross-computed per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `618935bce3def95d80b952d22235267be1c902bdb9ed14b8c57fd086853b1e73` (1585454 B),
  `mc2-windows-arm64-opt.sha256`
  `f03c952dd610afab3e737647e169a4c60b0601625528df0b9cc5e93019e9c884` (1527150 B),
  `mc2-windows-x86_64.sha256`
  `8f98e6baf86e21de8ebf0c0e4a1eea58e17e3333361dc4a32e2412a31de37c69` (1640198 B),
  `mc2-windows-x86_64-opt.sha256`
  `64cc3fe53c505e7cc02b4e9651e267ff08db0d2f13638d89dd1d38bc0dfea192` (1568754 B), all four also
  written byte for byte by `build/mc2`.
- M50 step A ✔ (`docs/specs/M50.md` § 9 row 1 + its new § Implementation notes -- step A):
  **the bench cell's runner, its schema and the phase argument.** Nothing in `src/`, `stage0/`,
  `lib/` or `tests/` -- `git diff origin/main -- src/ stage0/ lib/ tests/` is empty, no golden moves,
  `bench/` is bundled nowhere. The milestone's whole point is that the two caveats
  `docs/comparison.md` § Conditions records have DIFFERENT cures and only one of them is hardware:
  the stale tree label is cured by a DIGEST, and the shared host is cured by a REFERENCE TIMED IN
  THE SAME RUN, not by a machine this project can reach.
  * **`bench/cell/cell.py` (593 lines)** is one cell run: build every row whose toolchain is here,
    then **seven repetitions with the rows interleaved inside each one** in a fixed order, one
    process at a time, `taskset -c 0` on Linux and nothing on macOS; repetition 1 recorded and
    excluded from every statistic; **every repetition of every row asserts the workload's own
    recorded answer** for its phase, so a wrong number is a failed row and not a fast one; then
    per-row best/median/max of the kept six and `median(row) / median(clang -O2 built and timed in
    this same run)`. `results.json` per § 5.1 (the cell's identity, the `mc` block with its
    SHA-256, every toolchain string as its tool PRINTED it, the pins, every build and run command
    verbatim, all seven seconds per row, RSS, `stdout_ok`, the ratio, the verdict), plus
    `facts.json` and a `RESULTS.md`. Python 3 stdlib only. A toolchain that is absent, or a row
    whose build fails, is **SKIPPED with its reason printed and recorded** -- never faked.
  * **`bench/cell/build.sh` (78)** builds ONE row, `bench/soak/build.sh`'s shape, `MC`/`CC`/`LIBC`
    overrides, and its last line of stdout is `run: <command>` -- which is how `cell.py` never
    learns that `cs-jit` is launched through the `dotnet` muxer while every other row is a binary.
  * **`bench/cell/versions.env` (91)** is the one file the workflow, the local road and `cell.py`
    all read: `GO_VERSION=1.26.7`, `DOTNET_VERSION=10.0.400`, `ZIG_VERSION=0.16.0`,
    `RUST_VERSION=1.96.0`, `CLANG_APT=clang-18`, `REPS=7`, `DROP=1`, `TOLERANCE=0.05`,
    `REGRESS_MIN=1.5` -- with the MEASURED basis of the last two written into it beside the value,
    which is what step A owed.
  * **The phase argument** in all six sources (D11, **78 added / 25 removed**): `mix`, `primes`,
    `fib` by the argument's FIRST BYTE, no string comparison anywhere, and **no argument (or a
    mistyped one) runs all three in the recorded order**. Default stdout is byte for byte what it
    was on every one of the six -- md5 `c369e8b4679ca95f45fa46bbff03b7b7`, which is
    `bench/results.json`'s own `output_md5_all_variants` -- so `bench/run.sh`'s contract and every
    recorded number stay comparable (`make bench` green). The mc BINARY does move (`i64 main()`
    became `i64 main(i64 argc, uptr argv)`); nothing gates a `bench/` binary's bytes and risk 7's
    contract is the stdout. Zig 0.16 was the awkward one: `std.process.args()` is gone and the
    iterator is `std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa)`, probed
    against the installed standard library before the file was edited.
  * `make bench-cell` (`CELLFLAGS=` for a subset), **not in `make check`** (D12) and never will be.
    Results go to `build/bench-cell/<date>-<id>/`, which is untracked, so a local run stages
    nothing; `--out bench/results/<date>-<run-id>` is the directory step C commits.
  **Measured here** (Apple M4, Darwin 25.6.0, nothing pinned -- macOS has no `taskset`, so this is
  the noisiest of the three cells step B will add): **all eleven rows ran**, Apple clang 21.0.0,
  go1.26.4, zig 0.16.0, rustc 1.96.0, .NET SDK 10.0.301. The two version mismatches against the
  pins are exactly the drift D5 exists for and they are **visible in `facts.json`** rather than
  hidden. `cs-aot` had to be un-skipped: NativeAOT links libssl and libbrotli, which macOS does not
  ship (`ld: library 'ssl' not found`, the wart `bench/RESULTS.md` § A already records), so
  `build.sh` sets `LIBRARY_PATH` on Darwin as that page did -- where the libraries are absent the
  row skips with the linker's own message.
  **SIX full runs, three consecutive PAIRS**, 11 rows x 4 phases x 7 repetitions each.
  Worst per-row RATIO drift inside a pair, and rows of that phase over 5%: `all` 2.44 / 4.54 /
  4.76% with **0, 0, 0** over; `mix` 4.18 / 4.97 / 6.49% with 0, 0, 1; `primes` 3.56 / 5.85 /
  8.36% with 0, 1, **4**; `fib` 3.25 / 6.84 / 4.98% with 0, 1, 0 (median row 1.10-3.43%
  everywhere). The same runs' ABSOLUTE medians moved by up to **15.77%** and the reference row
  alone by **-9.34%** between two runs started back to back -- the ratios held while the machine
  underneath did not, which is the shape § 1.2 describes and § 4.4's health indicator is for; § 1.2's
  own 0.7% was one pair of FOUR rows, and the worst of 44 is necessarily larger. **So
  `TOLERANCE = 0.05` is right for the `all` phase (0 violations in three pairs, ~5% of margin) and
  wrong for the three short ones (7 of 99 rows over it)**: under 0.25 s both medians in the quotient
  are dominated by scheduler noise and their errors ADD instead of cancelling -- § 1.3 item 3's
  finding one level down, and in pair 3 the machine barely moved (reference -1.04%) while the worst
  ratio drift was still 8.36%. Recommended to step C, measured and not guessed: gate the band on
  `all`, report the per-phase ratios beside it, re-measure on the two pinned Linux cells.
  **Repetition 1 earns its drop on the phase that runs FIRST**: over every row of a run the median
  gap is only 1.03-1.10x, but `all` alone -- where the binary's pages and the 50 MB `__bss` sieve
  are first touched -- is **1.28x, 1.33x, 1.56x, 1.34x** median with a worst row of **1.79x**, the
  1.25-1.62x band `bench/results.json`'s own three-run rows show, and the three later phases of the
  same repetition sit at 1.01-1.12x. `results.json` therefore records the gap PER PHASE.
  **The teeth, and the one deviation from the spec**: § 4.3 puts the floor on the whole source, and
  the tooth per phase over the six runs is `all` 1.554-1.619, `mix` **2.243-2.379**, `primes`
  1.049-1.093, `fib` 0.996-1.037 -- M49 moves `mix` by 2.3x, `primes` by 5% and `fib` by nothing
  (its cost is its call count), so `all` is a weighted average landing 4-8% above the floor, and on
  the quieter host M49 step C measured it was 0.793 / 0.548 = **1.45**, which a 1.5 floor would have
  FAILED. `versions.env` carries `REGRESS_MIN=1.5` with **`REGRESS_PHASE=mix`**: the same floor, on
  the phase the optimizer is about, with half again of margin. Every run reports and gates it.
  The `mc` row measured, as the cell recorded it: `build/mc1`, `mc 0.0.0-dev`, `macos/aarch64`,
  SHA-256 `171025cc475abcd77591915172e9ebda4a382bf4835448792fcdb2179a95afc3`, 1 408 400 B -- a
  digest, so `bench/results.json:234`'s `"tree at commit e5a1643"` failure mode is structurally
  impossible after this.
  -- `make check` green end to end (RC 0, zero FAIL), `make check-docs` green (206 symbols, 49
  flags, 35 TOML keys, 10 directives, 52 samples, 482 links -- the new pages are under `bench/`,
  which `scripts/check-docs.sh` does not walk, and no fenced ` ```mc ` block was added), `make
  bench` green. `git diff origin/main -- src/ stage0/ lib/ tests/` **empty**; the `Makefile` diff is the
  new `bench-cell` target and its `.PHONY` entry; **no golden rewritten** -- nothing the compiler
  emits could move.
  Not in this step and named in § Implementation notes 10: `bench/cell/gate.py` and the first
  committed `bench/results/` directories (step C), `.github/workflows/bench-cell.yml` and the
  three cells (step B), any Dockerfile (D13, deferred).
- M50 step B ✔ (`docs/specs/M50.md` § 9 row 2 + its new § Implementation notes -- step B):
  **the bench-cell workflow, three cells, and the first x86-64 timing of M49 D2's allocator.**
  Nothing in `src/`, `stage0/`, `lib/` or `tests/` -- `git diff main -- src/ stage0/ lib/ tests/` is
  empty, no golden moves. `.github/workflows/bench-cell.yml` (299 lines): a `plan` job turning the
  `cells` input into a (cell, toolchain) matrix with `cell.py --plan` (an unknown cell fails THERE,
  before eighteen runners are spent), **one job per TOOLCHAIN** on `macos-15` /
  `ubuntu-24.04-arm` / `ubuntu-latest` with only that toolchain installed at the version
  `bench/cell/versions.env` pins and `clang -O2` of `bench/c/bench.c` built and timed INSIDE every
  one of them as the reference, and a `report` job merging every artifact into one `results.json`
  and one `RESULTS.md` **per cell**. Dispatch inputs `ref`/`cells`/`reps`/`mc-version` plus the
  Sunday 06:00 UTC cron; never on a push, a pull request or a tag; `permissions: contents: read`, so
  nothing is committed and the run summary prints the `gh run download` line a human uses. `cell.py`
  +222/-14 (180 code): `--plan`, `--toolchain`, `--merge`, the runner's own `ImageOS`/`ImageVersion`
  and the `MC_ROAD`/`MC_TAG`/`MC_ASSET`/`MC_ASSET_SHA256`/`MC_COMMIT` the workflow fills. **No
  `facts.py`** (the spec priced ~60 python for it): `cell.py` already owned `host_facts` and the
  report writer.
  **Three dispatches of the real workflow**, 18 jobs each, 21:00-21:13 UTC 2026-09-13 --
  `34782461342`, `34782812594`, `34783020976`. `workflow_dispatch` cannot reach a workflow that is
  not on the default branch (`HTTP 404`), so the runs were triggered by a `push:` trigger added in
  its own commit and **deleted before the merge**.
  * **Acceptance 4, the number M49 step D2 deferred to this cell**: on `ubuntu-latest`, `mc -O` is
    **1.500 / 1.447x `clang -O2`** on `mix` and the tooth (`mc` plain / `mc -O`) is
    **1.213 / 1.193** -- the x86-64 allocator buys **19-21%** where AArch64's buys **130-265%**
    (`linux-arm64` tooth 3.645 / 3.650, `macos-arm64` 2.305 / 2.422). Five allocatable registers
    against ten. Until this run that side had only an instruction count (-11.6%).
  * **The floor became per-architecture**, the step's one design change: 1.5 was calibrated on
    AArch64, so runs 1 and 2 correctly FAILED with `tooth 1.181 below 1.50`.
    `REGRESS_MIN_X86_64=1.10` (7-9% below both measurements, 10% above the 1.00 a dead allocator
    gives); `REGRESS_PHASE` needs no per-cell value -- on `ubuntu-latest` the tooth's run-to-run
    spread is 2.6% on `mix` against 28.7% / 69.3% / 8.5% on `all` / `primes` / `fib`. Run 3 green on
    all three cells.
  * **Acceptance 1 is met on ONE cell of three, and that refutes step A's recommendation.** Worst
    per-row `all` drift between two complete runs: `linux-arm64` **4.80%, 0 rows over 5%**;
    `macos-arm64` 12.24%, 2 over; `linux-x86_64` 22.60%, 1 over. The mechanism is measured: a job's
    own reference median moved **+31.81%** between the runs, and inside ONE run the six per-job
    references of `macos-arm64` spanned 0.556-0.719 s for the same `clang -O2` binary. A row's ratio
    carries its own job's noise. What holds is an IN-JOB ratio: the tooth drifts 0.13% / 1.6% /
    5.1%. Recommended to step C, which owns `gate.py`: gate in-job, report cross-run (0.25 would
    cover everything measured).
  * **Two step-A defects the first run found, both invisible locally**: a RELATIVE `--out` made
    `build.sh`'s `cd` resolve `-o <out>/go` wrongly and **five of eleven rows were SKIPPED on every
    cell** (`cell.py` now makes the directory absolute; runs 2 and 3 have all eleven rows and no
    skips anywhere), and the merge's blind `update()` let the five jobs that do NOT install Go and
    Rust overwrite the pinned strings with the image's preinstalled ones -- the first report claimed
    go1.24.13 and rustc 1.98.1 where the owning jobs had installed **1.26.7** and **1.96.0**. After
    the fix every cell reports exactly what is pinned.
  * **The runners are not the reference machines and the cell says so**: `macos-15` is an **Apple M1
    (Virtual)**, `ubuntu-24.04-arm` publishes no `model name`, and `ubuntu-latest` was an **AMD EPYC
    7763** in run 1 and an **Intel Xeon 8573C** in run 2 -- risk 2 happening twenty minutes apart,
    on the first day. M49's 1.30x stays an Apple M4 number no cell reproduces (D14).
  * **Acceptance 9**: 35 s to 1m31s per job, 4.12-6.18 min per cell, **17.2 min of runner time for a
    full three-cell run** in 2m25s-3m1s of wall clock -- about a third of the spec's ~1 runner-hour
    estimate, because the timing is ~21 s and the toolchain install dominates.
  -- `make check` **RC 0, zero FAIL** (`test-sandbox` 73 ok / 0 failed / 1 skipped as its last
  line), `make check-docs` green (206 symbols, 49 flags, 35 TOML keys, 10 directives, 52 samples,
  484 links). Docs: `docs/ci.md` (a `bench-cell.yml` section, and the table gained rows for BOTH
  bench workflows -- the count sentence said five and the file count was already six),
  `bench/cell/README.md` (how to dispatch, how to read a run, what the three cells measured),
  `docs/specs/M50.md` § 9 row 2 LANDED with the real line counts + nine implementation notes.
  Step C (`gate.py`, the first committed `bench/results/` directories, `docs/comparison.md`
  § Conditions) is what remains to close M50.
- M50 step C ✔ (`docs/specs/M50.md` § 9 row 3 + its § Implementation notes -- step C): **the gate,
  the committed history, and `docs/comparison.md` without its two caveats** -- the step that CLOSES
  M50. Nothing in `src/`, `stage0/`, `lib/` or `tests/` -- `git diff main -- src/ stage0/ lib/
  tests/` is empty, no golden moves, `bench/` is bundled nowhere.
  * **`bench/cell/gate.py` (273 lines, 171 of them code)** reads a fresh `results.json` (or a
    directory of them -- what `cell.py --merge` writes) and the **newest COMMITTED run of the same
    cell id** under `bench/results/`, and answers in three registers. What it GATES is exactly what
    the measurements support, which is the one design decision step B sent it: **the teeth**
    (`median(mc-plain) / median(mc-opt)` on `REGRESS_PHASE`, against the per-architecture
    `REGRESS_MIN`) and a row that printed the wrong answer. Both medians of the tooth come from the
    SAME job of the SAME run, which is why a cross-run comparison of it holds -- measured again
    here, between the committed run and this step's own: **0.25% (`linux-arm64` 3.650 -> 3.641),
    1.6% (`linux-x86_64` 1.193 -> 1.212), 4.4% (`macos-arm64` 2.422 -> 2.315)**, reproducing step
    B's 0.13 / 1.6 / 5.1%.
    Every row's `ratio_to_reference` drift against the committed run is a **REPORT** with
    `TOLERANCE` as the band, the worst five printed and the count beside them -- not a gate, because
    the reference is timed once per JOB and step B measured a job's own reference median moving
    +31.81% between two runs, so a 5% band held on `linux-arm64` alone. The reference's own absolute
    median is a **NOTE** at 10% (D15), beside a changed CPU model or runner image (risk 2). A cell
    id with nothing committed says `baseline recorded` and exits 0 (§ 4.5, risk 6). The thresholds
    come from `versions.env` and never from the run being gated -- a gate that took its floor out of
    its own artefact would pass whatever the artefact claimed. Under `GITHUB_ACTIONS` every report
    and note is a `::notice::` annotation and every failure a `::error::`.
  * **Wired into both roads.** `make bench-cell` runs `cell.py` then `gate.py` (which with no
    argument gates the newest directory under `build/bench-cell`); the workflow's `report` job runs
    it LAST, after the summary, so a failure never hides the numbers that produced it, with
    `set -o pipefail` and an explicit `exit $rc` because a `run:` step's default shell is `bash -e`
    and not `-o pipefail`. **It blocks no merge and no release either way** (D12): this workflow runs
    on neither a pull request nor a tag, so the only thing it can fail is its own run -- and it DOES
    fail that run on the teeth, which is § 8 item 2's "a deliberately regressed `mc` build fails the
    cell".
  * **Acceptance 2, proved end to end by two real dispatches** (the workflow is on the default
    branch now, so `gh workflow run bench-cell.yml --ref m50-step-c` reaches it; step B had to add a
    `push:` trigger for the same thing). The regression is the spec's own one-flag form --
    `bench/cell/build.sh`'s `opt="-O"` set to `opt="--opt=0"`, in a temporary commit dropped before
    the merge, because `--opt=0` IS the default and the two mc rows become the same binary.
    **Run [`34785520475`](https://github.com/minicompiler/mc/actions/runs/34785520475): FAILURE.**
    All three `mc` jobs fail inside `cell.py` and the `report` job's gate fails again with the same
    three lines, one per architecture: `tooth 1.001 below 1.50 on phase mix` (`linux-arm64`),
    `tooth 0.981 below 1.50` (`macos-arm64`), `tooth 1.006 below 1.10` (`linux-x86_64`). The drift
    REPORT named it too, from the other side -- `mc-opt/mix ratio 1.805 -> 6.574 (+264.2%)` -- which
    is what a per-cell history buys even where the band is not gated.
    **Run [`34785739260`](https://github.com/minicompiler/mc/actions/runs/34785739260): SUCCESS**,
    18 jobs, `ok 3 cell run(s) gated, no failures`, teeth 3.641 / 1.212 / 2.315 with 143% / 10% /
    54% of margin over their floors.
  * **The first committed history**: `bench/results/2026-09-13-34783020976/<cell id>/{results.json,
    RESULTS.md}` for the three cells of step B's green run, fetched with `gh run download` and
    committed by a human (D8 -- the workflow keeps `contents: read`; a workflow that pushed to
    `main` would make `autotag.yml` cut a version for a benchmark). `git blame` over
    `results.json` is the regression history the plan row asks for. **Deviation, on record**:
    § 5.1's third file, `facts.json`, is NOT in the committed directory -- `cell.py --merge` writes
    `results.json` + `RESULTS.md` per cell and the per-job `facts.json` stays in the 90-day
    artifacts; the identity that matters (cpu model, kernel, image, pinned cpus, every toolchain
    string as its tool printed it, the mc digests) is inside `results.json` itself. Also on record:
    only ONE run is committed, the one the task named -- the weekly cron adds the second, and this
    step's own green run is the one gate.py was measured against rather than a second row of history.
  * **Acceptance 3**: `docs/comparison.md` § Conditions lost **both** caveats -- "one host, shared
    with other work" and the stale `e5a1643` tree label -- for a **cell-of-record** block naming the
    run, its committed directory, and per cell the machine and image, the `mc` tag and asset, the
    **verified asset SHA-256**, the **timed binary's SHA-256 and byte count**, and the reference's
    absolute median (0.719 / 0.381 / 0.569 s), with the pins and the two thresholds beside them. It
    says plainly what no machine can fix and what the cell does instead. The workload table gained
    its second block -- the three cells' in-job ratios for `mc -O` and `mc` plain against
    `clang -O2`, per phase, with the tooth, hand-copied from the committed JSON (D9: no generator
    writes into `docs/`) -- and § Where to improve item 1 now carries the x86-64 number (five
    registers, **19-21%** against 130-265% on AArch64, `mc -O` at 1.45x `clang -O2` on `mix`) in
    place of its stale "the six slots are still empty" sentence, while item 2 is marked done with
    the reason the VPS road was refused. The HTTP tables keep their own ~20% caveat, unchanged and
    correctly scoped: those rows are deliberately out of the cell (0.9-228.5% recorded spread).
  -- cost: **273 lines of new python** (171 code) + 12 added lines across `cell.py` (the
  `RESULTS.md` link made depth-independent), the `Makefile` and the workflow + ~200 in docs.
  `make check` green end to end (**RC 0, zero FAIL**), `make check-docs` green (the new relative
  links into `bench/results/...` and `bench/cell/versions.env` all resolve), `site` + `check-site`
  green (comparison.md renders, 0 link problems). `git diff main -- src/ stage0/ lib/ tests/`
  **empty**; no golden rewritten.
  Docs: `docs/comparison.md` (§ Conditions, the workload table's second block, § Where to improve
  items 1 and 2), `bench/cell/README.md` § The committed history and `gate.py`, `bench/README.md`
  § D, `docs/ci.md` § `bench-cell.yml` (what the gate step can fail and what it cannot),
  `docs/plan.md`'s M50 row marked done with the numbers, `docs/specs/M50.md` § 9 row 3 LANDED with
  the real line count + its § Implementation notes -- step C.
- The registry index snapshot is refreshed when its answer could be stale (reported by the teko
  consumer against mc 0.15.23 with a pure-mc reproducer; `docs/specs/M44.md` § Implementation
  notes -- the stale index): **`pkg_index_file` fetched the snapshot once and read it for ever
  after.** `stage0/` untouched (2848/3000). Reproduced before anything was written, on a compiler
  built from `main`, over an `https://` registry a fixture `curl` serves: sync at `teko = "0.9.0"`
  writes `<libs>/index/teko.toml`; the registry gains 0.10.0; `mc pkg sync --yes` at 0.10.0 is
  **`mc: teko 0.10.0: no such version in the registry`, exit 1**, with the registry serving it --
  and `rm ~/.mc/libs/index/teko.toml` the only way out.
  * **The rule is "with `--yes` the snapshot is refreshed, not read".** `--yes` means "you may
    download" and it is carried by exactly the roads that ask the registry a question whose answer
    changes over time (`sync`, `add`, `mc update`, `mc install`, `mc upgrade`); at most one download
    per package per invocation, because `pkg_index_load` memoises. Without `--yes` the snapshot is
    read exactly as it is -- that offline read is what it exists for -- and **`mc build` is not
    involved either way**: it reads `mc.lock` and never the index, which is what the § 5 promise
    actually protects. Refresh-on-miss-and-retry was rejected as INSUFFICIENT, not merely bigger: a
    stale snapshot answers `pkg_newest`/`pkg_lowest`/`pkg_highest` with a version that EXISTS, so
    there is no miss to notice and `mc pkg add NAME` would silently choose the old one (asserted).
  * **The second half is the negative answers such a snapshot must not give.**
    `pkg_index_maybe_stale(name)` (a URL registry and no `--yes`) guards the three of them --
    `pkg_expand`'s missing row, `pkg_pick`'s missing-or-nothing-to-choose-from, `pkg_reselect`'s
    empty range -- and each plans the index fetch instead, landing in the existing `fetch  index
    <name>` + `nothing was downloaded: re-run with --yes` at exit 0. `pkg_index_load` already
    answered 0 under exactly that condition when there was no snapshot at all, which is why the two
    cases merge into one branch at each site. **No message was added and none changed**;
    `pkg_check_immutable` was left alone (it fetches into its own `<snapshot>.published` and must
    read a 404 as "a new package", so it is a different read and not a duplicate).
  -- cost: `src/pkg.mc` **+71/-20, 33 added lines that are neither comment nor blank**; zero new
  globals (`build/mc1 limits src/mc.mc` reports `globals 446/512` before and after, and
  `check-limits` is **17/17 under 90%**, its tightest row `globals 268/512 = 52%` on
  `src/mc_seed.mc`). `scripts/check-pkg.sh` § 36, **177 -> 183/183**, offline like everything above
  it: a THIRD bin directory whose `curl` serves `$WEBROOT` instead of exiting 97, so the transfer is
  a file copy through exactly the argv `fetch_get` builds while the two refusing downloaders stay on
  PATH for every other section. Six cases -- the first sync writing the snapshot, the reproducer
  itself (a row published after it, found with nothing deleted by hand), a version that truly does
  not exist still refused with the same message after one refresh, the no-`--yes` plan with the
  snapshot left untouched, `mc pkg add` picking the newly published newest, and **`mc build` green
  on a locked project under the REFUSING downloader**.
  `make bundle` re-run BEFORE bootstrapping (`src/pkg.mc` is `mc/pkg`): 101 files, raw 1479468 ->
  LZ 677117, blob 678368 B. `make check` green end to end (**RC 0, zero FAIL**), `check-obj`
  **32/32 identical to the frozen seed**, both fixed points (`mc2.o == mc3.o`, `mc2o.o == mc3o.o`)
  with the cross-road identity and **both `--dump-asm` diffs between `mc1` and `mc2` empty** (plain
  and `--opt=1`), `test-sandbox` 73 ok / 0 failed / 1 skipped as its last gate.
  `scripts/check-inert.sh <pre> build/mc1`: **33 objects identical on the plain road and 33 on
  `--opt=1`** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for `examples/api`,
  `lang`, `conc`, `desktop` and `kernel` -- a package-manager fix emits no different byte.
  **All ten goldens rewritten once**, each only after its own criterion -- the blob and `src/pkg.mc`
  are what moved: `mc2.sha256`
  `1b56148c4c1b11e57664072797e3dd8b7536b10b8e388653e0c80af1dacd5029`, `mc2-opt.sha256`
  `adc33a341a1aa80c48d94aeb4fbc9ab4c2c4c09977c547265ca2a41a3ecb6e4c` (both recorded by
  `make bootstrap` after the two empty `--dump-asm` diffs and the two `cmp`s); the four Linux ones
  deleted and re-recorded by **`make check-linux-host` RC 0 over all four cells** (aarch64 and
  x86_64 x musl and gnu), each after its own plain AND optimized fixed point, its own cross-road
  identity and the cross proof (`mc2l --backend=macho src/mc.mc` byte for byte the macOS
  `build/mc2.o`) -- `mc2-linux-arm64.sha256`
  `2d22393da374ae2fb5252f429d919663e14f15c5d176021ef9fc0ea18a04616e`,
  `mc2-linux-arm64-opt.sha256`
  `91035e13960e9acb1a85e618bd793d2e7089622df6744c81f6f43c2dcefda0ea`,
  `mc2-linux-x86_64.sha256`
  `0a1b1305a460c7c6c662b2aab31b3eefa23a55adcc2ae8ab8c29a83eeb6ed2a1`,
  `mc2-linux-x86_64-opt.sha256`
  `2d73d574e2864ffa69b35e85fa68ac02b364d3e9ff678c42c94402c09fb243b5`; the four Windows ones
  cross-computed on macOS
  per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `455e35b2eaecd1d017e2a4dfcb1c02e893f1192e4d126e023bfcb8fe5696469e` (1587307 B),
  `mc2-windows-arm64-opt.sha256`
  `ebdb305a2fd13691741059084c28f1aef24e9bad0d1f0b254bada1f08113974d` (1528975 B),
  `mc2-windows-x86_64.sha256`
  `1d3dc718d5cb805096a42bd50715f8d501cbe1fb4bb8a89bf91d9ab20228634a` (1642183 B),
  `mc2-windows-x86_64-opt.sha256`
  `b0da93d82b23507c80cd671320d5b63999b135957e9095d5a25f794ec6a12afa` (1570723 B), all four also
  written byte for byte by `build/mc2`.
  Docs: `docs/reference/packages.md` § 10 (§ "When the snapshot is refreshed"),
  `docs/reference/cli.md` (the `--registry` row), `docs/reference/diagnostics.md` (the
  `no such version in the registry` row now says when it is raised), `docs/specs/M44.md`.
- M52 step A ✔ (`docs/specs/M52.md` § 4 D4/D5/D6, § 10.2, § 10.6, § 11 row 1 + its new
  § Implementation notes -- step A): **the library root beside the binary, and the refusal that
  names `mc install`.** `stage0/` untouched (2848/3000, `git diff main -- stage0/` empty).
  **Inert by design**: the blob still carries all 101 rows, so every name a program can spell is
  still answered by step 2 of the resolution order, and the new road is proved with a name the
  blob does NOT have.
  * **D4, three roots instead of one** (`src/deps.mc`): `dp_mc_root()` tries
    `<libs>/mc/v<version>/` (`--libs-dir` or `$HOME/.mc/libs` -- FIRST, so an explicit
    `mc install` still wins over the copy that shipped), then
    `<dir of host_self_path()>/lib/mc/v<version>/`, then the same one directory up
    (`/usr/local/bin/mc` finding `/usr/local/lib/mc/v<version>/`). A root is recognised by its
    `bundle.list` and by nothing else, so a `<libs>` directory that exists and is empty does not
    silently fall through to the tree beside the binary. Roots 2 and 3 are `path_join(self, ...)`
    -- which cuts its base at the last slash, i.e. "the directory of this file", and normalises
    the `..` lexically -- and a self path with **no slash in it is refused**, because `path_join`
    would then answer a relative path and the working directory is never a root
    (`docs/determinism.md`). A PARTIAL tree is safe by construction: `dp_mc_open` falls through on
    any name whose file is not readable, which is what lets a release stage the library files and
    nothing of `src/`.
  * **D6, the refusal is widened** (`src/lex.mc`, `src/deps.mc`): the hint is asked whenever
    NOTHING answered, not only when this binary has no bundle, and it distinguishes three states.
    A root was found -> 0, and `unknown bundled include: <name>` is unchanged, which is the row
    `check-pkg` asserts twice. No root and no blob (`mc-slim`) -> the M44 sentence, unchanged. No
    root and a blob -> `#include <sys>: not in this compiler and mc 0.0.0-dev's library tree was
    not found: run mc install`, which is what a binary copied out of a release tarball WITHOUT the
    `lib/` directory beside it says. `dep_include_hint` reads `bopen_fn` directly: whether this
    binary carries a blob is one global in `src/lex.mc`, and `src/deps.mc` is compiled after it in
    every assembly that contains it, so the hook needed no new argument.
  * **D5, `make` lays the root** (`scripts/libroot.sh`, 50 lines, new; `Makefile` +25/-3):
    `build/lib/mc/v<mc_version()>/` beside `build/mc1`, holding `bundle.list` and the 41 `lib/`
    files the manifest names (256 685 B). **`scripts/release-assets.sh` calls the same script**
    (+22/-2) to stage `lib/mc/v<ver>/` in every tarball, full and slim -- one definition, because
    a release whose library root is laid differently from the one every gate runs against is a
    release nothing tested. With it, every check script keeps working with no new flag, no
    `--libs-dir` and no dependence on `$HOME`.
  * **`scripts/check-libroot.sh`** (178 lines, `make check-libroot`, inside `make check`):
    **7/7**. Because the blob still has every real name, each positive case adds ONE row to the
    tree under test -- `m52probe`, three lines of mc returning 42 -- and compiles, links and RUNS
    a program that calls it, so the case says which road answered instead of asserting a name that
    would have worked anyway. (a) no root: the exact D6 sentence, exit 1; (b) root 2 serves it,
    exit 42; (c) root 3, with the binary in a `bin/` beside a `lib/`; (d) precedence, two trees
    differing in one byte (`<libs>` says 42, the tree beside the binary says 7) and the program
    exits 42; (e) a misspelled name with a root present keeps `unknown bundled include:
    no/such/module`; (f) `scripts/release-assets.sh`'s archive untarred -- `lib/mc/v<ver>/` with
    `bundle.list` and all 41 files -- and used as a root with an empty `$HOME`, no `--libs-dir`
    and no network. **Teeth measured**: against a `build/mc1` built from `main`, the same script
    is **3/7 with four failures** (each `unknown bundled include: m52probe`) and exit 1.
  * **`scripts/check-standalone.sh` case 5 moved, and that is D6 working**: that script copies the
    binary into an empty directory and now runs it with an empty `HOME` too, so it is exactly
    state 1 and asserts the sentence that names the road. `docs/bootstrap.md` gained
    § "What 'alone' means for the LIBRARY": the compiler's own source is inside the binary (what
    the `cmp` against `build/mc2.o` proves, unchanged), the standard library travels beside it.
  * **Deviation, on record** (§ Implementation notes 8): case (f) compiles `<m52probe>` and not
    the `<float>` program § 10.7 names -- `lib/float.mc` is a compiler MODULE and needs a taught
    compiler built first, minutes in a gate that runs in seconds. Step B, where `<float>` leaves
    the blob, is where the literal form becomes measurable.
  -- cost, `git diff --numstat main -- src/` (the generated `src/bundle_data.mc` excluded):
  `src/deps.mc` **+78/-18**, `src/lex.mc` **+8/-6** = **86 added lines, 37 of them neither comment
  nor blank** (the spec priced ~40). **Zero new globals**: `build/mc1 limits src/mc.mc` reports
  `globals 446/512` before and after, and `funcs` 1951 -> 1954, the three being `dp_root_at`,
  `dp_root_beside` and `dp_mc_root`.
  `make bundle` re-run BEFORE bootstrapping (101 files, raw 1482105 -> LZ 678232, blob 679483 B).
  `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test` 32/32,
  `check-lex` 177/177 (5 skipped), `check-ast`/`check-asm` 178/178, `check-obj` **32/32 identical
  to the frozen seed** (and 32/32 `arm64-surface` against `macho`), `check-bundle`, `bootstrap` at
  BOTH fixed points (`mc2.o == mc3.o` 1555048 B, `mc2o.o == mc3o.o`) with the cross-road identity
  (`build/mc2o src/mc.mc == build/mc2.o`) and **both `--dump-asm` diffs between `mc1` and `mc2`
  empty** (plain and `--opt=1`), `check-surface` 32/32 + inert, `check-opt`, `test-exe` 32/32 via
  `--exe`, `check-mc`, `check-standalone`, `check-parts`, **`check-libroot` 7/7**, `check-toml`,
  `check-build`, `check-pkg` 183/183, `check-tool` 27/27, `check-sysroots` (13 rows),
  `check-stubs`, `check-limits` **17/17 seed limits under 90%** (the tightest row is `globals`
  268/512 = 52% on `src/mc_seed.mc`), `check-minimal`, `test-linux` / `test-linux-x86_64` and the
  four `--exe` cells, `test-windows` 56/56 and `test-windows-x86_64` 52/52 objects cross-compiled,
  `check-examples`, `check-lang`, `check-conc`, `check-desktop`, `check-float`, `check-wide`,
  `check-kernel` (`kernel.bin` 3304 B, QEMU 11.0.1), `check-avr` (`avr.elf` 15255 B),
  `test-sandbox` 73 ok / 0 failed / 1 skipped, `check-docs` (206 symbols, 49 flags, 35 TOML keys,
  10 directives, 52 samples, 514 links), `site` 99 pages + `check-site` (0 link problems) +
  `check-site-linux` (99 pages on all four Linux cells, byte for byte the macOS render).
  `make check-linux-host` **RC 0 over all four cells** (aarch64 musl 55/55 and gnu 56/56, x86_64
  musl 51/51 and gnu native), each after its own plain AND optimized fixed point and with the
  cross proof (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`) green.
  `scripts/check-inert.sh <mc1 from main 7c01d06> build/mc1`: **33 objects identical on the plain
  road and 33 on `--opt=1`** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for
  `examples/api`, `lang`, `conc`, `desktop` and `kernel` -- a name the blob answers is answered by
  the blob, before any root is consulted.
  **All ten goldens rewritten once**, each only after its own criterion -- what moved is
  `src/deps.mc`, `src/lex.mc` and therefore the blob: `mc2.sha256`
  `1b56148c...cd5029` -> `61846ac0e463cd68a472aefbc195887eee1646585d30010914f5ece30996b140`,
  `mc2-opt.sha256` `95205eeaf337246ebacbf08821bc39dc46c498c6512c2bd1c1ddafd0e638f144` (both by
  `scripts/bootstrap.sh`, after the two empty `--dump-asm` diffs and the two `cmp`s); the four
  Linux ones deleted and re-recorded by `make check-linux-host` --
  `mc2-linux-arm64.sha256` `631b1a92e093f9fa177a5729893f63a2afb08ab9cf338e94b2f53aad57fe8e79`,
  `mc2-linux-arm64-opt.sha256`
  `a111c5fb465d4fd495b5715e2356bb81ba3865e995b02c51c0ece73274f4deff`,
  `mc2-linux-x86_64.sha256` `979e33490e0397a2f5d44054462da1d5a40f72764b5618d3bcd05f6e477f3332`,
  `mc2-linux-x86_64-opt.sha256`
  `e34a957098f710288898f61263421363f5bf01849d978965b73884eeefcfc7d5`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the four Windows ones
  cross-computed on macOS per `tests/golden/README.md` --
  `mc2-windows-arm64.sha256` `1048679ac7f24c63b53d1d6c5a8e72b35fce9292d8cd01d9a75bdce7bda5cc5c`
  (1589726 B), `mc2-windows-arm64-opt.sha256`
  `ef75c2073c8d5989877ad8c6cc7b9c57766e8a991c0132691fe81884bfdbf06f` (1531314 B),
  `mc2-windows-x86_64.sha256`
  `7441742f103fa5ad88d989e5a8f7995c4154d1a5833288a5acfd7217827ae1ff` (1644678 B),
  `mc2-windows-x86_64-opt.sha256`
  `3a99fc8e7f6297b1209596c2063cf1b5c9c7211b86ff59b1b349509154858fd9` (1573098 B), all four also
  written byte for byte by `build/mc2`.
  Docs: `docs/reference/packages.md` § 2 (the three roots, their order and the partial tree) and
  the new § 2b (the three sentences), `docs/reference/diagnostics.md` (one new row, two corrected),
  `docs/bootstrap.md`, `docs/reference/bundle.md` § The slim flavour (both flavours ship the tree;
  the slim tarball is an offline toolchain for the first time), `docs/ci.md`
  § `scripts/release-assets.sh` (the tarball layout), `docs/specs/M52.md` (§ 11 row 1 LANDED with
  the real line count + nine implementation notes).
  Not in this step: **B**, the cut (`tools/bundle.mc`'s predicate, -140 300 B) and **C**,
  `mc build --sync`.
- M52 step B ✔ (`docs/specs/M52.md` § 2 D1, § 11 row 2 + its new § Implementation notes -- step B):
  **the cut -- 41 of the 101 manifest rows leave the blob for the tree beside the binary.**
  `stage0/` untouched (2848/3000, `git diff main -- stage0/` empty). The rule is the owner's, as one
  predicate in `tools/bundle.mc` (`bl_in_blob`, 8 code lines): **a row is in the blob iff its path
  is under `src/`, plus `prelude` and `user_default`** -- the two files `src/` itself `#include`s,
  which resolve by name inside the blob. `tools/bundle.list` keeps all 101 rows (it is the
  `NAME<TAB>PATH` map the tree is read through) and the root `mc.toml`'s `files` are unchanged: the
  blob shrinks, the package does not. `bl_verify` still runs over all 101 before `bl_cut` compacts
  to 60, so sorted/unique/no-shared-last-component still cover the whole map.
  * **Measured, the cut in isolation** (macOS arm64, the same compiler with the 41 rows in and out;
    `build/mc1 --exe src/mc.mc`):

    | | binary | `__text` | `__cstring` | `__DATA,__data` | blob |
    |---|---|---|---|---|---|
    | all 101 rows | 1 400 552 | 540 924 | 31 111 | 692 576 | 678 368 |
    | 60 rows | **1 268 454** | **540 924** | **31 111** | 567 952 | 556 168 |

    **−132 098 B, −9.4% of the binary and −18.0% of `__DATA,__data`, with `__text` and `__cstring`
    byte-identical** -- a bundle row is data. (§ 1.2 predicted −140 300 against the tree it was
    written on; the shape is exactly what it said.) The branch's final binary is **1 285 334 B**
    (`__text` 542 272, +1 348 for the nine new functions below; `__DATA,__data` 570 352, blob
    558 552), and `make bundle` reports 60 files, raw 1 231 666 -> LZ 557 778.
  * **Two roads a library name could not reach any more, and both are fixed at the root** -- the
    deviation from the step table's "~0 lines in `src/`", **52 code lines** in five files, no new
    global (`mc limits src/mc.mc` says `globals 446/512` before and after).
    (a) `mc build` with a `[compiler]` writes a taught compiler into the project's own `build/` and
    spawns it there, where roots 2 and 3 -- both relative to `host_self_path()` -- are invisible.
    Measured before the fix: `mc build examples/desktop --config ui.toml` answered
    `main.ui:16: #include <sys>: not in this compiler and mc 0.0.0-dev's library tree was not
    found: run mc install`, with the tree beside `build/mc1` all along -- a regression for every
    user with a `[compiler]` and a library include. `deps_libs_for_child()` (`src/deps.mc`, +18
    code) answers the `<libs>` a child must be told about (0 when `--libs-dir` was given, already
    forwarded; 0 when root 1 answered, since the child inherits `HOME`; else the tree beside THIS
    binary) and `drv_teach` passes it as `--libs-dir` (+4). `dp_mc_root` became
    `dp_beside_libs` + `dp_root_in`, so "beside the binary" has one definition.
    The **two-step** road (`--compiler-only`, then that compiler with `--entry-only`) forwards
    nothing by construction and the caller names `--libs-dir` itself -- `scripts/check-opt.sh`,
    `scripts/check-inert.sh`, and `docs/build.md` § M52 for a user's own script.
    (b) **The sandbox**: `make test-sandbox` came back **51 ok, 22 failed**, every case whose
    program says `#include <sys>` (`refused: syscall 78 (readlinkat)` -- the compiler asking where
    its own binary is). Inside the box neither beside-the-binary root can work (`/mc` is a single
    bound FILE and there is no `/proc`), so the box mounts the tree where `<libs>` looks: `HOME` is
    `/src`, hence **`/src/.mc/libs/mc/v<ver>/`**, bound read-only on the overlay's upper layer and
    granted read-only by Landlock (a mount of its own, so the `/src` rule does not reach it), with
    the host path resolved before the unshare in `dp_mc_root`'s order and without naming one of its
    functions -- `src/sandbox.mc` is `<mc/core_sandbox>`, which `check-parts` builds on
    `<mc/core_min>` alone. +30 code lines, one APPENDED field (`SB_LIB`, so no offset moved). On
    the overlay fallback road `/src` is read-only and there is nowhere for the mount point: the
    field is cleared and a library name gets the sentence that names `mc install`, which is the
    truth about that box. After it: **73 ok, 0 failed, 1 skipped**.
    `readlinkat` joined the four compile profiles, **measured with
    `sh scripts/sandbox-trace.sh --union`** on Ubuntu 26.04 (aarch64, glibc 2.43, Lima) and Alpine
    3 (aarch64, musl) -- the trace runs OUTSIDE the box, where the compiler does take that road --
    and `--check` is green there. The two x86-64 rows carry the same name, unmeasurable from this
    Mac (`strace` decodes nothing under its amd64 emulation); one residual on record in
    `docs/reference/sandbox.md` § The profiles: musl on x86-64 implements `readlink()` with the
    `readlink` syscall, which no `SN_*` covers, so on such a host a box with **no** tree says
    `refused: syscall 89 (readlink)` instead of the sentence -- one `--union` run there fixes it.
  * **The gates.** `scripts/libroot.sh` stages every non-`src/` row (43 files: the 41 plus the two
    exceptions, which ride along for free because the blob answers them first) and gained a
    `--libs DIR` mode that lays the same tree at `DIR/mc/v<ver>/` -- root 1's shape, what
    `mc install --libs-dir` writes. `check-bundle` **+1 case**: the 60 names the generator reports
    `diff`ed against the predicate restated over the manifest in `awk`, then each of the other 41
    offered to the real compiler (root 2 beside it) with neither refusal allowed to appear, then
    the same compiler alone in an empty directory refusing `<sys>` -- § 10.7's literal form, which
    step A could only prove with a synthetic row. `check-pkg` **186/186**: every fixture `<libs>`
    is laid whole (`--libs-dir` REPLACES `<libs>`, and `tests/pkg/app`/`app-float` both say
    `#include <sys>`), § 15's bundle-less probe moved to a `$tmp/none` that really is empty,
    § 18's "nothing was fetched" now says "nothing but the `mc` tree", and the new § 37 is the D6
    table on a real name (roots 2 and 3 each compile, link and RUN a `<sys>` program; with neither,
    the refusal is exact). `check-standalone` stages the tree beside the copied binary -- cases 1-3
    through root 2, case 4 (`<mc/host>` + `<mc/core>` + `<user_default>` == `src/mc.mc`, byte for
    byte) untouched, and case 5 moved to `alone/bin/mc`, two levels down so that neither root can
    see the tree. **`check-docs` needed no line**, against the step table's guess: its fences are
    compiled by `build/mc1` (root 2 beside it) and its `taught=DIR` fences go through `mc build`,
    which forwards it.
  -- `make bundle` re-run BEFORE bootstrapping (60 files, blob 558 552 B). `make check` green end
  to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test` 32/32, `check-lex` 177/177 (5 skipped),
  `check-ast`/`check-asm` 178/178, `check-obj` **32/32 identical to the frozen seed**,
  `check-bundle` (60/41 + the refusal, lz round trip 125 cases), `bootstrap` at BOTH fixed points
  (`mc2.o == mc3.o`, `mc2o.o == mc3o.o`) with the cross-road identity and **both `--dump-asm` diffs
  between `mc1` and `mc2` empty**, `check-surface` 32/32 + 154 ok, `check-opt` 75/75, `test-exe`
  32/32, `check-mc` 22/22, `check-standalone`, `check-parts`, `check-libroot` 7/7, `check-toml`
  10/10, `check-build` 55/55, **`check-pkg` 186/186**, `check-tool` 27/27, `check-sysroots`
  (13 rows), `check-stubs` 9/9, `check-limits` 17/17 seed limits under 90%, `check-minimal`,
  `test-linux` 55/55 and `test-linux-x86_64` 51/51, the four `--exe` cells 58/58 + 58/58 + 54/54 +
  54/54, `test-windows` 56/56 and `test-windows-x86_64` 52/52 objects cross-compiled +
  `test-windows-x86_64-exe` 24/24, `check-examples`, `check-lang` 18, `check-conc` 21,
  `check-desktop`, `check-float` (five legs + the four sweeps), `check-wide`, `check-kernel`
  (QEMU 11.0.1), `check-avr`, **`test-sandbox` 73 ok / 0 failed / 1 skipped**, `check-docs`
  (206 symbols, 49 flags, 35 TOML keys, 10 directives, 52 samples, 514 links), `site` 99 pages +
  `check-site` + `check-site-linux` 21/21.
  `scripts/check-inert.sh <mc1 from main 5c8bc3d> build/mc1`: **33 objects identical on the plain
  road and 33 with `--opt=1`** (`tests/*.mc` AND `src/mc.mc` -- the script compiles one tree with
  both compilers, so this is the strongest form) plus byte-identical artefacts for `examples/api`,
  `lang`, `conc`, `desktop` and `kernel`. The compiler's own body is confined as well: compiling
  main's `src/mc.mc` and this tree's with the same compiler gives **9 added function labels, 0
  removed, and 12 of 1935 shared functions differing** -- the six that were edited (`dp_mc_root`,
  `drv_teach`, `sb_go`, `sb_build_tree`, `sb_landlock_apply`, `sb_rec`) and the six `bundle_*`
  readers, whose immediates are the blob's own count going from 101 to 60.
  **One more thing a foreign host needed**, found by `make check-linux-host` and true of every CI
  Linux and Windows leg: those hosts start from a `build/` that holds the compiler and nothing else
  (`scripts/check-linux-host.sh` untars the checkout EXCLUDING `build/`; a CI leg links the object
  it was handed), so the tree has to be laid there before the suite runs. `libroot` is now the
  first prerequisite of the Linux and Windows `check` subsets in the `Makefile`, and
  `scripts/bootstrap-linux.sh` and `scripts/bootstrap-windows.sh` lay it themselves right before
  they run the suite -- the chain above it needs nothing of it, since `src/mc_linux.mc` and
  `src/mc_windows.mc` have relative includes only. Measured before the fix: 12 FAILs per cell, all
  of them `tests/mc/09[7-9]`/`10[01]` (the M49 tests, the only ones in that corpus that say
  `#include <sys>`).
  `make check-linux-host` **RC 0 over all four cells** (aarch64 musl 55/55 + `check-mc` 18/18 +
  `test-exe` 31/31, aarch64 gnu 56/56 native, x86_64 musl 51/51 + 17/17 + 29/29, x86_64 gnu 52/52
  native), each after its own plain AND optimized fixed point, its own cross-road identity, and the
  cross proof (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`) green in all
  four.
  **Three more things only CI could see**, all three the cut exposing something step A could not:
  (1) **roots 2 and 3 never worked on a Windows host** -- `host_self_path()` is
  `GetModuleFileNameA`, which answers `D:\a\mc\mc\build\mc.exe`, and every path function here
  cuts on `/` alone, so step A's own no-slash guard refused it; while the blob carried every name
  nothing asked, and with the cut both Windows legs answered `not in this compiler and mc
  0.0.0-dev's library tree was not found` for all 41 names. `src/host_windows.mc` hands back one
  spelling now (forward slashes, which Win32 takes everywhere), which `mc upgrade` and `mc tool`
  get as well. (2) `check-bundle` names the FILE target `build/mc1` while `$(LIBROOT)` hung off the
  PHONY `mc1`, so a clean `build/` never got the tree -- it is an order-only prerequisite of
  `build/mc1` now. (3) the two sandbox CI jobs download the compilers into `build/` and run neither
  `make check` nor a bootstrap script, so `scripts/ci-sandbox-cell.sh` lays the tree before the
  cell. (4) **`readlink` is not `readlinkat`**: the `linux/x86_64` sandbox cell measured
  `readlink` (89) in the compile trace -- AArch64 has no such syscall and both its C libraries
  issue `readlinkat`, while on x86-64 the number exists and glibc 2.39 uses it -- so
  `sh scripts/sandbox-trace.sh --check` there failed with `src/sysno.mc has no index for:
  SN_READLINK`. `SN_READLINK` is index 95 now (`SN_COUNT` 96), 89 on x86-64 and `SN_ABSENT` on
  AArch64, and both x86-64 compile lists carry the row beside `readlinkat`. The residual the first
  draft recorded is gone: a box with no tree reports the sentence that names `mc install` on every
  cell.
  **The ten goldens rewritten once**, each only after its own criterion -- `mc2.sha256`
  `61846ac0...96b140` -> `f194d0f02f7cf4f9385aee2810241623cccb881510187a38ea3b4ae4120d5fac` and
  `mc2-opt.sha256` `6a1dc5dddd5b7f4379a6b3f873618f0ab2f374c10e6f328abd4778f96de5344b` (both by
  `scripts/bootstrap.sh`, after the two empty `--dump-asm` diffs and the two `cmp`s); the four Linux
  ones deleted and re-recorded by `make check-linux-host` --
  `mc2-linux-arm64.sha256` `39371bf1e56b9b01b0eb95cb24fd1994994a8ef10d6f46ef0a33e1eaa1ce0a08`,
  `mc2-linux-arm64-opt.sha256`
  `260d4bdd5d9228dc8f0647e311ea3a7c8df2f5b4fabcf5e95fd2774e03c11ab6`,
  `mc2-linux-x86_64.sha256` `e880b243bb3368d4bf4ce39f82ee836ade021944a98aa9998d2062207bc180ce`,
  `mc2-linux-x86_64-opt.sha256`
  `747aa9b986de6dcaf03b91c0fb099ee81f7041768b3ee95c2ace9a86c217862b`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the four Windows ones
  cross-computed on macOS per `tests/golden/README.md` --
  `mc2-windows-arm64.sha256` `795af0d3342969f93f01ec48b490ab045c4312a626c0c53d9c9b606e58276ac5`, `mc2-windows-arm64-opt.sha256`
  `d1b38f2b67726edf1a2e906197bd090d2da23d8dd46683b1a9028e0aa2a3bf39`,
  `mc2-windows-x86_64.sha256`
  `02254508b3db269d21ca1863a7d61df3c7f1c5486a7ac465fb6f9561a0872b83`,
  `mc2-windows-x86_64-opt.sha256`
  `4e3346cd1befb8acd2f86651ad49a0e468286cdaf1e9f74607283dd9f665d702`.
  Docs: `docs/reference/bundle.md` (the catalogue split in two with the measured table, and what
  the headline claim is now), `docs/reference/packages.md` § 2 (step 3 is every library name; a new
  § on a compiler that cannot see the tree beside `mc`), `docs/build.md` § M52 (new),
  `docs/reference/sandbox.md` (§ The tree, § The profiles), `docs/bootstrap.md`;
  `docs/reference/diagnostics.md` needed no change -- step A had already written all three
  sentences.
- M52 step C ✔, and **M52 is CLOSED** (`docs/specs/M52.md` § 5 D7, § 10.8, § 11 row 3 + its new
  § Implementation notes -- step C): **`mc build --sync`, the one road from a build to the
  network.** `stage0/` untouched (2848/3000, `git diff origin/main -- stage0/` empty); zero new
  globals.
  * **The flag is `pkg_sync` and nothing else.** `mc build [DIR] --sync [--yes]` runs the SAME
    function `mc pkg sync` runs -- same plan, same install table, same `[[permission]]` consent,
    same `--yes`, same refusals -- and then builds. It runs at the top of `drv_run`, before
    anything reads `mc.lock` (`deps_apply`, inside `drv_parse`), and re-parses the config for
    itself: `toml_parse` resets the table, so the two reads of the same file cannot see each other.
    Without the flag `mc build` is byte for byte the command it was, and `check-pkg`'s
    `curl`/`wget`/`tar` shim (exit 97 if invoked) keeps proving it.
  * **The driver may not NAME `pkg_sync`.** `src/driver.mc` is `<mc/core_build>` and `src/pkg.mc`
    is `<mc/core_pkg>`; `check-parts` § 1b requires each part to stand on `<mc/core_min>` alone,
    and `docs/reference/packages.md` § 9's claim -- "a compiler assembled without `<mc/core_pkg>`
    cannot download even in principle" -- is a property of the code. So the sync step arrives as a
    **pointer**, `drv_set_sync(&pkg_sync_for_build)` from `mc_pkg_init()`, the shape
    `lex_set_bundle`/`lex_set_libs` already have, stored in the driver's own record (`DRV_SYNCFN`).
    Measured: a compiler assembled from `<mc/core_min>` + `<mc/core_machines>` +
    `<mc/core_writers>` + `<mc/core_build>` has `_drv_build` and **no `_pkg_sync`** in
    `--dump-syms`, and `mc build DIR --sync` on it is `mc: --sync needs the package half of this
    compiler: mc pkg is not in it`, exit 1.
  * **One bit `pkg_sync` could not answer.** It returns 0 both when the lock is written and when
    it printed a plan it did not run -- for `mc pkg sync` those are one outcome, for a build they
    are not. `pkg_sync_for_build(dir, cfg, yes)` is `pkg_open_config` + `pk_set_yes` + **that same
    `pkg_sync`**, then one line: `if (!pk_yes() && (pk_nplan() > 0 || pkg_perm_ask())) return -1;`
    -- `-1` is "stop, exit 0". The permission half is not decoration: a build that walked past an
    unaccepted `[[permission]]` set would be a second road around the consent.
  * **The four cases, measured.** (a) plain `mc build` on an unsynced project still refuses --
    `mc: mc.lock is stale`, exit 2, with its `run:` line, nothing spawned. (b) `--sync` alone:
    two `fetch` rows, `nothing was downloaded: re-run with --yes`, **exit 0, no lock written and
    nothing built**. (c) `--sync --yes`: fetched, `mc.lock` byte for byte `mc.lock.expect`, built,
    and the program runs (exit 42, `plot 110`) -- one command from checkout to binary. (d) with a
    `[compiler]` section (`tests/pkg/sync/teach.toml`, new): **one `lock` line and two `fetch`
    rows, not two and four** -- `drv_teach` writes the child's argv name by name, so `--sync`
    cannot travel to the `--entry-only` child, and the gate measures the consequence rather than
    the code. Plus (e): after (c), a plain `mc build` under the FULL shim (a `tar` that exits 97 as
    well as the two downloaders) still builds.
  * **A no-op sync stays a sync**: with no `[deps]` and no `[tools]` it is `sync: no
    dependencies`, an empty lock, and the build -- what `pkg_sync` does there, kept.
  * **`--yes` on its own is refused**, not ignored (`mc: --yes applies to --sync: mc build
    downloads nothing without it`) -- the post-M42 rule for a flag read by nobody. Both flags live
    in ONE record field (`DRV_SYNC`, 0/1/2), so `drv_run` needed no new parameter and its three
    callers were not touched.
  * **The `run:` line did not change**, against the step table's "the `run:` line it makes
    unnecessary" read as a licence to rewrite it: the refusal is raised by `src/deps.mc`, which is
    `<mc/core_build>` and has no business naming a flag that needs the other part, and
    `mc pkg sync --yes` is right on every road. What `--sync` makes unnecessary is the second
    COMMAND. `check-mc` and `check-pkg` assert that text and neither moved.
  * **`mc build` has no `--registry`** and does not get one: a build whose answer depended on a
    registry named in the shell line would be a build two people cannot reproduce from the same
    checkout -- the same argument § 5 used to refuse implicit resolution. The registry is
    `[registry].url` or the default; `check-pkg` § 38 names its fixture registry by `sed`-ing that
    table into a copy of the project's config, which is what a private tap looks like.
  * **A part-less compiler still ADVERTISES the flag** (the usage line is
    `subcommand("build", ...)`'s, `<mc/core_build>`'s): a subcommand disappears with its part
    (M43 § 4b), a flag inside one cannot. The refusal is what tells the truth, and it names the
    missing half. Re-registering `build` from `mc_pkg_init()` with a longer string was the
    alternative and puts the same text in two files.
  -- cost: **79 added lines in `src/`, 30 of them neither comment nor blank**
  (`src/driver.mc` +48/-1, `src/pkg.mc` +25, `src/core_pkg.mc` +5, `src/core_build.mc` +1/-1),
  against the spec's ~20. New fixtures `tests/pkg/sync/teach.toml` and `tests/pkg/sync/user.mc`;
  `scripts/check-pkg.sh` § 38 (**186/186 -> 191/191**) and `scripts/check-parts.sh` § 4c (the part
  boundary, three assertions). `make bundle` re-run BEFORE bootstrapping (60 files, raw 1238096 ->
  lz 560911, blob 561685 B).
  `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test` 32/32,
  `check-lex` 177/177 (5 skipped), `check-ast`/`check-asm` 178/178, `check-obj` **32/32 identical
  to the frozen seed**, `check-bundle`, `bootstrap` at BOTH fixed points -- `mc2.o == mc3.o` (1439768 B, the
  `--dump-asm` diff between `mc1` and `mc2` **empty**) and `mc2o.o == mc3o.o` (1381736 B, the
  `--dump-asm --opt=1` diff empty) -- `check-surface` 32/32, `check-opt` 75/75, `test-exe` 32/32,
  `check-mc`, `check-standalone`, `check-parts`, `check-toml`, `check-build` 55/55, **`check-pkg`
  191/191**, `check-libroot` 7/7, `check-tool` 27/27, `check-stubs`, `check-sysroots`,
  `check-limits` 17/17 under 90%,
  `test-linux`/`test-linux-x86_64` and the four `--exe` cells, `test-windows`/
  `test-windows-x86_64`, `check-examples`, `check-lang`, `check-conc`, `check-desktop`,
  `check-float`, `check-wide`, `check-kernel`, `check-avr`, `test-sandbox` 73 ok / 0 failed /
  1 skipped, `check-docs` (206 symbols, 50 flags, 35 TOML keys, 10 directives, 52 samples,
  525 links), `site` 99 pages + `check-site` (0 link problems) + `check-site-linux`.
  `make check-linux-host` **RC 0 over all four cells** (aarch64 and x86_64 x musl and gnu), each
  after its own `mc2l.o == mc3l.o` and `mc2lo.o == mc3lo.o`, the cross-road identity
  (`mc2lo-plain.o == mc2l.o`) and the cross proof (`mc2l --backend=macho src/mc.mc` byte for byte
  the macOS `build/mc2.o`).
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main`
  345b2b4): **33 objects identical on the plain road and 33 with `--opt=1`** (`tests/*.mc` and
  `src/mc.mc`) plus byte-identical artefacts for `examples/api`, `lang`, `conc`, `desktop` and
  `kernel` -- a flag nobody writes emits nothing.
  **Ten goldens rewritten once**, each only after its own criterion: `mc2.sha256`
  `a983077bbeba100e788b8639e2ff33cab3d96b26caa65070649bd8f32e6989e2` and `mc2-opt.sha256`
  `dbae8f11eb867d98ab82ab5bf44f28a7f549364fe8d4cb41e929fc9331420604` (after the two empty
  `--dump-asm` diffs and the two `cmp`s); the four Linux ones deleted and re-recorded by
  `make check-linux-host` -- `mc2-linux-arm64`
  `a560cbe66292858e79df4a0d4de6c5c1715c151d42a04c08347622a9baab48e5`, `mc2-linux-arm64-opt`
  `6e509ec41ca8b3cfe5b872a2f31b84820f4e02b7c2ff59ff66554933d6894623`, `mc2-linux-x86_64`
  `78d77eb56ef6f280e4eebba5c30d74aff0140a9e94c20884c4d8a63a35ad7d8e`, `mc2-linux-x86_64-opt`
  `88f256bee38d84c3281669cba1eb8e17bc56a669829b1cae3152ca0319fead26`; the four Windows ones
  cross-computed per `tests/golden/README.md` -- `mc2-windows-arm64`
  `4b9874f0feae7871327d3a2ac11338d4c65ebd2b1cb193a5b97b78f29083e3b4` (1474759 B),
  `mc2-windows-x86_64` `0f22974824ea801d3534d8d19fb6bdb542ebe05e2e49b8f2b87278572f208f9a`
  (1530211 B), `mc2-windows-arm64-opt`
  `bc02ae2b5abc1240755f61625a1ed69d1db0ba30232ea9807cdfcf25974f9dfa` (1416147 B),
  `mc2-windows-x86_64-opt` `6f41c01d20044cdcd0b231352832c50a92bdf2fe1d3eddb331007351abb08468`
  (1458291 B).
  **M52 closed**, three gated steps: **A** the library root beside the binary and the refusal that
  names `mc install` (86 added, 37 code), **B** the cut -- **101 blob rows -> 60**, 41 to the tree,
  **the binary −132 098 B, −9.4%, `__DATA,__data` −18.0%, `__text` and `__cstring` byte-identical**
  (52 code lines) -- and **C** this. The three roots are `<libs>` (`--libs-dir` or
  `$HOME/.mc/libs`), then `lib/mc/v<ver>/` beside the executable, then one directory up for a
  packager who puts `mc` in `bin/`. No `#include` spelling changed anywhere, and no library was
  published as a package of its own (§ 9.2, deferred).
  Docs: `docs/reference/cli.md` § 2 (`--sync`, `--yes`, and the sync's own output above the build's),
  `docs/reference/packages.md` § 9 (the one exception to "it never downloads") and § 10 (a new
  § "The same sync, from a build"), `docs/reference/diagnostics.md` (two rows),
  `docs/build.md` § M14/M44, `docs/guide/25-packages.md` § 6, `docs/specs/M52.md` (§ 11 row 3
  LANDED + § Implementation notes -- step C, nine notes) and `docs/plan.md`'s M52 row marked done
  with the measured numbers.
- M52 step D done (`docs/specs/M52.md` § 7 D12 + § Implementation notes -- step D): **`mc build`
  stages the library tree beside the taught compiler it writes**, so a `[compiler]` product is as
  self-sufficient as an unpacked release tarball. `stage0/` untouched (2848/3000). The gap was the
  consumer's (teko's) dry run against `main` 62f0cdd/21d081b and it is real: a `[compiler]` product
  is a SECOND binary in the project's own `build/`, so roots 2 and 3 -- the tree a release carries
  beside `mc`, and the one `make` lays beside `build/mc1` -- are relative to IT and invisible.
  Spawned by `mc build` it works (the parent hands its root over, `deps_libs_for_child`); run
  STANDALONE it did not -- `build/teko --entry-only ...`, teko's own `bootstrap.sh` and
  `check-docs.sh`, **3 of 64 fixtures**, `lib/rt.tk:40: unknown bundled include: sys`; with
  `--libs-dir` or a copied tree, 64/64 and FIXPOINT OK.
  **Reproduced here in both shapes before a line was written**, with `build/mc1` of 21d081b and an
  empty `$HOME`: `examples/avr`'s product (`core = "<mc/core_min>"`, no blob) answers
  `#include <sys>: not bundled in this compiler and mc 0.0.0-dev is not installed: run mc install`
  and `examples/lang`'s (the default `<mc/core>`, with a blob) answers
  `#include <sys>: not in this compiler and mc 0.0.0-dev's library tree was not found: run mc
  install`, both exit 1. (`make check-lang` is green today for a different reason than adjacency,
  and that was checked: `examples/lang`'s `.lx` sources name **no** bundled library at all.)
  Decision **(a)**, the owner's: `mc build` stages `<dir of [compiler].out>/lib/mc/v<version>/`
  from the root the RUNNING `mc` resolved for itself, by the same partial-tree rule
  `scripts/libroot.sh` lays the release tarball with -- `bundle.list` plus every row whose path is
  not under `src/`, only the files that are there. **44 files**, the same count and bytes
  `sh scripts/libroot.sh` writes. Rejected: **(b)** baking the builder's absolute root into the
  binary (a path in the object, against `docs/determinism.md`) and **(c)** `--libs-dir` on every
  invocation (it pushes the contract onto every consumer's scripts and breaks a user who is handed
  `build/teko`). **No flag** -- it is the contract.
  Staging from the BLOB was weighed and refused twice over: `src/driver.mc` is `<mc/core_build>`
  and `bundle_read` is `<mc/core_bundle>` (step C note 1's split -- it would need a fourth function
  pointer), and after step B the blob keeps `src/*` plus `prelude`/`user_default`, so a binary with
  no root has no library to stage anyway. Source is therefore the resolved root, and a running `mc`
  that found none stages nothing and the product inherits the same refusal.
  **`deps_libs_for_child` is kept**: with the staging in place the spawned child would find its own
  root 2, but the parent's `--libs-dir` still WINS (root 1 beats root 2) and it is what keeps the
  child compiling against the same bytes the parent did. It is also why the staging changes no
  artefact -- on the `mc build` road the staged tree is never read.
  **One function, and the frozen seed is why.** The first draft was five (three readers in
  `src/deps.mc` plus a `drv_stage_file` helper) and it turned `make check` red where nothing else
  in this change goes: `scripts/check-asm.sh` compiles `lib/mc_i128.mc` and `lib/mc_u128.mc` with
  `build/mc0`, and those are `#include "../src/core.mc"` plus a module -- **2044 of the seed's
  `MAXFUNCS` 2048 on `main`**, so five more is 2049 and `build/mc0` answers `mc: too many
  functions`, `176/178 files identical`. `stage0/` is frozen, so the budget gave: it is now
  `void drv_stage_libroot(uptr cbin)` alone, reading `src/deps.mc`'s already-parsed map through
  that file's own `#define`s -- **2045, three of headroom**. Worth knowing for the next `src/`
  milestone: that ceiling, not `check-limits`' rows (which measure `src/mc_seed.mc`), is the tight
  one.
  Cost: **67 added lines in `src/`, 34 of them neither comment nor blank**, all in
  `src/driver.mc`, one new function, **zero new globals** (`check-limits` reports the same
  `globals 268/512, 52%` row).
  Gate: `scripts/check-libroot.sh` case (g), where the other roots are proved -- the consumer's
  shape reduced to what runs in seconds (`core = "<mc/core_min>"`, a module that is
  `examples/avr/mc-avr.mc` minus the AVR: `<mc/core_machines>`, `<mc/core_writers>`,
  `<mc/core_build>`, a `main()` and an empty `user_init()`; **no `<mc/core_bundle>`**, so the
  product has no blob and a successful `#include <sys>` is road 3 through the staged tree and
  nothing else). Three assertions: the tree is beside it (44 files), the product run standalone
  compiles and RUNS the program (exit 42) with an empty `$HOME` and no `--libs-dir`, and a second
  build rewrites **0 of 44** files (`find -newer` against a marker, not a timestamp compare).
  `<mc/core_build>` is in that module list for a measured reason: without it `mc_build_init()`
  never runs, `lex_set_libs` is never called and the product has no road 3 at all -- the first
  draft of the fixture left it out and answered `unknown bundled include: sys` with the tree
  sitting beside it. **Measured teeth**: against `build/mc1` of 21d081b the script is **7/10 with
  three failures** (the staged tree, the standalone product, and the idempotence case, which
  refuses to pass vacuously when nothing was staged), exit 1; with this branch **10/10**.
  -- `make bundle` re-run BEFORE bootstrapping (60 files, raw 1241573 -> LZ 562533, blob
  563307 B). `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test`
  32/32, `check-lex`/`check-ast`/`check-asm` 178/178 (4 skipped), `check-obj` **32/32 identical to
  the frozen seed**, `check-bundle`, `bootstrap` at BOTH fixed points (`mc2.o == mc3.o`
  1442552 B, `mc2o.o == mc3o.o` 1384440 B; both `--dump-asm` diffs between `mc1` and `mc2`
  **empty**), `check-surface` 32/32, `check-opt`, `test-exe` 32/32, `check-mc`,
  `check-standalone`, `check-parts`, **`check-libroot` 10/10**, `check-toml`, `check-build`,
  `check-pkg`, `check-tool`, `check-sysroots`, `check-stubs`, `check-limits` **17/17 under 90%**,
  `check-minimal`, `test-linux`/`test-linux-x86_64` and the four `--exe` cells, `test-windows`/
  `test-windows-x86_64`, `check-examples`, `check-lang`, `check-conc`, `check-desktop`,
  `check-float`, `check-wide`, `check-kernel`, `check-avr`, `test-sandbox` 73 ok / 0 failed /
  1 skipped, `check-docs`, `site` 99 pages + `check-site` + `check-site-linux` 21/21.
  `scripts/check-inert.sh build/mc1.pre build/mc1` (pre = a `mc1` built from `origin/main`
  21d081b): **33 objects identical on the plain road, 33 with `--opt=1`**, plus byte-identical
  artefacts for `examples/api`, `lang`, `conc`, `desktop` and `kernel` -- the staging writes files
  BESIDE the product and never into it.
  **The ten goldens rewritten once**, each only after its own criterion: `mc2.sha256`
  `a983077b...6989e2` -> `8543f340c80f0d5bbae638ad2588940ad2149e5ce9146828a8ba6bb9e95a8ab3` and
  `mc2-opt.sha256` -> `54f862f1a35b6b94f992d733086c82a502534f05dc5c73872baaeacc2cfca007`, both
  after the two empty `--dump-asm` diffs and `cmp build/mc2.o build/mc3.o` /
  `cmp build/mc2o.o build/mc3o.o`; the four Linux ones deleted and re-recorded by
  `make check-linux-host` (Docker, both architectures, both libcs, each after its own
  `mc2l.o == mc3l.o` and with the cross proof green) -- `mc2-linux-arm64`
  `e3191996c7b9637688216bdf003dd6fc1d59d3c77087ff4c142c9650077801ef`, `mc2-linux-arm64-opt`
  `681ff98412e578a367164e3e59e9b6738bf1c9300a0776466743d1c8bf13e5f1`, `mc2-linux-x86_64`
  `eeb8f0e5b563f66f0e0aeb86f68ed0bd50169987616f65157488b1bad676cf58`, `mc2-linux-x86_64-opt`
  `41a4b32c7ea86fdf9f956a018ba652f068ad2b7af497497051f27f1802359679`; and the four Windows ones
  cross-computed per `tests/golden/README.md` -- `mc2-windows-arm64`
  `43aef1cf92554f1e27679dfea7fa506e0229db682957f675422f6b3b1720ec98` (1477619 B),
  `mc2-windows-arm64-opt` `d03e9be08b6aadeffc3aebd2548cebb1384a8b97f4085f7279814eb46de0ff13`
  (1418915 B), `mc2-windows-x86_64`
  `25a3852fe4350763b657ac18a6f81466d8d5bfa783edb155c207ef8ac4f878a0` (1533299 B),
  `mc2-windows-x86_64-opt` `9d830c2656cbc7e2988df16fa96f2acc942535dbc091f7a88aa106ab8a08c6d1`
  (1461251 B); `build/mc2` writes the two plain Windows objects byte for byte as `build/mc1` does.
  Docs: `docs/build.md` § `[compiler]` (a new "The product is self-sufficient" subsection),
  `docs/reference/toml.md` (`compiler.out`'s row and a paragraph), `docs/reference/packages.md`
  § 2 (root 2 is now also `mc build` beside a taught compiler; the `--libs-dir` workaround
  paragraph rewritten), `docs/specs/M52.md` (§ 7 D12 with the three weighed shapes, and
  § Implementation notes -- step D, ten notes).
- M52 step E done (`docs/specs/M52.md` § 11 row 4 + its § Implementation notes -- step E): **the
  spawned taught compiler resolves its own roots, and `host_self_path()` resolves a symlink.** Two
  defects the consumer's (teko's) dry run against `main` d18930d found, both reproduced here before
  a line was written. `stage0/` untouched (2848/3000, `git diff d18930d -- stage0/` empty).
  1. **`deps_libs_for_child` turned the `mc` tree into the WHOLE package root in the child.** Step B
     added it for the road step D had not built yet: with no `--libs-dir` and nothing under
     `$HOME/.mc/libs`, `drv_teach` handed the spawned compiler `--libs-dir <dir of mc>/lib`. But
     `<libs>` names two things -- the `mc` library tree under `<libs>/mc/v<ver>/` AND the installed
     packages under `<libs>/<pack>/v<ver>/`, which is what `dep_resolve` reads -- so a `[compiler]`
     project whose ENTRY has `[deps]` died in the child. Reproduced on `tests/pkg/app` (a
     `[compiler]` and three `[deps]`), packages installed under a scratch `HOME`, no `--libs-dir`:
     `compiler build/mc-app.mc -> build/mc-app`, `compile main.mc -> build/app`, then **`mc: geo
     1.2.0 is not fetched`, exit 1** -- the consumer's own `teko 0.11.0 is not fetched` with another
     name. After the fix the same command is exit 0 and the program runs (`geo 120`, exit 42).
     **Fixed at the root**: the parent forwards `--libs-dir` only when it was GIVEN one
     (`dp_libs_opt`), never a derived one, and `deps_libs_for_child` is DELETED -- since step D the
     child has a root 2 of its own and needs no derived answer. **The order was checked and not
     assumed**: `drv_stage_libroot(drv_path(cbin))` is called in `drv_teach` before `drv_finish` and
     before the `drv_spawn`, so the tree is beside the child when the child runs -- confirmed from
     the other side too, since the failing repro had already staged
     `tests/pkg/app/build/lib/mc/v0.0.0-dev/`. No case remains where the child would need a tree the
     parent could not stage: `drv_stage_libroot` stages from the root the running `mc` resolved by
     roots 1/2/3, and if it found none there is no library for either of them.
  2. **`host_self_path()` answered the symlink's path on macOS.** `~/bin/mc -> …/build/mc1` is how a
     developer puts one compiler on `PATH`, and `_NSGetExecutablePath` answers the path as invoked,
     so roots 2 and 3 were computed from `~/bin/` and the tree beside the real binary was invisible:
     `#include <sys>: not in this compiler and mc 0.0.0-dev's library tree was not found: run mc
     install`, exit 1, measured; after the fix, exit 0. `src/host_macos.mc` passes the answer through
     `realpath(3)` (libSystem, the buffer `xalloc`ed, so no global) and keeps the raw path when that
     fails. **The other two hosts need nothing and that was read rather than assumed**:
     `readlink("/proc/self/exe")` returns the target the kernel resolved and `GetModuleFileNameA`
     answers the module's own path. `docs/reference/hooks.md` § 6 claimed the opposite in prose
     ("the answer is not resolved any further") and is corrected with the code. One observable
     consequence, and it is the fix working: `mc upgrade` with no `--to` prints the RESOLVED path on
     its `into` line, so it replaces the compiler and not the link -- `check-pkg` § 33i asserted that
     line with `$tmp` spelled out and `$TMPDIR` on macOS is `/var/folders/…`, a symlink to
     `/private/var`, so the case now asserts the suffix and prints the whole line
     (`into   /private/var/folders/…/u/self/mc`).
  -- cost: **44 added / 35 removed lines in `src/`, code +4 / -7 -- net 3 code lines REMOVED**
  (`deps.mc` +14/-21, `driver.mc` +12/-10, `host_macos.mc` +18/-4). **Zero new globals**
  (`build/mc1 limits src/mc.mc` says `globals 446/512` before and after) and the seed's `MAXFUNCS`
  headroom is unchanged: `lib/mc_i128.mc` is **2045 of 2048** on d18930d and on this branch
  (`lowered` 2026 -> 2025, one function gone; `funcs` level, the `extern realpath` taking its slot),
  so no `seed-skip` was needed and `check-asm` stays 178/178.
  New gates: `scripts/check-pkg.sh` § 39 (**194/194**) -- `mc pkg sync --yes` with NO `--libs-dir`
  and a scratch `HOME` writes `$HOME/.mc/libs`, then `mc build` on the `[compiler]` config with no
  flag at all builds and the program runs (exit 42, `plot 110`), which proves both halves at once
  since that entry also says `#include <sys>` and therefore needs the staged tree; then the same
  config with an explicit `--libs-dir` still builds and runs, so the forwarded flag still wins.
  `scripts/check-libroot.sh` case (h) (**11/11**): a symlink in a directory with no `lib/` of its own
  compiles `#include <sys>` -- a REAL name, because `m52probe` exists only in the trees that script
  lays and would say nothing about the tree beside `build/mc1`.
  `make bundle` re-run BEFORE bootstrapping (60 files, raw 1242281 -> LZ 563098, blob 563872 B).
  `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test` 32/32,
  `check-lex` 177/177 (5 skipped), `check-ast`/`check-asm` 178/178, `check-obj` **32/32 identical to
  the frozen seed** (and 32/32 `arm64-surface` against `macho`), `check-bundle`, `bootstrap` at BOTH
  fixed points (`mc2.o == mc3.o` 1442984 B, `mc2o.o == mc3o.o`) with the cross-road identity
  (`build/mc2o src/mc.mc == build/mc2.o`) and **both `--dump-asm` diffs between `mc1` and `mc2`
  empty** (plain and `--opt=1`), `check-surface` 32/32 + inert, `check-opt`, `test-exe` 32/32,
  `check-mc`, `check-standalone`, `check-parts`, **`check-libroot` 11/11**, `check-toml`,
  `check-build`, **`check-pkg` 194/194**, `check-tool` 27/27, `check-sysroots`, `check-stubs`,
  `check-limits` **17/17 seed limits under 90%**, `check-minimal`, `test-linux`/`test-linux-x86_64`
  and the four `--exe` cells, `test-windows`/`test-windows-x86_64`, `check-examples`, `check-lang`,
  `check-conc`, `check-desktop`, `check-float`, `check-wide`, `check-kernel`, `check-avr`,
  **`test-sandbox` 73 ok / 0 failed / 1 skipped**, `check-docs` (206 symbols, 50 flags, 35 TOML keys,
  10 directives, 52 samples, 533 links), `site` + `check-site` + `check-site-linux`.
  `make check-linux-host` **RC 0 over all four cells** (aarch64 and x86_64 x musl and gnu), each
  after its own plain AND optimized fixed point (`mc2l.o == mc3l.o`, `mc2lo.o == mc3lo.o`), its own
  cross-road identity (`mc2lo-plain.o == mc2l.o`) and the cross proof
  (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`) green in all four.
  `scripts/check-inert.sh <mc1 from d18930d> build/mc1`: **33 objects identical on the plain road and
  33 with `--opt=1`** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for
  `examples/api`, `lang`, `conc`, `desktop` and `kernel` through the taught compiler each side
  builds -- what moved is which root the child reads, not a byte the compiler writes.
  **The ten goldens rewritten once**, each only after its own criterion: `mc2.sha256`
  `8543f340…5a8ab3` -> `7c5daea8e4f2c28ff42fa1c787a6c5dfbcd32ca5eaa3ed440793500c9f74e679` and
  `mc2-opt.sha256` -> `3ea767f6c5d017d09bc7a8c1dfd5cc6d49386016cd930b96413213587b39f3d4` (both by
  `scripts/bootstrap.sh`, after the two empty `--dump-asm` diffs and the two `cmp`s); the four Linux
  ones deleted and re-recorded by `make check-linux-host` -- `mc2-linux-arm64`
  `4e7dcc4fcd7be9239b989d7c68fdada8502f01779c3459c051a0372d90f9faae`, `mc2-linux-arm64-opt`
  `21cbd65662893efbb1152c8a765838ae2784307ad857a3c3ccf3c4bc7c00080b`, `mc2-linux-x86_64`
  `730c24adffb643aefe8fa3dab5670fdd2766c49974a3a465c133ed65a00a4c6a`, `mc2-linux-x86_64-opt`
  `958ab1b421d74bc6c41e673795e9630ae17e7da6084c91e71dcd30a4a830ce04`; the four Windows ones
  cross-computed on macOS per `tests/golden/README.md` -- `mc2-windows-arm64`
  `33aec08cab4171de320246f90a95bce2c965f9160046caa1ef2abe0f8feed84b` (1477929 B),
  `mc2-windows-arm64-opt` `5f365d5a304a4fdf3947695c60e2b4006c4a5d9fbeccb52464885ac73a44b3e1`
  (1419245 B), `mc2-windows-x86_64`
  `68efe037f8d08505a65550b4ec397d211d5e07c593c80c5ec731ed6f6d901f5d` (1533557 B),
  `mc2-windows-x86_64-opt` `c858c9e6e1a95eca648d268a400f8bb80462eaf365f7a56083bd3f0f51236f76`
  (1461541 B); `build/mc2` writes the two plain Windows objects byte for byte as `build/mc1` does.
  Docs: `docs/reference/packages.md` § 2 (what each root serves in a child, and why `--libs-dir` is
  forwarded only when explicit), `docs/build.md` § `[compiler]`, `docs/reference/hooks.md` § 6
  (`host_self_path` resolves a symlink, and which host needs what),
  `docs/specs/M52.md` (§ 11 row 4 LANDED + § Implementation notes -- step E).
- M53 step C ✔ (`docs/specs/M53.md` § 6, § 8.6-8.8, § 9 row 3 + its new § Implementation notes --
  step C): **the release canary** -- every release is born a GitHub pre-release while
  `vars.MC_CANARY` is armed, a `promote` job polls the consumer's public verdict and clears the
  flag, and `publish-to-registry` waits behind it. `stage0/`, `src/`, `lib/` and `tests/` untouched
  -- `git diff --stat src/ stage0/ tests/golden/` is **empty**, no golden moves, the compiler emits
  not one different byte. Only `.github/workflows/release.yml` (+97/-8), the new
  `scripts/canary-poll.sh` (167 lines, 106 code) and `docs/`.
  * **No credential crosses the boundary, either way** (§ 6's constraint). mc cannot dispatch a
    workflow in the consumer's repository (a PAT) and the consumer cannot receive mc's `release`
    webhook (a foreign repository does not get one), so both halves are PULL: the consumer polls
    mc's public releases API with no token, runs its whole recipe against the tarball, and writes a
    verdict into a branch of its own repository with its own `GITHUB_TOKEN`; mc `curl`s that file
    with no token at all.
  * **The verdict is at the ROOT of a branch named `canary`**, `<version>.json`, at
    `https://raw.githubusercontent.com/teko-org/teko-lang/canary/<version>.json` --
    `{"version":"0.17.0","status":"ok"|"fail","run":"<actions url>","utc":"..."}`, the version
    **bare** (a leading `v` is stripped before comparing). § 6.2 point 2's prose and its own URL
    contradicted each other (`canary/<version>.json` in a branch named `canary` would read
    `.../teko-lang/canary/canary/0.17.0.json`); **the URL was right, the prose was wrong**, and the
    spec is corrected in place to the ROOT form -- which is also what the consumer was told through
    the channel on 2026-09-14 and what it is building. The repository name comes from that channel
    and `gh repo list teko-org`, not from the milestone's shorthand, and it is the DEFAULT of
    `CANARY_REPO` rather than a literal, with `vars.MC_CANARY_REPO` overriding it.
    **A missing file is neither `ok` nor `fail`** -- the verdict has not been written yet and the
    poll continues; so is any other value, which lets the consumer write a placeholder without mc
    acting on it. A verdict naming a different version is not this release's and the poll says so.
  * **Three repository variables, and unarmed is byte for byte the pipeline that was there.**
    `MC_CANARY = true` arms it (§ 6.2 point 1's own spelling -- not `"1"` and not `"required"`,
    which is a second question): `publish`'s `case "$VERSION" in *-*)` is untouched and one
    `if [ "$CANARY" = "true" ]` below it forces `--prerelease`, and the body composer appends a
    Canary paragraph naming the one manual command. `MC_CANARY_REQUIRED = true` at 1.0.0
    ("bloqueante no 1.0.0"), as the job's `continue-on-error: ${{ vars.MC_CANARY_REQUIRED != 'true'
    }}` -- so § 6.2 point 5's two states are one variable and not two workflow edits.
    `MC_CANARY_REPO` moves the consumer. Unset, `promote` is SKIPPED and nothing else changes:
    `gh variable set MC_CANARY --body true` is the owner's switch, named in `docs/ci.md`.
  * **`promote` is a job**, `if: vars.MC_CANARY == 'true'`, `needs: publish`, `ubuntu-latest`,
    `timeout-minutes: 95`, `permissions: contents: write` (only it and `publish` have it), one
    checkout and one step. A job and not a step for `publish-to-registry`'s exact reason (§ 6.2
    point 3): a failed promotion must not be able to unmake a published release, and a rerun of the
    job alone is the retry. The 90-minute poll at 60 s is § 6.2 point 4's budget -- up to 15 minutes
    for the consumer's schedule plus its recipe -- and 95 is that plus the checkout.
  * **The four outcomes, from the lines.** `ok` -> `gh release edit "$TAG" --prerelease=false`,
    exit 0, the registry runs. `fail` -> `::error::` + the by-hand line + exit 1, the release left a
    pre-release with every asset attached; advisory the RUN stays green and the job renders red
    (§ 8.7), required the run is red and the registry is skipped. `timeout` -> advisory a
    `::notice::` and the release **promoted anyway** (§ 6.2 point 5 read literally -- a `::notice::`,
    not the `::warning::` the brief supposed -- so an outage on the consumer's side cannot hold an
    mc patch), required an `::error::` and the release stays a pre-release. `unarmed` -> skipped.
  * **`publish-to-registry` is `needs: [publish, promote]`** with an `if` that names a status
    function, because a job whose `needs` is SKIPPED is skipped too and `promote` is skipped on
    every release while `MC_CANARY` is unset:
    `!cancelled() && vars.MC_REGISTRY_PUBLISH == 'true' && needs.publish.result == 'success' &&
    needs.promote.result != 'failure'`. The load-bearing half is unambiguous -- at 1.0.0
    `continue-on-error` is false, a `fail` or a required timeout makes that result `failure`, and a
    pre-release is never announced as the registry's newest row.
  * **The poll is a script**, `scripts/canary-poll.sh`, not thirty lines of YAML: it is the only way
    § 8.6's round trip can be reasoned about before a real tag exists, and it is the repository's own
    precedent (`next-version.sh --test`). `--test` is **7/7 assertions over `file://` URLs**, no
    network and no framework (ok promotes, a `v`-prefixed field is accepted, `fail` is exit 1, a
    verdict for another version keeps waiting, an advisory timeout promotes with the `::notice::`,
    a required timeout is exit 1 with the `::error::`, and the derived URL is § 6.2 point 2's);
    `--url TAG` prints the URL without touching the network; `DRY_RUN=1` prints the `gh release
    edit` it would run. `shellcheck -s sh` clean.
  * **Proof, and what is NOT proved here.** `actionlint .github/workflows/release.yml` reports
    **exactly the two findings it reports on the same file from `main`** (SC2155 at `:527`, SC2086
    at `:547`), in the same steps, both predating this change -- zero new. `make check-docs` green
    (206 symbols, 50 flags, 35 TOML keys, 10 directives, 52 samples, 548 links). § 8.6's measured
    round trip and § 8.8's job graph need a tag and the consumer's `canary` branch, which does not
    exist yet (`gh api repos/teko-org/teko-lang/branches/canary` -> 404): **the first real round
    trip is the next tag with `MC_CANARY` armed**, and its elapsed time and run URL go into
    `docs/specs/M53.md` § Implementation notes then.
  Docs: `docs/ci.md` § The canary (new -- the protocol diagram, the contract, the `promote` job, the
  three variables with the `gh variable set` lines, and `scripts/canary-poll.sh`), § Versioning (a
  GitHub pre-release is not a pre-release VERSION) and § `release.yml` / § `publish-to-registry`;
  `docs/specs/M53.md` § 6.1 and § 6.2 point 2 corrected to the ROOT form, § 9 row 3 LANDED, plus
  twelve implementation notes. `docs/ci.md` § Branch protection needed nothing: `release.yml` fires
  on a tag and none of its jobs is a pull-request check.
- `mc build` fixes 0.16.1 (two defects the consumer -- teko -- reported from a real
  `windows-latest` run with `mc-0.16.0-windows-x86_64`; `docs/specs/M42.md` § Implementation notes
  -- the precedence gap step 2 opened): **a declared `[linker]` wins over the host's direct exe
  backend for the taught compiler, and a spawned compiler that fails is named.** `stage0/`
  untouched (2848/3000); the whole code change is `src/driver.mc` **+42/-4, 9 of the added lines
  neither comment nor blank**, and **zero new globals** (`check-limits` still reports
  `globals 268/512, 52%` on `src/mc_seed.mc`).
  1. **`drv_teach` took the exe slot whenever it was not 0.** The road existed for the entry
     (`drv_entry` has always preferred `[linker]`) and not for the compiler, so a config declaring
     `[linker] cmd = "lld-link"` -- the only road to a Windows binary at 0.15.23, when Windows had
     no exe slot -- got a PE the driver wrote itself the day M42 step 2 filled `windows/x86_64`'s.
     Reproduced here BEFORE the fix, on macOS, which has the same shape (a host with a direct exe
     backend and a `[linker]` in the config): `tests/proj/teach-link.toml` printed
     `compiler build/mc-teachld.mc -> build/mc-teachld` / `compile app.mc -> build/app-teachld.o` /
     `link build/app-teachld.o -> build/app-teachld` -- the ENTRY linked, the COMPILER not, no
     `build/mc-teachld.o` written at all. After: a `link build/mc-teachld.o -> build/mc-teachld`
     step line, the object on disk, and the linked compiler compiles the entry, which runs
     (`sqlite ok`, exit 0). The condition is one local -- `has_linker == 0 && tgt_exe_at(ht) != 0`
     -- and the existing `a taught compiler on this host needs [linker]` message is byte for byte
     where it was. The obligation it creates is documented: the linker a config names has to be
     able to link a binary THIS host can run, since `mc build` spawns the compiler it just wrote.
  2. **A spawned tool that fails is named.** `drv_teach` did `return 1` with no diagnostic, so the
     CI printed `compiler build/teko.mc -> build/teko.exe` and died mute (exit 127 from the child,
     the loader refusing the PE). Reproduced before the fix with `tests/proj/teach-fail.toml`,
     whose module is `_exit(127)` in `user_init`: exit 1, last line
     `compile app.mc -> build/app-teachfail`, nothing else. After:
     `mc: tests/proj/build/mc-teachfail exited 127`, exit 1. ONE helper, `drv_tool_failed`, at the
     two places the driver waits on a tool -- the `[linker]` spawn and the taught compiler's, so
     both `--compiler-only` and the normal road are covered. **Exit 1 is exempt**, and that is the
     whole rule: it is how every diagnostic in this compiler ends (`die`/`err_at` both `_exit(1)`)
     and how a linker reports its own error, so the tool has already said what was wrong and a
     line from here would only push it off the end of the output -- which `check-build`'s
     `noobj.toml` case, among others, reads as the last line (verified unchanged:
     `tests/proj/noobj.toml:19:8: toy/toy has no object backend: use kind = "exe": target.os`).
     Anything else is a death the tool had no chance to report; 128 + N is read as
     `killed by signal N`, drv_spawn's encoding and the shell's convention.
  Gates: `scripts/check-build.sh` **55/55 -> 59/59** (+4) -- `tests/proj/teach-link.toml`
  (`link.toml` plus a `[compiler]`, asserting the object AND the `link` step line for the taught
  compiler, then RUNNING the entry it built), the control that `toy.toml` (the same shape with no
  `[linker]`) still writes no `build/mc-toy.o`, and `tests/proj/teach-fail.toml` asserting the new
  line as the LAST one with exit 1. New fixtures: `tests/proj/teach-link.toml`,
  `tests/proj/quiet.mc` (a module that teaches nothing), `tests/proj/exit127.mc`,
  `tests/proj/teach-fail.toml`.
  `make bundle` re-run BEFORE bootstrapping (`src/driver.mc` is bundled as `mc/driver`): 60 files,
  raw 1244184 -> LZ 564064, blob 564838 B. `make check` green end to end (**RC 0, zero FAIL**):
  `budget` 2848/3000, `test` 32/32, `check-obj` **32/32 identical to the frozen seed**,
  `check-bundle`, `bootstrap` at a fixed point on both roads (`mc2.o == mc3.o`, 1444480 B, the
  `--dump-asm` diff between `mc1` and `mc2` **empty**; `mc2o.o == mc3o.o` and the cross-road
  identity `mc2o-plain.o == mc2.o`), **`check-build` 59/59**, `check-limits` **17/17 under 90%**,
  `check-docs`, `site` + `check-site`. `make check-linux-host` RC 0 over all four cells (aarch64
  and x86_64 x musl and gnu), each after its own `mc2l.o == mc3l.o` and `mc2lo.o == mc3lo.o` and
  with the cross proof against the macOS `build/mc2.o` green.
  `scripts/check-inert.sh <mc1 from origin/main f9c5797> build/mc1`: **33 objects identical on the
  plain road and 33 on `--opt=1`** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for
  `examples/api`, `lang`, `conc`, `desktop` and `kernel`. None of the five declares `[linker]` on
  this host -- the two configs in the repository that carry `[compiler]` AND `[linker]`,
  `examples/api/mc.linux.toml` and `examples/conc/mc.linux.toml`, are host-Linux configs no script
  exercises, and on a Linux host they now link the taught compiler with the `ld.lld` line their own
  headers already describe.
  The ten goldens rewritten **once**, each only after its own criterion: `mc2.sha256`
  `7c5daea8...f74e679` -> `045a89e47b5bc39bc94adc663972dc53afa6afb0c2277c046ec069b42e991ba8` and
  `mc2-opt.sha256` `3ea767f6...b39f3d4` ->
  `ca7711c2b5aa5687271502a596315d30b3bc61419affdd1417443c3624b0335c` (deleted and re-recorded by
  `make bootstrap` after the empty `--dump-asm` diff and the two `cmp`s); the four Linux ones
  deleted and re-recorded by `make check-linux-host` -- `mc2-linux-arm64`
  `a1d2b044b0d0ead348fca4f89b8b6e7271e7317eba828993dec8d830d2cf477f`, `mc2-linux-arm64-opt`
  `ae5e9b7cbd790f06ef159d4fe2fef87cebe9846ab72ce82dca9d04715398e9dd`, `mc2-linux-x86_64`
  `761ef33949ae7345dc396004f9fea115ed56539135a04dc4902e7a144d0f8205`, `mc2-linux-x86_64-opt`
  `464887e40e0a7d3ddbefbfdcf71501fa55e96ba506fad19d1f1d09c33dc4753c`; the four Windows ones
  cross-computed per `tests/golden/README.md` -- `mc2-windows-arm64`
  `0cb5677b0b0fe51d02344ede3ce4880ddc4e45b14a66ecd09f799eef38e5c889` (1479443 B),
  `mc2-windows-arm64-opt`
  `a068edbd3c757eca60e32badc174bdfbe4879989ac438d768b116a85a4422141` (1420723 B),
  `mc2-windows-x86_64`
  `493edc5134202a840e26bad2a197d9981c3144a364bfc3798a48ca9a95c3f043` (1535127 B),
  `mc2-windows-x86_64-opt`
  `97dfee1d4b168a66188ab0b11fce9b763f53bf0080553e5bb16f652a6879c554` (1463087 B).
  Docs: `docs/build.md` § `[compiler]` (the two-road table and the precedence, and what the driver
  prints when the compiler it spawned fails) and § `[linker]`, `docs/reference/toml.md`
  (the `linker.cmd` row and the errors), `docs/reference/diagnostics.md` (one new row),
  `docs/specs/M42.md` § Implementation notes.
- M53 step A ✔ (`docs/specs/M53.md` § 2 D1/D2, § 3, § 4, § 8.1-8.5, § 9 row 1 + its new
  § Implementation notes -- step A): **the surface extractor, `tests/golden/surface.txt` and
  `check-freeze`.** Nothing in `src/` or `stage0/` -- `git diff --stat src/ stage0/
  tests/golden/*.sha256` is **empty**, no golden moves, and the only new file under
  `tests/golden/` is the inventory itself. The measurement the milestone rests on is that the
  inventory ALREADY EXISTED and nobody read it as one: `scripts/check-docs.sh` extracted the whole
  public surface on every `make check` and threw it away after asking "is each one documented?".
  Asking the second question, "was each one here last time?", costs one recorded file and one
  comparison.
  * **`scripts/surface-extract.sh` (81 lines)** is THE definition of all seven kinds, printing
    `<kind><TAB><name>` bytewise-sorted (`LC_ALL=C`), or one kind's names alone with an argument:
    **`sym` 209** (the 17 prefixes, the five exact names, plus `val_reg`/`dst_reg`/`dst_done`),
    **`flag` 50**, **`toml` 35**, **`dir` 10**, **`bundle` 101** (column 1 of `tools/bundle.list`,
    the libraries AND the `<mc/*>` parts in one kind, D3), **`lock` 14** (the `tm_cat(key, "...")`
    literals in `src/pkg.mc`/`src/tool.mc`/`src/deps.mc`, a computed TOML path the `toml_*` regex
    cannot see, D4) and **`machine` 1** (the `Contract version N` line of
    `docs/reference/machine.md`, one line and not 37 slot names, D5) -- **420 in all**, exactly
    what § 2 predicted.
  * **D11 held: `scripts/check-docs.sh` has no regex left.** `grep -c 'grep -hoE'` over it is
    **0**; its four pipelines became four `sh scripts/surface-extract.sh <kind>` calls
    (**+19/-13**), so the two gates cannot disagree about what is public. Its four `ok coverage:`
    lines are unchanged except the first -- **206 -> 209 symbols**, 50 flags, 35 TOML keys,
    10 directives -- and samples (52) and links (543) are untouched.
  * **D2 closed the hole at no documentation cost.** `val_reg`, `dst_reg` and `dst_done` are the
    three names `machine.md` § 3 publishes BY NAME as the only three names of a machine's
    internals that are frozen (contract version 3, M24 D2) and they matched no prefix and no exact
    name -- **0 of 206**, so a gate built on the old regex would have frozen 206 names and left the
    three that were already promised unprotected. `check-docs` is green at 209 with **no edit to
    `docs/reference/`**: all three are already written as calls in `machine.md` and `hooks.md`.
  * **`scripts/check-freeze.sh` (125 lines)**, `make check-freeze`, inside `make check` right
    after `check-docs` on macOS and in the Linux and Windows subsets too -- it is `grep` over
    `src/`, `tools/bundle.list` and one line of `machine.md`, so it needs no compiler and runs on
    every host. Identical -> `ok freeze: 420 entries (209 sym, 50 flag, 35 toml, 10 dir,
    101 bundle, 14 lock, 1 machine)`, exit 0. An entry GONE -> `removed: <kind> <name>` and the
    MAJOR sentence pointing at the policy; gone and MARKED `deprecated <version> -> <replacement>`
    in the golden -> the shorter "legal, re-record it in this commit"; an entry ADDED ->
    `new: <kind> <name> -- additive, a MINOR` and `re-record: scripts/check-freeze.sh --record`
    (**D10**: a legal addition still fails until the file is re-recorded, so every surface change
    costs one committed line in the same pull request and the diff IS the announcement).
    Re-recording is a NAMED act, `--record` / `make record-surface`, and not the hash goldens'
    delete-and-rerun (**D9**): this file's CONTENT is the review artefact.
  * **`machine` gets its own verdict and is excluded from the add/remove diff**, because a version
    bump is neither a removal nor an addition -- leaving it in would have printed
    `removed: machine 5` under the MAJOR sentence for an append-only bump. All four rows of § 4.3's
    table measured: `-> 4` FAILS (`a version may only go up`), `-> 6` with no paragraph FAILS
    naming the `Version 5 -> 6` paragraph it wants, `-> 6` WITH one FAILS as "re-record", and after
    `--record` it passes. The paragraph is matched as `Version <old> (->|→|-->) <new>`, the shape
    `machine.md`'s own four changelog entries use.
  * **The policy pointer is to the SPEC, not to `hooks.md` § 8**, which is step B's: the gate's
    messages, `tests/golden/README.md` and a new two-line `hooks.md` § 8 all point at
    `docs/specs/M53.md` § 5 and say where the full text will be. Step B replaces one string
    (`policy` in `check-freeze.sh`).
  -- **Teeth, measured in both directions**, each with the tree restored afterwards: renaming
  `p_type` to `p_typ` in `src/parse.mc` gives `removed: sym p_type` + the MAJOR sentence AND
  `new: sym p_typ -- additive, a MINOR`, exit 1; deleting `tools/bundle.list`'s `float` row gives
  `removed: bundle float` + the MAJOR sentence, exit 1; marking that row deprecated in the golden
  first gives the shorter message; the pristine tree is `ok freeze: 420 entries`, exit 0.
  `make check` green end to end (**RC 0, zero FAIL**) with `check-freeze` in it; `check-docs`
  green at **209 symbols, 50 flags, 35 TOML keys, 10 directives, 52 samples, 543 links** (206 ->
  209 is the whole difference); `check-limits` unchanged. `Makefile` +17/-4 (`check-freeze`,
  `record-surface`, `.PHONY`, and the three `check:` lists).
  Docs: `tests/golden/README.md` (§ `surface.txt` -- what it is, the seven counts, why `--record`
  and not delete-and-rerun, and when to re-record: in the same pull request as the change that
  moved it, never to make the gate pass), `docs/reference/hooks.md` § 8 (two lines, pointing at
  the spec), `docs/ci.md` § Job `check` (the gate in the `make check` list),
  `docs/specs/M53.md` (§ 9 row 1 LANDED with the real line counts + ten implementation notes).
  Not in this step: **B** the policy (`hooks.md` § 8 in full, the six pointers, `ci.md`'s label
  table), **C** the canary (`release.yml`'s `MC_CANARY` pre-release flag and the `promote` job),
  and **D** the deprecation note, which lands with the first deprecation (D13).
- M53 step B ✔ (`docs/specs/M53.md` § 5, § 9 row 2 + its new § Implementation notes -- step B):
  **the stability policy.** Docs only -- `git diff --stat src/ stage0/ tests/golden/` empty, no
  golden moves, no name frozen or unfrozen. `docs/reference/hooks.md` § 8 written in full
  (+108/-5, 110 lines in place): the seven-kind inventory table, what is **not** the surface
  (`src/` globals -- an accessor is the migration, a rename goes in the release note; diagnostic
  text -- the exit code and the stream are the contract, wording is a PATCH), the PATCH/MINOR/MAJOR
  rules table, the four-step deprecation lane, the compile-time note SPECIFIED and NOT BUILT (D13,
  ~25 `src/` lines priced for the pull request that ships the first real deprecation), and the
  0.16.x / RC / 1.0.0 table. Six one-line pointers -- `cli.md`, `toml.md`, `packages.md` § 4,
  `bundle.md`, `objects.md`, `machine.md` (+3/+3/+5/+4/+5/+5) -- `objects.md` in place of the
  spec's own `directives.md` (§ Implementation notes 3: `objects.md` already draws the byte/name
  distinction § 8 needs, `dir`'s ten rows have nothing further to say). `docs/ci.md` § Versioning
  (+18/-6): the label table gains a "what the policy allows" column (`release:major` is the only
  label that may remove a `deprecated`-marked entry, `release:minor` any additive one) and a line
  naming RC 0.17.0 as a state of the repository, not a suffix (§ 7 D18).
  -- `check-freeze` unchanged: `ok freeze: 420 entries (209 sym, 50 flag, 35 toml, 10 dir,
  101 bundle, 14 lock, 1 machine)`, exit 0. `check-docs` green:
  `docs ok: 209 symbols, 50 flags, 35 toml keys, 10 directives, 52 samples, 570 links`.
  Docs: `docs/specs/M53.md` (§ 9 row 2 LANDED with the real line counts + seven implementation
  notes, including the one found while writing note 7 itself -- a markdown-link SYNTAX quoted
  literally to illustrate a pointer's shape is itself a link to `check-docs`'s naive scan, and
  broke it), `docs/plan.md`'s M53 row (steps A/B/C landed; the milestone still closes only on
  teko's own gap list reaching zero, § 13).
- `mc tool` -- the consumer's four (0.16.1; `docs/specs/M48.md` § Implementation notes -- C3
  review, the consumer's four): four defects reported by teko from a real run against 0.16.0, each
  with a pure reproducer, each fixed at its root and each reproduced HERE before a line was
  written. `stage0/` untouched (2848/3000). The whole compiled change is **78 added lines in
  `src/`, 39 of them neither comment nor blank** (`deps.mc` +23/-9, `pkg.mc` +29/-6, `tool.mc`
  +26/-0) and **zero new globals**.
  1. **`mc tool install DIR` ignored `[tools]` when the project had no `[deps]`.** `deps_apply`
     counted `deps.` keys alone and returned on `nd == 0` BEFORE `dep_read_lock`, so `dp_npkg()`
     was 0 and the answer was `no tools required by this project`, exit 0 -- with a valid lock
     naming the tool beside the manifest; adding one `[deps]` row made the same tree install.
     A `tools.` key now counts towards `nd`: the lock is the answer to BOTH tables and is read
     when EITHER has rows. One root, every consumer -- `mc build`, `mc pkg list|verify|vendor`
     and `mc tool install DIR` all reach the lock through that one function, and the `mc pkg sync`
     road (`pkg_read_deps`) already counted tools. Consequence, documented: a `[tools]`-only
     project needs an `mc.lock` for `mc build` too and says `mc.lock is stale` with its `run:`
     line without one. Inert for the tree: `tests/pkg/perm` is the only fixture with a `[tools]`
     table and it has `[deps]` beside it.
  2. **A `[replace]`d tool was half-applied.** The archive was fetched and then `tool_stage`'s
     `pkg_write_lock` resolved the project's `[replace]` path against the STAGED tree -- that
     function repoints `cfg_file()` so the vendored `deps/` is found -- and died
     `mc: cannot open: <tools>/hello_tool/toy/mc.toml` AFTER the download. Reproduced verbatim.
     **The rule chosen is IGNORE, and the spec supports it**: `[replace]` is Go's `replace`
     (M44 D11), an override for a tree the BUILD compiles, and `deps_apply` step 4 already skips
     every tool row before `dep_replace` is consulted -- a tool is a program installed under
     `~/.mc/tools` at the version the lock pins, not something compiled into your program.
     Honouring it would have meant a second, fetch-free install road for an unpinned tree with no
     hash to record, contradicting the row the build already skips. So the whole `mc tool` road
     ignores the table -- for the tool AND for the libraries `tool_stage` copies from `<libs>`
     beside it -- and announces it once per replaced name, above the plan: `note: [replace]
     hello_tool = "../toy" is ignored by mc tool: a tool is installed from the registry`.
     Nothing dies after a download.
  3. **A constraint `mc pkg sync` refuses reached the install road.** `deps_apply` validated a
     `deps.` value with `ver_parse` (step 3) and a `tools.` value not at all, so `[tools] x =
     "^0.1"` was accepted, fetched, staged and BUILT, with `x >= ^0.1` printed in the install
     table. Now the same `ver_parse` + `ver_bad_msg()` at the key's own `file:line:col`, exit 2,
     in step 1 -- before the lock is read and before anything is fetched. Step 1 and not step 3
     because step 3 compares a constraint against a lock row and a tool's version comes from the
     lock: the only thing to say about `^0.12` is that it is not a constraint.
  4. **The permission table lost its column gap.** `pkg_pad(line, 22)` pads to the width and no
     further, so a 24-byte `fs.write workspace/build` ran into the sentence --
     `fs.write workspace/buildmay create, change and delete files under build ...`, verbatim --
     and the `what` column (`<name> <version>`) has the same shape past 17 bytes. Fixed where
     every OTHER caller already puts it: `mc pkg list` and `mc tool list` write their own space
     after each column, so the permission table pads to `w - 1` and writes that space -- the same
     total width for every value that fits, a guaranteed gap for one that does not. **The first
     draft forced the space inside `pkg_pad` and it moved an unrelated golden**: `mc pkg list`'s
     hash column is `xstrdup(h, 12)` in a 12-wide column, exactly at its width, so every row of
     `tests/golden/pkg-list.txt` gained a space (measured: `check-pkg` 192/194). The helper is
     back to what it was.
  **The frozen seed's `MAXFUNCS` is what shaped the code.** `lib/mc_i128.mc` is
  `#include "../src/core.mc"` plus a module and sat at **2046 of 2048**; the first draft added
  three functions and `build/mc0 --dump-asm lib/mc_i128.mc` became `mc: too many functions`,
  which `check-asm` compares byte for byte and `stage0/` may not be edited to fix. Collapsed to
  **one**: `tool_ignore_replace()` prints the notes and then sets the flag itself (idempotent, so
  a two-tool project says it once), and `pkg_replace_path` reads `ld64(pk_state() + PKS_NOREPL)`
  where the record is declared -- the shape `pkg_list` already uses for `PKS_LONG`.
  **2047/2048: one function of headroom for the whole repository.** (The seed exhausting its
  64 MiB arena on `build/mc0 lib/mc_i128.mc -o x.o` PREDATES this change -- measured on a
  pristine checkout of 769d8e5 -- and no gate takes that road: check-lex/ast/asm only dump.)
  -- gates: `scripts/check-tool.sh` § 7 is one case per defect, **27 -> 31/31**, and all four FAIL
  against a `build/mc1` built from `origin/main` 769d8e5 (**27/31**): the `[tools]`-only project
  installs and its launcher exists, the `[replace]`d tool prints the exact note and stages the
  REGISTRY's tree (the local one carries a marker the staged copy must not have), the two-part
  constraint is refused at its own position with a fresh `<libs>`/`tools` pair left empty, and the
  padded line contains `build may`.
  `make bundle` re-run BEFORE bootstrapping (60 files, raw 1247436 -> LZ 565551, blob 566325 B).
  `make check` green end to end (**RC 0, zero FAIL**): `check-asm` 178/178 (4 skipped),
  `check-obj` **32/32 identical to the frozen seed**, `bootstrap` at BOTH fixed points
  (`mc2.o == mc3.o` 1446904 B, `mc2o.o == mc3o.o`) with the cross-road identity
  (`mc2o-plain.o == mc2.o`) and **both `--dump-asm` diffs between `mc1` and `mc2` empty** (plain
  and `--opt=1`), **`check-tool` 31/31**, **`check-pkg` 194/194**, `check-limits` **17/17 seed
  limits under 90%** (tightest `globals` 268/512 = 52% on `src/mc_seed.mc`), `check-freeze`
  `420 entries` unchanged (no public name added: `tool_ignore_replace` matches no surface prefix),
  `check-docs` (209 symbols, 50 flags, 35 TOML keys, 10 directives, 52 samples, 570 links),
  `test-sandbox` 73 ok / 0 failed / 1 skipped.
  `scripts/check-inert.sh <mc1 from origin/main 769d8e5> build/mc1`: **33 objects identical on the
  plain road and 33 with `--opt=1`** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts
  for `examples/api`, `lang`, `conc`, `desktop` and `kernel`.
  `make check-linux-host` **RC 0 over all four cells** (aarch64 and x86_64 x musl and gnu), each
  after its own plain AND optimized fixed point, its own cross-road identity and the cross proof
  (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`).
  **The ten goldens rewritten once**, each only after its own criterion: `mc2.sha256`
  `045a89e4...991ba8` -> `e1dbf53167b55b4c80e2d5009b63846a3f092bae4b760ddfa48c640fa6cab4c1`,
  `mc2-opt.sha256` `cce7215a93c225f9190b33e11a2e44fc9445a48ded8261df9e46bebf17d4f925` (both by
  `scripts/bootstrap.sh`, after the two empty `--dump-asm` diffs and the two `cmp`s); the four
  Linux ones deleted and re-recorded by `make check-linux-host` -- `mc2-linux-arm64`
  `e3ecfbc98370f6ac9863a24dd59e60288982ef09bb6f86b8db1c668458e64f82`, `mc2-linux-arm64-opt`
  `72fb44d9f2ba6d9df6e616d72b47879266f13148ebf2270d20ad560af43c7bf3`, `mc2-linux-x86_64`
  `1d54a0ff517276e8bc20c4457544feaa404a1493cc92b3914aa61a134e63e7b3`, `mc2-linux-x86_64-opt`
  `8418400db1249ddb7eb903cd6d5814b6eeb5eb893b1990342ec3cf1cbcf39864`; the four Windows ones
  cross-computed on macOS per `tests/golden/README.md` -- `mc2-windows-arm64`
  `2ca5132750a78c82faa04dafb7b3c7c5af4467c53fb1f62d2d4a1315ac316f9f` (1482169 B),
  `mc2-windows-arm64-opt`
  `3ad31640afe7a6574233b238d190edb3620869841c225bf773809bcf534de1e3` (1423389 B),
  `mc2-windows-x86_64`
  `f3a5a1e352233f83054cbcbf93e4b40d4736591c0444f301c39e16977a6c7643` (1537989 B),
  `mc2-windows-x86_64-opt`
  `d09875218ada0fce615619f1a0e4cf5ae4c414fc6ee17f05f266faf15c8e0d17` (1465861 B), the two plain
  ones also written byte for byte by `build/mc2`.
  Docs: `docs/reference/tools.md` (what `install [DIR]` reads, and a new § "`[replace]` is not
  consulted"), `docs/reference/packages.md` § 7 (a tool is never replaced),
  `docs/reference/toml.md` (`[deps]`/`[tools]` and the lock; the stale "`mc tool`, which does not
  exist yet" corrected), `docs/reference/diagnostics.md` (the `mc.lock is stale` row names both
  tables), `docs/specs/M48.md`.
- A vendored tree at another version is named, never hashed (0.16.1; reported by the consumer --
  teko -- with a pure reproducer; `docs/specs/M44.md` § Implementation notes -- the vendored tree
  at another version): **the version comes before the hash.** `stage0/` untouched (2848/3000).
  The consumer's dev loop is a git checkout at `deps/teko`, and `deps/` wins over the cache
  (M44 D10', § 3) -- but `pkg_present`/`pkg_tree_dir` decided that on ONE question, "is there an
  `mc.toml` under `deps/<pack>/`?", so a project whose `[deps]` had moved to version A while the
  checkout was still at B did not fetch A at all: it hashed B and compared that hash with A's
  `sha256`. Reproduced here before a line was written, with `[deps] zero = "0.2.0"` and
  `deps/zero` a copy of the 0.1.0 fixture:
  `mc: checksum mismatch for zero 0.2.0 / expected 1177e8ee… / got 9943772d…`, exit 2, nothing
  fetched -- and `got` is `mc pkg hash deps/zero` exactly. The diagnosis is wrong twice over:
  nothing is corrupt, and the advice a checksum mismatch carries (re-fetch, look for a tampered
  byte) does not apply. Moving `deps/zero` aside made the same command fetch and lock.
  **`mc build` said the same thing in its own words** and the check confirmed it is the same
  defect: `dep_resolve` picked the vendored tree on the same one question and `dep_scan` produced
  `mc: zero 0.2.0: the tree does not match mc.lock` with `run: mc pkg verify` -- and `mc pkg
  verify` repeats it, so the advice is a loop.
  * **One function, called from all three places**: `dep_vendored_at(name, dir, ver, from)`
    (`src/deps.mc`) answers "is `deps/<name>/` this package at this version?" and is the sole
    reader of the vendored tree's own `[package].version` -- a new, OPTIONAL key. 0 is "no tree
    there", 1 is "a tree that declares nothing, or declares this version", and a tree that
    declares another one never comes back:
    `mc: deps/zero is 0.1.0, [deps] wants 0.2.0: update the checkout or remove deps/zero`, exit 2.
    `from` is where the requirement was read, the only part that differs between the roads:
    `[deps]` for `mc pkg sync` (`pkg_vendored`, called by `pkg_present` and `pkg_tree_dir`) and
    `mc.lock` for `mc build`, `mc pkg verify`, `mc pkg list` and `mc pkg vendor` (`dep_resolve`).
    Nothing is fetched and no lock is written; `mc pkg vendor` refuses too, and the answer there
    is the one the message already gives -- remove the checkout, then vendor.
  * **A tree that declares no version behaves exactly as before**, which is what makes the change
    inert for every package published so far (none carries the key) and for every fixture but the
    two the gate uses. That is also the honest limit: without a declaration there is nothing to
    compare, and a mismatched checkout can still only be reported as a hash. The key resolves
    NOTHING -- the registry picks a version, `mc.lock` pins it, and a fetched or installed tree
    carries its version in the manifest beside it -- and it is read in this one place. A malformed
    value is `deps/<pack>/mc.toml:L:C: not a usable version`, exit 2, at its own position and with
    the same code `[package].mc` uses (`toml_err_key_code`): a dependency's manifest is part of
    the environment, not of the program being compiled.
  -- cost: `src/deps.mc` **+39/-5** and `src/pkg.mc` **+11/-4** = **50 added lines, 24 of them
  neither comment nor blank**; **zero new globals** (`build/mc1 limits src/mc.mc` reports
  `globals 446/512` before and after). `tests/pkg/src/zero-0.1.0` and `zero-0.2.0` gained the key;
  no committed hash names them, so no lock and no golden moved for it. The one new public name is
  a TOML key, so the M53 surface inventory moves: `check-freeze` goes **420 -> 421 entries**
  (`toml package.version`, additive, re-recorded with `make record-surface` in this commit, the
  M53 step A rule) and `check-docs` from 35 to **36 TOML keys**.
  Gate: `scripts/check-pkg.sh` § 39, **194 -> 200/200**, offline like everything above it -- the
  reproducer itself (exit 2, the exact sentence, no `checksum mismatch` anywhere, no lock and an
  empty `<libs>`), the checkout updated to 0.2.0 (vendored wins, exit 0, a lock, still nothing
  fetched), `mc build` and `mc pkg verify` naming the version instead of the bytes, a tree with no
  declaration still taking the hash road, and a malformed declaration.
  `make bundle` re-run BEFORE bootstrapping (60 files, raw 1249577 -> LZ 566437, blob 567211 B --
  unchanged by the rebase onto #89, since M52 step B's blob holds only the `src/` rows).
  `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test` 32/32,
  `check-lex`/`check-ast`/`check-asm` 108/108 (#89's corpus), `check-obj` **32/32 identical to the
  frozen seed**, `check-bundle`, `bootstrap` at BOTH fixed points (`mc2.o == mc3.o`, 1449096 B;
  `mc2o.o == mc3o.o`) with the cross-road identity (`mc2o-plain.o == mc2.o`) and **both
  `--dump-asm` diffs between `mc1` and `mc2` empty** (plain and `--opt=1`), `check-surface` 32/32,
  `check-opt`, `test-exe` 32/32, `check-mc`, `check-standalone`, `check-parts`, `check-libroot`,
  `check-toml`, `check-build`, **`check-pkg` 200/200**, `check-tool` 31/31, `check-sysroots`,
  `check-stubs`, `check-limits` **17/17 seed limits under 90%**, `check-freeze` **421 entries**,
  `check-minimal`, `test-linux`/`test-linux-x86_64` and the four `--exe` cells,
  `test-windows`/`test-windows-x86_64`, `check-examples`, `check-lang`, `check-conc`,
  `check-desktop`, `check-float`, `check-wide`, `check-kernel`, `check-avr`, **`test-sandbox`
  73 ok / 0 failed / 1 skipped**, `check-docs` (209 symbols, 50 flags, **36** TOML keys,
  10 directives, 52 samples, 574 links), `site` + `check-site` + `check-site-linux`.
  `scripts/check-inert.sh <mc1 from origin/main> build/mc1`: **33 objects identical on the plain
  road and 33 with `--opt=1`** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for
  `examples/api`, `lang`, `conc`, `desktop` and `kernel` -- nothing in the corpus vendors a tree,
  so nothing the compiler emits could move.
  `make check-linux-host` **RC 0 over all four cells** (aarch64 and x86_64 x musl and gnu), each
  after its own plain AND optimized fixed point, its own cross-road identity and the cross proof
  (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`).
  **The ten goldens rewritten once**, each only after its own criterion: `mc2.sha256`
  `e1dbf531…cab4c1` -> `4ee1f9ea2fdeb25a253fc260a9d132596154894e5240f76fa8d98cc5ea779e03`,
  `mc2-opt.sha256` -> `eb2dffe9b4b08fa18b96a45503a15594c4991c7d8fcc16480bb4afb2521dd0d7` (both by
  `scripts/bootstrap.sh`, after the two empty `--dump-asm` diffs and the two `cmp`s); the four
  Linux ones deleted and re-recorded by `make check-linux-host` -- `mc2-linux-arm64`
  `9b0a6feadae95cbbc6bb9effd63c8b31fcc3ed11591075398a6ff75c478852ce`, `mc2-linux-arm64-opt`
  `02296a3bfd8ec541068a83e87bfc52bece4f870c46ccdd33113fb4e1acb0f259`, `mc2-linux-x86_64`
  `ba46a89ca8e4714d00995d438d6effceefc91cb6f643f89142221371c769216e`, `mc2-linux-x86_64-opt`
  `9f0fda209805be51799eb218b85ac6d4057983b99cfd5934b4a35d6cff668a56`; the four Windows ones
  cross-computed on macOS per `tests/golden/README.md` -- `mc2-windows-arm64`
  `ebdcd720df64942f108f68622cb548186443127a87b3c428d1d23dc58163f4b6` (1484206 B),
  `mc2-windows-arm64-opt`
  `6c74f4c8d94131755ba95034a558be88911b006a7eba0bb3e330ceb49d45f415` (1425390 B),
  `mc2-windows-x86_64`
  `04a0e1ff2cc2277015e72de7e5f3fc751e873397ea9835814e27edbf5a447312` (1540078 B),
  `mc2-windows-x86_64-opt`
  `87828952b1e1b4124f5865a1ef2c39e4d61b9b67dcc657569e470fd1c0a8c29b` (1467894 B), the two plain
  ones also written byte for byte by `build/mc2`.
  Docs: `docs/reference/packages.md` § 2 (the version before the hash, with the message and what
  `from` names) and § 3 (`[package].version`, what it is not), § 8 (two rows) and § 10 (the
  vendored road), `docs/reference/toml.md` (the `package.version` row and its paragraph),
  `docs/reference/diagnostics.md` (two rows), `docs/specs/M44.md`.
- Unsigned comparisons (machine contract **version 6**): **a comparison of `u64` or `uptr` is
  unsigned.** Every integer comparison was signed, so any value with bit 63 set read as negative --
  reported by the teko consumer with a four-line reproducer, and reproduced on `origin/main`
  before anything was written: `u64 one = 1; u64 lim = one << 63; u64 m = 2; if (m >= lim)
  return 3;` exits **3**, and exits **0** after. `stage0/` untouched (2848/3000).
  * **The rule is `cmp_unsigned` in `src/gen_walk.mc` and it is deliberately NARROWER than C's**:
    unsigned iff **neither** operand is a signed type, both are `TK_INT`, and one of them is eight
    bytes wide. Two narrow unsigned operands keep the signed code -- they are zero-filled into
    their slots by the slot invariant, so a signed 64-bit compare of them is already the unsigned
    one -- which is what let **all 32 `tests/*.mc` objects come out byte for byte what they were**
    (`check-obj` 32/32 against the frozen seed). A comparison with an `i64` on either side stays
    **signed**: C would make the whole expression unsigned and turn a negative `i64` into a huge
    number, so the signed side wins and no program that works today changes meaning. `TK_FLOAT`,
    `TK_WIDE` and `TK_OPAQUE` are excluded by the kind test, which is what keeps `<float>`'s `f64`
    (width 8, not signed) and `<i128>`'s `u128` receiving the six codes their own `MTASK_CMP`
    knows. On record: a plain integer literal is `i64`, so `u64 x; x >= K` is a *signed* comparison
    -- correct for every literal below 2^63 -- and a constant with bit 63 set belongs in a `u64`
    variable, because a cast of a literal folds to a literal and `res_lit_type` types it `i64`
    again.
  * **Four codes, no slot and no signature.** `MCOND_ULT ULE UGT UGE` (6..9) after the six;
    `cmp_conds[]` became ONE table of twelve indexed `i + uns * 6` rather than two of six, so the
    seed's `MAXGLOBALS` pays for nothing (**268/512, exactly what it was**). `cmp_cond(op, uns)`;
    `src/gen_resolve.mc`'s "is this token a comparison" asks with `uns = 0`. Every machine maps
    the four in whatever it already dispatches on -- `cond_arm[]` gains `C_LO C_LS C_HI C_HS`
    (2/9/8/3, and `hs^1 == lo`, `hi^1 == ls`, so **both M49 peepholes negate them with the same
    `cc ^ 1`** they always used), `x86_cond[]` gains `2 6 7 3` (`b be a ae`, same low-bit rule),
    `rv_cmp` swaps `slt` for `sltu`, `avr_cmp` swaps `brlt`/`brge` for `brlo`/`brsh` (the C flag
    the `cp`/`cpc` chain leaves). **A code above the table is refused** (`unknown condition`) in
    all four, rather than encoded as the signed twin: the code arrives in an ARGUMENT, so there is
    no null-slot escape. `lib/backend_arm64.mc` needed nothing -- it re-encodes `I_CSET` from
    `ins_imm` generically.
  * **A name collision the change exposed**, and the reason a new core `#define` is surface:
    `lib/i128.mc` defined its own `XC_B`/`XC_AE` ("the core has no name for them") and
    `src/machine_x86_64.mc` now does too -- `lib/i128.mc:567: duplicate #define`, `check-wide`
    35 failures. Fixed by DELETING the module's copies (and `WC_HS`/`WC_LO`, the same duplication
    on the arm64 side, now `C_HS`/`C_LO`): one definition of each condition code, in the core.
    A taught module that spells one of the ten new names gets the same error.
  * **What moved, measured against a `build/mc1` from `origin/main` 4a92c9f.** Every difference in
    the whole tree is one of exactly three substitutions -- `cset ge -> cset hs`, `cset lt -> cset
    lo`, `cset gt -> cset hi` -- with no instruction added, none removed and no register moved.
    `src/mc.mc`: **29 comparisons** (19 + 9 + 1), all of them `uptr` against `uptr`, in
    `skip_space` (6), `lex_next` (5), `lex_hole` (5), `lex_number` (4), `read_char` (2),
    `p_take_lit` (2), `lex_string` (2), `lex_directive` (1) and `tm_cur`/`tm_adv` (1 each) -- the
    lexer's `cp < cend` and TOML's `tm_p < tm_end`. `examples/conc`: **3**, in `chan_check` (2) and
    `chan_send` (1) -- `v < rt_heap` and `v >= rt_heap + RT_ARENA`, the pointer bounds check that
    keeps `chan_send(c, 1)` from reaching `rc_inc(1)`. `examples/kernel`: **2**, both in `_start`
    (`slt -> sltu`), the bss-zeroing and data-copy `uptr p < e` loops; the image stays 3304 bytes
    and QEMU still prints the exact transcript, exit 0. `examples/api`, `examples/lang`,
    `examples/desktop` and `examples/avr`: **identical**.
  * **`check-asm` allow-lists this one divergence and is 108/108** (owner's decision,
    2026-09-15). It compares `mc0 --dump-asm` against `mc1 --dump-asm` over
    `tests/*.mc tests/lib/*.mc src/*.mc`, and the frozen seed IS a compiler with this bug -- it
    cannot be fixed and it will never emit `cset hs`. The 14 files are exactly the translation
    units that reach `src/lex.mc` or `src/toml.mc` (`astdump`, `lexdump`, `tomldump`, `mc_seed`,
    `mc.mc` and the eight `mc_<host>[_slim].mc` entries). Rather than reintroduce the retired M38
    seed-skip mechanism across all 14 (which would retire the seed as the oracle for the whole
    compiler), `scripts/check-asm.sh` now validates, hunk by hunk, that EVERY line these 14 files
    differ on is one of the four single-token substitutions (`ge/lt/gt/le -> hs/lo/hi/ls`) with
    nothing else on the line changed -- any other divergence, on these files or any other, still
    fails the file. The allow-list applies only when `MC0` is the frozen seed by name; on the
    Linux/Windows hosts, where `check-asm` compares two post-fix `.mc` compilers, no substitution
    is ever allowed. The total of allowed pairs -- **371** -- is recorded in
    `tests/golden/seed-cmp.txt` and asserted against on every run, so a fifteenth affected file or
    a fifth substitution shape still fails loudly. `check-obj` (32/32), `check-ast` (108/108) and
    `check-lex` (108/108) are untouched.
  -- cost: **80 added lines in `src/`, 38 of them neither comment nor blank** (`gen_walk.mc`
  +48/-4, `machine_arm64.mc` +18/-3, `machine_x86_64.mc` +14/-1, `gen_resolve.mc` +1/-1), plus
  `lib/i128.mc` +12/-14 and the two example machines +39/-20. **Zero new globals.**
  New: `tests/mc/102-unsigned-cmp.mc` (the reproducer in its branch form, all six operators at bit
  63, `uptr`, a `u8` against a `u64`, a both-narrow control, an `i64` control and the mixed
  `i64`/`u64` rule as a number -- exit 0, stdout `011000111111`; the pre-change compiler AND the
  frozen seed both exit **3**). It is in `tests/mc/` because the seed COMPILES it and miscompiles
  it; `scripts/check-mc.sh` needed no change, since its seed block asserts refusal only for a
  named list. `examples/kernel/tests/sweep.mc` gained `sw_compare_u` (the sweep 285 -> 288 distinct
  instructions, 0 mismatches, `sltu` in all four) and `examples/avr/tests/sweep_a.mc` checks 29-32
  over a `u64` with bit 63 set (simavr 1.6 and 1.7 and QEMU: every check agreed; 680 distinct
  instructions, 0 mismatches).
  **The llvm-mc sweep of every condition-carrying instruction**, over `tests/mc/102` and
  `src/mc.mc` on both roads and all five object formats: arm64 (mach-o) **25 distinct, 0
  mismatches** (`cset hs lo hi ls` and `b.hs`/`b.lo` among them), aarch64 (elf) 8/0, aarch64
  (coff) 8/0, x86_64 (elf) **21/0** (`setb setbe seta setae`, `jb`, `jae`), x86_64 (coff) 10/0.
  `make check` green end to end: `test` 32/32, `check-lex` 108/108,
  `check-ast` 108/108, **`check-asm` 108/108** (the allow-list above), **`check-obj` 32/32
  identical to the frozen seed**, `check-bundle`,
  `bootstrap` at a fixed point on BOTH roads (`mc2.o == mc3.o`, `mc2o.o == mc3o.o`, the
  `--dump-asm` diff between `mc1` and `mc2` **empty** on each, and the cross-road identity
  `mc2o-plain.o == mc2.o`), `check-surface` 154 ok, `check-opt` 76/76 (the null-slot proof holds:
  `kernel.bin` and `avr.elf` identical on both roads), `test-exe` 32/32, `check-mc` 23/23,
  `check-standalone`, `check-parts`, `check-libroot` 11/11, `check-toml` 10/10, `check-build`
  59/59, `check-pkg` 194/194, `check-tool` 31/31, `check-sysroots`, `check-stubs` 9/9,
  `check-limits` **17/17 under 90% (globals 268/512, unchanged)**, `check-minimal`, `test-linux`
  57/57 and `test-linux-x86_64` 53/53, the four `--exe` cells 60/60 + 60/60 + 56/56 + 56/56,
  `test-windows` 59/59 objects + 59 linked and `test-windows-x86_64` 55/55 + 55 linked,
  `test-windows-x86_64-exe` 24/24, `check-examples`, `check-lang` 18, `check-conc` 21,
  `check-desktop`, `check-float` (four sweeps, 0 mismatches), `check-wide`, `check-kernel`
  (QEMU 11.0.1, exit 0), `check-avr`, `test-sandbox` 73 ok / 0 failed, `check-docs` (209 symbols,
  50 flags, 35 TOML keys, 10 directives, 52 samples, 576 links), `check-freeze` (420 entries; the
  ONE line that moved is `machine 5` -> `machine 6`, re-recorded with `--record` in this commit),
  `site` 100 pages + `check-site` + `check-site-linux` 21/21.
  `make check-linux-host` **RC 0 over all four cells** (aarch64 and x86_64 x musl and gnu), each
  after its own `mc2l.o == mc3l.o` and `mc2lo.o == mc3lo.o` and with the cross proof
  (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`) green.
  **Rebased onto `origin/main` 881b3e7** (PR #91, "a vendored tree at another version is named,
  never hashed") before the ten goldens were recorded, so the values below are the merged tree's:
  `mc2.sha256` `f194f5eddfff138fa2067a2306f4ef308e8c5c4d97dcca3e6232f63fc727e09e`, `mc2-opt.sha256`
  `e18aa97b2ec0801bce6f5da22df0c42e12eb76c366ea71781f0389639980ca45` (both by
  `scripts/bootstrap.sh`, after the empty `--dump-asm` diff and the two `cmp`s); the four Linux
  ones recorded by `make check-linux-host` -- `mc2-linux-arm64.sha256`
  `8a386918cadd6ccd352e0bae8e1f50bf6e53a5c2e878f680beacbed37c646514`,
  `mc2-linux-arm64-opt.sha256`
  `e28cb3ad3c7c0c6b599a2215fb8b912fbc0f173459d55d5d1fe0a46ccfa2867a`, `mc2-linux-x86_64.sha256`
  `4dbc7f485f4e3b04d3bce027569ae8ca7fe197b8b6ddc7b3ec2b30a421df5ef8`,
  `mc2-linux-x86_64-opt.sha256`
  `e053b30b1108941f9b6669ada7ec5c1f0947bf593b3ae9a87d5cdfc27c983584`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the four Windows ones
  cross-computed on macOS per `tests/golden/README.md` -- `mc2-windows-arm64.sha256`
  `7ef023d442a168b56fc450582c0df760f1f7c807c5638fb4f5f6145638b7c7e4` (1487709 B),
  `mc2-windows-arm64-opt.sha256`
  `5901bb645f2698807ca2e6954815b2651b160c5729b68e9041161861dab255cd` (1428753 B),
  `mc2-windows-x86_64.sha256`
  `6da18efeac6c5a3c372447455794a8e3bdb48ea1fd1797c0e52b89d12b17c78e` (1543749 B),
  `mc2-windows-x86_64-opt.sha256`
  `e6b76868a9dea753daaa56bdae26fd32dde3abc772187cc93ad7dbf525af6ed3` (1471341 B), the two plain
  ones also written byte for byte by `build/mc2`.
  Docs: `docs/reference/machine.md` (version 6 -- the `Version 5 → 6` paragraph, the ten codes,
  the rule as a fenced block, the three consequences, the AVR paragraph rewritten),
  `docs/reference/language.md` (§ Comparisons, new, with the five-row table and the two
  consequences for a program; the precedence table and the `i32` table row),
  `docs/reference/diagnostics.md` (`unknown condition`),
  `docs/guide/97-a-new-architecture.md` ("Five rules earn their keep": ten codes, map them all,
  refuse the rest).
- Derived machines bound their opcode ranges and take distinct bases (0.16.x; reported by the teko
  consumer with two six-line reproducers): **`<float>` and `<i128>` could not coexist in one taught
  compiler.** The diff against `main` for `src/`, `stage0/` and `tests/golden/` is **empty** -- the
  fix is entirely in `lib/` and `examples/`, and since M52 step B cut every non-`src/` row out of
  the blob, **`src/bundle_data.mc` does not move either and not one of the ten goldens is
  rewritten**.
  A derived machine gives its new instructions opcode numbers above every `I_*`/`X_*` the core
  uses, and those numbers are shared by every machine derived from the same table. Each of the five
  claimants asked `op >= BASE` with **no upper bound**, and two of them had the same base.
  **Reproduced before anything was written**, with `build/mc1` and `origin/main`'s `lib/`:
  * **arm64** -- `lib/machine_arm64_float.mc` claimed `>= 100` and `lib/i128.mc`'s wide band starts
    at 200, so with `i128_init` registered BEFORE `machine_arm64_float_init` the float table
    encoded `WI_UMULH` (205) and `i128 y = x * 3i` died with **SIGILL, exit 132**; the other order
    answered 15. The two orders as compiler entry points differed by nothing else.
  * **x86-64** -- `lib/machine_x86_64_float.mc` and `lib/i128.mc`'s x86 half were **both based at
    100**: `XW_ADC..XW_SETCC` (100..103) are byte for byte `FX_ADD_D..FX_DIV_D`. Float first ->
    `mc: i128/u128 x86: no dump for a wide opcode` on a plain `f64 b = a + a`; wide first -> the
    wide multiply came out as **`mulsd xmm1, xmm0`**, 2 of them and 0 `mul r`, silently wrong with
    no diagnostic at all.
  * **The fix is two rules, written into `docs/reference/machine.md` § 3 as obligations of a
    derived machine.** (1) Bound the band at BOTH ends -- one predicate the encoder, the dump,
    `MTASK_INS_SIZE` and `MTASK_RELOC_*` share (`fa_mine`, `fx_mine`, `wi_mine`, `xw_mine`,
    `hi_mine`, `av_mine`), so the slots cannot disagree about where it ends and a foreign opcode
    always reaches the pristine table. (2) Take a free base from a **registry**, one band per
    module per architecture: 0..99 the bundled machine (`I_*`/`X_*`, 0..52), **100..199 `<float>`**
    (arm64 100..141, x86 100..133), **200..299 `<i128>`/`<u128>`** (arm64 200..209, x86 **100 ->
    200**..203), **300..399 `<f16>`** (arm64 **160 -> 300**..303, out of `<float>`'s band, where it
    was harmless only because those four slots were already bounded) and **400..499
    `examples/avx`** (**240 -> 400**..403, out of `<i128>`'s).
  * **The gate** is `tests/wide/035-coexist.mc` plus two entry points that differ only in the
    registration ORDER, `lib/mc_float_wide.mc` and `lib/mc_wide_float.mc` (both carrying `<float>`
    + its two machines, `<f16>` and `<i128>`/`<u128>`). `scripts/check-wide.sh` **+89/-4**: both
    compilers run it (exit 0, `15 1 0 7 4616189618054758400 1073741824`), the two orders produce
    the **same object** (`cmp`), the arm64 dump carries 2 `umulh` AND 2 float ops in each order,
    the x86_64 and x86_64-win dumps carry `mul` AND `addsd` in each order with no
    `no dump for a wide opcode` anywhere, and `tests/wide/031-f16.mc` still gives `fcvt h16, s16`
    through the same compilers (the third band, arm64-only). It runs on **macos/aarch64,
    linux/aarch64 and linux/x86_64** (Docker, `wide_linux`) and is cross-compiled and LINKED for
    **windows/aarch64 and windows/x86_64**, 5/5 wide objects each. **Teeth measured**: with
    `origin/main`'s `lib/` restored and the same `build/mc1`, the wide-first compiler SIGILLs
    (exit 132) and the float-first one dies on the x86 dump.
  * **Two things the fixture cannot carry, both pre-existing and reported rather than fixed.**
    (a) `<float>` and `<i128>` each keep their own AAPCS64/SysV argument counters and each handles
    a type it does NOT own itself instead of delegating it, so with both loaded a float or a
    16-byte value crossing a FUNCTION BOUNDARY is read out of the wrong register file -- measured
    both ways (`str x0` where `str d0` belongs with i128 on top; a 16-byte parameter in one
    register instead of an even pair with float on top). It is a gap in the machine CONTRACT
    (`MTASK_PARAM` has no way for one machine to tell the next how many registers it consumed),
    not in a band, and the test says so and stays inside it. (b) `<f16>` registers its machine on
    `arm64` alone but registers its four intrinsics unconditionally, so an f16 program compiled
    for x86-64 emits `HI_*` opcodes no x86 machine knows -- `mc: x86 instruction with no dump`,
    and on the encode path the bundled `x86_put` reads its descriptor table out of bounds instead
    of refusing an opcode it does not own. `lib/f16.mc`'s own header already describes the
    fallback (`<f16_rt>`) that does not exist.
  -- cost, the numstat against `main` for `lib/` and `examples/`: `lib/i128.mc` +30/-14,
  `lib/machine_arm64_float.mc` +17/-6, `lib/f16.mc` +17/-9, `lib/machine_x86_64_float.mc` +12/-6,
  `examples/avx/avx.mc` +17/-10 = **93 added lines, 45 removed**, of which **about 35 are code**;
  plus the three new files (`lib/mc_float_wide.mc` 26, `lib/mc_wide_float.mc` 22,
  `tests/wide/035-coexist.mc` 77). Nothing in `src/`, `stage0/` or `tests/golden/`.
  **The llvm-mc sweeps, per machine touched** (`llvm-mc -triple=...`, 0 mismatches everywhere):
  `<float>` arm64 (mach-o) **61**, aarch64 (elf) **70**, x86_64 (elf) **311**, x86_64 (coff)
  **293** (`check-float`); `<i128>` SysV/Win64 **139/147**, `<u128>` **144/151**, the wide ABI
  **122/141**, the narrow cast **102/103**, the coexistence program **130/131** (`check-wide`);
  the coexistence program on arm64 **43**; `<f16>` on arm64 through the coexistence compiler
  **63** (`fcvt h16, s16`, `ldr h16`, `str h17` among them); `examples/avx` **11 distinct VEX
  instructions** (`check-wide`) and **79** over its whole object after the base move.
  `make bundle` re-run before bootstrapping: 60 files, raw 1253365 -> LZ 568311, blob 569085 B --
  **byte for byte the checked-in `src/bundle_data.mc`**, which is what makes the goldens stand.
  `make check` green end to end (**RC 0, zero FAIL**), `make check-linux-host` RC 0 over all four
  cells, and `check-wide` / `check-float` green on every leg with the new cases.
  Docs: `docs/reference/machine.md` § 3 (a new "The opcode bands": the two rules and the registry
  table), `docs/guide/96-a-new-primitive.md` § 3 (the recipe -- pick a free base, bound the band,
  with the predicate spelled out), `docs/reference/bundle.md` (`<float>`, `<f16>` and
  `<i128>`/`<u128>` coexist in either order, with the two entry points and the test named).
- **1.0.0 cut** (2026-09-15): `v1.0.0` tagged from `main` a7966f1 (PR #95 `cmp_cond(op)` restored + arity
  in `check-freeze`, PR #96 the final docs pass), run 34964916762 -- five builds, publish, and the
  **required** canary: teko's verdict `1.0.0.json` status `ok` at 11:54Z (run 34965435282), the release
  promoted, `publish-to-registry` green, 20 assets (ten tarballs + checksums). `MC_CANARY_REQUIRED=true`
  was set before the tag, so from here a `fail` verdict or a 90-minute timeout leaves a release a
  pre-release and the registry row is never written. 0.17.5 (the first green canary since 0.17.2; 0.17.3
  and 0.17.4 stay pre-releases) went out the same morning. The contract from now on is
  `tests/golden/surface.txt` (423 entries: 211 sym with arity, 50 flag, 36 toml, 10 dir, 101 bundle,
  14 lock, machine v6) under `docs/reference/hooks.md` § 8 -- an entry removed or changed is a MAJOR.
  The registry pin follows (`minicompiler/mc-registry` PR #34, six spellings, autoDeploy on merge).
- A taught compiler can say its own name (0.16.x; reported with a released `mc-php` 0.2.0 binary,
  which is `mc` plus one Tier 3 module): **`program(name, version)`**, one registration a module
  makes from `user_init()` or a recreated compiler from its own `main()`. `stage0/` untouched
  (2848/3000, `/usr/bin/git diff origin/main -- stage0/` empty). Measured on that binary before
  anything was written: `mc-php --version` -> `mc 1.1.0` (the wrong tool, and a version belonging
  to something else), `mc-php` with no argument -> sixteen usage lines naming mc, and every
  diagnostic prefixed `mc: `. Every taught compiler shipped as a binary has it -- mc-php, teko's
  `tekoc`, and each of this repository's own `examples/*` that produce a compiler.
  * **The names.** `program(uptr name, uptr version)` registers; `program_name()` and
    `program_version()` read. Three surface entries. The first draft had TWO registrations
    (`program_name(name)` / `program_version(ver)`) with readers `prog_name`/`prog_version`, and
    the review killed both halves of that: a reader must not truncate its writer (no other
    registry does), and two calls made **a half registration expressible**, which is a plausible
    lie -- a name with no version printed `mc-php 0.0.0-dev`, attributing mc's dev sentinel to
    another tool, and a version with no name printed `mc 0.2.0` above `mc 0.0.0-dev`, one program
    name carrying two versions. One call makes both unrepresentable; a 0 in either argument is
    `program: a name and a version are required`. A module that wants the rename and mc's own
    version writes `program("myc", mc_version())`.
  * **`mc_version()` is NOT touched, and the two uses cannot share one accessor.** `mc_version()`
    is the version of the COMPILER this binary IS: `[package].mc` (`src/deps.mc`),
    `<libs>/mc/v<version>/` (`dp_mc_root`), the tree `mc build` stages beside a taught compiler
    (`drv_stage_libroot`), the one the sandbox binds (`sb_lib_box`), `mc install`, `mc upgrade`.
    All fourteen call sites still call it -- the review checked every one -- and only `--version`,
    the usage and the diagnostic prefix read the registered pair.
  * **All 27 prefix sites, not the 8 a grep found.** The first draft converted the two-call
    spelling (`out_str(2, "mc: "); out_str(2, msg);`) and missed the one-call majority,
    `out_str(2, "mc: <message>")`: `src/sysroot.mc` (10), `src/pkg.mc` (7), `src/sandbox.mc:906`,
    `src/upgrade.mc:367`. The review reproduced the consequence -- a recreated compiler printing
    `myc: cannot open:` from `dep_die` and `mc: unknown target:` from `src/sysroot.mc:374`, two
    names from one binary, with `sb_unsupported` printing either name depending on `host_os()`.
    All 27 now go through `out_prog()`; `grep -rn 'out_str(2, "mc' src/` is empty.
  * **`--version`, `--host` and the usage are answered at the same point, after `user_init()`.**
    `user_init()` cannot move earlier: M11 freezes `K_U8..K_EXTERN` at `tok_init()`, and `lex_init`
    opens with `nopen = 0`, which would throw away a source a `user_init` had pushed (the review
    confirmed that second constraint is real and independent of M11). So the answer moved instead,
    onto a path that runs `tok_init()`, pushes an EMPTY in-memory source (what gives a pushing
    `user_init` somewhere to push), then `core_types_init()` and `user_init()`. `usage()` rides
    with them at no extra cost -- the program with no argument is the FIRST thing a user types.
    Two consequences, both deliberate and both documented in `docs/reference/cli.md`: the whole
    argument list is now VALIDATED first, so `mc --version --bogus` reports the bad flag instead
    of ignoring it (same for `--version -o`, `--version a.mc b.mc`, `--version --opt=2`,
    `--version --libc=xx`); and given both, the LAST one wins -- `mc --version --host` prints the
    host, `mc --host --version` the version -- the rule every other flag in that loop follows,
    where before each returned where it was read.
  * **The subcommand usage lines** are literals in `src/core_build.mc`, `src/core_pkg.mc` and
    `src/core_sandbox.mc` (`       mc pkg ...`). `sub_use_print` substitutes the FIRST standalone
    `mc` word on each line at PRINT time -- registration time is too early, every part's `*_init`
    runs before `mc_main` -- so `mc.toml` and `<mc/core>` inside a line are left alone and a
    module that already writes its own name keeps it.
  * **`--version` prints TWO lines for a RENAMED compiler**, its own then the mc under it. The
    test is on the NAME and not on "did anything register", so one binary can never print two
    versions under one name: `program("mc", "1.2.3")` prints its one line and no contradiction.
  * **What a `user_init()` registration reaches, written down**: every message from there on, the
    whole compile path, plus `--version`, `--host` and the usage. Not the argument loop's own
    refusals, not the entry file's `cannot open`, not any subcommand (dispatched before the loop).
    A compiler that wants those too registers from its own `main()` -- `lib/mc_prognamemain.mc` is
    `src/main.mc` with one line added and is the gate for it.
  -- cost in `src/`: **201 added lines, 97 of them neither comment nor blank** -- `arena.mc`
  +51/15, `cli.mc` +73/30, `hooks.mc` +38/24, `version.mc` +15/4 is the new logic (73 code lines),
  and the other 24 are the one-call prefix sites rewritten in place (`sysroot.mc` 10, `pkg.mc` 8,
  `sandbox.mc` 3, `deps.mc` 1, `fetch.mc` 1, `upgrade.mc` 1). **Zero new globals beyond the
  two the feature is** -- `check-limits` reports the same `globals 268/512 (52%)` row on
  `src/mc_seed.mc`. New fixtures `lib/user_progname.mc`, `lib/mc_progname.mc` (the `user_init`
  road) and `lib/mc_prognamemain.mc` (the `main()` road), deliberately NOT in `tools/bundle.list`
  (the M41 precedent for check-script-only modules). `scripts/check-surface.sh` +100: five cases --
  `--version` from both compilers, all 15 usage lines, a diagnostic from both, ONE name per binary
  across `arena.mc`/`sysroot.mc`/`sandbox.mc` on the `main()` road, and the `--version`/`--host`
  ordering. `scripts/surface-extract.sh` gained the three names as exact entries.
  -- `make bundle` re-run BEFORE bootstrapping (60 files, raw 1266559 -> LZ 574788, blob 575562 B).
  `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test` 32/32,
  `check-lex`/`check-ast`/`check-asm` **108/108** with `tests/golden/seed-cmp.txt` **unmoved at
  407** (the change adds no comparison), `check-obj` **32/32 identical to the frozen seed**,
  `check-bundle`, `bootstrap` at BOTH fixed points with the cross-road identity and **both
  `--dump-asm` diffs between `mc1` and `mc2` empty**, `check-surface` 32/32 + the five new cases +
  inert, `check-opt`, `test-exe` 32/32, `check-mc`, `check-standalone`, `check-parts`,
  `check-libroot` 11/11, `check-toml`, `check-build`, `check-pkg`, `check-tool`, `check-stubs`,
  `check-sysroots`, `check-limits` **17/17 seed limits under 90%**, `check-minimal`,
  `test-windows` / `test-windows-x86_64`, `check-examples`, `check-lang`, `check-conc`,
  `check-desktop`, `check-float`, `check-wide`, `check-kernel`, `test-sandbox` **73 ok / 0 failed /
  1 skipped**, `check-docs` (**274 symbols**, 50 flags, 36 TOML keys, 10 directives, 52 samples,
  602 links), **`check-freeze` 486 entries** (274 sym, +3 over main, re-recorded in this commit),
  `site` + `check-site`.
  `scripts/check-inert.sh <mc1 from origin/main 507513a> build/mc1`: **33 objects identical on the
  plain road and 33 with `--opt=1`** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts
  for `examples/api`, `lang`, `conc`, `desktop` and `kernel` through the taught compiler each side
  builds -- nothing in the corpus registers a name, so nothing the compiler emits could move.
  `make check-linux-host` **RC 0 over all four cells** (aarch64 and x86_64 x musl and gnu), each
  after its own plain AND optimized fixed point and with the cross proof
  (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`) green.
  **All ten goldens rewritten once**, each only after its own criterion: `mc2.sha256`
  `42359f24ae172fb991f2d205a69d65b7b43e89ea03b007b887766ac56160c6b2` and `mc2-opt.sha256`
  `0a838e11dccf54f93f0f3d69f2e13249152ccd271b131cae22cf7943f357a8e6` (recorded by
  `scripts/bootstrap.sh` after the two empty `--dump-asm` diffs and the two `cmp`s); the four Linux
  ones deleted and re-recorded by `make check-linux-host` -- `mc2-linux-arm64`
  `ada299fd0995ba3fe1484d95caaefeaa5a9cf6607d384a08752f79509dc8ebba`, `mc2-linux-arm64-opt`
  `e4dec23d256840df1749acc7af269471c0f75e0b097306a709041e91ea5e3493`, `mc2-linux-x86_64`
  `d78d3827ef47296cd05eb32b9233ac9bcd3cd5b40ba8e2cd62d697d264096781`, `mc2-linux-x86_64-opt`
  `bdf4ded167d7b25a972789cf91f42b30487751d53cdde297957613e06c480a08`; the four Windows ones
  cross-computed on macOS per `tests/golden/README.md` -- `mc2-windows-arm64`
  `a7e5069283b2ee26a925f3ba465df8e8aaa1948bc94b1e130214917706f61f17` (1500665 B),
  `mc2-windows-arm64-opt`
  `3faab76d822f3bb115bd74fad2cb524ea9b776a7bc652f613c7a044a1203a5cd` (1441577 B),
  `mc2-windows-x86_64`
  `030da30b78611735d6073cc3e34d5e43d99c5d02306e941d6e6e8c2656997950` (1557021 B),
  `mc2-windows-x86_64-opt`
  `0a98b883870a0910b117ee262f420ca13ec6b57c34b17a9a89bb15f146dd810b` (1484389 B), the two plain
  ones also written byte for byte by `build/mc2`.
  Docs: `docs/reference/hooks.md` § 7 (the registration, the two readers, why one call, what
  `mc_version()` keeps meaning, the two-line `--version`, and the two roads with what each
  reaches), `docs/reference/cli.md` (`--version`'s row, the taught example, the validation and
  ordering consequences), `docs/reference/diagnostics.md` (`mc` is the PROGRAM's name, one helper,
  which registration road reaches which messages), plus the stale counts in `hooks.md` § 8 and
  `tests/golden/README.md` (423/211 by two earlier PRs) brought to 486/274.
- Next (rewritten 2026-09-15, the final docs pass before 1.0.0): **M49, M50, M52 and M53's own
  steps A-C are all closed and shipped** — the register allocator/peephole/hoisting on all five
  hosts (1.30x `clang -O2` on the workload, AArch64), the reproducible bench cell on three GitHub
  Actions cells, the installable-library cut, and the surface freeze + canary
  (`tests/golden/surface.txt`, 423 entries; `docs/reference/hooks.md` § 8;
  `.github/workflows/release.yml`'s `promote` job). **M42 step 2** (PE `--exe` for
  windows/x86_64, no `lld-link`) landed long before all of the above, is CI-gated on the Windows
  runners as required, and this entry corrects an earlier version of this line that still listed
  it as pending.
  **Current: tag `v0.17.4`, one patch ahead of it on `main`** (the f16 fix, PR #94). M53's own gate
  (§ 13) is not a step this repository ships: it closes when teko's gap list reaches zero, it
  self-hosts on its five legs and publishes `teko_std` asking for no new hook — a fact of the
  OTHER repository this side cannot certify, only watch for. Until then, **0.17.x takes bug fixes
  only** (`docs/specs/M53.md` § 7, D19; several of the 0.17.1-0.17.4 patches above are exactly
  that, reported by teko and reproduced here before being fixed) and the canary stays advisory.
  The real next action on this side is operational, not a milestone: once that gap list is
  verified empty, set `vars.MC_CANARY_REQUIRED=true` and cut **1.0.0** as a `release:major` tag
  (`docs/plan.md` § "What 1.0.0 promises, and what it does not").
  After 1.0.0 (or sooner, if 0.17.x's "bug fixes only" rule allows it — M51 touches no compiler
  surface): **M51**, the `<http>` library as a registry PACKAGE and not a bundle row (M52 § 9.3),
  carrying the `mc-forkka` fork-per-connection-keep-alive shape (the registry server's own move
  off fork-per-request is `minicompiler/mc-registry`'s work, not this repository's); the
  **site + registry server, M47 S4-S6**, ongoing in `minicompiler/mc-registry`; **M43 Layer 2**;
  **M46** (static linking) only on the owner's request; and the backlog, **M13** (sizing a
  program's memory at compile time — the fixed 4 MiB arena in `examples/api/lib/rt.mc` is one
  more motivating case) and **M18** (Linux x86 32-bit).
  Update this section when each milestone closes.
- i18n done (2026-09-03): the repository is fully in English — diagnostics, program/script
  output, identifiers, comments, and docs (`docs/*.md`, `docs/specs/*.md`, `CLAUDE.md`,
  `.claude/agents/*.md` re-synced to match `scripts/i18n-map.tsv`/`scripts/i18n-idents.tsv`).
  Language keywords were already English and untouched.
- CI (2026-09-03): `.github/workflows/` ci/tag/release/site; first run green (`make check` on macos-15 in 41 s, Linux arm64 suite native on ubuntu-24.04-arm in 28 s); site live at https://minicompiler.dev (rendered by `mcsite` since M27). See `docs/ci.md`.
- Comparison benchmark published (2026-09-06, `docs/comparison.md`, `bench/`): `mc` measured
  against C, Go, Zig, Rust and C# on one Mac (Apple M4, macOS 26.6.2) — an integer workload
  (LCG/xorshift, a sieve, recursive `fib`) compiled and run by all six, and nine minimal HTTP
  servers (three of them `mc`, at three concurrency shapes) under `ab`/`oha`. Headline: **4.1 ms**
  compile, a **33,461-byte** executable (3 bytes off `clang -O2`), a **1.2 MB** single-file
  toolchain with no linker — and, on the other side, run time at `clang -O0` level (2.2x behind
  `clang -O2`) because `mc` folds constants and does nothing else: no register allocator, no
  peephole, no inlining. The keep-alive HTTP shape (`mc-forkka`, fork per connection) lands at
  120k req/s in the Rust/Zig/Go/Kestrel band; fork-per-**request** (`mc-fork1`, the old registry
  server shape) costs 28x the CPU for a fifth of the throughput. Caveat on record and repeated on
  the page itself: one shared host, ~20% run-to-run variance on a few rows
  (`bench/http/RESULTS.md` § Notes 13), and the workload run's own `mc` binary reports a stale
  tree label (`e5a1643`) that does not match its measured size — the actual build was verified
  against current `main` (`0648e1a` / `v0.15.13`) by rebuilding both and comparing bytes.
  `bench/` holds the sources (one directory per language, servers under `bench/http/`, a portable
  `bench/run.sh` behind `make bench`, not in `make check`) and the raw `RESULTS.md`/`results.json`
  from this run. Three follow-up milestones opened from the gap this exposed: **M49** (optimizer),
  **M50** (reproducible bench cell), **M51** (`<http>` library) — see the Next line above and
  `docs/plan.md`. The docs landing page and the site's home page both link to `comparison.md` with
  the three headline numbers; `site/site.toml` gained `[site] home` (docs/home-extra.md) and
  `comparison` in the Internals section's reading order.
  Second HTTP set merged (2026-09-06, same host, back to back with the first): eight more servers
  (Node single-process and `cluster`, Rust `axum`, Python stdlib and uvicorn, Ruby WEBrick and
  Puma, PHP's built-in server) under the same contract and harness — sources in `bench/http2/`,
  full method and numbers in `bench/http2/RESULTS.md`/`results.json`, merged into the three HTTP
  tables in `docs/comparison.md`. `py-stdlib`'s `ab -k` run failed on all 3 attempts (0 requests
  in warm-up); its `oha` keep-alive and its no-keep-alive `ab` runs both succeeded, so the failure
  is specific to that combination, not to keep-alive itself.
  First soak hour recorded (2026-09-06, run 34062566194, tree `7d01b3a`): `docs/comparison.md`
  § "The hour under load" — 13 of 14 servers ran their full hour at a fixed 3,000 req/s, one
  GitHub Actions runner each; every compiled/AOT server (`mc` both shapes, C, Go, Rust both, Zig)
  held RSS flat to a few KiB, C# JIT and Ruby's Puma flat by the drift rule despite a small
  non-zero slope, while C# NativeAOT (+5.9%), Node (both shapes, +30%/+8%) and PHP's built-in
  server (+295% over the hour) drifted by it. `py-uvicorn` did not run: its own `UVICORN_VERSION`
  env var collided with uvicorn's `click` `auto_envvar_prefix="UVICORN"`, read as the value of
  `--version`, a boolean — fixed by renaming it `PY_UVICORN_VERSION` in `bench-soak.yml`; the
  hour has not been re-run. Results archived at `bench/soak/results/2026-09-06-34062566194/`;
  `rss.svg`/`cpu.svg` embedded in the page from `site/static/` (the one way a doc page gets a
  real `<img>` past mcsite's own link check, not a GitHub blob link) — `scripts/check-docs.sh`
  gained the `/static/*` -> `site/static/*` mapping its naive relative-link scan needed to see
  them.
- The seed compares `src/` and `tests/`, never `lib/` (owner's decision, 2026-09-15): `mc0` is a
  differential oracle for the parts of the tree that MUST track it (`src/`, and the corpus under
  `tests/`), and a library taught from the surface has no reason to be compared against a compiler
  that has never heard of Tier 3/4 — the comparison only pressed the seed's fixed `MAXFUNCS`
  (`lib/mc_i128.mc` sits at 2047/2048), which is what forced `// seed-skip:`/`// lex-skip:` headers
  onto `lib/mc_float.mc`, `lib/mc_f16.mc`, `lib/sys_windows_host.mc` and
  `lib/syntax_demo_test.mc` in the first place. `scripts/check-lex.sh`, `scripts/check-ast.sh` and
  `scripts/check-asm.sh` dropped `lib/*.mc` from their corpus glob (now `tests/*.mc tests/lib/*.mc
  src/*.mc`); the `seed-skip`/`lex-skip` escape mechanism itself is removed from all three scripts
  too, since it had no remaining user in `tests/` or `src/` (the last four carriers were all
  libraries) — a future `src/`- or `tests/`-only file that needs it can reintroduce the header and
  the two-line `sed` reader from git history. The four headers above are deleted from `lib/`, with
  their substantive explanations (the `MAXFUNCS` count, the `.` lexeme clash) kept as plain
  comments where they still teach something. No other script compiles a `lib/*.mc` file with `mc0`
  for comparison (`check-surface.sh`/`check-float.sh`/`check-wide.sh` build their taught compilers
  with `mc_seed`/`mc1`, never `mc0`, and `check-surface.sh`'s two direct `$mc0` uses are over
  `tests/*.mc` only). `src/`, `stage0/` and `tests/golden/` untouched by this change; `make
  check-docs` and `make check-freeze` unaffected (both are green: 209 symbols / 50 flags / 35 TOML
  keys / 10 directives / 52 samples / 570 links; 420 frozen entries).
  Counts: `check-lex` **177/177 (5 skipped) -> 108/108 (0 skipped)**, `check-ast`/`check-asm`
  **178/178 (4 skipped) -> 108/108 (0 skipped)**.
- `<f16>` on a machine it does not drive, and a bundled machine that refuses a foreign opcode
  (the two halves of the defect PR #93 reported and did not fix). `stage0/` untouched
  (`/usr/bin/git diff origin/main -- stage0/` empty); the whole compiled change in `src/` is
  **35 added lines, 16 of them neither comment nor blank**, and `lib/f16.mc` is +154/-11.
  1. **`<f16>` registered its machine on `arm64` alone but its four intrinsics unconditionally.**
     Reproduced first, with a `mc-f16` built from `origin/main` 8a03803: an f16 program compiled
     for linux/x86_64 through `mc build` **built and linked with no diagnostic at all** and then
     died in Docker with **SIGSEGV, exit 139** -- `llvm-objdump` shows `3e 4c 0f 00 08 strw
     %ds:(%rax)`, a system instruction, where `str h` belonged, because `x86_desc` is INDEXED by
     the opcode and `HI_STR_H` is 303. The dump road said `x86 instruction with no dump`.
     The promise `lib/f16.mc`'s own header made -- "on any other machine they are NOT registered,
     and the identically-named ordinary functions are called instead" -- is now implemented, in
     the shape `docs/specs/M24.md` § Generality asks for ("the module pushes as a second source",
     `p_push_source`, the `sd_rt` pattern) rather than the `<f16_rt>` include the header invented,
     because a program cannot include a file on one target and not on another.
     **The KIND is one of the two roads' differences, and that is the point**: `TK_FLOAT` is a
     claim about the MACHINE, so it is registered only where this module has one; elsewhere `f16`
     is `TK_INT` of width 2 -- two bytes the core moves, with no float machine involved and no
     8-byte `movsd` over a 2-byte global -- which is also the only shape in which the fallback can
     be WRITTEN (`fx_cast`/`fx_need_ds` refuse a width-2 float, so with `TK_FLOAT` there is no bit
     bridge between a half and its 16 bits and `ldf16`/`stf16` are not expressible in `mc`).
     The road is chosen from `[target].arch` -- what `mc build` has already parsed when
     `user_init` runs (M39.5) -- falling back to the host; `--machine=`/`--backend=` are read
     AFTER `user_init` (`src/cli.mc`) and cannot be seen from there, which is exactly the case
     half 2 turns into a diagnostic.
     **The fallback is bit-exact against the hardware, measured both directions**: the same source
     compiled by the same compiler for macos/aarch64 (`fcvt`) and for linux/x86_64 (softfloat),
     dumping every result -- **768192 f32 inputs** (scattered over the whole 32-bit space, every
     NaN payload of both signs, the subnormal edge and the overflow edge) and **all 65536 halves**
     back to f32: **0 differing**. Two rounding facts came out of that differential and are in the
     code: `fcvt h, s` propagates a NaN payload and quietens it (`sign | 0x7e00 | ((m >> 13) &
     0x1ff)`, not a bare quiet NaN), and `fcvt s, h` sets the f32 quiet bit on a signaling half
     (1022 of the 65536 disagreed before that line). Ties-to-even -- M24's acceptance case, 1 +
     2^-11 -> `0x3c00` -- is what `tests/wide/031-f16.mc` already pinned and what both roads print.
  2. **A bundled machine refuses an opcode nobody claims, instead of indexing past its table.**
     The general form of #93's band rule seen from the bundled side. `a64_claim(op)` (`op < I_COUNT`,
     new: 53) at the head of `a64_ins_size`, `encode` and `dump_ins`; `x86_claim(op)`
     (`op < X_COUNT`, 52) in `x86_d` and `x86_name_at`, the two accessors every reader goes through
     (`x86_form`, the five column reads in `x86_put` -- `MTASK_ENCODE` and, over the scratch
     buffer, `MTASK_INS_SIZE` -- and `x86_dump`). **Five call sites, and the `--dump-asm` delta
     over `src/mc.mc` is exactly those**: the same compiler on the old and the new tree adds
     `_a64_claim` and `_x86_claim` (52 instructions between them), 3 `bl _a64_claim`, 2
     `bl _x86_claim`, and nothing else but `l_strN` index shifts.
     `mc: opcode 303 is not x86-64's: no machine claims it` / `opcode 400 is not arm64's: ...` --
     the second is `examples/avx` (x86-64 only, intrinsics unconditional) dumped on the host's
     arm64 machine, which said `instruction with no dump` before, naming neither.
     **`check-asm` is 108/108 identical with the #92 allow-list unchanged** (`seed-cmp.txt` still
     371): both compilers compile the same source, and the guard compares two `i64`s, so it adds
     no signed/unsigned divergence.
  Gate: `scripts/check-wide.sh` (+95/-1) -- `tests/wide/031-f16.mc` joins the `--build-only`
  corpus, so the CI legs RUN it on linux/aarch64, linux/x86_64, windows/aarch64 and
  windows/x86_64; locally it is RUN in Docker on both Linux architectures (same stdout as the
  native hardware road) and cross-compiled and LINKED with `lld-link` for both Windows ones. Two
  assertions say the two roads really are two roads -- the x86-64 object CALLS `f32_to_f16` and
  the aarch64 object has no such symbol -- and three `guard_case`s pin the refusals verbatim.
  -- `make bundle` re-run before bootstrapping (60 files, raw 1255250 -> LZ 569393, blob
  570167 B). `make check` green end to end (**RC 0**): `check-lex`/`check-ast`/`check-asm`
  **108/108**, `check-obj` **32/32 identical to the frozen seed**, both fixed points
  (`mc2.o == mc3.o`, 1454408 B, `mc2o.o == mc3o.o`, and the cross-road identity), the `--dump-asm`
  diff between `mc1` and `mc2` **empty**, `check-wide` ok, `check-float` ok on all five legs,
  `check-freeze` **421 entries unmoved**, `check-docs` 209 symbols / 581 links, `check-pkg` 200/200, `check-limits` 17/17, `test-sandbox` 73 ok / 0 failed / 1 skipped.
  `scripts/check-inert.sh <mc1 from origin/main 8a03803> build/mc1`: **33 objects identical on
  both roads** (`tests/*.mc` and `src/mc.mc`) plus byte-identical `examples/api`, `lang`, `conc`,
  `desktop` and `kernel`. `make check-linux-host` RC 0 over all four cells (aarch64 musl 57/57 +
  31/31 via `--exe`, aarch64 gnu 58/58, x86_64 musl 53/53 + 29/29, x86_64 gnu 54/54), each after
  its own fixed point and with the cross proof green. No new instruction form, so the sweeps are
  unchanged (`check-wide`: 139/147/144/151/122/141/102/103/130/131 and 11 VEX, 0 mismatches).
  **All ten goldens rewritten once**, each after its own criterion: `mc2.sha256`
  `f194f5ed...27e09e` -> `9ccd1c335346820881792308d532a189b7bae6d6ceba8f6d154fd4ada2879489`,
  `mc2-opt.sha256` `dd42fe0af28927ffa362ca5277d1b57bb2ec9770796c2179b7abab0e07f25729`; the four
  Linux ones deleted and re-recorded by `make check-linux-host` --
  `mc2-linux-arm64` `19386bdb579141c75a3e7aa7dce1b3b94f1f523ab6ad24cba9ab65892c14f55b`,
  `mc2-linux-arm64-opt` `27c40fe2a4e792fe86fa7fbd7d3439d30538b6e2a4669f877c5e35f60bf2c99a`,
  `mc2-linux-x86_64` `6eb6eb4ca829059be0bb144552c09c8158557d53eece55bff1ff3b280da5e233`,
  `mc2-linux-x86_64-opt` `651496c8c30fae4eccb3b2a1b2e94ea2670261e6a14b4b21c4d20e2e33fe5401`;
  the four Windows ones cross-computed per `tests/golden/README.md` --
  `mc2-windows-arm64` `bb8a138488ab2c152ca61bf81b01645e93635412984d73d676af3fc15cc2451c`,
  `mc2-windows-arm64-opt` `986d0104304189934c417dce65622577dbf02fc0da7f4b8d09aeddab85fed7ee`,
  `mc2-windows-x86_64` `22eb73798a91e640e2166b88d885bb7416d1634fec9b4b2363564ad810ba32dd`,
  `mc2-windows-x86_64-opt` `d236b3267e15102e1eb4b519bcfe990e8006dcad155841a9e32ae031931f9c47`.
  Docs: `docs/reference/bundle.md` § `<f16>` (what it promises per architecture and what the
  fallback costs), `docs/reference/machine.md` § The opcode bands (the bundled side's refusal),
  `docs/reference/diagnostics.md`, `docs/guide/96-a-new-primitive.md`.
- `cmp_cond(op)` restored, and `check-freeze` records each symbol's arity (the first freeze
  regression; `docs/specs/M53.md` § Implementation notes -- the first freeze regression (#92) and
  the arity column). `stage0/` untouched (2848/3000).
  1. **The regression.** PR #92 (machine contract v6, unsigned comparisons) needed the unsigned
     half of the comparison table and gave the EXISTING function the parameter: `cmp_cond(op)`
     became `cmp_cond(op, uns)`. The consumer's `teko_typeof.tk:318` is
     `if (cmp_cond(op) >= 0) return TY_I64;` -- one argument -- so every taught compiler built on
     0.17.3/0.17.4 died with `wrong number of arguments` before it compiled a line of its own
     language. The canary held both as pre-releases; this is the first regression the canary caught
     and the gates did not. `docs/reference/hooks.md` § 8 already forbade it -- a signature change
     is a rename -- and nothing enforced it.
  2. **The fix is the deprecation lane's steps 1 and 2**: the new behaviour got a new name,
     `cmp_cond_of(op, uns)` in `src/gen_walk.mc`, and `cmp_cond(op)` is the one-line wrapper
     `cmp_cond_of(op, 0)` it always was in meaning -- not a deprecated alias, so no marker and no
     version are written. `gen_binary` asks `cmp_cond_of(op, cmp_unsigned(...))` and `res_binary`
     asks `cmp_cond(op)`, the signed half by definition; v6 is untouched.
     **4 added code lines in `src/`** (`gen_walk.mc` +15/-5, `gen_resolve.mc` +1/-1), one of them
     the new wrapper and three renamed call sites. **Zero new globals** -- `check-limits` reports
     `globals 268/512 (52%)` before and after; `funcs` 924 -> 925.
  3. **Two gate holes, both closed.** `cmp_cond` was not in `tests/golden/surface.txt` at all (the
     `sym` regex reaches a name through one of 17 prefixes or an exact-name list, and `cmp_` is
     neither), and the inventory recorded NAMES, so even a listed name could grow a parameter
     silently. `scripts/surface-extract.sh` now emits `sym<TAB>name<TAB>arity` -- the parameter
     count read from the definition's own `(...)` in `src/*.mc`, 0 for `()`, otherwise commas + 1 --
     and `cmp_cond`/`cmp_cond_of` join the exact-name list. `scripts/check-freeze.sh` gained a
     THIRD verdict beside removed and added, and the only one whose remedy is not "re-record":
     `changed: sym cmp_cond 1->2` with `FAIL a public function's parameter list is frozen: add a
     new name instead`. The deprecation marker is found by its TEXT now and not by its column, so
     it sits after the arity on a `sym` line and after the name on any other.
     `scripts/check-docs.sh` needed no edit: it asks the extractor for a single kind, and that road
     prints the name column alone.
  4. **Both teeth measured.** With #92's two-parameter `cmp_cond` the gate prints exactly
     `changed: sym cmp_cond 1->2` and exits 1; with the restored one, `ok freeze: 423 entries
     (211 sym, 50 flag, 36 toml, 10 dir, 101 bundle, 14 lock, 1 machine)`. And the consumer's shape
     is a gate now, not a report: `lib/user_cmpcond.mc` is `teko_typeof.tk:318` transliterated, and
     `scripts/check-surface.sh` builds a taught compiler from `lib/mc_cmpcond.mc` and RUNS its
     `pass`, which asserts the signed condition, the -1 for a non-comparison and the unsigned twin
     under the new name (`ok cmp_cond(op): one argument, the signed condition, and cmp_cond_of for
     the unsigned half`). Against `origin/main`'s compiler the same file is
     `lib/user_cmpcond.mc:16: wrong number of arguments`, exit 1. The two fixtures are NOT in
     `tools/bundle.list` (the M41 precedent for check-script-only modules).
  5. **The inventory moved 420 -> 423 entries**: 209 `sym` lines gaining a column, plus the two new
     names. No name in `src/` is defined with two different parameter counts (a prototype and its
     definition agree), so the re-record is exactly that. `seed-cmp.txt` did NOT move: the restored
     wrapper contains no comparison and the allow-listed total is still **371**
     (27 + 25 + 29 x 10 + 27 + 2 over the fourteen units that reach `src/lex.mc` or `src/toml.mc`).
  -- `make bundle` re-run BEFORE bootstrapping (60 files, raw 1253957 -> LZ 568589, blob 569363 B).
  `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test` 32/32,
  `check-lex`/`check-ast`/`check-asm` **108/108 files identical** (the #92 allow-list unmoved),
  `check-obj` **32/32 identical to the frozen seed**, `check-bundle` (reproducible + fresh),
  `bootstrap` at BOTH fixed points (`mc2.o == mc3.o` 1452880 B, `mc2o.o == mc3o.o` 1394496 B, the
  cross-road identity `mc2o-plain.o == mc2.o`, and the `--dump-asm` diff between `mc1` and `mc2`
  **empty on both roads**), `check-surface` 32/32 + the new `cmp_cond(op)` case, `test-exe` 32/32,
  `check-mc` 23/23, `check-standalone`, `check-parts`, `check-toml`, `check-build`, `check-pkg`,
  `check-tool`, `check-limits` **17/17 under 90%**, `test-linux` 57/57 and 53/53, the four `--exe`
  cells 60/60 + 60/60 + 56/56 + 56/56, `test-windows` and `test-windows-x86_64` (24/24 PE),
  `check-examples`, `check-lang`, `check-conc`, `check-desktop`, `check-float`, `check-wide`,
  `check-kernel`, `check-avr`, `test-sandbox` 73 ok / 0 failed / 1 skipped, `check-docs`
  (**211 symbols**, 50 flags, 36 toml keys, 10 directives, 52 samples, 579 links), **`check-freeze`
  423 entries**, `site` + `check-site`. `make check-linux-host` RC 0 over all four cells
  (aarch64 musl 57/57 + `test-exe` 31/31, aarch64 gnu 58/58 native, x86_64 musl 53/53 + 29/29,
  x86_64 gnu 54/54 native), each after its own `mc2l.o == mc3l.o` and with the cross proof
  (`mc2l --backend=macho src/mc.mc` byte for byte the macOS `build/mc2.o`) green.
  `scripts/check-inert.sh <mc1 from origin/main 8a03803> build/mc1`: **33 objects identical on both
  roads** (`tests/*.mc` and `src/mc.mc`) plus byte-identical artefacts for `examples/api`, `lang`,
  `conc`, `desktop` and `kernel` -- a rename of an internal call site emits no different byte.
  The **ten goldens** rewritten once, each only after its own criterion: `mc2.sha256`
  `344dd4beb1f602d791c8b92bf94a1fb28d0eb32e96eead32564a187cd2e80df7` and `mc2-opt.sha256`
  `e457a3520403a6951bb0267acc2ce0acf08c8a7a93c9f4111daabde40fa9aa13` (after the two empty
  `--dump-asm` diffs and the two `cmp`s); the four Linux ones deleted and re-recorded by
  `make check-linux-host` -- `mc2-linux-arm64` `2dd98ad8...7ff1c1e6`, `mc2-linux-arm64-opt`
  `3a9ad8f9...0edc3a0c`, `mc2-linux-x86_64` `deebd535...43e7458b`, `mc2-linux-x86_64-opt`
  `5e28b1cd...52a33459a7`; the four Windows ones cross-computed per `tests/golden/README.md` --
  `mc2-windows-arm64` `c26637d7...b6f7295b` (1488087 B), `mc2-windows-x86_64` `a3a3bf81...f0bcbbf4`
  (1544127 B), `mc2-windows-arm64-opt` `a39f3e7e...9bda64fd` (1429131 B),
  `mc2-windows-x86_64-opt` `1cb22208...4a14266fd4` (1471715 B).
  Docs: `docs/reference/hooks.md` (§ 4 "Asking about an operator token" -- `cmp_cond`/`cmp_cond_of`
  with the six tokens and the unsigned twins; § 8 gained the arity paragraph and the refreshed
  counts), `tests/golden/README.md` (the three-field `sym` line and the third verdict),
  `docs/specs/M53.md` (§ Implementation notes -- the first freeze regression (#92) and the arity
  column, six notes).
- Final docs pass before 1.0.0 (2026-09-15, docs-only, no `src/`/`lib/`/`tests/golden/` touched):
  an audit of the whole `docs/` tree plus `README.md` for stale statements ahead of the surface
  freeze and the eventual 1.0.0 tag. **Seven stale statements fixed**, each a concrete claim that
  work described as pending or narrower than reality was already done: (1)
  `docs/guide/00-getting-started.md` said "macOS on Apple Silicon (arm64). That is the only host
  today" — wrong since M37/M38; corrected to name all three hosted platforms with links to
  `90-linux-host.md`/`95-windows-host.md`. (2) The same page and root `README.md` both said
  "2,846-line C23 seed" against the real, unchanged `2848` (`sh scripts/loc-budget.sh`). (3) Root
  `README.md`'s lead sentence narrowed `mc` to "Mach-O for AArch64", years after Linux ELF and
  Windows PE/COFF landed; broadened, and the "Build it" list gained a `comparison.md` link and a
  one-line 1.0.0 status bullet (kept above the `<!-- release-excerpt-end -->` marker so it ships
  in every release's own `README.md`). (4) `docs/README.md`'s intro repeated the AArch64/Mach-O
  narrowing and said the run time is "still at `clang -O0` level" with no mention that `-O` (M49)
  already closes most of that gap to a measured 1.30x — both corrected; its design-documents table
  also still said `specs/M1.md … M30.md` where the tree has specs through `M53.md`, and
  `build.md`'s one-line description named only Linux targets where it documents Windows too. (5)
  `docs/guide/80-footprint.md` § "What is not measured yet" said there is no Windows backend and
  that the machine-interface split "has to land first" — both landed at M17/M19/M20; corrected to
  say the real gap, which is that `examples/minimal/measure.sh` itself has no Windows row (no
  Windows runner/host available to this Mac), not that the backend is missing. (6)
  `docs/reference/hooks.md` § 8's own frozen-surface table said **420 entries, `toml` 35** —
  stale by one PR (`#91` added `[package].version`, an additive MINOR, re-recorded in
  `tests/golden/surface.txt` at the time but never echoed into this prose table); corrected to the
  measured **421, `toml` 36** (`sh scripts/check-freeze.sh`). (7) **`CLAUDE.md`'s own `- Next:`
  line** named **M42 step 2 (Windows PE `--exe`)** as future work — it landed via PR #63, long
  before M48 through M53, fully CI-gated on `windows-11-arm`/`windows-2025` as the project's own
  rule for a new target requires (`docs/build.md` § "A direct PE, no lld-link (M42 step 2)"); the
  line is rewritten to state that M49/M50/M52 and M53's steps A-C are closed and shipped, that
  M42 step 2 is done (correcting the stale claim), that the current tag is `v0.17.4` with one
  patch ahead of it on `main`, and that M53's own closure gate (§ 13: teko's gap list at zero,
  self-hosting on five legs, `teko_std` published) is a fact of the OTHER repository this side
  watches rather than ships — so 0.17.x stays "bug fixes only" until it, then
  `vars.MC_CANARY_REQUIRED=true` and a `release:major` 1.0.0 tag.
  **Added, not just fixed**: `docs/plan.md` gained a new § "What 1.0.0 promises, and what it does
  not" (right after the M53 row) stating the promise in one place — the 421-entry recorded
  surface, the ten committed fixed points on five hosts, the canary gate; what is deliberately
  NOT promised (`src/` globals, diagnostic wording, emitted bytes/goldens — `docs/determinism.md`'s
  domain, not this one); how a consumer pins (`[package].mc`, `mc upgrade`, the registry's own
  pinned validator version); and when it is cut. `docs/README.md` gained a matching short § 1.0.0
  pointing back at it.
  Nothing in `src/`, `stage0/`, `lib/`, `tests/golden/` or any generated artefact was touched, so
  none of the ten goldens moved and `check-inert`'s claim is untouched by construction — this is
  prose only. Verified on this tree: `sh scripts/check-docs.sh` → `docs ok: 209 symbols, 50 flags,
  36 toml keys, 10 directives, 52 samples, 588 links`; `sh scripts/check-freeze.sh` → `ok freeze:
  421 entries (209 sym, 50 flag, 36 toml, 10 dir, 101 bundle, 14 lock, 1 machine)` — **unchanged by
  this pass**, confirming no public entry was added, removed or renamed; `make site` → `100 pages,
  5 sections, 52 fences highlighted (1 kept plain)`; `make check-site` → `mcsite --check: 100
  pages, 0 link problems`, `100 files, 0 problems` (`checkhtml.py`), `50 pairs checked, 0 below the
  minimum` (`contrast.py`).

- Lexer ownership, three additive items (0.16.x; reported by the mc-php consumer with reproducers
  in its `probes/gap-lexer-ownership/`, exit 0 only while the gap reproduces). Measured against
  `build/mc1` from `main` 210af6b BEFORE any code: `$name` -> `2 6 $a` (T_HOLE) and
  `e-dollar.php:1: hole $name has no rule binding it`, with a `syntax_expr("$", &f)` registered
  and every PHP lexeme `tok_add`ed -- the whole of what the surface offers. `stage0/` untouched
  (2848/3000, `/usr/bin/git diff main -- stage0/` empty). **Cost in `src/`: 64 added lines, 21 of
  them neither comment nor blank** (`parse.mc` +27/9, `lex.mc` +24/7, `hooks.mc` +13/5);
  **zero new globals** (`dhook_fn` in `lex.mc` replaces nothing but is the fourth of its kind;
  `check-limits` 17/17 seed limits under 90%, unchanged).
  1. **`void p_skip_to(uptr q)`** (`src/parse.mc`, beside `p_take_lit`/`p_src_end`): the cursor
     moves to `q` and the current token does **not** grow -- the generalisation of `p_take_lit`,
     which says "my literal ends here, make the token that long" where this says "I consumed these
     bytes myself, lex the next token from there". That is what a handler owning a region the core
     has no grammar for needs: a single-quoted string, a `#` comment, a heredoc body, the inline
     HTML between `?>` and `<?php`. It reads the bytes with `p_cp()`/`p_src_end()` (M45 already
     allowed that) and now says where it stopped. Guarded exactly like `p_take_lit` --
     `cp == tok_start(cur) + tok_len(cur)`, so never a string and never a substituted identifier,
     `q` at or past the cursor and inside the file -- with its own message,
     `p_skip_to outside the source token`.
     **Newlines in the skipped region are counted**, which `p_take_lit` never had to do (a literal
     has no newline in it; a heredoc is nothing but newlines). Proved by a negative control: with
     the counting line removed and the compiler rebuilt, a bad call on the line after a four-line
     region is reported at **line 3**; with it, at **line 6**.
  2. **`$name` reaches `syntax_expr("$", &f)`.** The rule, and it is the consumer's: with a
     registration on `$`, a `$` OUTSIDE a `#rule` pattern or template lexes as the one-character
     `$` token and the name after it as the ordinary identifier it looks like; INSIDE a template a
     hole is still a hole; with no registration nothing is even asked and `$name` is a hole exactly
     as it was. Safe in both directions: outside a template an unbound hole was already the error
     `hole $name has no rule binding it`, so nothing an untaught compiler accepts changes meaning.
     The lexer must not name `hooks.mc` (`src/lexdump.mc` includes it with `arena.mc` and nothing
     else), so it arrives as the fourth function pointer of its kind -- `lex_set_dollar_hook`,
     beside `lex_set_source_hook`/`lex_set_claim_hook`/`lex_set_bundle` -- registered by
     `syntax_expr` and answered in `hooks.mc` by `dollar_is_word(tok)`, which is the one place
     both halves are visible (`syntax_expr_find` is there, `rule_def` is `parse.mc`'s). The
     pointer is 0 until some module registers an expression word, and then not even the `callp`
     happens. `lex_set_dollar_hook` is deliberately NOT surface: like the other two hook setters it
     is named nowhere in `docs/reference/` (M53 § 8 -- an undocumented helper is not surface).
  3. **Surface coverage widened, the rule being "a name `docs/reference/` documents as a CALLABLE
     is frozen"** (`scripts/surface-extract.sh`, the ONE file both `check-docs` and `check-freeze`
     read). **60 entries added, 0 removed**: `check-freeze` **424 -> 483 entries
     (271 sym, 50 flag, 36 toml, 10 dir, 101 bundle, 14 lock, 1 machine)**, `check-docs`
     **209 -> 271 symbols**. The 16 `hooks.md` § 4/§ 6 already calls "the parser's public API.
     Fixed names" (`parse_expr`, `parse_stmt`, `parse_block`, `parse_params`, `parse_function`,
     `top_add`, `def_add`, `param_new`, `list_append`, `lex_set_libs`, `lex_root_of`,
     `lex_root_count`, `lex_root_name`, `lex_root_dir`, `lex_inc_count`, `lex_inc_at`), plus
     `lex_file`/`lex_set_bundle` by the same rule, the `nd_*`/`set_nd_*` families as prefixes (26)
     and `node_new`, `tok_add`, `word_id`, `def_find`/`de_at`/`de_val`, `path_join`/`path_norm`,
     `read_file`, `xalloc`/`xstrdup`, `str_eq`, `cstrlen`, `err_at`/`err_at2`. Exact names and not
     a `parse_`/`lex_` prefix, deliberately: those two prefixes would drag in 17 and 48 names
     respectively, most of them internals nobody documents. 26 of the 60 needed a documentation
     row and got one rather than being dropped from the list -- a new § "The `<mc/core>` facilities
     a handler stands on" in `docs/reference/hooks.md` § 4 (three tables: the AST, names the core
     already knows, strings/paths/files) plus `p_skip_to` in § Record and replay.
     `lex_next`, `lex_word_id` and the three `lex_set_*_hook` are documented nowhere and stay out.
  Proofs in `scripts/check-surface.sh` (**160 ok, 0 FAIL**), six new cases over two fixtures.
  `lib/user_dollar.mc` (M-earlier's `$"..."` demo) grew the `$name` half -- a table of its own,
  `a` -> 40, `b` -> 2 -- and one source now exercises **all three in the same file**: a `#rule`
  whose template uses `$n` holes, `$"...42 chars..."` and `$a + $b`, exit **40**; the default
  compiler still refuses `$"..."` (`invalid hole`) and still lexes `$name` as a hole
  (`hole $name has no rule binding it`, asserted on a file of its own, since in the combined one
  the `$"` above it is `invalid hole` first). `lib/user_rawlex.mc` + `lib/mc_rawlex.mc` are new and
  are the `p_skip_to` half: `q'...'` is a region the core cannot lex, read verbatim into an
  ordinary `N_STR` -- `q'a php single-quoted string'` prints itself and exits **26** -- the
  four-line region reports the error after it at **:6**, and the default compiler refuses the same
  source with `unterminated char literal`, which is the defect being answered. Neither fixture is
  in `tools/bundle.list` (the M41 precedent for check-script-only demos), so neither is a
  `[package].files` entry and the blob moved only through `src/lex.mc`/`src/parse.mc`/
  `src/hooks.mc`.
  **Inert**: `scripts/check-inert.sh <mc1 from main 38c0d6a> build/mc1` -- **33 objects identical
  on the plain road and 33 with `--opt=1`** (`tests/*.mc` and `src/mc.mc`) plus byte-identical
  artefacts for `examples/api`, `lang`, `conc`, `desktop` and `kernel` through the taught compiler
  each side builds. Nothing in the corpus registers `syntax_expr("$")` or calls `p_skip_to`.
  -- `make bundle` re-run BEFORE bootstrapping (60 files, raw 1260398 -> LZ 571548, blob
  572322 B). `make check` green end to end (**RC 0, zero FAIL**): `budget` 2848/3000, `test`
  32/32, `check-lex`/`check-ast`/`check-asm` **108/108**, `check-obj` **32/32 identical to the
  frozen seed** and 32/32 `arm64-surface` against `macho`, `check-bundle` (lz round trip 125
  cases), `bootstrap` at BOTH fixed points (`mc2.o == mc3.o`, `mc2o.o == mc3o.o`) with the
  cross-road identity (`mc2o-plain.o == mc2.o`) and **both `--dump-asm` diffs between `mc1` and
  `mc2` empty**, `check-surface` 32/32 + 160 ok + inert, `check-opt` **76/76**, `test-exe` 34/34
  via `--exe`, `check-mc`, `check-standalone`, `check-parts`, `check-libroot` 11/11, `check-toml`,
  `check-build`, `check-pkg` **200/200**, `check-tool` **31/31**, `check-sysroots` (13 rows),
  `check-stubs`, `check-limits` **17/17 seed limits under 90%**, `check-minimal`, `test-linux`
  57/57 and `test-linux-x86_64` 53/53, the four `--exe` cells 60/60 + 60/60 + 56/56 + 56/56,
  `test-windows` 59/59 and `test-windows-x86_64` 55/55 objects cross-compiled, `check-examples`,
  `check-lang` 18, `check-conc` 21, `check-desktop`, `check-float`, `check-wide`, `check-kernel`
  (QEMU 11.0.1), `check-avr`, `test-sandbox` 73 ok / 0 failed / 1 skipped, `check-docs`
  (**271 symbols**, 50 flags, 36 TOML keys, 10 directives, 52 samples, 588 links),
  **`check-freeze` 483 entries**, `site` 100 pages + `check-site` (0 link problems) +
  `check-site-linux` (100 pages on all four Linux cells, byte for byte the macOS render).
  `make check-linux-host` **RC 0 over all four cells** (aarch64 musl 57/57 and gnu 58/58, x86_64
  musl 53/53 and gnu 54/54), each after its own plain AND optimized fixed point, its own
  cross-road identity and the cross proof (`mc2l --backend=macho src/mc.mc` byte for byte the
  macOS `build/mc2.o`).
  `tests/golden/seed-cmp.txt` **371 -> 407**: `p_skip_to`'s three `uptr` comparisons and the `$`
  branch's, replicated across the 12 entry points that include `lex.mc`/`parse.mc`. Every one of
  the 108 files still passes `validate_seed_diff`, so every differing line is still one of the
  four allowed `ge/lt/gt/le -> hs/lo/hi/ls` substitutions; only the count moved, which is what the
  gate's own message says to re-record.
  **The ten goldens rewritten once**, each only after its own criterion: `mc2.sha256`
  `dcbc2711...5a1443` -> `8d77105587e34317db0d3a3bf1dafe8559d91345f53f06417098565faf101794`,
  `mc2-opt.sha256` `fce46f1235a75e00638548e7e19fb35e61eb6aa21af7072112c9c6098a0d83da` (both by
  `scripts/bootstrap.sh`, after the two empty `--dump-asm` diffs and the two `cmp`s); the four
  Linux ones deleted and re-recorded by `make check-linux-host` -- `mc2-linux-arm64`
  `018c2d2714b777f08b642824e23446276e8f043745ec2d25ffc57e44265110ed`, `mc2-linux-arm64-opt`
  `d1738f7b8784e6250cfb41e15f491ec8ec087587b99f9ff4b66c74959c5be2a1`, `mc2-linux-x86_64`
  `a30ca5abccc4fe338b7a156c4be3d177776be4788988da585d7d22de8e383bdb`, `mc2-linux-x86_64-opt`
  `a70b6bfb132f6dc9a52aeb523b0eae0aa3d0f79cbef6d3c8c10306fa302adef6`, each recorded in its musl
  cell and re-verified by the gnu cell of the same architecture; the four Windows ones
  cross-computed on macOS per `tests/golden/README.md` -- `mc2-windows-arm64`
  `a7046e7e9fa8de674c3d5febfa6b3b2bef6164651b718fbe975b6cf9783f8276` (1494308 B),
  `mc2-windows-arm64-opt`
  `856ee07da386e837601414af4f1922b01ba16073aa3a629be4dad3f2491b2fab` (1435288 B),
  `mc2-windows-x86_64`
  `c3e6363cb58a0fd42abc51235f06f004b8d45cc9991ab112f6851838ea1cc3e5` (1550224 B),
  `mc2-windows-x86_64-opt`
  `2569c0d8fe01c42f21b4e3b612d4878dad448e17535bc19b42bfc53a398a0d84` (1477696 B).
  **The consumer's own probe, re-run against the new compiler** (`MC=… sh run.sh`, exit 1 =
  "no longer reproduces"): `e-dollar.php` moved from `hole $name has no rule binding it` to
  `syntax_expr handler produced no expression: $` -- the handler road exists and `claimall.mc`'s
  `ca_dollar()` is `p_next(); return 0;`, which is the guard -- and three of the five
  `--dump-tokens` lines moved from `2 6 $a` (T_HOLE) to `2 308 $` + `2 1 a`. The other four lines
  (`'`, `#`, `#[`, the raw text) are unchanged **by design**: they need a handler that CALLS
  `p_skip_to`, and `claimall.mc` registers none. A 24-line module that does
  (`syntax_expr("$")` + `syntax("<?php")` + `p_cp`/`p_src_end`/`p_skip_to`/`p_push_source`)
  compiles both halves of the probe: `a-single-quote.php` exits **26** (the length of the
  single-quoted string the core cannot lex) and `e-dollar.php` exits **4** (`cstrlen("name")`).
  Docs: `docs/reference/hooks.md` (§ `syntax_expr` -- the `$` rule as a four-row table and why it
  is safe both ways; § Record and replay -- the `p_skip_to` row, the guard and the line rule;
  the new § "The `<mc/core>` facilities a handler stands on"), `docs/reference/diagnostics.md`
  (one new row, `p_skip_to outside the source token`), `scripts/surface-extract.sh`'s own header
  (what the widening freezes and what it deliberately leaves out).
