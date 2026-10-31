# End-to-end Alpine migration acceptance gates

**Assessment date:** 2026-10-29

**Status updated:** 2026-10-31
**Current conclusion:** The Alpine implementation has passed substantial
fresh-install and runtime validation for Koha `v26.05.01-1`. The isolated G4
Ubuntu-data rehearsal passed on Koha `26.06.00.003` at the source commit, with
one pre-existing malformed MARCXML record documented. G5 passed as an isolated
rehearsal (database, RabbitMQ credentials/definitions, host TLS assets,
encrypted archive, failed-rollback handling, and the helper's real restore
command); production asset inventory and RTO/RPO approval remain owner items.
The overall Ubuntu-to-Alpine migration and production recovery
are **not yet accepted**; G7–G9 remain open.

**Scope clarification (owner, 2026-10-31).** The credentials in the tracked
`env/.env` and similar files are deliberately public demo/test defaults that let
anyone try this Koha stack; they are not secrets and tracking them in Git is
intentional. G7's secret-handling criteria therefore apply to a **real
production deployment**, which must use its own untracked env file
(`KOHA_ENV_FILE`) with unique credentials. The repository must not be assumed
to hold production secrets, and demo defaults must never be reused in
production.

This document defines the evidence required before declaring the migration
complete. It distinguishes a working Alpine image from a proven migration and
recoverable production operation. Statuses below describe evidence available
in the repository at the assessment date, not future commitments.

## Decision rule

Declare end-to-end migration complete only after every **Required** gate below
is `PASS`, evidence is recorded in a dated tracker entry, and the service owner
accepts any explicitly out-of-scope conditions.

`PASS` requires observed results from the stated test, not just documentation,
static assertions, `docker compose config`, or an image build. A failed gate
returns to implementation; a skipped test is not a pass. Testing must use
disposable, isolated projects and data copies. No gate authorizes testing against
production volumes.

## Acceptance matrix

| ID | Priority / current state | Closure gate | Required evidence |
|---|---|---|---|
| G0 | **Required / PASS (2026-10-29, owner-accepted residual risk)** | Credential and configuration hygiene | Inventory tracked configuration without printing values. Remove production secrets from tracked files; provide a tested ignored/external secret injection path; rotate credentials that may have been committed or shared; verify the rotation works. Confirm the Git history and remote exposure implications have an owner-approved disposition. |
| G1 | **Required / PASS (2026-10-29)** | CI-independent local release validation | Run `bash scripts/validate-release-local.sh` with the intended Koha version/ref. The local suite, both Compose configs, and full uncached dev/prod image builds must pass. Record repository revision, requested Koha ref and resolved commit, image IDs/digests, tool versions, and any mutable-base-image exception/refresh policy. This repository intentionally does not require hosted CI. |
| G2 | **Required / PASS (2026-10-30)** | Pinned release and Debian-compatibility audit | The rebuilt candidate passed a manifest/command disposition audit and Koha's configured outbound Z39.50 search path against an isolated target; YAZ/ZOOM and MARC parsing succeeded. See the dated G2 tracker addendum for image identity, exact results, overlays, cron regression, and explicit exclusions. |
| G3 | **Required / PASS (2026-10-30)** (16/16 full workflow on the earlier candidate; current G2 candidate also passed a fresh OpenSearch TLS, rebuild, MARCXML import, and OPAC-search recheck; see tracker G3 addenda 3–4) | Koha operational feature acceptance | On a fresh isolated production-mode stack, verify authenticated staff login, OPAC, catalogue search, one representative catalogue create/edit, patron lookup, a controlled checkout/checkin, and a background job. If OpenSearch is enabled, verify cluster/auth health, index build or rebuild, and a Koha search returning expected records. Include MARC import if it is part of the deployment's required operations. Record screenshots/log identifiers and test data cleanup. |
| G4 | **Required / PASS (2026-10-30; source-data caveat recorded)** | Existing Ubuntu-data migration rehearsal | A protected, transaction-consistent source copy was imported into a verified-isolated project and started with explicit existing-data settings on an Alpine image built from the exact source Koha commit. Schema and baseline counts reconciled; staff/API authentication, patron lookup, MARC import/edit, checkout/checkin, background indexing, TLS, and migrated-record search passed. One malformed MARCXML row was present in both source and target and is documented as a pre-existing data-quality limitation. See the [G4 tracker record](../TRACKER/2026-10-30%20%E2%80%94%20G4%20Ubuntu-data%20migration%20rehearsal.md). |
| G5 | **Required / PASS - rehearsal (2026-10-31)** | Backup consistency, restore, and rollback rehearsal | With Koha stopped, the real helper backed up the DB, RabbitMQ definitions and host TLS assets (optionally GPG-encrypted). After a candidate upgrade, broker-password rotation and asset loss, the helper's real `restore` returned the prior image healthy at schema `26.0501000`, post-backup write absent, STOMP reconnected with the original credentials, assets sha256- and mode-identical, and OpenSearch rebuilt. The RabbitMQ "keys" root cause (data keyed by random container hostname; credentials only seeded into an empty broker) was fixed. Owner items: production asset inventory and RTO/RPO sign-off (G7/G9). See the [G5 tracker record](../TRACKER/2026-10-31%20%E2%80%94%20G5%20backup%20and%20recovery%20rehearsal.md). |
| G6 | **Required / PASS - rehearsal (2026-10-31)** | Volume identity and cutover safety | For an existing deployment, identify the exact current Compose project name and its database/RabbitMQ volumes. Configure `KOHA_PROD_PROJECT` to that exact project before an in-place upgrade, or document and rehearse a separate copy/restore migration. Verify the selected volume names before start and after start. Demonstrate that the fresh-start path cannot accidentally reset the migrated database. Evidence: [G6 record](../TRACKER/2026-10-31%20%E2%80%94%20G6%20volume%20identity%20and%20cutover%20rehearsal.md). The same image was reused for both "versions" (naming, not upgrade, was under test). |
| G7 | **Required / PARTIAL** | Security and operations readiness | Confirm production secrets are outside Git and not present in build args, labels, or logs; validate TLS trust and client authentication on actual endpoints; check file permissions/capabilities and container health; verify monitoring, log retention, alert ownership, capacity, and restore access. Review base/service image update ownership and pinning policy. Record which host assets and external services are independently protected.Audit 2026-10-31 (see [G7 record](../TRACKER/2026-10-31%20%E2%80%94%20G7%20security%20and%20operations%20audit.md)): demo-credential guard, banner masking and image secret scan done; Koha-to-DB TLS cannot be enforced with the current `DBD::mysql`; owner items remain. |
| G8 | **Required / PARTIAL** | Documentation and operator handoff | Replace obsolete `stack.sh` runbook commands and unsupported safety claims; link the acceptance, release, and recovery procedures from the README and roadmap. An operator who did not implement the migration must complete a tabletop walkthrough and confirm commands, volume identity, secret handling, escalation, and rollback steps. |
| G9 | **Required / NOT SIGNED OFF** | Final migration decision | Service owner signs the tested release/ref/digest, feature scope, known limitations, migration/restore evidence, maintenance and rollback window, and decision to proceed. No declaration is made by this checklist alone. |

`PARTIAL` means related component tests exist, but the stated end-to-end acceptance
has not been demonstrated. In particular, fresh Alpine database bootstrap and
restart tests do not satisfy G4.

## Gate details and safe execution order

### 1. Secure the test inputs first (G0)

The repository tracked environment files and OpenSearch auth configuration
with credential-capable values. Their values were not repeated here. The owner
reports potentially active credentials have been rotated. The current worktree
clears credential values from tracked env files, OpenSearch auth templates,
and credential-bearing historical documentation examples; old commits/remotes
may still retain former values. The owner must record whether history
rewriting, remote cleanup, or another disposition is required.

Before creating test copies:

1. Determine which credentials have ever been valid or shared; rotate those
   credentials and revoke old keys/certificates where possible.
2. Decide whether exposed Git history/remotes require history remediation in
   addition to rotation. Do not rewrite shared history without an owner-approved
   plan.
3. Keep committed example configuration non-sensitive. Use an ignored,
   access-controlled local file or a host secret manager for real values.
4. `stack-alpine.sh` and `netcheck.sh` now accept `KOHA_ENV_FILE` as a
   host-side override, defaulting to `env/.env`; the stack wrapper also passes
   the selected file to Compose as the Koha container env file unless
   `KOHA_CONTAINER_ENV_FILE` is explicitly set. Keep real credentials in an
   ignored, access-controlled file. The path is covered by static and Compose
   regression tests; never use the tracked default for production.
5. Run `git grep` and inspect the staged diff without printing secret values;
   verify no credentials appear in CI artifacts, image metadata, build logs, or
   tracker records.

Do not copy the tracked file into a ticket, CI artifact, or shared backup while
investigating it.

### 2. Establish the exact release and local validation result (G1–G2)

Select one Koha release tag or full commit SHA and resolve it to a commit. Keep
the image tag immutable and record its digest. The current recorded runtime
evidence is for Koha `v26.05.01-1`; it does not automatically certify a later
release or changes currently present in the worktree.

Run `bash scripts/validate-release-local.sh` on the intended checkout. It
checks the selected source ref against the local `koha/` checkout, runs the
non-project test suite, validates both Compose configurations, and performs
full uncached dev and production builds without starting stack services. Record
the exact repository revision, Koha commit, image IDs/digests, and Docker,
Compose, and Buildx versions. The local script is the project's repeatable
acceptance path; hosted CI is intentionally not required.

After local validation passes, run the production image in an isolated project
with newly verified-absent project volumes. Test Z39.50 through Koha's actual
configured interface, not only `ldd`, installed packages, or module loading. A
passing acceptance query must connect to a controlled test Z39.50 server,
execute a query, parse at least one result, and leave an auditable success
record. If a suitable test target is unavailable, the gate remains open; do
not silently waive it.

**G2 evidence (2026-10-30):** The candidate image was rebuilt as
`koha-alpine-acceptance:26.05.01-1-g2` from Koha
`dacce7d3fc15860d26d06444c1f5c9a2d0d6a4a9`. The controlled test queried
Koha's own configured `z3950servers` entry through
`C4::Breeding::Z3950Search` (the function used by
`cataloguing/z3950_search.pl`), parsed 20 first-page MARC records, and found
the expected title. A direct ZOOM query also returned 23 hits and parsed the
same record. YAZ 5.34.0 and `Net::Z3950::ZOOM` loaded from the production
image. The detailed compatibility audit, image ID, sanitized server log, and
scope exclusions are recorded in the dated G2 tracker addendum.

### 3. Prove critical Koha workflows (G3)

Agree on the production feature scope before testing. Use disposable
institutions, staff/patron accounts, and records. At minimum:

- authenticate through the staff UI;
- search in OPAC and staff;
- create or edit one catalogue record and verify it persists;
- find a test patron and perform a controlled checkout/checkin;
- submit and observe one real background job;
- when OpenSearch is part of the deployment, verify auth/cluster status,
  indexing, and expected search results.

Capture expected and actual outcomes, response status, logs, test release
digest, and cleanup. An HTTP 200 on the landing pages is only a readiness check,
not feature acceptance.

### 4. Rehearse migration from Ubuntu (G4)

This must use an owner-approved data copy with sensitive data removed or
protected. The source remains untouched. Prepare a dedicated project name,
distinct ports, isolated network, and verified-absent target volumes. Record
the exact volume names before starting.

The [migration and upgrade runbook](./koha-version-migration-runbook.md) records
the rehearsed export/import and configuration-reconciliation approach. Do not
assume that the Alpine `stack-alpine.sh restore` command is a general Ubuntu
migration tool: it restores this repository's three env files and a MariaDB
dump, then starts this stack.

Compare source and destination using agreed integrity checks, including Koha
schema version, key row counts, permissions, and critical workflow outcomes.
Test the actual production image with its source mount absent. Avoid recording
patron identifiers or credentials in the tracker. Capture deviations and
repeat the rehearsal after fixing them.

### 5. Prove backup and recovery (G5–G6)

The backup helper copies three env files, runs a MariaDB dump using
`--single-transaction`, exports RabbitMQ definitions, and archives the host
paths listed in `KOHA_BACKUP_ASSET_PATHS`; with `KOHA_BACKUP_GPG_RECIPIENT` it
encrypts the result. It does not stop or quiesce Koha itself (stop Koha first),
and it deliberately excludes OpenSearch data (rebuild it) and RabbitMQ queue
contents (transient). The production asset list is deployment-specific: until
the owner has listed the real certificates/keys, do not describe the archive as
a complete production backup. After any restore, confirm STOMP connections
(`rabbitmqctl list_stomp_connections`); the Koha health check does not detect a
broker outage.

Define whether production writes are paused, application services stopped, or
another database-consistent method is used during backup. Preserve a matching
release image and digest. Restore to a disposable project and separate volumes;
verify the active project and volume names explicitly. Test both a database
restore and the independent recovery of external assets. Measure the recovery
time and identify data written after the backup that would be lost.

For versioned project names, changing Koha version changes volume selection by
default. `KOHA_PROD_PROJECT` can keep project name stable across Koha releases,
but only if set to the exact existing project name. If the upgrade has already
altered the database schema, image-only rollback is not accepted; restore the
pre-upgrade database and matching release configuration/image.

### 6. Close operator documentation and decide (G8–G9)

The operator handoff must distinguish:

- tested image build and fresh-install behavior;
- in-place Alpine version upgrade;
- one-time Ubuntu-to-Alpine migration;
- database restore and full disaster recovery.

These are separate procedures with separate evidence. A successful image build
or fresh Alpine bootstrap cannot be used as evidence for the latter three.
Record open limitations and the operator/service owner's explicit scope
acceptance in the final tracker entry.

## Current open-gate summary

As of 2026-10-31:

- **Available evidence:** Phase B/E pinned-image and fresh-stack results;
  selected Plack/API/browser checks; lifecycle, worker, cron, broker,
  capability, permission, and health checks; latest local tests (292 passed,
  0 failed, 29 expected opt-in skips); current dev/prod Compose config checks;
  Dockerfile `buildx --check`; the isolated G4 Ubuntu-data rehearsal; and the
  partial G5 database restore/OpenSearch rebuild. The local release procedure
  repeated the tests and both Compose checks successfully.
- **G1 evidence (2026-10-29):** `scripts/validate-release-local.sh` passed end to
  end after storage was freed: 279 tests passed/0 failed/29 expected skips, both
  Compose configs, and uncached `--pull` builds of both images. Koha
  `v26.05.01-1` resolved to `dacce7d3fc15860d26d06444c1f5c9a2d0d6a4a9`;
  repository base revision `6d4a58958b2b` with a dirty worktree (uncommitted
  changes). Dev image `sha256:c4fe71c0d5cc…` (2.5 GB); production image
  `sha256:de43d04901f3…` (2.0 GB, labels version `26.05.01-1`, revision
  `v26.05.01-1`). Docker 28.1.1, Compose 2.35.1, Buildx 0.23.0. Images are
  local only (not digests from a registry); record a committed revision before
  release.
- **G2 evidence (2026-10-30):** configured Koha Z39.50 query/result parsing and
  Debian compatibility audit passed on a fresh isolated production candidate;
  see the G2 tracker addendum.
- **G4 evidence (2026-10-30):** the imported Ubuntu database started on the
  production image built from source commit
  `c355bb8574f62e4a04e774a65a6385feb9b858b0`. Baseline schema and row counts
  matched. Staff authentication, patron lookup, MARC import/edit,
  checkout/checkin, broker-backed indexing, MariaDB/OpenSearch TLS, and OPAC
  search passed. One malformed MARCXML row and associated indexer diagnostics
  were already present in the source data; see the dated G4 tracker record.
- **G5 evidence (2026-10-31, PASS as rehearsal):** a quiesced helper backup
  (DB, RabbitMQ definitions, host assets, optional GPG encryption) was followed
  by a candidate upgrade to schema `26.0600003`, a rotated broker password and
  deleted TLS assets. The helper's real `restore` returned the `26.05.01-1`
  image healthy at `26.0501000` with the post-backup write absent, STOMP
  reconnected, and assets identical by sha256 and mode; OpenSearch was rebuilt.
  Pinning the RabbitMQ hostname fixed a defect where each container recreation
  started an empty broker. Owner items remain: production asset inventory and
  RTO/RPO sign-off. See the dated G5 tracker record.
- **Still not demonstrated:** production asset inventory recovery, production
  cutover, and final service-owner sign-off. G2, G3, G4, and G5 have separate
  dated PASS evidence (G5 as an isolated rehearsal).
- **G0 decision (2026-10-29):** the owner chose to leave Git history and
  remotes unchanged (no rewrite) and to document the residual risk: former
  credential-capable values remain retrievable from old commits, clones, forks,
  and the remote. Mitigation relies on the owner-reported rotation of all
  potentially active credentials; any credential reused elsewhere must also be
  rotated. History is not rewritten; revisit if the repository's exposure or
  rotation status changes.
- **Former blocker (resolved by the decision above):** disposition of historical
  Git/remotes and final G0 verification. Current tracked env/auth templates and documentation
  examples have been scrubbed; a tracked-file scan found no remaining literal
  values for the credential keys checked. The owner reports rotation is
  complete. The external env path is tested.
- **Documentation blocker:** the older migration runbook must not be used until
  it is aligned with the Alpine scripts and truthful about backup scope. The
  revised runbook is linked from the roadmap.

## Explicitly conditional gates

These are mandatory if they are part of the service's agreed production scope:

- High availability, multi-host failover, horizontal scaling, and load testing.
- Defined capacity/latency/availability objectives and alert thresholds.
- OpenSearch snapshot restore if search data cannot be rebuilt within the
  accepted recovery window.
- Multi-language and local authority/Z39.50 endpoints beyond the single
  representative acceptance server.

If excluded, document the exclusion, operational consequence, and owner
approval; do not represent the excluded capability as tested.
