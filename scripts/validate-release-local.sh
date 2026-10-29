#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KOHA_SOURCE_DIR="${ROOT_DIR}/koha"
RELEASE_VERSION="${KOHA_RELEASE_VERSION:-26.05.01-1}"
RELEASE_REF="${KOHA_RELEASE_REF:-v26.05.01-1}"
RELEASE_GIT_URL="${KOHA_RELEASE_GIT_URL:-https://git.koha-community.org/Koha-community/Koha.git}"
DEV_IMAGE="koha-alpine-acceptance:dev"
PROD_IMAGE="koha-alpine-acceptance:${RELEASE_VERSION}"
TEST_ENV_FILE=""

cleanup() {
  if [[ -n "${TEST_ENV_FILE}" ]]; then
    rm -f "${TEST_ENV_FILE}"
  fi
}
trap cleanup EXIT

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

for command in git docker; do
  command -v "${command}" >/dev/null 2>&1 || fail "Required command not found: ${command}"
done
docker compose version >/dev/null 2>&1 || fail "Docker Compose plugin is required"
docker buildx version >/dev/null 2>&1 || fail "Docker Buildx is required"
docker info >/dev/null 2>&1 || fail "Docker daemon is not available"

[[ -d "${KOHA_SOURCE_DIR}/.git" ]] || fail "Koha source checkout is missing: ${KOHA_SOURCE_DIR}"
[[ -f "${ROOT_DIR}/Dockerfile-Alpine" ]] || fail "Dockerfile-Alpine is missing"

source_commit="$(git -C "${KOHA_SOURCE_DIR}" rev-parse HEAD)"
expected_commit="$(git -C "${KOHA_SOURCE_DIR}" rev-parse "${RELEASE_REF}^{commit}" 2>/dev/null)" \
  || fail "Release ref '${RELEASE_REF}' is not present in the local Koha checkout"
[[ "${source_commit}" == "${expected_commit}" ]] \
  || fail "Local Koha checkout is ${source_commit}, not the requested ref ${RELEASE_REF} (${expected_commit})"

repository_revision="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
worktree_changes="$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=all | wc -l | tr -d ' ')"
printf 'Repository revision: %s\n' "${repository_revision}"
if (( worktree_changes > 0 )); then
  printf 'Repository worktree: dirty (%s changed/untracked paths)\n' "${worktree_changes}"
else
  printf 'Repository worktree: clean\n'
fi
printf 'Docker: %s\n' "$(docker --version)"
printf 'Compose: %s\n' "$(docker compose version --short)"
printf 'Buildx: %s\n' "$(docker buildx version | head -1)"
printf 'Release version: %s\nRequested Koha ref: %s\nResolved Koha commit: %s\n' \
  "${RELEASE_VERSION}" "${RELEASE_REF}" "${source_commit}"
printf 'Validation mode: local only; no stack services will be started.\n\n'

printf '%s\n' '== Repository test suites =='
env \
  -u KOHA_TEST_PROJECT \
  -u KOHA_TEST_ENV_FILE \
  -u KOHA_TEST_COMPOSE_OVERRIDE \
  bash "${ROOT_DIR}/tests/run_all_tests.sh"

TEST_ENV_FILE="$(mktemp)"
chmod 600 "${TEST_ENV_FILE}"
cat >"${TEST_ENV_FILE}" <<EOF
KOHA_INSTANCE=kohadev
KOHA_DOMAIN=.example.invalid
KOHA_INTRANET_PREFIX=
KOHA_INTRANET_SUFFIX=-intra
KOHA_OPAC_PREFIX=
KOHA_OPAC_SUFFIX=
KOHA_OPAC_PORT=18880
KOHA_INTRANET_PORT=18881
KOHA_DB_ROOT_PASSWORD=local-validation-only
KOHA_DB_PASSWORD=local-validation-only
KOHA_RABBITMQ_PASS=local-validation-only
KOHA_PASS=local-validation-only
KOHA_RELEASE_VERSION=${RELEASE_VERSION}
KOHA_RELEASE_REF=${RELEASE_REF}
KOHA_RELEASE_GIT_URL=${RELEASE_GIT_URL}
KOHA_RELEASE_GIT_DEPTH=1
KOHA_ALPINE_IMAGE_TAG=${DEV_IMAGE}
KOHA_ALPINE_PROD_IMAGE_TAG=${PROD_IMAGE}
KOHA_ALPINE_ELASTICSEARCH=no
KOHA_IMAGE_MODE=dev
SYNC_REPO=${KOHA_SOURCE_DIR}
KOHA_ENV_FILE=${TEST_ENV_FILE}
KOHA_CONTAINER_ENV_FILE=${TEST_ENV_FILE}
LOCAL_USER_ID=$(id -u)
MANA_URL=https://mana-kb.koha-community.org
EOF

compose() {
  local mode="$1"
  shift
  local -a files=(-f "${ROOT_DIR}/docker-compose-alpinekoha.yml")
  if [[ "${mode}" == "prod" ]]; then
    files+=(-f "${ROOT_DIR}/docker-compose.prod.yml")
  fi
  docker compose \
    --project-name "koha-alpine-acceptance-${mode}" \
    --project-directory "${ROOT_DIR}" \
    --env-file "${TEST_ENV_FILE}" \
    "${files[@]}" "$@"
}

printf '\n%s\n' '== Compose configuration validation =='
compose dev config --quiet
printf 'Development Compose configuration: PASS\n'
compose prod config --quiet
printf 'Production Compose configuration: PASS\n'

docker_root="$(docker info --format '{{.DockerRootDir}}')"
free_kib="$(df -Pk "${docker_root}" | awk 'END {print $4}')"
minimum_free_kib=$((15 * 1024 * 1024))
[[ "${free_kib}" =~ ^[0-9]+$ ]] || fail "Could not determine free space for Docker data root: ${docker_root}"
if (( free_kib < minimum_free_kib )); then
  free_gib="$(awk -v kib="${free_kib}" 'BEGIN {printf "%.1f", kib / 1024 / 1024}')"
  fail "At least 15 GiB must be free on the Docker data filesystem before full builds; found ${free_gib} GiB at ${docker_root}"
fi

printf '\n%s\n' '== Full uncached release builds =='
compose dev build --pull --no-cache koha
docker image inspect "${DEV_IMAGE}" \
  --format 'Development image: id={{.Id}} size={{.Size}} version={{index .Config.Labels "org.opencontainers.image.version"}} revision={{index .Config.Labels "org.opencontainers.image.revision"}}'

compose prod build --pull --no-cache koha
docker image inspect "${PROD_IMAGE}" \
  --format 'Production image: id={{.Id}} size={{.Size}} version={{index .Config.Labels "org.opencontainers.image.version"}} revision={{index .Config.Labels "org.opencontainers.image.revision"}}'

printf '\nLocal release validation completed. No Compose services were started.\n'
