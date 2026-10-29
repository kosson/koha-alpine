# End-to-end Alpine migration acceptance gates

**Assessment date:** 2026-10-29  
**Current conclusion:** The Alpine implementation has passed substantial fresh-install
and runtime validation for Koha `v26.05.01-1`. The end-to-end migration from an
existing Ubuntu deployment is **not yet accepted**.

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
| G2 | **Required / PARTIAL** | Pinned release and Debian-compatibility audit | Build and run the exact candidate production image, not just `buildx --check`. Reconcile the runtime entries in Koha's Debian install manifest and the commands used by entrypoint, cron, and supported operator procedures; classify required commands as Alpine override, verified upstream-compatible, or intentionally excluded, with no unexplained required gaps. Reconfirm overlay precedence, Perl/native libraries, and production `PATH`. Exercise YAZ/ZOOM by completing a controlled Z39.50 query against a test target, including result parsing; record library versions and logs. |
| G3 | **Required / PARTIAL** | Koha operational feature acceptance | On a fresh isolated production-mode stack, verify authenticated staff login, OPAC, catalogue search, one representative catalogue create/edit, patron lookup, a controlled checkout/checkin, and a background job. If OpenSearch is enabled, verify cluster/auth health, index build or rebuild, and a Koha search returning expected records. Include MARC import if it is part of the deployment's required operations. Record screenshots/log identifiers and test data cleanup. |
| G4 | **Required / NOT RUN** | Existing Ubuntu-data migration rehearsal | Create a protected, recoverable copy of a representative source installation. In a separate disposable host or isolated project, migrate its logical Koha database and required configuration/assets using the approved procedure. Run Alpine startup with explicit existing-database behavior; verify schema upgrade, record/patron counts or agreed integrity queries, staff authentication, G3 workflows, background jobs, TLS, and enabled search. Record source/target Koha versions, database versions, duration, deviations, and before/after reconciliation. |
| G5 | **Required / NOT RUN** | Backup consistency, restore, and rollback rehearsal | Establish an application write-quiescence/maintenance procedure and test a backup while respecting the actual helper behavior. Restore into separate empty test volumes, not production. Verify database integrity, expected application state, the previous image, and all required external assets. Simulate a failed upgrade and demonstrate restoration of the pre-upgrade DB/config plus recovery of excluded RabbitMQ, OpenSearch, certificates, and host files. Record recovery time and data-loss point. |
| G6 | **Required / PARTIAL** | Volume identity and cutover safety | For an existing deployment, identify the exact current Compose project name and its database/RabbitMQ volumes. Configure `KOHA_PROD_PROJECT` to that exact project before an in-place upgrade, or document and rehearse a separate copy/restore migration. Verify the selected volume names before start and after start. Demonstrate that the fresh-start path cannot accidentally reset the migrated database. |
| G7 | **Required / PARTIAL** | Security and operations readiness | Confirm production secrets are outside Git and not present in build args, labels, or logs; validate TLS trust and client authentication on actual endpoints; check file permissions/capabilities and container health; verify monitoring, log retention, alert ownership, capacity, and restore access. Review base/service image update ownership and pinning policy. Record which host assets and external services are independently protected. |
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

Document how the source DB is exported, how Koha configuration and any required
attachments/assets are carried over, how DB users/privileges/TLS are recreated,
and how target Koha performs its schema upgrade. Do not assume that the Alpine
`stack-alpine.sh restore` command is a general Ubuntu migration tool: it restores
this repository's three env files and a MariaDB dump, then starts this stack.

Compare source and destination using agreed integrity checks, including Koha
schema version, key row counts, sample record/patron IDs, permissions, and
critical workflow outcomes. Test the actual production image with its source
mount absent. Capture deviations and repeat the rehearsal after fixing them.

### 5. Prove backup and recovery (G5–G6)

The current backup helper copies three env files and runs a MariaDB dump using
`--single-transaction`; it does not stop or quiesce Koha. It does not archive
RabbitMQ's named volume, OpenSearch data, generated certificates/private keys,
or other host assets. The archive is not encrypted by the helper. Until
consistency and excluded-state recovery are tested, do not describe it as a
complete production backup.

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

As of 2026-10-29:

- **Available evidence:** Phase B/E pinned-image and fresh-stack results;
  selected Plack/API/browser checks; lifecycle, worker, cron, broker,
  capability, permission, and health checks; latest local tests (279 passed,
  0 failed, 29 expected opt-in skips); current dev/prod Compose config checks;
  Dockerfile `buildx --check`. The local release procedure repeated the tests
  and both Compose checks successfully.
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
- **Not yet demonstrated:** Z39.50 end-to-end query against a test server; core authenticated
  Koha workflow suite on the pinned production image; migration from an Ubuntu
  data copy; consistent backup and restore; full recovery including excluded
  assets; final service-owner sign-off.
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
