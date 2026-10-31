# G5 — Backup, restore, rollback, and external-state rehearsal

**Date:** 2026-10-31  
**Branch:** `phase`  
**Result:** **PARTIAL** — database-level backup, cross-version restore, prior-image
recovery, and OpenSearch rebuild/search passed on isolated resources. This is
not full disaster-recovery acceptance or authorization for production use.

## Outcome

The G5 rehearsal used a disposable Koha `26.05.01-1` project, then ran the
`26.06.00.003` candidate against its database and restored the pre-upgrade
backup into a second project with new DB and OpenSearch volumes. A synthetic
catalogue record written before the backup returned after restore; a second
record written after the backup did not. The previous image started healthy
against the restored schema. OpenSearch was rebuilt from the restored Koha
database and returned the pre-backup record in a title search.

G5 remains **PARTIAL**. RabbitMQ volume state, generated private keys and real
host-mounted data, an intentionally failed-upgrade scenario, and the helper's
full restore command were not exercised. The built-in archive is not encrypted
and does not include those external assets.

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

The `stack-alpine.sh restore` command was not run. Its current path overwrites
host configuration and starts/stops OpenSearch and Traefik through fixed
Compose locations, so it was not safe to invoke against a second isolated
project. The database restore was performed manually from the generated
archive into the new project; it does not validate the helper's full restore
workflow.

Before G5 can pass:

1. Define and test an isolated full restore workflow that cannot touch shared
   OpenSearch, Traefik, or host-mounted paths.
2. Demonstrate recovery of RabbitMQ data or document and obtain approval for
   its exclusion.
3. Back up and restore representative real host assets, including required
   private keys/certificates, using the deployment's protected asset process.
4. Exercise recovery from a deliberately failed candidate upgrade.
5. Decide whether the measured recovery window and lost-write boundary meet
   the service owner's requirements; arrange encryption for off-host backups.

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
