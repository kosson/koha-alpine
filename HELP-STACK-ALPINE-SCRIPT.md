# stack-alpine.sh — Complete Reference

`stack-alpine.sh` is the single entry point for building, starting, stopping, and
maintaining the entire Alpine Koha stack (Koha + MariaDB + Memcached + RabbitMQ, with
optional OpenSearch and Traefik).

All commands must be run from the `koha-alpine` root directory:

```bash
cd /path/to/your/koha-alpine
./stack-alpine.sh <command> [options]
```

---

## Commands

| Command | Description |
|---|---|
| `start` | Start the full stack (default when no command is given) |
| `stop` | Stop all services (OpenSearch + Koha stack) |
| `restart` | Reset DB + recreate Koha container only; skips OpenSearch restart |
| `build` | Build images without starting anything |
| `latest-tag` | Show the latest upstream Koha release tag; `--apply [<tag>]` writes it to `env/.env` |
| `status` | Show running containers and OpenSearch cluster health |
| `logs` | Tail Koha container logs |
| `tls-client-cert` | Generate/reuse MariaDB client TLS cert/key and wire `env/.env` |
| `backup` | Create a `tar.gz` bundle of `env/` files + MariaDB data |
| `restore` | Restore `env/` files + MariaDB data from a backup bundle |
| `reset` | ⚠ Stop everything and remove all containers + named volumes (requires confirmation) |

---

## Options

### `start` and `build`

| Flag | Default | Description |
|---|---|---|
| `--image-mode <dev\|prod>` | `dev` | Choose compose/build target |
| `--koha-version <ver>` | from `env/.env` | Release label for image tag and project name (e.g. `25.11.06-1`) |
| `--koha-ref <ref>` | from `env/.env` | Git ref baked into the image (e.g. `v25.11.06-1`, `main`) |
| `--build-koha` | — | Rebuild only the Koha image |
| `--build-opensearch` | — | Rebuild only the OpenSearch image |
| `--build` | — | Rebuild both Koha and OpenSearch images |
| `--no-fresh-db` | — | Skip database drop/recreate; preserve existing data |
| `--bootstrap-profile <resume\|full>` | `resume` | `resume`: skip full population; `full`: force `do_all_you_can_do.pl` |
| `--no-logs` | — | Do not tail logs after starting |
| `--with-demo-data` | ✓ (default) | Load sample MARC records, items, and patron data |
| `--no-demo-data` | — | Start with an empty catalogue; superlibrarian account only |
| `--prepare-db-client-tls` | — | Ensure TLS client cert/key exist and wire `env/.env` before starting |

### `tls-client-cert`

| Flag | Description |
|---|---|
| `--force-client-tls-regen` | Regenerate client cert/key even if they already exist |

### `latest-tag`

| Flag | Description |
|---|---|
| `--apply` | Write the resolved tag to `KOHA_GIT_TAG` in `env/.env` |
| `--apply <tag>` | Write a specific tag (e.g. `v25.11.06-1` or `25.11.06-1`) |

### `backup`

| Flag | Description |
|---|---|
| `--output <path>` | Write the bundle to a custom path instead of `./backups/` |

### `restore`

| Argument | Description |
|---|---|
| `<archive>` | Path to the `.tar.gz` bundle to restore from |

---

## Koha source bootstrap (`env/.env`)

These variables control how `stack-alpine.sh` clones or locates the Koha source on first run.

| Variable | Description |
|---|---|
| `SYNC_REPO` | Absolute host path for Koha source (auto-cloned here if missing) |
| `KOHA_GIT_CLONE_MODE` | `tag` (pin a release) or `branch` (track a branch) |
| `KOHA_GIT_TAG` | **Primary version variable.** Required when clone mode is `tag`. Set with `latest-tag --apply`. |
| `KOHA_GIT_BRANCH` | Branch to track when clone mode is `branch` (e.g. `main`) |
| `KOHA_GIT_DEPTH` | Shallow clone depth (positive integer; `1` saves time and disk) |
| `KOHA_GIT_URL` | Optional override for forks or mirrors |

---

## Language automation (`env/.env`)

| Variable | Description |
|---|---|
| `KOHA_DESIRED_LANGUAGES` | Comma-separated list of language packs to install (e.g. `en,es-ES,ro-RO`) |
| `KOHA_OPAC_LANGUAGES_DISPLAY` | `1` to show OPAC language chooser, `0` to hide |
| `KOHA_TRANSLATIONS_REINSTALL` | `yes` to reinstall packs on every start; `no` to install missing only |

---

## Worked examples

### First run (development)

```bash
cp env/template.env env/.env
# edit env/.env: set SYNC_REPO, KOHA_DB_ROOT_PASSWORD

./stack-alpine.sh build --image-mode dev --build-koha
./stack-alpine.sh tls-client-cert
./stack-alpine.sh start
```

---

### First run (production — latest stable release)

```bash
cp env/template.env env/.env
# edit env/.env: set KOHA_DB_ROOT_PASSWORD

./stack-alpine.sh latest-tag --apply          # writes KOHA_GIT_TAG=v26.05.01-1 (or whatever is current)
./stack-alpine.sh build --image-mode prod --build-koha
./stack-alpine.sh tls-client-cert
./stack-alpine.sh start --image-mode prod
```

---

### First run (production — specific release)

Use this when you want to deploy a known-stable maintenance release rather than the
absolute latest.

```bash
# Step 1: see what tags are available
./stack-alpine.sh latest-tag

# Step 2: pin the release you want
./stack-alpine.sh latest-tag --apply v25.11.06-1
# leading 'v' is optional: --apply 25.11.06-1 works the same way

# Step 3: build
./stack-alpine.sh build --image-mode prod --build-koha

# Step 4: certificates + start
./stack-alpine.sh tls-client-cert
./stack-alpine.sh start --image-mode prod
```

---

### Upgrade to a newer Koha release

```bash
./stack-alpine.sh latest-tag                  # see what is available
./stack-alpine.sh latest-tag --apply v25.11.07-1  # or whatever the new release is
./stack-alpine.sh build --image-mode prod --build-koha
./stack-alpine.sh stop
./stack-alpine.sh start --image-mode prod
```

> If you want to preserve existing library data, add `--no-fresh-db` to the `start` command
> and ensure the Koha database schema upgrade runs (Koha's web installer handles this on
> first login after a version change).

---

### Resume dev stack after a reboot (no DB wipe)

```bash
./stack-alpine.sh start --no-fresh-db
```

`--no-fresh-db` checks for `koha/.alpine-bootstrap-complete`. If the marker is present, it
skips full population and starts quickly. If the marker is missing (e.g. first run on a
fresh clone), it falls back to a full bootstrap automatically.

---

### Force a full re-bootstrap on an existing database

```bash
./stack-alpine.sh start --no-fresh-db --bootstrap-profile full
```

This re-runs `do_all_you_can_do.pl` against the existing database. Use after a Koha upgrade
or when system preferences/MARC frameworks need to be repopulated.

---

### Start with a clean catalogue (no demo data)

```bash
./stack-alpine.sh start --no-demo-data
```

The superlibrarian account is created but no sample records, items, or patrons are loaded.
Useful for production-like testing and migration exercises.

---

### Rebuild images then start in one command

```bash
# Dev: rebuild only the Koha image, then start
./stack-alpine.sh start --build-koha

# Dev: rebuild everything (Koha + OpenSearch), then start
./stack-alpine.sh start --build

# Prod: rebuild Koha image and start (KOHA_GIT_TAG must already be set in env/.env)
./stack-alpine.sh start --image-mode prod --build-koha
```

---

### Build without starting (CI / pre-warm)

```bash
./stack-alpine.sh build --image-mode dev --build-koha
./stack-alpine.sh build --image-mode prod --build-koha
./stack-alpine.sh build --build-opensearch
./stack-alpine.sh build                               # rebuild everything (dev mode)
```

---

### Override version on a single build without editing `env/.env`

```bash
./stack-alpine.sh build \
  --image-mode prod \
  --koha-version 25.11.06-1 \
  --koha-ref v25.11.06-1 \
  --build-koha
```

`--koha-ref` overrides `KOHA_GIT_TAG` for this build only. `--koha-version` sets the image
tag and the compose project name (used for container naming).

---

### Pre-release / development branch build (experimental)

Use only for testing unreleased code. Do **not** deploy `main` in production.

```bash
./stack-alpine.sh latest-tag --apply main
./stack-alpine.sh build --image-mode prod --build-koha
```

---

### Quick restart (OpenSearch stays up)

```bash
./stack-alpine.sh restart
./stack-alpine.sh restart --no-demo-data        # restart with empty catalogue
./stack-alpine.sh restart --no-fresh-db         # restart, keep database
```

`restart` only recreates the Koha container and resets the database. OpenSearch, MariaDB,
Memcached, and RabbitMQ are left running. This is much faster than a full `stop` + `start`.

---

### TLS client certificates

```bash
# Generate client cert/key (or reuse if already present)
./stack-alpine.sh tls-client-cert

# Force regeneration (e.g. after CA rotation)
./stack-alpine.sh tls-client-cert --force-client-tls-regen

# Ensure certs are ready as part of a start
./stack-alpine.sh start --prepare-db-client-tls
```

The helper generates `files-alpine/mariadb-ssl/client-{cert,key}.pem` signed by the
project CA, and automatically writes the paths into `env/.env` as
`KOHA_DB_TLS_CLIENT_CERTIFICATE` and `KOHA_DB_TLS_CLIENT_KEY`.

---

### Languages

```bash
# Install Romanian and Spanish UI packs in addition to English, show OPAC chooser
KOHA_DESIRED_LANGUAGES=en,es-ES,ro-RO ./stack-alpine.sh start

# Or set permanently in env/.env:
# KOHA_DESIRED_LANGUAGES=en,es-ES,ro-RO
# KOHA_OPAC_LANGUAGES_DISPLAY=1
```

---

### Backup and restore

```bash
# Create a timestamped bundle in ./backups/
./stack-alpine.sh backup

# Save to a custom path
./stack-alpine.sh backup --output /mnt/nas/koha-backup-$(date +%Y%m%d).tar.gz

# Restore
./stack-alpine.sh restore backups/koha-backup-20260804T120000Z.tar.gz
```

The bundle contains all files in `env/`, the MariaDB data volume dump, and the
`files-alpine/mariadb-ssl/` certificate set.

---

### Nuclear reset (start from zero)

```bash
./stack-alpine.sh reset    # requires typing 'yes'; images are preserved
```

All named volumes (database, OpenSearch indexes) and containers are removed. Re-run the
first-run flow from Step 2 in the Quick Start to bring everything back up from zero.

---

## Safety notes

1. `start` **without** `--no-fresh-db` prompts for confirmation before dropping an existing
   Koha database. It will not silently delete data.
2. `--no-fresh-db` is safe to use on a zero-state machine — the script detects the missing
   bootstrap marker and performs a full bootstrap automatically.
3. `reset` is destructive and irreversible. Back up first with `backup`.
4. Always use a released tag (e.g. `v25.11.06-1`) for `--koha-ref` in production.
   The `main` branch is a development target and is not stable.
5. `KOHA_GIT_TAG` in `env/.env` is the single source of truth for the prod image version.
   Do not manually edit `KOHA_GIT_REF` in `Dockerfile-Alpine` — use `latest-tag --apply`
   instead.
