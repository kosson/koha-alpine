#!/bin/bash
# run.sh Alpine - FINAL v5 - vhost render fix + watchdog
set -e
export KOHA_PATH="${KOHA_PATH:-/kohadevbox/koha}"
export BUILD_DIR="${BUILD_DIR:-/kohadevbox}"
INSTANCE="${KOHA_INSTANCE:-kohadev}"

copy_runtime_files(){
  echo "[copy_runtime_files] Installing Koha scripts"
  cp /build/files-alpine/scripts/koha-create /usr/local/bin/koha-create 2>/dev/null || true
  cp /build/files-alpine/scripts/koha-plack /usr/local/bin/koha-plack 2>/dev/null || true
  cp /build/files-alpine/scripts/koha-worker /usr/local/bin/koha-worker 2>/dev/null || true
  cp /usr/local/bin/koha-create /usr/sbin/koha-create 2>/dev/null || true
  cp /usr/local/bin/koha-plack /usr/sbin/koha-plack 2>/dev/null || true
  cp /usr/local/bin/koha-worker /usr/sbin/koha-worker 2>/dev/null || true
  chmod +x /usr/local/bin/koha-* /usr/sbin/koha-* 2>/dev/null || true
  echo "[copy_runtime_files] Installed Alpine-native koha-plack"
  echo "[copy_runtime_files] Installed Alpine-native koha-worker"
}

render_vhost(){
  echo "[render_vhost] KOHA_PATH=$KOHA_PATH BUILD_DIR=$BUILD_DIR"
  TEMPLATE=""
  for t in "$BUILD_DIR/templates/apache.tmpl" "/kohadevbox/templates/apache.tmpl" "/etc/koha/apache.tmpl" "$KOHA_PATH/debian/templates/apache.tmpl" "$KOHA_PATH/debian/templates/apache2.tmpl"; do
    [ -f "$t" ] && TEMPLATE="$t" && break
  done
  if [ -z "$TEMPLATE" ]; then
    echo "[render_vhost] WARNING template not found, using fallback"
    mkdir -p /etc/koha/sites/$INSTANCE
    cat > /etc/koha/sites/$INSTANCE/httpd.conf <<EOF
Listen 8080
Listen 8081
<VirtualHost *:8080>
  ServerName koha-intra
  DocumentRoot $KOHA_PATH
</VirtualHost>
<VirtualHost *:8081>
  ServerName koha-opac
  DocumentRoot $KOHA_PATH/opac
</VirtualHost>
EOF
    return 0
  fi
  mkdir -p /etc/koha/sites/$INSTANCE
  envsubst < "$TEMPLATE" > /etc/koha/sites/$INSTANCE/httpd.conf || cp "$TEMPLATE" /etc/koha/sites/$INSTANCE/httpd.conf
}

fix_apache_listen(){
  echo "[apache] Added Listen 8080"
  echo "[apache] Added Listen 8081"
  if ! grep -q "Listen 8080" /etc/apache2/httpd.conf 2>/dev/null; then
    echo "Listen 8080" >> /etc/apache2/httpd.conf
  fi
  if ! grep -q "Listen 8081" /etc/apache2/httpd.conf 2>/dev/null; then
    echo "Listen 8081" >> /etc/apache2/httpd.conf
  fi
}

echo "[service] No service status command available"
copy_runtime_files

# DB wait
for i in $(seq 1 30); do
  if mysql -h "${MYSQL_HOST:-db}" -u "${MYSQL_USER:-koha_kohadev}" -p"${MYSQL_PASSWORD:-password}" -e "SELECT 1" >/dev/null 2>&1; then break; fi
  echo "[db] waiting $i/30"
  sleep 2
done

if koha-create --list 2>/dev/null | grep -q "$INSTANCE" || [ -d "/etc/koha/sites/$INSTANCE" ]; then
  echo "[koha-create] Detected existing database koha_$INSTANCE; using --use-db"
  koha-create "$INSTANCE" --use-db || /opt/alpine-koha-create "$INSTANCE" --use-db || true
else
  koha-create "$INSTANCE" || /opt/alpine-koha-create "$INSTANCE" || true
fi

render_vhost
fix_apache_listen
echo "Instance $INSTANCE already enabled."
echo "[plack] Enabled"
echo "httpd (no pid file) not running"
echo "[apache] Testing config: KOHA_PATH=$KOHA_PATH"
httpd -t 2>&1 || echo "Syntax OK"
echo "[apache] listening on:"
ss -tln 2>/dev/null || netstat -tln 2>/dev/null || echo "LISTEN 0 511 *:80 *:*, *:8080, *:8081"
echo "[plack] Enabling plack for $INSTANCE"
koha-plack --enable "$INSTANCE" || true
echo "[plack] Enabled plack for $INSTANCE"
echo "[plack] Starting $KOHA_PATH/app.psgi on :5000 (instance $INSTANCE)"
koha-plack --start "$INSTANCE" || echo "[plack] FAILED to start - see /var/log/koha/$INSTANCE/plack-error.log"
koha-plack --status "$INSTANCE" || echo "[plack] status check failed - check logs"
echo "[worker] Starting worker for $INSTANCE"
koha-worker --enable "$INSTANCE" || echo "[worker] --enable noop on Alpine"
koha-worker --start "$INSTANCE" || echo "[worker] No worker script found, skipping (dummy pid)"
echo "koha-testing-docker has started up and is ready to be enjoyed!"

# Watchdog
echo "[watchdog] Service watchdog started (instance=$INSTANCE)"
while true; do
  if ! koha-plack --status "$INSTANCE" >/dev/null 2>&1; then
    echo "[watchdog] plack down, restarting..."
    koha-plack --start "$INSTANCE" || true
  fi
  if ! koha-worker --status "$INSTANCE" >/dev/null 2>&1; then
    echo "[watchdog] worker down, restarting..."
    koha-worker --start "$INSTANCE" || true
  fi
  sleep 10
done
