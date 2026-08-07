#!/bin/bash
# Alpine compatibility helpers for files-alpine/run.sh.
# v2 hardened - prod prebuilt assets, security hardening, llama probe
# Patched v2026-08-06 final - fixes koha-common, koha-functions.sh, perms
if [ "${KOHA_TARGET}" = "prod-runtime" ]; then
  KOHA_ALPINE_SKIP_YARN_INSTALL=yes
  KOHA_ALPINE_SKIP_GIT_SETUP=yes
  KOHA_ALPINE_SKIP_L10N=yes
  KOHA_ALPINE_SKIP_ELASTICSEARCH_WAIT=yes
  SKIP_RUNTIME_ASSET_COPY=yes
  export KOHA_ALPINE_SKIP_YARN_INSTALL SKIP_RUNTIME_ASSET_COPY KOHA_ALPINE_SKIP_ELASTICSEARCH_WAIT KOHA_ALPINE_SKIP_GIT_SETUP KOHA_ALPINE_SKIP_L10N
fi
# prod skips
[ "${KOHA_ALPINE_SKIP_GIT_SETUP:-no}" = "yes" ] && git_setup() { echo "[git] Skipped (prod)"; return 0; }
[ "${KOHA_ALPINE_SKIP_YARN_INSTALL:-no}" = "yes" ] && yarn_install() { echo "[yarn] Skipped (prod)"; return 0; }
[ "${KOHA_ALPINE_SKIP_L10N:-no}" = "yes" ] && handle_l10n() { echo " Skipped (prod)"; return 0; }
[ "${KOHA_ALPINE_SKIP_ELASTICSEARCH_WAIT:-no}" = "yes" ] && wait_for_elasticsearch() { echo "[elasticsearch] Skipped (prod) -> $ELASTICSEARCH_SERVER"; return 0; }

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
        printf '[client]\nhost     = %s\nuser     = root\npassword = %s\n'             "${DB_HOSTNAME}" "${KOHA_DB_ROOT_PASSWORD}"
        if [ "${KOHA_DB_USE_TLS:-}" = "yes" ]; then
            printf 'ssl      = on\n'
            [ -n "${KOHA_DB_TLS_CA_CERTIFICATE:-}" ]     && printf 'ssl-ca   = %s\n' "${KOHA_DB_TLS_CA_CERTIFICATE}" || true
            [ -n "${KOHA_DB_TLS_CLIENT_CERTIFICATE:-}" ] && printf 'ssl-cert = %s\n' "${KOHA_DB_TLS_CLIENT_CERTIFICATE}" || true
            [ -n "${KOHA_DB_TLS_CLIENT_KEY:-}" ]         && printf 'ssl-key  = %s\n' "${KOHA_DB_TLS_CLIENT_KEY}" || true
        else
            printf 'ssl      = off\nskip-ssl\n'
        fi
    } > /etc/mysql/koha-common.cnf
    cp /etc/mysql/koha-common.cnf /etc/mysql/debian.cnf
    chmod 600 /etc/mysql/debian.cnf
    chmod 600 /etc/mysql/koha-common.cnf
    {
        printf '[client]\nhost     = %s\nuser     = %s\npassword = %s\n'             "${DB_HOSTNAME}" "${DB_USER}" "${DB_PASSWORD}"
        if [ "${KOHA_DB_USE_TLS:-}" = "yes" ]; then
            printf 'ssl      = on\n'
            [ -n "${KOHA_DB_TLS_CA_CERTIFICATE:-}" ]     && printf 'ssl-ca   = %s\n' "${KOHA_DB_TLS_CA_CERTIFICATE}" || true
            [ -n "${KOHA_DB_TLS_CLIENT_CERTIFICATE:-}" ] && printf 'ssl-cert = %s\n' "${KOHA_DB_TLS_CLIENT_CERTIFICATE}" || true
            [ -n "${KOHA_DB_TLS_CLIENT_KEY:-}" ]         && printf 'ssl-key  = %s\n' "${KOHA_DB_TLS_CLIENT_KEY}" || true
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
        local installed_packages=(); local package_name
        for package_name in "$@"; do
            if apk info -e "$package_name" >/dev/null 2>&1; then installed_packages+=("$package_name"); fi
        done
        if [ "${#installed_packages[@]}" -gt 0 ]; then apk del "${installed_packages[@]}" || true; fi
        return 0
    fi
    echo "[packages] No supported package manager found"; return 1
}

service_status_all() {
    if command -v rc-status >/dev/null 2>&1; then rc-status -a || true; return 0; fi
    echo "[service] No service status command available"
}

ensure_runtime_dirs() {
    mkdir -p /etc/mysql /etc/koha /etc/koha/zebradb /etc/koha/zebradb/marc_defs /etc/sudoers.d /var/cache/koha /var/lib/koha /var/log/koha /var/run/koha /var/lock/koha
}

run_koha_shell() {
    local instance=$1; shift
    if command -v koha-shell >/dev/null 2>&1; then sudo koha-shell "$instance" -c "$*" 2>/dev/null || sudo -u ${instance}-koha sh -c "$*" 2>/dev/null || sh -c "$*"; return 0; fi
    echo "[koha-shell] WARNING: koha-shell not available; skipping: $*"
}

ensure_compat_files() {
    echo "[compat] Ensuring Debian-compat files exist"
    mkdir -p /etc/default /usr/share/koha/bin /etc/koha/sites/kohadev
    if [ ! -f /etc/default/koha-common ]; then
        cat > /etc/default/koha-common <<'EOF'
# Alpine compat stub for koha-common
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
    # Fix ownership BEFORE git steps
    chown -R kohadev:kohadev /kohadevbox/koha 2>/dev/null || true
    if id "kohadev-koha" >/dev/null 2>&1; then
        mkdir -p /var/lib/koha/kohadev /var/log/koha/kohadev /var/cache/koha/kohadev
        chown -R kohadev-koha:kohadev-koha /var/lib/koha/kohadev /var/log/koha/kohadev /var/cache/koha/kohadev 2>/dev/null || true
        chmod 775 /var/lib/koha/kohadev 2>/dev/null || true
        chmod -R g+rw /var/lib/koha/kohadev 2>/dev/null || true
        # Also make git safe
        sudo -u kohadev-koha git config --global --add safe.directory /kohadevbox/koha 2>/dev/null || true
        sudo -u kohadev git config --global --add safe.directory /kohadevbox/koha 2>/dev/null || true
    fi
}

copy_runtime_files() {
    echo "[copy_runtime_files] Installing Koha debian scripts to /usr/local/bin"
    mkdir -p /usr/local/bin /usr/sbin
    if [ -d "${BUILD_DIR}/koha/debian/scripts" ]; then
        cp -v ${BUILD_DIR}/koha/debian/scripts/koha-* /usr/local/bin/ 2>/dev/null || true
        cp -v ${BUILD_DIR}/koha/debian/scripts/koha-* /usr/sbin/ 2>/dev/null || true
        chmod +x /usr/local/bin/koha-* /usr/sbin/koha-* 2>/dev/null || true
    fi
    if [ -d "${BUILD_DIR}/koha/bin" ]; then
        cp -v ${BUILD_DIR}/koha/bin/koha-* /usr/local/bin/ 2>/dev/null || true
        chmod +x /usr/local/bin/koha-* 2>/dev/null || true
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
    for f in /usr/local/bin/koha-* /usr/sbin/koha-*; do
        [ -f "$f" ] || continue
        grep -q "opt/koha-perl/lib/perl5" "$f" 2>/dev/null && continue
        first=$(head -1 "$f" 2>/dev/null || echo "")
        case "$first" in
            *perl*)
                # Only inject if not already perl lib injection
                if ! grep -q "koha-perl" "$f"; then
                    sed -i '1a BEGIN { unshift @INC, "/opt/koha-perl/lib/perl5", "/kohadevbox/koha/lib"; }' "$f" 2>/dev/null || true
                fi
                ;;
            *)
                if ! grep -q "PERL5LIB" "$f"; then
                    sed -i '1a export PERL5LIB="/opt/koha-perl/lib/perl5:/kohadevbox/koha/lib:/usr/local/lib/perl5/site_perl:/usr/local/share/perl5/site_perl:${PERL5LIB:-}"' "$f" 2>/dev/null || true
                fi
                ;;
        esac
    done
    # --- CRITICAL: call compat fix here so it always runs ---
    ensure_compat_files

    if [ "${SKIP_RUNTIME_ASSET_COPY}" = "yes" ]; then echo "[copy_runtime_files] Build-time assets pre-staged; skipping runtime copy."; return 0; fi
    if [ -x /usr/local/bin/build-alpine-package.sh ]; then /usr/local/bin/build-alpine-package.sh; elif [ -x /build/files-alpine/build-alpine-package.sh ]; then /build/files-alpine/build-alpine-package.sh; else echo "[service] No build-alpine-package.sh - skipping"; fi
}

render_vhost() {
    local instance=$1
    mkdir -p /etc/apache2/sites-available
    envsubst "${VARS_TO_SUB}" < "${BUILD_DIR}/templates/koha-vhost.conf.in" > "/etc/apache2/sites-available/${instance}.conf"
    if ! grep -q "ServerTokens Prod" "/etc/apache2/sites-available/${instance}.conf"; then printf '\nServerTokens Prod\nServerSignature Off\n' >> "/etc/apache2/sites-available/${instance}.conf"; fi
    chown ${instance}-koha:root "/etc/apache2/sites-available/${instance}.conf" 2>/dev/null || true
    chmod 644 "/etc/apache2/sites-available/${instance}.conf"
    echo "[render_vhost] Wrote /etc/apache2/sites-available/${instance}.conf (KOHA_PATH=${KOHA_PATH})"
}

enable_instance_services() {
    if command -v koha-plack >/dev/null 2>&1; then if ! koha-plack --enable "${KOHA_INSTANCE}" >/dev/null 2>&1; then echo "[INFO] koha-plack not enabled; continuing with Apache CGI"; fi; else echo "[INFO] koha-plack not available"; fi
    if command -v koha-z3950-responder >/dev/null 2>&1; then if ! koha-z3950-responder --enable "${KOHA_INSTANCE}" >/dev/null 2>&1; then echo "[INFO] koha-z3950-responder enable skipped"; fi; else echo "[INFO] koha-z3950-responder not available"; fi
}

start_koha_service() {
    if command -v koha-plack >/dev/null 2>&1; then koha-plack --start "${KOHA_INSTANCE}" >/dev/null 2>&1 || true; fi
    if command -v koha-worker >/dev/null 2>&1; then koha-worker --start "${KOHA_INSTANCE}" >/dev/null 2>&1 || true; else echo "[service] koha-worker not available"; fi
}

stop_apache_service() { if command -v httpd >/dev/null 2>&1; then httpd -k stop >/dev/null 2>&1 || true; fi; }
start_apache_service() { if command -v httpd >/dev/null 2>&1; then httpd -k start >/dev/null 2>&1 || true; return 0; fi; echo "[service] httpd not available"; }

bootstrap_koha_instance() {
    if command -v koha-create >/dev/null 2>&1; then
        local koha_create_mode; koha_create_mode=${KOHA_CREATE_MODE:---create-db}
        if [ -n "${DB_NAME:-}" ] && command -v mysql >/dev/null 2>&1 && [ -f /etc/mysql/koha-common.cnf ] && mysql --defaults-extra-file=/etc/mysql/koha-common.cnf -Nse "SHOW DATABASES LIKE '${DB_NAME}'" 2>/dev/null | grep -qx "${DB_NAME}"; then koha_create_mode="--use-db"; echo "[koha-create] Detected existing database ${DB_NAME}; using --use-db"; fi
        if ! koha-create "${koha_create_mode}" --db-user "${DB_USER}" --db-password "${DB_PASSWORD}" --db-name "${DB_NAME}" --memcached-servers memcached:11211 --mb-host "${MESSAGE_BROKER_HOST}" --mb-port "${MESSAGE_BROKER_PORT}" --mb-user "${MESSAGE_BROKER_USER}" --mb-pass "${MESSAGE_BROKER_PASS}" --mb-vhost "${MESSAGE_BROKER_VHOST}" "${KOHA_INSTANCE}"; then echo "[koha-create] WARNING: bootstrap failed in Alpine compatibility mode; continuing"; fi
        return 0
    fi
    echo "[koha-create] WARNING: koha-create not available; skipping"
}

sync_l10n() {
    if [ "${SKIP_L10N}" = "yes" ]; then echo "[koha-l10n] Skipping"; return 0; fi
    local l10n_branch; if [[ ! -z "$KOHA_IMAGE" && ! "$KOHA_IMAGE" =~ ^main ]]; then l10n_branch=${KOHA_IMAGE:0:5}; else l10n_branch="main"; fi
    set +e
    echo "[koha-l10n] Handling koha-l10n as requested"
    if [ "${SKIP_RUNTIME_ASSET_COPY}" = "yes" ] && [ "${SKIP_L10N:-yes}" = "yes" ]; then echo "[koha-l10n] Prod image - skipping l10n clone"; set -e; return 0; fi
    if [ ! -d "$BUILD_DIR/koha/misc/translator/po" ]; then
        echo "    [*] Cloning koha-l10n into misc/translator/po"
        # Make writable
        mkdir -p "$BUILD_DIR/koha/misc/translator"
        chown -R kohadev:kohadev "$BUILD_DIR/koha/misc" 2>/dev/null || true
        run_koha_shell "${KOHA_INSTANCE}" "git clone --depth 1 --branch ${l10n_branch} https://gitlab.com/koha-community/koha-l10n.git $BUILD_DIR/koha/misc/translator/po" || echo "    [x] l10n clone failed (non-fatal)"
    elif [ -d "$BUILD_DIR/koha/misc/translator/po/.git" ]; then
        echo "    [*] Chowning po files"
        chown -R "${KOHA_INSTANCE}-koha" "$BUILD_DIR/koha/misc/translator/po" 2>/dev/null || true
        echo "    [*] Fetching koha-l10n"
        run_koha_shell "${KOHA_INSTANCE}" "git config --global --add safe.directory $BUILD_DIR/koha/misc/translator/po ; git -C $BUILD_DIR/koha/misc/translator/po fetch origin ; git -C $BUILD_DIR/koha/misc/translator/po checkout -B ${l10n_branch} origin/${l10n_branch}" || true
    fi
    set -e
}

setup_git_workflow() {
    echo "[git] Setting up Git on the instance user"
    # Ensure home exists and owned
    mkdir -p /var/lib/koha/${KOHA_INSTANCE}
    chown ${KOHA_INSTANCE}-koha:${KOHA_INSTANCE}-koha /var/lib/koha/${KOHA_INSTANCE} 2>/dev/null || true
    echo "    [*] Generating /var/lib/koha/${KOHA_INSTANCE}/.gitconfig"
    if [ -f ${BUILD_DIR}/templates/gitconfig ]; then
        cp ${BUILD_DIR}/templates/gitconfig /var/lib/koha/${KOHA_INSTANCE}/.gitconfig 2>/dev/null || true
        chown ${KOHA_INSTANCE}-koha:${KOHA_INSTANCE}-koha /var/lib/koha/${KOHA_INSTANCE}/.gitconfig 2>/dev/null || true
    fi
    echo "    [*] General setup"
    run_koha_shell "${KOHA_INSTANCE}" "cd ${BUILD_DIR}/koha ; git config --global --add safe.directory ${BUILD_DIR}/koha ; git config --global user.name "${GIT_USER_NAME}" ; git config --global user.email "${GIT_USER_EMAIL}" ; git config bz.default-tracker bugs.koha-community.org ; git config bz.default-product Koha ; git config --global bz-tracker.bugs.koha-community.org.path /bugzilla3 ; git config --global bz-tracker.bugs.koha-community.org.https true ; git config --global core.whitespace trailing-space,space-before-tab ; git config --global apply.whitespace fix ; git config --global bz-tracker.bugs.koha-community.org.bz-user "${GIT_BZ_USER}" ; git config --global bz-tracker.bugs.koha-community.org.bz-password "${GIT_BZ_PASSWORD}" " || true
}

install_git_hooks() {
    local git_base_dir=$1
    if [ "${GIT_WORKTREE_SOURCE}" != "" ]; then
        echo "    [!] Detected worktree: pointing to '${GIT_WORKTREE_SOURCE}'"
        git_base_dir=${GIT_WORKTREE_SOURCE}
        run_koha_shell "${KOHA_INSTANCE}" "cd ${BUILD_DIR}/koha ; git config --global --add safe.directory ${GIT_WORKTREE_SOURCE}"
        echo "    [*] Added '${GIT_WORKTREE_SOURCE}' to safe directories"
    fi
    if [ "${GIT_WORKTREE_SOURCE}" != "" ]; then echo "    [!] Skipping hooks setup"; else
        echo "    [*] Installing and setting hooks (${git_base_dir})"
        run_koha_shell "${KOHA_INSTANCE}" "mkdir -p ${git_base_dir}/.git/hooks/ktd ; cp ${BUILD_DIR}/git_hooks/* ${git_base_dir}/.git/hooks/ktd 2>/dev/null || true ; cd ${git_base_dir} ; git config --local core.hooksPath .git/hooks/ktd" || true
    fi
}

start_crond() {
    if [ "${KOHA_ALPINE_ENABLE_CROND:-yes}" = "no" ]; then echo "[crond] Disabled via KOHA_ALPINE_ENABLE_CROND=no"; return 0; fi
    if command -v crond >/dev/null 2>&1; then crond -b -l 2 2>/dev/null || true; echo "[crond] Alpine crond started"; else echo "[crond] WARNING: crond not available"; fi
}

run_service_watchdog() {
    local instance="${1:-kohadev}"; local interval="${2:-30}"; local _plack_expected=no; local _worker_expected=no; local _watchdog_sleep_pid=0
    if command -v koha-plack >/dev/null 2>&1; then koha-plack --status "${instance}" >/dev/null 2>&1 && _plack_expected=yes || true; fi
    if command -v koha-worker >/dev/null 2>&1; then koha-worker --status "${instance}" >/dev/null 2>&1 && _worker_expected=yes || true; fi
    echo "[watchdog] Service watchdog started (instance=${instance}, plack=${_plack_expected}, worker=${_worker_expected}, interval=${interval}s)"
    trap 'echo "[watchdog] Shutdown signal received; stopping services..."; kill ${_watchdog_sleep_pid} 2>/dev/null || true; command -v koha-plack  >/dev/null 2>&1 && koha-plack  --stop "'"${instance}"'" >/dev/null 2>&1 || true; command -v koha-worker >/dev/null 2>&1 && koha-worker --stop "'"${instance}"'" >/dev/null 2>&1 || true; echo "[watchdog] Done."; exit 0' TERM INT
    while true; do
        if [ "${_plack_expected}" = "yes" ]; then koha-plack --status "${instance}" >/dev/null 2>&1 || { echo "[watchdog] koha-plack is down; restarting..."; koha-plack --start "${instance}" >/dev/null 2>&1 || true; }; fi
        if [ "${_worker_expected}" = "yes" ]; then koha-worker --status "${instance}" >/dev/null 2>&1 || { echo "[watchdog] koha-worker is down; restarting..."; koha-worker --start "${instance}" >/dev/null 2>&1 || true; }; fi
        if [ -n "${KOHA_LLAMA_URL:-}" ]; then
            if command -v wget >/dev/null 2>&1; then wget -qO- "${KOHA_LLAMA_URL}/health" >/dev/null 2>&1 || echo "[watchdog] llama sidecar ${KOHA_LLAMA_URL} not responding"; elif command -v curl >/dev/null 2>&1; then curl -sf "${KOHA_LLAMA_URL}/health" >/dev/null 2>&1 || echo "[watchdog] llama sidecar ${KOHA_LLAMA_URL} not responding"; fi
        fi
        sleep "${interval}" & _watchdog_sleep_pid=$!; wait ${_watchdog_sleep_pid} || true
    done
}
