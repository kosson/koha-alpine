#!/usr/bin/env bash
# tests/test_authority_groupby_sqlmode_integration.sh
#
# Integration guard for Koha authority-type GROUP BY behavior under SQL modes.
# This test does not modify Koha source code.
#
# Exit code: 0 = pass/skip, 1 = fail, 2 = invalid explicitly selected prerequisites.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/docker-compose-alpinekoha.yml"
ENV_FILE="${KOHA_TEST_ENV_FILE:-}"
TEST_PROJECT="${KOHA_TEST_PROJECT:-}"
COMPOSE_OVERRIDE="${KOHA_TEST_COMPOSE_OVERRIDE:-}"

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
echo "# Authority GROUP BY / SQL mode integration guard"
echo ""

if ! command -v docker >/dev/null 2>&1; then
  skip "authority SQL mode integration prerequisites" "docker not found"
  echo "1..${_N}"
  exit 0
fi

if [[ -z "${TEST_PROJECT}" || -z "${ENV_FILE}" ]]; then
  skip "authority SQL mode integration prerequisites" "set KOHA_TEST_PROJECT and KOHA_TEST_ENV_FILE for an isolated running stack"
  echo "1..${_N}"
  exit 0
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

DB_CONTAINER="$(compose ps -q db 2>/dev/null || true)"
if [[ -z "${DB_CONTAINER}" ]] || [[ "$(docker inspect --format '{{.State.Running}}' "${DB_CONTAINER}" 2>/dev/null || true)" != "true" ]]; then
  skip "authority SQL mode integration prerequisites" "database is not running in project ${TEST_PROJECT}; this test never starts services"
  echo "1..${_N}"
  exit 0
fi

KOHA_INSTANCE="$(grep -E '^KOHA_INSTANCE=' "${ENV_FILE}" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'" || true)"
KOHA_INSTANCE="${KOHA_INSTANCE:-kohadev}"
DB_NAME="koha_${KOHA_INSTANCE}"
if [[ ! "${KOHA_INSTANCE}" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "Bail out! KOHA_INSTANCE in selected test env file is invalid"
  exit 2
fi

DB_PASS="$(grep -E '^KOHA_DB_ROOT_PASSWORD=' "${ENV_FILE}" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")"
if [[ -z "${DB_PASS}" ]]; then
  echo "Bail out! KOHA_DB_ROOT_PASSWORD is empty in selected test env file"
  exit 2
fi
ok "KOHA_DB_ROOT_PASSWORD is set"
ok "Database is running in the selected isolated project"

QUERY="select count(*),auth_tag_structure.authtypecode,authtypetext from auth_tag_structure,auth_types where auth_types.authtypecode=auth_tag_structure.authtypecode group by auth_tag_structure.authtypecode"
STRICT_MODE="ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION"
NON_STRICT_MODE="IGNORE_SPACE,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION"

required_tables=$(docker exec -e "MYSQL_PWD=${DB_PASS}" "${DB_CONTAINER}" \
  mysql -uroot -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name IN ('auth_tag_structure','auth_types');" \
  2>/dev/null || echo 0)

if [[ "${required_tables:-0}" -lt 2 ]]; then
  skip "authority tables are populated" "${DB_NAME} is not fully installed yet"
  skip "Legacy authority query should fail under ONLY_FULL_GROUP_BY" "authority tables missing"
  skip "Legacy authority query succeeds under non-strict app mode" "authority tables missing"
  skip "koha-conf template strict_sql_modes guard" "authority tables missing"
  skip "live koha instance config check" "authority tables missing"
  echo ""
  echo "1..${_N}"
  echo "# Skipped: Koha schema is not fully populated"
  exit 0
fi
ok "authority tables are populated"

# 1) Strict mode must fail with this legacy query shape.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
if docker exec -e "MYSQL_PWD=${DB_PASS}" "${DB_CONTAINER}" \
  mysql -uroot "${DB_NAME}" -Nse "SET SESSION sql_mode='${STRICT_MODE}'; ${QUERY};" \
  >"${TMP_DIR}/strict.out" 2>"${TMP_DIR}/strict.err"; then
  not_ok "Legacy authority query should fail under ONLY_FULL_GROUP_BY"
else
  if grep -q "isn't in GROUP BY" "${TMP_DIR}/strict.err"; then
    ok "Legacy authority query fails under ONLY_FULL_GROUP_BY (expected)"
  else
    not_ok "Strict mode failed, but not with expected GROUP BY diagnostic"
  fi
fi

# 2) Non-strict mode must pass without source modifications.
if docker exec -e "MYSQL_PWD=${DB_PASS}" "${DB_CONTAINER}" \
  mysql -uroot "${DB_NAME}" -Nse "SET SESSION sql_mode='${NON_STRICT_MODE}'; ${QUERY};" \
  >"${TMP_DIR}/nonstrict.out" 2>"${TMP_DIR}/nonstrict.err"; then
  ok "Legacy authority query succeeds under non-strict app mode"
else
  not_ok "Legacy authority query should succeed under non-strict app mode"
fi

# 3) Stack template should keep strict_sql_modes disabled to avoid runtime regression.
if grep -q '<strict_sql_modes>0</strict_sql_modes>' "${REPO_ROOT}/files-alpine/templates/koha-conf-site.xml.in"; then
  ok "koha-conf template has strict_sql_modes disabled"
else
  not_ok "koha-conf template should set strict_sql_modes to 0"
fi

# 4) If koha container is running, verify live instance config too.
KOHA_CONTAINER="$(compose ps -q koha 2>/dev/null || true)"
if [[ -n "${KOHA_CONTAINER}" ]] && [[ "$(docker inspect --format '{{.State.Running}}' "${KOHA_CONTAINER}" 2>/dev/null || true)" == "true" ]]; then
  live_conf="/etc/koha/sites/${KOHA_INSTANCE}/koha-conf.xml"
  max_wait=180
  elapsed=0
  while (( elapsed < max_wait )); do
    if docker exec "${KOHA_CONTAINER}" sh -lc "test -f '${live_conf}'" >/dev/null 2>&1; then
      break
    fi
    sleep 3
    elapsed=$(( elapsed + 3 ))
  done

  if docker exec "${KOHA_CONTAINER}" sh -lc "test -f '${live_conf}'" >/dev/null 2>&1; then
    if docker exec "${KOHA_CONTAINER}" sh -lc "grep -q '<strict_sql_modes>0</strict_sql_modes>' '${live_conf}'"; then
      ok "live koha instance config has strict_sql_modes disabled"
    else
      not_ok "live koha instance config should set strict_sql_modes to 0"
    fi
  else
    skip "live koha instance config check" "koha-conf.xml not generated yet after ${max_wait}s"
  fi
else
  skip "live koha instance config check" "koha container is not running"
fi

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}"
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
