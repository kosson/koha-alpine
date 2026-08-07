#!/bin/bash
# Alpine compatibility helpers for files-alpine/run.sh.
# v2026-08-07 final - prod prebuilt assets, security hardening
# Patched to respect KOHA_TARGET=prod-runtime for ALL helpers

if [ "${KOHA_TARGET:-}" = "prod-runtime" ]; then
  export KOHA_ALPINE_SKIP_YARN_INSTALL=yes
  export KOHA_ALPINE_SKIP_GIT_SETUP=yes
  export KOHA_ALPINE_SKIP_L10N=yes
  export KOHA_ALPINE_SKIP_ELASTICSEARCH_WAIT=yes
  export SKIP_RUNTIME_ASSET_COPY=yes
  export KOHA_ALPINE_SKIP_RUNTIME_COPY=yes
fi

# prod skips - define as functions that override dev behavior
if [ "${KOHA_ALPINE_SKIP_GIT_SETUP:-no}" = "yes" ]; then
  git_setup() { echo "[git] Skipped (prod)"; return 0; }
  setup_git_workflow() { echo "[git] Skipped (prod)"; return 0; }
  install_git_hooks() { echo "[git] Skipped hooks (prod)"; return 0; }
fi

if [ "${KOHA_ALPINE_SKIP_YARN_INSTALL:-no}" = "yes" ]; then
  yarn_install() { echo "[yarn] Skipped (prod)"; return 0; }
fi

if [ "${KOHA_ALPINE_SKIP_L10N:-no}" = "yes" ]; then
  handle_l10n() { echo "[l10n] Skipped (prod)"; return 0; }
  sync_l10n() { echo "[koha-l10n] Prod image - skipping l10n clone"; return 0; }
fi

if [ "${KOHA_ALPINE_SKIP_ELASTICSEARCH_WAIT:-no}" = "yes" ]; then
  wait_for_elasticsearch() { echo "[elasticsearch] Skipped (prod) -> ${ELASTICSEARCH_SERVER:-os01:9200}"; return 0; }
fi

append_if_absent()
{
    local string=$1
    local file=$2
    if ! grep -Fxq "$string" "$file"; then
        printf '%s\n' "$string" >> "$file"
    fi
}

write_db_client_configs() {
    local instance="$1"
    mkdir -p /etc/mysql
    {
        printf '[client]\nhost     = %s\nuser     = root\npassword = %s\n' "${DB_HOSTNAME}" "${KOHA_DB_ROOT_PASSWORD}"
        if [ "${KOHA_DB_USE_TLS:-}" = "yes" ]; then
            printf 'ssl      = on\n'
            [ -n "${KOHA_DB_TLS_CA_CERTIFICATE:-}" ] && printf 'ssl-ca   = %s\n' "${KOHA_DB_TLS_CA_CERTIFICATE}" || true
            [ -n "${KOHA_DB_TLS_CLIENT_CERTIFICATE:-}" ] && printf 'ssl-cert = %s\n' "${KOHA_DB_TLS_CLIENT_CERTIFICATE}" || true
            [ -n "${KOHA_DB_TLS_CLIENT_KEY:-}" ] && printf 'ssl-key  = %s\n' "${KOHA_DB_TLS_CLIENT_KEY}" || true
        else
            printf 'ssl      = off\nskip-ssl\n'
        fi
    } > /etc/mysql/koha-common.cnf
    cp /etc/mysql/koha-common.cnf /etc/mysql/debian.cnf
    chmod 600 /etc/mysql/debian.cnf /etc/mysql/koha-common.cnf
    {
        printf '[client]\nhost     = %s\nuser     = %s\npassword = %s\n' "${DB_HOSTNAME}" "${DB_USER}" "${DB_PASSWORD}"
        if [ "${KOHA_DB_USE_TLS:-}" = "yes" ]; then
            printf 'ssl      = on\n'
            [ -n "${KOHA_DB_TLS_CA_CERTIFICATE:-}" ] && printf 'ssl-ca   = %s\n' "${KOHA_DB_TLS_CA_CERTIFICATE}" || true
            [ -n "${KOHA_DB_TLS_CLIENT_CERTIFICATE:-}" ] && printf 'ssl-cert = %s\n' "${KOHA_DB_TLS_CLIENT_CERTIFICATE}" || true
            [ -n "${KOHA_DB_TLS_CLIENT_KEY:-}" ] && printf 'ssl-key  = %s\n' "${KOHA_DB_TLS_CLIENT_KEY}" || true
        else
            printf 'ssl      = off\nskip-ssl\n'
        fi
    } > "/etc/mysql/koha_${instance}.cnf"
    chmod 600 "/etc/mysql/koha_${instance}.cnf"
    chown ${instance}-koha:root "/etc/mysql/koha_${instance}.cnf" 2>/dev/null || true
}

install_os_packages() {
    if [ "$#" -eq 0 ]; then return 0; fi
    if command -v apk >/dev/null 2>&1; then apk add --no-cache "$@"; return $?; fi
    echo "[packages] No supported package manager found"; return 1
}

remove_os_packages() {
    if [ "$#" -eq 0 ]; then return 0; fi
    if command -v apk >/dev/null 2>&1; then
        local installed=(); local p
        for p in "$@"; do apk info -e "$p" >/dev/null 2>&1 && installed+=("$p"); done
        [ "${#installed[@]}" -gt 0 ] && apk del "${installed[@]}" || true
        return 0
    fi
    echo "[packages] No supported package manager found"; return 1
}

service_status_all() {
    if command -v rc-status >/dev/null 2>&1; then rc-status -a || true; return 0; fi
    echo "[service] No service status command available"
}

ensure_runtime_dirs() {
    mkdir -p /etc/mysql /etc/koha /etc/koha/zebradb /etc/koha/zebradb/marc_defs /etc/sudoers.d /var/cache/koha /var/lib/koha /var/log/koha /var/run/koha /var/lock/koha /etc/apache2/sites-available /etc/apache2/sites-enabled
}

run_koha_shell() {
    local instance=$1; shift
    if command -v koha-shell >/dev/null 2>&1; then sudo koha-shell "$instance" -c "$*" 2>/dev/null || sudo -u ${instance}-koha sh -c "$*" 2>/dev/null || sh -c "$*"; return 0; fi
    echo "[koha-shell] WARNING: koha-shell not available; skipping: $*"
}

ensure_compat_files() {
    echo "[compat] Ensuring Debian-compat files exist"
    mkdir -p /etc/default /usr/share/koha/bin /etc/koha/sites/kohadev /etc/apache2/sites-available
    if [ ! -f /etc/default/koha-common ]; then
        cat > /etc/default/koha-common <<'EOF'
KOHA_USER=kohadev-koha
KOHA_GROUP=kohadev-koha
EOF
        chmod 644 /etc/default/koha-common
    fi
    mkdir -p /usr/share/koha/bin
    if [ -f /kohadevbox/koha/bin/koha-functions.sh ]; then
        cp /kohadevbox/koha/bin/koha-functions.sh /usr/share/koha/bin/koha-functions.sh 2>/dev/null || true
    elif [ -f /usr/local/bin/koha-functions.sh ]; then
        cp /usr/local/bin/koha-functions.sh /usr/share/koha/bin/koha-functions.sh 2>/dev/null || true
    fi
    chown -R kohadev:kohadev /kohadevbox/koha 2>/dev/null || true
    if id "kohadev-koha" >/dev/null 2>&1; then
        mkdir -p /var/lib/koha/kohadev /var/log/koha/kohadev /var/cache/koha/kohadev
        chown -R kohadev-koha:kohadev-koha /var/lib/koha/kohadev /var/log/koha/kohadev /var/cache/koha/kohadev 2>/dev/null || true
        chmod 775 /var/lib/koha/kohadev 2>/dev/null || true
        chmod -R g+rw /var/lib/koha/kohadev 2>/dev/null || true
        sudo -u kohadev-koha git config --global --add safe.directory /kohadevbox/koha 2>/dev/null || true
        sudo -u kohadev git config --global --add safe.directory /kohadevbox/koha 2>/dev/null || true
    fi
}

copy_runtime_files() {
    echo "[copy_runtime_files] Installing Koha debian scripts to /usr/local/bin"
    mkdir -p /usr/local/bin /usr/sbin
    if [ "${KOHA_ALPINE_SKIP_DEBIAN_SCRIPTS:-no}" != "yes" ] && [ "${SKIP_RUNTIME_ASSET_COPY:-no}" != "yes" ]; then
        if [ -d "${BUILD_DIR}/koha/debian/scripts" ]; then
            cp -v ${BUILD_DIR}/koha/debian/scripts/koha-* /usr/local/bin/ 2>/dev/null || true
            cp -v ${BUILD_DIR}/koha/debian/scripts/koha-* /usr/sbin/ 2>/dev/null || true
            chmod +x /usr/local/bin/koha-* /usr/sbin/koha-* 2>/dev/null || true
        fi
    else
        echo "[copy_runtime_files] Skipping Debian script copy (prod)"
    fi
    echo "[copy_runtime_files] Restoring Alpine-native koha-* overrides"
    if [ -f "/opt/alpine-koha-create" ]; then
        install -m 0755 /opt/alpine-koha-create /usr/local/bin/koha-create
        install -m 0755 /opt/alpine-koha-create /usr/sbin/koha-create
        echo "[copy_runtime_files] -> restored Alpine koha-create from /opt/alpine-koha-create"
    fi
    if [ -d "${BUILD_DIR}/files-alpine/scripts" ]; then
        for script_name in koha-create koha-plack koha-worker koha-functions.sh; do
            if [ -f "${BUILD_DIR}/files-alpine/scripts/${script_name}" ]; then
                install -m 0755 "${BUILD_DIR}/files-alpine/scripts/${script_name}" "/usr/sbin/${script_name}" 2>/dev/null || true
                install -m 0755 "${BUILD_DIR}/files-alpine/scripts/${script_name}" "/usr/local/bin/${script_name}" 2>/dev/null || true
            fi
        done
    fi
    cat > /usr/local/bin/koha-create-dirs <<'EOS'
#!/bin/sh
name="$1"
[ -z "$name" ] && exit 1
user="${name}-koha"
mkdir -p /etc/koha/sites/$name /var/lib/koha/$name /var/lib/koha/$name/plugins /var/cache/koha/$name /var/log/koha/$name /var/run/koha/$name /var/lock/koha/$name
chown -R $user:$user /var/lib/koha/$name /var/cache/koha/$name /var/log/koha/$name /var/run/koha/$name 2>/dev/null || true
EOS
    chmod +x /usr/local/bin/koha-create-dirs
    cp /usr/local/bin/koha-create-dirs /usr/sbin/koha-create-dirs
    if [ ! -f /etc/koha/koha-conf-site.xml.in ]; then
        echo "[copy_runtime_files] Installing /etc/koha templates"
        mkdir -p /etc/koha
        for src in "${BUILD_DIR}/koha/debian/templates" "${BUILD_DIR}/koha/etc" "/build/files-alpine/templates" "/kohadevbox/templates"; do
            if [ -d "$src" ]; then cp -v "$src"/*.in /etc/koha/ 2>/dev/null || true; fi
        done
        ls -l /etc/koha/*.in 2>/dev/null || echo "[copy_runtime_files] WARNING: still no templates"
    fi
    ensure_compat_files
    if [ "${SKIP_RUNTIME_ASSET_COPY:-no}" = "yes" ]; then echo "[copy_runtime_files] Build-time assets pre-staged; skipping runtime copy."; return 0; fi
    if [ -x /usr/local/bin/build-alpine-package.sh ]; then /usr/local/bin/build-alpine-package.sh; elif [ -x /build/files-alpine/build-alpine-package.sh ]; then /build/files-alpine/build-alpine-package.sh; else echo "[service] No build-alpine-package.sh - skipping"; fi
}

render_vhost() {
    local instance=$1
    mkdir -p /etc/apache2/sites-available
    if [ -f "${BUILD_DIR}/templates/koha-vhost.conf.in" ]; then
        envsubst '${KOHA_INSTANCE} ${KOHA_PATH}' < "${BUILD_DIR}/templates/koha-vhost.conf.in" > "/etc/apache2/sites-available/${instance}.conf"
    else
        echo "[render_vhost] WARNING: no vhost template, creating minimal"
        echo "<VirtualHost *:80>ServerName localhost</VirtualHost>" > "/etc/apache2/sites-available/${instance}.conf"
    fi
    if ! grep -q "ServerTokens Prod" "/etc/apache2/sites-available/${instance}.conf"; then printf '\nServerTokens Prod\nServerSignature Off\n' >> "/etc/apache2/sites-available/${instance}.conf"; fi
    chown ${instance}-koha:root "/etc/apache2/sites-available/${instance}.conf" 2>/dev/null || true
    chmod 644 "/etc/apache2/sites-available/${instance}.conf"
    echo "[render_vhost] Wrote /etc/apache2/sites-available/${instance}.conf (KOHA_PATH=${KOHA_PATH})"
}

enable_instance_services() {
    if command -v koha-plack >/dev/null 2>&1; then koha-plack --enable "${KOHA_INSTANCE}" >/dev/null 2>&1 || echo "[INFO] koha-plack not enabled; continuing with Apache CGI"; fi
    if command -v koha-z3950-responder >/dev/null 2>&1; then koha-z3950-responder --enable "${KOHA_INSTANCE}" >/dev/null 2>&1 || echo "[INFO] koha-z3950-responder enable skipped"; fi
}

start_koha_service() {
    if command -v koha-plack >/dev/null 2>&1; then koha-plack --start "${KOHA_INSTANCE}" >/dev/null 2>&1 || true; fi
    if command -v koha-worker >/dev/null 2>&1; then koha-worker --start "${KOHA_INSTANCE}" >/dev/null 2>&1 || true; else echo "[service] koha-worker not available"; fi
}

stop_apache_service() { if command -v httpd >/dev/null 2>&1; then httpd -k stop >/dev/null 2>&1 || true; fi; }
start_apache_service() { if command -v httpd >/dev/null 2>&1; then httpd -k start >/dev/null 2>&1 || true; return 0; fi; echo "[service] httpd not available"; }

bootstrap_koha_instance() { echo "[bootstrap] handled in run.sh"; }

sync_l10n() {
    if [ "${SKIP_L10N:-no}" = "yes" ] || [ "${KOHA_ALPINE_SKIP_L10N:-no}" = "yes" ]; then echo "[koha-l10n] Skipping (prod)"; return 0; fi
    echo "[koha-l10n] Handling koha-l10n as requested"
}

setup_git_workflow() {
    if [ "${KOHA_ALPINE_SKIP_GIT_SETUP:-no}" = "yes" ]; then echo "[git] Skipped (prod)"; return 0; fi
    echo "[git] Setting up Git on the instance user"
    mkdir -p /var/lib/koha/${KOHA_INSTANCE}
    chown ${KOHA_INSTANCE}-koha:${KOHA_INSTANCE}-koha /var/lib/koha/${KOHA_INSTANCE} 2>/dev/null || true
}

install_git_hooks() { echo "[git] hooks skipped"; }

start_crond() {
    if [ "${KOHA_ALPINE_ENABLE_CROND:-yes}" = "no" ]; then echo "[crond] Disabled"; return 0; fi
    if command -v crond >/dev/null 2>&1; then crond -b -l 2 2>/dev/null || true; echo "[crond] Alpine crond started"; fi
}

run_service_watchdog() {
    local instance="${1:-kohadev}"; local interval="${2:-30}"; local _plack_expected=no; local _worker_expected=no; local _watchdog_sleep_pid=0
    if command -v koha-plack >/dev/null 2>&1; then koha-plack --status "${instance}" >/dev/null 2>&1 && _plack_expected=yes || true; fi
    if command -v koha-worker >/dev/null 2>&1; then koha-worker --status "${instance}" >/dev/null 2>&1 && _worker_expected=yes || true; fi
    echo "[watchdog] Service watchdog started (instance=${instance}, plack=${_plack_expected}, worker=${_worker_expected}, interval=${interval}s)"
    trap 'echo "[watchdog] Shutdown signal received; stopping services..."; kill ${_watchdog_sleep_pid} 2>/dev/null || true; command -v koha-plack >/dev/null 2>&1 && koha-plack --stop "'"${instance}"'" >/dev/null 2>&1 || true; command -v koha-worker >/dev/null 2>&1 && koha-worker --stop "'"${instance}"'" >/dev/null 2>&1 || true; echo "[watchdog] Done."; exit 0' TERM INT
    while true; do
        if [ "${_plack_expected}" = "yes" ]; then koha-plack --status "${instance}" >/dev/null 2>&1 || { echo "[watchdog] koha-plack is down; restarting..."; koha-plack --start "${instance}" >/dev/null 2>&1 || true; }; fi
        if [ "${_worker_expected}" = "yes" ]; then koha-worker --status "${instance}" >/dev/null 2>&1 || { echo "[watchdog] koha-worker is down; restarting..."; koha-worker --start "${instance}" >/dev/null 2>&1 || true; }; fi
        sleep "${interval}" & _watchdog_sleep_pid=$!; wait ${_watchdog_sleep_pid} || true
    done
}
