#!/bin/bash
# run.sh — Koha container entrypoint.
# NOTE: This file is BAKED INTO THE IMAGE at build time (see Dockerfile: COPY files-alpine/run.sh).
# Editing this file on the host has NO effect until the image is rebuilt:
#   ./stack.sh start -b   (or docker compose build)
# RUN_SH_VERSION=2026-07-22-patched

set -e
trap 'rc=$?; echo "[run.sh] ERROR line ${LINENO}: ${BASH_COMMAND} (exit ${rc})" >&2' ERR

export BUILD_DIR=/kohadevbox
export TEMP=/tmp
export TZ=${TZ:-UTC}

# Port defaults
export KOHA_INTRANET_PORT=${KOHA_INTRANET_PORT:-8081}
export KOHA_OPAC_PORT=${KOHA_OPAC_PORT:-8080}

# Handy variables
export KOHA_INTRANET_FQDN=${KOHA_INTRANET_PREFIX}${KOHA_INSTANCE}${KOHA_INTRANET_SUFFIX}${KOHA_DOMAIN}
export KOHA_OPAC_FQDN=${KOHA_OPAC_PREFIX}${KOHA_INSTANCE}${KOHA_OPAC_SUFFIX}${KOHA_DOMAIN}

if [ -z ${KOHA_OPAC_URL} ]; then
    _pub_port="${KOHA_PUBLIC_PORT:-80}"
    if [ -z "${_pub_port}" ] || [ "${_pub_port}" = "80" ]; then
        export KOHA_OPAC_URL=http://${KOHA_OPAC_FQDN}
    else
        export KOHA_OPAC_URL=http://${KOHA_OPAC_FQDN}:${_pub_port}
    fi
    unset _pub_port
fi
if [ -z ${KOHA_INTRANET_URL} ]; then
    _pub_port="${KOHA_PUBLIC_PORT:-80}"
    if [ -z "${_pub_port}" ] || [ "${_pub_port}" = "80" ]; then
        export KOHA_INTRANET_URL=http://${KOHA_INTRANET_FQDN}
    else
        export KOHA_INTRANET_URL=http://${KOHA_INTRANET_FQDN}:${_pub_port}
    fi
    unset _pub_port
fi

export MESSAGE_BROKER_HOST=${MESSAGE_BROKER_HOST:-rabbitmq}
export MESSAGE_BROKER_PORT=${MESSAGE_BROKER_PORT:-61613}
export MESSAGE_BROKER_USER=${MESSAGE_BROKER_USER:-koha}
export MESSAGE_BROKER_PASS=${MESSAGE_BROKER_PASS:-${KOHA_DB_PASSWORD}}
export MESSAGE_BROKER_VHOST=${MESSAGE_BROKER_VHOST:-koha_${KOHA_INSTANCE}}

export PATH=${PATH}:/kohadevbox/bin:/kohadevbox/koha/node_modules/.bin/:/kohadevbox/node_modules/.bin/
export NODE_PATH=/kohadevbox/node_modules:$NODE_PATH

. /kohadevbox/lib/run-sh-alpine.sh

if [ "${DEBUG_RUN}" = "yes" ]; then
    echo "DEBUG_RUN_URL=$DEBUG_RUN_URL";
    wget ${DEBUG_RUN_URL} -O /tmp/run.sh
    bash /tmp/run.sh
    exit
fi

echo "kohadevbox" > /etc/hostname

if [ ! -f "${BUILD_DIR}/koha/about.pl" ]; then
    echo "The environment variable SYNC_REPO does not point to a valid Koha git repository."
    exit 2
fi

if [ -d "${BUILD_DIR}/koha/koha-tmpl" ]; then
    export KOHA_PATH="${BUILD_DIR}/koha"
else
    export KOHA_PATH="/usr/share/koha"
fi
export KOHA_LIB_PATH="${KOHA_PATH}/lib"

if [ "${CPAN}" = "yes" ]; then
    echo "Installing latest versions of dependancies from cpan"
    if command -v cpan-outdated >/dev/null 2>&1; then
        cpan-outdated --exclude-core -p | cpanm
    else
        echo "[cpan] cpan-outdated not available; falling back to cpanm --installdeps"
        cpanm --skip-installed --installdeps ${BUILD_DIR}/koha/
    fi
fi

if [ "${INSTALL_MISSING_FROM_CPANFILE}" = "yes" ]; then
    cpanm --skip-installed --installdeps ${BUILD_DIR}/koha/
fi

if [ -n "${EXTRA_APT}" ]; then
    echo "Installing requested OS packages using the local package manager: ${EXTRA_APT}"
    install_os_packages ${EXTRA_APT}
fi

if [ -n "${EXTRA_CPAN}" ]; then
    echo "Installing requested Perl libraries: ${EXTRA_CPAN}"
    cpanm --skip-installed ${EXTRA_CPAN}
fi

append_if_absent "127.0.0.1 kohadevbox" /etc/hosts
if command -v hostname >/dev/null 2>&1; then
  hostname kohadevbox 2>/dev/null || true
fi

service_status_all

if [ "${DEBUG_GIT_REPO_MISC4DEV}" = "yes" ]; then
    rm -rf ${BUILD_DIR}/misc4dev
    git clone -b ${DEBUG_GIT_REPO_MISC4DEV_BRANCH} ${DEBUG_GIT_REPO_MISC4DEV_URL} ${BUILD_DIR}/misc4dev
fi

if [ "${DEBUG_GIT_REPO_QATESTTOOLS}" = "yes" ]; then
    rm -rf ${BUILD_DIR}/qa-test-tools
    git clone -b ${DEBUG_GIT_REPO_QATESTTOOLS_BRANCH} ${DEBUG_GIT_REPO_QATESTTOOLS_URL} ${BUILD_DIR}/qa-test-tools
fi

copy_runtime_files

while ! nc -z db 3306; do sleep 1; done

ensure_runtime_dirs

export DB_NAME="koha_${KOHA_INSTANCE}"
export DB_PASSWORD=${KOHA_DB_PASSWORD}
export DB_USER="koha_${KOHA_INSTANCE}"
export KOHA_DB_USE_TLS=${KOHA_DB_USE_TLS:-yes}
export KOHA_DB_TLS_CA_CERTIFICATE=${KOHA_DB_TLS_CA_CERTIFICATE:-/etc/mysql/ssl/ca-cert.pem}
export KOHA_DB_TLS_CLIENT_CERTIFICATE=${KOHA_DB_TLS_CLIENT_CERTIFICATE:-}
export KOHA_DB_TLS_CLIENT_KEY=${KOHA_DB_TLS_CLIENT_KEY:-}

if [ "${KOHA_DB_USE_TLS}" = "yes" ] && { [ -z "${KOHA_DB_TLS_CLIENT_CERTIFICATE}" ] || [ -z "${KOHA_DB_TLS_CLIENT_KEY}" ]; }; then
    echo "[db-tls] KOHA_DB_USE_TLS=yes with no client cert/key pair; using CA-verified server TLS only"
fi

if [ "${KOHA_DB_USE_TLS}" = "yes" ]; then
    export MYSQL_OPT_SKIP_SSL=0
    export PERL_DBD_MYSQL_SSL_VERIFY_SERVER_CERT=0
else
    export MYSQL_OPT_SKIP_SSL=1
    export PERL_DBD_MYSQL_SSL_VERIFY_SERVER_CERT=0
fi

if [ "${KOHA_DB_USE_TLS}" = "yes" ]; then
    export __DB_USE_TLS__="yes"
else
    export __DB_USE_TLS__="no"
fi
export __DB_TLS_CA_CERTIFICATE__="${KOHA_DB_TLS_CA_CERTIFICATE}"
export __DB_TLS_CLIENT_CERTIFICATE__="${KOHA_DB_TLS_CLIENT_CERTIFICATE}"
export __DB_TLS_CLIENT_KEY__="${KOHA_DB_TLS_CLIENT_KEY}"

write_db_client_configs "${KOHA_INSTANCE}"

if [ -f /etc/apache2/httpd.conf ]; then
    append_if_absent "ServerName kohadevbox" /etc/apache2/httpd.conf
    append_if_absent "Listen ${KOHA_INTRANET_PORT:-8081}" /etc/apache2/httpd.conf
    append_if_absent "Listen ${KOHA_OPAC_PORT:-8080}" /etc/apache2/httpd.conf
fi

# Find defaults.env in either location (templates/ or env/)
if [ -f "${BUILD_DIR}/templates/defaults.env" ]; then
  _defaults_path="${BUILD_DIR}/templates/defaults.env"
elif [ -f "${BUILD_DIR}/env/defaults.env" ]; then
  _defaults_path="${BUILD_DIR}/env/defaults.env"
else
  echo "[run.sh] FATAL: defaults.env not found in templates/ or env/" >&2
  ls -la ${BUILD_DIR}/templates/ ${BUILD_DIR}/env/ 2>&1 || true
  exit 1
fi
VARS_TO_SUB=$(grep -v '^[[:space:]]*#' "${_defaults_path}" | grep '=' | cut -d '=' -f1 | tr '\n' ':' | sed -e 's/:/:$/g' | sed -e 's/:\$$//' | sed -e 's/^/\$/')
VARS_TO_SUB="\$DB_NAME:\$DB_PASSWORD:\$DB_USER:\$BUILD_DIR:\$KOHA_PATH:\$KOHA_LIB_PATH:\$__DB_USE_TLS__:\$__DB_TLS_CA_CERTIFICATE__:\$__DB_TLS_CLIENT_CERTIFICATE__:\$__DB_TLS_CLIENT_KEY__:$VARS_TO_SUB";

# Ensure bin dir exists before writing
mkdir -p ${BUILD_DIR}/bin
mkdir -p /root /etc/koha /var/lib/koha/${KOHA_INSTANCE} /var/lib/koha/kohadev 2>/dev/null || true

envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/root_bashrc           > /root/.bashrc
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/vimrc                 > /root/.vimrc
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/bash_aliases          > /root/.bash_aliases
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/koha-conf-site.xml.in > /etc/koha/koha-conf-site.xml.in
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/koha-sites.conf       > /etc/koha/koha-sites.conf
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/sudoers               > /etc/sudoers.d/${KOHA_INSTANCE}

perl -0pi -e 's/__DB_USE_TLS__/$ENV{__DB_USE_TLS__}/g; s#__DB_TLS_CA_CERTIFICATE__#$ENV{__DB_TLS_CA_CERTIFICATE__}#g; s#__DB_TLS_CLIENT_CERTIFICATE__#$ENV{__DB_TLS_CLIENT_CERTIFICATE__}#g; s#__DB_TLS_CLIENT_KEY__#$ENV{__DB_TLS_CLIENT_KEY__}#g' \
    /etc/koha/koha-conf-site.xml.in

if [ -z "${KOHA_DB_TLS_CA_CERTIFICATE}" ]; then
    sed -i '/<ca><\/ca>/d' /etc/koha/koha-conf-site.xml.in
fi
if [ -z "${KOHA_DB_TLS_CLIENT_CERTIFICATE}" ]; then
    sed -i '/<cert><\/cert>/d' /etc/koha/koha-conf-site.xml.in
fi
if [ -z "${KOHA_DB_TLS_CLIENT_KEY}" ]; then
    sed -i '/<key><\/key>/d' /etc/koha/koha-conf-site.xml.in
fi

# bin
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/bin/dbic > ${BUILD_DIR}/bin/dbic || true
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/bin/flush_memcached > ${BUILD_DIR}/bin/flush_memcached || true
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/bin/bisect_with_test > ${BUILD_DIR}/bin/bisect_with_test || true

if [ -r /etc/os-release ]; then
    . /etc/os-release
    if [ "${ID:-}" = "debian" ] && [ "${VERSION_CODENAME:-}" = "trixie" ] && [ -f /etc/mysql/my.cnf ]; then
        echo "[client]"  >> /etc/mysql/my.cnf
        echo "ssl = off" >> /etc/mysql/my.cnf
    fi
fi

chmod +x ${BUILD_DIR}/bin/* 2>/dev/null || true

cd ${BUILD_DIR}
bootstrap_koha_instance

KOHA_SITE_CONF="/etc/koha/sites/${KOHA_INSTANCE}/koha-conf.xml"
if [ -f "${KOHA_SITE_CONF}" ]; then
    sed -i '/<ssl_key>/d' "${KOHA_SITE_CONF}"
    sed -i '/<ssl_cert>/d' "${KOHA_SITE_CONF}"

    if [ "${KOHA_DB_USE_TLS}" = "yes" ]; then
        if grep -q '<tls>' "${KOHA_SITE_CONF}"; then
            sed -i 's#<tls>.*</tls>#<tls>yes</tls>#g' "${KOHA_SITE_CONF}"
        else
            sed -i 's#</pass>#</pass>\n <tls>yes</tls>#' "${KOHA_SITE_CONF}"
        fi

        if grep -q '<ca>' "${KOHA_SITE_CONF}"; then
            sed -i "s#<ca>.*</ca>#<ca>${KOHA_DB_TLS_CA_CERTIFICATE}</ca>#g" "${KOHA_SITE_CONF}"
        else
            sed -i "s#</tls>#</tls>\n <ca>${KOHA_DB_TLS_CA_CERTIFICATE}</ca>#" "${KOHA_SITE_CONF}"
        fi

        if [ -n "${KOHA_DB_TLS_CLIENT_CERTIFICATE}" ]; then
            if grep -q '<cert>' "${KOHA_SITE_CONF}"; then
                sed -i "s#<cert>.*</cert>#<cert>${KOHA_DB_TLS_CLIENT_CERTIFICATE}</cert>#g" "${KOHA_SITE_CONF}"
            else
                sed -i "s#</ca>#</ca>\n <cert>${KOHA_DB_TLS_CLIENT_CERTIFICATE}</cert>#" "${KOHA_SITE_CONF}"
            fi
        fi

        if [ -n "${KOHA_DB_TLS_CLIENT_KEY}" ]; then
            if grep -q '<key>' "${KOHA_SITE_CONF}"; then
                sed -i "s#<key>.*</key>#<key>${KOHA_DB_TLS_CLIENT_KEY}</key>#g" "${KOHA_SITE_CONF}"
            else
                sed -i "s#</ca>#</ca>\n <key>${KOHA_DB_TLS_CLIENT_KEY}</key>#" "${KOHA_SITE_CONF}"
            fi
        fi

        export MYSQL_OPT_SKIP_SSL=0
        export PERL_DBD_MYSQL_SSL_VERIFY_SERVER_CERT=0
    else
        if grep -q '<tls>' "${KOHA_SITE_CONF}"; then
            sed -i 's#<tls>.*</tls>#<tls>no</tls>#g' "${KOHA_SITE_CONF}"
        else
            sed -i 's#</pass>#</pass>\n <tls>no</tls>#' "${KOHA_SITE_CONF}"
        fi
        sed -i '/<ca>/d' "${KOHA_SITE_CONF}"
        sed -i '/<cert>/d' "${KOHA_SITE_CONF}"
        sed -i '/<key>/d' "${KOHA_SITE_CONF}"

        export MYSQL_OPT_SKIP_SSL=1
        export PERL_DBD_MYSQL_SSL_VERIFY_SERVER_CERT=0
    fi
fi

_db_hosts=$(mysql --defaults-file=/etc/mysql/koha-common.cnf --batch --skip-column-names \
    -e "SELECT Host FROM mysql.user WHERE User='${DB_USER}'" 2>/dev/null || true)
if [ -n "${_db_hosts}" ]; then
    for _h in ${_db_hosts}; do
        mysql --defaults-file=/etc/mysql/koha-common.cnf \
            -e "ALTER USER '${DB_USER}'@'${_h}' REQUIRE NONE;" 2>/dev/null || true
    done
fi
unset _db_hosts _h

# FIXED: ensure instance home exists before writing vimrc
mkdir -p /var/lib/koha/${KOHA_INSTANCE} /var/lib/koha/kohadev
chown ${KOHA_INSTANCE}-koha ${KOHA_INSTANCE}-koha 2>/dev/null || chown kohadev:kohadev /var/lib/koha/${KOHA_INSTANCE} 2>/dev/null || true
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/vimrc > /var/lib/koha/${KOHA_INSTANCE}/.vimrc || cp ${BUILD_DIR}/templates/vimrc /var/lib/koha/${KOHA_INSTANCE}/.vimrc || true
chown "${KOHA_INSTANCE}-koha" "/var/lib/koha/${KOHA_INSTANCE}/.vimrc" 2>/dev/null || true
# Also write for kohadev generic home
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/vimrc > /var/lib/koha/kohadev/.vimrc 2>/dev/null || true

if [ -d "${BUILD_DIR}/howto" ]
then
    echo "Install Koha-how-to"
    rm -f ${BUILD_DIR}/koha/how-to.pl ${BUILD_DIR}/koha/koha-tmpl/intranet-tmpl/prog/en/modules/how-to.tt
    ln -s ${BUILD_DIR}/howto/how-to.pl ${BUILD_DIR}/koha/how-to.pl
    ln -s ${BUILD_DIR}/howto/how-to.tt ${BUILD_DIR}/koha/koha-tmpl/intranet-tmpl/prog/en/modules/how-to.tt
fi

echo "[cypress] Make the pre-built cypress available to the instance user [HACK]"

mkdir -p "/var/lib/koha/${KOHA_INSTANCE}/.cache" \
  && echo "    [*] Created cache dir /var/lib/koha/${KOHA_INSTANCE}/.cache/" \
  || echo "    [x] Error creating cache dir /var/lib/koha/${KOHA_INSTANCE}/.cache/"

chown -R "${KOHA_INSTANCE}-koha:${KOHA_INSTANCE}-koha" "/var/lib/koha/${KOHA_INSTANCE}/.cache/" 2>/dev/null || true

ln -s /kohadevbox/Cypress "/var/lib/koha/${KOHA_INSTANCE}/.cache/" 2>/dev/null \
  && echo "    [*] Cypress dir linked" \
  || echo "    [x] Error linking Cypress"

if [[ ! -z "${LOCAL_USER_ID}" && "${LOCAL_USER_ID}" != "1000" ]]; then
    usermod -o -u ${LOCAL_USER_ID} "${KOHA_INSTANCE}-koha" 2>/dev/null || true
    if [[ "${SKIP_CYPRESS_CHOWN}" != "yes" ]]; then
        chown -R "${KOHA_INSTANCE}-koha:${KOHA_INSTANCE}-koha" "/kohadevbox/Cypress" 2>/dev/null || true
    fi
    chown -R "${KOHA_INSTANCE}-koha" "/var/cache/koha/${KOHA_INSTANCE}" 2>/dev/null || true
    chown -R "${KOHA_INSTANCE}-koha" "/var/lib/koha/${KOHA_INSTANCE}" 2>/dev/null || true
    chown -R "${KOHA_INSTANCE}-koha" "/var/lock/koha/${KOHA_INSTANCE}" 2>/dev/null || true
    chown -R "${KOHA_INSTANCE}-koha" "/var/log/koha/${KOHA_INSTANCE}" 2>/dev/null || true
    chown -R "${KOHA_INSTANCE}-koha" "/var/run/koha/${KOHA_INSTANCE}" 2>/dev/null || true
    chown -R "${KOHA_INSTANCE}-koha" ${BUILD_DIR}/misc4dev 2>/dev/null || true
    chown -R "${KOHA_INSTANCE}-koha" ${BUILD_DIR}/qa-test-tools 2>/dev/null || true
fi

sync_l10n

echo "[API logging] Set TRACE to API log4perl config"
sed -i 's/log4perl.logger.api = WARN, API/log4perl.logger.api = TRACE, API/' /etc/koha/sites/${KOHA_INSTANCE}/log4perl.conf 2>/dev/null || true

echo "[git] Setting up Git on the instance user"
setup_git_workflow

GIT_BASE_DIR=${BUILD_DIR}/koha
if [ "${GIT_WORKTREE_SOURCE}" != "" ]; then
    echo "    [!] Detected worktree: pointing to '${GIT_WORKTREE_SOURCE}'"
    GIT_BASE_DIR=${GIT_WORKTREE_SOURCE}
fi

install_git_hooks "${GIT_BASE_DIR}" || echo "    [!] Git hooks setup skipped"

envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/apache2_envvars > /etc/apache2/envvars

render_vhost "${KOHA_INSTANCE}"

if command -v koha-enable >/dev/null 2>&1; then
    koha-enable ${KOHA_INSTANCE}
else
    echo "[koha-enable] WARNING: koha-enable not available; skipping"
fi

mkdir -p /etc/apache2/sites-enabled
ln -sf "/etc/apache2/sites-available/${KOHA_INSTANCE}.conf" "/etc/apache2/sites-enabled/${KOHA_INSTANCE}.conf" 2>/dev/null || true

cp /kohadevbox/koha/package.json /kohadevbox 2>/dev/null || true
cp /kohadevbox/koha/yarn.lock    /kohadevbox 2>/dev/null || true
rm -rf /var/lib/koha/${KOHA_INSTANCE}/.cache/js-v8flags /var/lib/koha/${KOHA_INSTANCE}/.cache/yarn 2>/dev/null || true
if [ "${SKIP_YARN_INSTALL:-no}" = "yes" ]; then
    echo "[yarn] SKIP_YARN_INSTALL=yes — skipping yarn install"
else
    echo "[yarn] Running yarn install"
    cd /kohadevbox/koha && yarn install || true
    cd /
fi

echo "127.0.0.1    ${KOHA_OPAC_FQDN} ${KOHA_INTRANET_FQDN}" >> /etc/hosts

mkdir -p /var/lib/koha/${KOHA_INSTANCE}
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/instance_bashrc > /var/lib/koha/${KOHA_INSTANCE}/.bashrc || true
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/bash_aliases    > /var/lib/koha/${KOHA_INSTANCE}/.bash_aliases || true

if [ "${KOHA_ELASTICSEARCH}" = "yes" ]; then
    ES_FLAG="--elasticsearch"
fi

USE_EXISTING_DB_FLAG=""
if [ "${USE_EXISTING_DB}" != "yes" ]; then
    echo "[db-detect] Probing '${DB_NAME}' for existing Koha data..."
    _db_populated=$(mysql --defaults-file=/etc/mysql/koha-common.cnf --batch --skip-column-names -e "SELECT IF((SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '${DB_NAME}' AND table_name = 'systempreferences') > 0,'yes','no');" 2>/dev/null || echo "no")
    if [ "${_db_populated:-no}" = "yes" ]; then
        echo "[db-detect] Existing data found — enabling --use-existing-db"
        USE_EXISTING_DB="yes"
    else
        echo "[db-detect] Database is empty — fresh install"
    fi
    unset _db_populated
fi

if [ "${USE_EXISTING_DB}" = "yes" ]; then
    USE_EXISTING_DB_FLAG="--use-existing-db"
fi

if [ "${LOAD_DEMO_DATA:-yes}" = "no" ]; then
    echo "[demo data] LOAD_DEMO_DATA=no — skipping sample records"
    printf '#!/usr/bin/perl\nuse Modern::Perl;\nsay "Demo data skipped";\nexit(0);\n' > ${BUILD_DIR}/misc4dev/insert_data.pl
    chmod +x ${BUILD_DIR}/misc4dev/insert_data.pl
fi

if [ "${KOHA_ELASTICSEARCH}" = "yes" ]; then
    echo "[elasticsearch] Waiting for OpenSearch endpoint..."
    ES_ENDPOINT="${ELASTIC_SERVER:-os01:9200}"
    ES_HOST="${ES_ENDPOINT%%:*}"
    ES_PORT="${ES_ENDPOINT##*:}"
    [ -z "${ES_HOST}" ] && ES_HOST="os01"
    [ -z "${ES_PORT}" ] || [ "${ES_PORT}" = "${ES_HOST}" ] && ES_PORT="9200"
    _os_cacert_args=()
    if [ -s "/kohadevbox/opensearch-root-ca.pem" ]; then
        _os_cacert_args=(--cacert "/kohadevbox/opensearch-root-ca.pem")
    else
        _os_cacert_args=(-k)
    fi
    os_wait_ok="no"
    for attempt in $(seq 1 60); do
        if ! nc -z -w 3 "${ES_HOST}" "${ES_PORT}" 2>/dev/null; then
            echo "[elasticsearch] attempt ${attempt}/60: TCP not reachable"
            sleep 5
            continue
        fi
        os_response=$(curl -s "${_os_cacert_args[@]}" --connect-timeout 5 --max-time 10 -u "admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}" -w "\nHTTP_STATUS:%{http_code}" "https://${ES_HOST}:${ES_PORT}/_cluster/health?wait_for_status=yellow&timeout=5s" 2>&1)
        os_http_code=$(echo "${os_response}" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
        os_status=$(echo "${os_response}" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p' | head -n 1)
        if [ "${os_status}" = "yellow" ] || [ "${os_status}" = "green" ]; then
            os_wait_ok="yes"
            echo "[elasticsearch] OpenSearch is ${os_status}."
            break
        fi
        echo "[elasticsearch] attempt ${attempt}/60: not ready (HTTP ${os_http_code:-no-response})"
        sleep 5
    done
    if [ "${os_wait_ok}" != "yes" ]; then
        echo "[elasticsearch] OpenSearch did not become ready in time."
        exit 1
    fi
fi

find "${BUILD_DIR}/koha/misc/migration_tools" -type f -name '*.pl' -exec sed -i 's/\r$//' {} + 2>/dev/null || true

if [ "${APPLY_KOHA_PATCHES:-no}" = "yes" ] && [ -x "${BUILD_DIR}/apply-patches.sh" ]; then
    echo "[patches] Applying compatibility patches"
    KOHA_PATCH_TARGET_DIR="${BUILD_DIR}/koha" "${BUILD_DIR}/apply-patches.sh"
fi

RUN_DB_POPULATION="yes"
_bootstrap_profile="$(echo "${ALPINE_BOOTSTRAP_PROFILE:-resume}" | tr '[:upper:]' '[:lower:]')"
case "${_bootstrap_profile}" in
    full)
        if [ -z "${RUN_DB_POPULATION_ON_EXISTING_DB:-}" ]; then
            export RUN_DB_POPULATION_ON_EXISTING_DB=yes
        fi
        ;;
    resume|"")
        if [ -z "${RUN_DB_POPULATION_ON_EXISTING_DB:-}" ]; then
            export RUN_DB_POPULATION_ON_EXISTING_DB=no
        fi
        ;;
    *)
        if [ -z "${RUN_DB_POPULATION_ON_EXISTING_DB:-}" ]; then
            export RUN_DB_POPULATION_ON_EXISTING_DB=no
        fi
        ;;
esac

if [ "${USE_EXISTING_DB}" = "yes" ] && [ "${RUN_DB_POPULATION_ON_EXISTING_DB:-no}" != "yes" ]; then
    RUN_DB_POPULATION="no"
fi

if [ "${RUN_DB_POPULATION}" = "yes" ]; then
    if [ "${KOHA_ELASTICSEARCH}" = "yes" ]; then
        sed -i 's|\$cmd = "sudo koha-rebuild-zebra -f -v \$instance";|say "Skipping koha-rebuild-zebra in Elasticsearch mode";\n\$cmd = "true";|' "${BUILD_DIR}/misc4dev/do_all_you_can_do.pl" 2>/dev/null || true
        sed -i "s|perl \$rebuild_es_path -v'|perl \$rebuild_es_path' 2>/tmp/rebuild_elasticsearch.stderr; true|" "${BUILD_DIR}/misc4dev/do_all_you_can_do.pl" 2>/dev/null || true
    fi

    perl ${BUILD_DIR}/misc4dev/do_all_you_can_do.pl --instance ${KOHA_INSTANCE} ${ES_FLAG} ${USE_EXISTING_DB_FLAG} --userid ${KOHA_USER} --password ${KOHA_PASS} --marcflavour ${KOHA_MARC_FLAVOUR} --koha_dir ${BUILD_DIR}/koha --opac-base-url ${KOHA_OPAC_URL} --intranet-base-url ${KOHA_INTRANET_URL} || {
        echo "[db-population] WARNING: Database population failed"
    }

    if [ -s /tmp/rebuild_elasticsearch.stderr ]; then
        echo "[elasticsearch] WARNING: Index rebuild errors:"
        cat /tmp/rebuild_elasticsearch.stderr
    fi
fi

unset RUN_DB_POPULATION
unset _bootstrap_profile

find /etc/apache2/sites-enabled -name "*.conf" -exec sed -i 's/^[[:space:]]*AssignUserID/# AssignUserID/' {} + 2>/dev/null || true

if [ -d "/etc/koha/sites/${KOHA_INSTANCE}" ]; then
    chmod 644 /etc/koha/sites/${KOHA_INSTANCE}/koha-conf.xml 2>/dev/null || true
    chmod 644 /etc/koha/sites/${KOHA_INSTANCE}/log4perl.conf 2>/dev/null || true
fi
if [ -d "/var/cache/koha/${KOHA_INSTANCE}" ]; then
    chmod 777 /var/cache/koha/${KOHA_INSTANCE} 2>/dev/null || true
    find /var/cache/koha/${KOHA_INSTANCE} -type d -exec chmod 777 {} + 2>/dev/null || true
fi
if [ -d "/var/log/koha/${KOHA_INSTANCE}" ]; then
    find /var/log/koha/${KOHA_INSTANCE} -type f -exec chmod 666 {} + 2>/dev/null || true
    find /var/log/koha/${KOHA_INSTANCE} -type d -exec chmod 777 {} + 2>/dev/null || true
fi

sed -i 's/^[[:space:]]*#LoadModule cgi_module modules\/mod_cgi\.so/LoadModule cgi_module modules\/mod_cgi.so/' /etc/apache2/httpd.conf 2>/dev/null || true
sed -i '/^[[:space:]]*SetEnv PERL5LIB[[:space:]]/d' /etc/koha/apache-shared.conf 2>/dev/null || true
sed -i "/^[[:space:]]*DocumentRoot[[:space:]]/d; s|/usr/share/koha/intranet/cgi-bin|${KOHA_PATH}|g; s|/usr/share/koha/api|${KOHA_PATH}/api|g" /etc/koha/apache-shared-intranet.conf 2>/dev/null || true
sed -i "/^[[:space:]]*DocumentRoot[[:space:]]/d; s|/usr/share/koha/opac/cgi-bin/opac|${KOHA_PATH}/opac|g; s|/usr/share/koha/api|${KOHA_PATH}/api|g" /etc/koha/apache-shared-opac.conf 2>/dev/null || true

stop_apache_service

find "${BUILD_DIR}/koha" -type f \( -name '*.pl' -o -name '*.cgi' \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true

chown -R "${KOHA_INSTANCE}-koha:${KOHA_INSTANCE}-koha" "/var/log/koha/${KOHA_INSTANCE}" 2>/dev/null || true

for _logf in opac-error.log intranet-error.log z3950-error.log api-error.log sip-error.log sip-output.log plack-opac-error.log plack-api-error.log plack-intranet-error.log editrace.log; do
    touch "/var/log/koha/${KOHA_INSTANCE}/${_logf}" 2>/dev/null || true
    chmod 666 "/var/log/koha/${KOHA_INSTANCE}/${_logf}" 2>/dev/null || true
done
unset _logf

if [ "${ENABLE_PLUGINS}" = "yes" ]; then
    echo "[plugins] Installing plugins"
    PLUGINS_STRING=""
    counter=0
    for plugin_dir in $(find ${BUILD_DIR}/plugins -mindepth 1 -maxdepth 1 -type d 2>/dev/null); do
        echo "    [*] Found: ${plugin_dir}"
        entry=" <pluginsdir>${BUILD_DIR}/plugins/$(basename $plugin_dir)</pluginsdir>"
        if [ "${counter}" -ge 1 ]; then
            PLUGINS_STRING="${PLUGINS_STRING}\n${entry}"
        else
            PLUGINS_STRING="${entry}"
        fi
        counter=$((counter+1))
    done
    if command -v flush_memcached >/dev/null 2>&1; then
        flush_memcached
    fi
    sed -i "s# <!--pluginsdir>YOUR_PLUGIN_DIR_HERE</pluginsdir-->#$(echo "$PLUGINS_STRING")#" /etc/koha/sites/kohadev/koha-conf.xml 2>/dev/null || true
    perl ${BUILD_DIR}/koha/misc/devel/install_plugins.pl 2>/dev/null || true
    echo "    [*] Plugins loaded!"
fi

enable_instance_services

echo "[rabbitmq] Waiting for STOMP port ${MESSAGE_BROKER_HOST}:${MESSAGE_BROKER_PORT}..."
_stomp_ready=no
for _i in $(seq 1 30); do
    if nc -z "${MESSAGE_BROKER_HOST}" "${MESSAGE_BROKER_PORT}" 2>/dev/null; then
        _stomp_ready=yes
        break
    fi
    sleep 1
done
if [ "${_stomp_ready}" = "yes" ]; then
    echo "[rabbitmq] STOMP port ${MESSAGE_BROKER_HOST}:${MESSAGE_BROKER_PORT} is ready"
else
    echo "[rabbitmq] WARNING: STOMP port not ready after 30s"
fi
unset _stomp_ready _i

start_koha_service
start_apache_service
start_crond

touch /ktd_ready
touch /kohadevbox/koha/.alpine-bootstrap-complete
echo "koha-testing-docker has started up and is ready to be enjoyed!"

run_service_watchdog "${KOHA_INSTANCE}"
