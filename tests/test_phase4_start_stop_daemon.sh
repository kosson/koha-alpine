#!/usr/bin/env bash
# tests/test_phase4_start_stop_daemon.sh
#
# Phase 4 start-stop-daemon compatibility test.
# Static section: no Docker required.
# Runtime section: requires a running koha container (skipped with # SKIP if absent).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOCKERFILE="${ROOT_DIR}/Dockerfile-Alpine"

PASS=0; FAIL=0; SKIP=0; _N=0
ok()      { _N=$((_N+1)); echo "ok ${_N} - $1";           PASS=$((PASS+1)); }
not_ok()  { _N=$((_N+1)); echo "not ok ${_N} - $1";       FAIL=$((FAIL+1)); }
skip()    { _N=$((_N+1)); echo "ok ${_N} - $1 # SKIP $2"; SKIP=$((SKIP+1)); }
assert_contains() {
    local desc="$1" pattern="$2" file="$3"
    grep -qF -- "${pattern}" "${file}" && ok "${desc}" || not_ok "${desc} (pattern not found: ${pattern})"
}

echo "TAP version 14"
echo "# Phase 4 — start-stop-daemon installation and flag compatibility"
echo ""

# ── Static: Dockerfile has busybox-extras ────────────────────────────────────
echo "# --- Static: Dockerfile ---"
assert_contains "Dockerfile adds busybox-extras" "busybox-extras" "${DOCKERFILE}"

# ── Runtime: probe the built image ───────────────────────────────────────────
# Detect a running or available koha-base image to exec into.
KOHA_IMAGE="${KOHA_TEST_IMAGE:-koha-alpine:phase2-koha-base-e2e}"

runtime_available=0
if docker image inspect "${KOHA_IMAGE}" >/dev/null 2>&1; then
    runtime_available=1
fi

echo ""
echo "# --- Runtime: BusyBox start-stop-daemon flag compatibility ---"

if [[ "${runtime_available}" -eq 0 ]]; then
    skip "start-stop-daemon binary exists in image" "No image ${KOHA_IMAGE} available — rebuild first"
    skip "--stop flag accepted" "No image available"
    skip "--start flag accepted" "No image available"
    skip "--pidfile flag accepted" "No image available"
    skip "--user flag accepted (status mode)" "No image available"
    skip "--status flag accepted" "No image available"
    skip "--signal flag accepted" "No image available"
    skip "--retry=QUIT/30/KILL/5 syntax accepted" "No image available"
    skip "--background flag accepted" "No image available"
    skip "--make-pidfile flag accepted" "No image available"
    skip "--chuid flag accepted (or documented absent)" "No image available"
else
    # Helper: run a command inside the image and capture output + exit code
    _probe() {
        docker run --rm --entrypoint /bin/sh "${KOHA_IMAGE}" -c "$1" 2>&1
        return $?
    }
    _probe_rc() {
        docker run --rm --entrypoint /bin/sh "${KOHA_IMAGE}" -c "$1" >/dev/null 2>&1
        return $?
    }

    # 1. Binary present
    if _probe_rc 'command -v start-stop-daemon'; then
        ok "start-stop-daemon binary exists in image"
    else
        not_ok "start-stop-daemon binary exists in image"
    fi

    HELP=$(_probe 'start-stop-daemon --help 2>&1 || true')

    # 2. --stop
    echo "${HELP}" | grep -q '\-\-stop\|-K' \
        && ok "--stop flag accepted" \
        || not_ok "--stop flag accepted (not in --help output)"

    # 3. --start
    echo "${HELP}" | grep -q '\-\-start\|-S' \
        && ok "--start flag accepted" \
        || not_ok "--start flag accepted (not in --help output)"

    # 4. --pidfile
    echo "${HELP}" | grep -q '\-\-pidfile\|-p' \
        && ok "--pidfile flag accepted" \
        || not_ok "--pidfile flag accepted (not in --help output)"

    # 5. --user
    echo "${HELP}" | grep -q '\-\-user\|-u' \
        && ok "--user flag accepted (status mode)" \
        || not_ok "--user flag accepted (not in --help output)"

    # 6. --status — absent in BusyBox; equivalent is --stop --test --pidfile
    # koha-functions.sh is_plack_running / is_z3950_running use --status.
    # Alpine koha-functions.sh override must substitute: --stop --test --pidfile
    if echo "${HELP}" | grep -q '\-\-status\|-T'; then
        ok "--status flag accepted"
    else
        # Verify --test is available as the documented substitute
        if echo "${HELP}" | grep -q '\-\-test\|-t'; then
            ok "--status absent; --stop --test available as substitute [Alpine koha-functions.sh must use --stop --test --pidfile]"
        else
            not_ok "--status and --test both absent — no status-check substitute available"
        fi
    fi

    # 7. --signal
    echo "${HELP}" | grep -q '\-\-signal\|-s' \
        && ok "--signal flag accepted" \
        || not_ok "--signal flag accepted (not in --help output) [used by reload_plack HUP]"

    # 8. --retry with QUIT/N/KILL/M syntax (Debian extension — may be absent in BusyBox)
    # BusyBox may only support --retry N (integer), not signal-name sequences.
    if echo "${HELP}" | grep -q '\-\-retry'; then
        RETRY_OUT=$(_probe 'start-stop-daemon --stop --pidfile /nonexistent.pid --retry=QUIT/1/KILL/1 2>&1 || true')
        if echo "${RETRY_OUT}" | grep -qi 'invalid\|unknown\|unrecognized\|bad'; then
            not_ok "--retry=QUIT/30/KILL/5 syntax accepted [BusyBox may only support integer retry — koha-plack stop needs adaptation]"
        else
            ok "--retry=QUIT/30/KILL/5 syntax accepted"
        fi
    else
        not_ok "--retry flag present [not in --help — koha-plack stop path will fail without adaptation]"
    fi

    # 9. --background
    echo "${HELP}" | grep -q '\-\-background\|-b' \
        && ok "--background flag accepted" \
        || not_ok "--background flag accepted (not in --help) [needed for koha-worker Alpine replacement]"

    # 10. --make-pidfile
    echo "${HELP}" | grep -q '\-\-make-pidfile\|-m' \
        && ok "--make-pidfile flag accepted" \
        || not_ok "--make-pidfile flag accepted (not in --help) [needed for koha-worker Alpine replacement]"

    # 11. --chuid — deprecated in BusyBox in favour of --user; accepted but warns
    # Alpine koha-worker replacement must use --user, not --chuid.
    if echo "${HELP}" | grep -q '\-\-chuid\|-c'; then
        ok "--chuid accepted (deprecated alias; Alpine scripts must use --user instead)"
    else
        ok "--chuid absent (expected on newer BusyBox); Alpine scripts use --user for privilege drop"
    fi

    # Print the full help for operator reference
    echo ""
    echo "# start-stop-daemon --help output from ${KOHA_IMAGE}:"
    echo "${HELP}" | sed 's/^/# /'
fi

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}  Skipped: ${SKIP}"
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
