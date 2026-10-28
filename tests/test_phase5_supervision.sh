#!/usr/bin/env bash
# tests/test_phase5_supervision.sh
#
# Static and runtime guardrail tests for Phase 5: OpenRC Service Supervision
# and Alpine crond integration.
#
# TAP output format (Test Anything Protocol).
# Exit 0 = all tests passed (skips are acceptable).
# Exit 1 = at least one test failed.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PASS=0
FAIL=0
SKIP=0
TEST_NUM=0

ok() {
    TEST_NUM=$((TEST_NUM + 1))
    echo "ok ${TEST_NUM} - $1"
    PASS=$((PASS + 1))
}

not_ok() {
    TEST_NUM=$((TEST_NUM + 1))
    echo "not ok ${TEST_NUM} - $1"
    FAIL=$((FAIL + 1))
}

skip() {
    TEST_NUM=$((TEST_NUM + 1))
    echo "ok ${TEST_NUM} - $1 # SKIP $2"
    SKIP=$((SKIP + 1))
}

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        ok "$desc"
    else
        not_ok "$desc"
    fi
}

echo "TAP version 14"
echo "# Phase 5 — OpenRC supervision and crond integration"

# ─── Static: OpenRC init scripts ──────────────────────────────────────────────
echo ""
echo "# --- Static: OpenRC init scripts ---"

check "files-alpine/openrc/koha-plack exists"   test -f files-alpine/openrc/koha-plack
check "files-alpine/openrc/koha-worker exists"  test -f files-alpine/openrc/koha-worker
check "files-alpine/openrc/apache2 exists"      test -f files-alpine/openrc/apache2

check "koha-plack openrc script starts with #!/sbin/openrc-run" \
    grep -q '^#!/sbin/openrc-run' files-alpine/openrc/koha-plack
check "koha-worker openrc script starts with #!/sbin/openrc-run" \
    grep -q '^#!/sbin/openrc-run' files-alpine/openrc/koha-worker
check "apache2 openrc script starts with #!/sbin/openrc-run" \
    grep -q '^#!/sbin/openrc-run' files-alpine/openrc/apache2

check "koha-plack openrc has start() function" \
    grep -q '^start()' files-alpine/openrc/koha-plack
check "koha-worker openrc has start() function" \
    grep -q '^start()' files-alpine/openrc/koha-worker
check "apache2 openrc has start() function" \
    grep -q '^start()' files-alpine/openrc/apache2

check "koha-plack openrc delegates to /usr/sbin/koha-plack" \
    grep -q '/usr/sbin/koha-plack' files-alpine/openrc/koha-plack
check "koha-worker openrc delegates to /usr/sbin/koha-worker" \
    grep -q '/usr/sbin/koha-worker' files-alpine/openrc/koha-worker
check "apache2 openrc delegates to /usr/sbin/httpd" \
    grep -q '/usr/sbin/httpd' files-alpine/openrc/apache2

# ─── Static: Dockerfile installs OpenRC and cron ──────────────────────────────
echo ""
echo "# --- Static: Dockerfile installation ---"

check "Dockerfile copies koha-plack openrc script" \
    grep -q 'files-alpine/openrc/koha-plack' Dockerfile-Alpine
check "Dockerfile copies koha-worker openrc script" \
    grep -q 'files-alpine/openrc/koha-worker' Dockerfile-Alpine
check "Dockerfile copies apache2 openrc script" \
    grep -q 'files-alpine/openrc/apache2' Dockerfile-Alpine

check "Dockerfile copies koha-hourly cron script" \
    grep -q 'files-alpine/cron/koha-hourly' Dockerfile-Alpine
check "Dockerfile copies koha-daily cron script" \
    grep -q 'files-alpine/cron/koha-daily' Dockerfile-Alpine
check "Dockerfile copies koha-monthly cron script" \
    grep -q 'files-alpine/cron/koha-monthly' Dockerfile-Alpine
if grep -q 'COPY files-alpine/ /build/files-alpine/' Dockerfile-Alpine; then
    not_ok "runtime image does not copy the full development helper tree"
else
    ok "runtime image does not copy the full development helper tree"
fi

check "Dockerfile ensures run-parts entries in /etc/crontabs/root" \
    grep -q 'run-parts' Dockerfile-Alpine
check "runtime installs xmlstarlet for koha-shell instance config detection" \
    grep -q 'apk add --no-cache xmlstarlet' Dockerfile-Alpine
check "runtime adds Apache to the Koha shared group" \
    grep -q 'addgroup apache kohadev-koha' Dockerfile-Alpine
check "Plack uses a restrictive umask for shared runtime files" \
    grep -q 'umask 0007' files-alpine/scripts/koha-plack
check "Plack socket permissions are group-scoped, not world-writable" \
    grep -q 'chmod 0660 "$SOCKET"' files-alpine/scripts/koha-plack
check "required Plack startup failures are reported" \
    grep -q 'ERROR: koha-plack failed to start' files-alpine/lib/run-sh-alpine.sh
check "required worker startup failures are reported" \
    grep -q 'ERROR: koha-worker failed to start' files-alpine/lib/run-sh-alpine.sh
check "required Apache startup failures are reported" \
    grep -q 'ERROR: httpd failed to start' files-alpine/lib/run-sh-alpine.sh
check "required crond startup failures are reported" \
    grep -q 'ERROR: failed to start crond' files-alpine/lib/run-sh-alpine.sh
check "failed watchdog restart attempts are reported" \
    grep -q 'ERROR: koha-worker restart attempt failed' files-alpine/lib/run-sh-alpine.sh
check "MySQL credential files are restricted to root" \
    grep -q 'chmod 0600 /etc/mysql/koha-common.cnf /etc/mysql/debian.cnf' files-alpine/lib/run-sh-alpine.sh
check "MySQL instance credential file uses configured host and password" \
    grep -qF '"${DB_HOST}" "${DB_USER}" "${DB_PASS}"' files-alpine/lib/run-sh-alpine.sh

# ─── Static: Cron scripts ─────────────────────────────────────────────────────
echo ""
echo "# --- Static: Cron scripts ---"

check "files-alpine/cron/koha-hourly exists"  test -f files-alpine/cron/koha-hourly
check "files-alpine/cron/koha-daily exists"   test -f files-alpine/cron/koha-daily
check "files-alpine/cron/koha-monthly exists" test -f files-alpine/cron/koha-monthly

check "koha-hourly has KOHA_CONF guard" \
    grep -q 'KOHA_CONF' files-alpine/cron/koha-hourly
check "koha-daily has KOHA_CONF guard" \
    grep -q 'KOHA_CONF' files-alpine/cron/koha-daily
check "koha-monthly has KOHA_CONF guard" \
    grep -q 'KOHA_CONF' files-alpine/cron/koha-monthly

# ─── Static: run.sh and run-sh-alpine.sh ──────────────────────────────────────
echo ""
echo "# --- Static: run.sh and helper library ---"

check "run-sh-alpine.sh defines start_crond function" \
    grep -q 'start_crond()' files-alpine/lib/run-sh-alpine.sh
check "run-sh-alpine.sh defines run_service_watchdog function" \
    grep -q 'run_service_watchdog()' files-alpine/lib/run-sh-alpine.sh

check "run.sh calls start_crond" \
    grep -q 'start_crond' files-alpine/run.sh
check "run.sh calls run_service_watchdog" \
    grep -q 'run_service_watchdog' files-alpine/run.sh

TEST_NUM=$((TEST_NUM + 1))
if grep -q 'sleep infinity' files-alpine/run.sh; then
    echo "not ok ${TEST_NUM} - run.sh no longer uses sleep infinity as the blocking loop"
    FAIL=$((FAIL + 1))
else
    echo "ok ${TEST_NUM} - run.sh no longer uses sleep infinity as the blocking loop"
    PASS=$((PASS + 1))
fi

check "run_service_watchdog handles SIGTERM trap" \
    grep -q 'TERM INT' files-alpine/lib/run-sh-alpine.sh
check "run_service_watchdog monitors koha-plack status" \
    grep -q 'koha-plack.*--status\|koha-plack --status' files-alpine/lib/run-sh-alpine.sh
check "run_service_watchdog monitors koha-worker status" \
    grep -q 'koha-worker.*--status\|koha-worker --status' files-alpine/lib/run-sh-alpine.sh
check "run_service_watchdog restarts koha-plack on failure" \
    grep -q 'koha-plack.*--start\|koha-plack --start' files-alpine/lib/run-sh-alpine.sh
check "run_service_watchdog restarts koha-worker on failure" \
    grep -q 'koha-worker.*--start\|koha-worker --start' files-alpine/lib/run-sh-alpine.sh

# ─── Runtime checks (require a running container) ─────────────────────────────
echo ""
echo "# --- Runtime checks ---"

KOHA_CONTAINER="${KOHA_CONTAINER:-}"
if [[ -z "${KOHA_CONTAINER}" ]]; then
    skip "Phase 5 runtime checks" "set KOHA_CONTAINER to an explicitly selected test container"
elif ! docker inspect "${KOHA_CONTAINER}" >/dev/null 2>&1; then
    skip "crond process is running in container"       "Container '${KOHA_CONTAINER}' is not running"
    skip "/etc/periodic/hourly/koha-hourly installed"  "Container '${KOHA_CONTAINER}' is not running"
    skip "/etc/periodic/daily/koha-daily installed"    "Container '${KOHA_CONTAINER}' is not running"
    skip "/etc/init.d/koha-plack installed in image"   "Container '${KOHA_CONTAINER}' is not running"
    skip "/etc/init.d/koha-worker installed in image"  "Container '${KOHA_CONTAINER}' is not running"
    skip "watchdog process is alive in container"      "Container '${KOHA_CONTAINER}' is not running"
else
    if docker exec "${KOHA_CONTAINER}" pgrep -x crond >/dev/null 2>&1; then
        ok "crond process is running in container"
    else
        not_ok "crond process is running in container"
    fi

    if docker exec "${KOHA_CONTAINER}" test -f /etc/periodic/hourly/koha-hourly >/dev/null 2>&1; then
        ok "/etc/periodic/hourly/koha-hourly installed"
    else
        not_ok "/etc/periodic/hourly/koha-hourly installed"
    fi

    if docker exec "${KOHA_CONTAINER}" test -f /etc/periodic/daily/koha-daily >/dev/null 2>&1; then
        ok "/etc/periodic/daily/koha-daily installed"
    else
        not_ok "/etc/periodic/daily/koha-daily installed"
    fi

    if docker exec "${KOHA_CONTAINER}" sh -lc '
        test -f /build/files-alpine/lib/run-sh-alpine.sh &&
        test -f /build/files-alpine/templates/koha-vhost.conf.in
    ' >/dev/null 2>&1; then
        ok "runtime startup helper and vhost template are present"
    else
        not_ok "runtime startup helper and vhost template are present"
    fi

    if docker exec "${KOHA_CONTAINER}" sh -lc '
        test ! -e /build/files-alpine/mariadb-ssl &&
        test ! -e /build/files-alpine/misc4dev
    ' >/dev/null 2>&1; then
        ok "runtime image excludes development TLS keys and misc4dev helper tree"
    else
        not_ok "runtime image excludes development TLS keys and misc4dev helper tree"
    fi

    if docker exec "${KOHA_CONTAINER}" test -f /etc/init.d/koha-plack >/dev/null 2>&1; then
        ok "/etc/init.d/koha-plack installed in image"
    else
        not_ok "/etc/init.d/koha-plack installed in image"
    fi

    if docker exec "${KOHA_CONTAINER}" test -f /etc/init.d/koha-worker >/dev/null 2>&1; then
        ok "/etc/init.d/koha-worker installed in image"
    else
        not_ok "/etc/init.d/koha-worker installed in image"
    fi

    if docker exec "${KOHA_CONTAINER}" koha-shell --help >/dev/null 2>&1; then
        ok "koha-shell command is executable"
    else
        not_ok "koha-shell command is executable"
    fi

    koha_instance="$(docker exec "${KOHA_CONTAINER}" sh -lc 'printf "%s" "${KOHA_INSTANCE:-kohadev}"' 2>/dev/null)"
    if docker exec "${KOHA_CONTAINER}" sh -lc 'test -d /usr/share/koha/lib' >/dev/null 2>&1 \
        && docker exec "${KOHA_CONTAINER}" koha-shell -c 'printf "%s\n" "$PERL5LIB"' "${koha_instance}" 2>/dev/null | grep -Fxq '/usr/share/koha/lib'; then
        ok "koha-shell loads the packaged PERL5LIB for this non-git instance"
    else
        not_ok "koha-shell loads the packaged PERL5LIB for this non-git instance"
    fi

    if docker exec "${KOHA_CONTAINER}" sh -lc 'grep -a -q "/usr/local/bin/run.sh" /proc/1/cmdline' >/dev/null 2>&1; then
        ok "PID 1 is the live Alpine run.sh watchdog"
    else
        not_ok "PID 1 is the live Alpine run.sh watchdog"
    fi

    if docker logs "${KOHA_CONTAINER}" 2>&1 | grep -q '\[watchdog\] Service watchdog started'; then
        ok "watchdog startup is recorded in container logs"
    else
        not_ok "watchdog startup is recorded in container logs"
    fi

    if docker exec "${KOHA_CONTAINER}" sh -lc 'id apache | grep -qw kohadev-koha'; then
        ok "Apache has membership in the Koha runtime group"
    else
        not_ok "Apache has membership in the Koha runtime group"
    fi

    socket_permissions="$(docker exec "${KOHA_CONTAINER}" stat -c '%a:%G' "/var/run/koha/${koha_instance}/plack.sock" 2>/dev/null || true)"
    if [[ "${socket_permissions}" == "660:kohadev-koha" ]]; then
        ok "Plack socket is group-writable without world access"
    else
        not_ok "Plack socket is group-writable without world access (${socket_permissions:-missing})"
    fi

    if docker exec "${KOHA_CONTAINER}" sh -lc '
        find "/etc/koha/sites/${KOHASITE:-kohadev}" \
             "/var/cache/koha/${KOHASITE:-kohadev}" \
             "/var/log/koha/${KOHASITE:-kohadev}" \
             "/var/run/koha/${KOHASITE:-kohadev}" \
             "/var/lib/koha/${KOHASITE:-kohadev}/uploads" \
             "/var/lib/koha/${KOHASITE:-kohadev}/tmp" \
             -perm -0002 -print -quit | grep -q .
    '; then
        not_ok "Koha runtime paths are not world-writable"
    else
        ok "Koha runtime paths are not world-writable"
    fi

    if docker exec "${KOHA_CONTAINER}" sh -lc '
        for file in /etc/mysql/koha-common.cnf /etc/mysql/debian.cnf \
                    "/etc/mysql/koha_${KOHASITE:-kohadev}.cnf"; do
            test "$(stat -c "%a:%u" "$file")" = "600:0" || exit 1
        done
    '; then
        ok "generated MySQL credential files are root-only"
    else
        not_ok "generated MySQL credential files are root-only"
    fi

    health_status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "${KOHA_CONTAINER}")"
    if [[ "${health_status}" == "healthy" ]]; then
        ok "container healthcheck reports Plack and HTTP readiness"
    else
        not_ok "container healthcheck reports Plack and HTTP readiness (${health_status:-missing})"
    fi

    capability_config="$(docker inspect --format '{{json .HostConfig.CapDrop}}|{{json .HostConfig.CapAdd}}' "${KOHA_CONTAINER}")"
    expected_capabilities='["ALL"]|["CAP_CHOWN","CAP_DAC_OVERRIDE","CAP_FOWNER","CAP_KILL","CAP_NET_BIND_SERVICE","CAP_SETGID","CAP_SETUID"]'
    if [[ "${capability_config}" == "${expected_capabilities}" ]]; then
        ok "container drops all capabilities and uses the reviewed allowlist"
    else
        not_ok "container drops all capabilities and uses the reviewed allowlist"
    fi
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "1..${TEST_NUM}"
echo "# Passed: ${PASS}  Failed: ${FAIL}  Skipped: ${SKIP}"

[ "${FAIL}" -eq 0 ]
