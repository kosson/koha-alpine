#!/bin/bash
set -e
KOHASITE=${KOHASITE:-kohadev}
KOHA_HOME=/var/lib/koha/${KOHASITE}
KOHACONF=/etc/koha/sites/${KOHASITE}/koha-conf.xml
KOHADEVBOX=${KOHADEVBOX:-/kohadevbox/koha}
DB_HOST=${DB_HOST:-db}
DB_USER=koha_${KOHASITE}
DB_PASS=${MYSQL_PASS:-password}
DB_NAME=koha_${KOHASITE}
MEMCACHED_SERVERS=${MEMCACHED_SERVERS:-memcached:11211}
MESSAGE_BROKER_HOST=${MESSAGE_BROKER_HOST:-rabbitmq}
export KOHA_CONF=${KOHACONF} KOHA_HOME=${KOHA_HOME} PERL5LIB=/opt/koha-perl/lib/perl5:${KOHADEVBOX}/lib:${KOHADEVBOX} PATH=/opt/koha-perl/bin:/usr/local/bin:/usr/bin:/bin MYSQL_PWD=${DB_PASS}
echo "[run.sh] BEEFY v19 FINAL - ${KOHASITE}"

# FORCE create user (Alpine busybox compatible)
if ! getent passwd kohadev-koha >/dev/null 2>&1; then
  echo "[run.sh] Creating kohadev-koha via manual method"
  # Try normal
  addgroup -S kohadev-koha 2>&1 || addgroup kohadev-koha 2>&1 || true
  adduser -D -h ${KOHA_HOME} -G kohadev-koha -S kohadev-koha 2>&1 || adduser -D -h ${KOHA_HOME} -G kohadev-koha kohadev-koha 2>&1 || true
  # If still fails, manually inject
  if ! getent passwd kohadev-koha >/dev/null 2>&1; then
    echo "kohadev-koha:x:1001:1001:Koha:/var/lib/koha/kohadev:/bin/sh" >> /etc/passwd
    echo "kohadev-koha:x:1001:kohadev" >> /etc/group 2>/dev/null || echo "kohadev-koha:x:1001:" >> /etc/group
    echo "[run.sh] Manually added to passwd"
  fi
fi
id kohadev-koha
echo "[run.sh] passwd: $(grep kohadev-koha /etc/passwd)"

mkdir -p /etc/koha/sites/${KOHASITE} /var/log/koha/${KOHASITE} /var/run/koha/${KOHASITE} ${KOHA_HOME}/plugins /var/lock/koha/${KOHASITE} /var/lib/koha/${KOHASITE}/uploads /var/cache/koha/${KOHASITE} /var/lib/koha/${KOHASITE}/tmp
if [ ! -f /etc/koha/koha-conf-site.xml.in ]; then cp /kohadevbox/koha/debian/templates/* /etc/koha/ 2>/dev/null || true; fi

echo "[run.sh] Generating config"
TEMPLATE="/etc/koha/koha-conf-site.xml.in"
DB_PASS_ESC=$(printf '%s' "$DB_PASS" | sed 's/[&/\]/\\&/g')
cp "$TEMPLATE" "${KOHACONF}.tmp"
sed -i -e "s|__KOHASITE__|$KOHASITE|g" -e "s|__DB_HOST__|$DB_HOST|g" -e "s|__DB_USER__|$DB_USER|g" -e "s|__DB_PASS__|$DB_PASS_ESC|g" -e "s|__DB_NAME__|$DB_NAME|g" -e "s|__MEMCACHED_SERVERS__|$MEMCACHED_SERVERS|g" -e "s|__MEMCACHED_NAMESPACE__|koha_${KOHASITE}:|g" -e "s|__UNIXUSER__|kohadev-koha|g" -e "s|__UNIXGROUP__|kohadev-koha|g" -e "s|__KOHA_CONF_DIR__|/etc/koha/sites/$KOHASITE|g" -e "s|__OPACPORT__|80|g" -e "s|__INTRAPORT__|8080|g" -e "s|__ZEBRA_MARC_FORMAT__|marc21|g" -e "s|__ZEBRA_LANGUAGE__|en|g" -e "s|__SRU_BIBLIOS_PORT__|9998|g" -e "s|__START_SRU_PUBLICSERVER__|<!--|g" -e "s|__END_SRU_PUBLICSERVER__|-->|g" -e "s|__TIMEZONE__|Europe/Bucharest|g" -e "s|__ELASTICSEARCH_SERVER__|localhost:9200|g" -e "s|__TEMPLATE_CACHE_DIR__|/var/cache/koha/$KOHASITE/templates|g" -e "s|__PLUGINS_DIR__|/var/lib/koha/$KOHASITE/plugins|g" -e "s|__UPLOAD_PATH__|/var/lib/koha/$KOHASITE/uploads|g" -e "s|__TMP_PATH__|/var/lib/koha/$KOHASITE/tmp|g" -e "s|__LOG_DIR__|/var/log/koha/$KOHASITE|g" -e "s|__MESSAGE_BROKER_HOST__|$MESSAGE_BROKER_HOST|g" -e "s|__MESSAGE_BROKER_PORT__|61613|g" -e "s|__MESSAGE_BROKER_USER__|guest|g" -e "s|__MESSAGE_BROKER_PASS__|guest|g" -e "s|__MESSAGE_BROKER_VHOST__|koha_$KOHASITE|g" "${KOHACONF}.tmp"
ZEBRA_PWD=$(head -c 16 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c16); API_SECRET=$(head -c 32 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c32)
sed -i -e "s|__ZEBRA_PASS__|$ZEBRA_PWD|g" -e "s|__API_SECRET__|$API_SECRET|g" -e "s|__BCRYPT_SETTINGS__||g" -e "s|__OPACSERVER__||g" -e "s|__INTRASERVER__||g" -e "s|__SMTP_HOST__|localhost|g" -e "s|__SMTP_PORT__|25|g" -e "s|__SMTP.*__||g" "${KOHACONF}.tmp"
mv "${KOHACONF}.tmp" "${KOHACONF}"
chmod 644 "${KOHACONF}"; chown kohadev-koha:kohadev-koha "${KOHACONF}" || chown 1001:1001 "${KOHACONF}" || true

cp /etc/koha/log4perl-site.conf.in /etc/koha/sites/${KOHASITE}/log4perl.conf
sed -i "s|__KOHASITE__|$KOHASITE|g; s|__LOG_DIR__|/var/log/koha/$KOHASITE|g" /etc/koha/sites/${KOHASITE}/log4perl.conf
chmod 644 /etc/koha/sites/${KOHASITE}/log4perl.conf; chown kohadev-koha:kohadev-koha /etc/koha/sites/${KOHASITE}/log4perl.conf 2>/dev/null || true

echo "[run.sh] Waiting DB..."; for i in $(seq 1 60); do mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} -e "SELECT 1" >/dev/null 2>&1 && { echo "DB ready $i"; break; }; sleep 2; done
if ! mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} -e "SELECT 1 FROM systempreferences LIMIT 1" >/dev/null 2>&1; then echo "[run.sh] DB empty"; cd /kohadevbox/koha; mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} < installer/data/mysql/kohastructure.sql 2>&1 | tail -3; for f in installer/data/mysql/mandatory/*.sql; do mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} < "$f" 2>&1 | grep -v Duplicate | tail -1 || true; done; mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} -e "INSERT IGNORE INTO systempreferences (variable,value) VALUES ('Version','24.11')" 2>&1 || true; fi

chown -R kohadev-koha:kohadev-koha /etc/koha/sites/${KOHASITE} /var/log/koha/${KOHASITE} /var/run/koha/${KOHASITE} /var/lib/koha/${KOHASITE} /var/cache/koha/${KOHASITE} 2>/dev/null || chown -R 1001:1001 /etc/koha/sites/${KOHASITE} /var/log/koha/${KOHASITE} /var/run/koha/${KOHASITE} /var/lib/koha/${KOHASITE} || true
echo "[run.sh] updatedatabase"; su kohadev-koha -s /bin/sh -c "export KOHA_CONF=${KOHACONF} PERL5LIB=/opt/koha-perl/lib/perl5:${KOHADEVBOX}/lib:${KOHADEVBOX} KOHA_HOME=${KOHA_HOME}; cd ${KOHADEVBOX}; perl -Ilib installer/data/mysql/updatedatabase.pl" 2>&1 | tail -20 || true
echo "[run.sh] Starting Plack"; exec su kohadev-koha -s /bin/sh -c "export KOHA_CONF=${KOHACONF} LOG4PERL_CONF=/etc/koha/sites/${KOHASITE}/log4perl.conf PERL5LIB=/opt/koha-perl/lib/perl5:${KOHADEVBOX}/lib:${KOHADEVBOX} KOHA_HOME=${KOHA_HOME} PATH=/opt/koha-perl/bin:/usr/local/bin:/usr/bin:/bin; cd ${KOHADEVBOX}; exec perl /opt/koha-perl/bin/plackup --port 5000 --host 0.0.0.0 --env production app.psgi"
