#!/bin/sh
# canary-poll.sh -- wait for the consumer's verdict on an mc release, then promote it.
#
#   canary-poll.sh TAG
#
# The canary (docs/specs/M53.md § 6, docs/ci.md § The canary) crosses the
# repository boundary with NO CREDENTIAL in either direction. `release.yml`'s
# `publish` job creates the GitHub Release as a PRE-RELEASE; the consumer
# notices it by polling mc's public releases API, runs its whole recipe against
# the tarball, and writes a verdict into a branch of its OWN repository with its
# OWN token. This script is the mc half: it reads that file anonymously with
# `curl` and flips the pre-release flag.
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
# Environment:
#   CANARY_REPO      owner/repo publishing the verdict   (teko-org/teko-lang)
#   CANARY_BRANCH    the branch it writes to             (canary)
#   CANARY_URL       the whole URL, overriding both      (derived)
#   CANARY_TIMEOUT   seconds to wait for a verdict       (5400 = 90 minutes)
#   CANARY_INTERVAL  seconds between polls               (60)
#   CANARY_REQUIRED  `true` -> a TIMEOUT is a failure and the release stays a
#                    pre-release (1.0.0 and after). Anything else -> advisory:
#                    a timeout promotes anyway with a `::notice::`, so an
#                    outage on the consumer's side cannot hold an mc patch.
#                    A `fail` VERDICT is a failure either way.
#   DRY_RUN          non-empty -> print what would happen, touch no release
#   GH_TOKEN         needed by `gh release edit` unless DRY_RUN is set
#
# Exit 0: the release was promoted (verdict `ok`, or an advisory timeout).
# Exit 1: it was not (verdict `fail`, or a timeout while required). Every asset
#         stays attached and `gh release edit "$TAG" --prerelease=false`
#         promotes it by hand; a rerun of the job alone is the retry.
set -eu

if [ "${1:-}" = "--test" ]; then
    tmp=$(mktemp -d) || exit 1
    trap 'rm -rf "$tmp"' EXIT
    fail=0
    # Each case runs the real poll loop over a `file://` URL. CANARY_TIMEOUT=0
    # makes it poll exactly once and then time out, so a case with no verdict
    # file costs one failed `curl file://` instead of ninety minutes.
    run() { # run NAME WANT_RC WANT_GREP [env...]
        name=$1 want=$2 pat=$3
        shift 3
        out=$(env DRY_RUN=1 CANARY_TIMEOUT=0 CANARY_INTERVAL=1 "$@" \
              "$0" v0.17.0 2>&1) && rc=0 || rc=$?
        if [ "$rc" != "$want" ]; then
            echo "FAIL $name: exit $rc, want $want"; echo "$out"; fail=1; return
        fi
        if ! printf '%s\n' "$out" | grep -q "$pat"; then
            echo "FAIL $name: no /$pat/ in output"; echo "$out"; fail=1; return
        fi
        echo "ok   $name"
    }
    printf '%s\n' '{"version":"0.17.0","status":"ok","run":"u","utc":"t"}'   > "$tmp/ok.json"
    printf '%s\n' '{"version":"0.17.0","status":"fail","run":"u","utc":"t"}' > "$tmp/bad.json"
    printf '%s\n' '{"version":"0.16.0","status":"ok","run":"u","utc":"t"}'   > "$tmp/old.json"
    printf '%s\n' '{"version":"v0.17.0","status":"ok","run":"u","utc":"t"}'  > "$tmp/vpre.json"
    run "ok promotes"           0 'would promote' CANARY_URL="file://$tmp/ok.json"
    run "v-prefix accepted"     0 'would promote' CANARY_URL="file://$tmp/vpre.json"
    run "fail stays pre"        1 'status: fail'  CANARY_URL="file://$tmp/bad.json"
    run "another version waits" 0 'no verdict'    CANARY_URL="file://$tmp/old.json"
    run "timeout advisory"      0 '::notice::'    CANARY_URL="file://$tmp/none.json"
    run "timeout required"      1 '::error::'     CANARY_URL="file://$tmp/none.json" \
                                                  CANARY_REQUIRED=true
    # The URL derivation, without touching the network: `--url` prints and exits.
    got=$("$0" --url v0.17.0)
    want=https://raw.githubusercontent.com/teko-org/teko-lang/canary/0.17.0.json
    if [ "$got" = "$want" ]; then echo "ok   url derived"
    else echo "FAIL url derived: $got"; fail=1; fi
    [ "$fail" = 0 ] && echo "canary-poll: 7/7" || echo "canary-poll: FAILED"
    exit "$fail"
fi

urlonly=
[ "${1:-}" = "--url" ] && { urlonly=1; shift; }

tag=${1:-}
[ -n "$tag" ] || { echo "usage: canary-poll.sh [--url|--test] TAG" >&2; exit 2; }
version=${tag#v}

repo=${CANARY_REPO:-teko-org/teko-lang}
branch=${CANARY_BRANCH:-canary}
url=${CANARY_URL:-}
[ -n "$url" ] || url="https://raw.githubusercontent.com/$repo/$branch/$version.json"
timeout=${CANARY_TIMEOUT:-5400}
interval=${CANARY_INTERVAL:-60}

[ -n "$urlonly" ] && { echo "$url"; exit 0; }

echo "canary: $url"
echo "canary: up to ${timeout}s, every ${interval}s, required=${CANARY_REQUIRED:-false}"

promote() {
    if [ -n "${DRY_RUN:-}" ]; then
        echo "canary: would promote -- gh release edit $tag --prerelease=false"
    else
        gh release edit "$tag" --prerelease=false
        echo "canary: $tag is no longer a pre-release"
    fi
}

byhand() {
    echo "canary: $tag stays a pre-release with every asset attached."
    echo "canary: promote by hand with: gh release edit $tag --prerelease=false"
}

waited=0
while :; do
    # `curl -f` is non-zero on the 404 raw.githubusercontent.com answers while
    # the file does not exist yet, which is the ordinary case for most of the
    # wait; `|| body=` turns that into "keep polling" without tripping `set -e`.
    body=$(curl -fsSL --max-time 30 "$url" 2>/dev/null) || body=
    if [ -n "$body" ]; then
        status=$(printf '%s' "$body" | jq -r '.status // empty' 2>/dev/null) || status=
        got=$(printf '%s' "$body" | jq -r '.version // empty' 2>/dev/null) || got=
        got=${got#v}
        if [ -n "$got" ] && [ "$got" != "$version" ]; then
            # A verdict for some other release: not ours, keep waiting.
            echo "canary: the file names $got, waiting for $version"
            status=
        fi
        case "$status" in
        ok)
            echo "canary: status: ok -- $(printf '%s' "$body" | jq -r '.run // "no run url"')"
            promote
            exit 0
            ;;
        fail)
            echo "::error::canary: status: fail -- $(printf '%s' "$body" | jq -r '.run // "no run url"')"
            byhand
            exit 1
            ;;
        esac
    fi
    [ "$waited" -lt "$timeout" ] || break
    sleep "$interval"
    waited=$((waited + interval))
done

if [ "${CANARY_REQUIRED:-}" = "true" ]; then
    echo "::error::canary: no verdict for $version after ${timeout}s, and the canary is required."
    byhand
    exit 1
fi
echo "::notice::canary: no verdict for $version after ${timeout}s -- advisory, promoting anyway."
promote
exit 0
