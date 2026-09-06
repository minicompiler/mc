# Publishing a package

[Using a package](25-packages.md) covered the consumer's half: `[deps]`, `mc.lock`,
`#include <pack/file.mc>`. This page covers the other half — turning a source tree with an
`mc.toml` into something a stranger's `[deps]` line can name, through the registry at
<https://minicompiler.dev>.

The registry is a separate service (`minicompiler/mc-registry`) from the compiler you are running.
The compiler's side of a package is a reader and a hash — no network code, no client library —
so everything in this page is either a form on a website, a GitHub Release, or `mc pkg` commands
you already have.

---

## 1. What a package is, once more

A package is a source tree with an `mc.toml` at its root carrying a `[package]` table:

```toml
[package]
name   = "geo"
files  = ["geo.mc", "vec.mc"]
lib    = "geo.mc"                     # what a bare `#include <geo>` means
module = "mc_geo.mc"                  # optional: the file a COMPILER includes
check  = ["geo.mc"]                   # optional: what the registry compiles to validate a tag

[deps]
mathx = "1.0.0"
```

* **`name`** is the package's identity everywhere — in `[deps]`, in `#include <name>`, on the
  registry. See § 2.
* **`files`** is not documentation: it is the input to the tree hash, the boundary a fetched
  package may not read or write outside of, and the list `mc pkg vendor` copies. Forgetting a
  file changes nothing; a file that reaches outside the package is refused, at both the compiler
  and the registry.
* **`lib`** is what a bare `#include <name>` resolves to. Without it, only `<name/file.mc>` forms
  work.
* **`check`** exists because a registry validates a tag by *compiling* the package, and a package
  that carries alternatives — a host layer per system, a machine per architecture — has no single
  translation unit that holds all of it. Each entry is one unit, compiled on its own, and each has
  to be listed in `files` too (the tree hash covers `files` and nothing else, so a unit nobody
  ships is a unit no consumer — and no validator — would receive). With no `check` key the unit is
  `lib`.

Everything here — the manifest, the closure rule, every message — is
[reference/packages.md](../reference/packages.md); this page is the road from a manifest to a
registered, published, and consumable package.

## 2. The name rule, and the names nobody can register

A package name is `[a-z][a-z0-9_]*`, at most 32 bytes — lower case only, so there is one spelling.
Two sets of names cannot be registered by an ordinary account:

* **The compiler's own reserved set**, refused wherever a name is read — `[deps]`, `[replace]`,
  `mc pkg add`, `mc pkg check` of an index file: `mc`, every `mc/...` name, `deps`, `build`.
  `mc` is the compiler's own package (§ 11 below); a taught compiler assembled from a foreign `mc`
  would not be the compiler that built it.
* **The registry's own reserved prefixes**, checked when you register: any name matching `mc*` or
  `minicompiler*` — case-insensitively, and the same after stripping `-`/`_` (so `m-c` and
  `mini_compiler` are caught too) — is reserved for the registry's administrator. A registration
  attempt with such a name is refused at the form with `name reserved for the administrator`. This
  is how `mc` itself (§ 11) and any `mc*`-looking package stay official; a server policy is allowed
  to be stricter than the language's own name rule, never looser.

Beyond the reserved names, a name is a first-come resource: **first registration wins**, by the
exact `(host, owner, repo)` triple of the git URL — `.../geo`, `.../geo.git` and `.../GEO` are one
repository and cannot register twice. If somebody else already holds the name you want, the
remedy is `transfer` (§ 8) — a name never changes; who owns it can.

## 3. Registering, once, on `/me`

1. **Log in** at <https://minicompiler.dev/login> with GitHub. The first successful login creates
   your account and lands you on `/welcome`.
2. **Accept the documents.** `/welcome` shows the Terms of Service, the Privacy Policy and the
   Package Policy in full, one checkbox per document. Nothing that *writes* — registering,
   polling, yanking, an API token — works until you have accepted the current version of each; a
   later revision of a document asks you again, once, the next time you try to write.
3. **`POST /repos`** (the form on `/me`): one field, `git_url` — `https://github.com/<owner>/<repo>`.
   What is checked, in order, and refused with the exact sentence when it fails:

   | check | refusal |
   |---|---|
   | the URL is `https://github.com/<owner>/<repo>` (GitHub only, for now — § 9) | `only public GitHub repositories for now` |
   | the triple is not already registered | `that repository is already registered` |
   | the repository's `mc.toml`, at its default branch, can be read over the raw content endpoint | `the repository has no readable mc.toml at its default branch` (this is also what a *private* repository looks like: nothing else checks visibility separately) |
   | the file parses and has a `[package].name` | `the repository's mc.toml could not be read` / `the repository's mc.toml has no [package].name` |
   | the name is not reserved (§ 2) | `name reserved for the administrator` |
   | the name matches the name rule | `a package name is [a-z][a-z0-9_]*, at most 32 bytes` |
   | the name is not already taken by a different repository | `a package of that name is already registered` |

   Rate limits: 5 registrations per hour per account, 20 per hour per source address, charged in
   that order (an account can't be starved by an address it shares, and an address can't spend an
   account's whole budget after the account's own is gone).

Registering does not publish anything by itself. It queues a `register` job — the same validation
pipeline every later release goes through (§ 5) — and creates the `repos` row in state `pending`
until something of it is actually published.

## 4. What publishes a version: a GitHub Release, not a tag

A version `vX.Y.Z` is publishable only when it has a **GitHub Release**, not merely a tag —
`GET /repos/<owner>/<repo>/releases/tags/vX.Y.Z` has to answer with something that is not a draft.
The archive the registry serves is still the tag's own source archive
(`.../archive/refs/tags/vX.Y.Z.tar.gz`), which the Release guarantees exists.

* A tag with **no** Release yet is simply not taken up — not recorded as a failure, so a
  scheduled or CI poll tries it again on the next pass once the Release appears. Releases are
  routinely created minutes or days after the tag they name (this repository's own `release.yml`
  pushes the tag, builds five binaries, and creates the Release last).
* A **draft** Release is treated the same as no Release: not ready yet, tried again later.
* A **pre-release** (`v1.2.0-rc.1`) publishes with its `-rc.1` suffix and is never chosen by
  `mc pkg add`/`mc update` without naming it explicitly (`mc pkg add name@1.2.0-rc.1`) — the same
  rule [reference/packages.md § 10](../reference/packages.md#versions-and-pre-releases) states for
  consuming one.
* A **published row never changes** except to gain `yanked = true` (§ 6). There is no way to edit
  or re-publish a version once it exists; a mistake is a new tag and a new Release.

## 5. What the validator does, and what the report shows

Every tag with a Release goes through the same box, whether the poll that found it came from you,
from CI, from the schedule, or from an administrator:

1. A shallow clone of that exact tag (submodules refused — a submodule is a second URL nobody
   registered; a checkout over 64 MiB refused; a 120-second clock).
2. **Inside a sandbox with no network and no view of the host** (`mc sandbox run`,
   [reference/sandbox.md](../reference/sandbox.md)): `mc pkg hash` of the checkout compared against
   what the manifest claims, then a compile of each `[package].check` unit (or `lib` alone with no
   `check` key), each in its own box. If the tagged `mc.toml` carries a `[project]`, the package's
   own tests run in a second box afterward.
3. On success: a deterministic archive is built from the checkout, the row is inserted, and
   `index/<name>.toml` is regenerated and written atomically. On any refusal: nothing is
   published, and the report — the sandbox's named `refused:`/`killed:` line, or the compiler's own
   diagnostic — is what you (and CI, § 7) read back; the same commit is not retried automatically
   until you ask for a poll again.

The report is public at `<registry>/jobs/<id>` (plain text, `state: queued|running|done|failed`)
and on your repository's page. It is filtered to printable ASCII, tab and newline before it is
shown anywhere, since it is a stranger's bytes on their way into your terminal or your CI log.

## 6. Publishing automatically: the GitHub Action

Once a repository is registered, wire this into it so every Release publishes itself with no
further action:

```yaml
# .github/workflows/mc-publish.yml
name: Publish to the mc registry
on:
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      tag: {description: "Existing release tag", required: true, type: string}
permissions:
  contents: read
concurrency:
  group: mc-publish-${{ github.repository }}
  cancel-in-progress: false
jobs:
  publish:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: minicompiler/register-action@v1
        with:
          tag: ${{ inputs.tag || github.event.release.tag_name }}
```

No checkout, no secret, no permission beyond the default `contents: read`. The action
(`minicompiler/register-action`, a public, composite, dependency-free shell action — no node, no
Docker, no third-party action) does exactly this:

1. Refuses to run unless `tag` is `v` + a SemVer version and the event is a published, non-draft
   release.
2. Waits ten seconds, so the Release it is about to ask GitHub about is visible to the registry's
   own request.
3. `POST <registry>/poll` with `git_url=https://github.com/<owner>/<repo>` — no secret, since the
   request carries no identity and asks for nothing that identity would gate; it can only queue a
   validation of an **already registered** repository. A `429` is retried honouring `Retry-After`.
   An unregistered repository answers `404 not registered`, and the action fails with
   `register this repository once on <registry>/me, then re-run`.
4. Polls `GET <registry>/jobs/<id>` until the job is `done` or `failed`.
5. Prints the report inside `::group::registry report` — so a refusal like
   `sandbox: refused: open /etc/shadow` is right there in your Actions log.
6. Fails the workflow on `failed`.
7. On `done`, reads `<index>/index/<name>.toml` and requires
   `version = "<tag without its v>"` to be there — the one assertion that proves what a consumer
   of your package will actually see, not just that the job claimed success.

**Inputs**: `registry` (default `https://minicompiler.dev`), `index` (default
`https://pkg.minicompiler.dev`), `repository` (default `${{ github.repository }}`), `tag`, `wait`
(default `true`), `timeout` (default `900`), and `token` — accepted today, sent nowhere: it is
reserved for a later account-scoped API token that will let CI perform a *first* registration
too. Until then, registering (§ 3) is always a person, once, on `/me`.

`@v1` is a moving tag, the same convention GitHub's own actions use; pin a commit SHA instead if
you want the exact bytes you reviewed to never move under you.

A CI-triggered poll costs the registry at most one bounded job per repository (three an hour per
repository, sixty an hour per source address, three hundred an hour in all) and can neither
register a package nor name one — the reserved prefixes and "first registration wins" are
untouched by this road.

## 7. `yank`, and what it does not do

```console
$ curl -X POST https://minicompiler.dev/repos/<id>/versions/<version>/yank ...
```

(a form on your repository's page, session-authenticated, CSRF-protected). Yanking marks a
version `yanked = true` in the index: `mc pkg add` and `mc update` stop choosing it, but it stays
**in** the index and its archive stays served — a lock that already pins it keeps working. This is
Go's `retract`, not a deletion.

**There is no unyank.** A leaked or over-broadly-scoped credential can yank every version an
account owns and that cannot be undone by the same road — the mitigation (an API token scoped
without `yank`) is part of the account-token feature not yet shipped (§ 6's `token` input).
`delist` — stronger, removing a version from the index and the page entirely — is reserved for a
legal order and is an administrator action, never self-service.

## 8. Reporting a problem, and the policies

Every package page has a report form (logged in, rate-limited): abuse, malware, a licence
dispute, a name takeover claim, a privacy concern, or something else — it goes into a moderation
queue an administrator resolves. For a security vulnerability in `mc` itself or in the registry,
see `/.well-known/security.txt` and the Security Policy linked from every page's footer.

The Terms of Service, Privacy Policy, Package Policy, Security Policy and Legal Notice are linked
from the footer of every page and from `/login`. They describe: who may register (public GitHub
repositories, the name rules, the reserved prefixes), what publishing means (immutability, yank,
that the registry hosts *metadata* and your code stays on GitHub under your own licence),
what is collected and why (your GitHub id, login, name, avatar URL; session data; addresses in
audit rows), and your rights — `/me` lets you export or erase your account data at any time. An
erasure keeps your published versions published (a lock somewhere depends on them) and keeps the
moderation record of reports made *about* your packages, but scrubs the text of reports **you**
filed and every personally identifying field.

## 9. What is not built yet

* **GitHub only.** The host allowlist admits `github.com` alone; other forges (GitLab, Bitbucket)
  are a stated intention for after `mc`'s 1.0.0, one more allowlist entry and one more
  "does this tag have a release" question each.
* **No account-scoped API tokens yet** — that is what turns on the action's `token` input and
  what would let CI perform a first registration and a scoped yank.

## 10. Consuming what you (or anyone) published

This is [Using a package](25-packages.md)'s subject, in full — `[deps]`, `mc pkg sync`,
`mc.lock`, the tree hash, vendoring — and does not change once your package is registered:

```toml
[deps]
geo = "1.2.0"
```

```console
$ mc pkg add geo --yes
$ mc build myproject
```

One thing worth knowing while it is true: `mc pkg`'s **compiled-in** default registry is
`https://minicompiler.dev/registry` (`pkg_default_registry()` in `src/pkg.mc`), a path this
registry's server does not actually serve — the live layout is `https://pkg.minicompiler.dev`, with
`/index/<name>.toml` at the root of that host, no `/registry` path segment. Until the compiler's
default is updated to match, name the registry explicitly:

```console
$ mc pkg sync --registry https://pkg.minicompiler.dev --yes
```

or, once, in `mc.toml`:

```toml
[registry]
url = "https://pkg.minicompiler.dev"
```

`mc pkg check` — what the registry itself runs to validate an index row — and every other `mc pkg`
subcommand take `--registry`/`[registry].url` the same way.

## 11. The owner's own repository does this

`minicompiler/mc` — this repository — is a package too, and it is what the release workflow
publishes on every tag. Its root [`mc.toml`](../../mc.toml) carries:

```toml
[package]
name  = "mc"
lib   = "src/core.mc"
check = ["src/mc_linux_x86_64.mc"]
files = [ "lib/backend_arm64.mc", … , "tools/bundle.list" ]
```

and [`.github/workflows/release.yml`](../../.github/workflows/release.yml) has a job right after
the one that creates the GitHub Release:

```yaml
publish-to-registry:
  name: Publish to the mc registry
  needs: publish
  runs-on: ubuntu-latest
  timeout-minutes: 20
  permissions:
    contents: read
  steps:
    - uses: minicompiler/register-action@v1
      with:
        tag: ${{ github.ref_name }}
```

`name = "mc"` is the one reserved name the registry admits, and only from this repository — the
administrator registered it once, by hand, the way § 2 says an ordinary name cannot be. Everything
after that first registration is the same road as anyone else's: a tag, a Release, the action, the
box, the index.

## See also

* [reference/packages.md](../reference/packages.md) — the manifest, the lock, the resolution
  order, every refusal
* [reference/toml.md](../reference/toml.md) — `[deps]`, `[replace]`, `[registry]`, `[package]`
* [reference/sandbox.md](../reference/sandbox.md) — the box the validator runs every package in
* [Using a package](25-packages.md) — the consumer's side, by example
