# `-O`: what it does and what it does not

`mc` compiles with the optimizer **off** unless you ask for it. There is one road to ask for and
one level to ask for:

```
mc -O prog.mc -o prog.o          # -O is an alias for --opt=1
mc --opt=1 --exe prog.mc -o prog
```

and, for a project, one key in `mc.toml`:

```toml
[project]
entry = "main.mc"
out   = "build/app"
opt   = 1
```

A flag on the `mc build` command line wins over the key, the last flag wins over an earlier one,
and anything but `0` or `1` is `mc: --opt must be 0 or 1: <value>`. There are no levels: one road
to test is one road that can be trusted, and `-O2` would be a promise this compiler does not make.

## Why the default is 0, and will stay 0

The unoptimized lowering is the **reference** everything else is compared against
([determinism.md](../determinism.md)): the 32 objects `check-obj` compares against the frozen C
seed, the `--dump-asm` diff of `check-asm`, `check-inert`'s byte comparison across a change, the
fixed point of `scripts/bootstrap.sh` and the five goldens recorded from it. A reference that moves
when the optimizer improves is not a reference. So the plain road is what `mc` does when nobody
said otherwise, on every host and in every release, and a project that wants the speed says so once
in its own file.

## What it does

**It keeps locals and parameters in callee-saved registers, on every target `mc` ships.** On
AArch64 that is `x19..x28`, ten of them; on x86-64 it is `rbx`, `r12`, `r13`, `r14`, `r15`, five of
them, and the same five under System V and under Win64 — `rdi` and `rsi` are argument registers on
one ABI and callee-saved on the other, and two registers were not worth a second code path. One per
declaration, for the length of a function. Before, every read of a local was a load
from `[sp, #k]` and every write a store; the loop of `bench/mc/bench.mc`'s `mix` was 50
instructions per iteration, thirteen of them loads and ten stores of the same four values and
fourteen `movz`/`movk` rebuilding two 64-bit constants. With `-O` it is **18**, none of them
touches memory and none of them rebuilds a constant that needs more than one instruction.

A declaration qualifies when all of this is true:

- it is a parameter, or a scalar local (not an array);
- its type's kind is `TK_INT` or `TK_SINT` and its width is 8 bytes or less — so `i64`, `u8`,
  `i32`, `uptr` and a registered integer type qualify, and a float, a 16-byte value or an opaque
  one does not;
- its **address is never taken**. `&x` means "a pointer to a frame slot", and a register has no
  address, so a local the program takes the address of stays in memory (`tests/mc/097-opt-addr.mc`);
- the function it is in contains **no `#opcode` call, no `emit()` and no `reloc()`**. Those write
  instruction words that name registers by hand, and the compiler inserts nothing around them, so
  the whole function is left alone rather than the statement (`tests/mc/100-opt-opcode.mc`).

Among the declarations that qualify, the ten with the most uses win, where a use inside a loop
counts eight times as much as one outside, a use two loops deep sixty-four times, and three or more
five hundred and twelve. A declaration used fewer than three times is never taken: a register costs
a save in the prologue and a restore in the epilogue, and that does not pay for one read.

**A `callp` does not disqualify a function.** AAPCS64 makes `x19..x28` the callee's to preserve, and
the target of an indirect call is an ordinary function that keeps that promise — so a local stays
in its register across a call, direct or indirect, and the save-and-reload around the call that the
plain road performs is skipped entirely.

**It keeps a loop's invariant values in registers too.** A register no local wanted goes to a value
the loop would otherwise rebuild on every iteration. Two kinds qualify:

- a **constant whose immediate costs two or more instructions** — one `movz` plus up to three
  `movk`, so anything with a non-zero bit above the low sixteen. `65536` is hoisted, `7` is not:
  a single `movz` is already as cheap as the `mov` that would read the register. The constant must
  also be an **integer** of 8 bytes or less: `1.5` is a literal of a registered float type and it
  lives in a float register, so it is never put in `x19..x28`.
- the **address of a global** — a global array's decay to a pointer, and `&global`. That is an
  `adrp` + `add` pair, and both instructions are the same on every iteration.

Each DISTINCT value is counted once, with the same weighting as a local (a use one loop deep counts
eight times) and the same threshold of three, and the values take whatever registers the locals
left. A taken one is built ONCE, at function entry, and every use of it in the function — inside
the loop and outside it — reads the register. `bench/mc/bench.mc`'s sieve loop stops rebuilding
`sieve`'s address and the constant `N` sixty million times; `tests/mc/101-opt-hoist.mc` is the
worked case.

The entry code runs even when the loop is never entered. That is deliberate and it cannot fault: a
symbol address is a relocation and a constant is an immediate, so the cost of a loop that turns out
to run zero times is two to four instructions.

A string literal's address and a function's address are **not** hoisted. Both would have to be
named by a symbol the compiler creates on first use, so hoisting one would move where literals land
in the object for a gain nothing measured.

**A loop exits with one branch.** `loop { if (i >= n) break; ... }` — which is also exactly what the
prelude's `while` expands to — used to cost two taken branches every iteration: one over the
`break`, one back to the top. With `-O` an `if` whose only statement is a `break` or a `continue`
(at any level) is a single conditional branch to the loop's label, and the comparison and the branch
fuse into one `b.<cond>`/`jcc`. On a byte loop that halves the time; it is the largest single
effect `-O` has on loops like the ones below (`tests/mc/103-opt-exit.mc`).

**A constant operand is an immediate, and an address sum folds into the access.** `i + 1`,
`c >> 3`, `c & 7` and `n < 10` take their constant inside the instruction instead of building it in
a register first, and `ld8(p + i)` or `ld64(s + 16)` is one load, `ldrb w9, [x0, x2]` or
`ldr x9, [x0, #16]` (`movzx r8, byte [rdi + rbx]` on x86-64), instead of an add and then a load
(`tests/mc/104-opt-imm.mc`).

**A function that calls nothing keeps its values in the registers it may clobber.** A LEAF — no
call, no `callp`, no intrinsic a module registered — hands out `x0..x7` on AArch64 and `rdi`/`rsi`
on System V x86-64 before any callee-saved register, and those need no save: an 8-byte parameter of
a function whose parameters are all integers simply stays in the register it arrived in. A small
leaf therefore has no save area at all — the four `str`/`ldr` pairs the old reproducer showed in
a function that calls nothing are gone (`tests/mc/105-opt-leaf.mc`). Win64 x86-64 has no such
register to spare, so a Win64 leaf is what it was.

## What it does not do

- **It does not change what your program does.** `scripts/check-opt.sh` compiles every program of
  the corpus twice, links both, runs both, and compares exit code and stdout with each other and
  with the source's own `expect-*` header. The compiler itself is the largest case: an `mc` built
  with `-O` compiles `src/mc.mc` to **byte for byte** the object the plain one writes
  ([bootstrap.md](../bootstrap.md) § The optimized chain).
- **It does not inline, propagate constants, unroll or vectorise.** None of those is in the
  language's compiler today, and the step that could have added the first two measured them first
  and left them out ([M49 § Step E](../specs/M49.md), E.4).
- **It does not help a target whose machine does not offer it.** A machine says how many registers
  it lends the allocator (`MTASK_REG_COUNT`, [machine.md](../reference/machine.md) § 5), and a
  machine that says nothing — `examples/kernel`'s RISC-V 64 and `examples/avr`'s AVR fill the
  thirty-one slots that existed before and leave the six new ones empty — gets **byte-identical
  output on both roads**, with no edit. `--opt=1` on such a target is accepted and does nothing.
  Since M49 step D2 the five machines `mc` itself ships all offer it: `arm64` (macOS, Linux and
  Windows on ARM), `x86_64` and `x86_64-win`.
- **It does not let a runtime keep state in `x19..x28` — or in `rbx`, `r12..r15` — any more.** That
  permission ([objects.md](../reference/objects.md) § 4, § 4b, § 4c) still holds on the plain road
  and is withdrawn for `-O`. Nothing in this repository relied on it.
- **It is not measured on x86-64.** There is no x86-64 machine in this repository's development
  loop, so the table below is AArch64's; the x86-64 allocator's correctness comes from
  `scripts/test-linux.sh` and `scripts/test-windows.sh`, which build every `tests/mc/09[4-9]*`,
  `tests/mc/1*` and `tests/float/*` case on both roads and run them — in Docker for Linux, on the
  two Windows runners for Windows — and compare exit code and stdout with each other and with the
  header. A reproducible x86-64 cell is M50's job.

## What it costs

Measured on this host (Apple M4, macOS 26.6.2), wall clock, best of nine, the three binaries
interleaved so a thermal drift hits all of them:

| | plain | `-O` | `clang -O2` |
|---|---|---|---|
| `bench/mc/bench.mc`, the whole workload | 0.793 s | **0.548 s** | 0.420 s |
| `mix` alone (200M iterations) | 0.445 s | **0.216 s** | 0.215 s |
| `primes` alone (sieve + count over 50M) | 0.215 s | **0.202 s** | 0.138 s |
| `fib(38)` alone | 0.133 s | 0.132 s | 0.073 s |
| `mc` compiling `src/mc.mc` | 0.814 s | 0.807 s | — |
| the `-O`-built `mc` compiling `src/mc.mc` | — | **0.744 s** | — |
| `src/mc.mc`'s `__text` | 535 720 B | **480 420 B** | — |

Four of those rows are worth reading twice. The whole workload lands at **1.30x of `clang -O2`**,
and it is at the gate rather than under it: three runs at growing repetition counts gave 1.29x,
1.31x and 1.29x, so the host's own spread of about 2% straddles the number. **`mix` reaches
parity** — 0.216 s against clang's 0.215 — which is what "the frame round trip was the whole gap"
means. **Compiling with `-O` costs nothing measurable**: the two extra walks over each function's
nodes are linear and the same order as the pass that already resolves them. And the optimized code
is **smaller**, not bigger, by 10%: two instructions per allocated register per function is less
than the frame traffic and the re-materialised constants it removes.

Two rows do not move and both are expected. `fib`'s cost is the number of calls it makes, not the
quality of what happens between them — `clang -O2` wins there by turning one of the two recursive
calls into a loop, which is not something this compiler does. `primes` keeps a 0.06 s gap that is
`clang -O2`'s NEON vectorisation of the counting loop; nothing here vectorises.

## Step E, measured

The rows above are the allocator's. [M49 § Step E](../specs/M49.md) measured the exit branch, the
immediates and the leaf registers on three benchmarks, in ONE sitting on the same Apple M4 — which
was in low-power mode that day, so every absolute number is about 1.9x the table above; the ratios
are what compare:

| | `-O` before | `-O` after | `clang -O2` |
|---|---|---|---|
| `bench/mc/bench.mc`, the whole workload | 1.030 s (1.31x) | **0.992 s (1.26x)** | 0.788 s |
| `bench/leaf` `sum` (a byte sum, 4096 bytes x 200 000) | 0.798 s | **0.404 s** | 0.079 s (0.403 without vectorising) |
| `bench/leaf` `spn` (php's `strspn` loop) | 1.193 s | **0.596 s** | 0.579 s |
| `bench/leaf` `dadd` (a digit-buffer add) | 1.511 s | **0.603 s** | 1.626 s |
| `bench/leaf` short inputs (16 bytes, 40M calls of the three) | 3.307 s | **1.610 s** | 1.118 s |
| mc-php's `examples/decimal` (`bench.php`, per run) | 0.992 ms | **0.812 ms** | its C twin: 0.240 ms |

Removing one item at a time from the finished compiler says which item bought what: without the
exit branch the short phase is 2.850 s and `decimal` 0.918 ms; without the immediates and
addressing, 2.214 s and 0.889 ms; without the leaf registers, 1.663 s and 0.845 ms.

## Reading what it did

`--dump-asm` honours the flag, so the two lowerings can be put side by side:

```
diff <(mc --dump-asm prog.mc) <(mc --dump-asm --opt=1 prog.mc)
```

A program with no candidate produces the same text either way, which is the cheapest check that
nothing was optimized behind your back.
