#!/bin/bash
set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/koha-perl/bin:$PATH
KOHASITE=${KOHASITE:-kohadev}
KOHA_HOME=/var/lib/koha/${KOHASITE}
KOHACONF=/etc/koha/sites/${KOHASITE}/koha-conf.xml
KOHADEVBOX=/kohadevbox/koha
DB_HOST=${DB_HOST:-db}
DB_USER=koha_${KOHASITE}
DB_PASS=${KOHA_DB_PASSWORD:-${MYSQL_PASS:-password}}
DB_NAME=koha_${KOHASITE}
MEMCACHED_SERVERS=${MEMCACHED_SERVERS:-memcached:11211}
MESSAGE_BROKER_HOST=${MESSAGE_BROKER_HOST:-rabbitmq}
ADMIN_USER=${KOHA_ADMIN_USER:-admin}
ADMIN_PASS=${KOHA_ADMIN_PASS:-admin123}
ADMIN_BRANCH=${KOHA_ADMIN_BRANCH:-CPL}
ADMIN_CATEGORY=${KOHA_ADMIN_CATEGORY:-S}
export KOHA_CONF=${KOHACONF} KOHA_HOME=${KOHA_HOME} PERL5LIB=/opt/koha-perl/lib/perl5:${KOHADEVBOX}/lib:${KOHADEVBOX}:/opt/koha-perl/lib/perl5 MYSQL_PWD=${DB_PASS}

echo "[run.sh] BEEFY v25 TRAEFIK-FIX - $KOHASITE"

# Debug mount
ls -l $KOHADEVBOX/koha-tmpl/intranet-tmpl/prog/en/modules/auth.tt 2>&1 | head -5 || echo "WARN: host kohadevbox mount missing!"
ls -l $KOHADEVBOX/app.psgi 2>&1 | head -1 || true

# Fix templates - never fail on ls
mkdir -p /usr/share/koha/intranet/cgi-bin /usr/share/koha/intranet/htdocs /usr/share/koha/opac/htdocs
rm -rf /usr/share/koha/intranet/cgi-bin/installer
ln -sf ${KOHADEVBOX}/installer /usr/share/koha/intranet/cgi-bin/installer || true
rm -rf /usr/share/koha/intranet/htdocs/intranet-tmpl
rm -rf /usr/share/koha/opac/htdocs/opac-tmpl
# Symlink the WHOLE intranet-tmpl/opac-tmpl trees (not just prog/bootstrap
# subdirs): Koha::Template::Plugin::Asset resolves JS/CSS via <intrahtdocs>/
# <opachtdocs> (these paths), independently of Apache's DocumentRoot. Cherry-
# picking subdirs here previously missed intranet-tmpl/lib and
# opac-tmpl/lib (jQuery, jQuery UI, etc.), so Asset.js/css silently omitted
# their <script>/<link> tags (no error, just missing behavior/interactivity
# in the browser -- e.g. "$ is not defined" JS console errors).
if [ -d ${KOHADEVBOX}/koha-tmpl/intranet-tmpl ]; then
  ln -sf ${KOHADEVBOX}/koha-tmpl/intranet-tmpl /usr/share/koha/intranet/htdocs/intranet-tmpl
else
  echo "ERROR: ${KOHADEVBOX}/koha-tmpl/intranet-tmpl missing - check volume mount ./kohadevbox"
fi
if [ -d ${KOHADEVBOX}/koha-tmpl/opac-tmpl ]; then
  ln -sf ${KOHADEVBOX}/koha-tmpl/opac-tmpl /usr/share/koha/opac/htdocs/opac-tmpl
else
  echo "ERROR: ${KOHADEVBOX}/koha-tmpl/opac-tmpl missing - check volume mount ./kohadevbox"
fi
ln -sf ${KOHADEVBOX}/koha-tmpl /usr/share/koha/koha-tmpl 2>/dev/null || true
# soft check, don't exit
ls -l /usr/share/koha/intranet/htdocs/intranet-tmpl/prog/en/modules/auth.tt 2>&1 || echo "WARN: auth.tt still missing, will try anyway"
ls -l /usr/share/koha/intranet/htdocs/intranet-tmpl/lib/jquery/jquery-3.6.0.min.js 2>&1 || echo "WARN: jquery still missing, will try anyway"

# The bind-mounted koha checkout (dev workflow) ships CSS/JS *sources* only
# (SCSS, unbundled JS); the compiled main stylesheet (css/opac.css,
# css/staff-global.css) and JS bundles are a build step (yarn build), not
# checked into git. Without this, pages render but ship with zero CSS/JS.
# Skip if the compiled OPAC stylesheet is already present (fast path on restart).
# Reuses the pre-existing SKIP_YARN_INSTALL knob (env/.env -> KOHA_ALPINE_SKIP_YARN_INSTALL)
# instead of introducing a second, overlapping flag.
if [ "${SKIP_YARN_INSTALL:-no}" != "yes" ] && [ ! -f "${KOHADEVBOX}/koha-tmpl/opac-tmpl/bootstrap/css/opac.css" ]; then
  echo "[run.sh] Compiled CSS/JS assets missing; running yarn install + build (set SKIP_YARN_INSTALL=yes to skip)..."
  ( cd "${KOHADEVBOX}" && yarn install --frozen-lockfile 2>&1 | tail -20 && yarn build 2>&1 | tail -40 ) \
    || echo "[run.sh] WARNING: yarn build failed; OPAC/staff pages will render without CSS/JS. Check node/yarn are installed and re-run manually: cd ${KOHADEVBOX} && yarn build"
fi

# User setup for Alpine
if ! getent passwd kohadev-koha >/dev/null 2>&1; then
  echo "[run.sh] Creating user 'kohadev-koha'"
  # -S: create a system group. The || true is to prevent failure if it already exists from a partial run.
  addgroup -S kohadev-koha || true
  # -S: create a system user, -D: no password, -H: no home dir creation, -h: home dir path, -G: group, -s: shell
  adduser -S -D -H -h ${KOHA_HOME} -G kohadev-koha -s /bin/sh kohadev-koha
fi

mkdir -p /etc/koha/sites/${KOHASITE} /var/log/koha/${KOHASITE} /var/run/koha/${KOHASITE} ${KOHA_HOME}/plugins /var/lock/koha/${KOHASITE} /var/lib/koha/${KOHASITE}/uploads /var/cache/koha/${KOHASITE} /var/lib/koha/${KOHASITE}/tmp /var/cache/koha/${KOHASITE}/templates
[ -f /etc/koha/koha-conf-site.xml.in ] || cp ${KOHADEVBOX}/debian/templates/* /etc/koha/ 2>/dev/null || true
TEMPLATE="/etc/koha/koha-conf-site.xml.in"; [ -f "$TEMPLATE" ] || TEMPLATE="${KOHADEVBOX}/debian/templates/koha-conf-site.xml.in"
DB_PASS_ESC=$(printf '%s' "$DB_PASS" | sed 's/[&/\]/\\&/g')
cp "$TEMPLATE" "${KOHACONF}.tmp"
sed -i \
    -e "s|__KOHASITE__|$KOHASITE|g" \
    -e "s|__DB_HOST__|$DB_HOST|g" \
    -e "s|__DB_USER__|$DB_USER|g" \
    -e "s|__DB_PASS__|$DB_PASS_ESC|g" \
    -e "s|__DB_NAME__|$DB_NAME|g" \
    -e "s|__MEMCACHED_SERVERS__|$MEMCACHED_SERVERS|g" \
    -e "s|__MEMCACHED_NAMESPACE__|koha_${KOHASITE}:|g" \
    -e "s|__UNIXUSER__|kohadev-koha|g" \
    -e "s|__UNIXGROUP__|kohadev-koha|g" \
    -e "s|__KOHA_CONF_DIR__|/etc/koha/sites/$KOHASITE|g" \
    -e "s|__OPACPORT__|80|g" \
    -e "s|__INTRAPORT__|8080|g" \
    -e "s|__ZEBRA_MARC_FORMAT__|marc21|g" \
    -e "s|__ZEBRA_LANGUAGE__|en|g" \
    -e "s|__SRU_BIBLIOS_PORT__|9998|g" \
    -e "s|__START_SRU_PUBLICSERVER__|<!--|g" \
    -e "s|__END_SRU_PUBLICSERVER__|-->|g" \
    -e "s|__TIMEZONE__|Europe/Bucharest|g" \
    -e "s|__ELASTICSEARCH_SERVER__|localhost:9200|g" \
    -e "s|__TEMPLATE_CACHE_DIR__|/var/cache/koha/$KOHASITE/templates|g" \
    -e "s|__PLUGINS_DIR__|/var/lib/koha/$KOHASITE/plugins|g" \
    -e "s|__UPLOAD_PATH__|/var/lib/koha/$KOHASITE/uploads|g" \
    -e "s|__TMP_PATH__|/var/lib/koha/$KOHASITE/tmp|g" \
    -e "s|__LOG_DIR__|/var/log/koha/$KOHASITE|g" \
    -e "s|__MESSAGE_BROKER_HOST__|$MESSAGE_BROKER_HOST|g" \
    -e "s|__MESSAGE_BROKER_PORT__|61613|g" \
    -e "s|__MESSAGE_BROKER_USER__|guest|g" \
    -e "s|__MESSAGE_BROKER_PASS__|guest|g" \
    -e "s|__MESSAGE_BROKER_VHOST__|koha_$KOHASITE|g" \
    "${KOHACONF}.tmp"
ZEBRA_PWD=$(head -c 16 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c16); API_SECRET=$(head -c 32 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c32)
sed -i \
    -e "s|__ZEBRA_PASS__|$ZEBRA_PWD|g" \
    -e "s|__API_SECRET__|$API_SECRET|g" \
    -e "s|__BCRYPT_SETTINGS__||g" \
    -e "s|__OPACSERVER__||g" \
    -e "s|__INTRASERVER__||g" \
    -e "s|__SMTP_HOST__|localhost|g" \
    -e "s|__SMTP_PORT__|25|g" \
    -e "s|__SMTP.*__||g" \
    "${KOHACONF}.tmp"
mv "${KOHACONF}.tmp" "${KOHACONF}"; chmod 644 "${KOHACONF}"
cp /etc/koha/log4perl-site.conf.in /etc/koha/sites/${KOHASITE}/log4perl.conf 2>/dev/null || cp ${KOHADEVBOX}/debian/templates/log4perl-site.conf.in /etc/koha/sites/${KOHASITE}/log4perl.conf 2>/dev/null || true
sed -i "s|__KOHASITE__|$KOHASITE|g; s|__LOG_DIR__|/var/log/koha/$KOHASITE|g" /etc/koha/sites/${KOHASITE}/log4perl.conf 2>/dev/null || true

DB_IS_READY=0
for i in $(seq 1 60); do
    if mysql -h ${DB_HOST} -u ${DB_USER} -e "SELECT 1" >/dev/null 2>&1; then
        DB_IS_READY=1
        echo "[run.sh] Database connection established on attempt $i."
        break
    fi
    echo "[run.sh] Waiting for database... (attempt $i)"
    sleep 2
done

if [ "$DB_IS_READY" -eq 0 ]; then
    echo "[run.sh] ERROR: Database connection failed after 60 attempts. Aborting."
    exit 1
fi

# Check if the database is empty by looking for the systempreferences table.
# If it's empty, initialize the schema and load mandatory data.
if ! mysql -h ${DB_HOST} -u ${DB_USER} ${DB_NAME} -e "SELECT 1 FROM systempreferences LIMIT 1" >/dev/null 2>&1; then
    echo "[run.sh] Database appears to be empty. Initializing schema..."
    mysql -h ${DB_HOST} -u ${DB_USER} ${DB_NAME} < "${KOHADEVBOX}/installer/data/mysql/kohastructure.sql"
    echo "[run.sh] Loading mandatory data..."
    for f in ${KOHADEVBOX}/installer/data/mysql/mandatory/*.sql; do
        echo "  - Loading $f"
        mysql -h ${DB_HOST} -u ${DB_USER} ${DB_NAME} < "$f"
    done
    mysql -h ${DB_HOST} -u ${DB_USER} ${DB_NAME} -e "INSERT INTO systempreferences (variable,value) VALUES ('Version','24.11.00.000') ON DUPLICATE KEY UPDATE value='24.11.00.000';"
fi

echo "[run.sh] Ensuring base data"
mysql -h ${DB_HOST} -u ${DB_USER} ${DB_NAME} -e "INSERT IGNORE INTO branches (branchcode,branchname) VALUES ('$ADMIN_BRANCH','Central Library'); INSERT IGNORE INTO categories (categorycode,description,upperagelimit) VALUES ('$ADMIN_CATEGORY','Staff',999),('S','Staff',999),('PT','Patron',999);"

# Idempotency must check BOTH userid and cardnumber: a stale DB volume from a
# previous run/experiment can have cardnumber '1' taken by a differently-named
# user, which would otherwise crash create_superlibrarian.pl under `set -e` and
# take down the whole container (observed: "Field 'cardnumber' must be unique").
ADMIN_EXISTS=$(mysql -h ${DB_HOST} -u ${DB_USER} ${DB_NAME} -Nse "SELECT 1 FROM borrowers WHERE userid='$ADMIN_USER' OR cardnumber='1' LIMIT 1" 2>/dev/null || true)
if [ -z "$ADMIN_EXISTS" ]; then
  echo "[run.sh] Creating $ADMIN_USER"
  if ! su kohadev-koha -s /bin/sh -c "export KOHA_CONF=${KOHACONF} PERL5LIB=/opt/koha-perl/lib/perl5:${KOHADEVBOX}/lib:${KOHADEVBOX} KOHA_HOME=${KOHA_HOME}; cd ${KOHADEVBOX}; perl misc/devel/create_superlibrarian.pl --userid $ADMIN_USER --password $ADMIN_PASS --branchcode $ADMIN_BRANCH --categorycode $ADMIN_CATEGORY --cardnumber 1 --surname Admin"; then
    echo "[run.sh] WARNING: create_superlibrarian.pl failed; continuing startup (an admin account may already exist under a different userid/cardnumber)"
  fi
else
  echo "[run.sh] Superlibrarian $ADMIN_USER (or cardnumber 1) already exists"
fi

chown -R kohadev-koha:kohadev-koha /etc/koha/sites/${KOHASITE} /var/log/koha/${KOHASITE} /var/run/koha/${KOHASITE} /var/lib/koha/${KOHASITE} /var/cache/koha/${KOHASITE} 2>/dev/null || true
echo "[run.sh] updatedatabase"; su kohadev-koha -s /bin/sh -c "export KOHA_CONF=${KOHACONF} PERL5LIB=/opt/koha-perl/lib/perl5:${KOHADEVBOX}/lib:${KOHADEVBOX} KOHA_HOME=${KOHA_HOME}; cd ${KOHADEVBOX}; perl -Ilib installer/data/mysql/updatedatabase.pl"

# --- Apache + Plack + supervision -------------------------------------------
# Historical note: earlier revisions of this script `exec`d a bare `plackup
# --port 5000 app.psgi` here. That never worked: nothing routed traffic to
# port 5000, and koha/app.psgi (the Mojolicious dual-port app) requires
# Koha::App::Opac/Koha::App::Intranet, which do not exist in this Koha
# checkout. We now start Apache (serving OPAC/staff on 8080/8081, matching
# compose/Traefik) with mod_cgi as the always-working baseline, and try to
# layer real Plack (koha-plack -> debian's CGI-based plack.psgi over a unix
# socket, proxied by Apache) on top via the restored run-sh-alpine.sh helpers.
. /build/files-alpine/lib/run-sh-alpine.sh

# render_vhost() (from run-sh-alpine.sh) reads ${BUILD_DIR}/templates/koha-vhost.conf.in.
# Templates are bind-mounted (dev) / COPY'd (image) to /build/files-alpine/templates.
export BUILD_DIR=/build/files-alpine
export KOHA_INSTANCE=${KOHASITE}
export KOHA_PATH=${KOHADEVBOX}
export KOHA_LIB_PATH=${KOHADEVBOX}/lib
export KOHA_INTRANET_PORT=${KOHA_INTRANET_PORT:-8081}
export KOHA_OPAC_PORT=${KOHA_OPAC_PORT:-8080}
export KOHA_INTRANET_FQDN=${KOHA_INTRANET_PREFIX}${KOHASITE}${KOHA_INTRANET_SUFFIX}${KOHA_DOMAIN}
export KOHA_OPAC_FQDN=${KOHA_OPAC_PREFIX}${KOHASITE}${KOHA_OPAC_SUFFIX}${KOHA_DOMAIN}
VARS_TO_SUB='$KOHA_INTRANET_PORT:$KOHA_INTRANET_FQDN:$KOHA_OPAC_PORT:$KOHA_OPAC_FQDN:$KOHA_PATH:$KOHA_LIB_PATH:$KOHA_INSTANCE'

# Install the Alpine-native koha-plack/koha-worker/koha-create scripts. These
# are not baked into /usr/sbin by the Dockerfile (only files-alpine/run.sh is);
# install them here so enable_instance_services/start_koha_service can find them.
for _script in koha-create koha-plack koha-worker koha-functions.sh; do
    if [ -f "${BUILD_DIR}/scripts/${_script}" ]; then
        install -m 0755 "${BUILD_DIR}/scripts/${_script}" "/usr/sbin/${_script}"
    fi
done
unset _script

echo "[alpine] Enabling mod_cgi/mod_proxy modules for Apache..."
sed -i \
    -e 's/^[[:space:]]*#LoadModule cgi_module modules\/mod_cgi\.so/LoadModule cgi_module modules\/mod_cgi.so/' \
    -e 's/^[[:space:]]*#LoadModule proxy_module modules\/mod_proxy\.so/LoadModule proxy_module modules\/mod_proxy.so/' \
    -e 's/^[[:space:]]*#LoadModule proxy_http_module modules\/mod_proxy_http\.so/LoadModule proxy_http_module modules\/mod_proxy_http.so/' \
    -e 's/^[[:space:]]*#LoadModule rewrite_module modules\/mod_rewrite\.so/LoadModule rewrite_module modules\/mod_rewrite.so/' \
    /etc/apache2/httpd.conf 2>/dev/null || true
append_if_absent "ServerName kohadevbox"          /etc/apache2/httpd.conf 2>/dev/null || true
append_if_absent "Listen ${KOHA_INTRANET_PORT}"   /etc/apache2/httpd.conf 2>/dev/null || true
append_if_absent "Listen ${KOHA_OPAC_PORT}"       /etc/apache2/httpd.conf 2>/dev/null || true
# Alpine's httpd.conf (unlike Debian's apache2.conf) has no sites-enabled Include
# by default; without this the rendered vhost is silently ignored and Apache
# just serves its "It works!" default page on every port.
append_if_absent "IncludeOptional /etc/apache2/sites-enabled/*.conf" /etc/apache2/httpd.conf 2>/dev/null || true

# apache-shared.conf/apache-shared-{intranet,opac}.conf (Included from the vhost
# template) are the real Koha files and hardcode Debian package paths
# (/usr/share/koha/*). Rewrite them for the git-install layout so they don't
# clobber our vhost's DocumentRoot/PERL5LIB with paths that don't exist here.
sed -i '/^[[:space:]]*SetEnv PERL5LIB[[:space:]]/d' /etc/koha/apache-shared.conf 2>/dev/null || true
sed -i "/^[[:space:]]*DocumentRoot[[:space:]]/d; \
        /^[[:space:]]*ScriptAlias \/index.html/d; \
        /^[[:space:]]*ScriptAlias \/search/d; \
        s|/usr/share/koha/intranet/cgi-bin|${KOHA_PATH}|g; \
        s|/usr/share/koha/api|${KOHA_PATH}/api|g" \
    /etc/koha/apache-shared-intranet.conf 2>/dev/null || true
sed -i "/^[[:space:]]*DocumentRoot[[:space:]]/d; \
        /^[[:space:]]*ScriptAlias \/index.html/d; \
        /^[[:space:]]*ScriptAlias \/search/d; \
        /^[[:space:]]*ScriptAlias \/opac-search.pl/d; \
        s|/usr/share/koha/opac/cgi-bin/opac|${KOHA_PATH}/opac|g; \
        s|/usr/share/koha/api|${KOHA_PATH}/api|g" \
    /etc/koha/apache-shared-opac.conf 2>/dev/null || true

mkdir -p /etc/apache2/sites-available /etc/apache2/sites-enabled
render_vhost "${KOHASITE}"
ln -sf "/etc/apache2/sites-available/${KOHASITE}.conf" "/etc/apache2/sites-enabled/${KOHASITE}.conf"

chmod 644 "${KOHACONF}" 2>/dev/null || true
chmod 666 /var/log/koha/${KOHASITE}/*.log 2>/dev/null || true

# Alpine's Apache runs CGI as the 'apache' user (no AssignUserID/suexec support),
# unlike Debian where CGI runs as '<instance>-koha'. Without this, Template
# Toolkit's cache mkdir (and log4perl appenders) fail with "Permission denied"
# for every CGI request, producing 500s even though Apache itself is healthy.
chmod -R 777 /var/cache/koha/${KOHASITE} 2>/dev/null || true
chmod -R 777 /var/log/koha/${KOHASITE} 2>/dev/null || true
chmod -R 777 /var/run/koha/${KOHASITE} 2>/dev/null || true

stop_apache_service

# Start koha-plack BEFORE Apache: Apache's ProxyPass handles almost every
# request path (including bare "/"), so if it starts first and accepts
# connections before the plack.sock backend exists, every request 503s until
# koha-plack finishes starting (~2s) -- observed as "the site doesn't answer"
# on whichever vhost gets hit first after a fresh boot.
enable_instance_services
start_koha_service
start_apache_service
start_crond

touch /kohadevbox/koha/.alpine-bootstrap-complete
echo "[run.sh] Startup complete - OPAC on :${KOHA_OPAC_PORT}, staff on :${KOHA_INTRANET_PORT}"

run_service_watchdog "${KOHASITE}"
