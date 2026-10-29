#!/usr/bin/env bash

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
LOCAL_CONFIG_DIR="${SCRIPT_DIR}/assets/local-config"
INTERNAL_USERS_TEMPLATE="${SCRIPT_DIR}/assets/opensearch/config/os01/opensearch-security/internal_users.yml"
DASHBOARDS_TEMPLATE="${SCRIPT_DIR}/assets/dashboards/opensearch_dashboards.yml"
INTERNAL_USERS_CONFIG="${LOCAL_CONFIG_DIR}/internal_users.yml"
DASHBOARDS_CONFIG="${LOCAL_CONFIG_DIR}/opensearch_dashboards.yml"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

read_env_value() {
  local key="$1"
  grep -E "^${key}=" "${ENV_FILE}" 2>/dev/null \
    | head -1 | cut -d= -f2- | sed -e 's/^["'\'']//; s/["'\'']$//' || true
}

[[ -f "${ENV_FILE}" ]] || fail "Create the access-controlled local ${ENV_FILE} first."
admin_password="$(read_env_value OPENSEARCH_INITIAL_ADMIN_PASSWORD)"
[[ -n "${admin_password}" ]] || fail "Set OPENSEARCH_INITIAL_ADMIN_PASSWORD in the local OpenSearch env file."
command -v docker >/dev/null 2>&1 || fail "Docker is required to generate local OpenSearch password hashes."

open_search_version="$(read_env_value OPEN_SEARCH_VERSION)"
open_search_version="${open_search_version:-3.6.0}"
mkdir -p "${LOCAL_CONFIG_DIR}"
[[ -f "${INTERNAL_USERS_CONFIG}" ]] || install -m 600 "${INTERNAL_USERS_TEMPLATE}" "${INTERNAL_USERS_CONFIG}"
[[ -f "${DASHBOARDS_CONFIG}" ]] || install -m 600 "${DASHBOARDS_TEMPLATE}" "${DASHBOARDS_CONFIG}"
chmod 600 "${ENV_FILE}"

password_hash="$(
  ADMIN_PASS="${admin_password}" docker run --rm \
    --env ADMIN_PASS \
    "opensearchproject/opensearch:${open_search_version}" \
    bash -c '/usr/share/opensearch/plugins/opensearch-security/tools/hash.sh -p "$ADMIN_PASS" 2>/dev/null'
)"
[[ -n "${password_hash}" ]] || fail "OpenSearch hash.sh returned no password hash."

python3 - "${password_hash}" "${INTERNAL_USERS_CONFIG}" <<'PY'
import re
import sys
from pathlib import Path

password_hash, path = sys.argv[1], Path(sys.argv[2])
text = path.read_text()
text, count = re.subn(
    r"(?m)^(  hash: ).*$",
    lambda match: match.group(1) + '"' + password_hash + '"',
    text,
)
if count == 0:
    raise SystemExit("No internal user hashes found in the local template.")
path.write_text(text)
PY

OPENSEARCH_INITIAL_ADMIN_PASSWORD="${admin_password}" python3 - "${DASHBOARDS_CONFIG}" <<'PY'
import os
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
password = os.environ["OPENSEARCH_INITIAL_ADMIN_PASSWORD"]
quoted = "'" + password.replace("'", "''") + "'"
text, count = re.subn(
    r"(?m)^opensearch\.password:.*$",
    lambda _: "opensearch.password: " + quoted,
    path.read_text(),
)
if count != 1:
    raise SystemExit("Expected exactly one opensearch.password entry in the local Dashboards config.")
path.write_text(text)
PY

chmod 600 "${INTERNAL_USERS_CONFIG}" "${DASHBOARDS_CONFIG}"
printf 'OpenSearch authentication config generated in ignored local files; no credentials or hashes were printed.\n'
