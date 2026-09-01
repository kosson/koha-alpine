#!/bin/bash
# Consolidated test harness for the Koha Alpine Apache+Plack stack.
#
# Supersedes test-endpoints.sh's assumptions (pure Apache mod_cgi, no Plack).
# Exercises the actual architecture: Apache (mod_cgi + mod_proxy) on
# 8080/8081 -> koha-plack (Starman over a unix socket) -> debian's CGI-based
# plack.psgi -> real Koha, with mod_cgi as the automatic fallback for any path
# not yet proxied, and a watchdog that restarts koha-plack/koha-worker on crash.
#
# Usage: ./test-plack-stack.sh [--no-recreate] [--no-watchdog-test]
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

COMPOSE_FILE="docker-compose-alpinekoha.yml"
ENV_FILE="env/.env"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
KOHA_INSTANCE=$(grep -E '^KOHA_INSTANCE=' "${PROJECT_DIR}/${ENV_FILE}" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'" || true)
KOHA_INSTANCE="${KOHA_INSTANCE:-kohadev}"

DO_RECREATE=yes
DO_WATCHDOG_TEST=yes
for arg in "$@"; do
    case "$arg" in
        --no-recreate) DO_RECREATE=no ;;
        --no-watchdog-test) DO_WATCHDOG_TEST=no ;;
    esac
done

PASS=0
FAIL=0

compose() {
    docker compose -f "${PROJECT_DIR}/${COMPOSE_FILE}" --env-file "${PROJECT_DIR}/${ENV_FILE}" --project-directory "${PROJECT_DIR}" "$@"
}

kexec() {
    compose exec -T koha sh -c "$1"
}

pass() { echo -e "${GREEN}✓ $1${NC}"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}✗ $1${NC}"; FAIL=$((FAIL+1)); }
section() { echo; echo -e "${BLUE}== $1 ==${NC}"; }

section "0. Image / container freshness"
if [ "$DO_RECREATE" = "yes" ]; then
    echo "Recreating koha container from current image (guards against the stale-image drift bug: a running container can silently keep executing an old baked-in run.sh that no longer matches the source tree)..."
    compose up -d --force-recreate koha >/tmp/plack-stack-recreate.log 2>&1
    sleep 25
fi

LIVE_ENTRYPOINT=$(docker inspect koha-alpine --format '{{json .Config.Entrypoint}}' 2>/dev/null || echo "")
if echo "$LIVE_ENTRYPOINT" | grep -q "run.sh"; then
    pass "Container Entrypoint references run.sh ($LIVE_ENTRYPOINT)"
else
    fail "Unexpected container Entrypoint: $LIVE_ENTRYPOINT"
fi

LIVE_MD5=$(kexec "md5sum /usr/local/bin/run.sh 2>/dev/null | cut -d' ' -f1")
HOST_MD5=$(md5sum "${PROJECT_DIR}/files-alpine/run.sh" | cut -d' ' -f1)
if [ "$LIVE_MD5" = "$HOST_MD5" ]; then
    pass "run.sh inside container matches files-alpine/run.sh on host (no stale-image drift)"
else
    fail "run.sh MISMATCH: container has $LIVE_MD5, host has $HOST_MD5 -- rebuild the image (docker compose build koha)"
fi

section "1. Container health"
if compose ps koha 2>/dev/null | grep -qi "running\|Up"; then
    pass "koha container is running"
else
    fail "koha container is not running"
    echo "Recent logs:"; compose logs koha --tail 40
    exit 1
fi

section "2. Apache configuration"
if kexec "/usr/sbin/httpd -t 2>&1" | grep -q "Syntax OK"; then
    pass "Apache config syntax OK"
else
    fail "Apache config syntax error"
    kexec "/usr/sbin/httpd -t 2>&1"
fi

APACHE_MODULES=$(kexec "/usr/sbin/httpd -M 2>&1")
for mod in cgi_module proxy_module proxy_http_module rewrite_module; do
    if echo "$APACHE_MODULES" | grep -q "$mod"; then
        pass "Apache module loaded: $mod"
    else
        fail "Apache module NOT loaded: $mod (on Alpine, mod_proxy requires the apache2-proxy apk package, not just apache2)"
    fi
done

if kexec "test -L /etc/apache2/sites-enabled/${KOHA_INSTANCE}.conf"; then
    pass "Vhost is symlinked into sites-enabled"
else
    fail "Vhost symlink missing in sites-enabled (rendered vhost will never load)"
fi

section "3. Plack (koha-plack / Starman)"
if kexec "PATH=/usr/sbin:\$PATH koha-plack --status ${KOHA_INSTANCE}" | grep -q "running"; then
    pass "koha-plack reports running"
else
    fail "koha-plack is not running"
fi

SOCKET_PATH="/var/run/koha/${KOHA_INSTANCE}/plack.sock"
SOCKET_PERMS=$(kexec "stat -c '%a' ${SOCKET_PATH} 2>/dev/null")
if [ "$SOCKET_PERMS" = "777" ]; then
    pass "Plack unix socket is world read/write ($SOCKET_PATH, mode $SOCKET_PERMS)"
else
    fail "Plack unix socket has restrictive permissions (mode '$SOCKET_PERMS'); Apache runs as a different user and will get 'Permission denied' (503) connecting to it"
fi

SOCKET_CODE=$(kexec "curl -s -o /dev/null -w '%{http_code}' --unix-socket ${SOCKET_PATH} http://localhost/intranet/mainpage.pl")
if [ "$SOCKET_CODE" = "200" ]; then
    pass "Direct unix-socket request to plack.psgi returns 200"
else
    fail "Direct unix-socket request to plack.psgi returned $SOCKET_CODE (expected 200)"
fi

section "4. HTTP endpoints (through Apache -> Plack proxy)"
check_html_endpoint() {
    local label="$1" url="$2" min_size="$3"
    local out="/tmp/plack-stack-$$.html"
    local code size
    code=$(kexec "curl -s -o /tmp/plack-stack-check.html -w '%{http_code}' '$url'")
    size=$(kexec "wc -c < /tmp/plack-stack-check.html")
    if [ "$code" != "200" ]; then
        fail "$label: HTTP $code (expected 200) [$url]"
        return
    fi
    if [ "${size:-0}" -lt "$min_size" ]; then
        fail "$label: response too small (${size} bytes, expected >= ${min_size}) [$url]"
        return
    fi
    if kexec "grep -q '#!/usr/bin/perl\|use Modern::Perl' /tmp/plack-stack-check.html"; then
        fail "$label: response leaks raw Perl source (CGI execution bug) [$url]"
        return
    fi
    if kexec "grep -qi 'It works!.*Apache' /tmp/plack-stack-check.html"; then
        fail "$label: Apache default page served instead of the Koha vhost (rendered vhost not active) [$url]"
        return
    fi
    pass "$label: HTTP 200, ${size} bytes, real HTML, no source leakage [$url]"
}

check_html_endpoint "Staff root /"          "http://localhost:8081/"           5000
check_html_endpoint "Staff /index.html"     "http://localhost:8081/index.html" 5000
check_html_endpoint "OPAC root /"           "http://localhost:8080/"           5000
check_html_endpoint "OPAC /index.html"      "http://localhost:8080/index.html" 5000

API_CODE=$(kexec "curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/api/v1/app.pl/api/v1/patrons")
if [ "$API_CODE" = "401" ] || [ "$API_CODE" = "200" ]; then
    pass "REST API endpoint reachable through proxy (HTTP $API_CODE, auth-gated as expected)"
else
    fail "REST API endpoint returned unexpected HTTP $API_CODE (expected 401 unauthenticated or 200)"
fi

OPAC_SEARCH_CODE=$(kexec "curl -s -o /dev/null -w '%{http_code}' 'http://localhost:8080/search?q=test'")
if [ "$OPAC_SEARCH_CODE" = "200" ]; then
    pass "OPAC search endpoint reachable through proxy"
else
    fail "OPAC search endpoint returned HTTP $OPAC_SEARCH_CODE (expected 200)"
fi

section "5. Background worker"
# koha-worker's --start falls back to a "dummy up" pid when no
# background_jobs_worker.pl exists for this Koha checkout (known compat mode,
# see files-alpine/scripts/koha-worker). That dummy pid is the transient
# --start invocation itself, which has already exited by the time --status
# checks it, so "not running" here is an accepted, known outcome, not a bug in
# the Plack/Apache stack this harness targets.
if kexec "test -f /kohadevbox/koha/misc/background_jobs_worker.pl -o -f /kohadevbox/koha/bin/background_jobs_worker.pl"; then
    if kexec "PATH=/usr/sbin:\$PATH koha-worker --status ${KOHA_INSTANCE}" | grep -q "running"; then
        pass "koha-worker reports running"
    else
        fail "koha-worker is not running (a real worker script exists for this checkout, so this should be up)"
    fi
else
    echo -e "${YELLOW}! No background_jobs_worker.pl in this Koha checkout; koha-worker runs in compat/no-op mode (known limitation, not a stack failure)${NC}"
fi

section "6. Watchdog crash-recovery"
if [ "$DO_WATCHDOG_TEST" = "yes" ]; then
    PLACK_PID=$(kexec "cat /var/run/koha/${KOHA_INSTANCE}/plack.pid 2>/dev/null")
    if [ -n "$PLACK_PID" ]; then
        echo "Killing koha-plack pid=$PLACK_PID to test watchdog recovery..."
        kexec "kill -9 $PLACK_PID 2>/dev/null || true"
        echo "Waiting 35s for the watchdog (30s poll interval) to notice and restart it..."
        sleep 35
        if kexec "PATH=/usr/sbin:\$PATH koha-plack --status ${KOHA_INSTANCE}" | grep -q "running"; then
            pass "Watchdog restarted koha-plack after a simulated crash"
        else
            fail "Watchdog did NOT restart koha-plack within 35s"
        fi
        RECOVERY_CODE=$(kexec "curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/index.html")
        if [ "$RECOVERY_CODE" = "200" ]; then
            pass "Staff endpoint serves 200 again after watchdog recovery"
        else
            fail "Staff endpoint still broken after watchdog recovery (HTTP $RECOVERY_CODE)"
        fi
    else
        fail "Could not read plack.pid; skipping watchdog test"
    fi
else
    echo "(skipped: --no-watchdog-test)"
fi

section "7. Restart idempotency (regression test for the cardnumber/set-e crash)"
compose up -d --force-recreate koha >/tmp/plack-stack-recreate2.log 2>&1
sleep 25
if compose ps koha 2>/dev/null | grep -qi "running\|Up"; then
    pass "Container survives a second --force-recreate without crashing on startup"
else
    fail "Container failed to come back up after --force-recreate (check: docker compose logs koha)"
fi

section "Summary"
echo -e "Passed: ${GREEN}${PASS}${NC}   Failed: ${RED}${FAIL}${NC}"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
