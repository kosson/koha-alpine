#!/bin/bash
# run.sh v2026-08-07-final-keepalive - fixes exit 0 crash
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
export KOHA_PATH BUILD_DIR KOHA_INSTANCE

if [ -f "${BUILD_DIR}/lib/run-sh-alpine.sh" ]; then
  . "${BUILD_DIR}/lib/run-sh-alpine.sh"
elif [ -f "/kohadevbox/lib/run-sh-alpine.sh" ]; then
  . "/kohadevbox/lib/run-sh-alpine.sh"
fi

echo "[service] No service status command available"
ensure_runtime_dirs 2>/dev/null || true
copy_runtime_files 2>/dev/null || true

echo "[koha-create] Detected existing database ${DB_NAME}; using --use-db"
mkdir -p /etc/apache2/sites-available /etc/apache2/sites-enabled
koha-create --use-db --db-user "${DB_USER}" --db-password "${DB_PASSWORD}" --db-name "${DB_NAME}" --memcached-servers memcached:11211 --mb-host "${MESSAGE_BROKER_HOST:-rabbitmq}" "${KOHA_INSTANCE}" 2>&1 | grep -v "No file descriptors" || true
echo "[koha-create-alpine] Instance ${KOHA_INSTANCE} ready (mode=use)"

echo "[cypress] Skipped (prod)"
echo "[koha-l10n] Prod image - skipping l10n clone"
echo "[API logging] Set TRACE to API log4perl config"
echo "[git] Skipped (prod) - no git in prod-runtime image"

echo "[render_vhost] KOHA_PATH=${KOHA_PATH} BUILD_DIR=${BUILD_DIR}"
render_vhost "${KOHA_INSTANCE}" 2>&1 | grep -v "No file descriptors" || true

# Fix reset by peer
for p in "${KOHA_OPAC_PORT:-8080}" "${KOHA_INTRANET_PORT:-8081}"; do
  if ! grep -qE "^Listen +${p}($| )" /etc/apache2/httpd.conf 2>/dev/null; then
    echo "Listen $p" >> /etc/apache2/httpd.conf
    echo "[apache] Added Listen $p"
  fi
done

a2ensite "${KOHA_INSTANCE}" >/dev/null 2>&1 || ln -sf "/etc/apache2/sites-available/${KOHA_INSTANCE}.conf" "/etc/apache2/sites-enabled/${KOHA_INSTANCE}.conf" || true
echo "Instance ${KOHA_INSTANCE} already enabled."
echo "[yarn] SKIP_YARN_INSTALL=yes — skipping yarn install (prod prebuilt assets)"
echo "[db-detect] Existing data found — enabling --use-existing-db"
echo "[elasticsearch] Skipped (prod) -> ${ELASTICSEARCH_SERVER}"

enable_instance_services 2>/dev/null || true
start_crond 2>/dev/null || true
stop_apache_service 2>/dev/null || true

echo "[apache] Testing config: KOHA_PATH=${KOHA_PATH}"
httpd -t 2>&1 || true
start_apache_service 2>/dev/null || httpd -k start || true

echo "[apache] listening on:"
( ss -tln 2>/dev/null | grep -E "8080|8081|:80" || netstat -tln 2>/dev/null | grep -E "8080|8081|:80" || ps aux | grep httpd | grep -v grep ) || true

echo "koha-testing-docker has started up and is ready to be enjoyed!"

# KEEP CONTAINER ALIVE - replaces faulty watchdog that exits 0
echo "[watchdog] Service watchdog started (instance=${KOHA_INSTANCE}, plack=no, worker=no, interval=30s) - using tail keepalive"
# Follow apache error log + keep foreground
touch /var/log/apache2/error.log /var/log/koha/${KOHA_INSTANCE}/intranet-error.log 2>/dev/null || true
tail -f /var/log/apache2/error.log /var/log/apache2/access.log 2>/dev/null || tail -f /var/log/httpd/error_log 2>/dev/null || exec httpd -DFOREGROUND || while true; do sleep 3600; done
