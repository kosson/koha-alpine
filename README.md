# Alpine Linux Koha Docker Environment

A modern, lightweight Koha library management system runtime on Alpine Linux 3.24.1 with production-grade SSL/TLS database connectivity.
This setting and arrangements are originated in KTD Koha - https://gitlab.com/koha-community/koha-testing-docker.

This setup enables development and testing contexts. Also, it promotes OpenSearch integration for indexing purposes.
The main reason for developing this alternative is resource based, and production oriented. Its sister repo https://github.com/kosson/koha-alpine still uses Debian/Ubuntu, but the space used for the image is rather big. Also Debian/Ubuntu operating systems are very well endowed with all it needs for development.

The resulting Koha container is using the components it depends on as separate services. These are MariaDB (the database), RabbitMQ (the message queue messenger), Memcached (caching manager). OpenSearch version 3.6 is used for indexing, the cluster being provided as a separate service added to those who are raised all together using the `docker-compose-alpinekoha` orchestrator file.

Skills wise, you need to know how to use a terminal shell, and to use a Linux/GNU operating system. The development of this project was done on Ubuntu, Debian Trixie, and Linux Mint distributions.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Using stack-alpine.sh](#using-stack-alpinesh-script)
3. [SSL Certificate Management](#ssl-certificate-management)
4. [Project Structure](#project-structure)
5. [Environment Configuration](#environment-configuration)
6. [Starting the Project](#starting-the-project)
7. [Dual Image Modes (Development vs Production)](#dual-image-modes-development-vs-production)
8. [Operating the System](#operating-the-system)
9. [Architecture](#architecture)
10. [Troubleshooting](#troubleshooting)
11. [Dockerfile-Alpine Shims (1-Minute Explainer)](#dockerfile-alpine-shims-1-minute-explainer)
12. [OpenSearch Maintenance Tasks](#opensearch-maintenance-tasks)
13. [Reproducible Rebuild and Validation (Clean Cycle)](#reproducible-rebuild-and-validation-clean-cycle)
14. [Development Workflow](#development-workflow)

## Quick Start

### Prerequisites

- Docker Engine 20.10+ with docker-compose support
- Sufficient disk space (1.8GB for base image + database volume)
- At least 16 GB of RAM (OpenSearch cluster is RAM hungry)
- Network connectivity for initial image build
- A writable local clone path for Koha source (modify the `SYNC_REPO` value in env/.env)

### Start From Zero (Layman Path)

Use this path if this is your first run on a machine.

#### Step 1: Choose your mode

You have two valid startup modes:

1. **Koha only (simpler, no OpenSearch):**
  - Use this if you just want OPAC + Staff running first.
  - Set `KOHA_ALPINE_ELASTICSEARCH=no` in `env/.env`.
2. **Koha + OpenSearch (full search stack):**
  - Use this when you also want OpenSearch/Dashboards ready.
  - Set `KOHA_ALPINE_ELASTICSEARCH=yes` in `env/.env`.

#### Step 2: One-time local preparation

Run from repository root:

```bash
cd /path/to/your/koha-alpine
```

Create the networks needed.

```bash
# Required docker networks (safe if they already exist)
docker network create opensearch-36_osearch || true
docker network create knonikl || true
docker network create frontend || true
```

Create the `.env` file that contains all the environment variables needed to begin the project.

```bash
# Create your local env file for Koha usage
cp env/template.env env/.env
```

Create the `.env` file in the OpenSearch-3.6 subfolder that is needed to start OpenSearch cluster. Observe that the `.env` file you've just created by copying the template has in the end the following two lines similar to the:

```ini
OS_COMPLIANCE_SALT=ZLqnAIFnRMj2wTFw
OS_QUERY_MASTERKEY=0217e69bff29bc67dc12c16d84904a85
```

Those will be overwritten soon enough.

```bash
# Create OpenSearch env file for OpenSearch usage
cp OpenSearch-3.6/template.env OpenSearch-3.6/.env
```

Now edit `env/.env` and set at minimum:

1. `SYNC_REPO` -> absolute path to your local `koha/` source folder.
2. `KOHA_DB_ROOT_PASSWORD` -> replace template/default with your own secret.
3. `KOHA_ALPINE_ELASTICSEARCH` -> `no` (simple mode) or `yes` (full mode).

If you selected full mode (`yes`), ensure these credentials match:

1. `env/.env`: `OPENSEARCH_INITIAL_ADMIN_PASSWORD`
2. `OpenSearch-3.6/.env`: `OPENSEARCH_INITIAL_ADMIN_PASSWORD`

Initially it comes with a dummy password that match. Be very careful at this step if you modify in one place.

#### Step 3: OpenSearch first-run bootstrap (only if full mode)

Remember to copy `template.env` to `.env` in the OpenSearch-3.6 subfolder: `cp OpenSearch-3.6/template.env OpenSearch-3.6/.env` prior to the following operations. We move with the pulling of the OpenSearch official image and the creation of the credentials needed to operate the OpenSearch cluster (credentials needed for authorized communication among the nodes).
First, pull the OpenSearch image:

```bash
docker pull opensearchproject/opensearch:3.6.0
```

Then, make sure you are in the OpenSearch-3.6 subdirectory: `cd OpenSearch-3.6`. Here, you need to create the certificates needed for authorization and authentication.

```bash
# Ensure OpenSearch cert set is created correctly
./opensearch_local_certificates_creator.sh
```

If all goes well, start the cluster for the first time to ensure a green light.

```bash
# First-time cluster bring-up rehearsal
./raise-from-ground-up.sh
```

If the cluster is raised and green (message in Terminal: `[raise-from-ground-up] Cluster status=yellow, nodes=5`), bring it down before the next step `docker compose down -v --remove-orphans`. It will be brought back soon enough by another script in the next step. Remember to go up a level to the root directory if the project: `cd ..`.

#### Step 4: Build and start Koha stack

There are two runtime modes. Pick the one that matches your intent before building.

**Mode A — Development (default, source mounted from host)**

Use this when you are actively editing Koha code. The `./koha` directory from your machine is bind-mounted into the container at runtime, so changes are visible immediately without rebuilding.

```bash
# Build the dev image (target: dev-runtime, ~5-10 min first time)
./stack-alpine.sh build --image-mode dev --build-koha

# Prepare MariaDB TLS client cert/key and auto-wire env/.env
./stack-alpine.sh tls-client-cert

# Start the full managed stack in dev mode
./stack-alpine.sh start --image-mode dev
```

`--image-mode dev` is the default, so you may omit it if you are not switching between modes.

**Mode B — Production (Koha source baked into the image at a fixed released version)**

Use this when you want an immutable, version-pinned runtime that does not depend on a local source directory. The Koha source tree is fetched from the community git at build time using a released tag and stored inside the image. This will balloon the image to almost 4.48GB in size.

**Step 1 — choose a Koha release tag**

Koha releases frequently. Use the built-in helper to discover and pin the version you want:

```bash
# Show the latest upstream release tag (read-only, no changes)
./stack-alpine.sh latest-tag

# Write the latest release into env/.env automatically
./stack-alpine.sh latest-tag --apply

# OR pin a specific known-good release
./stack-alpine.sh latest-tag --apply v25.11.06-1
```

This writes `KOHA_GIT_TAG` to `env/.env`, which is the single value that flows through the entire build pipeline. The leading `v` is added automatically if you omit it.

**Step 2 — build the prod image** (~10-15 min, clones Koha source at build time)

```bash
./stack-alpine.sh build --image-mode prod --build-koha
```

**Step 3 — prepare MariaDB TLS client certificates**

```bash
./stack-alpine.sh tls-client-cert
```

**Step 4 — start the full stack**

```bash
./stack-alpine.sh start --image-mode prod
```

> **Not sure which mode to pick?** Start with Mode A. It is faster to set up, easier to troubleshoot, and is what most developers use day-to-day. Switch to Mode B when you need a fixed, deployable artifact.

#### Step 5: Wait, verify, then login

```bash
# Wait ~120-140 seconds, then check startup marker in logs
docker compose -f docker-compose-alpinekoha.yml logs --tail=80 koha

# Optional CGI check
docker compose -f docker-compose-alpinekoha.yml exec -T koha httpd -M | grep cgi_module

# Basic endpoint checks
curl -I http://localhost:8080
curl -I http://localhost:8081
```

Expected result:

1. Koha log includes: `[run.sh] Startup complete - OPAC on :8080, staff on :8081` followed by `[watchdog] Service watchdog started (instance=kohadev, plack=yes, worker=yes, interval=30s)`.
2. OPAC (`8080`) and Staff (`8081`) respond (typically 200/302 depending on route).

On the very first boot against a given `koha/` checkout, expect an extra ~30-90 seconds
before that message: `run.sh` detects that the compiled OPAC/staff stylesheet
(`koha-tmpl/opac-tmpl/bootstrap/css/opac.css`) is missing and runs
`yarn install && yarn build` automatically (gulp for CSS, rspack for JS) before
continuing. Subsequent restarts skip this once the file exists. Set
`KOHA_ALPINE_SKIP_YARN_INSTALL=yes` in `env/.env` to skip it entirely (pages will
then render with no CSS/JS until you run `yarn build` yourself inside the
container).

Login defaults come from `env/.env`:

1. Username: `KOHA_USER`
2. Password: `KOHA_PASS`

By default is user `koha` and password `koha`.

#### If you need to fully restart from zero later

Sometimes you just need to start all over again. Here is how.

```bash
# Destructive: removes containers + named volumes managed by stack
./stack-alpine.sh reset

# Then run the layman path again from Step 2
```

This removes database and OpenSearch persisted data for this workspace setup.

The sections below provide deeper OpenSearch operational details and recovery notes.

#### OpenSearch cluster forming details

First, bring the OpenSearch image with `docker pull opensearchproject/opensearch:3.6.0`.

Second, create the necessary credential files. Run the `opensearch_local_certificates_creator.sh` script. This script will take into consideration the existing environment variables, and based on that will generate the necessary certificate files in the `./OpenSearch-3.6/assets/ssl` subfolder. At the moment of first run, the `.OpenSearch-3.6/assets/opensearch/data` subfolder will be created containing the corresponding data for each node of the cluster.

The following details are useful in case you run into trouble with the OpenSearch cluster.
If you modified the password used for OpenSearch, this meaning the values of `ELASTIC_OPTION` and as a consequence also the value of `OPENSEARCH_INITIAL_ADMIN_PASSWORD` in the `env/.env` file, make sure you modify the value of `OPENSEARCH_INITIAL_ADMIN_PASSWORD` in the `.env` file in the OpenSearch-3.6 subfolder as well. Remember that if you have modified the password for the aforementioned environment variables you MUST run the `opensearch_local_certificates_creator.sh` script. Otherwise, the cluster is not forming. Node `os01` errors out. Create also the `OpenSearch-3.6/assets/ssl` subfolder if not found.

**Warning:** do not create or replace files under `OpenSearch-3.6/assets/ssl/` manually. OpenSearch expects `root-ca.pem`, `admin.pem`, and the per-node PEM files to be regular files, not directories. If a cert path is missing when Docker Compose starts, Docker can create a directory at that path and OpenSearch will abort with an error like `.../root-ca.pem - is a directory`. Always regenerate the certificate set with `opensearch_local_certificates_creator.sh` instead of creating placeholders by hand.

Requirements for a viable password for OpenSearch:

- minimum length 10
- uppercase + lowercase + digit + special character

**OpenSearch password:** `OPENSEARCH_INITIAL_ADMIN_PASSWORD` in `env/.env` file and `OPENSEARCH_INITIAL_ADMIN_PASSWORD` in the `OpenSearch-3.6/.env` file must match. Both files ship with the same default value: `test@Cici24#ANA`. Verify also the `./OpenSearch-3.6/assets/dashboards/opensearch_dashboards.yml` file to have the same password: `opensearch.password: "test@Cici24#ANA"`. Otherwise you will get into a credential drift, and your OpenSearch cluster will not form.

The OpenSearch-3.6 folder provides you with two important scripts that help raising the cluster:

- `raise-from-ground-up.sh`, and
- `restart-to-clear-cluster.sh`.

The first should be run prior to anything else, and the second when you made some mistake and you lost track. Remember that this is very useful to make a wet rehearsal for the OpenSearch cluster. If all is okay, bring it down with `docker compose down -v --remove-orphans`. The real creation of the cluster is on `./stack-alpine.sh start` script job.

#### OpenSearch credential drift note (important)

If `OPENSEARCH_INITIAL_ADMIN_PASSWORD` drifts between `env/.env` and `OpenSearch-3.6/.env`, OpenSearch can stay green while Basic Auth starts failing with HTTP 401. The `os01` health check is certificate-based, so it will not detect this on its own.

Symptoms are usually:

- `tests/test_opensearch_os01_auth_integration.sh` fails.
- `curl -u admin:<password>` returns 401.
- Koha or Dashboards show auth errors even though `os01` is running.

`./stack-alpine.sh start` now self-heals this case before Koha starts: it syncs Koha's `ELASTIC_OPTIONS` with `OpenSearch-3.6/.env`, probes the cluster, and reruns `initial_api_calls.sh` if OpenSearch still answers 401.

For a fully clean recovery, reset and rebuild OpenSearch from zero:

```bash
docker pull opensearchproject/opensearch:3.6.0
cd OpenSearch-3.6
./raise-from-ground-up.sh
```

If you need an in-place live credential resync on an already running cluster, use:

```bash
set -a && source .env && set +a && bash initial_api_calls.sh
docker compose up -d --force-recreate os01
```

#### Reindexing Koha records into OpenSearch

If Koha shows `Records are not indexed in Elasticsearch` in the staff interface, run the rebuild from inside the Koha application container, not from the OpenSearch container:

```bash
docker exec -it <koha-container-name> bash
koha-elasticsearch --rebuild -d -b -a <instance-name>
```

Use your actual Koha container name and instance name. For this repository the instance is commonly `kohadev` for example `docker exec -it koha-alpine-koha-1 bash` followed by `koha-elasticsearch --rebuild -d -b -a kohadev`.

Keep these values aligned every time you rotate credentials:

- `env/.env` -> `OPENSEARCH_INITIAL_ADMIN_PASSWORD`
- `OpenSearch-3.6/.env` -> `OPENSEARCH_INITIAL_ADMIN_PASSWORD`
- `env/.env` -> `ELASTIC_OPTIONS` (`<userinfo>admin:...`)
- `OpenSearch-3.6/assets/dashboards/opensearch_dashboards.yml` -> `opensearch.password`

After changing credentials, apply and refresh:

```bash
cd OpenSearch-3.6
set -a && source .env && set +a && bash initial_api_calls.sh
docker compose up -d --force-recreate os01
docker compose ps os01 dashboards
```

Recommended check after you start all the services:

```bash
bash tests/test_opensearch_os01_auth_integration.sh
```

As a rule of thumb it is wise to start the OpenSearch cluster prior to anything. If it forms well, continue with the next step.

### Start the Stack in 5 Steps

```bash
cd /path/to/your/koha-alpine

# 1. Copy environment template (if first time)
cp env/template.env env/.env

# 2. Edit env/.env (minimum required before first start)
# - set SYNC_REPO to your local koha path
# - set KOHA_DB_ROOT_PASSWORD to a non-default secret
# - optionally set KOHA_DB_PASSWORD, KOHA_USER, KOHA_PASS

# 3. Build the Alpine image (first run or after Dockerfile changes)
docker compose -f docker-compose-alpinekoha.yml build

# 4. Prepare DB TLS client materials (no Koha source changes required)
./stack-alpine.sh tls-client-cert

# 5. Start via stack manager (recommended)
./stack-alpine.sh start
```

Important:

1. Do not keep `KOHA_DB_ROOT_PASSWORD=change_me_before_first_start`.
2. The `.env` file contains secrets; keep it local and never commit it.

### Verify Bootstrap Success (Required Before Endpoint Tests)

```bash
# Wait 120-140 seconds for full bootstrap, then check:
docker compose -f docker-compose-alpinekoha.yml logs --tail=80 koha
# Should see: "[run.sh] Startup complete - OPAC on :8080, staff on :8081"
# followed by: "[watchdog] Service watchdog started (instance=kohadev, plack=yes, worker=yes, ...)"

# Confirm Apache has mod_cgi AND mod_proxy_http loaded (Plack is proxied through
# Apache via a unix socket; without apache2-proxy installed, mod_proxy_http is
# silently absent and every proxied request 503s)
docker compose -f docker-compose-alpinekoha.yml exec -T koha httpd -M | grep -E 'cgi_module|proxy_http_module'

# Confirm koha-plack (Starman) is actually running
docker compose -f docker-compose-alpinekoha.yml exec -T koha sh -c 'PATH=/usr/sbin:$PATH koha-plack --status kohadev'

# Only now run the endpoint suite
./test-plack-stack.sh --no-recreate
```

If you run the test suite too early, you can get false negatives (for example
`mod_proxy_http` or `koha-plack` not up yet) while bootstrap is still in
progress. `test-plack-stack.sh` is the current, maintained harness (22 checks:
Apache config/modules, Plack process + unix-socket health, HTTP endpoints
including CSS/jQuery asset-presence, watchdog crash-recovery, restart
idempotency). `test-endpoints.sh` predates the Apache+Plack-proxy architecture
and assumes pure `mod_cgi`-only serving; treat it as legacy/secondary.

### First Login

By default, staff login uses values from `env/.env`:

1. Username: `KOHA_USER` (commonly `koha`)
2. Password: `KOHA_PASS`

Use the staff interface at [http://localhost:8081](http://localhost:8081).

### Access the Application

| Service | URL | Port | Notes |
|---------|-----|------|-------|
| **OPAC** (patron interface) | http://localhost:8080 | 8080 | Public library catalog |
| **Staff/Intranet** (admin) | http://localhost:8081 | 8081 | Library staff interface |
| **Database** | localhost:3306 | 3306 | Internal only (SSL required) |
| **RabbitMQ Management** | http://localhost:15672 | 15672 | STOMP: localhost:61613 |
| **Memcached** | localhost:11211 | 11211 | Internal caching |

### Stop the Stack

```bash
docker compose -f docker-compose-alpinekoha.yml down

# To keep database between restarts, use: (data in koha-db-data volume persists)
docker compose -f docker-compose-alpinekoha.yml stop
```

### Rebuilding After Code Changes (read this before you file a "nothing works" bug)

`files-alpine/run.sh`, `files-alpine/lib/`, `files-alpine/scripts/`, and
`files-alpine/templates/` are bind-mounted into the container (see the `koha`
service `volumes:` in `docker-compose-alpinekoha.yml`), so editing those files
on the host and running `docker compose up -d` (or `--force-recreate`) is
enough to pick them up — no rebuild needed.

**Everything else is baked into the image at build time** and is invisible to
`up -d`: `Dockerfile-Alpine` itself (apk packages, CPAN modules), and anything
`run.sh` installs from those bind-mounted files into fixed system paths at
boot (e.g. `/usr/sbin/koha-plack`). If you change `Dockerfile-Alpine`, or if
behavior doesn't match what you just edited even after a `--force-recreate`,
rebuild first:

```bash
docker compose -f docker-compose-alpinekoha.yml build koha
docker compose -f docker-compose-alpinekoha.yml up -d --force-recreate koha
```

`docker compose up -d` alone silently reuses whatever image was last built —
it will keep running old, stale, baked-in behavior indefinitely and give no
warning that your `Dockerfile-Alpine` changes never took effect. A quick way
to confirm you're not hitting this: compare the entrypoint script's checksum
inside the container against the host file --
`docker compose exec koha md5sum /usr/local/bin/run.sh` should match
`md5sum files-alpine/run.sh` on the host (this exact check is the first thing
`test-plack-stack.sh` verifies).

## Using stack-alpine.sh script

`stack-alpine.sh` is the single entry point for building, starting, stopping, and
maintaining the entire Alpine Koha stack. All commands must be run from the `koha-alpine`
root directory.

```bash
cd /path/to/your/koha-alpine
./stack-alpine.sh --help          # full option reference
```

For the complete command reference, flag descriptions, and worked examples see
[HELP-STACK-ALPINE-SCRIPT.md](HELP-STACK-ALPINE-SCRIPT.md).

### Most common operations

```bash
./stack-alpine.sh start                           # fresh DB + demo data (dev mode, default)
./stack-alpine.sh start --no-fresh-db             # resume with existing database
./stack-alpine.sh start --no-demo-data            # fresh DB, empty catalogue
./stack-alpine.sh restart                         # reset DB + recreate Koha only (OS stays up)
./stack-alpine.sh stop                            # stop the whole stack
./stack-alpine.sh status                          # show container health summary
./stack-alpine.sh logs                            # tail Koha startup logs
./stack-alpine.sh reset                           # ⚠ destructive: removes containers + volumes
```

### Building images

```bash
# Development image (fast, ~5 min; Koha source bind-mounted from host)
./stack-alpine.sh build --image-mode dev --build-koha

# Production image (slow, ~10-15 min; Koha source baked in at a released tag)
./stack-alpine.sh latest-tag --apply              # set/update the release tag in env/.env
./stack-alpine.sh build --image-mode prod --build-koha
```

### Selecting a Koha release for the production image

```bash
./stack-alpine.sh latest-tag                      # show latest upstream tag (read-only)
./stack-alpine.sh latest-tag --apply              # write latest tag to env/.env
./stack-alpine.sh latest-tag --apply v25.11.06-1  # pin a specific release
./stack-alpine.sh latest-tag --apply 25.11.06-1   # leading 'v' is added automatically
```

`KOHA_GIT_TAG` in `env/.env` is the single source of truth; both the image build and the
compose project name derive from it automatically.

### TLS client certificates

```bash
./stack-alpine.sh tls-client-cert                       # generate / reuse
./stack-alpine.sh tls-client-cert --force-client-tls-regen  # force regeneration
./stack-alpine.sh start --prepare-db-client-tls         # generate then start
```

### Backup and restore

```bash
./stack-alpine.sh backup                                             # saves to ./backups/
./stack-alpine.sh backup --output /tmp/koha-backup.tar.gz
./stack-alpine.sh restore backups/koha-backup-20260804T120000Z.tar.gz
```

## SSL Certificate Management

### Overview

The Koha Alpine container uses **SSL/TLS encryption for all MariaDB database connections**. The certificates are pre-generated and included in the image at `/etc/mysql/ssl/`.

**Certificate Chain:**

- **CA Certificate** (`ca-cert.pem`, `ca-key.pem`): Self-signed Certificate Authority
- **Server Certificate** (`server-cert.pem`, `server-key.pem`): Database server certificate
- **Client Certificate** (`client-cert.pem`, `client-key.pem`): Koha client certificate (used by Perl/DBI paths)
- **Configuration** (`mariadb-ssl.cnf`): MySQL SSL configuration
- **Extensions** (`server-ext.cnf`): Certificate subject alternative names

You MUST regenerate them to avoid any security issues.

### Recommended helper workflow (stack-managed)

Use the integrated helper in `stack-alpine.sh` to keep TLS client material and `.env` in sync:

```bash
# Generate or reuse client cert/key and update env/.env:
./stack-alpine.sh tls-client-cert

# Force regeneration:
./stack-alpine.sh tls-client-cert --force-client-tls-regen

# Run helper automatically in normal operations:
./stack-alpine.sh start --prepare-db-client-tls
./stack-alpine.sh restart --prepare-db-client-tls
./stack-alpine.sh build --prepare-db-client-tls --build-koha
```

What it does:

1. Validates `files-alpine/mariadb-ssl/ca-cert.pem` and `ca-key.pem`.
2. Generates `client-cert.pem` + `client-key.pem` signed by the local CA.
3. Sets readable permissions required by Apache CGI/Perl DBI in bind-mounted paths.
4. Updates `env/.env` keys:
  - `KOHA_DB_TLS_CLIENT_CERTIFICATE=/etc/mysql/ssl/client-cert.pem`
  - `KOHA_DB_TLS_CLIENT_KEY=/etc/mysql/ssl/client-key.pem`

This avoids Koha source edits while keeping bootstrap and runtime DB connectivity stable.

### Who Creates Certificates and When

| Role | Task | Timing | How |
|------|------|--------|-----|
| **First-time Setup** (DevOps/Developer) | Generate root CA and server certificates | During initial project setup | See "Generating New Certificates" below |
| **Image Builder** | Bake certificates into Alpine image | During Docker image build | `COPY files-alpine/mariadb-ssl /etc/mysql/ssl` in Dockerfile-Alpine |
| **Runtime** | Mount SSL files into MariaDB container | At container startup | Via docker-compose volume mounts |
| **Certificate Renewal** (DevOps) | Replace expired certificates | Every 10 years (default) or on expiration | Generate new certs, rebuild image |

### Certificate Locations

```log
files-alpine/mariadb-ssl/
├── ca-cert.pem              # Root CA public certificate
├── ca-key.pem               # Root CA private key (keep private!)
├── server-cert.pem          # Database server public certificate
├── server-key.pem           # Database server private key (keep private!)
├── client-cert.pem          # Koha DB client certificate (generated by helper)
├── client-key.pem           # Koha DB client key (generated by helper)
├── client-ext.cnf           # Client certificate extensions (generated by helper)
├── server-ext.cnf           # Server certificate extensions (alt names)
├── ca-cert.srl              # CA serial number tracking
└── mariadb-ssl.cnf          # MySQL SSL configuration
```

All files are:

- ✅ Committed to git (self-signed, non-production safe)
- ✅ Baked into Docker image during build
- ✅ Mounted read-only into MariaDB container at `/etc/mysql/ssl`

### Generating New Certificates

**Use case:** Initial setup, certificate renewal, or custom hostname requirements.

**Prerequisites:**

```bash
# Alpine/Linux: ensure openssl is installed
apk add openssl

# Debian/Ubuntu:
sudo apt-get install openssl

# macOS:
brew install openssl
```

**Step 1: Create Certificate Authority (CA)**

```bash
cd files-alpine/mariadb-ssl

# Generate CA private key (RSA 2048-bit)
openssl genrsa -out ca-key.pem 2048

# Generate CA public certificate (valid 10 years)
openssl req -new -x509 -nodes -days 3650 -key ca-key.pem -out ca-cert.pem \
  -subj "/CN=koha-mariadb-ca"

# Initialize serial tracking
echo "01" > ca-cert.srl
```

**Step 2: Create Server Certificate Request**

```bash
# Generate server private key
openssl genrsa -out server-key.pem 2048

# Create server certificate request
openssl req -new \
  -key server-key.pem \
  -out server.csr \
  -subj "/CN=db"
```

**Step 3: Create Server Certificate Extensions**

Create `server-ext.cnf` with your hostnames:

```ini
subjectAltName=DNS:db,DNS:localhost,DNS:your-hostname.local,IP:127.0.0.1,IP:192.168.1.100
extendedKeyUsage=serverAuth
```

**Step 4: Sign Server Certificate with CA**

```bash
openssl x509 -req -in server.csr \
  -CA ca-cert.pem -CAkey ca-key.pem \
  -CAserial ca-cert.srl \
  -out server-cert.pem \
  -days 3650 \
  -extensions v3_ext -extfile server-ext.cnf

# Clean up request file
rm server.csr
```

**Step 5: Verify Certificates**

```bash
# Verify CA certificate
openssl x509 -in ca-cert.pem -text -noout

# Verify server certificate
openssl x509 -in server-cert.pem -text -noout

# Verify server certificate signed by CA
openssl verify -CAfile ca-cert.pem server-cert.pem
```

### Using Certificates in the Container

**The container automatically uses certificates:**

```yaml
# docker-compose-alpinekoha.yml
services:
  db:
    command:
      - "--ssl=ON"  # Enable SSL enforcement
    volumes:
      - ./files-alpine/mariadb-ssl:/etc/mysql/ssl:ro
      - ./files-alpine/mariadb-ssl/mariadb-ssl.cnf:/etc/mysql/conf.d/zz-koha-ssl.cnf:ro
```

**To connect from host with SSL:**

```bash
# Client SSL certificate bundle (if required)
# CA certificate must match the container's ca-cert.pem

mysql --ssl-ca=files-alpine/mariadb-ssl/ca-cert.pem \
      --ssl-mode=REQUIRED \
      -h 127.0.0.1 -u koha_kohadev -p
```

### Certificate Troubleshooting

**Issue: "SSL connection error"**

```bash
# Check if MariaDB started with SSL
docker compose -f docker-compose-alpinekoha.yml logs db | grep -i ssl

# Verify certificates are readable in container
docker compose -f docker-compose-alpinekoha.yml exec db ls -la /etc/mysql/ssl/
```

**Issue: "Certificate verification failed"**

- Ensure CA certificate matches between server and client
- Check certificate expiration: `openssl x509 -enddate -noout -in ca-cert.pem`
- Verify certificate chain: `openssl verify -CAfile ca-cert.pem server-cert.pem`

**Issue: "New certificates not picked up after rebuild"**

```bash
# Full rebuild clears build cache
docker compose -f docker-compose-alpinekoha.yml build --no-cache

# Then restart
docker compose -f docker-compose-alpinekoha.yml up -d
```

## Environment Configuration

### Initial Setup

```bash
# Copy template (first time only)
cp env/template.env env/.env

# Edit with your settings
nano env/.env
```

Mandatory first-start edits:

1. `SYNC_REPO` must point to your local Koha source directory.
2. `KOHA_DB_ROOT_PASSWORD` must be changed from the template placeholder/default.

### Essential Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SYNC_REPO` | `/mnt/beckie2/DEVELOPMENT/koha-alpine/koha` | Path to Koha source code (mounted into container) |
| `KOHA_INSTANCE` | `kohadev` | Library instance name |
| `KOHA_DB_PASSWORD` | `password` | Database password (change in production!) |
| `KOHA_DB_ROOT_PASSWORD` | `password` | Database root password |
| `KOHA_OPAC_PORT` | `8080` | Public catalog port |
| `KOHA_INTRANET_PORT` | `8081` | Staff interface port |
| `KOHA_ALPINE_IMAGE_TAG` | `kosson/koha-alpine:26.11` | Docker image to use |
| `KOHA_ALPINE_SKIP_YARN_INSTALL` | `no` | Skip frontend build (set to `yes` for faster start) |
| `KOHA_ALPINE_ELASTICSEARCH` | `no` | Enable Elasticsearch search (requires additional setup) |
| `APPLY_KOHA_PATCHES` | `no` | Apply `patches/*.patch` to mounted Koha source at startup (opt-in) |
| `LOCAL_USER_ID` | (user's UID) | Linux user ID for file permissions |

### Advanced Variables

```yaml
# Search/indexing
KOHA_ELASTICSEARCH=no              # Set to 'yes' for full-text search
ELASTIC_SERVER=es:9200             # Elasticsearch endpoint
OPENSEARCH_CA_CERT=                # OpenSearch SSL certificate path

# Frontend/build
COVERAGE=                           # Enable code coverage tracking
SKIP_YARN_INSTALL=no               # Install JavaScript dependencies
SKIP_L10N=no                        # Skip localization build
LOAD_DEMO_DATA=yes                 # Load sample library data

# Database
USE_EXISTING_DB=                    # Point to external database
ALPINE_BOOTSTRAP_PROFILE=resume     # resume=fast existing-DB startup, full=force full population/reindex
RUN_DB_POPULATION_ON_EXISTING_DB=   # optional explicit override (yes/no), usually leave empty
APPLY_KOHA_PATCHES=no               # optional startup patch application (default off)
PERL_LWP_SSL_VERIFY_HOSTNAME=1      # SSL verification for Koha

# CPAN modules (advanced)
CPAN=no                             # Install additional CPAN modules
EXTRA_CPAN=                         # Comma-separated module list
EXTRA_APT=                          # Additional Alpine packages
```

## Starting the Project in a full Bootstrap Sequence

The container runs these phases automatically:

1. [templates] Template/htdocs symlinks wired to the bind-mounted koha source
2. [db] Database wait, schema init (fresh DB only), superlibrarian bootstrap
3. [yarn] Frontend asset build (CSS, JavaScript) -- first boot only, skipped once `opac.css` exists
4. [apache] Vhost render + Apache module setup (mod_cgi, mod_proxy_http, mod_rewrite)
5. [plack] koha-plack (Starman, unix socket) + koha-worker start
6. [apache-start] Apache startup (proxies to Plack; mod_cgi fallback for any unproxied path)
7. [services] crond, watchdog (crash-recovery supervision for koha-plack/koha-worker)
8. [bootstrap-complete] HTTP endpoints ready on :8080 (OPAC) and :8081 (Staff)

**Timing:** ~30-140 seconds from `docker compose up` to
`[run.sh] Startup complete` (longer on the very first boot against a given
`koha/` checkout, since step 3 has to actually run `yarn build`).

### Patch Files vs Runtime Errors

`patches/*.patch` are optional source patches, controlled by `APPLY_KOHA_PATCHES`.

Rarely there is endpoint 500 errors occurs after startup. The observed failures come from database TLS/SSL negotiation during Koha DB connections, not from the two local code patches. Use this quick diagnostic to confirm:

```bash
docker compose -f docker-compose-alpinekoha.yml exec -T koha \
  tail -n 80 /var/log/koha/kohadev/opac-error.log | grep -E "DBI connect|TLS/SSL"
```

### Starting with Custom Configuration

```bash
# Start with custom environment
SYNC_REPO=/path/to/custom/koha \
KOHA_INSTANCE=mylib \
docker compose -f docker-compose-alpinekoha.yml up -d

# Or use .env file - modify SYNC_REPO with your path
cat > env/.env << EOF
SYNC_REPO=/path/to/custom/koha
KOHA_INSTANCE=mylib
KOHA_DB_PASSWORD=mysecretpassword
KOHA_ALPINE_SKIP_YARN_INSTALL=no
EOF

docker compose -f docker-compose-alpinekoha.yml up -d
```

### When Rebuild Is Required

Some files are baked into the image and need a rebuild before changes apply.

1. If you edit `files-alpine/run.sh`, rebuild and recreate the Koha service.
2. If you edit only mounted source under `SYNC_REPO`, no image rebuild is needed.

```bash
docker compose -f docker-compose-alpinekoha.yml build koha
docker compose -f docker-compose-alpinekoha.yml up -d --force-recreate koha
```

### Building from Source

```bash
# Full rebuild (clears build cache)
docker compose -f docker-compose-alpinekoha.yml build --no-cache

# Incremental build (uses cache layers)
docker compose -f docker-compose-alpinekoha.yml build

# Build with additional packages
EXTRA_APK="git htop curl" docker compose build
```

### Monitoring the Bootstrap

```bash
# Real-time logs
docker compose -f docker-compose-alpinekoha.yml logs -f koha

# Last 50 lines
docker compose -f docker-compose-alpinekoha.yml logs --tail=50 koha

# Filter specific phase
docker compose -f docker-compose-alpinekoha.yml logs koha | grep "\[alpine\]"
```

## Dual Image Modes (Development vs Production)

This project now supports two explicit image/run contexts from the same codebase.

### Mode comparison

| Mode | Build target | Source layout | Compose files used | Typical use |
|------|--------------|---------------|--------------------|-------------|
| Development | `dev-runtime` | Host source is bind-mounted (`SYNC_REPO` -> `/kohadevbox/koha`); `VOLUME` declared so compose bind-mount takes precedence | `docker-compose-alpinekoha.yml` | Day-to-day coding, patching, fast iteration |
| Production | `prod-runtime` | Koha source baked into image layers at a fixed ref; no `VOLUME` so the baked tree is visible at runtime | `docker-compose-alpinekoha.yml` + `docker-compose.prod.yml` | Immutable versioned runtime and release deployment |

Important behavior differences:

1. Development mode requires a valid `SYNC_REPO` path.
2. Production mode does not mount `SYNC_REPO`; the Koha tree is built into the image.
3. Production mode uses a version-derived compose project name (`koha-prod-<version-slug>`), which helps keep container names tied to Koha version context.

### Build and start in Development context

Use this when actively editing Koha source.

```bash
# Build Koha image in development mode (default target: dev-runtime)
./stack-alpine.sh build --image-mode dev --build-koha

# Start full stack in development mode
./stack-alpine.sh start --image-mode dev
```

Notes:

1. `--image-mode dev` is optional because dev is the default.
2. Source changes under `SYNC_REPO` are visible immediately in container.

### Build and start in Production context (fixed Koha version)

Use this for immutable, version-pinned runtime builds.

#### Step 1 — select the Koha release you want to bake in

`KOHA_GIT_TAG` in `env/.env` is the **single source of truth** for which Koha version is
baked into the prod image. Set it with the `latest-tag` helper before every prod build.

```bash
# See what the current upstream latest release is (no changes to env/.env)
./stack-alpine.sh latest-tag

# Accept the latest release — writes KOHA_GIT_TAG=<latest> to env/.env
./stack-alpine.sh latest-tag --apply

# OR pin a specific past release (e.g. last known-stable 25.11 maintenance release)
./stack-alpine.sh latest-tag --apply v25.11.06-1
# The leading 'v' is optional: --apply 25.11.06-1 works the same way
```

Available tags can be listed with:
```bash
git ls-remote --tags https://git.koha-community.org/Koha-community/Koha.git \
  | grep 'refs/tags/v2' | grep -v '\^{}' \
  | awk '{print $2}' | sed 's|refs/tags/||' \
  | sort -t. -k1,1V -k2,2n -k3,3n
```

> **Note on `sort -V`**: the `-REVISION` suffix in tags like `v25.11.06-1` confuses `sort -V`.
> Use `sort -t. -k1,1V -k2,2n -k3,3n` (splits on `.` and sorts each numeric field) for
> correct ordering. The `latest-tag` command does this for you automatically.

#### Step 2 — build the image

```bash
# Build the prod image (~10-15 min; clones Koha at the tag set in env/.env)
./stack-alpine.sh build --image-mode prod --build-koha
```

You can also override the tag on the fly without editing `env/.env`:

```bash
./stack-alpine.sh build \
  --image-mode prod \
  --koha-version 25.11.06-1 \
  --koha-ref v25.11.06-1 \
  --build-koha
```

`--koha-version` sets the release label (image tag, compose project name).
`--koha-ref` overrides `KOHA_GIT_TAG` from `env/.env` for this one build.

#### Step 3 — start the stack

```bash
# Uses KOHA_GIT_TAG from env/.env (set in step 1)
./stack-alpine.sh start --image-mode prod

# OR pass the version explicitly (must match what was built)
./stack-alpine.sh start \
  --image-mode prod \
  --koha-version 25.11.06-1 \
  --koha-ref v25.11.06-1
```

> **Pre-release / experimental builds only:** if no stable tag exists yet (e.g. 26.11 before
> November 2026), pass `--koha-ref main`. Do **not** use `main` for production deployments.
>
> ```bash
> ./stack-alpine.sh latest-tag --apply main
> ./stack-alpine.sh build --image-mode prod --build-koha
> ```

### Optional direct Docker Compose usage (without stack script)

If you need manual compose control for production mode:

```bash
# Preferred: set env/.env first, then let compose read it
./stack-alpine.sh latest-tag --apply v25.11.06-1
docker compose \
  -f docker-compose-alpinekoha.yml \
  -f docker-compose.prod.yml \
  --env-file env/.env \
  up -d --build

# One-shot inline override (does not touch env/.env):
KOHA_RELEASE_VERSION=25.11.06-1 \
KOHA_RELEASE_REF=v25.11.06-1 \
KOHA_ALPINE_PROD_IMAGE_TAG=kosson/koha-alpine-prod:25.11.06-1 \
docker compose \
  -f docker-compose-alpinekoha.yml \
  -f docker-compose.prod.yml \
  --env-file env/.env \
  up -d --build
```

> `KOHA_GIT_REF` in the Dockerfile has **no default**. A prod build with neither
> `KOHA_GIT_TAG` in `env/.env` nor `KOHA_RELEASE_REF` passed inline will fail fast with a
> clear error message pointing to `./stack-alpine.sh latest-tag --apply`.

### Quick operational recommendations

1. Keep development and production runs in separate compose projects/hosts.
2. Before every prod build, run `./stack-alpine.sh latest-tag` to see current releases.
3. Use `./stack-alpine.sh latest-tag --apply [<tag>]` to set the version; it is the single
   source of truth that flows to both the image build and the compose project name.
4. Validate endpoints after startup in both modes:
   - `http://localhost:8080` (OPAC)
   - `http://localhost:8081` (Staff)


## Operating the System

### Daily Operations

#### Check System Health

```bash
# All services status
docker compose -f docker-compose-alpinekoha.yml ps

# Service logs
docker compose -f docker-compose-alpinekoha.yml logs db        # Database
docker compose -f docker-compose-alpinekoha.yml logs memcached  # Cache
docker compose -f docker-compose-alpinekoha.yml logs rabbitmq   # Message queue

# HTTP response times
curl -w "Time: %{time_total}s\n" http://localhost:8080/
```

#### Database Management

```bash
# Connect to database (inside container)
docker compose -f docker-compose-alpinekoha.yml exec db mariadb -u root -p

# Backup database
docker compose -f docker-compose-alpinekoha.yml exec db \
  mysqldump -u root -p koha_kohadev > backup-$(date +%s).sql

# Access using SSL from host
mysql --ssl-ca=files-alpine/mariadb-ssl/ca-cert.pem \
      --ssl-mode=REQUIRED \
      -h 127.0.0.1 -u koha_kohadev -p koha_kohadev
```

#### View Application Logs

```bash
# Koha application logs (inside container)
docker compose -f docker-compose-alpinekoha.yml exec koha \
  tail -f /var/log/koha/kohadev/intranet-access.log

# Apache error logs
docker compose -f docker-compose-alpinekoha.yml exec koha \
  tail -f /var/log/apache2/error.log

# Perl compilation errors
docker compose -f docker-compose-alpinekoha.yml logs koha | grep -i "can't locate"
```

### Maintenance Tasks

#### Rebuild Search Indexes

```bash
# Inside container (if Elasticsearch enabled)
docker compose -f docker-compose-alpinekoha.yml exec koha \
  koha-rebuild-zebra -f kohadev

# Note: Currently returns warnings due to disabled Elasticsearch
# This is non-critical and does not affect HTTP operation
```

#### OpenSearch Maintenance Tasks

```bash
# 1) Verify OpenSearch node health (os01)
docker compose -f OpenSearch-3.6/docker-compose.yml exec -T os01 \
  curl -ks -u admin:"$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
  https://localhost:9200/_cluster/health?pretty

# 2) List indices and status
docker compose -f OpenSearch-3.6/docker-compose.yml exec -T os01 \
  curl -ks -u admin:"$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
  'https://localhost:9200/_cat/indices?v&s=health,index'

# 3) Restart OpenSearch nodes (cluster maintained outside Alpine stack)
docker compose -f OpenSearch-3.6/docker-compose.yml restart os01 os02 os03 os04 os05

# 4) Rebuild Koha search index after OpenSearch maintenance (if enabled)
docker compose -f docker-compose-alpinekoha.yml exec koha \
  koha-shell kohadev -p -c 'perl /kohadevbox/koha/misc/search_tools/rebuild_elasticsearch.pl'
```

Notes:

1. Use OpenSearch checks only when `KOHA_ELASTICSEARCH=yes` and the `OpenSearch-3.6` cluster is running.
2. Keep Alpine stack (`docker-compose-alpinekoha.yml`) and OpenSearch stack (`OpenSearch-3.6/docker-compose.yml`) lifecycle commands separate.

#### Reproducible Rebuild and Validation (Clean Cycle)

Use this sequence to reproduce a clean Alpine image rebuild and full verification on another machine:

```bash
cd /path/to/your/koha-alpine

# 1) Stop Alpine services
docker compose -f docker-compose-alpinekoha.yml down --remove-orphans

# 2) Remove Alpine Koha image (if already present)
docker image rm -f kosson/koha-alpine:26.11 || true

# 3) Rebuild from Dockerfile-Alpine without cache
docker compose -f docker-compose-alpinekoha.yml build --no-cache koha

# 4) Start Alpine services
docker compose -f docker-compose-alpinekoha.yml up -d

# 5) Run aggregate suite
bash tests/run_all_tests.sh

# 6) Run deterministic integration suite
KOHA_ELASTICSEARCH=no APPLY_KOHA_PATCHES=no bash tests/run_integration_deterministic.sh
```

#### Clear Caches

```bash
# Memcached (automatic restart clears)
docker compose -f docker-compose-alpinekoha.yml restart memcached

# Application caches (inside container)
docker compose -f docker-compose-alpinekoha.yml exec koha \
  rm -rf /var/cache/koha/kohadev/*
```

#### Update Koha Code

```bash
# With live code mounting (via SYNC_REPO)
# Simply edit files in: /mnt/beckie2/DEVELOPMENT/koha-alpine/koha/

# Changes are visible immediately (development mode)
# For production, rebuild image to bake in changes

docker compose -f docker-compose-alpinekoha.yml build
```

#### Restart Services

```bash
# Restart single service
docker compose -f docker-compose-alpinekoha.yml restart koha

# Restart all services
docker compose -f docker-compose-alpinekoha.yml restart

# Full teardown and restart
docker compose -f docker-compose-alpinekoha.yml down
docker compose -f docker-compose-alpinekoha.yml up -d
```

### Managing Users and Permissions

```bash
# Create library user (inside container)
docker compose -f docker-compose-alpinekoha.yml exec koha \
  koha-create-user --email=librarian@example.com --patron-type=staff

# Reset admin password
docker compose -f docker-compose-alpinekoha.yml exec koha \
  sudo -u kohadev perl -I/kohadevbox/koha/lib \
  -MKoha::Script::SetPassword \
  -e "Koha::Script::SetPassword->new( { koha_instance => 'kohadev', password => 'newpassword' } )"
```

## Architecture

### Container Stack

```log
┌─────────────────────────────────────────────────────────────┐
│  Docker Host (Linux)                                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Koha Container (Alpine 3.24.1)                       │   │
│  ├──────────────────────────────────────────────────────┤   │
│  │                                                      │   │
│  │  ┌─────────────────┐  ┌───────────────────────────┐  │   │
│  │  │ Apache2         │  │ Perl/Koha Application     │  │   │
│  │  │ :8080 (OPAC)    │  │ - run.sh entrypoint       │  │   │
│  │  │ :8081 (Staff)   │  │ - koha-create bootstrap   │  │   │
│  │  │                 │  │ - 38+ CPAN modules        │  │   │
│  │  │ mod_rewrite ✓   │  │ - Yarn/Node.js assets     │  │   │
│  │  │ mod_cgi ✓       │  │ - /kohadevbox/koha (mount)│  │   │
│  │  │ mod_proxy_http ✓│  │                           │  │   │
│  │  └────────┬────────┘  └───────────────────────────┘  │   │
│  │           │ proxied via unix socket                  │   │
│  │  ┌────────▼────────┐                                 │   │
│  │  │ koha-plack       │ Starman + plack.psgi           │   │
│  │  │ (Plack::App::CGIBin, CGI fallback via mod_cgi      │   │
│  │  │  for any path not yet proxied)                     │   │
│  │  └─────────────────┘                                 │   │
│  │                                                      │   │
│  │  /etc/mysql/ssl/              (SSL certificates)     │   │
│  │  - ca-cert.pem, ca-key.pem                           │   │
│  │  - server-cert.pem, server-key.pem                   │   │
│  │  - mariadb-ssl.cnf (config)                          │   │
│  │                                                      │   │
│  └──────────────────────────────────────────────────────┘   │
│         │               │               │                   │
│         └───────┬───────┴───────┬───────┘                   │
│                 │               │                           │
│  ┌──────────────▼──┐  ┌─────────▼─────────┐  ┌────────────┐ │
│  │ MariaDB 10.11   │  │ RabbitMQ 3        │  │ Memcached  │ │
│  │ :3306 (SSL ✓)   │  │ :61613 (STOMP)    │  │ :11211     │ │
│  │                 │  │ :15672 (mgmt)     │  │            │ │
│  │ koha_kohadev    │  │                   │  │ Cache      │ │
│  │ koha_kohadev_*  │  │ koha_kohadev queue│  │ Sessions   │ │
│  │                 │  │                   │  │            │ │
│  └─────────────────┘  └───────────────────┘  └────────────┘ │
│         │                       │                    │      │
│         └───────────────────────┼────────────────────┘      │
│                                 │                           │
└─────────────────────────────────┼───────────────────────────┘
                                  │ Network (bridge: kohanet)
                            Docker compose network
```

### Build Stages (Dockerfile-Alpine)

| Stage | Purpose | Packages | Modules |
|-------|---------|----------|---------|
| Base | Alpine 3.24.1 runtime | perl, apache2, nodejs, openssl | - |
| Build | Compilation tools | gcc, perl-dev, build-base | CPAN compilation |
| Perl | CPAN modules | 38+ modules | Text::CSV_XS, Email::*, XML::*, DBIx::*, MARC::*, JSON::* |
| Apache | Web server | apache2, apache2-utils, apache2-proxy, mod_rewrite, mod_cgi, mod_proxy_http | CGI + Plack-proxy interface |
| Node.js | Frontend | nodejs, npm, yarn | asset build pipeline |
| `koha-base` | Shared final image (no VOLUME) | All above | Complete Koha stack, run.sh, templates, misc4dev |
| `dev-runtime` | Dev image (thin wrapper) | inherits `koha-base` | Adds `VOLUME /kohadevbox/koha` for source bind-mount |
| `prod-runtime` | Prod image | inherits `koha-base` | Bakes Koha source via `git fetch`; no VOLUME so files persist at runtime |

### SSL/TLS Flow

```log
Client Request
    ↓
[HTTP :8080 (OPAC) or :8081 (Staff)]
    ↓
Apache2 (CGI dispatcher)
    ↓
Koha Perl Application
    ↓
[SSL/TLS :3306]
    ↓
MariaDB Database
    ├─ CA verified: ca-cert.pem ✓
    ├─ Server verified: server-cert.pem (signed by CA) ✓
    └─ Connection encrypted: server-key.pem ✓
```

## Troubleshooting

### Bootstrap Issues

#### "Compilation failed" or "Can't locate Module"

**Cause:** Missing Perl module
**Solution:**

```bash
# Check image logs
docker compose -f docker-compose-alpinekoha.yml logs koha | grep "Can't locate"

# Add missing module to Dockerfile-Alpine:
# Option A: Alpine package (fastest)
apk search perl-MODULE*

# Option B: CPAN (if no Alpine package)
# Add to Dockerfile-Alpine: RUN cpanm --notest ModuleName

# Rebuild
docker compose -f docker-compose-alpinekoha.yml build --no-cache
docker compose -f docker-compose-alpinekoha.yml up -d
```

#### "Port already in use"

**Cause:** Service running on 8080/8081
**Solution:**

```bash
# Find process
lsof -i :8080
lsof -i :8081

# Use different ports
KOHA_OPAC_PORT=9080 KOHA_INTRANET_PORT=9081 \
  docker compose -f docker-compose-alpinekoha.yml up -d
```

#### "Database connection failed"

**Cause:** MariaDB SSL certificate mismatch or not ready
**Solution:**

```bash
# Check MariaDB status
docker compose -f docker-compose-alpinekoha.yml logs db | grep -i error

# Verify SSL files present
docker compose -f docker-compose-alpinekoha.yml exec db ls -la /etc/mysql/ssl/

# Rebuild with fresh certificates
docker compose -f docker-compose-alpinekoha.yml down -v
docker compose -f docker-compose-alpinekoha.yml build --no-cache
docker compose -f docker-compose-alpinekoha.yml up -d
```

#### "503 Service Unavailable" on OPAC/Staff (Plack proxy not reachable)

Symptom: Apache responds (it's up), but every page returns `503`.

Two independent, easy-to-miss causes, in order of likelihood:

1. **`mod_proxy_http` isn't loaded.** Alpine's `apache2` apk package ships
   *no* `mod_proxy` at all -- it's the separate `apache2-proxy` subpackage.
   `<IfModule mod_proxy_http.c>` blocks in the rendered vhost fail silently
   (no error, the block is just skipped) if it's missing, so this is easy to
   miss. Verify and fix:
   ```bash
   docker compose -f docker-compose-alpinekoha.yml exec -T koha httpd -M | grep proxy
   # If empty: add apache2-proxy to the apk add line in Dockerfile-Alpine, then
   docker compose -f docker-compose-alpinekoha.yml build koha
   docker compose -f docker-compose-alpinekoha.yml up -d --force-recreate koha
   ```
2. **The koha-plack unix socket has restrictive permissions.** Apache runs as
   the `apache` user, not the instance user (`kohadev-koha`) that owns the
   socket; without world read/write on the socket file itself, Apache gets
   `(13)Permission denied: AH02454` connecting to it. Verify:
   ```bash
   docker compose -f docker-compose-alpinekoha.yml exec -T koha stat -c '%a' /var/run/koha/kohadev/plack.sock
   # Expect 777. If not, restart plack: koha-plack --restart kohadev
   ```

#### Page loads (HTTP 200) but has no CSS, or JS is broken / console shows `$ is not defined`

Symptom: `curl` looks fine (200, real HTML), but the page is unstyled and/or
interactive elements (password-show toggle, datepickers, etc.) don't work.

Cause: `Koha::Template::Plugin::Asset` (the `Asset.css`/`Asset.js` TT plugin)
resolves files by checking `-e` on disk under `<opachtdocs>`/`<intrahtdocs>`
(a symlink tree separate from Apache's own `DocumentRoot`) and **fails
silently** (just a Perl `warn`, no visible error, no 404) if the file isn't
found there -- the `<link>`/`<script>` tag is simply omitted. Two known causes
in this image:

1. The compiled stylesheet (`opac.css`) doesn't exist yet -- `run.sh` builds it
   automatically on first boot (`yarn install && yarn build`); check the logs
   for `[run.sh] Compiled CSS/JS assets missing; running yarn install +
   build...` and let it finish, or run it manually:
   ```bash
   docker compose -f docker-compose-alpinekoha.yml exec -T koha sh -c 'cd /kohadevbox/koha && yarn build'
   ```
2. The `intranet-tmpl`/`opac-tmpl` symlinks under `/usr/share/koha/{intranet,opac}/htdocs/`
   don't cover the whole tree (e.g. a missing `lib/` subdir breaks jQuery).
   `run.sh` symlinks the whole `intranet-tmpl`/`opac-tmpl` directories in one
   shot for this reason -- if you're on an older checkout that still
   cherry-picks subdirectories, update to the current `files-alpine/run.sh`.

Diagnostic: a page returning 200 is not sufficient proof it works -- check for
the actual tags, or open it in a real browser and check the console:
```bash
curl -s http://localhost:8080/ | grep -c 'rel="stylesheet"'   # expect > 0
curl -s http://localhost:8081/ | grep -c 'lib/jquery/jquery-3' # expect > 0
```

#### TLS mode drift causes HTTP 500 (most common first-run pitfall)

Symptom:

1. Ports 8080/8081 respond, but pages return `500 Internal Server Error`.
2. Koha logs show DBI errors such as:
   - `TLS/SSL error: Certificate verification failure: The certificate is NOT trusted`
   - `TLS/SSL error: SSL is required, but the server does not support it`

Why it happens:

1. Koha runtime and MariaDB runtime are using different TLS expectations.
2. Typical mismatch examples are toggling `KOHA_DB_USE_TLS` without aligning DB SSL mode, or reusing an old volume after changing SSL mode.

Quick verification:

```bash
# Koha-side TLS intent
docker compose -f docker-compose-alpinekoha.yml exec -T koha \
  bash -lc 'env | grep -E "^KOHA_DB_USE_TLS=|^KOHA_DB_TLS_CA_CERTIFICATE="; grep -n "<tls>\\|<ca>" /etc/koha/sites/kohadev/koha-conf.xml'

# DB-side SSL mode currently applied
docker compose -f docker-compose-alpinekoha.yml logs --tail=120 db | grep -iE 'ssl|tls|error'

# Failing request evidence
docker compose -f docker-compose-alpinekoha.yml exec -T koha \
  tail -n 120 /var/log/koha/kohadev/opac-error.log | grep -E 'DBI connect|TLS/SSL'
```

Recovery (recommended):

1. Keep one policy and apply it consistently (default recommendation: TLS enabled).
2. Recreate DB and Koha containers together after policy changes.
3. Wait for full startup marker before endpoint tests.

```bash
docker compose -f docker-compose-alpinekoha.yml up -d --force-recreate db koha
docker compose -f docker-compose-alpinekoha.yml logs --tail=120 koha
# wait for: "[run.sh] Startup complete"
./test-plack-stack.sh --no-recreate
```

### Runtime Issues

#### HTTP 500 errors in browser

**Check logs:**

```bash
docker compose -f docker-compose-alpinekoha.yml logs koha | tail -n 50
docker compose -f docker-compose-alpinekoha.yml exec koha \
  tail -f /var/log/koha/kohadev/intranet-error.log
```

Common 500 signatures and fixes:

1. `Can't locate Lingua/Stem/Snowball.pm`
  - Cause: missing CPAN dependency in the running image.
  - Fix: rebuild from updated `Dockerfile-Alpine` (which now installs `Lingua::Stem::Snowball`).

2. `ZOOM::Query::*->new` warnings or `create ZOOM::Connection` compile errors
  - Cause: incomplete/old ZOOM shim in older image layers.
  - Fix: rebuild `docker-compose-alpinekoha.yml` image to pick up current shim implementation.

3. `Auth ERROR: Cannot get_session() at /kohadevbox/koha/C4/Auth.pm line 1026`
  - Cause: `CGI::Session` cannot initialize `CGI::Session::ID::md5` because `Crypt::SysRandom` is missing in the image.
  - Verify from inside the Koha container:
    ```bash
    docker compose -f docker-compose-alpinekoha.yml exec -T koha \
      perl -MCrypt::SysRandom -e 'print "ok\n"'
    ```
  - Fix: rebuild and recreate Koha so the updated `Dockerfile-Alpine` layer (with `cpanm --notest Crypt::SysRandom`) is applied:
    ```bash
    docker compose -f docker-compose-alpinekoha.yml build koha
    docker compose -f docker-compose-alpinekoha.yml up -d --force-recreate koha
    ```

#### Slow performance / High CPU

**Check resource usage:**

```bash
docker stats koha-alpine-koha-1

# Increase container resources
# Edit docker-compose-alpinekoha.yml:
# services:
#   koha:
#     mem_limit: 4g
#     cpus: 2
```

#### "AssignUserID not recognized"

**This is expected on Alpine!** The run.sh script automatically comments out this Debian-specific directive:

```bash
# Seen in logs as:
# [alpine] Removing Debian-specific Apache suexec directives...

# This is NOT an error - it's required for Alpine compatibility
```

### Network Issues

#### Container can't reach host resources

**Enable host network (development only):**

```bash
# Edit docker-compose-alpinekoha.yml:
# services:
#   koha:
#     network_mode: host
```

#### DNS resolution failing

```bash
# Check container DNS
docker compose -f docker-compose-alpinekoha.yml exec koha cat /etc/resolv.conf

# Force specific DNS
# docker-compose-alpinekoha.yml:
# services:
#   koha:
#     dns:
#       - 8.8.8.8
#       - 8.8.4.4
```

## Dockerfile-Alpine Shims (1-Minute Explainer)

Why shims exist:

- Alpine 3.24 repositories currently do not provide YAZ/`Net::Z3950::ZOOM` in a way compatible with this Koha runtime.
- Koha still references ZOOM classes/constants in several search/bootstrap paths.

What the shim does:

1. Provides minimal `ZOOM` symbols Koha expects at compile/runtime:
  - `ZOOM::Query::CCL2RPN`, `ZOOM::Query::CQL`, `ZOOM::Query::PQF`
  - `ZOOM::Options`, `ZOOM::Connection`, `ZOOM::ResultSet`, `ZOOM::Record`
  - `ZOOM::Event::ZEND`, `ZOOM::event`, and `create` import bridge.
2. Returns safe no-op results where native Z39.50 behavior is unavailable.
3. Prevents fatal compile/runtime errors in CGI and startup paths while preserving HTTP service availability.

What the shim is not:

- It is not a full YAZ implementation.
- It is not intended to emulate full remote Z39.50 semantics.

Operational guidance:

1. Keep `APPLY_KOHA_PATCHES=no` by default and use only when explicitly needed.
2. Rebuild the Alpine image after any shim change:

```bash
docker compose -f docker-compose-alpinekoha.yml build koha
docker compose -f docker-compose-alpinekoha.yml up -d
```

3. Validate with:

```bash
bash tests/run_all_tests.sh
KOHA_ELASTICSEARCH=no APPLY_KOHA_PATCHES=no bash tests/run_integration_deterministic.sh
```

Related tracker entry:

- `docs/TRACKER/2026-07-24 — Alpine OPAC 500 remediation, ZOOM shim hardening, and test-suite stabilization.md`

## Development Workflow

### Setting Up Development Environment

```bash
# 1. Clone/checkout Koha repository
cd /path/to/your/koha-alpine
git clone https://github.com/Koha-Community/Koha.git koha
cd koha && git checkout -b develop origin/develop

# 2. Configure environment
cd ..
cp env/template.env env/.env
# Edit env/.env with local paths

# 3. Build and start
docker compose -f docker-compose-alpinekoha.yml build
docker compose -f docker-compose-alpinekoha.yml up -d

# 4. Monitor bootstrap
docker compose -f docker-compose-alpinekoha.yml logs -f koha
```

### Live Code Development

**With `SYNC_REPO` mount, your edits appear immediately:**

```bash
# Edit Koha files locally
nano /path/to/your/koha-alpine/koha/C4/SomeModule.pm

# Changes are visible in container at /kohadevbox/koha/C4/SomeModule.pm
# Perl scripts reload on next request (no restart needed)

# For CSS/JS changes, rebuild assets
docker compose -f docker-compose-alpinekoha.yml exec koha \
  bash -c 'cd /kohadevbox/koha && yarn build'
```

### Running Tests

```bash
# Run Koha test suite
docker compose -f docker-compose-alpinekoha.yml exec koha \
  prove -l /kohadevbox/koha/t/db_dependent/Auth.t

# Run specific test file
docker compose -f docker-compose-alpinekoha.yml exec koha \
  perl -I/kohadevbox/koha/lib -I/kohadevbox/koha/t/lib \
  /kohadevbox/koha/t/db_dependent/Api/Auth.t
```

### Debugging Perl Code

```bash
# Enable debugger in run.sh (edit and rebuild)
# Or use simple debugging:
docker compose -f docker-compose-alpinekoha.yml exec koha \
  perl -d -I/kohadevbox/koha/lib /kohadevbox/koha/svc/script.pl

# Print debugging
# Add to Perl code: warn "DEBUG: $variable";
# Check logs: docker compose logs koha | grep DEBUG
```

### Contributing Changes

```bash
# 1. Create feature branch
cd koha
git checkout -b feature/my-feature

# 2. Make changes and test locally
# ... edit files ...

# 3. Commit changes
git add .
git commit -m "Feature: description"

# 4. Push to fork
git push origin feature/my-feature

# 5. Create pull request on GitHub
```

## Production Deployment

Production mode now uses the fixed-version image workflow described in `Dual Image Modes (Development vs Production)`.
The procedure below is the canonical deployment path.

### Pre-Deployment Checklist

- [ ] All modules compile without "Can't locate" errors
- [ ] Database migrates cleanly (check logs)
- [ ] Both HTTP ports respond with 200 OK
- [ ] SSL certificates are current and valid
- [ ] Environment variables are secured (change default passwords)
- [ ] Backup database connection string and certificates
- [ ] Target release values are decided and pinned (`KOHA version` + `Git ref/tag`)

### Deployment Steps

Substitute `<VERSION>` and `<TAG>` with the target Koha release (e.g. `26.05.01-1` / `v26.05.01-1`).

```bash
# 1. Build a fixed-version production image using the released git tag
./stack-alpine.sh build \
  --image-mode prod \
  --koha-version 25.11.06-1 \
  --koha-ref v25.11.06-1 \
  --build-koha

# 2. (Optional) Push the resulting image tag to a registry
docker push kosson/koha-alpine-prod:25.11.06-1

# 3. Start the stack in production mode with the exact same version and ref
./stack-alpine.sh start \
  --image-mode prod \
  --koha-version 25.11.06-1 \
  --koha-ref v25.11.06-1

# 4. Verify services and endpoints
./stack-alpine.sh status
curl http://localhost:8080/
curl http://localhost:8081/
```

### Direct Compose Alternative (manual)

If you need to deploy without the stack wrapper:

```bash
KOHA_RELEASE_VERSION=25.11.06-1 \
KOHA_RELEASE_REF=v25.11.06-1 \
KOHA_ALPINE_PROD_IMAGE_TAG=kosson/koha-alpine-prod:25.11.06-1 \
docker compose \
  -f docker-compose-alpinekoha.yml \
  -f docker-compose.prod.yml \
  --env-file env/.env \
  up -d --build
```

### Rollback Pattern

To roll back, restart in prod mode with the previous known-good version and tag:

```bash
./stack-alpine.sh start \
  --image-mode prod \
  --koha-version 25.11.06 \
  --koha-ref v25.11.06
```

Replace those values with whichever earlier version/ref pair was last confirmed good.

### Scaling & Load Balancing

For multi-server deployment, use:
- **Traefik** (included in `traefik/`) for reverse proxy
- **Separate database** (external MariaDB or managed service)
- **Shared storage** (NFS for Koha files)
- **Session store** (Redis for distributed sessions)

See `traefik/README.md` for reverse proxy setup.

## Support & Documentation

| Resource | Location | Purpose |
|----------|----------|---------|
| Alpine Migration Notes | `docs/Alpine-migration/` | Historical development process |
| Koha Documentation | https://koha-community.org/documentation | Official Koha guides |
| Alpine Linux | https://alpinelinux.org/docs/ | Alpine-specific information |
| Docker Docs | https://docs.docker.com/ | Docker and compose reference |
| Koha Wiki | https://wiki.koha-community.org/ | Community knowledge base |


## Version Information

- **Alpine Base:** 3.24.1
- **Koha Image:** kosson/koha-alpine:26.11
- **MariaDB:** 10.11
- **RabbitMQ:** 3-management
- **Node.js:** Latest stable (Alpine apk)
- **Perl:** 5.x (Alpine apk)
- **Last Updated:** 2026-08-03

---

## License

This Alpine Docker setup follows Koha's licensing (GPL v3). SSL certificates are self-signed for development purposes.

## Contributing

Improvements, bug reports, and patches welcome! Submit to the koha-alpine repository.