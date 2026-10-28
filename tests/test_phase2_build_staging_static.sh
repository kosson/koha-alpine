#!/usr/bin/env bash
# tests/test_phase2_build_staging_static.sh
#
# Dedicated Phase 2 static validation:
# - Runtime staging fallback is removed from startup helper.
# - Build-time staging is configured in Dockerfile-Alpine.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER_SH="${ROOT_DIR}/files-alpine/lib/run-sh-alpine.sh"
PACKAGE_HELPER="${ROOT_DIR}/scripts/build-alpine-package.sh"
DOCKERFILE="${ROOT_DIR}/Dockerfile-Alpine"
PROD_COMPOSE="${ROOT_DIR}/docker-compose.prod.yml"

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
assert_contains "Koha htdocs destinations exist before manifest staging" "make_path('/usr/share/koha/intranet/htdocs', '/usr/share/koha/opac/htdocs');" "${PACKAGE_HELPER}"

# --- Dockerfile checks ---
assert_not_contains "koha source directory not copied into build context" "COPY koha /tmp/koha-build-src" "${DOCKERFILE}"
assert_contains "prod-runtime stages assets from fetched git source" "/tmp/build-scripts/build-alpine-package.sh /kohadevbox/koha" "${DOCKERFILE}"
assert_contains "runtime image keeps only the vhost template from the source tree" "COPY files-alpine/templates/koha-vhost.conf.in /build/files-alpine/templates/koha-vhost.conf.in" "${DOCKERFILE}"
assert_contains "build-time Alpine overlays are mounted transiently" "--mount=type=bind,source=files-alpine,target=/tmp/files-alpine,ro" "${DOCKERFILE}"
assert_not_contains "runtime image does not copy the full development helper tree" "COPY files-alpine/ /build/files-alpine/" "${DOCKERFILE}"
assert_not_contains "runtime image does not copy source TLS key material" "COPY files-alpine/mariadb-ssl/" "${DOCKERFILE}"
assert_contains "dev-runtime separately includes Alpine command helpers" "COPY files-alpine/scripts/ /build/files-alpine/scripts/" "${DOCKERFILE}"
assert_contains "prod-runtime skips runtime asset copying" "SKIP_RUNTIME_ASSET_COPY=yes" "${DOCKERFILE}"
assert_contains "node builder creates the Koha source parent before copying" "mkdir -p /kohadevbox" "${DOCKERFILE}"
assert_contains "node builder copies only Koha source into its build context" "COPY koha/ /tmp/context/koha/" "${DOCKERFILE}"
assert_contains "node builder fails on frontend asset build errors" "yarn build;" "${DOCKERFILE}"
assert_contains "dev compose explicitly builds dev-runtime" "target: dev-runtime" "${ROOT_DIR}/docker-compose-alpinekoha.yml"
assert_contains "dev runtime uses Node 22 for Koha's frontend toolchain" "COPY --from=node-builder /usr/local/bin/node /usr/local/bin/node" "${DOCKERFILE}"
assert_contains "prod-runtime checks for a pinned source ref" 'test -n "${KOHA_GIT_REF}"' "${DOCKERFILE}"
assert_contains "production Perl dependencies are resolved from fetched source" "COPY --from=prod-source /kohadevbox/koha /kohadevbox/koha" "${DOCKERFILE}"
assert_contains "production Perl dependency stage installs release dependencies" "FROM builder AS prod-deps" "${DOCKERFILE}"
assert_contains "production runtime copies Perl dependencies from its release stage" "COPY --from=prod-deps /opt/koha-perl /opt/koha-perl" "${DOCKERFILE}"
assert_contains "dev and production Perl dependencies share one installer" "install-koha-perl-dependencies.sh" "${DOCKERFILE}"
assert_contains "production source records the resolved commit" "git -C /kohadevbox/koha rev-parse HEAD > /tmp/koha-source-revision" "${DOCKERFILE}"
assert_contains "production rejects floating branch refs" 'refs/heads/*|refs/remotes/*)' "${DOCKERFILE}"
assert_contains "production fetches explicit tags under refs/tags" 'source_ref="refs/tags/${KOHA_GIT_REF}"' "${DOCKERFILE}"
assert_contains "production fetches the validated source ref" 'git -C /kohadevbox/koha fetch --depth "${KOHA_GIT_DEPTH}" origin "${source_ref}"' "${DOCKERFILE}"
assert_contains "production image labels the source revision" 'org.opencontainers.image.revision="${KOHA_GIT_REF}"' "${DOCKERFILE}"
assert_contains "production image contains resolved revision metadata" "COPY --from=prod-source /tmp/koha-source-revision /usr/share/koha/source-revision" "${DOCKERFILE}"
assert_contains "production runtime PATH includes packaged admin-command directories" "PATH=/opt/koha-perl/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin" "${DOCKERFILE}"
assert_contains "production Compose builds the production target" "target: prod-runtime" "${PROD_COMPOSE}"
assert_contains "production Compose requires a release version" 'KOHA_RELEASE_VERSION must be set' "${PROD_COMPOSE}"
assert_contains "production Compose requires a pinned source ref" 'KOHA_RELEASE_REF must be a release tag or commit SHA' "${PROD_COMPOSE}"
assert_contains "production Compose replaces inherited dev volumes" "volumes: !override" "${PROD_COMPOSE}"
assert_not_contains "production Compose does not bind the dev checkout" 'SYNC_REPO' "${PROD_COMPOSE}"
assert_contains "production Compose skips runtime asset installation" 'SKIP_YARN_INSTALL: "yes"' "${PROD_COMPOSE}"
assert_contains "production Compose disables demo-data loading by default" 'KOHA_PROD_LOAD_DEMO_DATA:-no' "${PROD_COMPOSE}"
assert_contains "production Compose disables dev CPAN extras" 'CPAN: "no"' "${PROD_COMPOSE}"

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}"
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
