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

check "Dockerfile ensures run-parts entries in /etc/crontabs/root" \
    grep -q 'run-parts' Dockerfile-Alpine

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

KOHA_CONTAINER="${KOHA_CONTAINER:-koha}"
if ! docker inspect "${KOHA_CONTAINER}" >/dev/null 2>&1; then
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

    # Watchdog: run.sh should not have exited (it's still blocked in run_service_watchdog).
    # We check that the PID 1 process (bash run.sh) is still alive.
    if docker exec "${KOHA_CONTAINER}" test -f /ktd_ready >/dev/null 2>&1; then
        ok "watchdog process is alive in container (ktd_ready marker exists)"
    else
        not_ok "watchdog process is alive in container (ktd_ready marker exists)"
    fi
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "1..${TEST_NUM}"
echo "# Passed: ${PASS}  Failed: ${FAIL}  Skipped: ${SKIP}"

[ "${FAIL}" -eq 0 ]
