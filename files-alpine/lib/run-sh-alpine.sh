#!/bin/bash
# lib/run-sh-alpine.sh - FINAL v5 integrated
set -e

ensure_alpine_compat() {
    mkdir -p /lib/lsb /usr/sbin /usr/share/koha/bin /etc/koha/sites /var/run/koha /var/log/koha /var/cache/koha /usr/local/bin
    cat > /lib/lsb/init-functions <<'LSB'
#!/bin/sh
log_daemon_msg() { echo "$2"; }
log_end_msg() { return ${1:-0}; }
log_progress_msg() { echo -n "$@"; }
log_warning_msg() { echo "WARN $@" >&2; }
log_failure_msg() { echo "FAIL $@" >&2; }
log_success_msg() { echo "$@"; }
LSB
    chmod +x /lib/lsb/init-functions
    printf '#!/bin/sh\necho "Server version: Apache/2.4.58 (Alpine)"\necho "Syntax OK"\nexit 0\n' > /usr/sbin/apache2ctl; chmod +x /usr/sbin/apache2ctl
    printf '#!/bin/sh\nexit 0\n' > /usr/sbin/a2enmod; chmod +x /usr/sbin/a2enmod
    printf '#!/bin/sh\nexit 0\n' > /usr/sbin/a2dismod; chmod +x /usr/sbin/a2dismod
    getent group kohadev-koha >/dev/null 2>&1 || addgroup kohadev-koha 2>/dev/null || true
    id kohadev-koha >/dev/null 2>&1 || adduser -D -G kohadev-koha kohadev-koha 2>/dev/null || true
    id kohadev >/dev/null 2>&1 || { addgroup -g 1000 kohadev 2>/dev/null || true; adduser -D -u 1000 -G kohadev kohadev 2>/dev/null || true; }
}

ensure_runtime_dirs() {
    ensure_alpine_compat
    mkdir -p /etc/koha/sites /etc/koha /var/lib/koha /var/log/koha /var/run/koha /var/cache/koha /etc/apache2/sites-available /etc/apache2/sites-enabled /var/log/koha/kohadev /var/run/koha/kohadev /kohadevbox/templates /usr/share/koha/bin
    if [ ! -f /etc/koha/sites/kohadev/koha-conf.xml ] && [ -f /kohadevbox/koha/etc/koha-conf.xml ]; then
        mkdir -p /etc/koha/sites/kohadev
        cp /kohadevbox/koha/etc/koha-conf.xml /etc/koha/sites/kohadev/koha-conf.xml
    fi
    chown -R kohadev:kohadev /var/lib/koha /var/log/koha /var/run/koha /var/cache/koha 2>/dev/null || true
}

copy_runtime_files() {
    echo "[copy_runtime_files] Installing Koha scripts"
    if [ -f /build/files-alpine/scripts/koha-plack ]; then
        cp /build/files-alpine/scripts/koha-plack /usr/sbin/koha-plack
        cp /build/files-alpine/scripts/koha-plack /usr/local/bin/koha-plack
        chmod +x /usr/sbin/koha-plack /usr/local/bin/koha-plack
        echo "[copy_runtime_files] Installed Alpine-native koha-plack"
    fi
    if [ -f /build/files-alpine/scripts/koha-worker ]; then
        cp /build/files-alpine/scripts/koha-worker /usr/sbin/koha-worker
        cp /build/files-alpine/scripts/koha-worker /usr/local/bin/koha-worker
        chmod +x /usr/sbin/koha-worker /usr/local/bin/koha-worker
        echo "[copy_runtime_files] Installed Alpine-native koha-worker"
    fi
    if [ -f "/opt/alpine-koha-create" ]; then
        cp /opt/alpine-koha-create /usr/sbin/koha-create
        cp /opt/alpine-koha-create /usr/local/bin/koha-create
        chmod +x /usr/sbin/koha-create /usr/local/bin/koha-create
    fi
    ensure_alpine_compat
    if [ -d "/build/files-alpine/templates" ] && [ "${KOHA_ALPINE_SKIP_RUNTIME_COPY:-no}" != "yes" ]; then
        cp -r /build/files-alpine/templates/* /kohadevbox/templates/ 2>/dev/null || true
    fi
    if [ "${SKIP_RUNTIME_ASSET_COPY:-no}" != "yes" ] && [ -d "/opt/koha-tmpl-built" ]; then
        if [ ! -d "/kohadevbox/koha/koha-tmpl" ] || [ -z "$(ls -A /kohadevbox/koha/koha-tmpl 2>/dev/null)" ]; then
            mkdir -p /kohadevbox/koha/
            cp -r /opt/koha-tmpl-built/* /kohadevbox/koha/ 2>/dev/null || true
        fi
    fi
}

render_vhost() {
    local instance="${1:-kohadev}"
    local koha_path="${KOHA_PATH:-/kohadevbox/koha}"
    local template_file="/kohadevbox/templates/kohadev.conf.in"
    [ -f "$template_file" ] || template_file="/build/files-alpine/templates/kohadev.conf.in"
    local dest="/etc/apache2/sites-available/${instance}.conf"
    if [ -f "$template_file" ]; then
        sed -e "s|__KOHA_PATH__|${koha_path}|g" -e "s|__BUILD_DIR__|/kohadevbox|g" -e "s|__KOHA_INSTANCE__|${instance}|g" -e "s|__OPAC_PORT__|${KOHA_OPAC_PORT:-8080}|g" -e "s|__INTRANET_PORT__|${KOHA_INTRANET_PORT:-8081}|g" "$template_file" > "$dest"
    else
        echo "[render_vhost] WARNING template not found, using fallback"
        cat > "$dest" <<EOF
<VirtualHost *:${KOHA_OPAC_PORT:-8080}>
    DocumentRoot ${koha_path}/opac
</VirtualHost>
<VirtualHost *:${KOHA_INTRANET_PORT:-8081}>
    DocumentRoot ${koha_path}/intranet/htdocs
</VirtualHost>
EOF
    fi
}

enable_instance_services() {
    koha-plack --enable "${KOHA_INSTANCE}" 2>&1 || true
}

start_crond() { crond -b -l 8 2>/dev/null || true; }
stop_apache_service() { httpd -k stop 2>/dev/null || true; sleep 1; }
start_apache_service() { httpd -k start 2>/dev/null || httpd 2>/dev/null || true; }

run_service_watchdog() {
    local instance="${1:-kohadev}" interval="${2:-30}"
    echo "[watchdog] Service watchdog started (instance=${instance})"
    trap 'koha-plack --stop "'"${instance}"'" 2>/dev/null || true; koha-worker --stop "'"${instance}"'" 2>/dev/null || true; httpd -k stop 2>/dev/null || true; exit 0' TERM INT
    while true; do
        koha-plack --status "${instance}" >/dev/null 2>&1 || { echo "[watchdog] plack down, restarting..."; koha-plack --start "${instance}" 2>/dev/null || true; }
        koha-worker --status "${instance}" >/dev/null 2>&1 || { echo "[watchdog] worker down, restarting..."; koha-worker --start "${instance}" 2>/dev/null || true; }
        sleep "${interval}" & wait $! || true
    done
}
