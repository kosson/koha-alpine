#!/usr/bin/env bash
# tests/run_integration_deterministic.sh
#
# Deterministic integration runner:
# - isolates test phases by preparing known stack state
# - enforces an execution order that avoids cross-test contamination
# - stores individual logs and prints a final stable summary
#
# Usage:
#   cd koha-alpine
#   bash tests/run_integration_deterministic.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ALPINE_COMPOSE="${REPO_ROOT}/docker-compose-alpinekoha.yml"
ENV_FILE="${KOHA_TEST_ENV_FILE:-}"
TEST_PROJECT="${KOHA_TEST_PROJECT:-}"
COMPOSE_OVERRIDE="${KOHA_TEST_COMPOSE_OVERRIDE:-}"

if [[ -z "${TEST_PROJECT}" || -z "${ENV_FILE}" ]]; then
    echo "SKIP: set KOHA_TEST_PROJECT and KOHA_TEST_ENV_FILE for a disposable isolated test stack"
    exit 0
fi

if [[ ! "${TEST_PROJECT}" =~ ^koha-alpine-test-[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
    echo "Bail out! KOHA_TEST_PROJECT must use the unique koha-alpine-test-<suffix> prefix"
    exit 2
fi

if [[ ! -f "${ALPINE_COMPOSE}" || ! -f "${ENV_FILE}" ]]; then
    echo "Bail out! compose or selected test env file not found"
    exit 2
fi

if ! command -v docker >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo "Bail out! docker and python3 are required for isolated volume verification"
    exit 2
fi

export KOHA_CONTAINER_ENV_FILE="${ENV_FILE}"
export KOHA_TEST_PROJECT KOHA_TEST_ENV_FILE KOHA_TEST_COMPOSE_OVERRIDE

alpine_compose() {
    local -a command=(docker compose --project-name "${TEST_PROJECT}" --env-file "${ENV_FILE}" --project-directory "${REPO_ROOT}" -f "${ALPINE_COMPOSE}")
    if [[ -n "${COMPOSE_OVERRIDE}" ]]; then
        command+=(-f "${COMPOSE_OVERRIDE}")
    fi
    "${command[@]}" "$@"
}

if ! alpine_compose config --quiet >/dev/null 2>&1; then
    echo "Bail out! selected test Compose configuration is invalid"
    exit 2
fi

if [[ -n "$(alpine_compose ps -q 2>/dev/null || true)" ]]; then
    echo "Bail out! selected test project already has containers; use a new project name"
    exit 2
fi

DB_VOLUME="$(alpine_compose config --format json | python3 -c 'import json, sys; print(json.load(sys.stdin)["volumes"]["koha-db-data"]["name"])')"
if [[ "${DB_VOLUME}" != "${TEST_PROJECT}_"* ]]; then
    echo "Bail out! DB volume is not scoped to the isolated project: ${DB_VOLUME}"
    exit 2
fi
if docker volume inspect "${DB_VOLUME}" >/dev/null 2>&1; then
    echo "Bail out! fresh-project DB volume already exists: ${DB_VOLUME}; choose a new project name"
    exit 2
fi

KOHA_INSTANCE="$(grep -E '^KOHA_INSTANCE=' "${ENV_FILE}" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'" || true)"
KOHA_INSTANCE="${KOHA_INSTANCE:-kohadev}"
DB_NAME="koha_${KOHA_INSTANCE}"
DB_PASS="$(grep -E '^KOHA_DB_ROOT_PASSWORD=' "${ENV_FILE}" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'" || true)"
if [[ -z "${DB_PASS}" ]]; then
    echo "Bail out! KOHA_DB_ROOT_PASSWORD is empty in selected test env file"
    exit 2
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ARTIFACT_DIR="${SCRIPT_DIR}/artifacts/integration-${STAMP}"
mkdir -p "${ARTIFACT_DIR}"

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; RESET=''
fi

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${RESET} $*"; }
ok()   { echo -e "${GREEN}[$(date +%H:%M:%S)]${RESET} $*"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)]${RESET} $*"; }
err()  { echo -e "${RED}[$(date +%H:%M:%S)]${RESET} $*"; }

wait_for_systempreferences() {
    local max_wait="${1:-420}"
    local elapsed=0

    while (( elapsed < max_wait )); do
        if alpine_compose exec -T db sh -lc "mysql -uroot -p\"${DB_PASS}\" -Nse \"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='systempreferences';\"" 2>/dev/null | grep -qx '1'; then
            return 0
        fi
        sleep 5
        elapsed=$(( elapsed + 5 ))
    done

    return 1
}

bootstrap_alpine_populated_db() {
    log "Preparing Alpine stack with populated database for restart/authority tests"
    alpine_compose up -d db memcached rabbitmq koha >/dev/null

    if wait_for_systempreferences 480; then
        ok "Alpine DB is populated (${DB_NAME}.systempreferences exists)"
    else
        err "Alpine DB was not populated in time"
        alpine_compose logs --tail=120 koha | sed 's/^/[alpine-koha] /' || true
        return 1
    fi
}

ensure_alpine_ready() {
    log "Preparing Alpine stack state for Alpine smoke test"
    alpine_compose up -d db memcached rabbitmq koha >/dev/null

    local max_wait=180
    local elapsed=0
    while (( elapsed < max_wait )); do
        if alpine_compose exec -T koha sh -lc 'test -f /ktd_ready' >/dev/null 2>&1; then
            ok "Alpine koha container reached /ktd_ready"
            return 0
        fi
        sleep 3
        elapsed=$(( elapsed + 3 ))
    done

    err "Alpine koha container did not reach /ktd_ready in ${max_wait}s"
    return 1
}

TOTAL=0
FAILED=0
PASSED=0
SKIPPED=0

run_test() {
    local script="$1"
    local name
    local out_file
    local rc=0

    name="$(basename "${script}" .sh)"
    out_file="${ARTIFACT_DIR}/${name}.log"

    TOTAL=$(( TOTAL + 1 ))

    log "Running ${script}"
    set +e
    bash "${script}" >"${out_file}" 2>&1
    rc=$?
    set -e

    if [[ ${rc} -eq 0 ]]; then
        if grep -q '# SKIP' "${out_file}"; then
            SKIPPED=$(( SKIPPED + 1 ))
            warn "${name}: pass-with-skip (rc=${rc})"
        else
            PASSED=$(( PASSED + 1 ))
            ok "${name}: pass"
        fi
    else
        FAILED=$(( FAILED + 1 ))
        err "${name}: fail (rc=${rc})"
    fi

    echo "----- ${name} output -----"
    sed -n '1,80p' "${out_file}"
    echo "----- end ${name} -----"
    echo ""
}

main() {
    if ! command -v docker >/dev/null 2>&1; then
        err "docker not found"
        exit 2
    fi

    log "Integration artifacts directory: ${ARTIFACT_DIR}"

    # Phase 1: DB readiness race test (self-isolates with down -v)
    run_test "${SCRIPT_DIR}/test_mariadb_auth_readiness_integration.sh"

    # Phase 2: Populate Alpine DB so restart + authority tests run deterministically
    bootstrap_alpine_populated_db || FAILED=$(( FAILED + 1 ))

    # Phase 3: Alpine integration tests that require populated DB
    run_test "${SCRIPT_DIR}/test_restart_integration.sh"
    run_test "${SCRIPT_DIR}/test_authority_groupby_sqlmode_integration.sh"

    # Phase 4: OpenSearch auth check (pass or pass-with-skip if cluster absent)
    run_test "${SCRIPT_DIR}/test_opensearch_os01_auth_integration.sh"

    # Phase 5: Re-align to Alpine runtime and run smoke checks
    ensure_alpine_ready || FAILED=$(( FAILED + 1 ))
    run_test "${SCRIPT_DIR}/test_alpine_startup_smoke.sh"

    echo ""
    echo "============================================================"
    echo "Integration summary"
    echo "  total tests:   ${TOTAL}"
    echo "  passed:        ${PASSED}"
    echo "  pass-with-skip:${SKIPPED}"
    echo "  failed:        ${FAILED}"
    echo "  artifacts:     ${ARTIFACT_DIR}"
    echo "============================================================"

    if [[ ${FAILED} -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
