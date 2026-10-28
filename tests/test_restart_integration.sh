#!/usr/bin/env bash
# tests/test_restart_integration.sh
#
# Integration test: verifies that restarting just the Koha container against a
# persistent database does NOT fail with "Database is not empty!".
#
# Prerequisites
#   - An explicitly selected, isolated, running test project
#   - The koha-db-data volume must be populated (i.e. Koha has been set up)
#   - Docker must be accessible from the current user
#
# What it does
#   1. Confirms the stack is healthy before the test.
#   2. Stops the Koha container (DB + Memcached stay up).
#   3. Restarts the Koha container via docker compose up --force-recreate.
#   4. Waits up to MAX_WAIT seconds for the Alpine startup-complete log.
#   5. Checks the container did not exit with code 255 ("Database is not empty!").
#
# Exit code: 0 = pass/skip, 1 = fail, 2 = invalid explicitly selected prerequisites.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/docker-compose-alpinekoha.yml"
ENV_FILE="${KOHA_TEST_ENV_FILE:-}"
TEST_PROJECT="${KOHA_TEST_PROJECT:-}"
COMPOSE_OVERRIDE="${KOHA_TEST_COMPOSE_OVERRIDE:-}"
MAX_WAIT=${MAX_WAIT:-300}   # seconds to wait for Koha to finish re-initialising

# ── tiny TAP helper ──────────────────────────────────────────────────────────
PASS=0; FAIL=0; _N=0
ok()     { _N=$(( _N + 1 )); echo "ok ${_N} - $1";     PASS=$(( PASS + 1 )); }
not_ok() { _N=$(( _N + 1 )); echo "not ok ${_N} - $1"; FAIL=$(( FAIL + 1 )); }
skip()   { _N=$(( _N + 1 )); echo "ok ${_N} - $1 # SKIP $2"; }
# ─────────────────────────────────────────────────────────────────────────────

compose() {
    local -a command=(docker compose --project-name "${TEST_PROJECT}" --env-file "${ENV_FILE}" --project-directory "${REPO_ROOT}" -f "${COMPOSE_FILE}")
    if [[ -n "${COMPOSE_OVERRIDE}" ]]; then
        command+=(-f "${COMPOSE_OVERRIDE}")
    fi
    "${command[@]}" "$@"
}

echo "TAP version 14"
echo "# Integration test — Koha container restart with persistent database"
echo ""

# ── Prerequisite: Docker available ──────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
    skip "restart integration prerequisites" "docker not found"
    skip "Koha container restart succeeds" "docker not found"
    skip "Container does not exit with code 255" "docker not found"
    echo "1..${_N}"
    exit 0
fi

# ── Prerequisite: explicit isolated test project ────────────────────────────
if [[ -z "${TEST_PROJECT}" || -z "${ENV_FILE}" ]]; then
    skip "restart integration prerequisites" "set KOHA_TEST_PROJECT and KOHA_TEST_ENV_FILE for an isolated running stack"
    skip "Koha container restart succeeds" "no isolated test project selected"
    skip "Container does not exit with code 255" "no isolated test project selected"
    echo "1..${_N}"
    exit 0
fi

if [[ ! "${TEST_PROJECT}" =~ ^koha-alpine-test-[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
    echo "Bail out! KOHA_TEST_PROJECT must use the unique koha-alpine-test-<suffix> prefix"
    exit 2
fi

# ── Prerequisite: selected Compose configuration ────────────────────────────
if [[ ! -f "${COMPOSE_FILE}" || ! -f "${ENV_FILE}" ]]; then
    echo "Bail out! compose or selected test env file not found"
    exit 2
fi

export KOHA_CONTAINER_ENV_FILE="${ENV_FILE}"
if ! compose config --quiet >/dev/null 2>&1; then
    echo "Bail out! selected test Compose configuration is invalid"
    exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Bail out! python3 is required to verify the selected DB volume"
    exit 2
fi
DB_VOLUME="$(compose config --format json | python3 -c 'import json, sys; print(json.load(sys.stdin)["volumes"]["koha-db-data"]["name"])')"
if [[ "${DB_VOLUME}" != "${TEST_PROJECT}_"* ]]; then
    echo "Bail out! DB volume is not scoped to the isolated project: ${DB_VOLUME}"
    exit 2
fi

# ── Prerequisite: DB container running ───────────────────────────────────────
if ! compose ps --status running db 2>/dev/null | grep -q "running\|Up"; then
    skip "DB container is running" "project ${TEST_PROJECT} is not started"
    skip "Koha container restart succeeds" "stack is not started"
    skip "Container does not exit with code 255" "stack is not started"
    echo ""
    echo "1..${_N}"
    echo "# Skipped: stack is not running"
    exit 0
fi
ok "DB container is running"

if ! compose ps --status running koha 2>/dev/null | grep -q "running\|Up"; then
    skip "Koha container restart succeeds" "Koha service is not running in project ${TEST_PROJECT}"
    skip "Container does not exit with code 255" "Koha service is not running"
    echo "1..${_N}"
    exit 0
fi

# ── Prerequisite: Koha DB has existing data ──────────────────────────────────
KOHA_INSTANCE=$(grep -E '^KOHA_INSTANCE=' "${ENV_FILE}" | head -1 | cut -d= -f2- | tr -d '"'"'" || echo "kohadev")
DB_NAME="koha_${KOHA_INSTANCE}"
DB_CONTAINER="$(compose ps -q db)"

DB_ROOT_PASS="$(grep -E '^KOHA_DB_ROOT_PASSWORD=' "${ENV_FILE}" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'" || true)"
if [[ -z "${DB_ROOT_PASS}" ]]; then
    echo "Bail out! KOHA_DB_ROOT_PASSWORD is empty in selected test env file"
    exit 2
fi

tables=$(docker exec -e "MYSQL_PWD=${DB_ROOT_PASS}" "${DB_CONTAINER}" \
    mysql -uroot "${DB_NAME}" \
    -sse "SELECT COUNT(*) FROM information_schema.tables
          WHERE table_schema='${DB_NAME}'
          AND table_name='systempreferences';" 2>/dev/null || echo 0)

if [[ "${tables:-0}" -eq 0 ]]; then
    skip "Database has existing Koha data" "systempreferences not found — cannot test restart against empty DB"
    skip "Koha container restart succeeds" "no existing data"
    skip "Container does not exit with code 255" "no existing data"
    echo ""
    echo "1..${_N}"
    echo "# Skipped: Koha database is empty (run the stack fully first)"
    exit 0
fi
ok "Database '${DB_NAME}' has existing Koha data (systempreferences present)"

# ── Stop the Koha container ───────────────────────────────────────────────────
echo "# Stopping Koha container..."
compose stop koha 2>&1 | sed 's/^/# /'

# ── Restart Koha without wiping the DB ───────────────────────────────────────
echo "# Restarting Koha container with USE_EXISTING_DB=yes (simulating production restart)..."
USE_EXISTING_DB=yes compose up -d --force-recreate koha 2>&1 | sed 's/^/# /'

# ── Wait for startup to complete ─────────────────────────────────────────────
echo "# Waiting up to ${MAX_WAIT}s for Koha to finish re-initialising..."
elapsed=0
startup_ok=false
error_255=false

while (( elapsed < MAX_WAIT )); do
    sleep 5
    elapsed=$(( elapsed + 5 ))

    # Check whether the container exited (code 255 = "Database is not empty!")
    KOHA_CONTAINER="$(compose ps -q koha 2>/dev/null || true)"
    state=$(docker inspect --format '{{.State.Status}}' "${KOHA_CONTAINER}" 2>/dev/null || echo "unknown")
    exit_code=$(docker inspect --format '{{.State.ExitCode}}' "${KOHA_CONTAINER}" 2>/dev/null || echo -1)

    if [[ "${state}" == "exited" && "${exit_code}" == "255" ]]; then
        error_255=true
        break
    fi

    # Check logs for the success banner
    if compose logs --tail=50 koha 2>/dev/null | grep -q "Startup complete - OPAC on"; then
        startup_ok=true
        break
    fi

    # Check logs for the fatal error (fail fast)
    if compose logs --tail=50 koha 2>/dev/null | grep -q "Database is not empty!"; then
        error_255=true
        break
    fi

    printf "\r# [%ds] waiting..." "${elapsed}"
done
echo ""

# ── Assertions ───────────────────────────────────────────────────────────────
if [[ "${error_255}" == true ]]; then
    not_ok "Koha container restart succeeds (FATAL: 'Database is not empty!' detected)"
    not_ok "Container does not exit with code 255"
else
    ok "Koha container restart succeeds (no 'Database is not empty!' error)"
    if [[ "${startup_ok}" == true ]]; then
        ok "Container started up fully (success banner found in logs)"
    else
        not_ok "Container started up fully within ${MAX_WAIT}s (banner not seen — check logs)"
    fi
fi

# ── Cleanup note ─────────────────────────────────────────────────────────────
echo ""
echo "# NOTE: only the selected isolated project's Koha service was restarted; its database volume was not removed."

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}"
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
