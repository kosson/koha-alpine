#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0
_N=0

ok() {
    _N=$((_N + 1))
    echo "ok ${_N} - $1"
    PASS=$((PASS + 1))
}

not_ok() {
    _N=$((_N + 1))
    echo "not ok ${_N} - $1"
    FAIL=$((FAIL + 1))
}

if python3 - "${ROOT_DIR}" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
tracked = subprocess.check_output(
    ["git", "-C", str(root), "ls-files", "-z"], text=False
).decode().split("\0")
secret_keys = re.compile(
    r"(?i)(pass(word)?|secret|token|masterkey|salt)"
)
bad = False

for relative in tracked:
    if not relative:
        continue
    path = Path(relative)
    if path.suffix != ".env" and path.name not in {".env", "defaults.env", "template.env"}:
        continue
    try:
        lines = (root / path).read_text(errors="replace").splitlines()
    except OSError:
        continue
    for line in lines:
        match = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)", line)
        if match and (secret_keys.search(match.group(1)) or match.group(1) == "ELASTIC_OPTIONS"):
            if match.group(2).strip().strip("\"'"):
                print(f"{relative}:{match.group(1)}")
                bad = True

if bad:
    raise SystemExit(1)
PY
then
    ok "tracked environment files contain no credential values"
else
    not_ok "tracked environment files contain no credential values"
fi

if python3 - "${ROOT_DIR}" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
checks = {
    "OpenSearch-3.6/assets/dashboards/opensearch_dashboards.yml":
        re.compile(r"^\s*opensearch\.password:\s*(?:\"\"|'')\s*$"),
    "OpenSearch-3.6/assets/opensearch/config/os01/opensearch-security/config.yml":
        re.compile(r"^\s*password:\s*$"),
}
for name, pattern in checks.items():
    lines = (root / name).read_text().splitlines()
    if not any(pattern.search(line) for line in lines):
        raise SystemExit(1)

hash_lines = [
    line for line in (root / "OpenSearch-3.6/assets/opensearch/config/os01/opensearch-security/internal_users.yml").read_text().splitlines()
    if re.match(r"^\s+hash:", line)
]
if not hash_lines or any('"<generated-locally>"' not in line for line in hash_lines):
    raise SystemExit(1)
PY
then
    ok "tracked OpenSearch authentication templates require local secret generation"
else
    not_ok "tracked OpenSearch authentication templates require local secret generation"
fi

if ! grep -Eq 'KOHA_DB_(ROOT_)?PASSWORD:-[^}]*password|KOHA_ADMIN_PASS:-[^}]*admin' \
    "${ROOT_DIR}/files-alpine/run.sh" "${ROOT_DIR}/files-alpine/scripts/run.sh" \
    "${ROOT_DIR}/files-alpine/scripts/koha-create-superlibrarian.sh"; then
    ok "Koha entrypoint and helpers have no built-in database/admin password defaults"
else
    not_ok "Koha entrypoint and helpers have no built-in database/admin password defaults"
fi

if grep -Fq 'KOHA_DB_ROOT_PASSWORD must be set' "${ROOT_DIR}/docker-compose-alpinekoha.yml" &&
   grep -Fq 'KOHA_DB_PASSWORD must be set' "${ROOT_DIR}/docker-compose-alpinekoha.yml" &&
   grep -Fq 'KOHA_RABBITMQ_PASS must be set' "${ROOT_DIR}/docker-compose-alpinekoha.yml"; then
    ok "Compose requires non-empty database and broker credentials"
else
    not_ok "Compose requires non-empty database and broker credentials"
fi

if ! grep -Eq 'echo.*(COMPLIANCE_SALT|SQL_MASTERKEY|NEW_HASH)' \
    "${ROOT_DIR}/OpenSearch-3.6/opensearch_local_certificates_creator.sh"; then
    ok "OpenSearch setup does not print generated secrets or hashes"
else
    not_ok "OpenSearch setup does not print generated secrets or hashes"
fi

if grep -Fq -- '--env ADMIN_PASS' "${ROOT_DIR}/OpenSearch-3.6/prepare_local_auth_config.sh" &&
   ! grep -Fq -- '--env "ADMIN_PASS=' "${ROOT_DIR}/OpenSearch-3.6/prepare_local_auth_config.sh"; then
    ok "OpenSearch hash generation does not place the admin password in Docker arguments"
else
    not_ok "OpenSearch hash generation does not place the admin password in Docker arguments"
fi

if grep -Fq './assets/local-config/internal_users.yml:/usr/share/opensearch/config/opensearch-security/internal_users.yml:ro' \
    "${ROOT_DIR}/OpenSearch-3.6/docker-compose.yml" &&
   grep -Fq './assets/local-config/opensearch_dashboards.yml:/usr/share/opensearch-dashboards/config/opensearch_dashboards.yml:ro' \
    "${ROOT_DIR}/OpenSearch-3.6/docker-compose.yml"; then
    ok "OpenSearch mounts generated authentication files read-only from ignored local config"
else
    not_ok "OpenSearch mounts generated authentication files read-only from ignored local config"
fi

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}"
[[ ${FAIL} -eq 0 ]]
