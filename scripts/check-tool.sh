#!/bin/sh
# check-tool.sh [MC] — the acceptance of M48 C3, `mc tool` (docs/reference/tools.md).
#
# NOTHING HERE TOUCHES THE NETWORK. As in scripts/check-pkg.sh the fixture
# registry is a DIRECTORY this script builds from tests/tool/ with the real tar,
# and a curl/wget shim that exits 97 sits on PATH so a fetch that reached the
# network fails the run instead of succeeding silently.
#
# `mc tool run` behaves differently by host and that is the milestone (the M48
# amendment, no --unconfined): on a host with a sandbox it boxes the tool under
# the permissions it declared, and on a host without one it runs the binary
# directly. So the direct cases run everywhere and the boxed cases self-skip
# with a printed reason where there is no sandbox (macOS, Windows). The Linux
# boxed proof -- a tool refused a file outside its granted root -- runs under
# `make check-linux-host` and the CI sandbox cells.
#
# The install roots are overridden with --libs-dir and --bin-dir and HOME is
# emptied for the run, so the whole thing is proved to touch no ~/.mc (CI has no
# HOME).
mc="${1:-build/mc1}"
if [ ! -x "$mc" ]; then
    echo "FAIL: compiler '$mc' not found or not executable"
    exit 1
fi
here=$(pwd)
mc=$(cd "$(dirname "$mc")" && pwd)/$(basename "$mc")
uos=$("$mc" --host 2>/dev/null | awk '/^os / { print $2 }')
[ -n "$uos" ] || uos=$(uname -s)

tmp="${TMPDIR:-/tmp}/check-tool.$$"
rm -rf "$tmp"
mkdir -p "$tmp/bin" "$tmp/reg/index" "$tmp/stage" "$tmp/l" "$tmp/b" "$tmp/ws"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

# Does a boxed `mc tool run` work on THIS host? On macOS/Windows there is no
# sandbox and the tool runs directly, so the boxed cases below self-skip. On
# Linux the box needs user namespaces; an unprivileged container without them
# (check-linux-host's plain `docker run`, no --privileged) cannot unshare, and
# mc rightly refuses to run a Linux tool unconfined. `mc sandbox check` is the
# same guard test-sandbox.sh uses -- it exits 0 only where the box can be
# built. The real boxed proof runs on a sandbox host: Lima mc-k7, docker
# --privileged, or the CI sandbox cells.
boxed=0
nosandbox=""
if [ "$uos" = linux ]; then
    if "$mc" sandbox check > "$tmp/sbchk" 2>&1; then
        boxed=1
    else
        nosandbox=$(head -1 "$tmp/sbchk")
    fi
fi

fails=0
total=0
ok()   { total=$((total + 1)); echo "ok $1"; }
fail() { total=$((total + 1)); echo "FAIL $1: $2"; fails=$((fails + 1)); }
skip() { echo "ok $1 (SKIPPED: $2)"; total=$((total + 1)); }

realpath_env="$PATH"
for t in curl wget; do
    cat > "$tmp/bin/$t" <<EOF
#!/bin/sh
echo "check-tool: $t was invoked -- mc tool must never download here" >&2
exit 97
EOF
    chmod +x "$tmp/bin/$t"
done
PATH="$tmp/bin:$realpath_env"
export PATH
# mc, run with the real tar (a package fetch unpacks an archive) and the
# refusing downloaders, and with NO usable HOME (the roots are explicit).
run() { PATH="$realpath_env" HOME="$tmp/nohome" "$mc" "$@" > "$tmp/o" 2>&1; rc=$?; }

# ---- the fixture registry: hello_tool, a kind=exe tool ----
H=$(PATH="$realpath_env" sh scripts/pkg-hash.sh tests/tool/hello)
cp -R tests/tool/hello "$tmp/stage/hello_tool-0.1.0"
( cd "$tmp/stage" && PATH="$realpath_env" tar -czf "$tmp/reg/hello_tool-0.1.0.tar.gz" hello_tool-0.1.0 )
cat > "$tmp/reg/index/hello_tool.toml" <<EOF
# written by scripts/check-tool.sh
[package]
name = "hello_tool"
repo = "https://example.invalid/hello_tool"
[[versions]]
version     = "0.1.0"
url         = "$tmp/reg/hello_tool-0.1.0.tar.gz"
strip       = 1
sha256      = "$H"
deps        = []
kind        = "tool"
bin         = "hello"
permissions = ["fs.read workspace"]
licence     = "MIT"
EOF
reg="$tmp/reg"
ti() { run tool install "$@" --registry "$reg" --libs-dir "$tmp/l" --bin-dir "$tmp/b"; }

# =========================== 1. box-args, the mapping ========================
# Acceptance 6: fs.read workspace -> `--ro <cwd> --at-path`, net -> `--allow=net`.
cwd=$(cd tests/pkg/src/tool-0.1.0 && pwd)
( cd tests/pkg/src/tool-0.1.0 && PATH="$realpath_env" "$mc" tool box-args mc.toml ) > "$tmp/ba" 2>&1
if [ "$(sed -n 1p "$tmp/ba")" = "--ro $cwd --at-path" ] && [ "$(sed -n 2p "$tmp/ba")" = "--allow=net" ]; then
    ok "box-args tool-0.1.0: '--ro <cwd> --at-path' then '--allow=net'"
else
    fail "box-args tool-0.1.0" "$(cat "$tmp/ba")"
fi

# every kind maps to its primitive (tests/tool/allperms)
awd=$(cd tests/tool/allperms && pwd)
( cd tests/tool/allperms && PATH="$realpath_env" "$mc" tool box-args mc.toml ) > "$tmp/ba2" 2>&1
check_line() { grep -qxF -- "$1" "$tmp/ba2" && ok "box-args maps: $2" || fail "box-args $2" "no '$1' in: $(cat "$tmp/ba2")"; }
check_line "--env HOME"                             "env NAME -> --env NAME"
check_line "--bin sh"                               "exec NAME -> --bin NAME"
check_line "--ro $awd --at-path"                    "fs.read workspace -> --ro <ws> --at-path"
check_line "--rw $awd/out --at-path"                "fs.write workspace/<rel> -> --rw"
check_line "--tmp"                                  "fs.* tmp -> --tmp"
check_line "--allow=net"                            "net -> --allow=net"
grep -q '\.cache/allperms --at-path' "$tmp/ba2" && ok "box-args maps: fs.read home/<rel> -> --ro <home>/<rel>" \
    || fail "box-args home" "$(cat "$tmp/ba2")"

# =========================== 2. install ======================================
# a dry run: the plan, the permission table with the fixed sentence, and
# nothing staged (acceptance 5).
ti hello_tool
if [ "$rc" = 0 ] \
   && grep -q "^fetch  hello_tool 0.1.0" "$tmp/o" \
   && grep -q "fs.read workspace     may read files under the directory it is run from" "$tmp/o" \
   && grep -q "^nothing was installed: re-run with --yes" "$tmp/o" \
   && [ ! -d "$tmp/tools/hello_tool" ]; then
    ok "install (dry): plan + permission table, nothing staged"
else
    fail "install dry run" "exit $rc: $(cat "$tmp/o")"
fi
if [ "$uos" = macos ] || [ "$uos" = windows ]; then
    grep -q "^note: this host has no sandbox" "$tmp/o" \
        && ok "install (dry): the no-sandbox note is printed on $uos" \
        || fail "no-sandbox note" "$(cat "$tmp/o")"
else
    grep -q "^note: this host has no sandbox" "$tmp/o" \
        && fail "no-sandbox note on $uos" "it must not appear where there is a box" \
        || ok "install (dry): no no-sandbox note on $uos (there is a box)"
fi

# the real install: the staged tree, the manifest last, the launcher, the index
ti hello_tool --yes
if [ "$rc" = 0 ] \
   && [ -f "$tmp/tools/hello_tool/v0.1.0/mc.toml" ] \
   && [ -d "$tmp/tools/hello_tool/v0.1.0/build" ] \
   && [ -f "$tmp/tools/hello_tool/v0.1.0/mc.lock" ] \
   && [ -f "$tmp/tools/hello_tool/v0.1.0.toml" ] \
   && [ -x "$tmp/b/hello" ]; then
    ok "install --yes: staged {mc.toml,build/,mc.lock}, v0.1.0.toml, launcher"
else
    fail "install --yes" "exit $rc: $(cat "$tmp/o"); $(ls -R "$tmp/tools" 2>&1 | head)"
fi
# the manifest is the claim, written last, with sandbox recorded as a fact
if grep -q '^kind        = "tool"$' "$tmp/tools/hello_tool/v0.1.0.toml" \
   && grep -q '^permissions = \["fs.read workspace"\]$' "$tmp/tools/hello_tool/v0.1.0.toml" \
   && grep -q "^sandbox     = " "$tmp/tools/hello_tool/v0.1.0.toml"; then
    ok "install manifest: kind/permissions/sandbox recorded ($(grep '^sandbox' "$tmp/tools/hello_tool/v0.1.0.toml"))"
else
    fail "install manifest" "$(cat "$tmp/tools/hello_tool/v0.1.0.toml")"
fi
# the launcher is a short script, not a binary, naming `tool run`
if [ "$(wc -l < "$tmp/b/hello" | tr -d ' ')" -le 2 ] && grep -q "tool run hello_tool" "$tmp/b/hello"; then
    ok "launcher: a $(wc -l < "$tmp/b/hello" | tr -d ' ')-line script that calls tool run"
else
    fail "launcher" "$(cat "$tmp/b/hello")"
fi
# no ~/.mc was touched
if [ ! -e "$tmp/nohome/.mc" ]; then
    ok "install honoured --bin-dir/--libs-dir: HOME/.mc untouched"
else
    fail "install touched HOME" "$(ls -R "$tmp/nohome" 2>&1)"
fi

# =========================== 3. list ==========================================
run tool list --libs-dir "$tmp/l" --bin-dir "$tmp/b"
if [ "$rc" = 0 ] && diff -u tests/golden/tool-list.txt "$tmp/o" > "$tmp/d" 2>&1; then
    ok "list matches the golden"
else
    fail "list" "$(cat "$tmp/d" 2>&1 | head; cat "$tmp/o")"
fi

# =========================== 4. run ===========================================
printf 'hello\n' > "$tmp/ws/data.txt"
printf 'secret\n' > "$tmp/secret.txt"
# via the launcher, from the workspace directory. On macOS/Windows the tool
# runs directly; on a Linux sandbox host it runs boxed and the workspace file
# is inside the granted root, so either way it prints and exits 0. A Linux host
# with no usable box refuses (there is nothing to run unconfined), so skip.
if [ "$uos" != linux ] || [ "$boxed" = 1 ]; then
    # stdout and stderr apart: the program's stdout is exactly the file, and a
    # boxed run also prints `sandbox: exit 0` on stderr -- the supervisor's
    # report, not the tool's output (unboxed on macOS, stderr is empty).
    ( cd "$tmp/ws" && HOME="$tmp/nohome" "$tmp/b/hello" "$tmp/ws/data.txt" ) > "$tmp/o" 2> "$tmp/e"
    rc=$?
    if [ "$rc" = 0 ] && [ "$(cat "$tmp/o")" = "hello" ]; then
        ok "run via the launcher: prints the file under the workspace, exit 0"
    else
        fail "run via launcher" "exit $rc: out=[$(cat "$tmp/o")] err=[$(cat "$tmp/e")]"
    fi
else
    skip "run via the launcher" "no usable sandbox on this linux host: $nosandbox"
fi

# the boxed proof: a file OUTSIDE the granted workspace root is refused. Only a
# host with a WORKING sandbox can show it -- the file is simply read on
# macOS/Windows, and a Linux host without user namespaces cannot box at all
# (check-linux-host's plain docker), so both self-skip.
if [ "$boxed" = 1 ]; then
    ( cd "$tmp/ws" && HOME="$tmp/nohome" "$tmp/b/hello" "$tmp/secret.txt" ) > "$tmp/o" 2>&1
    rc=$?
    if [ "$rc" = 125 ] && grep -q "^sandbox: refused: open" "$tmp/o"; then
        ok "run boxed: a file outside the workspace is refused ($(grep -m1 refused "$tmp/o"))"
    else
        fail "run boxed refusal" "exit $rc: $(cat "$tmp/o")"
    fi
    # box-args feeds `mc sandbox exec` directly, proving the two roads agree
    flags=$( cd "$tmp/ws" && PATH="$realpath_env" "$mc" tool box-args "$here/tests/tool/hello/mc.toml" )
    binp="$tmp/tools/hello_tool/v0.1.0/build/hello"
    ( cd "$tmp/ws" && PATH="$realpath_env" HOME="$tmp/nohome" "$mc" sandbox exec $flags "$binp" "$tmp/ws/data.txt" ) > "$tmp/o" 2> "$tmp/e"
    rc=$?
    if [ "$rc" = 0 ] && [ "$(cat "$tmp/o")" = "hello" ]; then
        ok "box-args flags fed to mc sandbox exec behave as mc tool run does"
    else
        fail "box-args agreement" "exit $rc: out=[$(cat "$tmp/o")] err=[$(cat "$tmp/e")]"
    fi
elif [ "$uos" = linux ]; then
    skip "run boxed refusal" "no usable sandbox on this linux host: $nosandbox"
    skip "box-args feeds mc sandbox exec" "no usable sandbox on this linux host"
else
    skip "run boxed refusal" "no sandbox on $uos; the file is read directly"
    skip "box-args feeds mc sandbox exec" "no sandbox on $uos"
fi

# =========================== 5. remove ========================================
run tool remove hello_tool --libs-dir "$tmp/l" --bin-dir "$tmp/b"
if [ "$rc" = 0 ] && [ ! -e "$tmp/b/hello" ] && [ ! -f "$tmp/tools/hello_tool/v0.1.0.toml" ]; then
    ok "remove: launcher and manifest gone"
else
    fail "remove" "exit $rc: $(cat "$tmp/o"); $(ls "$tmp/b" 2>&1)"
fi
run tool run hello_tool --libs-dir "$tmp/l" --bin-dir "$tmp/b"
if [ "$rc" != 0 ] && grep -q "is not installed" "$tmp/o"; then
    ok "run after remove: 'is not installed'"
else
    fail "run after remove" "exit $rc: $(cat "$tmp/o")"
fi

# =========================== 6. security (M48 C3 review) =====================
# A tool package's mc.toml is attacker-controlled (fetched from a registry).
# Each case here reproduces one escalation and asserts it is closed.

# --- finding 1: [project].out injection is escaped, not spliced ---
# inject_tool's `out` embeds `"`+newline+`[tool]`+a write permission. Before
# toml_esc the install manifest carried a SECOND [tool]/permissions and the
# spliced write was granted; now the whole thing is one escaped string.
IH=$(PATH="$realpath_env" sh scripts/pkg-hash.sh tests/tool/inject)
cp -R tests/tool/inject "$tmp/stage/inject_tool-0.1.0"
( cd "$tmp/stage" && PATH="$realpath_env" tar -czf "$tmp/reg/inject_tool-0.1.0.tar.gz" inject_tool-0.1.0 )
cat > "$tmp/reg/index/inject_tool.toml" <<EOF
[package]
name = "inject_tool"
[[versions]]
version     = "0.1.0"
url         = "$tmp/reg/inject_tool-0.1.0.tar.gz"
strip       = 1
sha256      = "$IH"
deps        = []
kind        = "tool"
bin         = "inject"
permissions = ["fs.read workspace"]
licence     = "MIT"
EOF
run tool install inject_tool --yes --registry "$reg" --libs-dir "$tmp/l" --bin-dir "$tmp/b"
man="$tmp/tools/inject_tool/v0.1.0.toml"
ntool=$(grep -c '^\[tool\]' "$man" 2>/dev/null)
permline=$(grep '^permissions' "$man" 2>/dev/null)
if [ "$rc" = 0 ] && [ "$ntool" = 1 ] \
   && [ "$permline" = 'permissions = ["fs.read workspace"]' ]; then
    ok "finding 1: [project].out injection escaped -- one [tool] table, only the declared permission"
else
    fail "finding 1 injection" "exit $rc; [tool]x$ntool; perms=[$permline]; $(cat "$man" 2>&1)"
fi
# and box-args maps only the declared fs.read, never a --rw for the spliced write
( cd "$tmp/ws" && PATH="$realpath_env" "$mc" tool box-args "$tmp/tools/inject_tool/v0.1.0/mc.toml" ) > "$tmp/ba3" 2>&1
if grep -q '^--ro ' "$tmp/ba3" && ! grep -q '^--rw ' "$tmp/ba3"; then
    ok "finding 1: box-args maps only --ro (the declared fs.read), no injected --rw"
else
    fail "finding 1 box-args" "$(cat "$tmp/ba3")"
fi

# --- finding 2: tool run re-validates the stored permissions ---
# hand-corrupt the just-installed manifest with an injected `fs.write home/..`
# (a `..` a valid [[permission]] row could never produce) and run it: refused
# on every host, before any flag is mapped.
sed 's|permissions = \["fs.read workspace"\]|permissions = ["fs.read workspace", "fs.write home/../../tmp/pwned"]|' "$man" > "$man.x" && mv "$man.x" "$man"
run tool run inject_tool --libs-dir "$tmp/l" --bin-dir "$tmp/b"
if [ "$rc" != 0 ] && grep -q "the install manifest carries an invalid permission" "$tmp/o"; then
    ok "finding 2: tool run refuses a manifest with an injected ../ permission ($(grep -o 'invalid permission.*' "$tmp/o" | head -1))"
else
    fail "finding 2 re-validation" "exit $rc: $(cat "$tmp/o")"
fi

# --- finding 3: a version with `..` is refused before it becomes a path ---
cat > "$tmp/reg/index/badver.toml" <<EOF
[package]
name = "badver"
[[versions]]
version     = "../../../../tmp/evilver"
url         = "$tmp/reg/hello_tool-0.1.0.tar.gz"
strip       = 1
sha256      = "$H"
kind        = "tool"
bin         = "badver"
EOF
rm -rf /tmp/evilver
run tool install "badver@../../../../tmp/evilver" --registry "$reg" --libs-dir "$tmp/l" --bin-dir "$tmp/b"
if [ "$rc" != 0 ] && grep -q "not a usable version" "$tmp/o" && [ ! -e /tmp/evilver ]; then
    ok "finding 3: a version with .. is refused before staging ($(grep -o '[^ ]*: not a usable version' "$tmp/o" | head -1))"
else
    fail "finding 3 version" "exit $rc: $(cat "$tmp/o"); staged=$( [ -e /tmp/evilver ] && echo yes || echo no)"
fi

# --- finding 4: a permission set past the box's per-kind ceilings is refused ---
# at install, before the user accepts -- not at every later `mc tool run`.
rows=""
i=0
while [ "$i" -lt 20 ]; do rows="$rows\"fs.read workspace/d$i\", "; i=$((i + 1)); done
cat > "$tmp/reg/index/bigperm.toml" <<EOF
[package]
name = "bigperm"
[[versions]]
version     = "0.1.0"
url         = "$tmp/reg/hello_tool-0.1.0.tar.gz"
strip       = 1
sha256      = "$H"
kind        = "tool"
bin         = "bigperm"
permissions = [$(printf '%s' "$rows" | sed 's/, $//')]
EOF
run tool install bigperm --yes --registry "$reg" --libs-dir "$tmp/l" --bin-dir "$tmp/b"
if [ "$rc" != 0 ] && grep -q "too many fs.read permissions for the box" "$tmp/o" \
   && [ ! -f "$tmp/tools/bigperm/v0.1.0.toml" ]; then
    ok "finding 4: >16 fs.read refused at install ($(grep -o 'too many.*' "$tmp/o" | head -1))"
else
    fail "finding 4 capacity" "exit $rc: $(cat "$tmp/o")"
fi

# --- finding 5: the (none) row -- a zero-permission tool cannot write ---
NH=$(PATH="$realpath_env" sh scripts/pkg-hash.sh tests/tool/noperm)
cp -R tests/tool/noperm "$tmp/stage/noperm_tool-0.1.0"
( cd "$tmp/stage" && PATH="$realpath_env" tar -czf "$tmp/reg/noperm_tool-0.1.0.tar.gz" noperm_tool-0.1.0 )
cat > "$tmp/reg/index/noperm_tool.toml" <<EOF
[package]
name = "noperm_tool"
[[versions]]
version     = "0.1.0"
url         = "$tmp/reg/noperm_tool-0.1.0.tar.gz"
strip       = 1
sha256      = "$NH"
kind        = "tool"
bin         = "noperm"
permissions = []
EOF
run tool install noperm_tool --yes --registry "$reg" --libs-dir "$tmp/l" --bin-dir "$tmp/b"
npm="$tmp/tools/noperm_tool/v0.1.0.toml"
if [ "$rc" = 0 ] && grep -q '^permissions = \[\]$' "$npm"; then
    ok "finding 5: a zero-permission tool installs with permissions = []"
else
    fail "finding 5 install" "exit $rc: $(cat "$tmp/o"); $(cat "$npm" 2>&1)"
fi
# boxed: its install tree is bound read-only and nothing of the user's is bound,
# so it cannot create a host-visible file (docs/reference/tools.md records that
# its ephemeral copy-on-write /src cwd remains writable but never touches the
# host). Only a working sandbox can show it; elsewhere it runs directly.
if [ "$boxed" = 1 ]; then
    rm -f "$tmp/ws/created-by-noperm"
    ( cd "$tmp/ws" && HOME="$tmp/nohome" "$tmp/b/noperm" "$tmp/ws/created-by-noperm" ) > "$tmp/o" 2>&1
    if [ ! -e "$tmp/ws/created-by-noperm" ]; then
        ok "finding 5 boxed: a zero-permission tool cannot create a host-visible file"
    else
        fail "finding 5 boxed write" "the file was created: $(cat "$tmp/o")"
    fi
else
    skip "finding 5 boxed" "no working sandbox here; the tool runs directly (see docs/reference/tools.md)"
fi

echo "check-tool: $((total - fails))/$total"
[ "$fails" -eq 0 ]
