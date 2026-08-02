#!/usr/bin/env bash
# tests/test_phase4_koha_functions_rewrite.sh
#
# Phase 4 koha-functions rewrite guardrails.
# Static checks always run. Runtime checks run only when a test image exists.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_FILE="${ROOT_DIR}/files-alpine/scripts/koha-functions.sh"
DOCKERFILE="${ROOT_DIR}/Dockerfile-Alpine"
KOHA_CREATE_SCRIPT="${ROOT_DIR}/files-alpine/scripts/koha-create"
KOHA_PLACK_SCRIPT="${ROOT_DIR}/files-alpine/scripts/koha-plack"
KOHA_WORKER_SCRIPT="${ROOT_DIR}/files-alpine/scripts/koha-worker"
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
echo "# Phase 4 - koha-functions Alpine rewrite checks"
echo ""

echo "# --- Static checks ---"

if [ -f "$SCRIPT_FILE" ]; then
    ok "Alpine koha-functions script exists"
else
    not_ok "Alpine koha-functions script exists"
fi

if [ -x "$SCRIPT_FILE" ]; then
    ok "Alpine koha-functions script is executable"
else
    not_ok "Alpine koha-functions script is executable"
fi

if /bin/sh -n "$SCRIPT_FILE" >/dev/null 2>&1; then
    ok "Alpine koha-functions shell syntax is valid"
else
    not_ok "Alpine koha-functions shell syntax is valid"
fi

assert_file_not_contains "koha-functions override avoids daemon utility invocation" '^[[:space:]]*daemon[[:space:]]' "$SCRIPT_FILE"
assert_file_not_contains "koha-functions override avoids start-stop-daemon --status" '--status' "$SCRIPT_FILE"
assert_file_contains "koha-functions override has worker running check" '^is_worker_running\(\)' "$SCRIPT_FILE"
assert_file_contains "koha-functions override has plack running check" '^is_plack_running\(\)' "$SCRIPT_FILE"
assert_file_contains "koha-functions override has z3950 running check" '^is_z3950_running\(\)' "$SCRIPT_FILE"

assert_file_contains "Dockerfile installs Alpine koha-functions override" 'install -m 0755 /kohadevbox/files-alpine/scripts/koha-functions\.sh /usr/sbin/koha-functions\.sh' "$DOCKERFILE"
assert_file_contains "koha-create sources Alpine koha-functions first" '/usr/sbin/koha-functions.sh' "$KOHA_CREATE_SCRIPT"
assert_file_contains "koha-plack sources Alpine koha-functions first" '/usr/sbin/koha-functions.sh' "$KOHA_PLACK_SCRIPT"
assert_file_contains "koha-worker sources Alpine koha-functions first" '/usr/sbin/koha-functions.sh' "$KOHA_WORKER_SCRIPT"

runtime_available=0
if docker image inspect "$KOHA_IMAGE" >/dev/null 2>&1; then
    runtime_available=1
fi

echo ""
echo "# --- Runtime checks ---"

if [ "$runtime_available" -eq 0 ]; then
    skip "koha-functions points to Alpine override in test image" "No image ${KOHA_IMAGE} available"
else
    out_path=$(docker run --rm --entrypoint /bin/sh "$KOHA_IMAGE" -c 'command -v koha-functions.sh')
    if [ "$out_path" = "/usr/sbin/koha-functions.sh" ]; then
        ok "koha-functions points to Alpine override in test image"
    else
        not_ok "koha-functions points to Alpine override in test image (got: $out_path)"
    fi
fi

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}  Skipped: ${SKIP}"
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
