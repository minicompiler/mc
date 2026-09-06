# mc vs Go, Zig, Rust, C#, C -- measured on Apple M4 (16 GiB), macOS 26 (Darwin 25.6.0), 2026-09-06

Method: `/usr/bin/time -l`, best of 3 wall-clock `real`, max RSS of the best run. Compiles under
10 ms re-timed with `perl -MTime::HiRes` (min of 20). Nothing in the repository was modified; all
work is in `scratchpad/bench/` (`mc/ c/ go/ zig/ rust/ cs/ out/`). Raw data: `results.json`.

Toolchains: mc `build/mc1` (`mc 0.0.0-dev`, tree e5a1643) · go1.26.4 · zig 0.16.0 · rustc 1.96.0 ·
dotnet SDK 10.0.301 (runtime 10.0.9) · Apple clang 21.0.0.

## A. The same workload in six languages

One integer workload, same semantics everywhere: (1) 200,000,000 iterations of a wrapping 64-bit
LCG (`x = x*6364136223846793005 + 1442695040888963407`) + xorshift mixing (`y ^= y>>13; y ^= y<<7;
y ^= y>>17`), accumulated in a wrapping u64; (2) sieve of Eratosthenes over 50,000,000 bytes,
counting primes below 50,000,000; (3) naive recursive `fib(38)`. Three numbers printed.

**Cross-check: every variant printed exactly `8128903901837660708 / 3001134 / 39088169`**
(stdout md5 `c369e8b4679ca95f45fa46bbff03b7b7` for all 12 runs).

Sieve storage: mc `u8 sieve[50000000]` in `__bss`; C `static uint8_t[N]`; Zig
`std.heap.page_allocator.alloc` + `@memset`; Go `make([]byte, N)`; Rust `vec![0u8; N]`;
C# `new byte[N]`. Bounds checks stay on where the language has them (Go, Rust, C#, Zig Debug).

| Language / variant | Build command (exact) | Compile (best of 3) | Compile RSS | Binary (bytes) | `__text` (bytes) | Run (best of 3) | Run RSS | Source lines |
|---|---|---|---|---|---|---|---|---|
| **mc** `--exe` | `build/mc1 --exe mc/bench.mc -o out/bench-mc` | **4.1 ms** (min of 20; `time -p` shows 0.00) | 2.2 MB | 33 461 | 1 480 | **1.09 s** [1.47 1.12 1.09] | 51.3 MB | 76 |
| C `clang -O2` | `clang -O2 c/bench.c -o out/bench-c-O2` | 0.11 s (62 ms min of 10) | 54.1 MB | 33 464 | 1 320 | **0.49 s** [0.75 0.50 0.49] | 51.4 MB | 50 |
| C `clang -O0` | `clang -O0 c/bench.c -o out/bench-c-O0` | 0.09 s | 40.6 MB | 33 512 | 740 | 1.02 s [1.36 1.02 1.21] | 51.4 MB | 50 |
| Go `go build` | `go build -o out/bench-go bench.go` | 0.08 s warm; **5.94 s cold** (fresh `GOCACHE`, 317 MB RSS) | 26.1 MB | 2 492 482 | 649 316 | 0.55 s [0.89 0.55 0.62] | 54.8 MB | 55 |
| Zig `-O ReleaseFast` | `zig build-exe -O ReleaseFast bench.zig -femit-bin=out/bench-zig-fast` | **9.80 s** warm [12.26 10.59 9.80]; 13.42 s cold | 292.7 MB | 396 304 | 238 804 | 0.50 s [0.78 0.51 0.50] | 51.6 MB | 57 |
| Zig `-O Debug` | `zig build-exe -O Debug bench.zig -femit-bin=out/bench-zig-debug` | 2.19 s [2.42 2.31 2.19] | 261.1 MB | 2 046 800 | 1 272 108 | 1.69 s [1.93 1.69 1.72] | 53.0 MB | 57 |
| Rust `-C opt-level=3` | `rustc -C opt-level=3 bench.rs -o out/bench-rust-O3` | 0.19 s [0.91 0.19 0.19] | 98.6 MB | 466 320 | 216 908 | **0.47 s** [0.74 0.48 0.47] | 51.6 MB | 59 |
| Rust `-C opt-level=0` | `rustc -C opt-level=0 bench.rs -o out/bench-rust-O0` | 0.14 s | 98.0 MB | 469 152 | 218 308 | 1.55 s [1.99 1.67 1.55] | 51.6 MB | 59 |
| C# JIT | `dotnet build -c Release --no-restore` (restore 0.80 s once) | 0.54 s warm; 0.76 s cold (`rm -rf bin obj`); 0.64 s `--no-incremental` | 176.0 MB | 5 120 (`bench.dll`) + 123 944 apphost + 78 MB shared runtime | n/a (IL) | 0.59 s `dotnet bench.dll` [0.59 0.64 0.67]; 0.59 s apphost; **1.71 s `dotnet run -c Release`** (build check included) | 94.6 MB (222 MB for `dotnet run`) | 58 |
| C# NativeAOT | `LIBRARY_PATH=/opt/homebrew/opt/openssl@3/lib:/opt/homebrew/opt/brotli/lib dotnet publish -c Release -r osx-arm64 -p:PublishAot=true -o out/cs-aot` | 3.23 s cold (`rm -rf bin obj`); 1.04 s incremental re-publish | 231.5 MB | 1 020 584 | 282 276 | 0.62 s [0.94 0.63 0.62] | 57.5 MB | 58 |

Failures recorded verbatim:
- NativeAOT, first attempt (`dotnet publish -c Release -r osx-arm64 -p:PublishAot=true`):
  `ld: library 'ssl' not found` / `clang: error: linker command failed with exit code 1` (MSB3073).
  Second attempt with `LIBRARY_PATH=/opt/homebrew/opt/openssl@3/lib`: `ld: library 'brotlienc' not found`.
  Third attempt with both Homebrew `openssl@3` and `brotli` on `LIBRARY_PATH`: rc 0 (three `ld: warning:
  building for macOS-12.0, but linking with dylib ... built for newer version 26.0`). The AOT binary
  dynamically links `libssl.3`, `libcrypto.3`, `libbrotli{enc,dec,common}.1`, `libswiftCore`,
  `libswiftFoundation`, `libicucore`, `libz`, `libobjc` and six frameworks (`otool -L`).
- C# apphost `cs/bin/Release/net10.0/bench` run directly: `You must install .NET to run this
  application. ... Default location: /usr/local/share/dotnet` (rc 131) -- Homebrew's dotnet is not
  there; with `DOTNET_ROOT=/opt/homebrew/Cellar/dotnet/10.0.301/libexec` it runs (0.59 s).
- Zig: the 0.15-style `std.fs.File.stdout().writer(&buf)` does not exist in 0.16 (`error: root source
  file struct 'fs' has no member named 'File'`); 0.16 wants `pub fn main(init: std.process.Init)` and
  `std.Io.File.stdout().writer(init.io, &buf)`. A static `var sieve: [N]u8 = [_]u8{0} ** N` (or
  `@splat(0)`) compiled in ~10 s as well, so the array was moved to the heap; the ~10 s ReleaseFast
  compile persists with the heap version and is the toolchain's cost for this program.
- mc: none. (`time -p`'s 10 ms resolution reads 0.00; the HiRes number is 4.12 ms for `--exe`,
  2.18 ms for an object.)

Linker needed for a native executable (measured): mc **no** (`--exe` writes and ad-hoc signs the
Mach-O itself; `codesign -dvvv`: `flags=0x2(adhoc)`); Go **no** (`go build -x` runs only
`pkg/tool/darwin_arm64/link`); Zig **no** (`--verbose-link`: bundled `zig ld`); Rust **yes**
(`--print link-args`: `"cc"`); C **yes** (clang -> Apple ld); C# JIT **no**, NativeAOT **yes**
(clang -> ld, plus OpenSSL/brotli libraries).

## B. Toolchain facts

| Toolchain | Version | Root measured (`du -sh`) | Size | Files | System linker for a native exe | Self-hosting |
|---|---|---|---|---|---|---|
| mc | `mc 0.0.0-dev` (tree e5a1643) | `build/mc1` (single binary; `build/mc-exe`, written by `mc --exe`, 1 170 739 B) | **1.2 MB** (1 181 184 B) | **1** | no (macOS/Linux); Windows needs `lld-link` | yes -- written in mc, byte-identical fixed point; 2 848-line C23 seed only for bootstrap (`docs/bootstrap.md`) |
| Go | go1.26.4 darwin/arm64 | `go env GOROOT` = `/opt/homebrew/Cellar/go/1.26.4/libexec` | 258 MB | 14 954 | no (pure Go: internal linker) | yes since Go 1.5 (2015) [knowledge] |
| Zig | 0.16.0 | `/opt/homebrew/Cellar/zig/0.16.0_1` (`zig env`: `zig_exe` .../bin/zig 21 MB, `lib_dir` .../lib/zig) | 246 MB | 19 548 | no (bundled `zig ld`) | yes -- self-hosted compiler since 0.11 (2023); LLVM used for ReleaseFast [knowledge] |
| Rust | rustc 1.96.0 (ac68faa20 2026-05-25) | `rustc --print sysroot` = `~/.rustup/toolchains/stable-aarch64-apple-darwin` | 1.7 GB (`~/.cargo` another 233 MB) | 54 532 | yes (`cc`) | yes since 2011; LLVM backend [knowledge] |
| .NET | SDK 10.0.301, runtime 10.0.9 | `/opt/homebrew/Cellar/dotnet/10.0.301` (sdk dir 350 MB, `shared/Microsoft.NETCore.App` 78 MB) | 666 MB | 4 738 | JIT no; NativeAOT yes (clang/ld) | Roslyn (C# compiler) in C#; CoreCLR/JIT/GC in C++ [knowledge] |
| clang | Apple clang 21.0.0 (clang-2100.1.1.101) | `XcodeDefault.xctoolchain` (clang binary 141 MB; `usr/lib/clang` 25 MB; MacOSX.sdk 303 MB extra) | 1.0 GB | 5 109 | yes (Apple `ld`) | yes (C++, builds itself) [knowledge] |

## C. mc's own numbers

| Measure | Value |
|---|---|
| `build/mc1 src/mc.mc -o x.o` (self-compile to object, best of 3) | **0.88 s** [0.90 0.93 0.88], RSS 59.9 MB, object 1 285 176 B |
| `build/mc1 --exe src/mc.mc -o mcx` (self-compile to executable) | 0.93 s, **1 170 736 B**, `codesign --verify` OK |
| `src/*.mc` lines excluding `src/bundle_data.mc` | **24 726** (62 files; `bundle_data.mc` alone is 11 815 lines / 1 349 348 B, generated) |
| `stage0/*.c` lines (`make budget`) | **2 848 / 3000** (`stage0: 2848 / 3000 lines`; +216 for `mc.h` = 3 064) |
| `build/mc1 --dump-asm mc/bench.mc` instruction lines | **370** (410 lines, 40 labels); per function: strlen 26, puts 22, putnum 46, putu64 46, mix 68, primes 91, fib 32, main 39 -- workload only (mix+primes+fib+main) **230** |
| `clang -O2 -S c/bench.c` instructions | **330** (main 309 with mix/primes inlined and the sieve count vectorized; fib 21) |
| `clang -O0 -S c/bench.c` instructions | **185** (main 30, mix 53, primes 75, fib 27) |
| `--exe` binary vs `clang -O2` binary | 33 461 B vs 33 464 B (both one 16 KiB `__TEXT` page + 50 MB zero-fill `__DATA` + signature); `__text` 1 480 B vs 1 320 B (`-O0`: 740 B); `.o` 2 432 B vs 2 352 B |

Counting: mc = lines starting with two spaces in `--dump-asm`; clang = lines beginning with
whitespace and a letter, minus `.` directives. mc's 370 includes the 140 instructions of
`strlen/puts/putnum/putu64` from `<io>`, which the C version gets from `printf`.

## D. Feature matrix -- facts only

mc column: read from the docs (file:line cited). Other columns: from general knowledge of each
language as of its version here, marked [k].

| Feature | mc | C (clang 21) [k] | Go 1.26 [k] | Zig 0.16 [k] | Rust 1.96 [k] | C# / .NET 10 [k] |
|---|---|---|---|---|---|---|
| Generics | **No** in the core (`docs/reference/language.md:614-616` lists generics among what the core "deliberately does not have"); `examples/lang` teaches generics with `where` constraints by record-and-replay from the surface (`examples/lang/README.md:73-74,124`) | No (`_Generic` selection only) | Yes (type parameters, since 1.18) | Yes (comptime type parameters) | Yes (traits, monomorphized) | Yes (runtime generics, CLR) |
| Structs / records | **No** `struct` (`language.md:623-626`: "`#define` offsets plus accessor functions"); `examples/api/oop.mc` teaches `class`/`interface` in 482 lines without touching `src/` | Yes | Yes | Yes | Yes (struct/enum/tuple) | Yes (class/struct/record) |
| Floats | **None in the core** (`language.md:75-76`); `<float>` is a library: `f32`/`f64` via `type_new`/`syntax_lit`/`intrinsic` + a derived machine in `lib/float.mc`, `lib/machine_*_float.mc` (`language.md:618-621`) | Yes | Yes | Yes (f16..f128) | Yes | Yes |
| Strings | Literals only: `"..."` is a `uptr` into `__TEXT,__cstring`, NUL-terminated, deduplicated; `\0` inside is an error; no string type (`language.md:50-54`) | char arrays + libc | Built-in immutable `string` | `[]const u8` slices | `String`/`&str` (UTF-8) | `System.String` (UTF-16) |
| Closures / function pointers | `&fn` is a `uptr`; indirect call is the `callp(p, a1..a11)` intrinsic; no function type, no closures (`language.md:469-478`) | Function pointers, no closures (blocks are an Apple extension) | Closures | Function pointers; no closures | Closures (`Fn` traits) | Lambdas/delegates |
| Error handling | Nothing in the language; the compiler's own contract is diagnostic + exit code 0/1/2/3/124-126 (`docs/reference/cli.md:426-441`); a runtime divide-by-zero is whatever the ISA does (`docs/core-language.md:86-88`) | Return codes / errno | Multiple returns, `error` values, panic | Error unions `!T`, `try`/`catch` | `Result`/`?`, panics | Exceptions |
| Memory safety model | **Unchecked**: `uptr` is "opaque, no pointee, byte arithmetic" (`language.md:73`); all access is `ld8..ld64`/`st8..st64` on a raw address (`language.md:302-311`); no bounds checks; signedness by convention "documented, not enforced" (`language.md:77-79`) | Unchecked | GC + bounds checks; `unsafe` pkg | Bounds/overflow checks in Debug/ReleaseSafe, off in ReleaseFast | Ownership/borrowing, bounds checks; `unsafe` blocks | GC + bounds checks; `unsafe` |
| GC | **None**; no allocator in the core (no standard library, `language.md:616`); `examples/lang` uses reference counting in `lib/rt.mc` (4 MiB arena, 16 size-class free lists; "Cycles leak", `examples/lang/README.md:217-228,256-259`) | None | Tracing, concurrent GC | None (explicit allocators) | None (RAII) | Tracing, generational GC |
| Concurrency primitives | **None in the core** (no "thread"/"atomic" in the language reference); `examples/conc` teaches threads, channels, a worker pool, `lock`, `await` as a module stacked on `lang.mc` (`examples/conc/README.md:8-11`); `x18..x28` reserved "never written, never read" so a taught runtime may keep state there (`docs/reference/objects.md:293-303`) | pthreads/C11 threads + atomics (library) | goroutines, channels, sync (built in) | std.Thread, atomics; async removed pending redesign | std threads, atomics; async/await + external executors | Threads, Task/async-await, locks |
| Optimizer | **Constant folding only** (`fold()`, `docs/core-language.md:76,89,284`; `docs/specs/M1.md:69`). No peephole (`docs/surface.md:211-212`), no inlining/leaf-frame elision (`surface.md:1389`), no dead-code elimination ("`mc` emits every function it parses", `docs/guide/80-footprint.md:124`), no register allocator (`objects.md:302-303`). The only optimization seam is a user `pass()` before `fold` (`surface.md:449-451`) | LLVM -O0..-O3 | SSA backend with inlining, escape analysis, DCE | LLVM (ReleaseFast/Small) or self-hosted (Debug) | LLVM -O0..-O3 | RyuJIT tiered + PGO; NativeAOT via ILCompiler |
| Register allocation | **None** (no allocator): fixed "depth" scheme -- expression depths 0..6 in `x9..x15`, deeper values spill to the frame through `x16`/`x17`; locals at `[sp, #k]`; `MAXDEPTH` 64; frame ceiling 4095 B (`objects.md:189-191,285-299`; `machine.md:209-215`). Per machine: x86-64 `r8..r11` (0..3), RISC-V `t3..t6`, AVR none (`machine.md:279,339,404`) | Yes (LLVM greedy) | Yes (linear scan / SSA-based) | Yes (LLVM; own in Debug) | Yes (LLVM) | Yes (RyuJIT LSRA) |
| Cross targets shipped | 5 `target()` registrations in `src/core_writers.mc:57-61`: macos/aarch64 (`macho`, `macho-exe`), linux/aarch64 and linux/x86_64 (`elf-obj*`, `elf-exe*`), windows/aarch64 and windows/x86_64 (`coff-obj-*`, no direct exe -> `lld-link`); 3 machines in `src/` (arm64, x86_64, x86_64-win); **riscv64 bare metal** (`examples/kernel`, "zero lines added to `src/`") and **AVR ATmega328P** with a 2-byte `uptr` (`examples/avr`) taught from the surface | Many (LLVM targets; needs per-target SDK/sysroot) | Many (`GOOS`/`GOARCH`, built in) | Many (LLVM + bundled libc headers) | Many (rustup targets; needs linker/sysroot) | osx/linux/win x64/arm64 RIDs |
| Package manager | **Yes**: `mc pkg sync\|add\|list\|vendor\|verify\|hash\|check`, `mc update`; `[deps]` in `mc.toml`, `mc.lock`, minimal version selection, registry index at `<registry>/index/<name>.toml`, default `https://pkg.minicompiler.dev`; optional part `<mc/core_pkg>` (`docs/reference/cli.md:315-343`, `docs/reference/packages.md:85,146,330,361-375`) | None (system pkg mgrs) | Go modules (built in) | `zig fetch` + `build.zig.zon` | cargo + crates.io | NuGet |
| LSP | **None shipped**: zero hits for "lsp" in `src/`; `mc lsp` is planned as M28 (`docs/plan.md:440`, `docs/specs/M28.md`) | clangd | gopls | zls (third party) | rust-analyzer | Roslyn LSP / OmniSharp |
| Debugger support | **None**: no DWARF, no `-g`, zero hits in `src/`; planned as M30 (`docs/plan.md:442`, `docs/specs/M30.md`; `docs/specs/M28.md:86` notes the compiler cannot produce a column today) | DWARF (`-g`), lldb/gdb | DWARF, delve | DWARF | DWARF, lldb/gdb | PDB / portable PDB; NativeAOT emits DWARF (a `.dSYM` was produced here) |
| Reproducible builds | **Byte-identical fixed point**: `mc1 mc.mc -> mc2.o`, `mc2 mc.mc -> mc3.o`, `cmp mc2.o mc3.o`; SHA-256 goldens in `tests/golden/`; the 8 determinism rules (no pointer hashing, stable symbol partition, no dates/paths) (`docs/determinism.md:1-20`, `docs/bootstrap.md:11-40`) | Mostly, with effort (`-frandom-seed`, no `__DATE__`) | Yes by design (`-trimpath` for paths) | Yes (content-addressed cache) | Yes in practice (cargo, with path remapping) | Deterministic IL by default; native varies |
| Extensibility of the compiler by user code | **Four tiers, in the language itself**: Tier 1 directives (`#token`, `#infix`/`#prefix`, `#rule`, `#include <name>`, `#embed`, `#section`, `#opcode`, `emit()`/`reloc()`); Tier 2 `pass()`, `backend()`, `machine()`, `target()`; Tier 3/4: 6 word registrations (`syntax`, `syntax_stmt`, `syntax_expr`, `syntax_infix`, `type_alias`, `type_new`) + 7 word-free hooks (`on_stmt`, `on_jump`, `syntax_lit`, `syntax_param`, `syntax_type`, `on_source`, `source_claim`) + `intrinsic` (`docs/reference/hooks.md:286-312`, `docs/surface.md:646-665`). Proofs in tree: `examples/api` (classes), `examples/lang` (a language with generics), `examples/conc`, `examples/kernel` (a new ISA), `examples/avr`, `<float>`/`<i128>`/`<f16>` (new primitives) | None (preprocessor only) | None (`go generate` is external) | `comptime` (compile-time execution inside the language; no new syntax) -- nearest analogue | Procedural macros / `macro_rules!` (token-level, no new types/backends) -- nearest analogue | Source generators / analyzers (Roslyn, C#-level; no new syntax) -- nearest analogue |
| Sandbox | `mc sandbox run\|exec\|check`: Linux-only box (user/mount/pid/net/ipc/uts namespaces, overlay + `pivot_root`, Landlock, seccomp with a supervisor that names each refusal, rlimits, wall clock); exit 126 off Linux (`docs/reference/sandbox.md:1-31`, `cli.md:439`) | n/a | n/a | n/a | n/a | n/a |
| Self-hosting | **Yes**: clang compiles the 2 848-line C seed once (`build/mc0`), then `mc` compiles itself to a fixed point; no script calls a C compiler afterwards (`docs/bootstrap.md:11-56`) | yes [k] | yes since 1.5 [k] | yes since 0.11 (LLVM for optimized builds) [k] | yes [k] | Roslyn in C#; runtime in C++ [k] |
| Native exe without a system linker | **Yes** on macOS (`macho-exe`, ad-hoc signed) and Linux (`elf-exe`, dynamic `ET_EXEC` against musl or glibc); Windows needs `lld-link`; static link against a libc needs `[linker]` (`docs/build.md:198-199,697,757-774,1117-1122`; `cli.md:34`) | No (ld) | Yes (internal linker; measured) | Yes (bundled linker; measured) | No (`cc`; measured) | JIT n/a; NativeAOT no (clang/ld; measured) |

## Commands run (exact)

Build: see column 2 of table A. Runs: `./measure.sh LABEL OUT cmd` = 3x `/usr/bin/time -l cmd > OUT`.
Cold Go: `env GOCACHE=<fresh dir> go build -o out/bench-go bench.go`. Cold Zig:
`zig build-exe -O ReleaseFast --global-cache-dir <fresh> --cache-dir <fresh> bench.zig`. C# JIT run:
`dotnet cs/bin/Release/net10.0/bench.dll`; apphost `env DOTNET_ROOT=/opt/homebrew/Cellar/dotnet/10.0.301/libexec cs/bin/Release/net10.0/bench`;
`dotnet run -c Release`. Linker checks: `go build -x`, `zig build-exe --verbose-link`,
`rustc --print link-args`. Sizes: `stat -f %z`, `otool -l | sectname __text`, `du -sh`, `find -type f | wc -l`.
mc: `build/mc1 --dump-asm mc/bench.mc`, `build/mc1 src/mc.mc -o x.o`, `build/mc1 --exe src/mc.mc -o mcx`,
`make budget` (read-only: `scripts/loc-budget.sh` = `cat stage0/*.c | wc -l`), `clang -O2 -S` / `clang -O0 -S`.
