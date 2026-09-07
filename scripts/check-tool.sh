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

echo "check-tool: $((total - fails))/$total"
[ "$fails" -eq 0 ]
