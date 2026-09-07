# `mc tool` — install and run a program package

A **tool** is a package of `kind = "exe"`: a program `mc tool install` builds on your own machine
with the compiler that is running, and `mc tool run` runs — boxed under the permissions the package
declared and you confirmed, on a host that has a sandbox, and directly on one that does not. It is
the package half of the registry aimed at *programs* rather than *libraries* (a library is
`kind = "obj"` or has no `[project]`, is compiled into your own code, and is never installed).

This page is the reference; the everyday view is [../guide/25-packages.md](../guide/25-packages.md)
and the manifest keys are in [packages.md](packages.md) § 3 and [toml.md](toml.md) § `[[permission]]`.

## The commands

```
mc tool install NAME[@VERSION]     resolve, show the plan and the permissions, fetch, build, launch
mc tool install [DIR]              every tool a project's lock names
mc tool list                       what is installed
mc tool remove NAME                unlink the launcher and the manifests
mc tool upgrade [NAME]             the newest of the same major, then install
mc tool run NAME [-- ARGS]         what the launcher calls
mc tool box-args <mc.toml>         (hidden) the derived sandbox flags, one per line
```

The flags — `--yes`, `--registry`, `--libs-dir`, `--bin-dir`, `--workspace` — are in
[cli.md](cli.md) § 3g.

## `install`, step by step

1. **Resolve.** The tool is the root of the same MVS graph `mc pkg` uses; its own `[deps]` are
   libraries. A name that is a library, not a tool, is refused.
2. **The plan is the prompt.** `mc` has no prompt; it prints the archives it would fetch and a
   permission table — one fixed sentence per permission, from the index row, on screen *before* a
   byte is fetched — and stops. `--yes` accepts both.
3. **Fetch** into `<libs>` (`~/.mc/libs`, or `--libs-dir`), exactly as `mc pkg sync` does.
4. **Stage** a buildable copy under `~/.mc/tools/<name>/v<ver>/`: `mc.toml` and the declared files,
   `deps/<lib>/` for every library, and an `mc.lock` — the vendored shape `mc build` rehashes.
5. **Build** it by spawning this compiler (`mc build`), the same trust a `mc build` of any project
   has; the tool it produces is what runs boxed later.
6. **Record and launch.** The install manifest `~/.mc/tools/<name>/v<ver>.toml` is written last
   ([toml.md](toml.md) § `[tool]`), and a one-line launcher goes in `~/.mc/bin/<bin>` (`--bin-dir`).

There is no `--unconfined` (the M48 amendment): the plan, the table and the acceptance are the same
on every host. On a host without a sandbox the plan adds one line —
`note: this host has no sandbox; the permissions above are recorded, not enforced` — and the
manifest records `sandbox = false`. Nothing else differs until `run`.

## The `~/.mc` layout

```
~/.mc/libs/<pack>/v<ver>/          the fetched trees (shared with mc pkg)
~/.mc/tools/<name>/v<ver>/         the staged, built copy: mc.toml, files, deps/, mc.lock, build/<bin>
~/.mc/tools/<name>/v<ver>.toml     the install manifest, written last
~/.mc/tools/installed              one line `<name> <version> <bin>` per install (mc has no readdir)
~/.mc/bin/<bin>                    the launcher (macOS/Linux: a short sh script; Windows: <bin>.cmd)
```

`--bin-dir` and `--libs-dir` override the two roots so CI can run with no `HOME`; the tools root is
the parent of `<libs>` with `tools/` on it, and the default bin directory the same parent with
`bin/`. `remove` unlinks the launcher and the manifests; `mc` has no `rmdir`, so the directories
stay, and `mc tool run` afterwards is `is not installed`.

## The launcher

```sh
#!/bin/sh
exec "/path/to/mc" tool run hello_tool --libs-dir "/path/to/libs" -- "$@"
```

One line. It names the compiler that installed it by absolute path — so a tool keeps working when
`mc` is not on `PATH` — and it embeds `--libs-dir` only to locate the install (the tools root is the
parent of `<libs>`); it carries **no** sandbox flags, so the way permissions map to a box can change
with no launcher regenerated. All the logic is in `mc tool run`.

## `run` — boxed here, direct there

`mc tool run NAME` reads the newest installed version's manifest and:

* on a host with a sandbox (Linux), derives the `mc sandbox exec` flags from the manifest's
  permissions and spawns the box, stdio inherited, exiting with the child's status;
* on a host without one (macOS, Windows), runs the binary directly.

The decision is made at run time, not from the manifest's `sandbox` field — that field is only a
fact `mc tool list` shows.

## The workspace

Several permissions are relative to a **workspace**: the directory the tool is invoked from
(`--workspace DIR`, default the current directory). An editor sets it to the project folder; a shell
to wherever you are. `$HOME` and `/` are refused without an explicit `--workspace`, so a tool run
from your home directory is not silently handed every file you own.

## The one mapping: permissions to sandbox primitives

`mc tool box-args <mc.toml>` prints the flags a permission set derives to, one line per permission —
the single definition, shared by `mc tool run` and by a registry validator (which spawns exactly
this verb). The mapping ([sandbox.md](sandbox.md) § The primitives):

| permission | flags |
|---|---|
| `fs.read <path>` | `--ro <resolved> --at-path` |
| `fs.write <path>` | `--rw <resolved> --at-path` (a `home/<rel>` directory is created first) |
| `fs.read tmp` / `fs.write tmp` | `--tmp` |
| `net` | `--allow=net` |
| `exec NAME` | `--bin NAME` |
| `env NAME` | `--env NAME` |
| (none) | the install tree read-only, an empty netns, the program profile |

`workspace` resolves to the workspace directory, `workspace/<rel>` and `home/<rel>` to a directory
beneath it or beneath `$HOME`; `--at-path` binds each at its own absolute path inside the box, so a
tool handed an absolute path (as an editor hands a language server `file:///…`) can reach it, and a
path outside its granted roots is `sandbox: refused: open <path>`, exit 125.

## Boxed vs direct, and what is verified

On Linux a tool that reads a file outside its `fs.read` root is stopped by the box, and one that
opens a socket without `net` or forks without `exec` is refused — the C2 sandbox around it. On macOS
and Windows there is no box (see [sandbox.md](sandbox.md) § Hosts), so the permissions are recorded
and not enforced; the same install, the same manifest, and a tool you chose to install runs. What
the registry verifies about a tool, and what it cannot verify about a library, is in
[packages.md](packages.md) § Permissions.
