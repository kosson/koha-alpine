#!/bin/bash
# Fixed run.sh - beefy version with full logging
set -e

KOHASITE=${KOHASITE:-kohadev}
KOHA_HOME=/var/lib/koha/${KOHASITE}
KOHACONF=/etc/koha/sites/${KOHASITE}/koha-conf.xml
LOG4PERL_CONF=/etc/koha/log4perl/log4perl-${KOHASITE}.conf
KOHADEVBOX=${KOHADEVBOX:-/kohadevbox/koha}
KOHA_USER=${KOHA_USER:-kohadev}
DB_HOST=${DB_HOST:-db}
DB_USER=koha_${KOHASITE}
DB_PASS=${MYSQL_PASS:-password}
DB_NAME=koha_${KOHASITE}

export KOHA_CONF=${KOHACONF}
export LOG4PERL_CONF=${LOG4PERL_CONF}
export KOHA_HOME=${KOHA_HOME}
export PERL5LIB=/opt/koha-perl/lib/perl5:${KOHADEVBOX}/lib:${KOHADEVBOX}
export PATH=/opt/koha-perl/bin:$PATH
export MYSQL_PWD=${DB_PASS}
export KOHADEVBOX

echo "======================================================================"
echo "[run.sh] KOHA ALPINE BEEFY - Site: ${KOHASITE}"
echo "[run.sh] Date: $(date)"
echo "[run.sh] KOHA_CONF=${KOHA_CONF}"
echo "[run.sh] PERL5LIB=${PERL5LIB}"
echo "[run.sh] DB=${DB_USER}@${DB_HOST}/${DB_NAME}"
echo "======================================================================"

# Ensure directories with correct ownership
mkdir -p /etc/koha/sites/${KOHASITE} /etc/koha/log4perl /var/log/koha/${KOHASITE} /var/run/koha/${KOHASITE} ${KOHA_HOME}/plugins /var/lock/koha/${KOHASITE}
chown -R ${KOHA_USER}:${KOHA_USER} /etc/koha /var/log/koha /var/run/koha /var/lib/koha /var/lock/koha || true

# Generate koha-conf.xml from template - ALWAYS regenerate to avoid timezone bug
echo "[run.sh] Generating ${KOHACONF}"
cp /etc/koha/koha-conf.xml.template "${KOHACONF}"
# Use | as delimiter to avoid / in paths breaking sed
sed -i \
  -e "s|__TIMEZONE__|${TIMEZONE:-Europe/Bucharest}|g" \
  -e "s|__KOHASITE__|${KOHASITE}|g" \
  -e "s|__DB_HOST__|${DB_HOST}|g" \
  -e "s|__DB_USER__|${DB_USER}|g" \
  -e "s|__DB_PASS__|${DB_PASS}|g" \
  -e "s|__DB_NAME__|${DB_NAME}|g" \
  -e "s|__SRU_BIBLIOS_PORT__|9998|g" \
  -e "s|__ZEBRA_MARC_FORMAT__|marc21|g" \
  -e "s|__OPACDIR__|${KOHADEVBOX}/opac|g" \
  -e "s|__INTRANETDIR__|${KOHADEVBOX}|g" \
  -e "s|__KOHAHOME__|${KOHA_HOME}|g" \
  "${KOHACONF}"

if ! grep -q "<timezone>${TIMEZONE:-Europe/Bucharest}</timezone>" "${KOHACONF}"; then
  echo "[run.sh] ERROR: timezone replacement failed!"
  cat "${KOHACONF}" | grep timezone || true
  exit 1
fi

chown ${KOHA_USER}:${KOHA_USER} "${KOHACONF}"
echo "[run.sh] koha-conf.xml OK - timezone=$(grep timezone ${KOHACONF} | head -1)"

# Generate log4perl
if [ ! -f "${LOG4PERL_CONF}" ]; then
  echo "[run.sh] Generating ${LOG4PERL_CONF}"
  cp /etc/koha/log4perl.conf.template "${LOG4PERL_CONF}"
  sed -i "s|__KOHASITE__|${KOHASITE}|g" "${LOG4PERL_CONF}"
  chown ${KOHA_USER}:${KOHA_USER} "${LOG4PERL_CONF}"
fi

# Wait for DB with proper env
echo "[run.sh] Waiting for DB ${DB_HOST}:3306..."
for i in $(seq 1 60); do
  if mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} -e "SELECT 1" >/dev/null 2>&1; then
    echo "[run.sh] DB ready after $i tries"
    break
  fi
  if [ $i -eq 60 ]; then
    echo "[run.sh] DB not reachable after 60 tries, failing"
    exit 1
  fi
  echo "[run.sh] DB not ready, retry $i/60"
  sleep 2
done

# Check if DB is empty
TABLE_COUNT=$(mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} -e "SHOW TABLES;" 2>/dev/null | wc -l)
echo "[run.sh] DB table count: $TABLE_COUNT"

if [ "$TABLE_COUNT" -lt 5 ]; then
  echo "[run.sh] DB empty, importing kohastructure.sql (this takes ~10 sec)..."
  mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} < ${KOHADEVBOX}/installer/data/mysql/kohastructure.sql
  echo "[run.sh] Importing mandatory data..."
  for sql in ${KOHADEVBOX}/installer/data/mysql/mandatory/*.sql; do
    echo "  - Loading $(basename $sql)"
    mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} < "$sql" 2>&1 | tail -1 || true
  done
  echo "[run.sh] Adding MAIN branch and Version..."
  mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} <<EOSQL
INSERT IGNORE INTO branches (branchcode, branchname, branchaddress1) VALUES ('MAIN','Main Library','Adunatii-Copaceni');
INSERT IGNORE INTO systempreferences (variable,value,explanation,options,type) VALUES ('Version','25.1100000','Koha version','','') ON DUPLICATE KEY UPDATE value='25.1100000';
UPDATE systempreferences SET value='25.1100000' WHERE variable='Version';
INSERT IGNORE INTO library_groups (id, title, description, ft_hide_patron_info, ft_search_groups_opac, ft_search_groups_staff) VALUES (1,'Main','Main group',0,0,0);
EOSQL
  NEW_COUNT=$(mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} -e "SHOW TABLES;" 2>/dev/null | wc -l)
  echo "[run.sh] DB initialized: $NEW_COUNT tables"
else
  echo "[run.sh] DB already initialized ($TABLE_COUNT tables), skipping import"
fi

# Clean old pid/socket
rm -rf /var/run/koha/${KOHASITE}/*
mkdir -p /var/run/koha/${KOHASITE} /var/log/koha/${KOHASITE}
chown -R ${KOHA_USER}:${KOHA_USER} /var/run/koha /var/log/koha

echo "[run.sh] Starting Plack on 0.0.0.0:${KOHA_PLACK_PORT}..."
echo "[run.sh] Using: /usr/bin/perl /opt/koha-perl/bin/plackup --port ${KOHA_PLACK_PORT} --host 0.0.0.0 ${KOHADEVBOX}/app.psgi"
echo "[run.sh] Logs: /var/log/koha/${KOHASITE}/"

# CRITICAL FIX: Use /usr/bin/perl explicitly, not the local-lib perl binary
# The local-lib perl's shebang breaks when PERL5LIB is set
exec /usr/bin/perl /opt/koha-perl/bin/plackup \
  --port ${KOHA_PLACK_PORT} \
  --host 0.0.0.0 \
  --access-log /var/log/koha/${KOHASITE}/plack-access.log \
  --error-log /var/log/koha/${KOHASITE}/plack-error.log \
  --env production \
  ${KOHADEVBOX}/app.psgi
