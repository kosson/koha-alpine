#!/usr/bin/env bash
# tests/test_phase3_dual_mode_templating_static.sh
#
# Static validation for Phase 3: Dual-Mode Templating & koha-gitify Elimination.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_SH="${ROOT_DIR}/files-alpine/run.sh"
HELPER_SH="${ROOT_DIR}/files-alpine/lib/run-sh-alpine.sh"
DOCKERFILE="${ROOT_DIR}/Dockerfile-Alpine"
CP_ALPINE="${ROOT_DIR}/files-alpine/misc4dev/cp_alpine_files.pl"
VHOST_TMPL="${ROOT_DIR}/files-alpine/templates/koha-vhost.conf.in"
KOHA_CONF_TMPL="${ROOT_DIR}/files-alpine/templates/koha-conf-site.xml.in"

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
    local desc="$1"; local pattern="$2"; local file="$3"
    if grep -qF -- "${pattern}" "${file}"; then
        ok "${desc}"
    else
        not_ok "${desc} (pattern not found: ${pattern})"
    fi
}
assert_not_contains() {
    local desc="$1"; local pattern="$2"; local file="$3"
    if ! grep -qF -- "${pattern}" "${file}"; then
        ok "${desc}"
    else
        not_ok "${desc} (unexpected pattern found: ${pattern})"
    fi
}
assert_file_exists() {
    local desc="$1"; local file="$2"
    if [ -f "${file}" ]; then
        ok "${desc}"
    else
        not_ok "${desc} (file not found: ${file})"
    fi
}

echo "TAP version 14"
echo "# Static checks for Phase 3 dual-mode templating and koha-gitify elimination"
echo ""

# --- run.sh: KOHA_PATH detection ---
assert_contains "run.sh sets KOHA_PATH dynamically" "export KOHA_PATH=" "${RUN_SH}"
assert_contains "run.sh sets KOHA_LIB_PATH" "export KOHA_LIB_PATH=" "${RUN_SH}"
assert_contains "KOHA_PATH added to VARS_TO_SUB" 'KOHA_PATH' "${RUN_SH}"
assert_contains "KOHA_LIB_PATH added to VARS_TO_SUB" 'KOHA_LIB_PATH' "${RUN_SH}"

# --- run.sh: gitify eliminated ---
assert_not_contains "run.sh has no direct koha-gitify call" "./koha-gitify" "${RUN_SH}"
assert_not_contains "run.sh has no --gitify_dir for do_all_you_can_do" "--gitify_dir" "${RUN_SH}"
assert_not_contains "run.sh has no chown on gitify dir" 'chown -R "${KOHA_INSTANCE}-koha" ${BUILD_DIR}/gitify' "${RUN_SH}"
assert_not_contains "run.sh has no apache-shared-*-git.conf sed injection" "apache-shared-opac-git.conf" "${RUN_SH}"

# --- run.sh: render_vhost replaces gitify Stage C ---
assert_contains "run.sh calls render_vhost" "render_vhost" "${RUN_SH}"

# --- run-sh-alpine.sh: render_vhost function ---
assert_contains "run-sh-alpine.sh has render_vhost function" "render_vhost()" "${HELPER_SH}"
assert_contains "render_vhost uses koha-vhost.conf.in template" "koha-vhost.conf.in" "${HELPER_SH}"

# --- koha-vhost.conf.in template ---
assert_file_exists "koha-vhost.conf.in template exists" "${VHOST_TMPL}"
assert_contains "vhost template uses KOHA_PATH" '${KOHA_PATH}' "${VHOST_TMPL}"
assert_contains "vhost template uses KOHA_LIB_PATH" '${KOHA_LIB_PATH}' "${VHOST_TMPL}"
assert_contains "vhost template includes ExecCGI" "ExecCGI" "${VHOST_TMPL}"
assert_contains "vhost template has intranet VirtualHost" "KOHA_INTRANET_PORT" "${VHOST_TMPL}"
assert_contains "vhost template has OPAC VirtualHost" "KOHA_OPAC_PORT" "${VHOST_TMPL}"

# --- koha-conf-site.xml.in: no hardcoded /usr/share/koha ---
assert_not_contains "koha-conf-site.xml.in has no hardcoded /usr/share/koha" "/usr/share/koha" "${KOHA_CONF_TMPL}"
assert_contains "koha-conf-site.xml.in uses KOHA_PATH variable" '${KOHA_PATH}' "${KOHA_CONF_TMPL}"
assert_contains "koha-conf-site.xml.in uses KOHA_LIB_PATH variable" '${KOHA_LIB_PATH}' "${KOHA_CONF_TMPL}"

# --- Dockerfile: no live gitify clone ---
assert_not_contains "Dockerfile has no koha-gitify git clone" "koha-gitify.git" "${DOCKERFILE}"
assert_contains "Dockerfile has no-op gitify stub" "koha-gitify eliminated" "${DOCKERFILE}"

# --- cp_alpine_files.pl: no gitify references ---
assert_not_contains "cp_alpine_files.pl has no gitify_dir argument" "gitify_dir" "${CP_ALPINE}"
assert_not_contains "cp_alpine_files.pl has no koha-gitify call" "koha-gitify" "${CP_ALPINE}"

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}"
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
