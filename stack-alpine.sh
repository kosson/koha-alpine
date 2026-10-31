#!/usr/bin/env bash
# stack-alipne.sh — Manage the Alpine Koha stack + optional OpenSearch/Traefik services
#
# Usage: ./stack-alipne.sh <command> [options]
#   start     Build (if requested) and start the full stack (default)
#   stop      Stop all services gracefully
#   restart   Quick restart: reset DB + recreate Koha container (no OS restart)
#   status    Show running containers and OpenSearch cluster health
#   logs      Tail Koha container logs
#   build     Build images only (no start)
#   backup    Create a portable backup bundle for env files + MariaDB data
#   restore   Restore env files + MariaDB data from a backup bundle
#
# Run './stack-alipne.sh --help' for full usage.

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths — all derived from this script's location
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSEARCH_DIR="${SCRIPT_DIR}/OpenSearch-3.6"
TRAEFIK_DIR="${SCRIPT_DIR}/traefik"
KOHA_COMPOSE_FILE="${SCRIPT_DIR}/docker-compose-alpinekoha.yml"
KOHA_COMPOSE_PROD_FILE="${SCRIPT_DIR}/docker-compose.prod.yml"
KOHA_ENV_FILE="${KOHA_ENV_FILE:-${SCRIPT_DIR}/env/.env}"
if [[ "${KOHA_ENV_FILE}" != /* ]]; then
  KOHA_ENV_FILE="$(cd "$(dirname "${KOHA_ENV_FILE}")" && pwd)/$(basename "${KOHA_ENV_FILE}")"
fi
KOHA_PROJECT_DIR="${SCRIPT_DIR}"
KOHA_DEFAULT_REPO_URL="https://git.koha-community.org/Koha-community/Koha.git"
MARIADB_SSL_DIR="${SCRIPT_DIR}/files-alpine/mariadb-ssl"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; RESET=''
fi

ts()   { date '+%H:%M:%S'; }
log()  { echo -e "${BLUE}[$(ts)]${RESET} $*"; }
ok()   { echo -e "${GREEN}[$(ts)] ✓${RESET} $*"; }
warn() { echo -e "${YELLOW}[$(ts)] ⚠${RESET}  $*"; }
die()  { echo -e "${RED}[$(ts)] ✗  $*${RESET}" >&2; exit 1; }
hdr()  { echo -e "\n${BOLD}${CYAN}── $* ──${RESET}"; }

# ---------------------------------------------------------------------------
# Config — read from env files, with safe fallbacks
# ---------------------------------------------------------------------------
_env_val() {
  # Usage: _env_val FILE KEY [DEFAULT]
  local file="$1" key="$2" default="${3:-}"
  local val
  val=$(grep -E "^${key}=" "${file}" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'" || true)
  echo "${val:-${default}}"
}

_set_env_val() {
  # Usage: _set_env_val FILE KEY VALUE
  local file="$1" key="$2" value="$3"
  local esc
  esc="$(printf '%s' "${value}" | sed 's/[\/&]/\\&/g')"
  if grep -qE "^${key}=" "${file}" 2>/dev/null; then
    sed -i "s#^${key}=.*#${key}=${esc}#" "${file}"
  else
    printf "%s=%s\n" "${key}" "${value}" >> "${file}"
  fi
}

# Fetch the highest version tag from the upstream Koha git repository.
# Tags follow the pattern vMAJOR.MINOR.PATCH[-REVISION] (e.g. v25.11.06-1, v26.05.01-1).
# plain `sort -V` mis-orders the -REVISION suffix; splitting on '.' and sorting each
# numeric field independently gives the correct order.
koha_latest_tag() {
  local url
  url="${1:-${KOHA_GIT_URL:-${KOHA_DEFAULT_REPO_URL}}}"
  git ls-remote --tags "${url}" 2>/dev/null \
    | grep 'refs/tags/v2' \
    | grep -v '\^{}' \
    | awk '{print $2}' \
    | sed 's|refs/tags/||' \
    | sort -t. -k1,1V -k2,2n -k3,3n \
    | tail -1
}

KOHA_INSTANCE="$(_env_val "${KOHA_ENV_FILE}" KOHA_INSTANCE kohadev)"
KOHA_DOMAIN="$(_env_val   "${KOHA_ENV_FILE}" KOHA_DOMAIN   .myDNSname.org)"
KOHA_INTRANET_SUFFIX="$(_env_val "${KOHA_ENV_FILE}" KOHA_INTRANET_SUFFIX -intra)"
KOHA_OPAC_PORT="$(_env_val      "${KOHA_ENV_FILE}" KOHA_OPAC_PORT      8080)"
KOHA_INTRANET_PORT="$(_env_val  "${KOHA_ENV_FILE}" KOHA_INTRANET_PORT  8081)"
KOHA_USER="$(_env_val "${KOHA_ENV_FILE}" KOHA_USER koha)"
KOHA_PASS="$(_env_val "${KOHA_ENV_FILE}" KOHA_PASS "")"
KOHA_DB_ROOT_PASSWORD="$(_env_val "${KOHA_ENV_FILE}" KOHA_DB_ROOT_PASSWORD "")"
TRAEFIK_HTTP_PORT="$(_env_val "${TRAEFIK_DIR}/.env" TRAEFIK_HTTP_PORT 80)"
TRAEFIK_HTTPS_PORT="$(_env_val "${TRAEFIK_DIR}/.env" TRAEFIK_HTTPS_PORT 443)"
TRAEFIK_DASHBOARD_PORT="$(_env_val "${TRAEFIK_DIR}/.env" TRAEFIK_DASHBOARD_PORT 8083)"
ACME_EMAIL="$(_env_val "${TRAEFIK_DIR}/.env" ACME_EMAIL "")"
KOHA_ELASTICSEARCH="$(_env_val "${KOHA_ENV_FILE}" KOHA_ALPINE_ELASTICSEARCH "$(_env_val "${KOHA_ENV_FILE}" KOHA_ELASTICSEARCH no)")"
# Admin password: prefer the OS .env file (source of truth for the cluster)
OS_ADMIN_PASS="$(_env_val "${OPENSEARCH_DIR}/.env" OPENSEARCH_INITIAL_ADMIN_PASSWORD \
  "$(_env_val "${KOHA_ENV_FILE}" OPENSEARCH_INITIAL_ADMIN_PASSWORD "")")"
KOHA_ELASTIC_OPTIONS="$(_env_val "${KOHA_ENV_FILE}" ELASTIC_OPTIONS "")"
DASHBOARDS_DOMAIN="$(_env_val "${OPENSEARCH_DIR}/.env" DASHBOARDS_DOMAIN "dashboards.localhost")"
TLS_CERTRESOLVER="$(_env_val "${KOHA_ENV_FILE}" TLS_CERTRESOLVER "")"
SYNC_REPO="$(_env_val "${KOHA_ENV_FILE}" SYNC_REPO "${SCRIPT_DIR}/koha")"
KOHA_GIT_URL="$(_env_val "${KOHA_ENV_FILE}" KOHA_GIT_URL "${KOHA_DEFAULT_REPO_URL}")"
KOHA_GIT_CLONE_MODE="$(_env_val "${KOHA_ENV_FILE}" KOHA_GIT_CLONE_MODE tag)"
KOHA_GIT_TAG="$(_env_val "${KOHA_ENV_FILE}" KOHA_GIT_TAG "")"
KOHA_GIT_BRANCH="$(_env_val "${KOHA_ENV_FILE}" KOHA_GIT_BRANCH main)"
KOHA_GIT_DEPTH="$(_env_val "${KOHA_ENV_FILE}" KOHA_GIT_DEPTH 1)"
KOHA_DESIRED_LANGUAGES="$(_env_val "${KOHA_ENV_FILE}" KOHA_DESIRED_LANGUAGES en)"
KOHA_OPAC_LANGUAGES_DISPLAY="$(_env_val "${KOHA_ENV_FILE}" KOHA_OPAC_LANGUAGES_DISPLAY 1)"
KOHA_TRANSLATIONS_REINSTALL="$(_env_val "${KOHA_ENV_FILE}" KOHA_TRANSLATIONS_REINSTALL no)"
KOHA_IMAGE_MODE="$(_env_val "${KOHA_ENV_FILE}" KOHA_IMAGE_MODE dev)"
KOHA_RELEASE_VERSION="$(_env_val "${KOHA_ENV_FILE}" KOHA_RELEASE_VERSION "${KOHA_GIT_TAG#v}")"
KOHA_RELEASE_REF="$(_env_val "${KOHA_ENV_FILE}" KOHA_RELEASE_REF "${KOHA_GIT_TAG}")"
KOHA_RELEASE_GIT_URL="$(_env_val "${KOHA_ENV_FILE}" KOHA_RELEASE_GIT_URL "${KOHA_GIT_URL}")"
KOHA_RELEASE_GIT_DEPTH="$(_env_val "${KOHA_ENV_FILE}" KOHA_RELEASE_GIT_DEPTH "${KOHA_GIT_DEPTH}")"
KOHA_ALPINE_PROD_IMAGE_TAG="$(_env_val "${KOHA_ENV_FILE}" KOHA_ALPINE_PROD_IMAGE_TAG "")"
KOHA_PROD_PROJECT="$(_env_val "${KOHA_ENV_FILE}" KOHA_PROD_PROJECT "${KOHA_PROD_PROJECT:-}")"
KOHA_CONTAINER_ENV_FILE="${KOHA_CONTAINER_ENV_FILE:-$(_env_val "${KOHA_ENV_FILE}" KOHA_CONTAINER_ENV_FILE "${KOHA_ENV_FILE}")}"

DB_NAME="koha_${KOHA_INSTANCE}"
DB_USER="koha_${KOHA_INSTANCE}"
KOHA_PROJECT="$(basename "${KOHA_PROJECT_DIR}")"   # which strips away all leading parent directories and leaves only the final folder name string → koha-alpine
SYNC_REPO="${SYNC_REPO:-${SCRIPT_DIR}/koha}"
export KOHA_ENV_FILE KOHA_CONTAINER_ENV_FILE SYNC_REPO
KOHA_COMPOSE_PROJECT="${KOHA_PROJECT}"
DB_CONTAINER="${KOHA_COMPOSE_PROJECT}-db-1"
BACKUP_ROOT="${SCRIPT_DIR}/backups"
BOOTSTRAP_MARKER="${SYNC_REPO}/.alpine-bootstrap-complete"

reload_runtime_config() {
  KOHA_INSTANCE="$(_env_val "${KOHA_ENV_FILE}" KOHA_INSTANCE "${KOHA_INSTANCE}")"
  KOHA_DOMAIN="$(_env_val "${KOHA_ENV_FILE}" KOHA_DOMAIN "${KOHA_DOMAIN}")"
  KOHA_INTRANET_SUFFIX="$(_env_val "${KOHA_ENV_FILE}" KOHA_INTRANET_SUFFIX "${KOHA_INTRANET_SUFFIX}")"
  KOHA_OPAC_PORT="$(_env_val "${KOHA_ENV_FILE}" KOHA_OPAC_PORT "${KOHA_OPAC_PORT}")"
  KOHA_INTRANET_PORT="$(_env_val "${KOHA_ENV_FILE}" KOHA_INTRANET_PORT "${KOHA_INTRANET_PORT}")"
  KOHA_USER="$(_env_val "${KOHA_ENV_FILE}" KOHA_USER "${KOHA_USER}")"
  KOHA_PASS="$(_env_val "${KOHA_ENV_FILE}" KOHA_PASS "${KOHA_PASS}")"
  KOHA_DB_ROOT_PASSWORD="$(_env_val "${KOHA_ENV_FILE}" KOHA_DB_ROOT_PASSWORD "${KOHA_DB_ROOT_PASSWORD}")"
  KOHA_ELASTICSEARCH="$(_env_val "${KOHA_ENV_FILE}" KOHA_ALPINE_ELASTICSEARCH "$(_env_val "${KOHA_ENV_FILE}" KOHA_ELASTICSEARCH "${KOHA_ELASTICSEARCH}")")"
  KOHA_ELASTIC_OPTIONS="$(_env_val "${KOHA_ENV_FILE}" ELASTIC_OPTIONS "${KOHA_ELASTIC_OPTIONS}")"
  LOAD_DEMO_DATA="$(_env_val "${KOHA_ENV_FILE}" LOAD_DEMO_DATA "${LOAD_DEMO_DATA}")"
  SYNC_REPO="$(_env_val "${KOHA_ENV_FILE}" SYNC_REPO "${SYNC_REPO}")"
  KOHA_GIT_URL="$(_env_val "${KOHA_ENV_FILE}" KOHA_GIT_URL "${KOHA_GIT_URL}")"
  KOHA_GIT_CLONE_MODE="$(_env_val "${KOHA_ENV_FILE}" KOHA_GIT_CLONE_MODE "${KOHA_GIT_CLONE_MODE}")"
  KOHA_GIT_TAG="$(_env_val "${KOHA_ENV_FILE}" KOHA_GIT_TAG "${KOHA_GIT_TAG}")"
  KOHA_GIT_BRANCH="$(_env_val "${KOHA_ENV_FILE}" KOHA_GIT_BRANCH "${KOHA_GIT_BRANCH}")"
  KOHA_GIT_DEPTH="$(_env_val "${KOHA_ENV_FILE}" KOHA_GIT_DEPTH "${KOHA_GIT_DEPTH}")"
  KOHA_DESIRED_LANGUAGES="$(_env_val "${KOHA_ENV_FILE}" KOHA_DESIRED_LANGUAGES "${KOHA_DESIRED_LANGUAGES}")"
  KOHA_OPAC_LANGUAGES_DISPLAY="$(_env_val "${KOHA_ENV_FILE}" KOHA_OPAC_LANGUAGES_DISPLAY "${KOHA_OPAC_LANGUAGES_DISPLAY}")"
  KOHA_TRANSLATIONS_REINSTALL="$(_env_val "${KOHA_ENV_FILE}" KOHA_TRANSLATIONS_REINSTALL "${KOHA_TRANSLATIONS_REINSTALL}")"
  KOHA_IMAGE_MODE="$(_env_val "${KOHA_ENV_FILE}" KOHA_IMAGE_MODE "${KOHA_IMAGE_MODE}")"
  KOHA_RELEASE_VERSION="$(_env_val "${KOHA_ENV_FILE}" KOHA_RELEASE_VERSION "${KOHA_RELEASE_VERSION}")"
  KOHA_RELEASE_REF="$(_env_val "${KOHA_ENV_FILE}" KOHA_RELEASE_REF "${KOHA_RELEASE_REF}")"
  KOHA_RELEASE_GIT_URL="$(_env_val "${KOHA_ENV_FILE}" KOHA_RELEASE_GIT_URL "${KOHA_RELEASE_GIT_URL}")"
  KOHA_RELEASE_GIT_DEPTH="$(_env_val "${KOHA_ENV_FILE}" KOHA_RELEASE_GIT_DEPTH "${KOHA_RELEASE_GIT_DEPTH}")"
  KOHA_ALPINE_PROD_IMAGE_TAG="$(_env_val "${KOHA_ENV_FILE}" KOHA_ALPINE_PROD_IMAGE_TAG "${KOHA_ALPINE_PROD_IMAGE_TAG}")"
  KOHA_PROD_PROJECT="$(_env_val "${KOHA_ENV_FILE}" KOHA_PROD_PROJECT "${KOHA_PROD_PROJECT}")"
  KOHA_CONTAINER_ENV_FILE="$(_env_val "${KOHA_ENV_FILE}" KOHA_CONTAINER_ENV_FILE "${KOHA_CONTAINER_ENV_FILE}")"
  SYNC_REPO="$(_env_val "${KOHA_ENV_FILE}" SYNC_REPO "${SYNC_REPO}")"
  TRAEFIK_HTTP_PORT="$(_env_val "${TRAEFIK_DIR}/.env" TRAEFIK_HTTP_PORT "${TRAEFIK_HTTP_PORT}")"
  TRAEFIK_HTTPS_PORT="$(_env_val "${TRAEFIK_DIR}/.env" TRAEFIK_HTTPS_PORT "${TRAEFIK_HTTPS_PORT}")"
  TRAEFIK_DASHBOARD_PORT="$(_env_val "${TRAEFIK_DIR}/.env" TRAEFIK_DASHBOARD_PORT "${TRAEFIK_DASHBOARD_PORT}")"
  ACME_EMAIL="$(_env_val "${TRAEFIK_DIR}/.env" ACME_EMAIL "${ACME_EMAIL}")"
  OS_ADMIN_PASS="$(_env_val "${OPENSEARCH_DIR}/.env" OPENSEARCH_INITIAL_ADMIN_PASSWORD "${OS_ADMIN_PASS}")"
  DASHBOARDS_DOMAIN="$(_env_val "${OPENSEARCH_DIR}/.env" DASHBOARDS_DOMAIN "${DASHBOARDS_DOMAIN}")"
  TLS_CERTRESOLVER="$(_env_val "${KOHA_ENV_FILE}" TLS_CERTRESOLVER "${TLS_CERTRESOLVER}")"
  DB_NAME="koha_${KOHA_INSTANCE}"
  DB_USER="koha_${KOHA_INSTANCE}"
  configure_koha_mode
}

normalize_language_list() {
  # Keep only valid language tags, deduplicate, and ensure 'en' is first.
  local raw="$1"
  local token
  local -a parts
  local -a ordered
  local -a normalized
  declare -A seen=()

  IFS=',' read -r -a parts <<<"${raw}"
  for token in "${parts[@]}"; do
    token="${token//[[:space:]]/}"
    [[ -z "${token}" ]] && continue
    [[ "${token}" =~ ^[A-Za-z0-9_-]+$ ]] || die "Invalid language tag '${token}' in KOHA_DESIRED_LANGUAGES"
    if [[ -z "${seen[${token}]+x}" ]]; then
      seen["${token}"]=1
      ordered+=("${token}")
    fi
  done

  normalized=("en")
  for token in "${ordered[@]}"; do
    [[ "${token}" == "en" ]] && continue
    normalized+=("${token}")
  done

  local out=""
  for token in "${normalized[@]}"; do
    out+="${out:+,}${token}"
  done
  echo "${out}"
}

version_slug() {
  local raw="$1"
  echo "${raw}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/^v//' -e 's/[^a-z0-9]/-/g' -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//'
}

configure_koha_mode() {
  KOHA_IMAGE_MODE="$(echo "${KOHA_IMAGE_MODE}" | tr '[:upper:]' '[:lower:]')"
  case "${KOHA_IMAGE_MODE}" in
    dev|prod) ;;
    *) die "Invalid --image-mode '${KOHA_IMAGE_MODE}'. Use dev or prod." ;;
  esac

  if [[ "${KOHA_IMAGE_MODE}" == "prod" ]]; then
    if [[ -n "${KOHA_RELEASE_VERSION}" && -z "${KOHA_RELEASE_REF}" ]]; then
      KOHA_RELEASE_REF="v${KOHA_RELEASE_VERSION}"
    fi
    if [[ -z "${KOHA_RELEASE_VERSION}" && -n "${KOHA_RELEASE_REF}" ]]; then
      KOHA_RELEASE_VERSION="${KOHA_RELEASE_REF#v}"
    fi

    # Accept release refs with or without leading "v" (e.g. 25.11.06-1 -> v25.11.06-1).
    if [[ "${KOHA_RELEASE_REF}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$ ]]; then
      KOHA_RELEASE_REF="v${KOHA_RELEASE_REF}"
    fi

    [[ -n "${KOHA_RELEASE_VERSION}" ]] || die "KOHA_RELEASE_VERSION is required in prod mode. Set KOHA_GIT_TAG in env/.env or pass --koha-version."
    [[ -n "${KOHA_RELEASE_REF}" ]] || die "KOHA_RELEASE_REF is required in prod mode. Set KOHA_GIT_TAG in env/.env, pass --koha-ref, or run: ./$(basename "$0") latest-tag --apply"

    if [[ -z "${KOHA_ALPINE_PROD_IMAGE_TAG}" ]]; then
      KOHA_ALPINE_PROD_IMAGE_TAG="kosson/koha-alpine-prod:${KOHA_RELEASE_VERSION}"
    fi

    if [[ -n "${KOHA_PROD_PROJECT}" ]]; then
      [[ "${KOHA_PROD_PROJECT}" =~ ^[a-z0-9][a-z0-9_-]*$ ]] \
        || die "KOHA_PROD_PROJECT must start with a lowercase letter or digit and contain only lowercase letters, digits, '_' or '-'."
      KOHA_COMPOSE_PROJECT="${KOHA_PROD_PROJECT}"
    else
      local _slug
      _slug="$(version_slug "${KOHA_RELEASE_VERSION}")"
      KOHA_COMPOSE_PROJECT="koha-prod-${_slug}"
    fi

    export KOHA_RELEASE_VERSION
    export KOHA_RELEASE_REF
    export KOHA_RELEASE_GIT_URL
    export KOHA_RELEASE_GIT_DEPTH
    export KOHA_ALPINE_PROD_IMAGE_TAG
    export KOHA_CONTAINER_ENV_FILE SYNC_REPO
  else
    KOHA_COMPOSE_PROJECT="${KOHA_PROJECT}"
  fi

  DB_CONTAINER="${KOHA_COMPOSE_PROJECT}-db-1"
}

wait_translation_runtime() {
  local attempts=0
  local max=350

  log "Waiting for Koha translation runtime and full startup readiness for instance '${KOHA_INSTANCE}'..."
  until koha_compose exec -T koha bash -lc "
    test -x /kohadevbox/koha/misc/translator/translate &&
    test -d /kohadevbox/koha/misc/translator/po &&
    test -f /ktd_ready &&
    test -d /etc/koha/sites/${KOHA_INSTANCE} &&
    id ${KOHA_INSTANCE}-koha >/dev/null 2>&1 &&
    sudo koha-shell ${KOHA_INSTANCE} -p -c 'true' >/dev/null 2>&1
  " >/dev/null 2>&1; do
    (( ++attempts ))
    if (( attempts >= max )); then
      echo ""
      die "Koha translation runtime/full startup for instance '${KOHA_INSTANCE}' did not become ready after $(( max * 4 )) seconds"
    fi
    printf "\r  [%d/%d] waiting..." "${attempts}" "${max}"
    sleep 4
  done
  echo ""
  ok "Koha translation runtime and full startup for instance '${KOHA_INSTANCE}' are ready."
}

configure_koha_languages() {
  hdr "Configuring Koha interface languages"

  local languages_raw="${KOHA_DESIRED_LANGUAGES:-en}"
  local normalized_languages
  normalized_languages="$(normalize_language_list "${languages_raw}")"

  local opac_display="${KOHA_OPAC_LANGUAGES_DISPLAY:-1}"
  [[ "${opac_display}" =~ ^[01]$ ]] || die "KOHA_OPAC_LANGUAGES_DISPLAY must be 0 or 1 (current: '${opac_display}')"

  local reinstall="${KOHA_TRANSLATIONS_REINSTALL:-no}"
  reinstall="$(echo "${reinstall}" | tr '[:upper:]' '[:lower:]')"
  [[ "${reinstall}" =~ ^(yes|no)$ ]] || die "KOHA_TRANSLATIONS_REINSTALL must be yes or no (current: '${KOHA_TRANSLATIONS_REINSTALL}')"

  log "Language list from env/.env: ${normalized_languages}"

  local -a languages=()
  local -a install_languages=()
  local -a failed_languages=()
  local lang
  IFS=',' read -r -a languages <<<"${normalized_languages}"
  for lang in "${languages[@]}"; do
    [[ "${lang}" == "en" ]] && continue
    install_languages+=("${lang}")
  done

  if (( ${#install_languages[@]} > 0 )); then
    wait_translation_runtime
    for lang in "${install_languages[@]}"; do
      if [[ "${reinstall}" == "no" ]]; then
        if koha_compose exec -T koha bash -lc "test -d /usr/share/koha/intranet/htdocs/intranet-tmpl/prog/${lang} && test -d /usr/share/koha/opac/htdocs/opac-tmpl/bootstrap/${lang}" >/dev/null 2>&1; then
          ok "Language ${lang} already installed; skipping (set KOHA_TRANSLATIONS_REINSTALL=yes to force reinstall)."
          continue
        fi
      fi

      log "Installing translation pack: ${lang}"
      if ! koha_compose exec -T koha bash -lc "export KOHA_CONF=/etc/koha/sites/${KOHA_INSTANCE}/koha-conf.xml PERL5LIB=\"/kohadevbox/koha:/kohadevbox/koha/lib:\${PERL5LIB}\"; cd /kohadevbox/koha/misc/translator && ./translate install ${lang}"; then
        warn "Translation install failed for ${lang}; continuing startup. Check Perl module dependencies in container (e.g. Locale::PO)."
        failed_languages+=("${lang}")
      fi
    done
  else
    log "No extra translation packs requested (only 'en')."
  fi

  if (( ${#failed_languages[@]} > 0 )); then
    warn "Some translation packs failed to install: ${failed_languages[*]}"
  fi

  log "Applying language preferences to database (${DB_NAME})"
  local _has_systempreferences
  _has_systempreferences="$(docker exec "${DB_CONTAINER}" mysql -uroot -p"${KOHA_DB_ROOT_PASSWORD}" \
    --batch --skip-column-names -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='systempreferences';" 2>/dev/null || echo 0)"

  if [[ "${_has_systempreferences}" != "1" ]]; then
    warn "Skipping language DB updates for now: ${DB_NAME}.systempreferences is not available yet."
    warn "Run './$(basename "$0") start --no-fresh-db --no-logs' again after bootstrap to apply language preferences."
    return 0
  fi

  docker exec "${DB_CONTAINER}" mysql -uroot -p"${KOHA_DB_ROOT_PASSWORD}" "${DB_NAME}" -e "
UPDATE systempreferences SET value='${normalized_languages}' WHERE variable='StaffInterfaceLanguages';
UPDATE systempreferences SET value='${normalized_languages}' WHERE variable='OPACLanguages';
UPDATE systempreferences SET value='${opac_display}' WHERE variable='opaclanguagesdisplay';
"

  if ! koha_compose exec -T koha bash -lc "sudo koha-shell ${KOHA_INSTANCE} -p -c '/kohadevbox/koha/misc/bin/clear_cache.pl'" >/dev/null 2>&1; then
    warn "Could not run clear_cache.pl automatically; changes still applied and will take effect after cache expiry/restart."
  fi

  ok "Language configuration applied: Staff/OPAC=${normalized_languages}, opaclanguagesdisplay=${opac_display}"
}

# ---------------------------------------------------------------------------
# Compose wrappers
# ---------------------------------------------------------------------------
koha_compose() {
  local compose_args=(
    -f "${KOHA_COMPOSE_FILE}"
  )

  if [[ "${KOHA_IMAGE_MODE}" == "prod" ]]; then
    compose_args+=( -f "${KOHA_COMPOSE_PROD_FILE}" )
  fi

  # Optional per-project overrides (e.g. an isolated rehearsal project).
  local extra_file
  for extra_file in ${KOHA_EXTRA_COMPOSE_FILES:-}; do
    compose_args+=( -f "${extra_file}" )
  done

  docker compose \
    "${compose_args[@]}" \
    --env-file "${KOHA_ENV_FILE}" \
    -p "${KOHA_COMPOSE_PROJECT}" \
    --project-directory "${KOHA_PROJECT_DIR}" \
    "$@"
}

os_compose() {
  docker compose \
    -f "${OPENSEARCH_DIR}/docker-compose.yml" \
    --env-file "${OPENSEARCH_DIR}/.env" \
    --project-directory "${OPENSEARCH_DIR}" \
    "$@"
}

traefik_compose() {
  docker compose \
    -f "${TRAEFIK_DIR}/docker-compose.yaml" \
    --env-file "${TRAEFIK_DIR}/.env" \
    --project-directory "${TRAEFIK_DIR}" \
    "$@"
}

# Public demo values (env/demo-credentials.env) and placeholders must never
# run a production deployment.
reject_demo_credentials() {
  [[ "${KOHA_ALLOW_DEMO_CREDENTIALS:-no}" == "yes" ]] && return 0
  local key val bad=()
  for key in KOHA_DB_ROOT_PASSWORD KOHA_DB_PASSWORD KOHA_RABBITMQ_PASS KOHA_PASS KOHA_ADMIN_PASS OPENSEARCH_INITIAL_ADMIN_PASSWORD; do
    val="$(_env_val "${KOHA_ENV_FILE}" "${key}" "")"
    [[ -z "${val}" ]] && continue
    shopt -s nocasematch
    if [[ "${val}" == demo-* || "${val}" == change_me* || "${val}" == "password" || "${val}" == "koha" ]]; then
      bad+=("${key}")
    fi
    shopt -u nocasematch
  done
  if ((${#bad[@]})); then
    die "Production mode refuses demo/placeholder credentials (${bad[*]}) in ${KOHA_ENV_FILE}. Set unique values in an untracked env file, or KOHA_ALLOW_DEMO_CREDENTIALS=yes for a throwaway test."
  fi
  if git -C "${SCRIPT_DIR}" ls-files --error-unmatch files-alpine/mariadb-ssl/ca-key.pem >/dev/null 2>&1; then
    warn "files-alpine/mariadb-ssl/ca-key.pem is tracked in Git (public demo CA) and is mounted into the Koha container. Regenerate private TLS material (and keep the CA key out of the mounted directory) for production."
  fi
}

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
check_prereqs() {
  log "Checking prerequisites..."
  command -v git      >/dev/null 2>&1 || die "git not found in PATH"
  command -v docker   >/dev/null 2>&1 || die "docker not found in PATH"
  docker info >/dev/null 2>&1 || die "Docker daemon is not running. Start it first (for example: sudo systemctl start docker)."
  docker compose version >/dev/null 2>&1 || die "Docker Compose plugin not found"
  [[ -f "${KOHA_ENV_FILE}" ]] || die "Koha environment file not found: ${KOHA_ENV_FILE}. Set KOHA_ENV_FILE to an access-controlled local file."
  [[ -f "${KOHA_CONTAINER_ENV_FILE}" ]] || die "Koha container environment file not found: ${KOHA_CONTAINER_ENV_FILE}"
  [[ -n "${KOHA_DB_ROOT_PASSWORD}" ]] || die "KOHA_DB_ROOT_PASSWORD must be set in ${KOHA_ENV_FILE}"
  [[ -n "$(_env_val "${KOHA_ENV_FILE}" KOHA_DB_PASSWORD "")" ]] || die "KOHA_DB_PASSWORD must be set in ${KOHA_ENV_FILE}"
  [[ -n "$(_env_val "${KOHA_ENV_FILE}" KOHA_RABBITMQ_PASS "")" ]] || die "KOHA_RABBITMQ_PASS must be set in ${KOHA_ENV_FILE}"
  [[ -n "${KOHA_PASS}" || -n "$(_env_val "${KOHA_ENV_FILE}" KOHA_ADMIN_PASS "")" ]] \
    || die "KOHA_PASS or KOHA_ADMIN_PASS must be set in ${KOHA_ENV_FILE}"
  if [[ "${KOHA_IMAGE_MODE}" == "prod" ]]; then
    [[ -f "${KOHA_COMPOSE_PROD_FILE}" ]] || die "docker-compose.prod.yml not found"
    reject_demo_credentials
  fi
  if [[ "${KOHA_MANAGE_SHARED_SERVICES:-yes}" != "no" ]]; then
    [[ -f "${OPENSEARCH_DIR}/docker-compose.yml" ]] \
      || die "OpenSearch-3.6/docker-compose.yml not found"
    [[ -f "${TRAEFIK_DIR}/docker-compose.yaml" ]] \
      || die "traefik/docker-compose.yaml not found"
  fi
  ok "Prerequisites OK"
}

ensure_koha_source() {
  hdr "Ensuring Koha source tree"

  local clone_mode repo_dir repo_parent resolved_tag
  clone_mode="$(echo "${KOHA_GIT_CLONE_MODE}" | tr '[:upper:]' '[:lower:]')"
  repo_dir="${SYNC_REPO}"

  [[ -n "${repo_dir}" ]] || die "SYNC_REPO is empty in env/.env"
  repo_parent="$(dirname "${repo_dir}")"
  mkdir -p "${repo_parent}"

  if [[ -d "${repo_dir}/.git" ]]; then
    ok "Koha source already present at ${repo_dir}"
    return 0
  fi

  if [[ -e "${repo_dir}" ]]; then
    die "SYNC_REPO path exists but is not a git repo: ${repo_dir}"
  fi

  if [[ ! "${KOHA_GIT_DEPTH}" =~ ^[1-9][0-9]*$ ]]; then
    die "KOHA_GIT_DEPTH must be a positive integer (current: '${KOHA_GIT_DEPTH}')"
  fi

  case "${clone_mode}" in
    tag)
      [[ -n "${KOHA_GIT_TAG}" ]] || die "KOHA_GIT_TAG is required when KOHA_GIT_CLONE_MODE=tag"
      resolved_tag="${KOHA_GIT_TAG}"
      if ! git ls-remote --tags --refs "${KOHA_GIT_URL}" "refs/tags/${resolved_tag}" | grep -q .; then
        if [[ "${resolved_tag}" != v* ]] && git ls-remote --tags --refs "${KOHA_GIT_URL}" "refs/tags/v${resolved_tag}" | grep -q .; then
          resolved_tag="v${resolved_tag}"
          warn "KOHA_GIT_TAG='${KOHA_GIT_TAG}' not found; using '${resolved_tag}' (v-prefixed upstream tag)."
        else
          die "Koha tag '${KOHA_GIT_TAG}' not found at ${KOHA_GIT_URL}"
        fi
      fi
      log "Cloning Koha tag '${resolved_tag}' into '${repo_dir}' (depth=${KOHA_GIT_DEPTH})..."
      git clone --branch "${resolved_tag}" --single-branch --depth "${KOHA_GIT_DEPTH}" "${KOHA_GIT_URL}" "${repo_dir}"
      ;;
    branch)
      [[ -n "${KOHA_GIT_BRANCH}" ]] || die "KOHA_GIT_BRANCH is required when KOHA_GIT_CLONE_MODE=branch"
      log "Cloning Koha branch '${KOHA_GIT_BRANCH}' into '${repo_dir}' (depth=${KOHA_GIT_DEPTH})..."
      git clone --branch "${KOHA_GIT_BRANCH}" --single-branch --depth "${KOHA_GIT_DEPTH}" "${KOHA_GIT_URL}" "${repo_dir}"
      ;;
    *)
      die "Invalid KOHA_GIT_CLONE_MODE='${KOHA_GIT_CLONE_MODE}'. Use 'tag' or 'branch'."
      ;;
  esac

  ok "Koha source prepared at ${repo_dir}"
}

prepare_mariadb_client_tls() {
  hdr "Preparing MariaDB client TLS materials"

  command -v openssl >/dev/null 2>&1 || die "openssl not found in PATH"

  local ca_cert ca_key ca_srl client_key client_csr client_cert client_ext
  ca_cert="${MARIADB_SSL_DIR}/ca-cert.pem"
  ca_key="${MARIADB_SSL_DIR}/ca-key.pem"
  ca_srl="${MARIADB_SSL_DIR}/ca-cert.srl"
  client_key="${MARIADB_SSL_DIR}/client-key.pem"
  client_csr="${MARIADB_SSL_DIR}/client.csr"
  client_cert="${MARIADB_SSL_DIR}/client-cert.pem"
  client_ext="${MARIADB_SSL_DIR}/client-ext.cnf"

  [[ -f "${ca_cert}" ]] || die "Missing CA certificate: ${ca_cert}"
  [[ -f "${ca_key}" ]] || die "Missing CA private key: ${ca_key}"

  mkdir -p "${MARIADB_SSL_DIR}"

  if [[ "${FORCE_CLIENT_TLS_REGEN}" != true ]] && [[ -f "${client_key}" && -f "${client_cert}" ]]; then
    ok "Client TLS cert/key already present. Reusing existing files."
  else
    log "Generating client TLS key/certificate signed by ${ca_cert}"
    cat > "${client_ext}" <<'EOF'
extendedKeyUsage = clientAuth
keyUsage = digitalSignature,keyEncipherment
subjectAltName = DNS:koha,IP:127.0.0.1
EOF
    openssl genrsa -out "${client_key}" 2048 >/dev/null 2>&1
    openssl req -new -key "${client_key}" -subj "/CN=koha-client" -out "${client_csr}" >/dev/null 2>&1
    openssl x509 -req \
      -in "${client_csr}" \
      -CA "${ca_cert}" \
      -CAkey "${ca_key}" \
      -CAserial "${ca_srl}" \
      -out "${client_cert}" \
      -days 3650 \
      -sha256 \
      -extfile "${client_ext}" >/dev/null 2>&1
    rm -f "${client_csr}"
    ok "Client TLS certificate generated."
  fi

  # Readable by Apache CGI inside read-only bind mount.
  chmod 644 "${client_key}" "${client_cert}" "${client_ext}" 2>/dev/null || true

  _set_env_val "${KOHA_ENV_FILE}" "KOHA_DB_TLS_CLIENT_CERTIFICATE" "/etc/mysql/ssl/client-cert.pem"
  _set_env_val "${KOHA_ENV_FILE}" "KOHA_DB_TLS_CLIENT_KEY" "/etc/mysql/ssl/client-key.pem"
  reload_runtime_config

  ok "Configured ${KOHA_ENV_FILE} for Koha DB client TLS cert/key."
  log "Values set: KOHA_DB_TLS_CLIENT_CERTIFICATE=/etc/mysql/ssl/client-cert.pem"
  log "           KOHA_DB_TLS_CLIENT_KEY=/etc/mysql/ssl/client-key.pem"
}

koha_db_has_systempreferences() {
  local _has_systempreferences
  _has_systempreferences="$(docker exec "${DB_CONTAINER}" mysql -uroot -p"${KOHA_DB_ROOT_PASSWORD}" \
    --batch --skip-column-names -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='systempreferences';" 2>/dev/null || echo 0)"
  [[ "${_has_systempreferences}" == "1" ]]
}

koha_bootstrap_marker_present() {
  [[ -f "${BOOTSTRAP_MARKER}" ]]
}

# ---------------------------------------------------------------------------
# Volume identity (G6): make the selected Compose project and its data volumes
# explicit, and refuse destructive or silently-empty outcomes in prod mode.
# ---------------------------------------------------------------------------
shared_services_managed() {
  [[ "${KOHA_MANAGE_SHARED_SERVICES:-yes}" != "no" ]]
}

koha_db_volume_name()  { echo "${KOHA_COMPOSE_PROJECT}_koha-db-data"; }
koha_mq_volume_name()  { echo "${KOHA_COMPOSE_PROJECT}_koha-rabbitmq-data"; }

# Other default-scheme production projects that already own a database volume.
sibling_prod_projects() {
  docker volume ls -q 2>/dev/null \
    | sed -n 's/^\(koha-prod-.*\)_koha-db-data$/\1/p' \
    | grep -vxF -- "${KOHA_COMPOSE_PROJECT}" || true
}

show_volume_identity() {
  local vol
  hdr "Volume identity"
  log "Compose project : ${KOHA_COMPOSE_PROJECT} (mode: ${KOHA_IMAGE_MODE})"
  for vol in "$(koha_db_volume_name)" "$(koha_mq_volume_name)"; do
    if docker volume inspect "${vol}" >/dev/null 2>&1; then
      log "Volume (exists) : ${vol} (created $(docker volume inspect -f '{{.CreatedAt}}' "${vol}"))"
    else
      log "Volume (absent) : ${vol} (will be created empty on first start)"
    fi
  done
  local siblings; siblings="$(sibling_prod_projects)"
  if [[ -n "${siblings}" ]]; then
    log "Other koha-prod-* projects owning a database volume:"
    while IFS= read -r vol; do log "  - ${vol}"; done <<< "${siblings}"
  fi
}

# Version-specific default project names turn an upgrade into an empty
# deployment. Refuse unless the operator confirms a genuinely new deployment.
guard_prod_volume_identity() {
  [[ "${KOHA_IMAGE_MODE}" == "prod" ]] || return 0
  show_volume_identity
  if docker volume inspect "$(koha_db_volume_name)" >/dev/null 2>&1; then
    return 0
  fi
  local siblings; siblings="$(sibling_prod_projects)"
  [[ -n "${siblings}" ]] || return 0
  if [[ "${KOHA_ACCEPT_NEW_VOLUMES:-no}" == "yes" ]]; then
    warn "KOHA_ACCEPT_NEW_VOLUMES=yes: creating a new empty deployment next to: $(echo "${siblings}" | tr '\n' ' ')"
    return 0
  fi
  die "Project '${KOHA_COMPOSE_PROJECT}' has no database volume, but existing production data was found in project(s): $(echo "${siblings}" | tr '\n' ' ').
           This usually means the Koha version changed while KOHA_PROD_PROJECT is unset, which selects an EMPTY volume pair.
           To upgrade in place, set KOHA_PROD_PROJECT to the exact existing project name. For a deliberate new deployment, set KOHA_ACCEPT_NEW_VOLUMES=yes."
}

# After start, prove the running containers use exactly the expected volumes.
verify_running_volume_identity() {
  local container expected mount actual
  for pair in "${DB_CONTAINER}|/var/lib/mysql|$(koha_db_volume_name)" \
              "${KOHA_COMPOSE_PROJECT}-rabbitmq-1|/var/lib/rabbitmq|$(koha_mq_volume_name)"; do
    container="${pair%%|*}"; pair="${pair#*|}"; mount="${pair%%|*}"; expected="${pair#*|}"
    actual="$(docker inspect -f "{{range .Mounts}}{{if eq .Destination \"${mount}\"}}{{.Name}}{{end}}{{end}}" "${container}" 2>/dev/null || true)"
    if [[ "${actual}" != "${expected}" ]]; then
      die "Volume identity mismatch: ${container} mounts '${actual:-<none>}' at ${mount}, expected '${expected}'."
    fi
    ok "Verified ${container}:${mount} -> ${actual}"
  done
}

# Production data is only wiped after the operator types the exact project name.
confirm_prod_destructive() {
  local action="$1" answer
  warn "PRODUCTION project '${KOHA_COMPOSE_PROJECT}': ${action}"
  warn "This permanently destroys data in $(koha_db_volume_name)."
  read -rp "Type the Compose project name '${KOHA_COMPOSE_PROJECT}' to proceed: " answer || answer=""
  if [[ "${answer}" != "${KOHA_COMPOSE_PROJECT}" ]]; then
    log "Cancelled. Nothing was changed."
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Docker network
# Create the frontend network. Used for the main Koha + Traefik paths.
ensure_frontend_network() {
  if ! docker network inspect frontend >/dev/null 2>&1; then
    log "Creating 'frontend' Docker network (required by Traefik)..."
    docker network create frontend
    ok "Network 'frontend' created."
  else
    ok "Network 'frontend' already exists."
  fi
}

# Ensure required external networks exist before starting any stack that references
# them. Used by the Koha and OpenSearch compose files.
ensure_extra_networks() {
  local net name
  if [[ "${KOHA_MANAGE_SHARED_SERVICES:-yes}" == "no" ]]; then
    return 0
  fi
  for net in knonikl opensearch-36_osearch; do
    if ! docker network inspect "$net" >/dev/null 2>&1; then
      log "Creating '$net' Docker network..."
      docker network create "$net"
      ok "Network '$net' created."
    else
      ok "Network '$net' already exists."
    fi
  done
}

ensure_opensearch_certs() {
  hdr "Preparing OpenSearch certificates"

  local cert_dir="${OPENSEARCH_DIR}/assets/ssl"
  local generator="${OPENSEARCH_DIR}/opensearch_local_certificates_creator.sh"
  local config_file="${OPENSEARCH_DIR}/opensearch_installer_vars.cfg"
  local required_files=(
    root-ca.pem
    root-ca-key.pem
    admin.pem
    admin-key.pem
    os01.pem
    os01-key.pem
    os02.pem
    os02-key.pem
    os03.pem
    os03-key.pem
    os04.pem
    os04-key.pem
    os05.pem
    os05-key.pem
    dashboards.pem
    dashboards-key.pem
  )
  local file_path needs_regen=false

  [[ -f "${config_file}" ]] || die "Missing ${config_file}; OpenSearch certificates cannot be generated without it."
  mkdir -p "${cert_dir}"

  for file_name in "${required_files[@]}"; do
    file_path="${cert_dir}/${file_name}"
    if [[ -d "${file_path}" ]]; then
      warn "Removing directory at certificate path: ${file_path}"
      rm -rf "${file_path}"
      needs_regen=true
    elif [[ ! -f "${file_path}" ]]; then
      needs_regen=true
    fi
  done

  if [[ "${needs_regen}" == true ]]; then
    log "OpenSearch certs are missing or invalid; regenerating them now..."
    pushd "${OPENSEARCH_DIR}" > /dev/null
    bash ./opensearch_local_certificates_creator.sh
    popd > /dev/null
  else
    ok "OpenSearch certificates already present."
  fi

  for file_name in "${required_files[@]}"; do
    file_path="${cert_dir}/${file_name}"
    [[ -f "${file_path}" ]] || die "Expected OpenSearch certificate file missing or invalid: ${file_path}"
  done

  if [[ ! -f "${OPENSEARCH_DIR}/assets/local-config/internal_users.yml" || \
        ! -f "${OPENSEARCH_DIR}/assets/local-config/opensearch_dashboards.yml" ]]; then
    log "Generating missing OpenSearch authentication config without rotating certificates or touching data."
    bash "${OPENSEARCH_DIR}/prepare_local_auth_config.sh"
  fi
  [[ -f "${OPENSEARCH_DIR}/assets/local-config/internal_users.yml" ]] \
    || die "OpenSearch internal-user config was not generated."
  [[ -f "${OPENSEARCH_DIR}/assets/local-config/opensearch_dashboards.yml" ]] \
    || die "OpenSearch Dashboards config was not generated."

  ok "OpenSearch certificates ready."
}

sync_koha_opensearch_credentials() {
  if [[ "${KOHA_ELASTICSEARCH}" != "yes" ]]; then
    return 0
  fi

  [[ -n "${OS_ADMIN_PASS}" ]] \
    || die "Set OPENSEARCH_INITIAL_ADMIN_PASSWORD in the local OpenSearch environment file."
  if [[ -z "${KOHA_ELASTIC_OPTIONS}" ]]; then
    die "Set ELASTIC_OPTIONS in ${KOHA_ENV_FILE} when OpenSearch is enabled."
  fi

  ELASTIC_OPTIONS="$(OPENSEARCH_ADMIN_PASSWORD="${OS_ADMIN_PASS}" ELASTIC_OPTIONS="${KOHA_ELASTIC_OPTIONS}" python3 - <<'PY'
import os
import re

options = os.environ["ELASTIC_OPTIONS"]
password = os.environ["OPENSEARCH_ADMIN_PASSWORD"]
synced = re.sub(r'(<userinfo>admin:)[^<]*(</userinfo>)', r'\1' + password + r'\2', options, count=1)
print(synced)
PY
)"
  export OPENSEARCH_INITIAL_ADMIN_PASSWORD="${OS_ADMIN_PASS}"
  export ELASTIC_OPTIONS
  ok "Aligned Koha OpenSearch credentials with OpenSearch-3.6/.env."
}

ensure_opensearch_auth() {
  if [[ "${KOHA_ELASTICSEARCH}" != "yes" ]]; then
    return 0
  fi

  sync_koha_opensearch_credentials

  local auth_code
  auth_code="$(curl -ks -o /dev/null -w '%{http_code}' -u "admin:${OS_ADMIN_PASS}" \
    https://localhost:9200/_cluster/health?pretty || true)"

  if [[ "${auth_code}" == "200" ]]; then
    ok "OpenSearch auth probe succeeded (HTTP 200)."
    return 0
  fi

  if [[ "${auth_code}" == "401" ]]; then
    warn "OpenSearch returned HTTP 401. Reapplying security config and recreating os01..."
    pushd "${OPENSEARCH_DIR}" > /dev/null
    set -a
    source .env
    set +a
    bash ./initial_api_calls.sh
    docker compose up -d --force-recreate os01
    popd > /dev/null

    wait_opensearch_green

    auth_code="$(curl -ks -o /dev/null -w '%{http_code}' -u "admin:${OS_ADMIN_PASS}" \
      https://localhost:9200/_cluster/health?pretty || true)"
    [[ "${auth_code}" == "200" ]] || die "OpenSearch auth still returns HTTP ${auth_code} after security resync."
    ok "OpenSearch auth resynced and verified."
    return 0
  fi

  warn "OpenSearch auth probe returned HTTP ${auth_code}; continuing with current credentials."
}

# ---------------------------------------------------------------------------
# Traefik
# ---------------------------------------------------------------------------
start_traefik() {
  hdr "Starting Traefik reverse proxy"
  ensure_frontend_network
  # Bring up only if not already running
  if traefik_compose ps --status running traefik 2>/dev/null | grep -q traefik; then
    ok "Traefik is already running."
  else
    traefik_compose up -d traefik
    ok "Traefik started (HTTP :${TRAEFIK_HTTP_PORT}, dashboard :${TRAEFIK_DASHBOARD_PORT})."
  fi
}

stop_traefik() {
  hdr "Stopping Traefik"
  traefik_compose stop traefik 2>/dev/null || true
  ok "Traefik stopped."
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
build_opensearch() {
  local os_ver
  os_ver="$(_env_val "${OPENSEARCH_DIR}/.env" OPEN_SEARCH_VERSION 3.6.0)"
  hdr "Building OpenSearch image"
  log "Building single kosson/opensearch-icu:${os_ver} image with analysis-icu plugin..."
  pushd "${OPENSEARCH_DIR}" > /dev/null
  docker compose build os01
  popd > /dev/null
  ok "OpenSearch image built (kosson/opensearch-icu:${os_ver})."
}

build_koha() {
  hdr "Building Koha image"
  log "Image mode: ${KOHA_IMAGE_MODE}"
  if [[ "${KOHA_IMAGE_MODE}" == "prod" ]]; then
    log "Production image tag: ${KOHA_ALPINE_PROD_IMAGE_TAG}"
    log "Koha ref: ${KOHA_RELEASE_REF}"
  fi
  koha_compose build koha
  ok "Koha image built."
}

# ---------------------------------------------------------------------------
# OpenSearch
# ---------------------------------------------------------------------------
start_opensearch() {
  hdr "Starting OpenSearch 3.6 cluster"
  local os_ver os_img
  os_ver="$(_env_val "${OPENSEARCH_DIR}/.env" OPEN_SEARCH_VERSION 3.6.0)"
  os_img="kosson/opensearch-icu:${os_ver}"

  # Ensure first run works without Docker Hub access: build locally when missing.
  if ! docker image inspect "${os_img}" >/dev/null 2>&1; then
    log "Local image ${os_img} not found. Building it now (no Docker Hub login required)..."
    build_opensearch
  fi

  pushd "${OPENSEARCH_DIR}" > /dev/null
  # Start only core nodes first. dashboards depends_on os01:service_healthy;
  # starting everything at once can fail with "dependency os01 failed to start"
  # while the security plugin is still initializing.
  docker compose up -d os01 os02 os03 os04 os05
  popd > /dev/null
  ok "OpenSearch core nodes started (os01–os05)."
}

start_opensearch_dashboards() {
  hdr "Starting OpenSearch Dashboards"
  pushd "${OPENSEARCH_DIR}" > /dev/null
  docker compose up -d dashboards
  popd > /dev/null
  ok "OpenSearch Dashboards started."
}

wait_opensearch_green() {
  log "Waiting for OpenSearch cluster to reach green status..."
  warn "This may take up to 5 minutes on first start (security plugin initialises)."
  local attempts=0 max=72  # 6 minutes (72 × 5 s)
  while (( attempts < max )); do
    if curl -sk -u "admin:${OS_ADMIN_PASS}" \
        https://localhost:9200/_cluster/health 2>/dev/null \
        | grep -q '"status":"green"'; then
      echo ""
      ok "OpenSearch cluster is green."
      return 0
    fi
    (( ++attempts ))
    printf "\r  [%d/%d] waiting..." "${attempts}" "${max}"
    sleep 5
  done
  echo ""
  die "OpenSearch cluster did not reach green status after $(( max * 5 )) seconds."
}

stop_opensearch() {
  hdr "Stopping OpenSearch cluster"
  pushd "${OPENSEARCH_DIR}" > /dev/null
  docker compose down
  popd > /dev/null
  ok "OpenSearch stopped."
}

# ---------------------------------------------------------------------------
# MariaDB + Memcached
# ---------------------------------------------------------------------------
start_support_services() {
  hdr "Starting MariaDB + Memcached"
  ensure_extra_networks
  koha_compose up -d db memcached
  ok "Support services started."
}

wait_db_ready() {
  log "Waiting for MariaDB to accept connections..."
  local attempts=0 max=30  # 60 seconds
  while (( attempts < max )); do
    if docker exec "${DB_CONTAINER}" \
        mysql -uroot -p"${KOHA_DB_ROOT_PASSWORD}" \
        --batch --skip-column-names -e 'SELECT 1;' >/dev/null 2>&1; then
      ok "MariaDB is ready."
      return 0
    fi
    (( ++attempts ))
    printf "\r  [%d/%d] waiting..." "${attempts}" "${max}"
    sleep 2
  done
  echo ""
  die "MariaDB did not become ready after $(( max * 2 )) seconds. Check KOHA_DB_ROOT_PASSWORD in env/.env. If koha-db-data already exists from an older password, run './$(basename "$0") reset' (destructive) or restore the old password in env/.env."
}

reset_database() {
  hdr "Recreating Koha database"
  rm -f "${BOOTSTRAP_MARKER}" 2>/dev/null || true
  log "Dropping and recreating '${DB_NAME}'..."
  docker exec "${DB_CONTAINER}" mysql -uroot -p"${KOHA_DB_ROOT_PASSWORD}" -e "
    DROP DATABASE IF EXISTS ${DB_NAME};
    CREATE DATABASE ${DB_NAME}
      CHARACTER SET utf8mb4
      COLLATE utf8mb4_unicode_ci;
    GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';
    FLUSH PRIVILEGES;" || die "MariaDB root authentication failed while recreating ${DB_NAME}. Verify KOHA_DB_ROOT_PASSWORD in env/.env matches the password used when the existing koha-db-data volume was first initialized."
  ok "Database '${DB_NAME}' ready."
}

rabbitmq_running() {
  [[ -n "$(koha_compose ps --status running -q rabbitmq 2>/dev/null)" ]]
}

wait_rabbitmq_ready() {
  local i
  for i in $(seq 1 60); do
    if koha_compose exec -T rabbitmq rabbitmq-diagnostics -q check_running >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  die "RabbitMQ did not become ready."
}

# RABBITMQ_DEFAULT_* only seed an empty volume, so a restored or rotated
# volume must be reconciled with the credentials Koha will be given.
reconcile_rabbitmq_credentials() {
  log "Reconciling RabbitMQ user, vhost and permissions with the restored configuration..."
  koha_compose up -d rabbitmq
  wait_rabbitmq_ready
  koha_compose exec -T rabbitmq sh -c '
    set -e
    u="$RABBITMQ_DEFAULT_USER"; p="$RABBITMQ_DEFAULT_PASS"; v="$RABBITMQ_DEFAULT_VHOST"
    rabbitmqctl -q list_vhosts --no-table-headers | grep -qx -- "$v" || rabbitmqctl -q add_vhost "$v"
    if rabbitmqctl -q list_users --no-table-headers | cut -f1 | grep -qx -- "$u"; then
      rabbitmqctl -q change_password "$u" "$p"
    else
      rabbitmqctl -q add_user "$u" "$p"
    fi
    rabbitmqctl -q set_user_tags "$u" administrator
    rabbitmqctl -q set_permissions -p "$v" "$u" ".*" ".*" ".*"
  ' >/dev/null || die "Could not reconcile RabbitMQ credentials."
  ok "RabbitMQ credentials reconciled."
}

backup_rabbitmq_definitions() {
  local dest_dir="$1"
  mkdir -p "${dest_dir}"
  if ! rabbitmq_running; then
    koha_compose up -d rabbitmq >/dev/null 2>&1 || true
  fi
  if rabbitmq_running; then wait_rabbitmq_ready; else
    warn "RabbitMQ could not be started; broker definitions were not included in the backup."
    return 0
  fi
  if ( umask 077; koha_compose exec -T rabbitmq rabbitmqctl -q export_definitions - > "${dest_dir}/definitions.json" 2>/dev/null ) \
    && [[ -s "${dest_dir}/definitions.json" ]]; then
    chmod 0600 "${dest_dir}/definitions.json"
    ok "RabbitMQ definitions exported (users, vhosts, permissions; queue contents are transient)."
  else
    warn "RabbitMQ definitions export failed; continuing without it."
  fi
}

# Host-side assets (TLS keys/certificates, CA bundles) that live outside the
# database and env files. Paths come from KOHA_BACKUP_ASSET_PATHS (space
# separated, absolute) in the environment or the main Koha env file.
backup_asset_paths() {
  local paths="${KOHA_BACKUP_ASSET_PATHS:-$(_env_val "${KOHA_ENV_FILE}" KOHA_BACKUP_ASSET_PATHS "")}"
  echo "${paths}"
}

backup_host_assets() {
  local dest_dir="$1" path rel
  local paths; paths="$(backup_asset_paths)"
  [[ -n "${paths}" ]] || return 0
  mkdir -p "${dest_dir}"
  : > "${dest_dir}/paths.txt"
  local rels=()
  for path in ${paths}; do
    [[ "${path}" == /* ]] || die "KOHA_BACKUP_ASSET_PATHS entries must be absolute: ${path}"
    [[ -e "${path}" ]] || die "Backup asset path does not exist: ${path}"
    rel="${path#/}"
    echo "${path}" >> "${dest_dir}/paths.txt"
    rels+=( "${rel}" )
  done
  ( umask 077; tar -C / -cpf "${dest_dir}/assets.tar" "${rels[@]}" )
  chmod 0600 "${dest_dir}/paths.txt" "${dest_dir}/assets.tar"
  ok "Host assets archived: $(wc -l < "${dest_dir}/paths.txt") path(s) (modes preserved)."
}

restore_host_assets() {
  local src_dir="$1" root="${KOHA_ASSET_RESTORE_ROOT:-/}"
  [[ -f "${src_dir}/assets.tar" ]] || { warn "No host assets in this backup."; return 0; }
  log "Restoring host assets under ${root} (modes preserved)..."
  mkdir -p "${root}"
  tar -C "${root}" -xpf "${src_dir}/assets.tar"
  ok "Host assets restored."
}

# Optional off-host protection: set KOHA_BACKUP_GPG_RECIPIENT to encrypt the
# finished archive to a public key (output gets a .gpg suffix).
encrypt_backup_archive() {
  local archive="$1" recipient="${KOHA_BACKUP_GPG_RECIPIENT:-}"
  [[ -n "${recipient}" ]] || return 0
  command -v gpg >/dev/null 2>&1 || die "KOHA_BACKUP_GPG_RECIPIENT is set but gpg is not installed."
  ( umask 077; gpg --batch --yes --trust-model always --encrypt --recipient "${recipient}" --output "${archive}.gpg" "${archive}" ) \
    || die "GPG encryption failed."
  chmod 0600 "${archive}.gpg"
  rm -f "${archive}"
  ok "Backup encrypted to ${archive}.gpg (plaintext archive removed)."
}

create_backup_bundle() {
  hdr "Creating backup bundle"

  local output_path stage_dir timestamp
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  output_path="${BACKUP_OUTPUT:-${BACKUP_ROOT}/koha-backup-${timestamp}.tar.gz}"

  mkdir -p "${BACKUP_ROOT}" "$(dirname "${output_path}")"
  stage_dir="$(mktemp -d)"
  trap 'rm -rf "${stage_dir}"' RETURN

  start_support_services
  wait_db_ready

  mkdir -p "${stage_dir}/config" "${stage_dir}/database"
  cp "${KOHA_ENV_FILE}" "${stage_dir}/config/env.env"
  cp "${TRAEFIK_DIR}/.env" "${stage_dir}/config/traefik.env"
  cp "${OPENSEARCH_DIR}/.env" "${stage_dir}/config/opensearch.env"
  chmod 0600 \
    "${stage_dir}/config/env.env" \
    "${stage_dir}/config/traefik.env" \
    "${stage_dir}/config/opensearch.env"

  cat > "${stage_dir}/manifest.txt" <<EOF
created_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
repo_root=${SCRIPT_DIR}
koha_instance=${KOHA_INSTANCE}
database=${DB_NAME}
includes=env/.env, traefik/.env, OpenSearch-3.6/.env, database dump, rabbitmq definitions, optional host assets
EOF

  log "Dumping MariaDB database '${DB_NAME}'..."
  docker exec "${DB_CONTAINER}" \
    mysqldump -uroot -p"${KOHA_DB_ROOT_PASSWORD}" \
    --single-transaction --routines --triggers --events "${DB_NAME}" \
    | gzip -9 > "${stage_dir}/database/${DB_NAME}.sql.gz"

  backup_rabbitmq_definitions "${stage_dir}/rabbitmq"
  backup_host_assets "${stage_dir}/assets"

  chmod 0700 "${stage_dir}/config" "${stage_dir}/database" "${stage_dir}/rabbitmq"
  [[ ! -d "${stage_dir}/assets" ]] || chmod 0700 "${stage_dir}/assets"
  chmod 0600 \
    "${stage_dir}/manifest.txt" \
    "${stage_dir}/database/${DB_NAME}.sql.gz"

  log "Packing backup archive at ${output_path}..."
  ( umask 077; tar -C "${stage_dir}" -czf "${output_path}" . )
  chmod 0600 "${output_path}"
  encrypt_backup_archive "${output_path}"

  rm -rf "${stage_dir}"
  trap - RETURN

  ok "Backup written to ${output_path}$( [[ -n "${KOHA_BACKUP_GPG_RECIPIENT:-}" ]] && echo .gpg )"
}

restore_backup_bundle() {
  hdr "Restoring backup bundle"

  local archive_path stage_dir
  [[ -n "${RESTORE_ARCHIVE}" ]] || die "restore requires a backup archive path. Use: ./$(basename "$0") restore /path/to/koha-backup.tar.gz"
  archive_path="${RESTORE_ARCHIVE}"
  [[ -f "${archive_path}" ]] || die "Backup archive not found: ${archive_path}"

  show_volume_identity
  warn "This will overwrite env/.env, traefik/.env and OpenSearch-3.6/.env, then recreate '${DB_NAME}' in project '${KOHA_COMPOSE_PROJECT}'."
  warn "Any running containers should be stopped before restoring."
  echo ""
  read -rp "Type 'restore' to continue: " answer
  if [[ "${answer}" != "restore" ]]; then
    log "Restore cancelled."
    return 0
  fi

  stop_koha
  stop_support_services
  if [[ "${KOHA_MANAGE_SHARED_SERVICES:-yes}" != "no" ]]; then
    stop_opensearch
    stop_traefik
  fi

  stage_dir="$(mktemp -d)"
  trap 'rm -rf "${stage_dir}"' RETURN

  if [[ "${archive_path}" == *.gpg ]]; then
    command -v gpg >/dev/null 2>&1 || die "gpg is required to restore an encrypted archive."
    ( umask 077; gpg --batch --yes --decrypt --output "${stage_dir}/archive.tar.gz" "${archive_path}" ) \
      || die "GPG decryption failed."
    archive_path="${stage_dir}/archive.tar.gz"
  fi
  tar -xzf "${archive_path}" -C "${stage_dir}" --exclude=./archive.tar.gz

  [[ -f "${stage_dir}/config/env.env" ]] || die "Backup archive is missing config/env.env"
  [[ -f "${stage_dir}/config/traefik.env" ]] || die "Backup archive is missing config/traefik.env"
  [[ -f "${stage_dir}/config/opensearch.env" ]] || die "Backup archive is missing config/opensearch.env"

  cp "${stage_dir}/config/env.env" "${KOHA_ENV_FILE}"
  cp "${stage_dir}/config/traefik.env" "${TRAEFIK_DIR}/.env"
  cp "${stage_dir}/config/opensearch.env" "${OPENSEARCH_DIR}/.env"
  chmod 0600 "${KOHA_ENV_FILE}" "${TRAEFIK_DIR}/.env" "${OPENSEARCH_DIR}/.env"

  reload_runtime_config
  if [[ "${KOHA_IMAGE_MODE}" == "dev" ]]; then
    ensure_koha_source
  fi

  ok "Configuration files restored."
  restore_host_assets "${stage_dir}/assets"

  start_support_services
  wait_db_ready
  reset_database

  if [[ -f "${stage_dir}/database/${DB_NAME}.sql.gz" ]]; then
    log "Importing MariaDB dump into '${DB_NAME}'..."
    gzip -dc "${stage_dir}/database/${DB_NAME}.sql.gz" | \
      docker exec -i "${DB_CONTAINER}" mysql -uroot -p"${KOHA_DB_ROOT_PASSWORD}" "${DB_NAME}"
    ok "Database restored."
  else
    warn "No database dump found in the backup archive; the database was only reinitialized."
  fi

  if [[ "${KOHA_MANAGE_SHARED_SERVICES:-yes}" != "no" ]]; then
    ensure_opensearch_certs
    start_traefik
    start_opensearch
    wait_opensearch_green
    ensure_opensearch_auth
    start_opensearch_dashboards
  else
    log "KOHA_MANAGE_SHARED_SERVICES=no: shared Traefik/OpenSearch left untouched."
  fi

  export USE_EXISTING_DB=yes
  start_koha
  verify_running_volume_identity
  configure_koha_languages

  rm -rf "${stage_dir}"
  trap - RETURN

  if [[ "${FOLLOW_LOGS}" == true ]]; then
    follow_logs
  fi

  ok "Restore complete. The stack has been brought back up."
}

stop_support_services() {
  hdr "Stopping MariaDB + Memcached"
  koha_compose stop db memcached 2>/dev/null || true
  ok "Support services stopped."
}

reset_all() {
  if [[ "${KOHA_IMAGE_MODE}" == "prod" ]]; then
    show_volume_identity
    confirm_prod_destructive "'reset' removes this project's containers AND volumes." || return 0
  fi
  warn "This will stop ALL containers, remove them, and delete ALL named volumes."
  warn "Database data, OpenSearch indices, and Traefik state will be permanently lost."
  warn "Docker images will be preserved."
  echo ""
  read -rp "Type 'yes' to confirm: " answer
  if [[ "${answer}" != "yes" ]]; then
    log "Reset cancelled."
    return 0
  fi

  hdr "Removing Koha containers and volumes"
  koha_compose down --volumes 2>/dev/null || true
  ok "Koha stack removed."

  hdr "Removing OpenSearch containers and volumes"
  os_compose down --volumes 2>/dev/null || true
  ok "OpenSearch stack removed."

  hdr "Removing Traefik containers"
  # Traefik has no named volumes; --volumes is a no-op but included for consistency.
  traefik_compose down --volumes 2>/dev/null || true
  ok "Traefik removed."

  echo ""
  ok "Reset complete. All containers and volumes removed. Images are intact."
}

# ---------------------------------------------------------------------------
# Koha container
# ---------------------------------------------------------------------------
start_koha() {
  hdr "Starting Koha container"
  # Export LOAD_DEMO_DATA so Docker Compose picks it up via the environment: block
  # in docker-compose-alpinekoha.yml, overriding whatever is in env/.env at this point.
  export LOAD_DEMO_DATA
  local demo_label; demo_label="$( [[ "${LOAD_DEMO_DATA}" == "no" ]] && echo "clean (no demo data)" || echo "with demo data" )"
  log "Demo data mode: ${demo_label}"
  reconcile_rabbitmq_credentials
  koha_compose up -d --force-recreate koha
  ok "Koha container started (${demo_label})."
}

stop_koha() {
  hdr "Stopping Koha container"
  koha_compose stop koha 2>/dev/null || true
  ok "Koha container stopped."
}

follow_logs() {
  hdr "Koha startup logs"
  warn "Startup takes 5–15 minutes. Watching for key milestones..."
  warn "Press Ctrl-C at any time to detach — the stack will keep running."
  echo ""

  # Stream logs and annotate milestones on the fly
  koha_compose logs -f koha 2>&1 | while IFS= read -r line; do
    echo "${line}"
    case "${line}" in
      *"koha-testing-docker has started up"*)
        local proto="http"
        local port_suffix=""
        if [[ -n "${TLS_CERTRESOLVER}" ]]; then
          proto="https"
          [[ "${TRAEFIK_HTTPS_PORT}" != "443" ]] && port_suffix=":${TRAEFIK_HTTPS_PORT}"
        else
          [[ "${TRAEFIK_HTTP_PORT}" != "80" ]] && port_suffix=":${TRAEFIK_HTTP_PORT}"
        fi
        echo ""
        echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${GREEN}${BOLD}║   Stack fully started and ready!                         ║${RESET}"
        echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}  Via Traefik (recommended):║${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}    OPAC    : ${proto}://${KOHA_INSTANCE}${KOHA_DOMAIN}${port_suffix}║${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}    Staff   : ${proto}://${KOHA_INSTANCE}${KOHA_INTRANET_SUFFIX}${KOHA_DOMAIN}${port_suffix}║${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}  Direct (fallback, no DNS needed):║${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}    OPAC    : http://localhost:${KOHA_OPAC_PORT}║${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}    Staff   : http://localhost:${KOHA_INTRANET_PORT}║${RESET}"
        local login_note="${KOHA_USER} / ${KOHA_PASS}"
        [[ "${KOHA_IMAGE_MODE}" == "prod" ]] && login_note="${KOHA_USER} / (password from ${KOHA_ENV_FILE##*/})"
        echo -e "${GREEN}${BOLD}║${RESET}  Login     : ${login_note}║${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}  Dashbrd   : ${proto}://${DASHBOARDS_DOMAIN}${port_suffix}║${RESET}"
        echo -e "${GREEN}${BOLD}║${RESET}  Traefik   : http://localhost:${TRAEFIK_DASHBOARD_PORT}║${RESET}"
        local demo_note; demo_note="$( [[ "${LOAD_DEMO_DATA:-yes}" == "no" ]] && echo "clean (no demo data)" || echo "with demo data" )"
        echo -e "${GREEN}${BOLD}║${RESET}  Catalogue : ${demo_note}║${RESET}"
        echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
show_status() {
  hdr "Container status"
  echo ""
  echo -e "${BOLD}── Koha stack ──────────────────────────────${RESET}"
  koha_compose ps 2>/dev/null || echo "  (not running)"
  echo ""
  echo -e "${BOLD}── OpenSearch cluster ──────────────────────${RESET}"
  os_compose ps 2>/dev/null || echo "  (not running)"
  echo ""
  echo -e "${BOLD}── OpenSearch health ───────────────────────${RESET}"
  local health
  health=$(curl -sk -u "admin:${OS_ADMIN_PASS}" \
    https://localhost:9200/_cluster/health 2>/dev/null || echo '{"error":"unreachable"}')
  echo "${health}" | python3 -m json.tool 2>/dev/null || echo "${health}"
  echo ""
  echo -e "${BOLD}── Traefik ──────────────────────────────────${RESET}"
  traefik_compose ps 2>/dev/null || echo "  (not running)"
  echo ""
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF

${BOLD}stack-alpine.sh${RESET} — Manage the Alpine Koha stack + optional OpenSearch/Traefik services

${BOLD}Usage:${RESET}
  $(basename "$0") <command> [options]

${BOLD}Commands:${RESET}
  start       Start the full stack (default when no command given)
  stop        Stop all services (OpenSearch + Koha stack)
  restart     Quick restart: reset DB + recreate Koha container only
              (skips OpenSearch restart — use when OS is already running)
  tls-client-cert
              Generate/reuse MariaDB client TLS cert/key and wire env/.env
  reset       Stop everything, remove all containers and named volumes
              (requires confirmation; images are preserved)
  status      Show running containers and OpenSearch cluster health
  logs        Tail Koha container logs
  build       Build images without starting anything
  latest-tag  Show the latest upstream Koha tag; --apply [<tag>] writes it to env/.env
  backup      Create a tar.gz backup bundle for env files + MariaDB data
  restore     Restore env files + MariaDB data from a backup bundle
  volumes     Show the Compose project and the exact data volumes it selects

${BOLD}Options for 'start' and 'build':${RESET}
  --image-mode <dev|prod>
                        Choose compose/build mode (default: dev)
  --koha-version <ver>  Production version label (for example 26.11.00)
  --koha-ref <ref>      Production git ref/tag/commit (for example v26.11.00)
  KOHA_PROD_PROJECT     Optional stable production Compose project name.
                        Defaults to a version-specific project when unset.
  KOHA_ACCEPT_NEW_VOLUMES=yes
                        Allow prod start to create a new empty deployment even
                        though other koha-prod-* projects own data (the guard
                        otherwise refuses; see 'volumes').
  KOHA_ENV_FILE          Host-side Koha configuration path (default: env/.env).
  KOHA_CONTAINER_ENV_FILE
                        Koha container env file (defaults to KOHA_ENV_FILE).
  --build-opensearch    Rebuild the kosson/opensearch-icu image (analysis-icu plugin)
  --build-koha          Rebuild the Koha image for the selected --image-mode
  --build               Rebuild both OpenSearch and Koha images
  --no-fresh-db         Skip the database drop/recreate (preserve existing data)
  --bootstrap-profile <resume|full>
                        Alpine existing-DB startup mode:
                        resume (default) -> skip full population/reindex
                        full             -> force full do_all_you_can_do path
  --no-logs             Do not tail Koha startup logs after starting
  --with-demo-data      Load sample MARC records, items, and patron data (default)
  --no-demo-data        Start with an empty catalogue — superlibrarian account only
  --prepare-db-client-tls
                        Ensure files-alpine/mariadb-ssl/client-{cert,key}.pem exist
                        and auto-set KOHA_DB_TLS_CLIENT_{CERTIFICATE,KEY} in env/.env
  --force-client-tls-regen
                        Regenerate client TLS cert/key even if already present

${BOLD}Koha source bootstrap (env/.env):${RESET}
  SYNC_REPO             Host path for Koha source (auto-cloned if missing)
  KOHA_GIT_CLONE_MODE   tag | branch
  KOHA_GIT_TAG          Required when clone mode is 'tag'
  KOHA_GIT_BRANCH       Required when clone mode is 'branch' (e.g. main)
  KOHA_GIT_DEPTH        Shallow clone depth (positive integer)
  KOHA_GIT_URL          Optional override for forks/mirrors

${BOLD}Koha language automation (env/.env):${RESET}
  KOHA_DESIRED_LANGUAGES       Comma list for final UI languages (e.g. en,es-ES,ro-RO)
  KOHA_OPAC_LANGUAGES_DISPLAY  1 to show OPAC language chooser, 0 to hide it
  KOHA_TRANSLATIONS_REINSTALL  yes to reinstall packs on every start, no to install missing only

${BOLD}Examples:${RESET}
  $(basename "$0") start                    # Fresh DB + demo data, follow logs
  $(basename "$0") start --image-mode prod --koha-version 26.11.00 --koha-ref v26.11.00
  $(basename "$0") start --no-demo-data     # Fresh DB, clean catalogue (no sample records)
  $(basename "$0") start --with-demo-data   # Explicitly load demo data (same as default)
  $(basename "$0") start --build            # Rebuild all images, then start
  $(basename "$0") start --build-opensearch # Rebuild OS images only, then start
  $(basename "$0") start --no-fresh-db      # Restart without wiping the database
  $(basename "$0") start --bootstrap-profile full
  $(basename "$0") start --no-logs          # Start without tailing logs
  $(basename "$0") start --prepare-db-client-tls
  $(basename "$0") tls-client-cert
  $(basename "$0") tls-client-cert --force-client-tls-regen
  KOHA_DESIRED_LANGUAGES=en,es-ES,ro-RO $(basename "$0") start
  $(basename "$0") restart                  # Quick restart (DB reset + koha only)
  $(basename "$0") restart --no-demo-data   # Quick restart, clean catalogue
  $(basename "$0") stop                     # Stop everything
  $(basename "$0") reset                    # Nuclear reset: remove all containers + volumes
  $(basename "$0") status                   # Check what's running
  $(basename "$0") logs                     # Attach to Koha logs
  $(basename "$0") build --build-opensearch # Build OS images only
  $(basename "$0") build --image-mode prod --koha-version 26.11.00 --koha-ref v26.11.00 --build-koha
  $(basename "$0") backup                   # Create a backup in ./backups
  $(basename "$0") backup --output /tmp/koha-backup.tar.gz
  $(basename "$0") restore backups/koha-backup-YYYYMMDDTHHMMSSZ.tar.gz
  $(basename "$0") latest-tag               # Show the latest Koha release tag
  $(basename "$0") latest-tag --apply       # Write latest tag to env/.env, then build with build --image-mode prod --build-koha
  $(basename "$0") latest-tag --apply v25.11.06-1  # Pin a specific release in env/.env

EOF
}

# ---------------------------------------------------------------------------
# Command dispatcher
# ---------------------------------------------------------------------------

# Default command
COMMAND="start"
BUILD_OPENSEARCH=false
BUILD_KOHA=false
FRESH_DB=true
FOLLOW_LOGS=true
BACKUP_OUTPUT=""
RESTORE_ARCHIVE=""
PREPARE_DB_CLIENT_TLS=false
FORCE_CLIENT_TLS_REGEN=false
APPLY_LATEST_TAG=false
KOHA_TAG_TO_APPLY=""
# Read LOAD_DEMO_DATA from env/.env (default 'yes'); --no-demo-data / --with-demo-data override
LOAD_DEMO_DATA="$(_env_val "${KOHA_ENV_FILE}" LOAD_DEMO_DATA yes)"
ALPINE_BOOTSTRAP_PROFILE="$(_env_val "${KOHA_ENV_FILE}" ALPINE_BOOTSTRAP_PROFILE resume)"

# Parse command (first positional arg)
if [[ $# -gt 0 ]]; then
  case "$1" in
    start|stop|restart|reset|status|logs|build|backup|restore|volumes|tls-client-cert|latest-tag) COMMAND="$1"; shift ;;
    --help|-h) usage; exit 0 ;;
    --*) : ;;  # no subcommand given, use default "start"
    *) die "Unknown command: '$1'. Run '$(basename "$0") --help' for usage." ;;
  esac
fi

# Parse remaining options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image-mode)
      [[ $# -ge 2 ]] || die "--image-mode requires a value: dev|prod"
      KOHA_IMAGE_MODE="$2"
      shift ;;
    --koha-version)
      [[ $# -ge 2 ]] || die "--koha-version requires a value"
      KOHA_RELEASE_VERSION="$2"
      shift ;;
    --koha-ref)
      [[ $# -ge 2 ]] || die "--koha-ref requires a value"
      KOHA_RELEASE_REF="$2"
      shift ;;
    --build-opensearch)  BUILD_OPENSEARCH=true ;;
    --build-koha)        BUILD_KOHA=true ;;
    --build)             BUILD_OPENSEARCH=true; BUILD_KOHA=true ;;
    --no-fresh-db)       FRESH_DB=false ;;
    --bootstrap-profile)
      [[ $# -ge 2 ]] || die "--bootstrap-profile requires a value: resume|full"
      ALPINE_BOOTSTRAP_PROFILE="$2"
      shift ;;
    --no-logs)           FOLLOW_LOGS=false ;;
    --no-demo-data)      LOAD_DEMO_DATA=no ;;
    --with-demo-data)    LOAD_DEMO_DATA=yes ;;
    --prepare-db-client-tls) PREPARE_DB_CLIENT_TLS=true ;;
    --force-client-tls-regen) FORCE_CLIENT_TLS_REGEN=true; PREPARE_DB_CLIENT_TLS=true ;;
    --apply)
      APPLY_LATEST_TAG=true
      # optional explicit tag: --apply v25.11.06-1
      if [[ $# -ge 2 && "${2}" != --* ]]; then
        KOHA_TAG_TO_APPLY="$2"; shift
      fi
      ;;
    --output)
      [[ $# -ge 2 ]] || die "--output requires a file path"
      BACKUP_OUTPUT="$2"
      shift ;;
    --input)
      [[ $# -ge 2 ]] || die "--input requires a backup archive path"
      RESTORE_ARCHIVE="$2"
      shift ;;
    --help|-h)           usage; exit 0 ;;
    *)
      if [[ "${COMMAND}" == "restore" && -z "${RESTORE_ARCHIVE}" ]]; then
        RESTORE_ARCHIVE="$1"
      else
        die "Unknown option: '$1'. Run '$(basename "$0") --help' for usage."
      fi
      ;;
  esac
  shift
done

ALPINE_BOOTSTRAP_PROFILE="$(echo "${ALPINE_BOOTSTRAP_PROFILE}" | tr '[:upper:]' '[:lower:]')"
case "${ALPINE_BOOTSTRAP_PROFILE}" in
  resume|full) ;;
  *) die "Invalid --bootstrap-profile '${ALPINE_BOOTSTRAP_PROFILE}'. Use resume or full." ;;
esac

configure_koha_mode

# ---------------------------------------------------------------------------
# Execute
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}${CYAN}╔════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║   Alpine Koha Stack Manager        ║${RESET}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════╝${RESET}"
echo ""
log "Mode: ${KOHA_IMAGE_MODE} | Compose project: ${KOHA_COMPOSE_PROJECT}"
if [[ "${KOHA_IMAGE_MODE}" == "prod" ]]; then
  log "Prod image: ${KOHA_ALPINE_PROD_IMAGE_TAG} | Ref: ${KOHA_RELEASE_REF}"
fi

case "${COMMAND}" in

  start)
    if [[ "${KOHA_DB_ROOT_PASSWORD}" == "change_me_before_first_start" ]]; then
      die "Default placeholder password detected for KOHA_DB_ROOT_PASSWORD in env/.env.
           Please edit env/.env and set a secure password before the first start."
    fi

    check_prereqs
    guard_prod_volume_identity
    [[ "${PREPARE_DB_CLIENT_TLS}" == true ]] && prepare_mariadb_client_tls
    if [[ "${KOHA_IMAGE_MODE}" == "dev" ]]; then
      ensure_koha_source
    fi
    [[ "${BUILD_OPENSEARCH}" == true ]] && build_opensearch
    [[ "${BUILD_KOHA}"       == true ]] && build_koha
    if shared_services_managed; then
      ensure_opensearch_certs
      start_traefik
      start_opensearch
      wait_opensearch_green
      ensure_opensearch_auth
      start_opensearch_dashboards
    else
      log "KOHA_MANAGE_SHARED_SERVICES=no: shared Traefik/OpenSearch left untouched."
    fi
    start_support_services
    wait_db_ready
    if [[ "${FRESH_DB}" == true ]]; then
      # Warn the user if the database already contains Koha data — an accidental
      # plain 'start' after a machine reboot would silently wipe everything.
      if koha_db_has_systempreferences && [[ "${KOHA_IMAGE_MODE}" == "prod" ]]; then
        confirm_prod_destructive "'start' would DROP and recreate database '${DB_NAME}'. Use --no-fresh-db to keep it." || exit 0
      elif koha_db_has_systempreferences; then
        echo ""
        warn "Database '${DB_NAME}' already contains Koha data."
        warn "Proceeding will DROP and recreate it — ALL DATA WILL BE PERMANENTLY LOST."
        warn "To resume without wiping, press n and run:  ./$(basename "$0") start --no-fresh-db"
        echo ""
        read -rp "$(echo -e "${RED}Type 'yes' to wipe the database and continue, or anything else to cancel:${RESET} ")" _confirm
        echo ""
        if [[ "${_confirm}" != "yes" ]]; then
          log "Start cancelled. Resume with existing data: ./$(basename "$0") start --no-fresh-db"
          exit 0
        fi
      fi
      reset_database
    else
      # Tell run.sh the DB already has data only when that is actually true.
      # On a zero-state machine, fall back to a fresh bootstrap instead of
      # skipping do_all_you_can_do.pl and leaving Auth/session setup incomplete.
      if koha_db_has_systempreferences; then
        export USE_EXISTING_DB=yes
        if koha_bootstrap_marker_present; then
          log "--no-fresh-db: bootstrap marker present, reusing existing DB"
        else
          export ALPINE_BOOTSTRAP_PROFILE=full
          log "--no-fresh-db: bootstrap marker missing, forcing full bootstrap on existing DB"
        fi
      else
        warn "--no-fresh-db requested, but ${DB_NAME} is still empty; falling back to fresh bootstrap."
        reset_database
      fi
    fi
    if [[ "${ALPINE_BOOTSTRAP_PROFILE}" == "full" ]]; then
      export RUN_DB_POPULATION_ON_EXISTING_DB=yes
      log "Alpine bootstrap profile: full (forcing DB population/reindex on existing DB)"
    else
      export RUN_DB_POPULATION_ON_EXISTING_DB=no
      log "Alpine bootstrap profile: resume (skipping full DB population/reindex on existing DB)"
    fi
    export ALPINE_BOOTSTRAP_PROFILE
    start_koha
    verify_running_volume_identity
    configure_koha_languages
    echo ""
    log "Koha container is running and initialising."
    [[ "${FOLLOW_LOGS}" == true ]] && follow_logs
    ;;

  stop)
    stop_koha
    stop_support_services
    if shared_services_managed; then
      stop_opensearch
      stop_traefik
    fi
    ok "All services stopped."
    ;;

  reset)
    reset_all
    ;;

  restart)
    check_prereqs
    [[ "${PREPARE_DB_CLIENT_TLS}" == true ]] && prepare_mariadb_client_tls
    if [[ "${KOHA_IMAGE_MODE}" == "dev" ]]; then
      ensure_koha_source
    fi
    guard_prod_volume_identity
    hdr "Quick restart (OpenSearch stays up)"
    warn "Assumes OpenSearch cluster is already running and green."
    wait_db_ready
    if [[ "${FRESH_DB}" == true ]]; then
      if [[ "${KOHA_IMAGE_MODE}" == "prod" ]] && koha_db_has_systempreferences; then
        confirm_prod_destructive "'restart' would DROP and recreate database '${DB_NAME}'. Use --no-fresh-db to keep it." || exit 0
      fi
      reset_database
    elif koha_db_has_systempreferences; then
      export USE_EXISTING_DB=yes
      if koha_bootstrap_marker_present; then
        log "restart --no-fresh-db: bootstrap marker present, reusing existing DB"
      else
        export ALPINE_BOOTSTRAP_PROFILE=full
        log "restart --no-fresh-db: bootstrap marker missing, forcing full bootstrap on existing DB"
      fi
    else
      warn "restart --no-fresh-db requested, but ${DB_NAME} is empty; falling back to fresh bootstrap."
      reset_database
    fi
    if [[ "${ALPINE_BOOTSTRAP_PROFILE}" == "full" ]]; then
      export RUN_DB_POPULATION_ON_EXISTING_DB=yes
      log "Alpine bootstrap profile: full (forcing DB population/reindex on existing DB)"
    else
      export RUN_DB_POPULATION_ON_EXISTING_DB=no
      log "Alpine bootstrap profile: resume (skipping full DB population/reindex on existing DB)"
    fi
    export ALPINE_BOOTSTRAP_PROFILE
    start_koha
    verify_running_volume_identity
    configure_koha_languages
    [[ "${FOLLOW_LOGS}" == true ]] && follow_logs
    ;;

  status)
    show_status
    ;;

  logs)
    follow_logs
    ;;

  build)
    check_prereqs
    [[ "${PREPARE_DB_CLIENT_TLS}" == true ]] && prepare_mariadb_client_tls
    if [[ "${BUILD_OPENSEARCH}" == false && "${BUILD_KOHA}" == false ]]; then
      # No specific target → build everything
      BUILD_OPENSEARCH=true; BUILD_KOHA=true
    fi
    if [[ "${BUILD_KOHA}" == true && "${KOHA_IMAGE_MODE}" == "dev" ]]; then
      ensure_koha_source
    fi
    [[ "${BUILD_OPENSEARCH}" == true ]] && build_opensearch
    [[ "${BUILD_KOHA}"       == true ]] && build_koha
    ok "Build complete."
    ;;

  backup)
    check_prereqs
    create_backup_bundle
    ;;

  restore)
    check_prereqs
    restore_backup_bundle
    ;;

  volumes)
    show_volume_identity
    ;;

  tls-client-cert)
    check_prereqs
    prepare_mariadb_client_tls
    ok "TLS client materials are ready. Next: ./$(basename "$0") restart --no-logs"
    ;;

  latest-tag)
    hdr "Fetching latest Koha release tag"
    latest="$(koha_latest_tag)"
    [[ -n "${latest}" ]] || die "Could not resolve latest tag from ${KOHA_GIT_URL:-${KOHA_DEFAULT_REPO_URL}}"
    ok "Latest upstream tag: ${latest}"
    if [[ "${APPLY_LATEST_TAG}" == true ]]; then
      target="${KOHA_TAG_TO_APPLY:-${latest}}"
      # accept version without leading 'v' (e.g. 25.11.06-1 -> v25.11.06-1)
      [[ "${target}" =~ ^v ]] || target="v${target}"
      _set_env_val "${KOHA_ENV_FILE}" KOHA_GIT_TAG "${target}"
      ok "Written KOHA_GIT_TAG=${target} to ${KOHA_ENV_FILE}"
      log "Rebuild the prod image with: ./$(basename "$0") build --image-mode prod --build-koha"
    else
      log "To set the latest tag:         ./$(basename "$0") latest-tag --apply"
      log "To set a specific tag:         ./$(basename "$0") latest-tag --apply v25.11.06-1"
    fi
    ;;

esac

if [[ "${COMMAND}" == "reset" ]]; then
  rm -f "${BOOTSTRAP_MARKER}" 2>/dev/null || true
fi

exit 0
