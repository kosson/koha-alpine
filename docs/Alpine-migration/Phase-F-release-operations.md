# Phase F — Local release validation, backup, and rollback

This guide describes the current release process for the Alpine implementation.
The [Alpine runtime architecture](../architecture/18%20-%20Alpine%20Runtime%20Architecture.md)
and the repository's Dockerfiles, Compose files, and `stack-alpine.sh` are the
sources of truth for runtime behavior.

## CI-independent local release validation

This project does not require GitHub Actions or another hosted CI service.
Run the local acceptance procedure from the repository root:

```bash
KOHA_RELEASE_VERSION=26.05.01-1 \
KOHA_RELEASE_REF=v26.05.01-1 \
bash scripts/validate-release-local.sh
```

The script requires Docker, Compose, Buildx, and a local `koha/` checkout at
the exact selected ref. It runs the non-project test suites, validates both
Compose configurations with a temporary non-secret environment file, and
performs uncached, pulled development and production builds. It does not start
Compose services or select a deployment project. Integration tests requiring
an explicitly isolated running project remain opt-in and are not represented
as passing by this procedure. The script prints source identity, tool versions,
and image IDs/sizes for a release record. It requires at least 15 GiB free on
the Docker data filesystem before building to avoid filling a nearly full host.

## Select and identify a release

Use a released tag or a verified commit ID, not a moving branch such as `main`.
The image build checks out the selected source ref, builds its assets, records
the resolved commit in `/usr/share/koha/source-revision`, and records the source
URL and requested ref in corresponding files. The image also has OCI labels:

- `org.opencontainers.image.title`
- `org.opencontainers.image.version`
- `org.opencontainers.image.source`
- `org.opencontainers.image.revision`

The revision label represents the requested ref, which may be a tag. Use the
resolved revision file to establish the exact source commit. For strongest
repeatability, verify a release tag and build from its full commit SHA while
keeping the human-readable Koha release version separate.

Choose and record all four values for each release:

```text
KOHA_RELEASE_VERSION=<Koha release version>
KOHA_RELEASE_REF=<verified tag or full commit SHA>
KOHA_RELEASE_GIT_URL=https://git.koha-community.org/Koha-community/Koha.git
KOHA_ALPINE_PROD_IMAGE_TAG=<registry>/<image>:<immutable release tag>
```

Avoid reusing or moving an image tag after publication. The local validation
procedure builds images but does not publish them; image publication and
registry access are an explicit operator-controlled step after successful
validation.

Inspect a locally built image before deployment:

```bash
IMAGE=kosson/koha-alpine-prod:26.05.01-1
docker image inspect "$IMAGE" \
  --format '{{json .Config.Labels}}'
docker run --rm --entrypoint cat "$IMAGE" \
  /usr/share/koha/source-revision
docker run --rm --entrypoint cat "$IMAGE" \
  /usr/share/koha/source-ref
```

Keep the build log, version, requested ref, resolved commit, image tag, and image
digest together in the release record. If the image is pushed, record the
registry digest as well.

## Secrets and local configuration

`env/.env`, `traefik/.env`, and `OpenSearch-3.6/.env` can contain passwords,
credentials, or paths to private keys. Treat them and backup archives as
secrets:

- The tracked environment files and OpenSearch auth templates previously had
  credential-capable values. The current worktree has cleared those values and
  replaced tracked OpenSearch authentication material with local-generation
  placeholders. The owner reports potentially active credentials have been
  rotated; an owner-approved Git-history/remotes disposition is still required.
  `stack-alpine.sh` and `netcheck.sh` accept
  `KOHA_ENV_FILE=/absolute/path/to/local.env`; the stack wrapper passes the
  selected file to Compose as the container env file by default. Keep the
  external file access-controlled and ignored by Git.
- Use unique, strong passwords; never deploy example or default credentials.
- Keep runtime credentials out of Git, command output, issue reports, and image build
  arguments. Build arguments and image labels are not secret channels.
- Prefer a host secret manager to render the required environment files on the
  deployment host. Restrict file access (for example, mode `0600`) and ensure
  backups are encrypted and access-controlled.
- The Compose environment-file mechanism supplies values to containers; it is
  not Docker Swarm secret storage. Protect the host and Docker daemon accordingly.
- Do not add registry credentials to local image validation; publishing is a
  separately reviewed operator-controlled action.

The backup helper copies the environment files into its archive without
encrypting them unless `KOHA_BACKUP_GPG_RECIPIENT` is set (see below). Store
that archive as confidential data. The archive, staged
configuration files, database dump, and manifest use `0600` permissions; the
staging subdirectories use `0700`. Restored environment files are also set to
`0600`. Keep the containing backup directory access-controlled as well.

## Compose project names and persistent volumes

Compose scopes named volumes by project. The production project name selected by
`stack-alpine.sh` is version-specific by default:
`koha-prod-<version-slug>`. Consequently, merely changing the release version
can select a different MariaDB and RabbitMQ volume pair. This can look like an
empty deployment rather than an upgrade.

For in-place upgrades, set `KOHA_PROD_PROJECT` in `env/.env` to a stable,
lowercase project identifier, for example:

```dotenv
KOHA_PROD_PROJECT=koha-prod-live
```

The value must begin with a lowercase letter or digit and contain only
lowercase letters, digits, `_`, or `-`. Keep it unchanged for every release,
backup, and restore. When adopting this option on an existing installation,
set it to the exact current Compose project name so the existing volumes remain
selected; do not guess the name. The script prints the selected Compose project
at startup. If managing Compose directly rather than using `stack-alpine.sh`,
pass the same name with `docker compose --project-name`.

Never use `docker compose down -v`, `stack-alpine.sh reset`, or volume-prune
commands as part of routine release or rollback.

### Volume identity guards (G6)

- `./stack-alpine.sh volumes --image-mode prod` prints the selected project and
  its DB/RabbitMQ volumes (exists/absent, creation time) plus sibling
  `koha-prod-*` projects that own data. Run it before every upgrade.
- If the selected project has no DB volume but a sibling `koha-prod-*` project
  does, `start`/`restart` refuse. Pin `KOHA_PROD_PROJECT` to the existing
  project, or set `KOHA_ACCEPT_NEW_VOLUMES=yes` for a deliberate new deployment.
- After `start`, `restart` and `restore`, the helper verifies the running
  containers mount exactly the expected volumes and aborts on mismatch.
- On a populated production DB, `start` and `restart` without `--no-fresh-db`,
  and `reset`, require typing the exact Compose project name. (`restart`
  previously dropped the database without any prompt.) For upgrades always use
  `--no-fresh-db`.
- In prod mode with `--no-fresh-db` the helper may log "bootstrap marker
  missing"; this is harmless, as the container decides by inspecting the DB.

## Pre-deployment backup and upgrade

Run upgrades in a planned maintenance window. Take the backup before changing
the active release settings. If using the stable project option, verify the
project name first; the helper will dump the database belonging to that project.

```bash
# Confirm the selected production version/ref/project before maintenance.
./stack-alpine.sh status --image-mode prod

# Stop the application and related services to establish a maintenance window.
./stack-alpine.sh stop --image-mode prod

# Archive the database and current release/configuration settings.
./stack-alpine.sh backup --image-mode prod --output /secure-backups/koha-before-upgrade.tar.gz
```

The archive contains the three environment files and a compressed MariaDB dump
of the configured Koha database. It does **not** contain the RabbitMQ named
volume, OpenSearch data, generated TLS certificates/private keys, or other
host-mounted assets. Back up the latter assets separately according to local
retention requirements. OpenSearch indexes can generally be rebuilt from Koha
data, but that recovery must be planned and verified for the deployment.

Record and verify the external backup copies before proceeding. Then update the
release settings in the protected `env/.env` file, preserving
`KOHA_PROD_PROJECT`, and build the candidate image:

```bash
./stack-alpine.sh build \
  --image-mode prod \
  --koha-version 26.05.01-1 \
  --koha-ref v26.05.01-1 \
  --build-koha
```

Inspect image labels, source-ref/revision files, image size, and build logs.
After the candidate is approved, start it against the existing database without
requesting a fresh database:

```bash
./stack-alpine.sh start \
  --image-mode prod \
  --no-fresh-db \
  --koha-version 26.05.01-1 \
  --koha-ref v26.05.01-1
```

Validate `./stack-alpine.sh status`, container health, startup logs, OPAC and
staff HTTP responses on ports 8080 and 8081, and the Koha functions that matter
to the deployment. Confirm that the running project is the intended stable
project and that the expected named volumes are attached.

## Rollback

Do not roll back only the application image after Koha has upgraded the
database. Schema changes may make the earlier application incompatible. The
supported recovery procedure is to stop the stack and use the pre-upgrade
archive, which restores both the earlier configuration and database dump:

```bash
./stack-alpine.sh stop --image-mode prod
./stack-alpine.sh restore \
  --image-mode prod \
  --input /secure-backups/koha-before-upgrade.tar.gz
```

The restore command is interactive and recreates/imports the database before
starting the stack using the restored release settings. Ensure the corresponding
previous production image is available locally or can be pulled from its
registry before starting recovery. Changes written after the backup point will
be lost when the archived database is restored. Recheck service health and
application behavior after recovery.

The helper restores the env files, the MariaDB dump, RabbitMQ users/vhosts/
permissions and any host assets listed in the archive. On `start_koha` it
re-applies the broker user, password and permissions from the (restored) env,
because `RABBITMQ_DEFAULT_*` only seed an empty broker. RabbitMQ queue contents
and OpenSearch data are not restored: rebuild the index afterwards with
`koha-elasticsearch --rebuild --reset --delete <instance>`. After restore,
verify `rabbitmqctl list_stomp_connections` is non-empty; the Koha health check
stays green even when the broker rejects Koha. For a new host, provide the
certificates and host-mounted files (or let the archive restore them) before
starting Koha.

### Host assets and encrypted archives

Set `KOHA_BACKUP_ASSET_PATHS` (absolute, space-separated files or directories,
e.g. TLS keys/certificates, OpenSearch CA, Traefik ACME data) in the env file or
environment. They are archived with modes preserved and re-extracted by
`restore`; `KOHA_ASSET_RESTORE_ROOT` redirects extraction for dry runs. Set
`KOHA_BACKUP_GPG_RECIPIENT` to encrypt the finished archive to a public key
(`*.gpg`, plaintext removed); `restore --input file.gpg` decrypts it with the
operator's private key. The key itself must be stored separately from the
backups. Note that `files-alpine/mariadb-ssl/*-key.pem` in this repository are
test keys tracked in git; production must generate and back up its own.

### RabbitMQ data and node name

The broker's data directory is keyed by node name (`rabbit@<hostname>`). The
compose file pins `hostname: rabbitmq`, so users and queues now survive
container recreation. Do not remove that setting: without it each recreation
starts an empty broker and the named volume is orphaned.

### Rehearsing the restore command safely

`KOHA_EXTRA_COMPOSE_FILES` adds compose override files to every Koha compose
call (for example to drop host ports and rename networks), and
`KOHA_MANAGE_SHARED_SERVICES=no` stops `restore` from stopping/starting the
shared OpenSearch and Traefik stacks or creating global Docker networks. Use
both, a separate `KOHA_ENV_FILE`, a distinct `KOHA_PROD_PROJECT`, and a copy of
the helper, so nothing outside the disposable project is touched.

## Restore rehearsal

Before relying on this procedure in production, rehearse it against a
disposable, isolated Compose project and distinct test volumes. Confirm the
archived database can be imported, the prior image is available, all required
configuration and TLS material exists, and the expected endpoints work. Never
point a rehearsal at production volumes and never delete production volumes as
cleanup.
