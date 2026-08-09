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
mkdir -p /usr/share/koha/intranet/htdocs/intranet-tmpl
mkdir -p /usr/share/koha/opac/htdocs/opac-tmpl
# Ensure source exists before linking
if [ -d ${KOHADEVBOX}/koha-tmpl/intranet-tmpl/prog ]; then
  ln -sf ${KOHADEVBOX}/koha-tmpl/intranet-tmpl/prog /usr/share/koha/intranet/htdocs/intranet-tmpl/prog
  ln -sf ${KOHADEVBOX}/koha-tmpl/intranet-tmpl/prog/en /usr/share/koha/intranet/htdocs/intranet-tmpl/en || true
else
  echo "ERROR: ${KOHADEVBOX}/koha-tmpl/intranet-tmpl/prog missing - check volume mount ./kohadevbox"
fi
if [ -d ${KOHADEVBOX}/koha-tmpl/opac-tmpl/bootstrap ]; then
  ln -sf ${KOHADEVBOX}/koha-tmpl/opac-tmpl/bootstrap /usr/share/koha/opac/htdocs/opac-tmpl/bootstrap
  ln -sf ${KOHADEVBOX}/koha-tmpl/opac-tmpl/bootstrap/en /usr/share/koha/opac/htdocs/opac-tmpl/en || true
fi
ln -sf ${KOHADEVBOX}/koha-tmpl /usr/share/koha/koha-tmpl 2>/dev/null || true
# soft check, don't exit
ls -l /usr/share/koha/intranet/htdocs/intranet-tmpl/prog/en/modules/auth.tt 2>&1 || echo "WARN: auth.tt still missing, will try anyway"
ls -l /usr/share/koha/intranet/htdocs/intranet-tmpl/en/modules/auth.tt 2>&1 || true

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

if ! mysql -h ${DB_HOST} -u ${DB_USER} ${DB_NAME} -e "SELECT 1 FROM borrowers WHERE userid='$ADMIN_USER' LIMIT 1" --silent | grep -q "1"; then
  echo "[run.sh] Creating $ADMIN_USER"
  su kohadev-koha -s /bin/sh -c "export KOHA_CONF=${KOHACONF} PERL5LIB=/opt/koha-perl/lib/perl5:${KOHADEVBOX}/lib:${KOHADEVBOX} KOHA_HOME=${KOHA_HOME}; cd ${KOHADEVBOX}; perl misc/devel/create_superlibrarian.pl --userid $ADMIN_USER --password $ADMIN_PASS --branchcode $ADMIN_BRANCH --categorycode $ADMIN_CATEGORY --cardnumber 1 --surname Admin"
else echo "[run.sh] Superlibrarian $ADMIN_USER exists"; fi

chown -R kohadev-koha:kohadev-koha /etc/koha/sites/${KOHASITE} /var/log/koha/${KOHASITE} /var/run/koha/${KOHASITE} /var/lib/koha/${KOHASITE} /var/cache/koha/${KOHASITE} 2>/dev/null || true
echo "[run.sh] updatedatabase"; su kohadev-koha -s /bin/sh -c "export KOHA_CONF=${KOHACONF} PERL5LIB=/opt/koha-perl/lib/perl5:${KOHADEVBOX}/lib:${KOHADEVBOX} KOHA_HOME=${KOHA_HOME}; cd ${KOHADEVBOX}; perl -Ilib installer/data/mysql/updatedatabase.pl"

echo "[run.sh] Starting Plack on port 5000"
PLACKUP_CMD="/opt/koha-perl/bin/plackup --port 5000 --host 0.0.0.0 --env production app.psgi"
# Set environment variables for the koha user and execute plackup.
# The final 'exec' replaces this shell process with the plackup process, making it the main container process.
exec su kohadev-koha -s /bin/sh -c " \
    export KOHA_CONF=${KOHACONF}; \
    export LOG4PERL_CONF=/etc/koha/sites/${KOHASITE}/log4perl.conf; \
    export PERL5LIB=/opt/koha-perl/lib/perl5:${KOHADEVBOX}/lib:${KOHADEVBOX}; \
    export KOHA_HOME=${KOHA_HOME}; \
    export PATH=/opt/koha-perl/bin:/usr/local/bin:/usr/bin:/bin; \
    cd ${KOHADEVBOX}; \
    exec ${PLACKUP_CMD}"
