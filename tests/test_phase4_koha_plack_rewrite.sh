#!/usr/bin/env bash
# tests/test_phase4_koha_plack_rewrite.sh
#
# Phase 4 koha-plack rewrite guardrails.
# Static checks always run. Runtime checks run only when a test image exists.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_FILE="${ROOT_DIR}/files-alpine/scripts/koha-plack"
DOCKERFILE="${ROOT_DIR}/Dockerfile-Alpine"
KOHA_IMAGE="${KOHA_TEST_IMAGE:-koha-alpine:phase4-koha-create}"

PASS=0; FAIL=0; SKIP=0; _N=0
ok()      { _N=$((_N+1)); echo "ok ${_N} - $1";           PASS=$((PASS+1)); }
not_ok()  { _N=$((_N+1)); echo "not ok ${_N} - $1";       FAIL=$((FAIL+1)); }
skip()    { _N=$((_N+1)); echo "ok ${_N} - $1 # SKIP $2"; SKIP=$((SKIP+1)); }

assert_file_contains() {
    local desc="$1" pattern="$2" file="$3"
    if grep -qE -- "$pattern" "$file"; then
        ok "$desc"
    else
        not_ok "$desc (pattern not found: $pattern)"
    fi
}

assert_file_not_contains() {
    local desc="$1" pattern="$2" file="$3"
    if grep -qE -- "$pattern" "$file"; then
        not_ok "$desc (forbidden pattern found: $pattern)"
    else
        ok "$desc"
    fi
}

echo "TAP version 14"
echo "# Phase 4 - koha-plack Alpine rewrite checks"
echo ""

echo "# --- Static checks ---"

if [ -f "$SCRIPT_FILE" ]; then
    ok "Alpine koha-plack script exists"
else
    not_ok "Alpine koha-plack script exists"
fi

if [ -x "$SCRIPT_FILE" ]; then
    ok "Alpine koha-plack script is executable"
else
    not_ok "Alpine koha-plack script is executable"
fi

if /bin/sh -n "$SCRIPT_FILE" >/dev/null 2>&1; then
    ok "Alpine koha-plack shell syntax is valid"
else
    not_ok "Alpine koha-plack shell syntax is valid"
fi

assert_file_not_contains "koha-plack avoids apt-get" 'apt-get' "$SCRIPT_FILE"
assert_file_not_contains "koha-plack avoids apt-cache" 'apt-cache' "$SCRIPT_FILE"
assert_file_not_contains "koha-plack avoids dpkg-query" 'dpkg-query' "$SCRIPT_FILE"
assert_file_not_contains "koha-plack avoids lsb_release" 'lsb_release' "$SCRIPT_FILE"
assert_file_not_contains "koha-plack avoids Debian retry syntax" '--retry=QUIT/30/KILL/5' "$SCRIPT_FILE"
assert_file_not_contains "koha-plack avoids runtime a2enmod execution" '\ba2enmod\b' "$SCRIPT_FILE"
assert_file_contains "koha-plack implements Alpine process fallback" 'kill -0' "$SCRIPT_FILE"
assert_file_contains "koha-plack includes enable action" '--enable' "$SCRIPT_FILE"
assert_file_contains "koha-plack includes start action" '--start' "$SCRIPT_FILE"

assert_file_contains "Dockerfile installs Alpine koha-plack override" 'install -m 0755 /kohadevbox/files-alpine/scripts/koha-plack /usr/sbin/koha-plack' "$DOCKERFILE"

runtime_available=0
if docker image inspect "$KOHA_IMAGE" >/dev/null 2>&1; then
    runtime_available=1
fi

echo ""
echo "# --- Runtime checks ---"

if [ "$runtime_available" -eq 0 ]; then
    skip "koha-plack points to Alpine script in test image" "No image ${KOHA_IMAGE} available"
    skip "koha-plack --help works in test image" "No image ${KOHA_IMAGE} available"
else
    out_path=$(docker run --rm --entrypoint /bin/sh "$KOHA_IMAGE" -c 'command -v koha-plack')
    if [ "$out_path" = "/usr/sbin/koha-plack" ]; then
        ok "koha-plack points to Alpine script in test image"
    else
        not_ok "koha-plack points to Alpine script in test image (got: $out_path)"
    fi

    if docker run --rm --entrypoint /bin/sh "$KOHA_IMAGE" -c 'koha-plack --help >/dev/null 2>&1'; then
        ok "koha-plack --help works in test image"
    else
        not_ok "koha-plack --help works in test image"
    fi
fi

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}  Skipped: ${SKIP}"
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
