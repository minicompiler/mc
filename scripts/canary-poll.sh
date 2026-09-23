#!/bin/sh
# canary-poll.sh -- wait for the consumer's verdict on an mc release, then promote it.
#
#   canary-poll.sh TAG          # poll until a verdict or the timeout, then act
#   canary-poll.sh --once TAG   # one lookup, no sleeping (see exit codes below)
#   canary-poll.sh --url TAG    # print the raw URL this script would poll
#   canary-poll.sh --test       # run the assertions
#
# The canary (docs/specs/M53.md § 6, docs/ci.md § The canary) crosses the
# repository boundary with NO CREDENTIAL in either direction. `release.yml`'s
# `publish` job creates the GitHub Release as a PRE-RELEASE; the consumer
# notices it by polling mc's public releases API, runs its whole recipe against
# the tarball, and writes a verdict into a branch of its OWN repository with its
# OWN token. This script is the mc half: it reads that file with no token owed
# to the consumer's repository and flips the pre-release flag. (It may use
# mc's OWN GITHUB_TOKEN to raise its own rate limit against GitHub's public API
# -- that never reaches the consumer and is not the credential the boundary is
# about.)
#
# The verdict is one JSON object at the ROOT of a branch named `canary` -- the
# branch occupies the ref position of the raw URL, so the file is NOT inside a
# `canary/` directory (that would read `.../teko-lang/canary/canary/0.17.0.json`):
#
#   https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<version>.json
#   {"version":"0.17.0","status":"ok","run":"<actions url>","utc":"..."}
#
# A missing file is neither `ok` nor `fail`: the verdict has not been written
# yet and the poll continues until the timeout.
#
# Two roads read the same file, and the ORDER matters. raw.githubusercontent.com
# sits behind a CDN that can serve a STALE body for minutes after the file
# changes (measured on 1.1.0: the API served the fresh `ok` while raw kept
# answering the previous version's cached `fail`). The contents API
# (api.github.com/repos/.../contents/NAME?ref=BRANCH) is never CDN-cached, so
# it is tried FIRST; raw is the fallback, for a host with no `gh` and no
# network path to the API. An `ok` read from raw is trusted as is -- the
# consumer never downgrades a verdict, so a stale `ok` cannot exist -- but a
# `fail` read from raw ALONE is re-checked against the API before it is acted
# on, because blocking a good release on a stale cached failure is the
# expensive mistake and missing one more poll cycle is not.
#
# Environment:
#   CANARY_REPO      owner/repo publishing the verdict   (teko-org/teko-lang)
#   CANARY_BRANCH    the branch it writes to             (canary)
#   CANARY_URL       the whole raw URL, overriding it     (derived)
#   CANARY_API_CMD   a shell command whose stdout replaces the contents-API
#                    fetch entirely (test hook; not read on the real road)
#   CANARY_TIMEOUT   seconds to wait for a verdict       (900 = 15 minutes --
#                    this is the FAST path, catching the common case where the
#                    consumer's own poller is already awake; a release whose
#                    verdict lands later is picked up by the scheduled
#                    `.github/workflows/promote-pending.yml`, which asks once
#                    every 30 minutes forever, with no upper bound of its own)
#   CANARY_INTERVAL  seconds between polls               (60)
#   CANARY_REQUIRED  informational only here (it still governs the promote
#                    job's `continue-on-error` in release.yml, so a `fail`
#                    VERDICT shows as a red run at 1.0.0 and a green one with a
#                    failed step before it): a TIMEOUT never fails this script,
#                    required or not -- the release is correctly left a
#                    pre-release and the scheduled promoter will finish the job
#                    when a verdict lands. A `fail` VERDICT is always a
#                    failure, required or not.
#   DRY_RUN          non-empty -> print what would happen, touch no release
#   GH_TOKEN         used by `gh release edit`, and by the contents-API read
#                    to raise its own rate limit (unless DRY_RUN is set for the
#                    former; the latter always may use it when present)
#   GITHUB_OUTPUT    when set (inside a GitHub Actions step), the polling form
#                    writes `promoted=true|false` to it -- `true` only once the
#                    flag was actually cleared, never on a timeout -- so a
#                    caller can gate on the OUTCOME instead of the job's own
#                    result (a timeout must not look like success to something
#                    that must never run before an ACTUAL promotion, such as
#                    `publish-to-registry`)
#
# `--once TAG`: one lookup, no sleeping.
#   exit 0  verdict is `ok` for this version   (prints `ok`)
#   exit 1  verdict is `fail` for this version, confirmed if it came from raw
#           (prints `fail`)
#   exit 2  no verdict yet -- missing, unparsable, names another version, or
#           an unconfirmed `fail` read from raw alone   (prints `no verdict`)
#
# The polling form's exit codes:
# Exit 0: verdict `ok` (promoted), or no verdict within the timeout (deferred
#         to the scheduled promoter -- see CANARY_TIMEOUT above -- NOT
#         promoted; check `promoted` in GITHUB_OUTPUT, not this exit code, to
#         tell the two apart).
# Exit 1: verdict `fail`. Every asset stays attached and
#         `gh release edit "$TAG" --prerelease=false --latest` promotes it by
#         hand once the consumer corrects it; a rerun of the job alone is the
#         retry, and so is the next run of the scheduled promoter.
set -eu

# ---------------------------------------------------------------------------
# Fetch the verdict file's raw text, one road at a time. Both return empty
# (never a non-zero exit under `set -e`, since the caller decides what "no
# answer" means) when nothing could be read.

fetch_api_body() {
    # Test hook: a whole command standing in for the network call.
    if [ -n "${CANARY_API_CMD:-}" ]; then
        eval "$CANARY_API_CMD" 2>/dev/null || :
        return 0
    fi
    if command -v gh >/dev/null 2>&1; then
        # `gh api` writes its JSON error body (e.g. a 404) to STDOUT even on
        # failure, so a missing file must not be mistaken for a verdict: only
        # print what it captured when the call itself succeeded.
        out=$(gh api -H "Accept: application/vnd.github.raw+json" \
              "repos/$repo/contents/$version.json?ref=$branch" 2>/dev/null) && printf '%s' "$out"
        return 0
    fi
    tok=${GITHUB_TOKEN:-${GH_TOKEN:-}}
    api="https://api.github.com/repos/$repo/contents/$version.json?ref=$branch"
    if [ -n "$tok" ]; then
        curl -fsSL --max-time 30 -H "Accept: application/vnd.github.raw+json" \
            -H "Authorization: Bearer $tok" "$api" 2>/dev/null || :
    else
        curl -fsSL --max-time 30 -H "Accept: application/vnd.github.raw+json" "$api" 2>/dev/null || :
    fi
}

fetch_raw_body() {
    curl -fsSL --max-time 30 "$url?t=$(date +%s)" 2>/dev/null || :
}

# read_verdict: one attempt at both roads, applying the confirm-fail rule.
# Returns 0 (ok), 1 (fail, acted on), 2 (nothing usable yet) via $?, and
# prints one status line either way.
read_verdict() {
    source=api
    body=$(fetch_api_body)
    if [ -z "$body" ]; then
        source=raw
        body=$(fetch_raw_body)
    fi
    if [ -z "$body" ]; then
        echo "canary: no verdict yet (api and raw both empty)"
        return 2
    fi

    status=$(printf '%s' "$body" | jq -r '.status // empty' 2>/dev/null) || status=
    got=$(printf '%s' "$body" | jq -r '.version // empty' 2>/dev/null) || got=
    got=${got#v}
    if [ -n "$got" ] && [ "$got" != "$version" ]; then
        echo "canary: the file names $got, waiting for $version"
        return 2
    fi

    if [ "$status" = "fail" ] && [ "$source" = "raw" ]; then
        confirm=$(fetch_api_body)
        if [ -z "$confirm" ]; then
            echo "canary: raw reports fail for $version but the contents API did not answer; treating as no verdict yet"
            return 2
        fi
        cgot=$(printf '%s' "$confirm" | jq -r '.version // empty' 2>/dev/null) || cgot=
        cgot=${cgot#v}
        if [ -n "$cgot" ] && [ "$cgot" != "$version" ]; then
            echo "canary: the file names $cgot, waiting for $version"
            return 2
        fi
        status=$(printf '%s' "$confirm" | jq -r '.status // empty' 2>/dev/null) || status=
        body=$confirm
        source="api (confirming a stale raw fail)"
    fi

    case "$status" in
    ok)
        echo "canary: status: ok ($source) -- $(printf '%s' "$body" | jq -r '.run // "no run url"')"
        return 0
        ;;
    fail)
        echo "canary: status: fail ($source) -- $(printf '%s' "$body" | jq -r '.run // "no run url"')"
        return 1
        ;;
    esac
    echo "canary: unrecognized status ($source): ${status:-<empty>}"
    return 2
}

# ---------------------------------------------------------------------------

if [ "${1:-}" = "--test" ]; then
    tmp=$(mktemp -d) || exit 1
    trap 'rm -rf "$tmp"' EXIT
    fail=0
    n=0
    # Each case runs the real poll loop over a `file://` URL for raw, and/or a
    # `CANARY_API_CMD` stub for the contents API. CANARY_TIMEOUT=0 makes the
    # loop poll exactly once and then time out, so a case with no verdict file
    # costs one failed lookup instead of ninety minutes.
    run() { # run NAME WANT_RC WANT_GREP [env...]
        name=$1 want=$2 pat=$3
        n=$((n + 1))
        shift 3
        # CANARY_API_CMD=: is the default (the API road answers nothing, so a
        # case that only sets CANARY_URL exercises raw exactly as before); a
        # case naming its own CANARY_API_CMD overrides it, since `env` applies
        # duplicate assignments in argument order and this one comes first.
        out=$(env CANARY_API_CMD=: DRY_RUN=1 CANARY_TIMEOUT=0 CANARY_INTERVAL=1 "$@" \
              "$0" v0.17.0 2>&1) && rc=0 || rc=$?
        if [ "$rc" != "$want" ]; then
            echo "FAIL $name: exit $rc, want $want"; echo "$out"; fail=$((fail + 1)); return
        fi
        if ! printf '%s\n' "$out" | grep -q "$pat"; then
            echo "FAIL $name: no /$pat/ in output"; echo "$out"; fail=$((fail + 1)); return
        fi
        echo "ok   $name"
    }
    printf '%s\n' '{"version":"0.17.0","status":"ok","run":"u","utc":"t"}'   > "$tmp/ok.json"
    printf '%s\n' '{"version":"0.17.0","status":"fail","run":"u","utc":"t"}' > "$tmp/bad.json"
    printf '%s\n' '{"version":"0.16.0","status":"ok","run":"u","utc":"t"}'   > "$tmp/old.json"
    printf '%s\n' '{"version":"v0.17.0","status":"ok","run":"u","utc":"t"}'  > "$tmp/vpre.json"
    run "ok promotes"           0 'would promote' CANARY_URL="file://$tmp/ok.json"
    run "v-prefix accepted"     0 'would promote' CANARY_URL="file://$tmp/vpre.json"
    run "fail stays pre"        1 'status: fail'  CANARY_URL="file://$tmp/bad.json" \
                                                   CANARY_API_CMD="cat $tmp/bad.json"
    run "another version waits" 0 'no verdict'    CANARY_URL="file://$tmp/old.json"
    run "timeout defers, unrequired" 0 'deferred to the scheduled promoter' \
                                                   CANARY_URL="file://$tmp/none.json"
    run "timeout defers, required"   0 'deferred to the scheduled promoter' \
                                                   CANARY_URL="file://$tmp/none.json" \
                                                   CANARY_REQUIRED=true
    # A timeout must never look like a promotion to a caller that gates on the
    # output rather than the exit code (release.yml's publish-to-registry).
        n=$((n + 1))
    out=$(env CANARY_API_CMD=: CANARY_URL="file://$tmp/none.json" DRY_RUN=1 \
          CANARY_TIMEOUT=0 CANARY_INTERVAL=1 GITHUB_OUTPUT="$tmp/gh_output" \
          "$0" v0.17.0 2>&1) && rc=0 || rc=$?
    if [ "$rc" = 0 ] && grep -q '^promoted=false$' "$tmp/gh_output"; then
        echo "ok   timeout emits promoted=false"
    else
        echo "FAIL timeout emits promoted=false ($rc): $out"; fail=$((fail + 1))
    fi
    : > "$tmp/gh_output"
        n=$((n + 1))
    out=$(env CANARY_API_CMD=: CANARY_URL="file://$tmp/ok.json" DRY_RUN=1 \
          CANARY_TIMEOUT=0 CANARY_INTERVAL=1 GITHUB_OUTPUT="$tmp/gh_output" \
          "$0" v0.17.0 2>&1) && rc=0 || rc=$?
    if [ "$rc" = 0 ] && grep -q '^promoted=true$' "$tmp/gh_output"; then
        echo "ok   ok emits promoted=true"
    else
        echo "FAIL ok emits promoted=true ($rc): $out"; fail=$((fail + 1))
    fi

    # The stale-raw-fail-confirmed-by-api path (the 1.1.0 finding): raw alone
    # answers `fail` for this version, but the contents API -- asked to
    # confirm it, since a `fail` read from raw alone is never acted on
    # directly -- says `ok`. The release must promote.
    run "stale raw fail overturned by api" 0 'ok (api' \
        CANARY_URL="file://$tmp/bad.json" CANARY_API_CMD="cat $tmp/ok.json"
    # The API confirms the fail: it must still block.
    run "raw fail confirmed by api" 1 'fail (api' \
        CANARY_URL="file://$tmp/bad.json" CANARY_API_CMD="cat $tmp/bad.json"
    # The API cannot be reached at all to confirm a raw `fail`: treated as no
    # verdict yet, not as a failure -- an unconfirmed fail must not block.
    run "raw fail unconfirmable waits" 0 '::notice::' \
        CANARY_URL="file://$tmp/bad.json" CANARY_API_CMD="true"

    # The URL derivation, without touching the network: `--url` prints and exits.
        n=$((n + 1))
    got=$("$0" --url v0.17.0)
    want=https://raw.githubusercontent.com/teko-org/teko-lang/canary/0.17.0.json
    if [ "$got" = "$want" ]; then echo "ok   url derived"
    else echo "FAIL url derived: $got"; fail=$((fail + 1)); fi

    # --once, the three exit codes, no sleeping and no promotion attempted.
        n=$((n + 1))
    out=$(CANARY_API_CMD=: CANARY_URL="file://$tmp/ok.json" "$0" --once v0.17.0 2>&1) && rc=0 || rc=$?
    if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^ok$'; then echo "ok   once: ok"
    else echo "FAIL once: ok ($rc): $out"; fail=$((fail + 1)); fi
        n=$((n + 1))
    out=$(CANARY_URL="file://$tmp/bad.json" CANARY_API_CMD="cat $tmp/bad.json" \
          "$0" --once v0.17.0 2>&1) && rc=0 || rc=$?
    if [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^fail$'; then echo "ok   once: fail"
    else echo "FAIL once: fail ($rc): $out"; fail=$((fail + 1)); fi
        n=$((n + 1))
    out=$(CANARY_API_CMD=: CANARY_URL="file://$tmp/none.json" "$0" --once v0.17.0 2>&1) && rc=0 || rc=$?
    if [ "$rc" = 2 ] && printf '%s\n' "$out" | grep -q '^no verdict$'; then echo "ok   once: no verdict"
    else echo "FAIL once: no verdict ($rc): $out"; fail=$((fail + 1)); fi

    pass=$((n - fail))
    echo "canary-poll: $pass/$n"
    [ "$fail" = 0 ] || echo "canary-poll: FAILED"
    exit "$fail"
fi

urlonly=
[ "${1:-}" = "--url" ] && { urlonly=1; shift; }
once=
[ "${1:-}" = "--once" ] && { once=1; shift; }

tag=${1:-}
[ -n "$tag" ] || { echo "usage: canary-poll.sh [--url|--once|--test] TAG" >&2; exit 2; }
version=${tag#v}

repo=${CANARY_REPO:-teko-org/teko-lang}
branch=${CANARY_BRANCH:-canary}
url=${CANARY_URL:-}
[ -n "$url" ] || url="https://raw.githubusercontent.com/$repo/$branch/$version.json"
timeout=${CANARY_TIMEOUT:-900}
interval=${CANARY_INTERVAL:-60}

[ -n "$urlonly" ] && { echo "$url"; exit 0; }

emit_output() { # emit_output NAME VALUE
    [ -n "${GITHUB_OUTPUT:-}" ] && printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
    :
}

promote() {
    if [ -n "${DRY_RUN:-}" ]; then
        echo "canary: would promote -- gh release edit $tag --prerelease=false --latest"
    else
        gh release edit "$tag" --prerelease=false --latest
        echo "canary: $tag is no longer a pre-release"
    fi
    emit_output promoted true
}

byhand() {
    echo "canary: $tag stays a pre-release with every asset attached."
    echo "canary: promote by hand with: gh release edit $tag --prerelease=false --latest"
}

if [ -n "$once" ]; then
    rc=0
    read_verdict || rc=$?
    case "$rc" in
    0) echo ok; exit 0 ;;
    1) echo fail; exit 1 ;;
    *) echo "no verdict"; exit 2 ;;
    esac
fi

echo "canary: $url"
echo "canary: up to ${timeout}s, every ${interval}s, required=${CANARY_REQUIRED:-false}"

waited=0
while :; do
    rc=0
    read_verdict || rc=$?
    case "$rc" in
    0) promote; exit 0 ;;
    1)
        echo "::error::canary: fail verdict for $version"
        byhand
        emit_output promoted false
        exit 1
        ;;
    esac
    [ "$waited" -lt "$timeout" ] || break
    sleep "$interval"
    waited=$((waited + interval))
done

# A timeout is no longer an error the owner must act on: the scheduled
# promoter (.github/workflows/promote-pending.yml, every 30 minutes, no
# timeout of its own) will clear the flag as soon as a real verdict lands,
# `ok` or `fail`. This script never guesses in either direction on a timeout
# -- required or not, the release stays a pre-release until an actual verdict
# is read, which is what `emit_output promoted false` tells a caller that
# must not treat "the job did not fail" as "the release is live".
echo "::notice::canary: no verdict for $version after ${timeout}s -- deferred to the scheduled promoter."
byhand
emit_output promoted false
exit 0
