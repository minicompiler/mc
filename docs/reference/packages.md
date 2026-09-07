# Packages

> **Trust.** A library package is source `mc` compiles; a compiler-module package is code that
> RUNS on your machine at build time, inside the taught compiler `mc build` spawns. The brakes are
> the lock (nothing runs that is not the bytes you reviewed) and the closure rule (a package reads
> its own tree, libraries the binary ships, and its declared dependencies — nothing else). They do
> not stop a module that opens a file through an `extern`. Until `mc sandbox` wraps the spawn,
> **a compiler-module package is trusted code**.

This page is the reference for what a package IS, how `#include <name>` is resolved, what
`mc.lock` says, what `mc build` refuses, and what `mc pkg` does — the registry, minimal version
selection, the fetch, the lock writer and vendoring.

---

## 1. Angle brackets are libraries, quotes are my files

```c
#include "vec.mc"              // a file of mine, next to the includer or on [include].paths
#include <geo/geo.mc>          // a file of the package `geo`, at the version mc.lock pins
#include <geo>                 // the same, through geo's `lib` entry
#include <float>               // a library this binary ships — unless a lock says otherwise
#include <mc/core>             // the compiler's own source
```

`<name>` means **a library that is not in my tree**. It is never resolved against the working
directory, so the answer to `<float>` is a function of *(this binary, this lock, the installed
packages)* and of nothing else — dropping a `float.mc` next to `main.mc` cannot change it.

A trailing `.mc` is dropped from every `<...>` name, so `<geo/geo.mc>` and `<geo/geo>` are one
name and both land on `geo.mc` on disk. A payload with another extension keeps it
(`<pack/table.txt>` for an `#embed`).

The same spelling goes into `[compiler].modules`:

```toml
[compiler]
out     = "build/mc-app"
modules = ["<teach/mc_teach.mc>", "user.mc"]
```

A value that starts with `<` is emitted into the generated compiler source verbatim, with no
`../` adjustment — the rule `[compiler].core` has carried since M41.

## 2. The resolution order

`#include <X>` is answered by the first of three steps that has it.

| step | who answers | for which names |
|---|---|---|
| 1 | the **lock** | `X`'s first path component is a package `mc.lock` names, and the file asking is allowed to reach it (§ 5) |
| 2 | the **bundle** — the copy inside this binary ([bundle.md](bundle.md)) | every name in the manifest, plus `<mc/bundle_data>` and `<mc/bundle.bin>` |
| 3 | the **installed `mc` package** under `<libs>/mc/v<version>/` | the same names as step 2, when the binary carries no bundle |
| — | nobody | `prog.mc:1: unknown bundled include: no/such/module` — or, in a binary that carries no bundle AND has no installation, `prog.mc:1: #include <prelude>: not bundled in this compiler and mc 0.16.0 is not installed: run mc install` |

Step 1 exists only where a lock was read, which is `mc build`. The single-file CLI
(`mc x.mc -o x.o`) has no project and therefore no step 1: `<geo/geo.mc>` there is
`unknown bundled include: geo/geo`, and `--include=DIR` plus a quote include is the hand road.

Step 3 is reached only on a bundle miss. For a binary that carries the blob — the full flavour —
that means a name nobody ships, so a full `mc` behaves exactly as it did before packages existed
unless a lock says otherwise. For **`mc-slim`** ([bundle.md](bundle.md) § The slim flavour) it
means every `<name>` there is, which is what `mc install` ([cli.md](cli.md) § 3e) is for.

What step 3 reads is `<libs>/mc/v<version>/` in the REPOSITORY layout, with one extra file:

```
~/.mc/libs/mc/v0.16.0.toml      the cache manifest: name, version, tree hash, one [[file]] row each
~/.mc/libs/mc/v0.16.0/
    mc.toml                     the package manifest, hashed first
    bundle.list                 the NAME<TAB>PATH map, copied up from tools/ by `mc install`
    src/…  lib/…  tools/…       every path of [package].files (§ 11)
```

`bundle.list` at the root is what turns a name into a path: `<float>` is `lib/float.mc`,
`<mc/core>` is `src/core.mc`. The repository keeps that file under `tools/`, and the copy at the
root is deliberately **not** in `[package].files` — it must not move the tree hash the registry
published.

**Where a locked package's tree is**, in order:

1. `deps/<pack>/` beside `mc.toml` — the vendored tree. When it is there the installation is not
   consulted at all: `deps/` plus `mc.lock` in git is the fully offline project.
2. `<libs>/<pack>/v<version>/`, and only that version. A `v1.0.0/` sitting beside a locked
   `v1.2.0/` is never opened, so it cannot change a byte.

`<libs>` is `--libs-dir DIR` when given, else `$HOME/.mc/libs`. CI passes the flag so that no job
depends on `HOME`, exactly as `--sysroot-dir` does for [sysroots](sysroot.md).

## 3. The package manifest

A package is a source tree with an `mc.toml` at its root carrying a `[package]` table:

```toml
[package]
name   = "geo"
files  = ["geo.mc", "vec.mc"]
lib    = "geo.mc"        # optional: what a bare `#include <geo>` means
module = "mc_geo.mc"     # optional: the file a COMPILER includes

[deps]
mathx = "1.0.0"
```

`files` is not documentation. It is the hash's input, the vendor-copy list, and the boundary
§ 5 enforces. It is written by hand because `mc` has no directory listing — the same reason
`tools/bundle.list` exists.

**Every entry is a relative path inside the package, and that is checked.** An entry may not

* be empty, or start with `/`;
* contain a `.` or a `..` component, or an empty one (`a//b`), or end with `/`;
* contain a backslash, any byte below `0x20`, or one of the characters Windows reserves in a
  name -- `:` (a drive letter, an NTFS stream), `<`, `>`, `"`, `|`, `?`, `*` -- because the rule is one
  rule for the three hosts and `C:/x` is absolute to a Windows extractor;
* resolve, after normalisation, to anything outside the package's own directory.

Anything else is `<pack> <ver>: files entry escapes the package: <entry>`, exit 2, at every place
the list is used: the tree hash `mc build` recomputes, the cache manifest a fetch writes, the copy
`mc pkg vendor` makes, and the per-file attribution of a mismatch. The reason is that the list
arrives inside a downloaded tree and is then handed to `open`, to `write` and (before this rule)
to `unlink`: `files = ["../../../../.ssh/id_rsa"]` used to be read on every build, and
`mc pkg vendor` used to write it outside the project.

### `[package].check` -- what the registry compiles

A registry validates a tag by compiling the package, and a package that carries **alternatives**
-- a host layer per system, a machine per architecture, a data file that is not source -- has no
single translation unit that holds all of it. `check` names the ones it does have:

```toml
[package]
name  = "geo"
lib   = "geo.mc"
files = ["geo.mc", "geo_linux.mc", "geo_macos.mc"]
check = ["geo_linux.mc", "geo_macos.mc"]
```

Each entry is a translation unit, compiled **on its own**. A path is relative to the package root,
may not leave it (the rule `[package].files` entries obey, above), and must be listed in `files`
-- the tree hash covers `files` and nothing else, so a unit the package does not ship is one no
consumer would receive. With no `check` key the unit is `lib`, which is what a package with one
answer per platform already is.

**The compiler does not read this key**: it is a manifest key for whoever validates the package,
and `mc build`, `mc pkg hash` and `mc pkg sync` behave exactly as they do without it. It does take
part in the tree hash, like every other byte of `mc.toml`.

### The kind: library or tool

A package's kind is written in exactly one place, `[project]`:

| the package's `mc.toml` | kind |
|---|---|
| `[package]` and no `[project]` | library |
| `[package]` + `[project] kind = "obj"` | library that also builds an object of its own |
| `[package]` + `[project] kind = "exe"` | **tool**: a program to install and run, not a tree to compile into yours |
| `[package]` + `[project]` with no `kind` line | refused: `a package's [project] must say kind = "obj" or "exe"` |

The last row is refused because `mc build` defaults `kind` to `exe`, so a library that carries a
`[project]` for its own tests would silently be classified as a program. A tool also carries
`[package].bin`, the name it takes in `~/.mc/bin` -- `[a-z][a-z0-9_-]*`, at most 32 bytes, the one
name in a manifest that may have a hyphen, because it is a file name and not an identifier --
defaulting to the basename of `[project].out`. `[package].licence` is an SPDX identifier the
registry shows; the compiler reads it only to compare an index row against the archive it claims
to describe.

A tool is named under `[tools]`, never under `[deps]`, and a library the other way round; the
registry publishes the kind and `mc pkg sync` refuses the wrong table by name.

### `[[permission]]` -- what a package asks to be allowed to do

```toml
[[permission]]
kind   = "fs.read"
path   = "workspace"
reason = "reads the sources it is asked about"

[[permission]]
kind = "exec"
name = "mc"
```

| kind | key | the fixed sentence a developer reads |
|---|---|---|
| `fs.read` | `path` | may read files under PATH |
| `fs.write` | `path` | may create, change and delete files under PATH |
| `net` | -- | may open network connections to any host and port |
| `exec` | `name` | may run the program NAME found on your PATH |
| `env` | `name` | may read the environment variable NAME |

`path` is one of four forms and never an absolute path: `workspace` (the directory the tool is run
from), `tmp`, `workspace/<rel>` or `home/<rel>`, with `<rel>` under the same containment rule
`[package].files` entries obey. At most 32 rows; no rows at all means **stdio only**. `reason` is
at most 120 bytes, is shown and never compared.

Each row becomes one canonical line -- `fs.read workspace`, `net`, `exec mc` -- and the set,
duplicates collapsed and sorted bytewise, is what the index row carries, what `mc pkg sync` prints
before it fetches anything and what the lock records (§ 4). A wrong kind, a path on `net`, a name
on `fs.read`, a path that escapes: each is refused at the offending key's own `file:line:col`, and
a tree whose manifest is refused during a fetch never gets a cache manifest, so the next build
says `is not fetched` rather than reading it.

> **What was checked, and what was not.** These permissions were declared by each package's author
> and checked by the registry where the package runs a test; a library runs inside your program and
> is held to nothing at run time. `mc` prints that sentence with the table, and it does not say
> "safe": it says what was checked. What enforces a TOOL's set is the sandbox `mc tool run` puts it
> in, on a host that has one; installing and running a tool is [tools.md](tools.md).

**A package never defines `user_init`.** It exports `<name>_init()` and the project's own module
calls it, because a compiler holds exactly one `user_init` and the order of initialisation is the
project's decision:

```c
// user.mc, in the project
void user_init() {
    teach_init();
}
```

## 4. The lock

`mc.lock` sits beside `mc.toml`, is written only by `mc pkg sync` (§ 10), and has one
`[[package]]` row per resolved package, sorted by name — a total order over unique keys, so two
runs of `sync` write the same bytes:

```toml
# written by `mc pkg sync` -- do not edit (docs/reference/packages.md)
[[package]]
name        = "geo"
version     = "1.2.0"
lib         = "geo.mc"
sha256      = "ba1924dc...9776f"
deps        = ["mathx"]
permissions = []

[[package]]
name        = "hello_tool"
version     = "0.1.0"
kind        = "tool"
bin         = "hello-tool"
sha256      = "14d2e51a...58d6b"
deps        = []
permissions = ["fs.read workspace", "net"]
```

`deps` is the edge list § 5 reads. `lib` is what a bare `<geo>` means. `sha256` is the tree hash.

`kind` and `bin` are written for a **tool** only, so a row without `kind` is a library -- which is
what every row of every lock written before tools existed says, and why those locks read exactly as
they did. A tool's row registers no include root and its tree is never opened by a build.

`permissions` is the set this project has **accepted**, in canonical form and sorted; it is written
for every row, including as `[]`. Before it rewrites the lock, `mc pkg sync` compares each
package's set with the old lock's row of the same name, whatever version that row pinned: a set
that is not a subset of the accepted one has to be read and accepted again, a row the old lock does
not carry at all was never accepted, and a row with no `permissions` key -- a lock written before
the key existed -- is an empty accepted set. So a dependency whose new version adds `net` prints
and stops, and one that drops a permission is silent.

**The lock is checked, not trusted**: `mc build` rehashes every locked package on **every** build
and refuses on any disagreement. A dependency's source is about to be lexed anyway.

### The tree hash

For `mc.toml` first and then each entry of `[package].files` **in manifest order**, one line

```text
<64 hex of sha256(file bytes)><space><byte length of the path><colon><path><LF>
```

and the tree hash is the `sha256` of those lines, in plain hex. This is the shape of Go's
`dirhash.Hash1`, without its `h1:` base64 spelling — **and with the path length-prefixed**, which
Go's is not. Go derives its file list from a zip it built; here the list is an array in an mc.toml
that was downloaded, so a path is attacker-controlled and `<hex><two spaces><path><LF>` cannot say
which file list produced a given stream of lines. A control byte in a `files` entry is refused
outright (§ 3), so the ambiguity has no way in; the length prefix is what stops the *format* from
being able to express it.

What makes it stable across hosts: it is over **content**, never over an archive (GitHub
regenerated its tag tarballs in 2023 and broke every archive-checksum consumer; a content hash did
not move); it names each file explicitly instead of listing a directory; and it carries no mtime,
no mode and no ordering of its own — manifest order is the canonical order. Bytes are taken
exactly as they are on disk, so a checkout that translates line endings changes the hash. This
repository sets `* -text` in `.gitattributes` for that reason.

`mc pkg hash DIR` prints it. `scripts/pkg-hash.sh DIR` is the same rule in shell, and
`make check-pkg` compares the two implementations against every lock checked into `tests/pkg` on
every run — a divergence between the compiler and this page is a red `make check`, not a surprise
at a consumer.

### The cache manifest

Beside an installed tree, `<libs>/<pack>/v<version>.toml` records what was installed:

```toml
[source]
name    = "geo"
version = "1.2.0"
sha256  = "ba1924dc...9776f"

[[file]]
path   = "mc.toml"
sha256 = "..."
```

It is written **last**, after the tree is complete, so it is the claim that the directory holds
what the lock says: a half-extracted tree has no manifest and is reported as *not fetched* rather
than as *does not match*. It is also what lets a mismatch name the FILE that moved — the lock
carries one hash per package, so without a manifest (a vendored tree) the refusal names the tree.

## 5. A package is closed

A file under a package root may read:

* its own tree, with quotes and relative paths;
* `<...>` names the bundle or the installed `mc` package answers;
* `<dep/...>` where `dep` is in its own lock row's `deps` — or itself.

Anything else is refused, for `#include` and for `#embed` alike:

```text
geo/vec.mc:3: package geo reaches outside its tree: /etc/hosts
```

A `<...>` name whose first component is a locked package the file may NOT reach is not silently
downgraded to the bundle's answer and it is not silently allowed: step 1 is skipped, and if
nothing else answers, the refusal above is what comes out.

After the parse, every file the build actually READ under a package root is checked against that
package's `files`:

```text
geo/extra.mc:1: not declared in geo's [package].files
```

That is what makes `files` a boundary. An author who forgets a file ships one that fails loudly at
the first consumer; a file planted inside a fetched tree is refused even though the tree hash — which
covers only what the manifest lists — did not move.

## 6. Names

`[a-z][a-z0-9_]*`, at most 32 bytes: a bare TOML key, a valid path component on all three hosts,
and a valid identifier prefix (`geo_init`). Upper case and `-` are out so that one spelling is the
only spelling.

Reserved, in `[deps]` and in the registry: **`mc`** and every `mc/...` name, **`deps`** and
**`build`**. `mc` is the compiler's own package — `<mc/core>` is the source of the compiler that
is *running*, and a taught compiler assembled from a foreign one would not be the compiler that
built it.

A bundled library name is **not** reserved. A registry package may carry `float`, `sys` or `i128`,
and a project that pins `[deps] float = "1.3.0"` gets that tree for `<float>` and
`<float/float_rt.mc>` instead of the blob. That is safe on both counts that matter: the row pins a
content hash and `mc build` rehashes, so two machines with the same binary, lock and bytes resolve
the same bytes; and a project with no such line is byte for byte what it was.

## 7. Development: `[replace]`

```toml
[replace]
geo = "../geo"
```

points a name at a local tree. A replaced package is **not pinned and not hashed**, and `mc build`
says so on stdout:

```text
replaced geo: ../geo -- not pinned by mc.lock
```

Go's `go.sum` omits path-replaced modules for the same reason.

## 8. Refusals

Every one of these is exit **2** — "the environment is not ready" — except the two that are about
the source, which are exit 1. See [diagnostics.md](diagnostics.md) § 13.

| disagreement | message | exit |
|---|---|---|
| a file's bytes differ from the manifest's line | `mc: geo 1.2.0: vec.mc does not match mc.lock` | 2 |
| the tree hash differs but no file line does (the `files` list changed) | `mc: geo 1.2.0: mc.toml does not match mc.lock` | 2 |
| the same, with no manifest to attribute it to (a vendored tree) | `mc: geo 1.2.0: the tree does not match mc.lock` | 2 |
| `[deps]` names a package the lock lacks, or asks a minimum above the lock | `mc: mc.lock is stale: geo` | 2 |
| the lock names a version that is neither vendored nor installed | `mc: geo 1.2.0 is not fetched` | 2 |
| a package reads outside its tree | `geo/vec.mc:3: package geo reaches outside its tree: ...` | 1 |
| a file the build read is not in that package's `files` | `geo/extra.mc:1: not declared in geo's [package].files` | 1 |
| a reserved or malformed name in `[deps]`/`[replace]` | `mc.toml:8:6: reserved package name: deps.mc` | 1 |
| a `[package].files` entry that leaves the package (§ 3) | `mc: geo 1.2.0: files entry escapes the package: ../x` | 2 |
| an archive member that is a link | `mc: v1.2.0.tar.gz: archive member is a link: geo-1.2.0/x` | 2 |
| an archive member that leaves the destination | `mc: v1.2.0.tar.gz: member escapes the archive: ../x` | 2 |
| a body over its cap (64 MiB for an archive, 1 MiB for an index file) | `mc: larger than the cap of 67108864 bytes: <source>` | 2 |

The exit-2 refusals carry the M25 `run:` line:

```text
mc: mathx 1.0.0 is not fetched
  run:   mc pkg sync --yes
```

## 9. What `mc build` does NOT do

**It never downloads.** There is no downloader in the read side at all: it reads the lock, finds
each tree in `deps/` or `<libs>`, hashes, registers the roots, compiles. `make check-pkg` proves
it rather than asserting it — the whole run has a `curl`, a `wget` and a `tar` on `PATH` that fail
if they are invoked.

**It never opens a directory no lock names**, and it never guesses a version.

A compiler assembled without `<mc/core_pkg>` cannot download even in principle: it has no
fetcher, no registry and no lock writer, and it still builds every project above. That is the
CI and consumer shape ([bundle.md](bundle.md) § The parts).

---

## 10. `mc pkg` — resolving, fetching and locking

Everything below is `<mc/core_pkg>`'s. The command lines are in [cli.md](cli.md) § 3d.

### The registry

One file per package, at `<registry>/index/<name>.toml`:

```toml
# index/geo.toml
[package]
name        = "geo"
repo        = "https://github.com/minicompiler/mc-geo"
description = "2-D vectors"

[[versions]]
version = "1.0.0"
url     = "https://github.com/minicompiler/mc-geo/archive/refs/tags/v1.0.0.tar.gz"
strip   = 1
sha256  = "<the tree hash of that tag's checkout>"
deps    = ["mathx 1.0.0"]

[[versions]]
version = "1.2.0"
url     = "https://github.com/minicompiler/mc-geo/archive/refs/tags/v1.2.0.tar.gz"
strip   = 1
sha256  = "..."
deps    = ["mathx 1.1.0"]
yanked  = true          # optional, and the ONLY thing a published row may gain
```

`sha256` is the **tree hash** of § 4, never the archive's: a forge that regenerates its tag
tarballs (GitHub did, in 2023) does not move it. `strip` is what `tar --strip-components` gets, 1
for the `<repo>-<version>/` top directory a tag archive has. `deps` carries each requirement as
`"<name> <minimum>"`, which is what lets version selection run over the index alone, with no
archive downloaded.

**Where the index comes from.** `--registry`, else `[registry].url`, else
`https://pkg.minicompiler.dev` — a package **server** that produces exactly this layout out
of the git repositories registered with it. That host is the registry's canonical name; the site
answers `https://minicompiler.dev/registry/index/<name>.toml` with the same bytes, which is what a
compiler older than 0.15.6 asks for by default. The compiler's side of that is a reader and a
constant: there is no API client here, no JSON, no search and no transparency log. A **directory**
with the same layout is a registry too, read in place, which is what a private tap costs: a
`git clone` and one line of TOML. A URL registry is fetched one file at a time into
`<libs>/index/<name>.toml`, the snapshot every later `mc pkg` in that project reads.

Publishing into that server is a website, a GitHub Release and a CI action, none of it in the
compiler: [guide/27-publishing.md](../guide/27-publishing.md). An account there may hold API
tokens (`/me` > Tokens, scope `poll` only) with which the CI action polls a repository as the
account rather than anonymously; the guide's § 7 says what they buy and what they cannot do.

### Minimal version selection

Go's algorithm (`cmd/go/internal/mvs`), exactly:

1. the build list starts from the project's `[deps]` minimums;
2. for every selected `(name, version)`, the requirements of **that** version's index row are
   added;
3. a name's selected version is the **maximum over every minimum that mentions it**;
4. repeat to a fixed point.

No search, no SAT and no "latest": the answer is a function of the index alone, and the lock then
freezes it, so the index can move afterwards without moving the build. A project asking for
`mathx 1.0.0` whose `plot` asks for `mathx 1.1.0` gets **1.1.0** — not 1.0.0, and not the 2.0.0
the registry also carries.

**Two majors of one name are refused, not solved:**

```text
mc: mathx: 1.0.0 and 2.0.0: different majors: no solver
```

exit 1, and no lock is written. Semantic import versioning (`/v2` in the name) is out of scope.

**Yanked** is Go's `retract`: `mc pkg add` and `mc update` skip such a row, and a lock that
already pins one keeps working — a published build never breaks retroactively. `mc update` also
stays inside the current major: raising a minimum across a major is not an update, it is the case
above.

### Versions, and pre-releases

A version is `X.Y.Z` with the optional `-pre.release` and `+build` parts of
[SemVer 2.0](https://semver.org). Comparison is the specification's, § 11:

1. the three numeric fields decide first, each compared as a number;
2. a version **with** a pre-release suffix is **lower** than the same `X.Y.Z` without one, so
   `1.2.0-rc1 < 1.2.0`;
3. two suffixes compare identifier by identifier, `.` separated: an all-digit identifier ranks
   below an alphanumeric one and compares by value, anything else compares byte for byte, and
   when everything so far is equal the shorter list is the lower one;
4. `+build` metadata is ignored.

So the specification's own chain holds:

```text
1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta < 1.0.0-beta.2
            < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
```

**A pre-release is never chosen for you.** `mc pkg add NAME` with no `@` and `mc update` skip
every pre-release row, exactly as `go get` does; a candidate enters a project in one of two ways
only:

* `mc pkg add NAME@1.2.0-rc1` — asked for by name;
* `mc update NAME` when the minimum already written in `[deps]` is itself a pre-release, which is
  the reader saying they are on that train. Even then a released version wins whenever there is
  one, because `2.1.0-rc1 < 2.1.0`.

Minimal version selection never picks "newest" at all, so it can only reach a candidate that some
`[deps]` or index row names outright.

A registry that has published nothing but candidates says so instead of guessing:

```text
mc: only pre-release versions are registered: name one, NAME@VERSION: mathx
```

`mc.lock`, `<libs>/<pack>/v<version>/` and the index carry the suffix **verbatim** — `v2.1.0-rc1/`
is a directory name like any other.

### The fetch

In `mc sysroot fetch`'s order of operations, and for the same reasons:

1. download the archive to `<libs>/<pack>/v<version>.tar.gz` (an `https://` url through
   `curl`/`wget` with the HTTPS-only flags; a source with no scheme is a local path, copied).
   **An archive is refused above 64 MiB and an index file above 1 MiB**, before either is read:
   `mc: larger than the cap of 67108864 bytes: <source>`, exit 2;
2. **list the archive and check every member** (below), then `tar -xzf` it into
   `<libs>/<pack>/v<version>/` with the row's `strip`;
3. **hash the tree and compare it to the row, before anything else.** On a mismatch every file the
   EXTRACTION wrote is unlinked and no manifest is written:

   ```text
   mc: checksum mismatch for geo 1.2.0
     expected ba1924dc...
     got      2b7c01f9...
   ```

   exit 2. The archive itself is not checksummed — § 4 says why — so unlike a sysroot the refusal
   comes after the bytes are on disk, but still before any manifest exists and before any build
   can consume the tree;
4. write `<libs>/<pack>/v<version>.toml` **last**. That file is the claim.

A download that fails leaves no claim either: `mc: the download failed (exit 22): <url>` for a URL
and `mc: cannot open: <path>` for a path, exit 2, and the next `mc build` says `is not fetched`
rather than reading debris. So does a tree whose `mc.toml` is refused after extraction — an entry
that escapes (§ 3), or one naming a file the archive does not carry: the tree is cleared first and
the message comes second, and what is cleared is the member list from step 2, never the list in
the mc.toml that has just been refused.

#### The archive member rule

`tar` is not trusted with a file somebody else produced. Before any extraction the archive is
listed twice — `tar -t...f` for the names, one per line, and `tar -tv...f` for the ls-style type
character — and a member is refused when it

* is a symbolic link or a hard link (`mc: <archive>: archive member is a link: <member>`);
* is absolute, or carries a `.`/`..` component, or lands outside the destination once
  `--strip-components` has been applied
  (`mc: <archive>: member escapes the archive: <member>`);
* is one of more than 1 MiB of names, or the two listings disagree.

Every refusal is exit 2 and unlinks the archive. After the extraction each listed member has to be
there as a file `open` can read, which is what says tar wrote what tar said it would; that last
check is skipped when the caller asked for a subset of members, which only `mc sysroot fetch`
does. A member is never named back to `tar` on the extraction: an argument list is
space-separated here and a member name may contain a space.

Nothing downloads without `--yes`. Without it every verb that would fetch prints the plan and
stops:

```text
fetch  plot 1.0.0
url    /path/to/archives/plot-1.0.0.tar.gz
sha256 f5e0f0c64e85...
into   /path/to/libs/plot/v1.0.0/
nothing was downloaded: re-run with --yes
```

`mc` has no `isatty`, so there is no prompt — the plan is the prompt.

### The install table

After selection and **before a byte is downloaded**, `mc pkg sync|add|update` print what they would
fetch and, when something in the build list asks for a permission the current lock does not already
record as accepted (§ 4), the permission table with it:

```
fetch  hello_tool 0.1.0      tool  bin hello-tool
url    https://example.invalid/hello_tool-0.1.0.tar.gz
sha256 14d2e51a...58d6b
into   /home/me/.mc/libs/hello_tool/v0.1.0/

permissions
  hello_tool 0.1.0 fs.read workspace     may read files under the directory it is run from
                   net                   may open network connections to any host and port
  mathx 1.0.0      (none: stdio only)
these permissions were declared by each package's author and checked by the registry where the package runs a test; a library runs inside your program and is held to nothing at run time
tools required by this project
  hello_tool >= 0.1.0
nothing was downloaded: re-run with --yes to fetch and to accept the permissions above
```

The set shown is the **index row's**, so it is on the screen before anything is fetched; the set
written into the lock is the tree's own, after the fetch, and the two cannot disagree without the
tree hash disagreeing first. A row that is a library and asks for something carries
`(declared by the author; a library runs inside your program)` under it, for the reason the trust
box in § 3 gives.

`--yes` accepts what was printed; there is no second flag, and the lock diff in the project's git
history is the review record. A `sync` with nothing at all to download but an unaccepted, non-empty
set stops the same way; a package that asks for nothing never turns a silent `sync` into one that
needs `--yes`.

### The lock writer

`mc pkg sync` writes every row from the tree it just resolved, never from the index's claim about
it: `version` is what selection chose, `lib`, `deps`, the kind, `bin` and `permissions` come out of
the package's **own** `mc.toml`, and `sha256` is the tree hash of what is on the disk. A `[replace]`d package gets a
`path` line and no hash (§ 7). Rows nothing requires are dropped, because the lock is written from
the build list and from nothing else.

### Vendoring

`mc pkg vendor` copies each locked tree into `deps/<pack>/` — `mc.toml` plus `[package].files`,
which is the same list the hash is over, checked entry by entry against § 3 before a byte is
written — and then verifies. `deps/` plus `mc.lock` in git is the
fully offline project: a build with an empty `<libs>` produces a byte-identical object, and
`make check-pkg` asserts exactly that.

### `mc pkg check` — the registry gate

What the registry's CI runs on every changed index file, and what an author runs before opening
the pull request. It refuses:

* a `[package].name` outside the name rule (§ 6) or a reserved one — `mc` above all;
* a row with no `url`, no `sha256`, or a `sha256` that is not 64 hex characters;
* with `--yes`, a row whose **archive** disagrees with it: the tree hash, the package name, the
  set of `[deps]` — `the archive requires a package the row does not list: mathx` — or any of the
  five keys a row carries about the manifest: `kind`, `bin`, `licence`, `permissions` and `tools`
  (`the row's permissions are not the archive's`). A row is what a consumer reads before fetching
  anything, so a row that under-declares its archive is a row asking for consent to the wrong
  thing;
* against the registry's current copy, any edit to a published row except adding `yanked = true`:
  `mc: plot 1.0.0: a published row was edited: only yanked = true may be added`, and
  `a published version was removed` for a row that vanished.

Rows are immutable because that is the one property of a checksum database worth keeping when you
have no server to run one on: the git history of the index IS the audit log.

**The immutability check never passes by default.** Comparing needs the published copy, so with a
URL registry it needs `--yes` — without it, `check` says so and stops
(`mc: check needs --yes to compare against the published index: <name>`, exit 2) rather than
answering "unchanged" by doing nothing. With `--yes`, only the downloader's own "no such file"
(`curl -f` exits 22, `wget` 8) means *a new package*; any other failure is
`mc: check: cannot read the published index for <name>: <reason>`, exit 2. With a directory
registry the comparison is free and neither case arises.

## 11. The `mc` package — this repository

`minicompiler/mc` carries an `mc.toml` at its root, so the compiler's own tree
**is** a package. It is what the release workflow announces to the registry on
every tag (`.github/workflows/release.yml`, job `publish-to-registry`), and what
`<libs>/mc/v<version>/` holds for a binary that answers `<mc/...>` from an
installation instead of from a blob (§ 2, step 3).

```toml
[package]
name  = "mc"
lib   = "src/core.mc"
check = ["src/mc_linux_x86_64.mc"]
files = [ "lib/backend_arm64.mc", …, "tools/bundle.list" ]
```

* **`name = "mc"`** — M44's D15': the package `mc` is the whole bundle at the
  compiler's version. It is the one reserved name the registry admits, and only
  from this repository.
* **`lib = "src/core.mc"`** — a bare `#include <mc>` is the compiler *without*
  `user_init`: what `[compiler].core` defaults to, and what every taught
  compiler in this tree includes. It carries its own `main()`, so a consumer
  adds a host layer and a `user_init` and nothing else.
* **`check = ["src/mc_linux_x86_64.mc"]`** — one translation unit, because the
  bundle carries alternatives: two host layers are `duplicate #define O_CREAT`,
  two system layers the same, `tools/bundle.list` is not source at all, and
  `src/core.mc` alone needs a host layer chosen first. The unit named is the
  entry point for the architecture the registry's worker runs
  (`linux/x86_64`); a unit that cannot be compiled there fails there.
* **The install road.** `mc install [VERSION]` fetches exactly this package —
  the tag archive, `strip = 1`, `files` hashed like any other package — into
  `<libs>/mc/v<VERSION>/` and copies `tools/bundle.list` to the root of the
  tree afterwards; `mc install --from-tree DIR` does the same from a checkout,
  which is what a development build (`0.0.0-dev`, a version no registry
  publishes) must use. See [cli.md](cli.md) § 3e.
* **`files`** is `cut -f2 tools/bundle.list | LC_ALL=C sort -u` (byte order: a UTF-8
  locale collates `_` before `.` on macOS, and the manifest order is what the
  tree hash is over) plus **four** files that list
  cannot name — `src/bundle_data.mc` (the blob has no row in a bundle of
  itself), `tools/bundle.list` (the `NAME<TAB>PATH` map an installed tree
  reads), and the two the `check` entry needs: `src/mc_linux_x86_64.mc` itself
  and the `src/user.mc` it includes, neither of which is a name the bundle
  serves (a compiler is BUILT from them). A `check` entry that is not in `files`
  is refused by the validator, since the tree hash covers `files` and nothing
  else. `scripts/check-pkg.sh` fails when the array drifts from the manifest,
  and asserts that every `check` unit is on disk and declared.
* There is **no `[project]`**: `make` builds this repository, not `mc build`, and
  the five real project configs are `src/mc.<target>.toml`. `mc build .` at the
  root is `mc.toml: missing key: project.entry`, on purpose.

### `mc upgrade` — the binary, not the source

`mc install` puts this package's SOURCE where `#include <name>` reads it.
`mc upgrade` replaces the BINARY, and the two roads meet in the index file: the
version is resolved out of the same `mc` rows (newest non-yanked,
non-pre-release, unless one is named), and the tree that matches the new binary
is installed afterwards by spawning it (`mc install --yes`), so a full binary
and a slim one both end up consistent with themselves.

The index row carries the **tag archive** — a registry of sources has nothing
else to carry — so the address of the compiled binaries is derived from it, for
the one forge whose layout is written down:

```
https://github.com/<owner>/<repo>/archive/refs/tags/v0.16.0.tar.gz
  ->  https://github.com/<owner>/<repo>/releases/download/v0.16.0/mc-0.16.0-<target>.tar.gz
                                                             ... .tar.gz.sha256
```

Any other url is `no binaries known for <url>` rather than a guess. A row whose
url is a **local path** puts the assets in the same directory, which is the
air-gapped upgrade: unpack a release into a directory, write an index file
beside it, `mc upgrade --registry DIR --yes`. `<target>` is this host's os and
arch in the release vocabulary and the flavour is this binary's own; neither is
a flag. See [cli.md](cli.md) § 3f.

**What the checksum proves, and what it does not.** The archive is verified
against the `.sha256` published beside it, before it is unpacked, and the
compiler that comes out is run once and must report the version that was asked
for. That is integrity, and it is the release naming what it packaged. It is
**not** provenance: the checksum is served from the same origin as the archive,
so anyone who can serve one to your machine can serve the other. The priced
follow-up is a signing key over the checksums, with the public key baked into
the binary beside the version; until it ships, `mc upgrade` trusts the release
host. A package's tree hash is a different matter — it is pinned in `mc.lock`
by the developer who reviewed the tree (§ 4).

### What it cannot do yet

**`mc` is reserved on every road a consumer would take.** `[deps] mc = "…"`,
`[replace] mc = "…"`, `mc pkg add mc` and `mc pkg check` of an index file whose
`[package].name` is `mc` are all `reserved package name` (§ 6, § 8). The
published package is for the installed-tree road — `mc install`, § 2 step 3 —
and not for `[deps]`. `mc install` reads the same index file every other package
has, and the reserved set does not apply to it: it installs the compiler's own
package **for the binary itself**, at the binary's own version, into a directory
no project resolves through. `scripts/check-pkg.sh` asserts both halves in one
run — § 11 still refuses all three consumer roads, § 32 installs from the same
kind of row.

**A package's namespace is not the bundle's.** `<mc/core>` out of the blob is
`src/core.mc`; through a locked package it would be `<pkgdir>/core.mc`, because
`libs_open` joins the name's tail to the package directory and only the
installed road (`dp_mc_load`) has the `NAME → PATH` map. A consumer of the tree
names files by their real paths — `<mc/src/core.mc>` — and `<mc/host>`, which is
synthesized, has no meaning there at all.

Both are recorded, with what each would cost to change, in
[../specs/M47-S5.md](../specs/M47-S5.md) § 3.

## See also

* [guide/25-packages.md](../guide/25-packages.md) — using a package, by example
* [guide/27-publishing.md](../guide/27-publishing.md) — publishing one: registering, the CI action, `yank`
* [toml.md](toml.md) — `[deps]`, `[replace]`, `[registry]`, `[package]`
* [bundle.md](bundle.md) — what the binary ships, and why a bundled name can be overridden
* [cli.md](cli.md) — `--libs-dir`
* [diagnostics.md](diagnostics.md) — every message above, with cause and fix
* [../specs/M47-S5.md](../specs/M47-S5.md) — this repository as a package, and what the registry's validator has to be told
