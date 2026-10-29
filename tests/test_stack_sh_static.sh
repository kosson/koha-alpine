#!/usr/bin/env bash
# tests/test_stack_sh_static.sh
#
# Static checks for stack-alpine.sh backup/restore support.
# No Docker required.

set -euo pipefail

STACK_SH="$(cd "$(dirname "$0")/.." && pwd)/stack-alpine.sh"

PASS=0; FAIL=0; _N=0
ok() {
    _N=$(( _N + 1 ))
    echo "ok ${_N} - $1"
    PASS=$(( PASS + 1 ))
}
not_ok() {
    _N=$(( _N + 1 ))
    echo "not ok ${_N} - $1"
    FAIL=$(( FAIL + 1 ))
}
assert_contains() {
    local desc="$1"; local pattern="$2"
    if grep -qF -- "${pattern}" "${STACK_SH}"; then
        ok "${desc}"
    else
        not_ok "${desc} (pattern not found: ${pattern})"
    fi
}
assert_not_contains() {
    local desc="$1"; local pattern="$2"
    if grep -qF -- "${pattern}" "${STACK_SH}"; then
        not_ok "${desc} (unexpected pattern found: ${pattern})"
    else
        ok "${desc}"
    fi
}

echo "TAP version 14"
echo "# Static checks on stack-alpine.sh backup/restore support"
echo ""

assert_contains "help mentions backup command" "backup      Create a tar.gz backup bundle for env files + MariaDB data"
assert_contains "help mentions restore command" "restore     Restore env files + MariaDB data from a backup bundle"
assert_contains "dispatcher handles backup" "backup)"
assert_contains "dispatcher handles restore" "restore)"
assert_contains "backup root is defined" 'BACKUP_ROOT="${SCRIPT_DIR}/backups"'
assert_contains "backup command supports --output" "--output)"
assert_contains "restore command supports --input" "--input)"
assert_contains "backup uses mysqldump" 'mysqldump -uroot -p"${KOHA_DB_ROOT_PASSWORD}"'
assert_contains "restore imports the dump" 'gzip -dc "${stage_dir}/database/${DB_NAME}.sql.gz"'
assert_contains "restore starts Traefik" "start_traefik"
assert_contains "restore starts Koha" "start_koha"
assert_contains "stack script probes for populated DB before no-fresh-db shortcut" 'koha_db_has_systempreferences()'
assert_contains "stack script falls back when no-fresh-db hits an empty DB" 'falling back to fresh bootstrap'
assert_contains "stack script checks for bootstrap completion marker" 'koha_bootstrap_marker_present()'
assert_contains "bootstrap marker is cleared on reset" 'rm -f "${BOOTSTRAP_MARKER}"'
assert_contains "production project name can be kept stable across Koha releases" 'KOHA_COMPOSE_PROJECT="${KOHA_PROD_PROJECT}"'
assert_contains "stable production project names are validated" 'KOHA_PROD_PROJECT}" =~ ^[a-z0-9][a-z0-9_-]*$'
assert_contains "stable production project name reloads from runtime config" 'KOHA_PROD_PROJECT="$(_env_val "${KOHA_ENV_FILE}" KOHA_PROD_PROJECT "${KOHA_PROD_PROJECT}")"'
assert_contains "version-specific production project remains the default" 'KOHA_COMPOSE_PROJECT="koha-prod-${_slug}"'
assert_contains "main Koha env file can be selected outside the repository" 'KOHA_ENV_FILE="${KOHA_ENV_FILE:-${SCRIPT_DIR}/env/.env}"'
assert_contains "container env file defaults to selected host env file" 'KOHA_CONTAINER_ENV_FILE="${KOHA_CONTAINER_ENV_FILE:-$(_env_val "${KOHA_ENV_FILE}" KOHA_CONTAINER_ENV_FILE "${KOHA_ENV_FILE}")}"'
assert_not_contains "startup does not rewrite tracked SYNC_REPO configuration" 'perl -pi -e "s|^SYNC_REPO='

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}"
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1