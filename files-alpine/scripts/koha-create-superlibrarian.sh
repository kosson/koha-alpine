#!/bin/sh
set -e
KOHASITE=${KOHASITE:-kohadev}
export KOHA_CONF=/etc/koha/sites/${KOHASITE}/koha-conf.xml
export LOG4PERL_CONF=/etc/koha/log4perl/log4perl-${KOHASITE}.conf
export PERL5LIB=/opt/koha-perl/lib/perl5:/kohadevbox/koha/lib:/kohadevbox/koha
export MYSQL_PWD=${KOHA_DB_PASSWORD:-${MYSQL_PASS:-}}
KOHA_ADMIN_PASS=${KOHA_ADMIN_PASS:-${KOHA_PASS:-}}
if [ -z "${MYSQL_PWD}" ] || [ -z "${KOHA_ADMIN_PASS}" ]; then
  echo "ERROR: KOHA_DB_PASSWORD and KOHA_PASS must be set." >&2
  exit 1
fi
/usr/bin/perl /kohadevbox/koha/bin/koha-create-superlibrarian --userid "${KOHA_ADMIN_USER:-admin}" --password "${KOHA_ADMIN_PASS}" --branchcode MAIN --categorycode S --firstname Admin --surname Koha
