#!/usr/bin/env bash
# tests/test_phase4_koha_worker_rewrite.sh
#
# Phase 4 koha-worker rewrite guardrails.
# Static checks always run. Runtime checks run only when a test image exists.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_FILE="${ROOT_DIR}/files-alpine/scripts/koha-worker"
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
echo "# Phase 4 - koha-worker Alpine rewrite checks"
echo ""

echo "# --- Static checks ---"

if [ -f "$SCRIPT_FILE" ]; then
    ok "Alpine koha-worker script exists"
else
    not_ok "Alpine koha-worker script exists"
fi

if [ -x "$SCRIPT_FILE" ]; then
    ok "Alpine koha-worker script is executable"
else
    not_ok "Alpine koha-worker script is executable"
fi

if bash -n "$SCRIPT_FILE" >/dev/null 2>&1; then
    ok "Alpine koha-worker shell syntax is valid"
else
    not_ok "Alpine koha-worker shell syntax is valid"
fi

assert_file_not_contains "koha-worker avoids Debian daemon utility" '^[[:space:]]*daemon[[:space:]]' "$SCRIPT_FILE"
assert_file_not_contains "koha-worker avoids Debian retry syntax" '--retry[[:space:]]+QUIT/30/KILL/5|--retry=QUIT/30/KILL/5' "$SCRIPT_FILE"
assert_file_not_contains "koha-worker avoids apt-get" 'apt-get' "$SCRIPT_FILE"
assert_file_not_contains "koha-worker avoids apt-cache" 'apt-cache' "$SCRIPT_FILE"
assert_file_not_contains "koha-worker avoids dpkg-query" 'dpkg-query' "$SCRIPT_FILE"
assert_file_not_contains "koha-worker avoids lsb_release" 'lsb_release' "$SCRIPT_FILE"
assert_file_contains "koha-worker includes queue flag" '--queue' "$SCRIPT_FILE"
assert_file_contains "koha-worker locates current Koha worker path" 'misc/workers/background_jobs_worker\.pl' "$SCRIPT_FILE"
assert_file_contains "koha-worker supports all configured queues" --all-queues "$SCRIPT_FILE"
assert_file_contains "koha-worker includes Alpine process fallback" 'kill -0' "$SCRIPT_FILE"
if "$SCRIPT_FILE" --help >/dev/null 2>&1; then
    ok "koha-worker --help exits successfully without setup"
else
    not_ok "koha-worker --help exits successfully without setup"
fi

assert_file_contains "koha-worker runs the ES indexer daemon for the elastic_index queue" 'misc/workers/es_indexer_daemon\.pl' "$SCRIPT_FILE"
assert_file_contains "Alpine service library starts the elastic_index worker when OpenSearch is enabled" 'koha-worker --start --queue elastic_index' "${ROOT_DIR}/files-alpine/lib/run-sh-alpine.sh"
assert_file_contains "watchdog supervises the elastic_index worker" 'elastic_index worker is down' "${ROOT_DIR}/files-alpine/lib/run-sh-alpine.sh"
assert_file_contains "run.sh substitutes ELASTIC_SERVER into koha-conf" 'ELASTIC_SERVER_ESC' "${ROOT_DIR}/files-alpine/run.sh"
assert_file_contains "run.sh injects ELASTIC_OPTIONS into koha-conf" 'ELASTIC_OPTIONS' "${ROOT_DIR}/files-alpine/run.sh"
assert_file_contains "run.sh links admin/searchengine mappings into the intranet cgi-bin tree" 'cgi-bin/admin' "${ROOT_DIR}/files-alpine/run.sh"
assert_file_contains "Dockerfile installs Alpine command overrides after asset staging" 'for script in koha-create koha-plack koha-worker koha-functions\.sh' "$DOCKERFILE"

runtime_available=0
if docker image inspect "$KOHA_IMAGE" >/dev/null 2>&1; then
    runtime_available=1
fi

echo ""
echo "# --- Runtime checks ---"

if [ "$runtime_available" -eq 0 ]; then
    skip "koha-worker points to Alpine script in test image" "No image ${KOHA_IMAGE} available"
    skip "koha-worker --help works in test image" "No image ${KOHA_IMAGE} available"
else
    out_path=$(docker run --rm --entrypoint /bin/sh "$KOHA_IMAGE" -c 'command -v koha-worker')
    if [ "$out_path" = "/usr/sbin/koha-worker" ]; then
        ok "koha-worker points to Alpine script in test image"
    else
        not_ok "koha-worker points to Alpine script in test image (got: $out_path)"
    fi

    if docker run --rm --entrypoint /bin/sh "$KOHA_IMAGE" -c 'koha-worker --help >/dev/null 2>&1'; then
        ok "koha-worker --help works in test image"
    else
        not_ok "koha-worker --help works in test image"
    fi
fi

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}  Skipped: ${SKIP}"
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
