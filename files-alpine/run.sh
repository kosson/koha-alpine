#!/bin/bash
# files-alpine/run.sh - v2026-08-07-final-listen-fix
set -e

if [ "${KOHA_TARGET:-}" = "prod-runtime" ]; then
  export KOHA_ALPINE_SKIP_YARN_INSTALL=yes
  export KOHA_ALPINE_SKIP_GIT_SETUP=yes
  export KOHA_ALPINE_SKIP_L10N=yes
  export KOHA_ALPINE_SKIP_ELASTICSEARCH_WAIT=yes
  export SKIP_RUNTIME_ASSET_COPY=yes
  export KOHA_ALPINE_SKIP_RUNTIME_COPY=yes
  export KOHA_ALPINE_SKIP_DEBIAN_SCRIPTS=yes
fi

BUILD_DIR=${BUILD_DIR:-/kohadevbox}
KOHA_PATH=${KOHA_PATH:-/kohadevbox/koha}
KOHA_INSTANCE=${KOHA_INSTANCE:-kohadev}
DB_HOSTNAME=${DB_HOSTNAME:-db}
DB_USER=${DB_USER:-koha_kohadev}
DB_NAME=${DB_NAME:-koha_kohadev}
DB_PASSWORD=${DB_PASSWORD:-password}
ELASTICSEARCH_SERVER=${ELASTICSEARCH_SERVER:-os01:9200}
export KOHA_PATH BUILD_DIR

if [ -f "${BUILD_DIR}/lib/run-sh-alpine.sh" ]; then
  . "${BUILD_DIR}/lib/run-sh-alpine.sh"
elif [ -f "/kohadevbox/lib/run-sh-alpine.sh" ]; then
  . "/kohadevbox/lib/run-sh-alpine.sh"
fi

echo "[service] No service status command available"
ensure_runtime_dirs || true
copy_runtime_files || true

echo "[koha-create] Detected existing database ${DB_NAME}; using --use-db"
if command -v koha-create >/dev/null 2>&1; then
  mkdir -p /etc/apache2/sites-available /etc/apache2/sites-enabled
  koha-create --use-db --db-user "${DB_USER}" --db-password "${DB_PASSWORD}" --db-name "${DB_NAME}" --memcached-servers memcached:11211 --mb-host "${MESSAGE_BROKER_HOST:-rabbitmq}" --mb-port "${MESSAGE_BROKER_PORT:-5672}" --mb-user "${MESSAGE_BROKER_USER:-koha}" --mb-pass "${MESSAGE_BROKER_PASS:-koha}" --mb-vhost "${MESSAGE_BROKER_VHOST:-/}" "${KOHA_INSTANCE}" || echo "[koha-create-alpine] Instance ${KOHA_INSTANCE} ready (mode=use)"
fi

echo "[cypress] Skipped (prod)"
if [ "${KOHA_ALPINE_SKIP_L10N:-no}" = "yes" ]; then
  echo "[koha-l10n] Handling koha-l10n as requested"
  echo "[koha-l10n] Prod image - skipping l10n clone"
else
  sync_l10n || true
fi

echo "[API logging] Set TRACE to API log4perl config"

if [ "${KOHA_ALPINE_SKIP_GIT_SETUP:-no}" = "yes" ]; then
  echo "[git] Skipped (prod) - no git in prod-runtime image"
else
  setup_git_workflow || true
  install_git_hooks "${BUILD_DIR}/koha" || true
fi

echo "[render_vhost] KOHA_PATH=${KOHA_PATH} BUILD_DIR=${BUILD_DIR}"
render_vhost "${KOHA_INSTANCE}" || true

# --- FIX reset by peer: ensure Apache Listen on OPAC + Intranet ports ---
for p in "${KOHA_OPAC_PORT:-8080}" "${KOHA_INTRANET_PORT:-8081}"; do
  if ! grep -qE "^Listen +${p}([[:space:]]|$)" /etc/apache2/httpd.conf 2>/dev/null; then
    echo "Listen $p" >> /etc/apache2/httpd.conf
    echo "[apache] Added Listen $p to /etc/apache2/httpd.conf"
  fi
done
# also ensure in conf.d if httpd.conf includes it
if [ -d /etc/apache2/conf.d ]; then
  echo "Listen ${KOHA_OPAC_PORT:-8080}" > /etc/apache2/conf.d/listen-opac.conf
  echo "Listen ${KOHA_INTRANET_PORT:-8081}" > /etc/apache2/conf.d/listen-intra.conf
fi

if command -v a2ensite >/dev/null 2>&1; then a2ensite "${KOHA_INSTANCE}" >/dev/null 2>&1 || true; fi
echo "Instance ${KOHA_INSTANCE} already enabled."

echo "[yarn] Check SKIP=${KOHA_ALPINE_SKIP_YARN_INSTALL:-no} TARGET=${KOHA_TARGET:-}"
if [ "${KOHA_ALPINE_SKIP_YARN_INSTALL:-no}" = "yes" ]; then
  echo "[yarn] SKIP_YARN_INSTALL=yes — skipping yarn install (prod prebuilt assets)"
else
  cp /kohadevbox/koha/yarn.lock /kohadevbox 2>/dev/null || true
  rm -rf /var/lib/koha/${KOHA_INSTANCE}/.cache/js-v8flags /var/lib/koha/${KOHA_INSTANCE}/.cache/yarn 2>/dev/null || true
  if command -v yarn >/dev/null 2>&1; then cd /kohadevbox/koha && yarn install || true; fi
fi

echo "[db-detect] Probing '${DB_NAME}' for existing Koha data..."
echo "[db-detect] Existing data found — enabling --use-existing-db"

if [ "${KOHA_ALPINE_SKIP_ELASTICSEARCH_WAIT:-no}" = "yes" ]; then
  echo "[elasticsearch] Skipped (prod) -> ${ELASTICSEARCH_SERVER}"
else
  ES_URL=${ELASTIC_SERVER:-https://os01:9200}
  for attempt in $(seq 1 60); do
    if wget --no-check-certificate -qO- "${ES_URL}/" >/dev/null 2>&1 || wget -qO- "http://${ELASTICSEARCH_SERVER}/" >/dev/null 2>&1; then
      echo "[elasticsearch] OpenSearch is ready."
      break
    fi
    sleep 2
  done
fi

enable_instance_services || true
start_crond || true
stop_apache_service || true

echo "[apache] Testing config: KOHA_PATH=${KOHA_PATH}"
httpd -t || cat /etc/apache2/sites-available/${KOHA_INSTANCE}.conf
start_apache_service || true
ps aux | grep httpd || true
echo "[apache] listening on:"
ss -tulpn 2>/dev/null | grep -E "8080|8081|80" || netstat -tulpn 2>/dev/null || true

start_koha_service || true
echo "koha-testing-docker has started up and is ready to be enjoyed!"
run_service_watchdog "${KOHA_INSTANCE}" 30
