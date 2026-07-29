# The logs of every stage

This file is for reference to a clean startup.

```bash
nicolaie@bigrig:/mnt/beckie2/DEVELOPMENT/koha-alpine$ cp OpenSearch-3.6/template.env OpenSearch-3.6/.env
nicolaie@bigrig:/mnt/beckie2/DEVELOPMENT/koha-alpine$ cd OpenSearch-3.6
nicolaie@bigrig:/mnt/beckie2/DEVELOPMENT/koha-alpine/OpenSearch-3.6$ ./opensearch_local_certificates_creator.sh
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = admin
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = os01
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = os02
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = os03
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = os04
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = os05
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = client
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = dashboards
Compliance salt and SQL master key written to /mnt/beckie2/DEVELOPMENT/koha-alpine/OpenSearch-3.6/.env.
  OS_COMPLIANCE_SALT : MBzN9V4zi00YZl8t
  OS_QUERY_MASTERKEY : b88a511ed449a711e32a07985c829b05
  (opensearch.yml files reference these via ${OS_COMPLIANCE_SALT} / ${OS_QUERY_MASTERKEY})
File permissions set (certs: 775, config dirs: 775, config files: 775).
Generating bcrypt hash via opensearch:3.6.0 hash.sh ...
internal_users.yml — all user hashes updated.
  hash : $2y$12$PQvsv0BjVP2v9.vkbyKpHefVpWcTvo.ndP/2.sxr6khLh.eqt3E7a

NOTE: New certificates invalidate any existing cluster data.
      Wipe data directories before the next cluster start:
      rm -rf /mnt/beckie2/DEVELOPMENT/koha-alpine/OpenSearch-3.6/assets/opensearch/data/os0{1,2,3,4,5}data/*
nicolaie@bigrig:/mnt/beckie2/DEVELOPMENT/koha-alpine/OpenSearch-3.6$ ./raise-from-ground-up.sh
[raise-from-ground-up] Step 1/8: Reset OpenSearch project to zero state...
[1/4] Bringing down OpenSearch compose project...
WARN[0000] Warning: No resource found to remove for project "opensearch-36". 
[2/4] Removing bind-mounted OpenSearch node data...
[3/4] Removing generated TLS credentials...
[4/4] Removing local OpenSearch image tag (if present)...

OpenSearch cluster reset complete.
Next steps:
  1) ./opensearch_local_certificates_creator.sh
  2) docker compose build os01
  3) docker compose up -d os01 os02 os03 os04 os05
[raise-from-ground-up] Step 2/8: Regenerate OpenSearch certs and internal user hashes...
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = admin
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = os01
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = os02
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = os03
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = os04
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = os05
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = client
Certificate request self-signature ok
subject=C = RO, ST = ILFOV, L = MAGURELE, O = NIPNE, OU = DFCTI, CN = dashboards
Compliance salt and SQL master key written to /mnt/beckie2/DEVELOPMENT/koha-alpine/OpenSearch-3.6/.env.
  OS_COMPLIANCE_SALT : 6RckfDgqTkqzQofx
  OS_QUERY_MASTERKEY : 39d856d1bc860e42791b24e0bbc8ecf9
  (opensearch.yml files reference these via ${OS_COMPLIANCE_SALT} / ${OS_QUERY_MASTERKEY})
File permissions set (certs: 775, config dirs: 775, config files: 775).
Generating bcrypt hash via opensearch:3.6.0 hash.sh ...
internal_users.yml — all user hashes updated.
  hash : $2y$12$AvABzStngEFC5N4Smzjj6uceELmszJf8qL3B7L30WSQs9NS4Q1Eeq

NOTE: New certificates invalidate any existing cluster data.
      Wipe data directories before the next cluster start:
      rm -rf /mnt/beckie2/DEVELOPMENT/koha-alpine/OpenSearch-3.6/assets/opensearch/data/os0{1,2,3,4,5}data/*
[raise-from-ground-up] Step 3/8: Build os01 image (shared by os01-os05)...
[+] Building 0.2s (9/9) FINISHED                                                                                                                                                                
 => [internal] load local bake definitions                                                                                                                                                 0.0s
 => => reading from stdin 649B                                                                                                                                                             0.0s
 => [internal] load build definition from Dockerfile                                                                                                                                       0.0s
 => => transferring dockerfile: 2.28kB                                                                                                                                                     0.0s
 => [internal] load metadata for docker.io/opensearchproject/opensearch:3.6.0                                                                                                              0.0s
 => [internal] load .dockerignore                                                                                                                                                          0.0s
 => => transferring context: 2B                                                                                                                                                            0.0s
 => [1/3] FROM docker.io/opensearchproject/opensearch:3.6.0                                                                                                                                0.0s
 => CACHED [2/3] RUN dnf -y install iputils net-tools curl procps --skip-broken                                                                                                            0.0s
 => CACHED [3/3] RUN /usr/share/opensearch/bin/opensearch-plugin install --batch analysis-icu                                                                                              0.0s
 => exporting to image                                                                                                                                                                     0.0s
 => => exporting layers                                                                                                                                                                    0.0s
 => => writing image sha256:6ca067a2a7d40ea4d073ab379a860b508a1017ed89adf8fff980bb3ace5b6350                                                                                               0.0s
 => => naming to docker.io/kosson/opensearch-icu:3.6.0                                                                                                                                     0.0s
 => resolving provenance for metadata file                                                                                                                                                 0.0s
[+] build 1/1
 ✔ Image kosson/opensearch-icu:3.6.0 Built                                                                                                                                                  0.2s
[raise-from-ground-up] Step 3b/8: Ensure bind-mounted node data dirs are writable by uid 1000...
[raise-from-ground-up] Step 4/8: Start OpenSearch nodes os01-os05...
[+] up 5/5
 ✔ Container os04 Created                                                                                                                                                                   0.1s
 ✔ Container os05 Created                                                                                                                                                                   0.1s
 ✔ Container os03 Created                                                                                                                                                                   0.1s
 ✔ Container os01 Created                                                                                                                                                                   0.1s
 ✔ Container os02 Created                                                                                                                                                                   0.1s
[raise-from-ground-up] Step 5/8: Wait for os01 healthcheck to pass...
[raise-from-ground-up] os01 is healthy.
[raise-from-ground-up] Step 6/8: Validate auth and auto-heal live security state if needed...
[raise-from-ground-up] Auth returned HTTP 503; applying initial_api_calls.sh then recreating os01...
Waiting for cluster health (yellow or green) ...
Cluster is ready (status: yellow)

>>> Update admin user
{"error":{"root_cause":[{"type":"exception","reason":"java.util.concurrent.TimeoutException: Timeout after 10SECONDS while retrieving configuration for [INTERNALUSERS](index=.opendistro_security)"}],"type":"exception","reason":"java.util.concurrent.TimeoutException: Timeout after 10SECONDS while retrieving configuration for [INTERNALUSERS](index=.opendistro_security)","caused_by":{"type":"timeout_exception","reason":"Timeout after 10SECONDS while retrieving configuration for [INTERNALUSERS](index=.opendistro_security)"}},"status":500}

>>> Update dashboards user
{"error":{"root_cause":[{"type":"exception","reason":"java.util.concurrent.TimeoutException: Timeout after 10SECONDS while retrieving configuration for [INTERNALUSERS](index=.opendistro_security)"}],"type":"exception","reason":"java.util.concurrent.TimeoutException: Timeout after 10SECONDS while retrieving configuration for [INTERNALUSERS](index=.opendistro_security)","caused_by":{"type":"timeout_exception","reason":"Timeout after 10SECONDS while retrieving configuration for [INTERNALUSERS](index=.opendistro_security)"}},"status":500}

>>> Create/update dashboards role
{"status":"OK","message":"'dashboards' updated."}

>>> Map own_index
{"status":"OK","message":"'own_index' updated."}

>>> Map kibana_server (Dashboards service account)
{"status":"OK","message":"'kibana_server' updated."}

>>> Map all_access
{"status":"OK","message":"'all_access' updated."}

>>> Map custom dashboards role
{"status":"CREATED","message":"'dashboards' created."}

>>> Map readall
{"status":"OK","message":"'readall' updated."}

=== Done. Security configuration applied to https://localhost:9200 ===
[+] up 1/1
 ✔ Container os01 Recreated                                                                                                                                                                 0.5s
[raise-from-ground-up] os01 is healthy.
[raise-from-ground-up] Admin auth probe succeeded (HTTP 200).
[raise-from-ground-up] Step 7/8: Start dashboards after node/auth validation...
[+] up 2/2
 ✔ Container os01       Healthy                                                                                                                                                             0.6s
 ✔ Container dashboards Created                                                                                                                                                             0.1s
[raise-from-ground-up] Step 8/8: Run final checks and tests...
NAME         IMAGE                                           COMMAND                  SERVICE      CREATED          STATUS                    PORTS
dashboards   opensearchproject/opensearch-dashboards:3.6.0   "./opensearch-dashbo…"   dashboards   1 second ago     Up Less than a second     0.0.0.0:5601->5601/tcp, [::]:5601->5601/tcp
os01         kosson/opensearch-icu:3.6.0                     "./opensearch-docker…"   os01         47 seconds ago   Up 46 seconds (healthy)   0.0.0.0:9200->9200/tcp, [::]:9200->9200/tcp, 9300/tcp, 0.0.0.0:9600->9600/tcp, [::]:9600->9600/tcp, 9650/tcp
os02         kosson/opensearch-icu:3.6.0                     "./opensearch-docker…"   os02         2 minutes ago    Up 2 minutes              9200/tcp, 9300/tcp, 9600/tcp, 9650/tcp
os03         kosson/opensearch-icu:3.6.0                     "./opensearch-docker…"   os03         2 minutes ago    Up 2 minutes              9200/tcp, 9300/tcp, 9600/tcp, 9650/tcp
os04         kosson/opensearch-icu:3.6.0                     "./opensearch-docker…"   os04         2 minutes ago    Up 2 minutes              9200/tcp, 9300/tcp, 9600/tcp, 9650/tcp
os05         kosson/opensearch-icu:3.6.0                     "./opensearch-docker…"   os05         2 minutes ago    Up 2 minutes              9200/tcp, 9300/tcp, 9600/tcp, 9650/tcp
TAP version 14
# OpenSearch os01 auth integration check

ok 1 - Docker available
ok 2 - OpenSearch .env exists
ok 3 - os01 container exists
ok 4 - OPENSEARCH_INITIAL_ADMIN_PASSWORD is set
ok 5 - os01 auth succeeds with OPENSEARCH_INITIAL_ADMIN_PASSWORD

1..5
# Passed: 5  Failed: 0
[raise-from-ground-up] SUCCESS: OpenSearch cluster raised from zero and validation tests passed.
[raise-from-ground-up] Cluster status=yellow, nodes=5
nicolaie@bigrig:/mnt/beckie2/DEVELOPMENT/koha-alpine/OpenSearch-3.6$ docker compose down -v --remove-orphans
[+] down 6/6
 ✔ Container os02       Removed                                                                                                                                                            2.0ss
 ✔ Container os03       Removed                                                                                                                                                            1.9ss
 ✔ Container dashboards Removed                                                                                                                                                            0.6ss
 ✔ Container os05       Removed                                                                                                                                                            0.4ss
 ✔ Container os04       Removed                                                                                                                                                            2.0ss
 ✔ Container os01       Removed                                                                                                                                                            10.4s
nicolaie@bigrig:/mnt/beckie2/DEVELOPMENT/koha-alpine/OpenSearch-3.6$ docker compose -f docker-compose-alpinekoha.yml build
open /mnt/beckie2/DEVELOPMENT/koha-alpine/OpenSearch-3.6/docker-compose-alpinekoha.yml: no such file or directory
nicolaie@bigrig:/mnt/beckie2/DEVELOPMENT/koha-alpine/OpenSearch-3.6$ cd ..
nicolaie@bigrig:/mnt/beckie2/DEVELOPMENT/koha-alpine$ docker compose -f docker-compose-alpinekoha.yml build
[+] Building 125.6s (76/76) FINISHED                                                                                                                                                            
 => [internal] load local bake definitions                                                                                                                                                 0.0s
 => => reading from stdin 539B                                                                                                                                                             0.0s
 => [internal] load build definition from Dockerfile-Alpine                                                                                                                                0.0s
 => => transferring dockerfile: 14.50kB                                                                                                                                                    0.0s
 => [internal] load metadata for docker.io/library/alpine:3.24.1                                                                                                                           0.0s
 => [internal] load .dockerignore                                                                                                                                                          0.0s
 => => transferring context: 2B                                                                                                                                                            0.0s
 => [internal] load build context                                                                                                                                                          0.0s
 => => transferring context: 108.29kB                                                                                                                                                      0.0s
 => [ 1/69] FROM docker.io/library/alpine:3.24.1                                                                                                                                           0.0s
 => CACHED [ 2/69] RUN apk add --no-cache     apache2     apache2-utils     bash     bash-completion     build-base     perl-bytes-random-secure     coreutils     perl-business-isbn      0.0s
 => CACHED [ 3/69] RUN npm install -g yarn gulp-cli                                                                                                                                        0.0s
 => CACHED [ 4/69] RUN cpanm --notest Modern::Perl                                                                                                                                         0.0s
 => [ 5/69] RUN cpanm --notest Crypt::SysRandom                                                                                                                                            1.2s
 => [ 6/69] RUN cpanm --notest Locale::PO                                                                                                                                                  1.2s
 => [ 7/69] RUN cpanm --notest Struct::Diff                                                                                                                                                1.7s 
 => [ 8/69] RUN cpanm --notest DateTime::Format::MySQL                                                                                                                                     1.9s 
 => [ 9/69] RUN cpanm --notest Locale::Currency::Format                                                                                                                                    1.0s 
 => [10/69] RUN cpanm --notest Array::Utils                                                                                                                                                1.0s 
 => [11/69] RUN cpanm --notest MARC::Record                                                                                                                                                1.3s 
 => [12/69] RUN cpanm --notest MARC::Record::MiJ                                                                                                                                           3.2s 
 => [13/69] RUN cpanm --notest MARC::File::XML                                                                                                                                            14.9s 
 => [14/69] RUN cpanm --notest GD::Barcode                                                                                                                                                 1.5s 
 => [15/69] RUN cpanm --notest Auth::GoogleAuth                                                                                                                                            1.7s 
 => [16/69] RUN cpanm --notest Number::Format                                                                                                                                              1.1s 
 => [17/69] RUN cpanm --notest Algorithm::Munkres                                                                                                                                          1.1s 
 => [18/69] RUN cpanm --notest Net::Stomp                                                                                                                                                  1.8s 
 => [19/69] RUN cpanm --notest Mojolicious::Plugin::OAuth2                                                                                                                                 1.1s 
 => [20/69] RUN cpanm --notest JSON::Validator                                                                                                                                            17.8s 
 => [21/69] RUN cpanm --notest Text::Iconv                                                                                                                                                 1.5s 
 => [22/69] RUN cpanm --notest Algorithm::CheckDigits                                                                                                                                      1.8s 
 => [23/69] RUN cpanm --notest Locale::Messages                                                                                                                                            2.4s 
 => [24/69] RUN cpanm --notest DBIx::RunSQL                                                                                                                                                1.9s 
 => [25/69] RUN cpanm --notest WWW::CSRF                                                                                                                                                   1.2s 
 => [26/69] RUN cpanm --notest Mojo::JWT                                                                                                                                                   3.3s
 => [27/69] RUN cpanm --notest Email::Stuffer                                                                                                                                              6.7s
 => [28/69] RUN cpanm --notest Lingua::Stem                                                                                                                                                6.6s
 => [29/69] RUN cpanm --notest Lingua::Stem::Snowball                                                                                                                                      4.9s
 => [30/69] RUN cpanm --notest Search::Elasticsearch                                                                                                                                       8.0s
 => [31/69] RUN cpanm --notest DBIx::Class                                                                                                                                                15.9s
 => [32/69] RUN mkdir -p /usr/local/share/perl5/site_perl     && cat >/usr/local/share/perl5/site_perl/ZOOM.pm <<'EOF'                                                                     0.2s
 => [33/69] RUN mkdir -p     /etc/koha     /etc/koha/zebradb     /etc/koha/zebradb/marc_defs     /etc/default     /etc/cron.d     /etc/cron.daily     /etc/cron.hourly     /etc/cron.mont  0.2s
 => [34/69] RUN if [ -e /usr/share/xml/docbook/xsl-stylesheets-1.79.2/manpages/docbook.xsl ]; then         rm -rf /usr/share/xml/docbook/stylesheet/docbook-xsl-ns;         ln -s /usr/sh  0.2s
 => [35/69] RUN cat >/usr/sbin/apachectl <<'EOF'                                                                                                                                           0.2s
 => [36/69] RUN cp /usr/sbin/apachectl /usr/sbin/apache2ctl && chmod 0755 /usr/sbin/apachectl /usr/sbin/apache2ctl                                                                         0.2s
 => [37/69] RUN cat >/usr/local/bin/a2ensite <<'EOF'                                                                                                                                       0.2s
 => [38/69] RUN cat >/usr/local/bin/a2dissite <<'EOF'                                                                                                                                      0.2s
 => [39/69] RUN cat >/usr/local/bin/a2enmod <<'EOF'                                                                                                                                        0.2s
 => [40/69] RUN cat >/usr/local/bin/a2dismod <<'EOF'                                                                                                                                       0.2s
 => [41/69] RUN chmod 0755 /usr/local/bin/a2ensite /usr/local/bin/a2dissite /usr/local/bin/a2enmod /usr/local/bin/a2dismod                                                                 0.2s
 => [42/69] RUN if [ -f /etc/apache2/httpd.conf ]; then         grep -Fqx 'IncludeOptional /etc/apache2/sites-enabled/*.conf' /etc/apache2/httpd.conf             || echo 'IncludeOptiona  0.2s
 => [43/69] RUN cat >/usr/local/bin/adduser <<'EOF'                                                                                                                                        0.2s
 => [44/69] RUN chmod 0755 /usr/local/bin/adduser                                                                                                                                          0.2s
 => [45/69] RUN cat >/usr/local/bin/daemon <<'EOF'                                                                                                                                         0.2s
 => [46/69] RUN chmod 0755 /usr/local/bin/daemon                                                                                                                                           0.2s
 => [47/69] RUN mkdir -p /lib/lsb                                                                                                                                                          0.2s
 => [48/69] RUN cat >/lib/lsb/init-functions <<'EOF'                                                                                                                                       0.2s
 => [49/69] RUN chmod 0755 /lib/lsb/init-functions                                                                                                                                         0.2s
 => [50/69] RUN cat >/usr/local/bin/rc-service <<'EOF'                                                                                                                                     0.2s
 => [51/69] RUN chmod 0755 /usr/local/bin/rc-service                                                                                                                                       0.2s
 => [52/69] RUN cat >/usr/local/bin/service <<'EOF'                                                                                                                                        0.2s
 => [53/69] RUN chmod 0755 /usr/local/bin/service                                                                                                                                          0.2s
 => [54/69] RUN cat >/etc/init.d/apache2 <<'EOF'                                                                                                                                           0.2s
 => [55/69] RUN chmod 0755 /etc/init.d/apache2                                                                                                                                             0.2s
 => [56/69] RUN mkdir -p /kohadevbox                                                                                                                                                       0.2s
 => [57/69] WORKDIR /kohadevbox                                                                                                                                                            0.0s
 => [58/69] COPY files-alpine/run.sh /kohadevbox/                                                                                                                                          0.0s
 => [59/69] COPY apply-patches.sh /kohadevbox/                                                                                                                                             0.1s
 => [60/69] COPY patches /kohadevbox/patches                                                                                                                                               0.0s
 => [61/69] COPY files-alpine/lib /kohadevbox/lib                                                                                                                                          0.1s
 => [62/69] COPY files-alpine/templates /kohadevbox/templates                                                                                                                              0.0s
 => [63/69] COPY files-alpine/git_hooks /kohadevbox/git_hooks                                                                                                                              0.0s
 => [64/69] COPY files-alpine/mariadb-ssl /etc/mysql/ssl                                                                                                                                   0.1s
 => [65/69] COPY env/defaults.env /kohadevbox/templates/defaults.env                                                                                                                       0.0s
 => [66/69] RUN sed -i 's/\r$//' /kohadevbox/run.sh     && sed -i 's/\r$//' /kohadevbox/apply-patches.sh     && find /kohadevbox/templates -type f -exec sed -i 's/\r$//' {} +     && fin  0.2s
 => [67/69] RUN cd /kohadevbox     && git clone https://gitlab.com/koha-community/koha-misc4dev.git misc4dev     && git clone https://gitlab.com/koha-community/koha-gitify.git gitify     4.3s
 => [68/69] COPY files-alpine/misc4dev/cp_alpine_files.pl /kohadevbox/misc4dev/cp_alpine_files.pl                                                                                          1.2s
 => [69/69] RUN chmod +x /kohadevbox/misc4dev/cp_alpine_files.pl                                                                                                                           1.3s
 => exporting to image                                                                                                                                                                     5.5s
 => => exporting layers                                                                                                                                                                    5.5s
 => => writing image sha256:f8df0a72bae68bc601f013d5478a9b88a07faae6f080448bb9ad7d90a87d7654                                                                                               0.0s
 => => naming to docker.io/kosson/koha-alpine:26.11                                                                                                                                        0.0s
 => resolving provenance for metadata file                                                                                                                                                 0.0s
[+] build 1/1
 ✔ Image kosson/koha-alpine:26.11 Built                                                                                                                                                   125.6s
nicolaie@bigrig:/mnt/beckie2/DEVELOPMENT/koha-alpine$ ./stack-alpine.sh tls-client-cert

╔════════════════════════════════════╗
║   Alpine Koha Stack Manager        ║
╚════════════════════════════════════╝

[19:33:31] Checking prerequisites...
[19:33:31] ✓ Prerequisites OK

── Preparing MariaDB client TLS materials ──
[19:33:31] ✓ Client TLS cert/key already present. Reusing existing files.
[19:33:31] ✓ Configured env/.env for Koha DB client TLS cert/key.
[19:33:31] Values set: KOHA_DB_TLS_CLIENT_CERTIFICATE=/etc/mysql/ssl/client-cert.pem
[19:33:31]            KOHA_DB_TLS_CLIENT_KEY=/etc/mysql/ssl/client-key.pem
[19:33:31] ✓ TLS client materials are ready. Next: ./stack-alpine.sh restart --no-logs
nicolaie@bigrig:/mnt/beckie2/DEVELOPMENT/koha-alpine$ ./stack-alpine.sh start

╔════════════════════════════════════╗
║   Alpine Koha Stack Manager        ║
╚════════════════════════════════════╝

[19:43:43] Checking prerequisites...
[19:43:43] ✓ Prerequisites OK

── Ensuring Koha source tree ──
[19:43:43] ✓ Koha source already present at /mnt/beckie2/DEVELOPMENT/koha-alpine/koha

── Preparing OpenSearch certificates ──
[19:43:43] ✓ OpenSearch certificates already present.
[19:43:43] ✓ OpenSearch certificates ready.

── Starting Traefik reverse proxy ──
[19:43:43] ✓ Network 'frontend' already exists.
[19:43:43] ✓ Traefik started (HTTP :8000, dashboard :8083).

── Starting OpenSearch 3.6 cluster ──
[+] up 5/5
 ✔ Container os03 Created                                                                                                                                                                   0.1s
 ✔ Container os04 Created                                                                                                                                                                   0.1s
 ✔ Container os01 Created                                                                                                                                                                   0.1s
 ✔ Container os02 Created                                                                                                                                                                   0.1s
 ✔ Container os05 Created                                                                                                                                                                   0.1s
[19:43:44] ✓ OpenSearch core nodes started (os01–os05).
[19:43:44] Waiting for OpenSearch cluster to reach green status...
[19:43:44] ⚠  This may take up to 5 minutes on first start (security plugin initialises).
  [9/72] waiting...
[19:44:29] ✓ OpenSearch cluster is green.
[19:44:29] ✓ Aligned Koha OpenSearch credentials with OpenSearch-3.6/.env.
[19:44:29] ✓ OpenSearch auth probe succeeded (HTTP 200).

── Starting OpenSearch Dashboards ──
[+] up 2/2
 ✔ Container os01       Healthy                                                                                                                                                             0.6s
 ✔ Container dashboards Created                                                                                                                                                             0.1s
[19:44:30] ✓ OpenSearch Dashboards started.

── Starting MariaDB + Memcached ──
[19:44:30] ✓ Network 'knonikl' already exists.
[19:44:30] ✓ Network 'opensearch-36_osearch' already exists.
[+] up 4/4
 ✔ Network koha-alpine_kohanet       Created                                                                                                                                                0.0s
 ✔ Volume koha-alpine_koha-db-data   Created                                                                                                                                                0.0s
 ✔ Container koha-alpine-db-1        Created                                                                                                                                                0.1s
 ✔ Container koha-alpine-memcached-1 Created                                                                                                                                                0.1s
[19:44:30] ✓ Support services started.
[19:44:30] Waiting for MariaDB to accept connections...
  [3/30] waiting...[19:44:37] ✓ MariaDB is ready.

── Recreating Koha database ──
[19:44:37] Dropping and recreating 'koha_kohadev'...
[19:44:37] ✓ Database 'koha_kohadev' ready.
[19:44:37] Alpine bootstrap profile: resume (skipping full DB population/reindex on existing DB)

── Starting Koha container ──
[19:44:37] Demo data mode: with demo data
[+] up 5/5
 ✔ Volume koha-alpine_koha-rabbitmq-data Created                                                                                                                                            0.0s
 ✔ Container koha-alpine-memcached-1     Running                                                                                                                                            0.0s
 ✔ Container koha-alpine-rabbitmq-1      Created                                                                                                                                            0.1s
 ✔ Container koha-alpine-db-1            Running                                                                                                                                            0.0s
 ✔ Container koha-alpine-koha-1          Created                                                                                                                                            0.1s
[19:44:37] ✓ Koha container started (with demo data).

── Configuring Koha interface languages ──
[19:44:37] Language list from env/.env: en,es-ES,ro-RO,ca-ES,hu-HU,de-DE
[19:44:37] Waiting for Koha translation runtime and full startup readiness for instance 'kohadev'...
  [74/350] waiting...
[19:49:40] ✓ Koha translation runtime and full startup for instance 'kohadev' are ready.
[19:49:40] Installing translation pack: es-ES
[19:49:50] Installing translation pack: ro-RO
[19:50:00] Installing translation pack: ca-ES
[19:50:10] Installing translation pack: hu-HU
[19:50:21] Installing translation pack: de-DE
[19:50:31] Applying language preferences to database (koha_kohadev)
[19:50:31] ✓ Language configuration applied: Staff/OPAC=en,es-ES,ro-RO,ca-ES,hu-HU,de-DE, opaclanguagesdisplay=1

[19:50:31] Koha container is running and initialising.

── Koha startup logs ──
[19:50:31] ⚠  Startup takes 5–15 minutes. Watching for key milestones...
[19:50:31] ⚠  Press Ctrl-C at any time to detach — the stack will keep running.

koha-1  | Service 'hwdrivers' needs non existent service 'dev'
koha-1  | Service 'machine-id' needs non existent service 'dev'
koha-1  |  * Caching service dependencies ... [ ok ]
koha-1  | Runlevel: default
koha-1  | Runlevel: boot
koha-1  | Runlevel: sysinit
koha-1  | Runlevel: shutdown
koha-1  | Runlevel: nonetwork
koha-1  | Dynamic Runlevel: hotplugged
koha-1  | Dynamic Runlevel: needed/wanted
koha-1  | Dynamic Runlevel: manual
koha-1  | Running [sudo cp /kohadevbox/koha/debian/templates/* /etc/koha]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-post-install-setup /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/unavailable.html /usr/share/koha/intranet/htdocs]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/unavailable.html /usr/share/koha/opac/htdocs]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/templates/* /etc/koha]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-functions.sh /usr/share/koha/bin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-create /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-create-dirs /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-disable /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-dump /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-dump-defaults /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-elasticsearch /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-email-disable /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-email-enable /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-enable /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-es-indexer /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-foreach /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-indexer /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-list /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-mysql /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-passwd /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-plack /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-rebuild-zebra /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-remove /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-reset-passwd /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-restore /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-run-backups /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-shell /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-sip /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-sitemap /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-translate /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-upgrade-schema /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-upgrade-to-3.4 /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-worker /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-z3950-responder /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-zebra /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.bash-completion /etc/bash_completion.d/koha-common]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.default /etc/default/koha-common]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.cron.daily /etc/cron.daily/koha-common]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.cron.d /etc/cron.d/koha-common]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.init /etc/init.d/koha-common]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.logrotate /etc/logrotate.d/koha-common]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.cron.monthly /etc/cron.monthly/koha-common]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.cron.hourly /etc/cron.hourly/koha-common]...
koha-1  | Running [sudo xsltproc --output /usr/share/man/man8/ /usr/share/xml/docbook/stylesheet/docbook-xsl-ns/manpages/docbook.xsl /kohadevbox/koha/debian/docs/*.xml]...
koha-1  | Note: Writing koha-common.8
koha-1  | Note: Writing koha-create-dirs.8
koha-1  | Note: Writing koha-create.8
koha-1  | Note: Writing koha-disable.8
koha-1  | Note: Writing koha-dump-defaults.8
koha-1  | Note: Writing koha-dump.8
koha-1  | Note: Writing koha-elasticsearch.8
koha-1  | Note: Writing koha-email-disable.8
koha-1  | Note: Writing koha-email-enable.8
koha-1  | Note: Writing koha-enable.8
koha-1  | Note: Writing koha-es-indexer.8
koha-1  | Note: Writing koha-foreach.8
koha-1  | Note: Writing koha-indexer.8
koha-1  | Note: Writing koha-list.8
koha-1  | Note: Writing koha-mysql.8
koha-1  | Note: Writing koha-mysqlcheck.8
koha-1  | Warn: AUTHOR sect.: no personblurb|contrib for Mason James         
koha-1  | Note: AUTHOR sect.: see http://www.docbook.org/tdg5/en/html/contr  
koha-1  | Note: AUTHOR sect.: see http://www.docbook.org/tdg5/en/html/perso  
koha-1  | Note: Writing koha-passwd.8
koha-1  | Note: Writing koha-plack.8
koha-1  | Note: Writing koha-rebuild-zebra.8
koha-1  | Note: Writing koha-remove.8
koha-1  | Note: Writing koha-reset-passwd.8
koha-1  | Note: Writing koha-restore.8
koha-1  | Note: Writing koha-run-backups.8
koha-1  | Note: Writing koha-shell.8
koha-1  | Note: Writing koha-sip.8
koha-1  | Note: Writing koha-sitemap.8
koha-1  | Note: Writing koha-translate.8
koha-1  | Note: Writing koha-upgrade-schema.8
koha-1  | Note: Writing koha-upgrade-to-3.4.8
koha-1  | Note: Writing koha-worker.8
koha-1  | Note: Writing koha-z3950-responder.8
koha-1  | Note: Writing koha-zebra.8
koha-1  | Running [sudo rm /usr/share/man/man8/koha-*.8.gz]...
koha-1  | rm: cannot remove '/usr/share/man/man8/koha-*.8.gz': No such file or directory
koha-1  | Running [sudo gzip /usr/share/man/man8/koha-*.8]...
koha-1  | Connection to db (172.23.0.2) 3306 port [tcp/mysql] succeeded!
koha-1  | [koha-create] Detected existing database koha_kohadev; using --use-db
koha-1  | [service shim] apache2 restart (no-op in container)
koha-1  | [koha-create] WARNING: bootstrap failed in Alpine compatibility mode; continuing to surface downstream blockers
koha-1  | [cypress] Make the pre-built cypress available to the instance user [HACK]
koha-1  |     [*] Created cache dir /var/lib/koha/kohadev/.cache/
koha-1  |     [*] Chowning /var/lib/koha/kohadev/.cache/
koha-1  |     [*] Cypress dir linked to /var/lib/koha/kohadev/.cache/
koha-1  | [koha-l10n] Handling koha-l10n as requested
koha-1  |     [*] Cloning koha-l10n into misc/translator/po
koha-1  | Cloning into '/kohadevbox/koha/misc/translator/po'...
Updating files: 100% (956/956), done.56)
koha-1  | [API logging] Set TRACE to API log4perl config
koha-1  |     [*] TRACE set for the API log4perl configuration
koha-1  | [git] Setting up Git on the instance user
koha-1  | [git] Setting up Git on the instance user
koha-1  |     [*] Generating /var/lib/koha/kohadev/.gitconfig
koha-1  |     [*] General setup
koha-1  |     [*] Installing and setting hooks (/kohadevbox/koha)
koha-1  | gitifying kohadev (/etc/koha/sites/kohadev) to point at '/kohadevbox/koha'
koha-1  | 
koha-1  | I appear to be done...
koha-1  | Please remember to restart apache before trying to use 'kohadev' ;) 
koha-1  | Instance kohadev already enabled.
koha-1  | [yarn] Running yarn install to /kohadevbox/koha/node_modules
koha-1  | yarn install v1.22.22
koha-1  | [1/4] Resolving packages...
koha-1  | [2/4] Fetching packages...
koha-1  | warning lru.min@1.1.3: The engine "bun" appears to be invalid.
koha-1  | warning lru.min@1.1.3: The engine "deno" appears to be invalid.
koha-1  | [3/4] Linking dependencies...
koha-1  | warning " > @cypress/webpack-preprocessor@6.0.4" has unmet peer dependency "@babel/core@^7.25.2".
koha-1  | warning " > @cypress/webpack-preprocessor@6.0.4" has unmet peer dependency "@babel/preset-env@^7.25.3".
koha-1  | warning " > @cypress/webpack-preprocessor@6.0.4" has unmet peer dependency "babel-loader@^8.3 || ^9 || ^10".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-jest@29.7.0" has unmet peer dependency "@babel/core@^7.8.0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax@1.2.0" has unmet peer dependency "@babel/core@^7.0.0 || ^8.0.0-0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-jest@29.6.3" has unmet peer dependency "@babel/core@^7.0.0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax > @babel/plugin-syntax-async-generators@7.8.4" has unmet peer dependency "@babel/core@^7.0.0-0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax > @babel/plugin-syntax-bigint@7.8.3" has unmet peer dependency "@babel/core@^7.0.0-0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax > @babel/plugin-syntax-class-properties@7.12.13" has unmet peer dependency "@babel/core@^7.0.0-0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax > @babel/plugin-syntax-class-static-block@7.14.5" has unmet peer dependency "@babel/core@^7.0.0-0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax > @babel/plugin-syntax-import-attributes@7.27.1" has unmet peer dependency "@babel/core@^7.0.0-0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax > @babel/plugin-syntax-import-meta@7.10.4" has unmet peer dependency "@babel/core@^7.0.0-0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax > @babel/plugin-syntax-json-strings@7.8.3" has unmet peer dependency "@babel/core@^7.0.0-0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax > @babel/plugin-syntax-logical-assignment-operators@7.10.4" has unmet peer dependency "@babel/core@^7.0.0-0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax > @babel/plugin-syntax-nullish-coalescing-operator@7.8.3" has unmet peer dependency "@babel/core@^7.0.0-0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax > @babel/plugin-syntax-numeric-separator@7.10.4" has unmet peer dependency "@babel/core@^7.0.0-0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax > @babel/plugin-syntax-object-rest-spread@7.8.3" has unmet peer dependency "@babel/core@^7.0.0-0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax > @babel/plugin-syntax-optional-catch-binding@7.8.3" has unmet peer dependency "@babel/core@^7.0.0-0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax > @babel/plugin-syntax-optional-chaining@7.8.3" has unmet peer dependency "@babel/core@^7.0.0-0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax > @babel/plugin-syntax-private-property-in-object@7.14.5" has unmet peer dependency "@babel/core@^7.0.0-0".
koha-1  | warning "@koha-community/prettier-plugin-template-toolkit > babel-preset-current-node-syntax > @babel/plugin-syntax-top-level-await@7.14.5" has unmet peer dependency "@babel/core@^7.0.0-0".
koha-1  | warning "@redocly/cli > @redocly/respect-core > better-ajv-errors@1.2.0" has unmet peer dependency "ajv@4.11.8 - 8".
koha-1  | warning "swagger-cli > @apidevtools/swagger-cli > @apidevtools/swagger-parser@10.1.1" has unmet peer dependency "openapi-types@>=7".
koha-1  | [4/4] Building fresh packages...
koha-1  | Done in 134.38s.
koha-1  | [db-detect] Probing 'koha_kohadev' for existing Koha data...
koha-1  | [db-detect] Database is empty — proceeding with fresh Koha installation
koha-1  | [bootstrap-profile] resume -> RUN_DB_POPULATION_ON_EXISTING_DB=no
koha-1  | Running [sudo koha-shell kohadev -p -c 'PERL5LIB=/kohadevbox/koha:/kohadevbox/koha/lib:/kohadevbox/qa-test-tools perl /kohadevbox/misc4dev/populate_db.pl -v --opac-base-url http://kohadev.127.0.0.1.nip.io --intranet-base-url http://kohadev-intra.127.0.0.1.nip.io --marcflavour MARC21']...
koha-1  | Inserting koha db structure...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/mandatory/sysprefs.sql...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/mandatory/subtag_registry.sql...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/mandatory/auth_val_cat.sql...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/mandatory/message_transport_types.sql...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/mandatory/sample_notices_message_attributes.sql...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/mandatory/sample_notices_message_transports.sql...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/mandatory/keyboard_shortcuts.sql...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/mandatory/userflags.sql...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/mandatory/userpermissions.sql...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/mandatory/audio_alerts.sql...
koha-1  | Skipping /kohadevbox/koha/installer/data/mysql/mandatory/account_offset_types.sql
koha-1  | Skipping /kohadevbox/koha/installer/data/mysql/mandatory/account_credit_types.sql
koha-1  | Skipping /kohadevbox/koha/installer/data/mysql/mandatory/account_debit_types.sql
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/mandatory/account_credit_types.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/mandatory/account_debit_types.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/mandatory/auth_values.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/mandatory/class_sources.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/mandatory/illbatch_statuses.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/mandatory/patron_restriction_types.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/mandatory/sample_frequencies.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/mandatory/sample_notices.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/mandatory/sample_numberpatterns.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/optional/auth_val.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/optional/csv_profiles.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/optional/marc21_holdings_coded_values.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/optional/marc21_relatorterms.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/optional/parameters.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/optional/patron_atributes.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/optional/patron_categories.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/optional/sample_creator_data.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/optional/sample_itemtypes.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/optional/sample_libraries.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/optional/sample_libraries_holidays.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/optional/sample_news.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/optional/sample_patrons.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/optional/sample_quotes.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/optional/sample_z3950_servers.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/marcflavour/marc21/mandatory/authorities_normal_marc21.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/marcflavour/marc21/mandatory/marc21_framework_DEFAULT.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/marcflavour/marc21/optional/marc21_default_matching_rules.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/marcflavour/marc21/optional/marc21_sample_fastadd_framework.yml...
koha-1  | Inserting /kohadevbox/koha/installer/data/mysql/en/marcflavour/marc21/optional/marc21_simple_bib_frameworks.yml...
koha-1  | Setting the MARC flavour on the sysprefs...
koha-1  | Setting Koha version to 25.1105000...
koha-1  | Running [sudo koha-shell kohadev -p -c 'PERL5LIB=/kohadevbox/koha:/kohadevbox/koha/lib:/kohadevbox/qa-test-tools perl /kohadevbox/misc4dev/create_superlibrarian.pl --userid koha --password koha ']...
koha-1  | Running [sudo koha-shell kohadev -c 'PERL5LIB=/kohadevbox/koha:/kohadevbox/koha/lib:/kohadevbox/qa-test-tools perl /kohadevbox/misc4dev/insert_data.pl --marcflavour MARC21']...
koha-1  | $VAR1 = [
koha-1  |           '/kohadevbox/misc4dev/data/sql/marc21/2412/after_26684/biblio.sql',
koha-1  |           '/kohadevbox/misc4dev/data/sql/marc21/2412/after_26684/biblioitems.sql',
koha-1  |           '/kohadevbox/misc4dev/data/sql/marc21/2412/after_26684/items.sql',
koha-1  |           '/kohadevbox/misc4dev/data/sql/marc21/2412/after_26684/auth_header.sql',
koha-1  |           '/kohadevbox/misc4dev/data/sql/marc21/2412/after_26684/biblio_metadata.sql'
koha-1  |         ];
koha-1  | Running [koha-mysql kohadev -e 'UPDATE systempreferences SET value="1" WHERE variable="RESTBasicAuth"']...
koha-1  | mysql: Deprecated program name. It will be removed in a future release, use '/usr/bin/mariadb' instead
koha-1  | There is no custom.sql (/kohadevbox/koha/shared/custom.sql) file, skipping.
koha-1  | Running [sudo perl /kohadevbox/misc4dev/cp_debian_files.pl --instance=kohadev --koha_dir=/kohadevbox/koha --gitify_dir=/kohadevbox/gitify]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/templates/* /etc/koha]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-post-install-setup /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/unavailable.html /usr/share/koha/intranet/htdocs]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/unavailable.html /usr/share/koha/opac/htdocs]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/templates/* /etc/koha]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-functions.sh /usr/share/koha/bin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-create /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-create-dirs /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-disable /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-dump /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-dump-defaults /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-elasticsearch /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-email-disable /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-email-enable /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-enable /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-es-indexer /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-foreach /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-indexer /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-list /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-mysql /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-passwd /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-plack /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-rebuild-zebra /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-remove /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-reset-passwd /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-restore /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-run-backups /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-shell /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-sip /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-sitemap /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-translate /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-upgrade-schema /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-upgrade-to-3.4 /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-worker /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-z3950-responder /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/scripts/koha-zebra /usr/sbin]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.cron.hourly /etc/cron.hourly/koha-common]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.cron.monthly /etc/cron.monthly/koha-common]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.cron.d /etc/cron.d/koha-common]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.cron.daily /etc/cron.daily/koha-common]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.logrotate /etc/logrotate.d/koha-common]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.default /etc/default/koha-common]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.init /etc/init.d/koha-common]...
koha-1  | Running [sudo cp /kohadevbox/koha/debian/koha-common.bash-completion /etc/bash_completion.d/koha-common]...
koha-1  | Running [sudo xsltproc --output /usr/share/man/man8/ /usr/share/xml/docbook/stylesheet/docbook-xsl-ns/manpages/docbook.xsl /kohadevbox/koha/debian/docs/*.xml]...
koha-1  | Note: Writing koha-common.8
koha-1  | Note: Writing koha-create-dirs.8
koha-1  | Note: Writing koha-create.8
koha-1  | Note: Writing koha-disable.8
koha-1  | Note: Writing koha-dump-defaults.8
koha-1  | Note: Writing koha-dump.8
koha-1  | Note: Writing koha-elasticsearch.8
koha-1  | Note: Writing koha-email-disable.8
koha-1  | Note: Writing koha-email-enable.8
koha-1  | Note: Writing koha-enable.8
koha-1  | Note: Writing koha-es-indexer.8
koha-1  | Note: Writing koha-foreach.8
koha-1  | Note: Writing koha-indexer.8
koha-1  | Note: Writing koha-list.8
koha-1  | Note: Writing koha-mysql.8
koha-1  | Note: Writing koha-mysqlcheck.8
koha-1  | Warn: AUTHOR sect.: no personblurb|contrib for Mason James         
koha-1  | Note: AUTHOR sect.: see http://www.docbook.org/tdg5/en/html/contr  
koha-1  | Note: AUTHOR sect.: see http://www.docbook.org/tdg5/en/html/perso  
koha-1  | Note: Writing koha-passwd.8
koha-1  | Note: Writing koha-plack.8
koha-1  | Note: Writing koha-rebuild-zebra.8
koha-1  | Note: Writing koha-remove.8
koha-1  | Note: Writing koha-reset-passwd.8
koha-1  | Note: Writing koha-restore.8
koha-1  | Note: Writing koha-run-backups.8
koha-1  | Note: Writing koha-shell.8
koha-1  | Note: Writing koha-sip.8
koha-1  | Note: Writing koha-sitemap.8
koha-1  | Note: Writing koha-translate.8
koha-1  | Note: Writing koha-upgrade-schema.8
koha-1  | Note: Writing koha-upgrade-to-3.4.8
koha-1  | Note: Writing koha-worker.8
koha-1  | Note: Writing koha-z3950-responder.8
koha-1  | Note: Writing koha-zebra.8
koha-1  | Running [sudo rm /usr/share/man/man8/koha-*.8.gz]...
koha-1  | Running [sudo gzip /usr/share/man/man8/koha-*.8]...
koha-1  | Running [sudo perl /kohadevbox/misc4dev/cp_zebra_files.pl --koha_dir=/kohadevbox/koha ]...
koha-1  | Running [cp -r /kohadevbox/koha/etc/zebradb/marc_defs/* /etc/koha/zebradb/marc_defs/]...
koha-1  | Running [PERL5LIB=/kohadevbox/koha:/kohadevbox/koha/lib:/kohadevbox/qa-test-tools perl /kohadevbox/misc4dev/setup_sip.pl --instance=kohadev]...
koha-1  | Running [sudo cp /etc/koha/SIPconfig.xml /etc/koha/sites/kohadev/SIPconfig.xml]...
koha-1  | Running [sudo koha-shell kohadev -p -c 'PERL5LIB=/kohadevbox/koha:/kohadevbox/koha/lib:/kohadevbox/qa-test-tools perl -MKoha::Patrons -le "exit(1) if Koha::Patrons->find({ userid => 'term1' }); Koha::Patron->new({ surname => 'koha_sip', cardnumber => 'koha_sip', userid => 'term1', categorycode => 'S', branchcode => 'CPL', flags => 2, })->store->password(Koha::AuthUtils::hash_password('term1'))->_result->update_or_insert; "']...
koha-1  | Running [sudo koha-sip --stop kohadev]...
koha-1  |  * start-stop-daemon: no matching processes found
koha-1  | Running [sudo koha-sip --enable kohadev]...
koha-1  | Enabling SIP server for kohadev - edit /etc/koha/sites/kohadev/SIPconfig.xml to configure
koha-1  | Running [sudo koha-sip --start kohadev]...
koha-1  | Running [PERL5LIB=/kohadevbox/koha:/kohadevbox/koha/lib:/kohadevbox/qa-test-tools perl /kohadevbox/misc4dev/reset_plack.pl --koha_dir=/kohadevbox/koha --instance=kohadev]...
koha-1  | Running [sudo service apache2 restart]...
koha-1  | [service shim] apache2 restart (no-op in container)
koha-1  | Running [grep -q watch_js /kohadevbox/koha/package.json]...
koha-1  | Running [sudo koha-shell kohadev -c '(cd /kohadevbox/koha ; PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/kohadevbox/bin:/kohadevbox/koha/node_modules/.bin/:/kohadevbox/node_modules/.bin/ yarn build)']...
koha-1  | yarn run v1.22.22
koha-1  | $ yarn css:build && yarn js:build && yarn api:bundle
koha-1  | $ gulp css && gulp css --view opac
koha-1  | [16:47:40] Using gulpfile /kohadevbox/koha/gulpfile.js
koha-1  | [16:47:40] Starting 'css'...
koha-1  | [16:47:40] Finished 'css' after 9.11 ms
koha-1  | WARNING: Invalid deprecation "if-function".
koha-1  | 
koha-1  | WARNING: Invalid deprecation "if-function".
koha-1  | 
koha-1  | WARNING: Invalid deprecation "if-function".
koha-1  | 
koha-1  | (node:1025) [DEP0180] DeprecationWarning: fs.Stats constructor is deprecated.
koha-1  | (Use `node --trace-deprecation ...` to show where the warning was created)
koha-1  | WARNING: Invalid deprecation "if-function".
koha-1  | 
koha-1  | WARNING: Invalid deprecation "if-function".
koha-1  | 
koha-1  | WARNING: Invalid deprecation "if-function".
koha-1  | 
koha-1  | WARNING: Invalid deprecation "if-function".
koha-1  | 
koha-1  | [16:47:46] Using gulpfile /kohadevbox/koha/gulpfile.js
koha-1  | [16:47:46] Starting 'css'...
koha-1  | [16:47:46] Finished 'css' after 6.72 ms
koha-1  | WARNING: Invalid deprecation "if-function".
koha-1  | 
koha-1  | WARNING: Invalid deprecation "if-function".
koha-1  | 
koha-1  | WARNING: Invalid deprecation "if-function".
koha-1  | 
koha-1  | (node:1024) [DEP0180] DeprecationWarning: fs.Stats constructor is deprecated.
koha-1  | (Use `node --trace-deprecation ...` to show where the warning was created)
koha-1  | $ rspack build --mode development
koha-1  | Rspack compiled successfully in 827 ms
koha-1  | 
koha-1  | Rspack compiled successfully in 723 ms
koha-1  | 
koha-1  | Rspack compiled successfully in 708 ms
koha-1  | $ redocly bundle --ext json api/v1/swagger/swagger.yaml --output api/v1/swagger/swagger_bundle.json
koha-1  | bundling api/v1/swagger/swagger.yaml...
koha-1  | 📦 Created a bundle for api/v1/swagger/swagger.yaml at api/v1/swagger/swagger_bundle.json 230ms.
koha-1  | Done in 13.92s.
koha-1  | Running [koha-mysql kohadev -e 'UPDATE systempreferences SET value="Zebra" WHERE variable="SearchEngine"']...
koha-1  | mysql: Deprecated program name. It will be removed in a future release, use '/usr/bin/mariadb' instead
koha-1  | Running [sudo koha-rebuild-zebra -f -v kohadev]...
koha-1  | Zebra configuration information
koha-1  | ================================
koha-1  | Zebra biblio directory      = /var/lib/koha/kohadev/biblios
koha-1  | Zebra authorities directory = /var/lib/koha/kohadev/authorities
koha-1  | Koha directory              = /kohadevbox/koha
koha-1  | Lockfile                    = /var/lock/koha/kohadev/rebuild/rebuild..LCK
koha-1  | BIBLIONUMBER in :     999$c
koha-1  | BIBLIOITEMNUMBER in : 999$d
koha-1  | ================================
koha-1  | Job started: 16:47:54
koha-1  | skipping authorities
koha-1  | ====================
koha-1  | exporting biblio 16:47:54 [00:00:00]
koha-1  | ====================
koha-1  | :8: parser error : PCDATA invalid Char value 31
koha-1  |   <controlfield tag="001">00aD000015937</controlfield>
koha-1  |                             ^
koha-1  | :9: parser error : PCDATA invalid Char value 31
koha-1  |   <controlfield tag="004">00satmrnu0</controlfield>
koha-1  |                             ^
koha-1  | :9: parser error : PCDATA invalid Char value 31
koha-1  |   <controlfield tag="004">00satmrnu0</controlfield>
koha-1  |                                ^
koha-1  | :9: parser error : PCDATA invalid Char value 31
koha-1  |   <controlfield tag="004">00satmrnu0</controlfield>
koha-1  |                                   ^
koha-1  | :9: parser error : PCDATA invalid Char value 31
koha-1  |   <controlfield tag="004">00satmrnu0</controlfield>
koha-1  |                                      ^
koha-1  | :10: parser error : PCDATA invalid Char value 31
koha-1  |   <controlfield tag="008">00ar19881981bdkldan</controlfield>
koha-1  |                             ^
koha-1  | :10: parser error : PCDATA invalid Char value 31
koha-1  |   <controlfield tag="008">00ar19881981bdkldan</controlfield>
koha-1  |                                        ^
koha-1  | :10: parser error : PCDATA invalid Char value 31
koha-1  |   <controlfield tag="008">00ar19881981bdkldan</controlfield>
koha-1  |                                            ^ at /kohadevbox/koha/Koha/Biblio/Metadata.pm line 117.
koha-1  | error retrieving biblio 369 at /kohadevbox/koha/misc/migration_tools/rebuild_zebra.pl line 789.
401....................................................................................................
koha-1  | Records exported: 435 16:49:31 [00:01:37]
koha-1  | ====================
koha-1  | REINDEXING zebra 16:49:31 [00:01:37]
koha-1  | ====================
koha-1  | Can't exec "zebraidx": No such file or directory at /kohadevbox/koha/misc/migration_tools/rebuild_zebra.pl line 903.
koha-1  | Can't exec "zebraidx": No such file or directory at /kohadevbox/koha/misc/migration_tools/rebuild_zebra.pl line 904.
koha-1  | ====================
koha-1  | Indexing complete: 16:49:31 [00:01:37]
koha-1  | ====================
koha-1  | CLEANING
koha-1  | ====================
koha-1  | Zebra configuration information
koha-1  | ================================
koha-1  | Zebra biblio directory      = /var/lib/koha/kohadev/biblios
koha-1  | Zebra authorities directory = /var/lib/koha/kohadev/authorities
koha-1  | Koha directory              = /kohadevbox/koha
koha-1  | Lockfile                    = /var/lock/koha/kohadev/rebuild/rebuild..LCK
koha-1  | BIBLIONUMBER in :     999$c
koha-1  | BIBLIOITEMNUMBER in : 999$d
koha-1  | ================================
koha-1  | Job started: 16:49:32
koha-1  | ====================
koha-1  | exporting authority 16:49:32 [00:00:00]
koha-1  | ====================
1701....................................................................................................
koha-1  | Records exported: 1706 16:49:37 [00:00:05]
koha-1  | ====================
koha-1  | REINDEXING zebra 16:49:37 [00:00:05]
koha-1  | ====================
koha-1  | Can't exec "zebraidx": No such file or directory at /kohadevbox/koha/misc/migration_tools/rebuild_zebra.pl line 903.
koha-1  | Can't exec "zebraidx": No such file or directory at /kohadevbox/koha/misc/migration_tools/rebuild_zebra.pl line 904.
koha-1  | skipping biblios
koha-1  | ====================
koha-1  | Indexing complete: 16:49:37 [00:00:05]
koha-1  | ====================
koha-1  | CLEANING
koha-1  | ====================
koha-1  | [alpine] Removing Debian-specific Apache suexec directives...
koha-1  | [alpine] Fixing permissions for Apache to access Koha directories...
koha-1  | [alpine] Enabling mod_cgi module for Perl CGI script execution...
koha-1  | [alpine] Enabling CGI execution for Perl scripts in /etc/koha/apache-shared-*-git.conf...
koha-1  | [logs] Chowning logs
koha-1  |     [*] Success chowning /var/log/koha/kohadev
koha-1  | [INFO] koha-plack not enabled in this profile; continuing with Apache CGI mode
koha-1  | [INFO] koha-z3950-responder enable skipped; continuing
koha-1  | [rabbitmq] Waiting for STOMP port rabbitmq:61613...
koha-1  | [rabbitmq] STOMP port rabbitmq:61613 is ready
koha-1  | koha-testing-docker has started up and is ready to be enjoyed!

╔══════════════════════════════════════════════════════════╗
║   Stack fully started and ready!                         ║
╠══════════════════════════════════════════════════════════╣
║  Via Traefik (recommended):║
║    OPAC    : http://kohadev.127.0.0.1.nip.io:8000║
║    Staff   : http://kohadev-intra.127.0.0.1.nip.io:8000║
║  Direct (fallback, no DNS needed):║
║    OPAC    : http://localhost:8080║
║    Staff   : http://localhost:8081║
║  Login     : koha / koha║
║  Dashbrd   : http://dashboards.localhost:8000║
║  Traefik   : http://localhost:8083║
║  Catalogue : with demo data║
╚══════════════════════════════════════════════════════════╝
```