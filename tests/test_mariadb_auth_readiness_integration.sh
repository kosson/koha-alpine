#!/usr/bin/env bash
# tests/test_mariadb_auth_readiness_integration.sh
#
# Integration test: detects MariaDB readiness race where mysqladmin ping can
# succeed before root auth is actually usable on a fresh volume initialization.
#
# Exit code: 0 = pass/skip, 1 = fail, 2 = invalid explicitly selected prerequisites.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/docker-compose-alpinekoha.yml"
ENV_FILE="${KOHA_TEST_ENV_FILE:-}"
TEST_PROJECT="${KOHA_TEST_PROJECT:-}"
COMPOSE_OVERRIDE="${KOHA_TEST_COMPOSE_OVERRIDE:-}"
MAX_WAIT=${MAX_WAIT:-120}

PASS=0; FAIL=0; _N=0
ok()     { _N=$(( _N + 1 )); echo "ok ${_N} - $1"; PASS=$(( PASS + 1 )); }
not_ok() { _N=$(( _N + 1 )); echo "not ok ${_N} - $1"; FAIL=$(( FAIL + 1 )); }
skip()   { _N=$(( _N + 1 )); echo "ok ${_N} - $1 # SKIP $2"; }

compose() {
  local -a command=(docker compose --project-name "${TEST_PROJECT}" --env-file "${ENV_FILE}" --project-directory "${REPO_ROOT}" -f "${COMPOSE_FILE}")
  if [[ -n "${COMPOSE_OVERRIDE}" ]]; then
    command+=(-f "${COMPOSE_OVERRIDE}")
  fi
  "${command[@]}" "$@"
}

echo "TAP version 14"
echo "# MariaDB auth readiness integration check"
echo ""

if ! command -v docker >/dev/null 2>&1; then
  skip "MariaDB readiness prerequisites" "docker not found"
  echo "1..${_N}"
  exit 0
fi

if [[ -z "${TEST_PROJECT}" || -z "${ENV_FILE}" ]]; then
  skip "MariaDB readiness prerequisites" "set KOHA_TEST_PROJECT and KOHA_TEST_ENV_FILE for an isolated fresh project"
  echo "1..${_N}"
  exit 0
fi

if [[ ! "${TEST_PROJECT}" =~ ^koha-alpine-test-[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
  echo "Bail out! KOHA_TEST_PROJECT must use the unique koha-alpine-test-<suffix> prefix"
  exit 2
fi

if [[ ! -f "${COMPOSE_FILE}" || ! -f "${ENV_FILE}" ]]; then
  echo "Bail out! compose or selected test env file not found"
  exit 2
fi

export KOHA_CONTAINER_ENV_FILE="${ENV_FILE}"
if ! compose config --quiet >/dev/null 2>&1; then
  echo "Bail out! selected test Compose configuration is invalid"
  exit 2
fi

if [[ -n "$(compose ps -q 2>/dev/null || true)" ]]; then
  echo "Bail out! selected test project already has containers; use a new project name"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  skip "MariaDB readiness prerequisites" "python3 is required to verify the generated volume name"
  echo "1..${_N}"
  exit 0
fi

DB_VOLUME="$(compose config --format json | python3 -c 'import json, sys; print(json.load(sys.stdin)["volumes"]["koha-db-data"]["name"])')"
if [[ "${DB_VOLUME}" != "${TEST_PROJECT}_"* ]]; then
  echo "Bail out! DB volume is not scoped to the isolated project: ${DB_VOLUME}"
  exit 2
fi
if docker volume inspect "${DB_VOLUME}" >/dev/null 2>&1; then
  echo "Bail out! fresh-project DB volume already exists: ${DB_VOLUME}; choose a new project name"
  exit 2
fi

DB_PASS="$(grep -E '^KOHA_DB_ROOT_PASSWORD=' "${ENV_FILE}" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")"
if [[ -z "${DB_PASS}" ]]; then
  echo "Bail out! KOHA_DB_ROOT_PASSWORD is empty in selected test env file"
  exit 2
fi
ok "KOHA_DB_ROOT_PASSWORD is set"

compose up -d db >/dev/null
DB_CONTAINER="$(compose ps -q db)"
ok "DB container started with fresh volume"

ping_at=-1
auth_at=-1
elapsed=0
while (( elapsed < MAX_WAIT )); do
  if (( ping_at < 0 )); then
    if docker exec -e "MYSQL_PWD=${DB_PASS}" "${DB_CONTAINER}" mysqladmin ping -uroot --silent >/dev/null 2>&1; then
      ping_at=${elapsed}
    fi
  fi

  if (( auth_at < 0 )); then
    if docker exec -e "MYSQL_PWD=${DB_PASS}" "${DB_CONTAINER}" mysql -uroot -e 'SELECT 1;' >/dev/null 2>&1; then
      auth_at=${elapsed}
    fi
  fi

  if (( ping_at >= 0 && auth_at >= 0 )); then
    break
  fi

  sleep 1
  elapsed=$(( elapsed + 1 ))
done

if (( ping_at < 0 )); then
  not_ok "mysqladmin ping succeeds within ${MAX_WAIT}s"
else
  ok "mysqladmin ping succeeds within ${MAX_WAIT}s"
fi

if (( auth_at < 0 )); then
  not_ok "authenticated SQL query succeeds within ${MAX_WAIT}s"
else
  ok "authenticated SQL query succeeds within ${MAX_WAIT}s"
fi

if (( ping_at >= 0 && auth_at >= 0 )); then
  if (( ping_at < auth_at )); then
    ok "race detected: ping became ready ${auth_at-ping_at}s before auth (source of intermittent ERROR 1045)"
  else
    ok "no race observed in this run (auth readiness not behind ping)"
  fi
fi

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}"
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
