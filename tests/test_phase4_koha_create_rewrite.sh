#!/usr/bin/env bash
# tests/test_phase4_koha_create_rewrite.sh
#
# Phase 4 koha-create rewrite guardrails.
# Static checks always run. Runtime checks run only when a test image exists.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_FILE="${ROOT_DIR}/files-alpine/scripts/koha-create"
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
echo "# Phase 4 - koha-create Alpine rewrite checks"
echo ""

echo "# --- Static checks ---"

if [ -f "$SCRIPT_FILE" ]; then
    ok "Alpine koha-create script exists"
else
    not_ok "Alpine koha-create script exists"
fi

if [ -x "$SCRIPT_FILE" ]; then
    ok "Alpine koha-create script is executable"
else
    not_ok "Alpine koha-create script is executable"
fi

if /bin/sh -n "$SCRIPT_FILE" >/dev/null 2>&1; then
    ok "Alpine koha-create shell syntax is valid"
else
    not_ok "Alpine koha-create shell syntax is valid"
fi

assert_file_not_contains "koha-create avoids apt-get" 'apt-get' "$SCRIPT_FILE"
assert_file_not_contains "koha-create avoids apt-cache" 'apt-cache' "$SCRIPT_FILE"
assert_file_not_contains "koha-create avoids dpkg-query" 'dpkg-query' "$SCRIPT_FILE"
assert_file_not_contains "koha-create avoids lsb_release" 'lsb_release' "$SCRIPT_FILE"
assert_file_not_contains "koha-create avoids mpm_itk" 'mpm_itk' "$SCRIPT_FILE"
assert_file_not_contains "koha-create avoids service apache2 restart" 'service[[:space:]]+apache2[[:space:]]+restart' "$SCRIPT_FILE"
assert_file_contains "koha-create uses canonical .conf symlink" 'sites-enabled/\$name\.conf' "$SCRIPT_FILE"

assert_file_not_contains "Dockerfile no longer injects adduser translation shim" '/usr/local/bin/adduser' "$DOCKERFILE"
assert_file_not_contains "Dockerfile no longer spoofs mpm_itk" 'mpm_itk_module' "$DOCKERFILE"

runtime_available=0
if docker image inspect "$KOHA_IMAGE" >/dev/null 2>&1; then
    runtime_available=1
fi

echo ""
echo "# --- Runtime checks ---"

if [ "$runtime_available" -eq 0 ]; then
    skip "koha-create points to Alpine script in test image" "No image ${KOHA_IMAGE} available"
    skip "apachectl -M output has no mpm_itk spoof" "No image ${KOHA_IMAGE} available"
else
    out_path=$(docker run --rm --entrypoint /bin/sh "$KOHA_IMAGE" -c 'command -v koha-create')
    if [ "$out_path" = "/usr/sbin/koha-create" ]; then
        ok "koha-create points to Alpine script in test image"
    else
        not_ok "koha-create points to Alpine script in test image (got: $out_path)"
    fi

    if docker run --rm --entrypoint /bin/sh "$KOHA_IMAGE" -c 'apachectl -M 2>/dev/null | grep -q mpm_itk'; then
        not_ok "apachectl -M output has no mpm_itk spoof"
    else
        ok "apachectl -M output has no mpm_itk spoof"
    fi
fi

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}  Skipped: ${SKIP}"
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
