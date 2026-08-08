#!/bin/sh
set -e
KOHASITE=${KOHASITE:-kohadev}
export KOHA_CONF=/etc/koha/sites/${KOHASITE}/koha-conf.xml
export LOG4PERL_CONF=/etc/koha/log4perl/log4perl-${KOHASITE}.conf
export PERL5LIB=/opt/koha-perl/lib/perl5:/kohadevbox/koha/lib:/kohadevbox/koha
export MYSQL_PWD=${MYSQL_PASS:-password}
/usr/bin/perl /kohadevbox/koha/bin/koha-create-superlibrarian --userid admin --password admin123 --branchcode MAIN --categorycode S --firstname Admin --surname Koha || true
