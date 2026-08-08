#!/bin/bash
set -e
KOHASITE=${KOHASITE:-kohadev}
KOHA_HOME=/var/lib/koha/${KOHASITE}
KOHACONF=/etc/koha/sites/${KOHASITE}/koha-conf.xml
LOG4PERL_CONF_DIR=/etc/koha/sites/${KOHASITE}
LOG4PERL_CONF=${LOG4PERL_CONF_DIR}/log4perl.conf
LOG4PERL_CONF_LEGACY=/etc/koha/log4perl/log4perl-${KOHASITE}.conf
KOHADEVBOX=${KOHADEVBOX:-/kohadevbox/koha}
KOHA_USER=kohadev
KOHA_GROUP=kohadev
DB_HOST=${DB_HOST:-db}
DB_USER=koha_${KOHASITE}
DB_PASS=${MYSQL_PASS:-password}
DB_NAME=koha_${KOHASITE}
MEMCACHED_SERVERS=${MEMCACHED_SERVERS:-memcached:11211}
MESSAGE_BROKER_HOST=${MESSAGE_BROKER_HOST:-rabbitmq}
export KOHA_CONF=${KOHACONF} LOG4PERL_CONF=${LOG4PERL_CONF} KOHA_HOME=${KOHA_HOME} PERL5LIB=/opt/koha-perl/lib/perl5:${KOHADEVBOX}/lib:${KOHADEVBOX} PATH=/opt/koha-perl/bin:/usr/local/bin:/usr/bin:/bin MYSQL_PWD=${DB_PASS} KOHADEVBOX
echo "[run.sh] BEEFY v16 FIXED - ${KOHASITE} ${KOHA_USER} $(date) MEMCACHED=${MEMCACHED_SERVERS}"

mkdir -p /etc/koha/sites/${KOHASITE} /etc/koha/log4perl /var/log/koha/${KOHASITE} /var/run/koha/${KOHASITE} ${KOHA_HOME}/plugins /var/lock/koha/${KOHASITE} /usr/share/koha/bin

# ensure templates exist in /etc/koha (critical fix)
if [ ! -f /etc/koha/koha-conf-site.xml.in ]; then
  echo "[run.sh] Restoring debian templates to /etc/koha"
  cp /kohadevbox/koha/debian/templates/* /etc/koha/ 2>/dev/null || true
fi
ls -l /etc/koha/*.in | head -5

if [ ! -f /usr/share/koha/bin/koha-functions.sh ]; then
  cp /kohadevbox/koha/debian/scripts/koha-functions.sh /usr/share/koha/bin/koha-functions.sh 2>/dev/null || true
fi

# Create config via patched koha-create
if [ -x /usr/local/bin/koha-create ]; then
  echo "[run.sh] Using koha-create: /usr/local/bin/koha-create"
  mkdir -p /etc/apache2/sites-available /etc/apache2/sites-enabled /var/log/koha/${KOHASITE} /var/lib/koha/${KOHASITE}
  echo "[run.sh] Running koha-create --use-db ${KOHASITE}"
  /usr/local/bin/koha-create --use-db --db-user "${DB_USER}" --db-password "${DB_PASS}" --db-name "${DB_NAME}" --memcached-servers "${MEMCACHED_SERVERS}" --mb-host "${MESSAGE_BROKER_HOST}" "${KOHASITE}" 2>&1 | tail -30 || true
  echo "[run.sh] koha-create exit: $?"
  ls -l /etc/koha/sites/${KOHASITE}/ 2>&1 || true
else
  echo "[run.sh] koha-create not found!"
fi

# Fallback if koha-create failed to create file
if [ ! -f "${KOHACONF}" ]; then
  echo "[run.sh] Config missing after koha-create, copying fallback template"
  cp /etc/koha/koha-conf.xml.template "${KOHACONF}" 2>/dev/null || cp /kohadevbox/templates/koha-conf.xml.template "${KOHACONF}" 2>/dev/null || cp /kohadevbox/koha/debian/templates/koha-conf-site.xml.in "${KOHACONF}" 2>/dev/null || true
fi

# Fix perms BEFORE sed (Koha Config.pm is strict)
chmod 644 "${KOHACONF}" 2>/dev/null || true
chown root:kohadev "${KOHACONF}" 2>/dev/null || chown kohadev:kohadev "${KOHACONF}" 2>/dev/null || true
ls -l "${KOHACONF}"

# Fix placeholders (critical for __MEMCACHED_SERVERS__)
if [ -f "${KOHACONF}" ]; then
  sed -i -e "s|__TIMEZONE__|${TIMEZONE:-Europe/Bucharest}|g" \
         -e "s|__KOHASITE__|${KOHASITE}|g" \
         -e "s|__DB_HOST__|${DB_HOST}|g" \
         -e "s|__DB_USER__|${DB_USER}|g" \
         -e "s|__DB_PASS__|${DB_PASS}|g" \
         -e "s|__DB_NAME__|${DB_NAME}|g" \
         -e "s|__MEMCACHED_SERVERS__|${MEMCACHED_SERVERS}|g" \
         -e "s|__MEMCACHED_NAMESPACE__|KOHA:${KOHASITE}:|g" \
         -e "s|localhost:11211|${MEMCACHED_SERVERS}|g" \
         -e "s|__SRU_BIBLIOS_PORT__|9998|g" \
         -e "s|__ZEBRA_MARC_FORMAT__|marc21|g" \
         -e "s|__OPACDIR__|${KOHADEVBOX}/opac|g" \
         -e "s|__INTRANETDIR__|${KOHADEVBOX}|g" \
         -e "s|__KOHAHOME__|${KOHA_HOME}|g" "${KOHACONF}" 2>/dev/null || true
  echo "[run.sh] koha-conf.xml memcached -> $(grep memcached ${KOHACONF} | head -1)"
fi

# Ensure perms again after sed
chmod 644 "${KOHACONF}" 2>/dev/null || true
chown root:kohadev "${KOHACONF}" 2>/dev/null || true
chmod 644 /etc/koha/sites/${KOHASITE}/log4perl.conf 2>/dev/null || true

for dest in "${LOG4PERL_CONF}" "${LOG4PERL_CONF_LEGACY}"; do mkdir -p "$(dirname "$dest")"; [ -f "$dest" ] || { cp /etc/koha/log4perl.conf.template "$dest" 2>/dev/null || cp /etc/koha/log4perl-site.conf.in "$dest" 2>/dev/null || cp /kohadevbox/templates/log4perl.conf.template "$dest" 2>/dev/null || echo "log4perl.logger=DEBUG, Screen" > "$dest"; sed -i "s|__KOHASITE__|${KOHASITE}|g" "$dest" || true; chmod 644 "$dest" 2>/dev/null || true; }; done

echo "[run.sh] Waiting DB..."
for i in $(seq 1 60); do mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} -e "SELECT 1" >/dev/null 2>&1 && { echo "DB ready $i"; break; }; sleep 2; done

# If tables don't exist, populate properly via mysql (not perl)
if ! mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} -e "SELECT 1 FROM systempreferences LIMIT 1" >/dev/null 2>&1; then
  echo "[run.sh] DB empty, importing kohastructure.sql via mysql"
  cd /kohadevbox/koha
  mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} < installer/data/mysql/kohastructure.sql 2>&1 | tail -5 || true
  for f in installer/data/mysql/mandatory/*.sql; do
    echo "[run.sh] importing $f"
    mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} < "$f" 2>&1 | grep -v "Duplicate" | tail -3 || true
  done
  mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} -e "INSERT IGNORE INTO systempreferences (variable,value,explanation) VALUES ('Version','24.1100000','Koha version')" 2>&1 || true
  echo "[run.sh] running updatedatabase.pl as ${KOHA_USER}"
  chown -R ${KOHA_USER}:${KOHA_GROUP} /etc/koha/sites/${KOHASITE} /var/log/koha/${KOHASITE} || true
  # Run as koha user to satisfy Config.pm permission check
  su ${KOHA_USER} -s /bin/sh -c "export KOHA_CONF=${KOHACONF} PERL5LIB=/opt/koha-perl/lib/perl5:${KOHADEVBOX}/lib:${KOHADEVBOX} KOHA_HOME=${KOHA_HOME}; cd ${KOHADEVBOX}; perl -Ilib installer/data/mysql/updatedatabase.pl" 2>&1 | tail -100 || perl -Ilib installer/data/mysql/updatedatabase.pl 2>&1 | tail -100 || true
fi

rm -rf /var/run/koha/${KOHASITE}/*; mkdir -p /var/run/koha/${KOHASITE} /var/log/koha/${KOHASITE}; chown -R ${KOHA_USER}:${KOHA_GROUP} /var/run/koha /var/log/koha /etc/koha/sites || true
echo "[run.sh] Starting Plack :${KOHA_PLACK_PORT:-5000}"
exec /usr/bin/perl /opt/koha-perl/bin/plackup --port ${KOHA_PLACK_PORT:-5000} --host 0.0.0.0 --access-log /var/log/koha/${KOHASITE}/plack-access.log --error-log /var/log/koha/${KOHASITE}/plack-error.log --env production ${KOHADEVBOX}/app.psgi
