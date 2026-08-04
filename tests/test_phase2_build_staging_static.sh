#!/usr/bin/env bash
# tests/test_phase2_build_staging_static.sh
#
# Dedicated Phase 2 static validation:
# - Runtime staging fallback is removed from startup helper.
# - Build-time staging is configured in Dockerfile-Alpine.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER_SH="${ROOT_DIR}/files-alpine/lib/run-sh-alpine.sh"
DOCKERFILE="${ROOT_DIR}/Dockerfile-Alpine"

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

echo "TAP version 14"
echo "# Static checks for Phase 2 build-time asset staging compliance"
echo ""

# --- run-sh-alpine.sh checks ---
assert_contains "copy_runtime_files exists" "copy_runtime_files()" "${HELPER_SH}"
assert_contains "SKIP_RUNTIME_ASSET_COPY guard present" "SKIP_RUNTIME_ASSET_COPY" "${HELPER_SH}"
assert_contains "dev path calls build-alpine-package.sh" '/usr/local/bin/build-alpine-package.sh' "${HELPER_SH}"
assert_not_contains "no cp_alpine_files.pl fallback remains" "cp_alpine_files.pl" "${HELPER_SH}"
assert_not_contains "no cp_debian_files.pl fallback remains" "cp_debian_files.pl" "${HELPER_SH}"

# --- Dockerfile checks ---
assert_not_contains "koha source directory not copied into build context" "COPY koha /tmp/koha-build-src" "${DOCKERFILE}"
assert_contains "prod-runtime stages assets from fetched git source" "/usr/local/bin/build-alpine-package.sh /kohadevbox/koha" "${DOCKERFILE}"
assert_contains "SKIP_RUNTIME_ASSET_COPY set in prod-runtime" "ENV SKIP_RUNTIME_ASSET_COPY=yes" "${DOCKERFILE}"

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}"
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
