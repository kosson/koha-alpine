#!/usr/bin/env bash
# Verifies that an Alpine test project gets its own named volumes and containers.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose-alpinekoha.yml"
PROJECT_NAME="koha-alpine-isolation-test"
TEST_ENV_FILE="$(mktemp)"
trap 'rm -f "${TEST_ENV_FILE}"' EXIT
printf 'KOHA_COMPOSE_ISOLATION_SENTINEL=from-test-env\n' >"${TEST_ENV_FILE}"

PASS=0
FAIL=0
_N=0

ok() {
    _N=$((_N + 1))
    echo "ok ${_N} - $1"
    PASS=$((PASS + 1))
}

not_ok() {
    _N=$((_N + 1))
    echo "not ok ${_N} - $1"
    FAIL=$((FAIL + 1))
}

echo "TAP version 14"
echo "# Compose isolation checks; no containers are created"

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
    echo "# SKIP Docker Compose is unavailable"
    exit 0
fi

CONFIG="$(
    env \
        SYNC_REPO="${ROOT_DIR}/koha" \
        KOHA_CONTAINER_ENV_FILE="${TEST_ENV_FILE}" \
        KOHA_INSTANCE=kohadev \
        KOHA_DOMAIN=.example.invalid \
        KOHA_INTRANET_SUFFIX=-intra \
        KOHA_INTRANET_PREFIX= \
        KOHA_OPAC_PREFIX= \
        KOHA_OPAC_SUFFIX= \
        MANA_URL=https://mana-kb.koha-community.org \
        LOCAL_USER_ID=1000 \
        docker compose \
            --project-name "${PROJECT_NAME}" \
            --env-file /dev/null \
            --file "${COMPOSE_FILE}" \
            config --format json 2>&1
)" || {
    echo "not ok 1 - Compose renders an isolated project"
    echo "${CONFIG}"
    exit 1
}

if grep -Fq "\"${PROJECT_NAME}_koha-db-data\"" <<<"${CONFIG}" &&
    grep -Fq "\"${PROJECT_NAME}_koha-rabbitmq-data\"" <<<"${CONFIG}"; then
    ok "named data volumes are scoped to the Compose project"
else
    not_ok "named data volumes are scoped to the Compose project"
fi

if ! grep -Fq '"container_name":' <<<"${CONFIG}"; then
    ok "services use Compose-generated container names"
else
    not_ok "services use Compose-generated container names"
fi

if grep -Fq '"KOHA_COMPOSE_ISOLATION_SENTINEL": "from-test-env"' <<<"${CONFIG}"; then
    ok "container env file can be overridden without editing env/.env"
else
    not_ok "container env file can be overridden without editing env/.env"
fi

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}"
[[ ${FAIL} -eq 0 ]]
