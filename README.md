# mc

[![CI](https://github.com/minicompiler/mc/actions/workflows/ci.yml/badge.svg)](https://github.com/minicompiler/mc/actions/workflows/ci.yml)
[![Site](https://github.com/minicompiler/mc/actions/workflows/site.yml/badge.svg)](https://github.com/minicompiler/mc/actions/workflows/site.yml)

**A compiler small enough to read, written in itself.**

`mc` compiles a schoolbook-C language — seven types, one opaque pointer, `loop` and `if` — for
macOS, Linux and Windows, on arm64 and x86-64. A 2,848-line C23 seed is compiled by `clang`
exactly once; after that `mc` compiles its own source, writes and signs (or directly writes) the
executable itself, and reaches a fixed point where one generation is byte-identical to the next.
Everything the core leaves out — `while`, `for`, `+=`, a second backend, a whole object model —
you teach it from ordinary `mc` source.

- **Website** — <https://minicompiler.dev>
- **The plan** — [`docs/plan.md`](docs/plan.md): the language, the teaching surface, the
  architecture, the budget and the milestones
- **Projects, the bundled library, cross-compiling** — [`docs/build.md`](docs/build.md):
  `mc build`, `mc.toml`, `#include <name>`, `#embed`, Linux and Windows targets
- **How it compares** — [`docs/comparison.md`](docs/comparison.md): compile time, binary size and
  run time against C, Go, Zig, Rust and C#
- **CI and releases** — [`docs/ci.md`](docs/ci.md)
- **Examples** — [`examples/`](examples/)
- **1.0.0 is cut** — the public surface is recorded and frozen against removal
  (`docs/reference/hooks.md` § 8); see [`docs/plan.md`](docs/plan.md) §
  "What 1.0.0 promises, and what it does not"

<!-- release-excerpt-end -->

## Build it

```sh
make stage0     # clang compiles the C23 seed, once and never again
make mc1        # the seed compiles src/mc.mc into the real compiler
make check      # tests, the fixed point, the taught-surface demos, the examples
```

`build/mc1 --exe src/mc.mc -o mc` writes the signed, `ld`-free compiler in one step. Released
binaries are ad-hoc signed and not notarized, so a download needs
`xattr -d com.apple.quarantine mc` once — see [`docs/ci.md`](docs/ci.md).
