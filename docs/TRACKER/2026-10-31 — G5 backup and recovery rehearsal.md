# G5 — Backup, restore, rollback, and external-state rehearsal

**Date:** 2026-10-31  
**Branch:** `phase`  
**Result:** **PASS (rehearsal)** after the closure pass recorded in the final
addendum. The first pass was PARTIAL (database-level only); the closure pass
added RabbitMQ, host-asset and encrypted-archive recovery, a failed-rollback
scenario and a real `restore` run. Production asset inventory and RTO/RPO
approval remain owner items (G7/G9).

## Outcome

The G5 rehearsal used a disposable Koha `26.05.01-1` project, then ran the
`26.06.00.003` candidate against its database and restored the pre-upgrade
backup into a second project with new DB and OpenSearch volumes. A synthetic
catalogue record written before the backup returned after restore; a second
record written after the backup did not. The previous image started healthy
against the restored schema. OpenSearch was rebuilt from the restored Koha
database and returned the pre-backup record in a title search.

The first pass left G5 **PARTIAL**: RabbitMQ state, private keys/host assets,
a failed-upgrade scenario and the helper's full restore command were not
exercised. Those gaps were closed in the addendum below.

## Isolation and provenance

- The source database container `koha-docker-db-1` remained running on
  `koha-docker_koha-db-data`; it was not used as a test database.
- Prior-version project: `koha-g5-20261031`; its database volume was
  `koha-g5-20261031_koha-db-data`.
- Restore project: `koha-g5-restore-20261031`; its database and OpenSearch
  volumes were `koha-g5-restore-20261031_koha-db-data` and
  `koha-g5-restore-20261031_opensearch-data`. These were newly created and
  distinct from the original G5 volumes.
- Prior image `koha-alpine-g5-prior:26.05.01-1`:
  `sha256:0f4fbef2ef866cbef3806f55cc7a2b837d2814bf5a3d94f0cc152d44f814ad28`.
- Upgrade candidate `koha-alpine-g4:26.06.00.003-c355bb8`:
  `sha256:063ca6c26a9480ebecea54621b78e5c1a856819e3c49547f7c4b8bec0187943e`.
  OCI version/revision labels were `26.06.00.003` /
  `c355bb8574f62e4a04e774a65a6385feb9b858b0`.
- All Koha services had no host port mappings in the isolated projects.
  Synthetic environment and backup files stayed under the access-controlled
  `/tmp/koha-g5-rehearsal-20261031` workspace.

## Quiescence and backup

The pre-upgrade database schema was `26.0501000`. Before backup, the disposable
Koha service was explicitly stopped; the backup helper itself does not stop or
quiesce Koha. The database had one bibliographic record,
`G5PRE1793434232`, and no items. The test database also had one borrower and
one branch.

The actual helper ran a MariaDB dump with `--single-transaction`, routines,
triggers, and events, and archived three configuration files. The archive was
created at `2026-10-31T08:18:54Z`; its outer file mode was `0600`, all three
configuration members were `0600`, and the compressed SQL dump passed `gzip -t`.
The dump contained the pre-backup marker.

Runtime inspection found that the first archive's SQL dump member was mode
`0664` when extracted, although the containing archive was `0600`. The helper
was hardened to set the config/database staging directories to `0700` and the
database dump and manifest to `0600`. A second actual backup confirmed the
archive mode `0600`, directories `0700`, all configuration/dump/manifest files
`0600`, and a valid compressed dump. The second archive was made after the
schema upgrade and was used only for the permission regression check, not for
the rollback test.

One initial helper invocation used a temporary helper copy without the G5
isolation Compose override. Compose stopped the G5 DB/cache containers and
Docker refused to remove the G5 network because RabbitMQ/OpenSearch still had
active endpoints. No volumes were removed. The DB/cache services were restarted
using the original isolated Compose definition and the marker/counts were
verified intact. The helper copy was then aligned to the same G5 override and
the backup completed without creating or changing any global Docker network.

## Upgrade and rollback boundary

After the backup, a second synthetic MARCXML record,
`G5POST1793434232`, was imported into the disposable database. The database
then contained two bibliographic records. The candidate image was started
against that same G5 DB volume:

| Check | Before candidate | After candidate |
|---|---:|---:|
| Koha schema preference | `26.0501000` | `26.0600003` |
| Bibliographic records | 2 | 2 |
| Pre-backup marker | 1 | 1 |
| Post-backup marker | 1 | 1 |
| Items / borrowers / branches | 0 / 1 / 1 | 0 / 1 / 1 |

The candidate container became healthy. This rehearsed the version upgrade,
but the upgrade itself succeeded; a deliberately failed-upgrade recovery was
not injected.

The pre-upgrade SQL archive was then imported into the empty DB in the separate
restore project. The prior `26.05.01-1` image became healthy on that database
with schema `26.0501000`, one bibliographic record, pre-backup marker count 1,
and post-backup marker count 0. This demonstrates that the post-backup write is
lost at the recorded backup boundary and that restoring only the older image
would not be an adequate rollback after a schema upgrade.

Measured recovery time was **47 seconds** from immediately before the empty-DB
check/import to the prior Koha container becoming healthy. The
DB/OpenSearch/cache/broker services and new volumes were already provisioned;
this time excludes infrastructure provisioning, external-asset recovery, and
OpenSearch rebuild.

## OpenSearch and separately archived assets

A new OpenSearch service and volume were used for the restore project. The
OpenSearch index was rebuilt from the restored Koha DB with
`koha-elasticsearch --rebuild --reset --delete --verbose kohadev`: one biblio
was indexed, and an exact title search for the restored marker returned one
hit. The authorities rebuild indexed zero records and emitted an
uninitialized-value warning in Koha's rebuild script; the test database had
no authorities.

The database/config archive does not include the OpenSearch CA or host files.
A separate protected test asset archive contained the public OpenSearch CA and
a synthetic host-file marker. Both were restored; the CA was set to `0644` so
the non-root Koha process could read it. Koha's Elasticsearch client then
authenticated to the isolated HTTPS endpoint using the restored CA. This
proves that specific test asset path only; no production private key,
certificate chain, or actual host-mounted data was available or tested.

RabbitMQ's named volume was not archived or restored, and no broker message
state was tested. OpenSearch data was rebuilt rather than snapshot-restored.

## Restore-helper scope and remaining work

In the first pass the `stack-alpine.sh restore` command was not run. Its then-current path overwrites
host configuration and starts/stops OpenSearch and Traefik through fixed
Compose locations, so it was not safe to invoke against a second isolated
project. The database restore was performed manually from the generated
archive into the new project; it does not validate the helper's full restore
workflow.

Open items at the end of the first pass (closed in the addendum below, except
the owner decisions in item 5):

1. Define and test an isolated full restore workflow that cannot touch shared
   OpenSearch, Traefik, or host-mounted paths.
2. Demonstrate recovery of RabbitMQ data or document and obtain approval for
   its exclusion.
3. Back up and restore representative real host assets, including required
   private keys/certificates, using the deployment's protected asset process.
4. Exercise recovery from a deliberately failed candidate upgrade.
5. Decide whether the measured recovery window and lost-write boundary meet
   the service owner's requirements; arrange encryption for off-host backups.

## Addendum — full G5 closure rehearsal (2026-10-31)

The first pass left G5 PARTIAL. This second pass closed each open item in one
disposable project (`koha-g5f`, project-scoped volumes, no host ports, its own
single-node OpenSearch with the project's ICU image) using synthetic secrets.
The real `stack-alpine.sh` was run from an isolated helper copy; the source DB
container/volume and shared Traefik/OpenSearch/global networks were not touched.

### Root cause of the RabbitMQ "keys" problem

Two defects, both reproduced:

1. **Volume never persisted across container recreation.** The official image
   names its Erlang node `rabbit@<container hostname>`. Compose recreates the
   container with a new random hostname, so each recreation created a new empty
   broker directory inside `koha-rabbitmq-data` and orphaned the previous one
   (three node directories were found after three recreations). Users,
   permissions and queues were therefore never preserved, and a restored volume
   would never have been picked up.
2. **Credentials are only seeded into an empty broker.** `RABBITMQ_DEFAULT_*`
   are ignored once state exists, so a rotated/restored `KOHA_RABBITMQ_PASS`
   would not reach the broker and Koha's `MESSAGE_BROKER_PASS` would be rejected.

Observed failure mode: after a candidate upgrade with a rotated broker
password, a naive rollback (prior image + prior env) reported the container
`healthy` with schema `26.0600003` but **0 STOMP connections**, and the broker
rejected the original password. The Koha health check does not detect a broker
outage, so check `rabbitmqctl list_stomp_connections` after any restore.

### Changes

- `docker-compose-alpinekoha.yml`: `hostname: rabbitmq` pins the node name.
  Verified: a marker user created before `up --force-recreate rabbitmq` was
  still present afterwards (one node directory in the volume).
- `stack-alpine.sh`:
  - `start_koha` now runs `reconcile_rabbitmq_credentials` (idempotent: ensures
    vhost, adds or resets the user password, sets permissions from the env).
  - `backup` stores `rabbitmq/definitions.json` (users/hashes, vhosts,
    permissions; `0600`, dirs `0700`). Queue contents are transient and are
    deliberately not backed up.
  - `KOHA_BACKUP_ASSET_PATHS` (absolute paths, space separated) adds
    `assets/assets.tar` (modes preserved); `restore` re-extracts it before
    services start. `KOHA_ASSET_RESTORE_ROOT` redirects extraction for dry runs.
  - `KOHA_BACKUP_GPG_RECIPIENT` encrypts the finished archive to `*.gpg` and
    removes the plaintext; `restore` decrypts `*.gpg` transparently.
  - Isolation switches: `KOHA_EXTRA_COMPOSE_FILES` adds per-project compose
    overrides; `KOHA_MANAGE_SHARED_SERVICES=no` makes `restore` and the
    prerequisite check leave shared OpenSearch/Traefik alone, and stops
    `ensure_extra_networks` creating global networks. A first run without this
    guard created the global `knonikl` network (no containers; removed again).
- Static tests: 41 checks (was 29); full suite 313 passed, 0 failed, 29 skipped.

### Rehearsal result

| Step | Evidence |
|---|---|
| Baseline | prior `26.05.01-1` image healthy at schema `26.0501000`; 2 STOMP connections; one synthetic record imported |
| Backup (real helper, Koha stopped) | archive `0600`; contains env files, dump, `rabbitmq/definitions.json` (user `koha`, vhost `koha_kohadev`), `assets.tar`; no global network created |
| Upgrade | candidate `26.06.00.003` healthy at `26.0600003`; broker password rotated; post-backup marker written |
| Failed rollback | prior image + prior env on upgraded DB: `healthy` but 0 STOMP, original password rejected |
| Asset loss | removed the OpenSearch CA and the MariaDB CA/client private keys; widened a cert's mode |
| Real `restore` | helper reported "Restore complete" 17 s after start; Koha healthy within the following polling interval; schema `26.0501000`; post-backup marker absent; pre-backup record present; 2 STOMP connections; original password accepted |
| Assets | sha256 and file modes of all 11 files identical before loss and after restore (key contents never printed) |
| OpenSearch | rebuild (`koha-elasticsearch --rebuild --reset --delete`) indexed the record; search returned 1 hit; CA restored from the archive still matched the cluster |
| Encrypted restore | archive made with `KOHA_BACKUP_GPG_RECIPIENT` (test key in a temporary keyring) restored through the helper; schema `26.0501000`, healthy |

Notes: the "failed upgrade" injected by revoking DDL privileges did not fail,
because bootstrap upgrades with the root DB credential; the failure exercised
instead is the broken rollback above. On this 91%-full host OpenSearch's disk
watermark blocked index creation until disabled for the rehearsal cluster, and
the stock OpenSearch image lacks the ICU plugin; both are rehearsal-environment
effects, not product defects. Cleanup removed the project, its three volumes,
network, the rebuilt prior image and the workspace (including the test keyring).

### Findings for the owner

- The MariaDB TLS private keys under `files-alpine/mariadb-ssl/` (including
  `ca-key.pem`, `client-key.pem`) are **tracked in git**. They are test material
  for this repository, but production must generate its own and include their
  paths in `KOHA_BACKUP_ASSET_PATHS`. Existing G0 history decision unchanged.
- Production asset inventory (real certificates, Traefik ACME data, OpenSearch
  generated certificates) is deployment-specific and must be listed by the
  owner; the mechanism is proven, the real inventory is not.
- RabbitMQ queue contents are not preserved by design; consumers must tolerate
  re-enqueued background jobs after a restore.
- RTO/RPO sign-off (recovery window ~1–2 min excluding provisioning and
  re-index; loss of all writes after the backup) belongs to G9.

**Result: G5 PASS (rehearsal)**, with the owner-dependent items above carried to
G7/G9.

## Validation and code changes

- `bash tests/test_stack_sh_static.sh`: **29 checks passed, 0 failed**.
- `bash -n stack-alpine.sh tests/test_stack_sh_static.sh`: passed.
- `git diff --check`: passed.
- Runtime archive permission and gzip-integrity assertions passed after the
  permission hardening.

The code change restricts the staged database dump and manifest to `0600` and
the staging subdirectories to `0700`; the runbook and static tests were updated
accordingly. No production data, source volume, or source container was
modified.
