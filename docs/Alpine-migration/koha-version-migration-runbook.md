# Koha Migration and Upgrade Runbook

This repository's active orchestration is `stack-alpine.sh`, with
`docker-compose-alpinekoha.yml` and `docker-compose.prod.yml`. This runbook
supersedes older `stack.sh` examples.

**Important:** upgrading an Alpine installation and migrating an existing
Ubuntu installation are different operations. Neither should be attempted in
production until the acceptance gates in
[End-to-end migration acceptance](./End-to-end-migration-acceptance.md) have
passed for the target release.

## Choose the procedure

| Operation | Procedure |
|---|---|
| Build/start a fresh Alpine test environment | [README Quick Start](../../README.md) using an explicitly isolated Compose project and synthetic env. |
| Upgrade an existing Alpine production instance | [Phase F release, backup, and rollback guide](./Phase-F-release-operations.md). |
| Migrate a real existing Ubuntu Koha database to Alpine | First complete the isolated rehearsal described under [G4](./End-to-end-migration-acceptance.md#g4-rehearse-migration-from-ubuntu-g4). This runbook does not authorize direct production migration. |
| Restore or rehearse disaster recovery | Complete G5/G6 in the acceptance gates and use the Phase F guide; the built-in archive is not a full-volume backup. |

## Non-negotiable safety controls

1. Never point a rehearsal at production containers, project names, networks, or
   volumes. Use a protected data copy, unique project name, dedicated ports,
   and verified-absent named volumes.
2. Do not use `stack-alpine.sh reset`, `docker compose down -v`, or volume-prune
   commands during upgrade, migration, or restore.
3. Verify `KOHA_PROD_PROJECT` and the actual DB/RabbitMQ volume names before
   every start. The default production project name changes with Koha version.
4. Do not use the fresh-database default for an existing database. Existing-data
   starts require `--no-fresh-db`; this flag does not by itself prove a
   cross-distribution migration is safe.
5. Preserve the source environment and database until migration and rollback
   acceptance are complete.
6. Treat environment files and backup archives as secrets. Do not put real
   credentials in tracked `env/.env`.

## Phase A — Scope and record source state

Before any rehearsal:

- Record source Koha version/ref, image digest, OS/container versions, MariaDB
  version, instance name, enabled integrations, and source Compose project.
- Inventory the database and non-database state required by this installation:
  configuration, attachments, TLS material, RabbitMQ state, OpenSearch
  indexes/snapshots, custom templates/plugins, and host-mounted files.
- Agree on feature acceptance, maintenance window, maximum recovery time, and
  acceptable data-loss window.
- Confirm backup credentials and all recovery material are available to the
  authorized operator.
- Resolve the credential hygiene gate before copying configs or placing any
  secrets in CI or shared artifacts.

## Phase B — Prepare an isolated rehearsal

1. Create a dedicated test host or isolated project with unique ports and
   network. Confirm the intended project-scoped DB and RabbitMQ volumes do not
   exist; record their exact names.
2. Make a protected copy of the source database using an owner-approved,
   database-consistent export procedure. Do not modify the source installation.
3. Sanitize personal data when feasible while preserving representative Koha
   schema and workflow relationships. Protect unsanitized copies as production
   data.
4. Build the exact pinned production image and record its digest, requested
   Koha ref, resolved source commit, base image versions, and build logs.
5. Stage required environment/configuration and non-database assets separately.
   Do not assume the repository backup archive contains them.

## Phase C — Import and start the Alpine target

The Ubuntu-to-Alpine method must be written and reviewed based on the rehearsal.
Do not assume `stack-alpine.sh restore` can migrate an Ubuntu environment:
that command restores this repository's env files and a MariaDB dump, resets
the configured database, and starts the Alpine stack.

For an existing Alpine database during a planned version upgrade, use the
supported production procedure in the Phase F guide. For the one-time Ubuntu
migration rehearsal, the operator procedure must explicitly specify:

- how the copied database is created/imported into the isolated Alpine
  MariaDB service;
- how DB credentials, privileges, TLS certificates, and Koha config are
  reconciled;
- how required host files and external-service state are restored;
- how the exact target project and volumes are selected; and
- how Koha schema upgrade is triggered and monitored.

Start the target only after confirming the isolated project, target image
digest, environment, and volumes. For a populated DB, use the existing-data
startup behavior; do not run a fresh bootstrap or reset. Record logs and stop
the test if the schema-upgrade path is ambiguous or destructive.

## Phase D — Acceptance checks

Complete and record every required check in the
[acceptance matrix](./End-to-end-migration-acceptance.md):

- database readiness, expected Koha schema version, and agreed data
  reconciliation queries;
- staff authentication and OPAC access;
- catalogue search, create/edit, patron lookup, controlled circulation;
- background worker and broker behavior;
- OpenSearch auth/health/index/search when enabled;
- Z39.50 query and result parsing on the pinned production image;
- TLS verification and expected access restrictions;
- startup health, logs, restart, and graceful shutdown.

HTTP 200 on the home pages or a successful fresh bootstrap does not satisfy
these checks.

## Phase E — Backup, restore, and rollback rehearsal

Use the Phase F release guide and acceptance G5/G6. Before accepting recovery:

- test whether writes must be paused to obtain an application-consistent backup;
- restore the database and matching release configuration to separate test
  volumes;
- independently recover RabbitMQ, OpenSearch if required, certificates/private
  keys, and host-mounted files omitted from the built-in archive;
- restore/start the previous image and verify its DB compatibility;
- record recovery duration, lost-write boundary, and any manual steps.

Do not perform an image-only rollback after a database schema upgrade unless
that exact compatibility has separately been established and accepted.

## Evidence and close-out

Attach to the dated tracker record:

- source and target release/ref/digest and resolved Koha commit;
- test project name and DB/RabbitMQ volume names (never credentials);
- sanitized backup/export provenance and integrity checks;
- build/CI run identifiers, logs, workflow results, test cases and outcomes;
- before/after database reconciliation and feature acceptance results;
- restore/rollback results, recovery duration, and unresolved limitations;
- service owner decision and explicit scope exclusions.

End-to-end migration is complete only when all required gates pass. Until then,
the accepted statement is: **Alpine image implementation is validated for the
recorded release; migration of an existing Ubuntu installation and production
recovery are pending rehearsal and owner approval.**

## Operator execution record

- Date / UTC:
- Operator:
- Source Koha version / image digest:
- Target Koha ref / resolved commit / image digest:
- Isolated project name:
- Isolated DB and RabbitMQ volume names:
- Backup/export reference (no secrets):
- CI run reference:
- Feature test results:
- Z39.50 endpoint/result:
- Restore/rollback result and recovery duration:
- Unresolved deviations:
- Owner sign-off:
