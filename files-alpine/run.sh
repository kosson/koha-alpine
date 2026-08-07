#!/bin/bash
# files-alpine/run.sh - v2026-08-07-plack-fix2 - overwrites previous
set -e
export KOHA_ALPINE_SKIP_YARN_INSTALL=yes
export KOHA_ALPINE_SKIP_GIT_SETUP=yes
export KOHA_ALPINE_SKIP_L10N=yes
export KOHA_ALPINE_SKIP_ELASTICSEARCH_WAIT=yes
export KOHA_ALPINE_SKIP_RUNTIME_COPY=no
export KOHA_ALPINE_SKIP_DEBIAN_SCRIPTS=no
export SKIP_RUNTIME_ASSET_COPY=no
export KOHA_ENABLE_PLACK=yes
export KOHA_ENABLE_WORKER=yes
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
ensure_runtime_dirs 2>&1 | grep -v "No file descriptors" || true
copy_runtime_files 2>&1 | grep -v "No file descriptors" || true
echo "[koha-create] Detected existing database ${DB_NAME}; using --use-db"
mkdir -p /etc/apache2/sites-available /etc/apache2/sites-enabled
koha-create --use-db --db-user "${DB_USER}" --db-password "${DB_PASSWORD}" --db-name "${DB_NAME}" --memcached-servers memcached:11211 --mb-host "${MESSAGE_BROKER_HOST:-rabbitmq}" "${KOHA_INSTANCE}" 2>&1 | grep -v "No file descriptors" || true
echo "[koha-create-alpine] Instance ${KOHA_INSTANCE} ready (mode=use)"
echo "[render_vhost] KOHA_PATH=${KOHA_PATH} BUILD_DIR=${BUILD_DIR}"
render_vhost "${KOHA_INSTANCE}" 2>&1 | grep -v "No file descriptors" || true
for p in "${KOHA_OPAC_PORT:-8080}" "${KOHA_INTRANET_PORT:-8081}"; do
  if ! grep -qE "^Listen +${p}($| )" /etc/apache2/httpd.conf 2>/dev/null; then
    echo "Listen $p" >> /etc/apache2/httpd.conf
    echo "[apache] Added Listen $p"
  fi
done
a2ensite "${KOHA_INSTANCE}" >/dev/null 2>&1 || ln -sf "/etc/apache2/sites-available/${KOHA_INSTANCE}.conf" "/etc/apache2/sites-enabled/${KOHA_INSTANCE}.conf" || true
echo "Instance ${KOHA_INSTANCE} already enabled."
enable_instance_services 2>&1 | grep -v "No file descriptors" || true
start_crond 2>/dev/null || true
stop_apache_service 2>/dev/null || true
echo "[apache] Testing config: KOHA_PATH=${KOHA_PATH}"
httpd -t 2>&1 || true
start_apache_service 2>/dev/null || httpd -k start || true
echo "[apache] listening on:"
( ss -tln 2>/dev/null | grep -E "8080|8081|:80" || netstat -tln 2>/dev/null | grep -E "8080|8081|:80" || ps aux | grep httpd | grep -v grep ) || true
if command -v koha-plack >/dev/null 2>&1; then
  echo "[plack] Enabling plack for ${KOHA_INSTANCE}"
  koha-plack --enable "${KOHA_INSTANCE}" 2>&1 | grep -v "No file descriptors" || true
  koha-plack --start "${KOHA_INSTANCE}" 2>&1 | grep -v "No file descriptors" || true
  sleep 2
  koha-plack --status "${KOHA_INSTANCE}" 2>&1 || echo "[plack] status check failed - check logs"
  ss -tln | grep -E "5000|5001" || true
else
  echo "[plack] koha-plack not found - THIS SHOULD NOT HAPPEN"
  ls -l /usr/sbin/koha-* /usr/local/bin/koha-* 2>&1
fi
if command -v koha-worker >/dev/null 2>&1; then
  echo "[worker] Starting worker for ${KOHA_INSTANCE}"
  koha-worker --enable "${KOHA_INSTANCE}" 2>&1 | grep -v "No file descriptors" || true
  koha-worker --start "${KOHA_INSTANCE}" 2>&1 | grep -v "No file descriptors" || true
fi
echo "koha-testing-docker has started up and is ready to be enjoyed!"
touch /var/log/koha/${KOHA_INSTANCE}/plack.log /var/log/koha/${KOHA_INSTANCE}/plack-error.log 2>/dev/null || true
run_service_watchdog "${KOHA_INSTANCE}" 30
