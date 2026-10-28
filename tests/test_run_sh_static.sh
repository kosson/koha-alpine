#!/usr/bin/env bash
# Static checks for the Alpine entrypoint's database bootstrap flow.

set -euo pipefail

RUN_SH="$(cd "$(dirname "$0")/.." && pwd)/files-alpine/run.sh"

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

assert_contains() {
    local desc="$1"
    local pattern="$2"
    if grep -qF -- "${pattern}" "${RUN_SH}"; then
        ok "${desc}"
    else
        not_ok "${desc} (pattern not found: ${pattern})"
    fi
}

assert_before() {
    local desc="$1"
    local before="$2"
    local after="$3"
    local before_line
    local after_line

    before_line="$(grep -nF -- "${before}" "${RUN_SH}" | head -1 | cut -d: -f1 || true)"
    after_line="$(grep -nF -- "${after}" "${RUN_SH}" | head -1 | cut -d: -f1 || true)"
    if [[ -n "${before_line}" && -n "${after_line}" ]] && (( before_line < after_line )); then
        ok "${desc}"
    else
        not_ok "${desc}"
    fi
}

echo "TAP version 14"
echo "# Static checks for Alpine database bootstrap"
echo ""

assert_contains "entrypoint retries database readiness" 'for i in $(seq 1 60); do'
assert_contains "readiness probe runs an authenticated SQL query" 'mysql -h ${DB_HOST} -u ${DB_USER} -e "SELECT 1"'
assert_contains "bootstrap detects a missing systempreferences table" 'SELECT 1 FROM systempreferences LIMIT 1'
assert_contains "empty-database branch loads the Koha schema" '< "${KOHADEVBOX}/installer/data/mysql/kohastructure.sql"'
assert_contains "empty-database branch loads mandatory SQL data" '${KOHADEVBOX}/installer/data/mysql/mandatory/*.sql'
assert_contains "existing schema is upgraded with updatedatabase.pl" 'perl -Ilib installer/data/mysql/updatedatabase.pl'
assert_contains "frontend asset pipeline propagates build failures" 'set -o pipefail'
assert_contains "entrypoint builds missing frontend assets" 'yarn build 2>&1 | tail -40'
assert_before "instance data directories are owned before admin creation" \
    'chown -R kohadev-koha:kohadev-koha /etc/koha/sites/${KOHASITE}' \
    'if [ -z "$ADMIN_EXISTS" ]; then'
assert_contains "entrypoint fails explicitly when initial admin creation fails" \
    'ERROR: create_superlibrarian.pl failed; refusing to start without the initial admin account'
if grep -qF -- 'yarn build failed; OPAC/staff pages will render without CSS/JS' "${RUN_SH}"; then
    not_ok "frontend asset build failures are not suppressed"
else
    ok "frontend asset build failures are not suppressed"
fi

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}"
[[ ${FAIL} -eq 0 ]]
