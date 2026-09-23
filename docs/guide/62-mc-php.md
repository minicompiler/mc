# PHP, carried by one module

[mc-php](https://github.com/minicompiler/mc-php) is a compiler for PHP 8.5 whose entire front end
is a Tier 3 module: the grammar, the type system, the library surface, all of it taught from
ordinary source, with nothing added to `src/` and nothing added to `stage0/`. It is not part of
this repository and it does not need to be. It consumes a published release the way any other
project does.

It is here in the guide because of what it measures. [30-teaching.md](30-teaching.md) claims a
module can carry a language; this is the largest answer anyone has given that claim, and it
answers it in numbers rather than in prose.

## What it does

A `.php` file is PHP. It runs under `php` and it compiles with `mc-php`, and the two must agree —
so the oracle is not a test suite somebody wrote for it, but php-src's own `.phpt` corpus, run
under both. There is no dialect, no annotation and no "mc-php mode".

```php
<?php
declare(strict_types=1);

function fib(int $n): int { return $n < 2 ? $n : fib($n - 1) + fib($n - 2); }

echo fib(30), "\n";
```

Over the whole corpus — 21,395 tests — the compiler and `php` agree on **1,704**, byte for byte on
stdout and on the exit code. That number was measured on 2026-09-23 and the repository records the
day it was taken beside every figure it publishes, because a number without its date is a claim
about the past pretending to be a claim about now.

## What it costs the module

The grammar is seventeen files of `.mc`. Classes, interfaces, traits, enums, closures, arrow
functions, exceptions with `finally`, generators, references, `list()` destructuring and PHP's own
precedence table all live there — in the module, not in the core.

Three things it needed did not exist, and each arrived as an additive `mc` release rather than as
a patch to the core:

| what was missing | why | where it landed |
|---|---|---|
| `p_skip_to` | PHP has four regions the core lexer cannot tokenize — a single-quoted string, a `#` comment, the raw text between `?>` and `<?php`, and a heredoc body. A handler must be able to read them itself and say where it stopped. | 1.1.0 |
| `syntax_expr("$")` | `$name` is a variable in PHP and a `#rule` hole in mc. Outside a template, a registered handler now sees it. | 1.1.0 |
| the `--exe` export fix | an executable's own symbol table became unreadable once its zerofill crossed a page, which a host that `dlopen`s a plugin needs | 1.0.1 |

That is the shape the surface is meant to have. A consumer finds the edge, the edge is reported
with a reproducer, and the answer is a new name — never a rename, never a change to what already
worked. [../reference/hooks.md](../reference/hooks.md) § 8 is the policy those three releases
obeyed.

## The state, and where the detail is

mc-php is a proof of concept and says so in its own README. What exists today is the front end,
and a program it compiles is a macOS program, because the runtime it embeds is built on mc's
libSystem layer. The back end that emits a native PHP **extension** — a `get_module()`, a
`zend_module_entry` and the handler tables php loads — is the line being built now.

Everything about using it lives in the repository, and this page deliberately does not copy it:

- [the README](https://github.com/minicompiler/mc-php#readme) — what works today, how to build it,
  how to run the corpus, and how to install a tagged release;
- [`docs/mcphp-toml.md`](https://github.com/minicompiler/mc-php/blob/main/docs/mcphp-toml.md) — the
  project file an extension is described by, in the same relation to mc-php that
  [20-project-toml.md](20-project-toml.md) describes for `mc`;
- [`docs/plan.md`](https://github.com/minicompiler/mc-php/blob/main/docs/plan.md) — the decisions
  and what each one cost.

## Next

The two examples that live in this repository, and what each of them teaches:
[60-examples.md](60-examples.md).
