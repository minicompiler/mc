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

**It keeps locals and parameters in callee-saved registers.** On AArch64 that is `x19..x28`, ten of
them, one per declaration, for the length of a function. Before, every read of a local was a load
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

## What it does not do

- **It does not change what your program does.** `scripts/check-opt.sh` compiles every program of
  the corpus twice, links both, runs both, and compares exit code and stdout with each other and
  with the source's own `expect-*` header. The compiler itself is the largest case: an `mc` built
  with `-O` compiles `src/mc.mc` to **byte for byte** the object the plain one writes
  ([bootstrap.md](../bootstrap.md) § The optimized chain).
- **It does not inline, propagate constants, unroll or vectorise.** None of those is in the
  language's compiler today.
- **It does not help a target whose machine does not offer it.** A machine says how many registers
  it lends the allocator (`MTASK_REG_COUNT`, [machine.md](../reference/machine.md) § 5), and a
  machine that says nothing — `examples/kernel`'s RISC-V 64 and `examples/avr`'s AVR fill the
  thirty-one slots that existed before and leave the six new ones empty — gets **byte-identical
  output on both roads**, with no edit. `--opt=1` on such a target is accepted and does nothing.
  The x86-64 machines are in that state today too; the allocator there is a later step.
- **It does not let a runtime keep state in `x19..x28` any more.** That permission
  ([objects.md](../reference/objects.md) § 4) still holds on the plain road and is withdrawn for
  `-O`. Nothing in this repository relied on it.

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

## Reading what it did

`--dump-asm` honours the flag, so the two lowerings can be put side by side:

```
diff <(mc --dump-asm prog.mc) <(mc --dump-asm --opt=1 prog.mc)
```

A program with no candidate produces the same text either way, which is the cheapest check that
nothing was optimized behind your back.
