# End-to-end migration acceptance gates and runbook alignment

**Date:** 2026-10-29  
**Branch:** `phase`  
**Result:** Acceptance criteria and safe rehearsal sequence defined; end-to-end migration remains not accepted.

## Assessment outcome

The Alpine implementation has substantial evidence for the recorded pinned
Koha release, including fresh development and production startup, selected API
and browser checks, supervision, health, and runtime hardening. Those results do
not demonstrate migration of an existing Ubuntu installation or full production
recovery.

This assessment does **not** declare migration complete and did not start or
modify containers, databases, or Docker volumes. It defines observable gates
that must be passed before the owner can make that declaration.

## Findings that changed the acceptance plan

### Tracked credential-capable configuration

`env/.env` is tracked and contains non-empty assignments under credential-like
keys for database, Koha, OpenSearch, Git, and TLS-related settings. The values
were not printed or independently validated. They may be examples or live
credentials; until an authorized owner determines otherwise, any value that may
have been used must be treated as exposed.

The main wrapper reads `env/.env` directly. Its
`KOHA_CONTAINER_ENV_FILE` override applies to the Koha container environment,
not every host-side read of the main file. Production readiness therefore
requires an explicit, tested secret-injection interface, safe committed example
configuration, rotation/revocation where applicable, and an owner-approved
decision on remote Git history. No credentials were changed or copied.

### Ubuntu migration and backup scope

Fresh Alpine bootstrap is not a substitute for importing and upgrading a
representative Ubuntu database copy. The prior version migration runbook used
the obsolete `stack.sh` entry point and described a general Ubuntu-to-Alpine
procedure without rehearsal evidence; it has been replaced with a runbook
grounded in the current Alpine scripts.

The current backup helper archives three environment files and a MariaDB dump.
It does not quiesce the Koha application, and it does not archive RabbitMQ
volume data, OpenSearch data, certificates/private keys, or other host assets.
Its `--single-transaction` option alone does not establish a full application
and multi-service recovery point. These boundaries are explicit gates, not
assumptions of completeness.

### Other closure evidence

The hosted GitHub Actions workflow and full hosted builds have not been run.
The recorded Phase E runtime tests do not cover a successful Z39.50 query and
result parse against a test target, nor a complete authenticated catalogue,
patron, circulation, and search workflow suite on the pinned production image.
The exact Ubuntu source data has not been rehearsed in an isolated Alpine
project; restore and rollback have not been rehearsed; and no service-owner
sign-off exists in the records reviewed.

## Work completed in this assessment

- Added [End-to-end-migration-acceptance.md](../Alpine-migration/End-to-end-migration-acceptance.md),
  with G0–G9 gates, priority/current status, exact evidence, safe execution
  boundaries, and a final decision rule.
- Replaced the stale `stack.sh` migration document with
  [koha-version-migration-runbook.md](../Alpine-migration/koha-version-migration-runbook.md),
  distinguishing fresh Alpine setup, in-place Alpine upgrades, Ubuntu data
  migration, and recovery.
- Updated the [state assessment and roadmap](../Alpine-migration/2026-10-roadmap-and-state-assessment.md)
  to say explicitly that end-to-end migration is not complete; added an
  unchecked G0–G9 closure checklist and references.
- Updated README and architecture navigation to link to the acceptance matrix.
- Marked the original fixed-version production document's future suggestions
  as historical, separated its image-level criteria from end-to-end acceptance,
  and corrected its unsupported implication that image rollback is
  straightforward.
- Strengthened the Phase F release guide to disclose the tracked-env finding
  and the required credential rotation/history decision without exposing any
  values.

## Required gates and their dependencies

The authoritative, detailed matrix is G0–G9 in
[End-to-end-migration-acceptance.md](../Alpine-migration/End-to-end-migration-acceptance.md).
The practical order is:

1. **G0:** resolve secrets/config hygiene before copying files or generating
   shared test artifacts.
2. **G1:** run the CI-independent local validation procedure and establish
   the candidate image and immutable provenance.
3. **G2–G3:** exercise Z39.50 and agreed Koha workflows on the exact candidate
   production image.
4. **G4:** use a protected, representative source copy and a new isolated
   project to rehearse actual Ubuntu database/config/assets migration.
5. **G5–G6:** establish write quiescence, back up, restore, and test rollback
   plus exact volume identity without touching production volumes.
6. **G7–G8:** close production security/operations controls and complete an
   independent operator walkthrough.
7. **G9:** obtain recorded service-owner approval of the tested release,
   scope, recovery path, and exclusions.

Do not mark checkboxes passed based on a runbook being written. Attach test run
IDs, image digest, test project/volume names, sanitized reconciliation results,
restore timings, and owner sign-off to a subsequent dated tracker record.

## Validation and safety

The work was documentation-focused. No service or container was started. No
existing or test volumes were deleted, mounted, or modified. `git diff --check` and relative Markdown links in the updated README, roadmap,
acceptance matrix, runbooks, tracker, and architecture map passed. The earlier
Phase F local tests and image syntax checks are not rerun integration evidence
for this assessment.

## Follow-up implementation — CI-independent local acceptance

The service owner subsequently confirmed that this project should not depend on
hosted CI. The hosted GitHub Actions workflow proposed in the Phase F tracker
was removed; it was not run and is not part of the project acceptance contract.
The historical Phase F tracker remains an accurate record of the proposal at
the time, but the local procedure below supersedes its hosted-workflow plan.

Implementation changes:

- Added `scripts/validate-release-local.sh`. It verifies that the local ignored
  Koha checkout matches the selected release ref, records repository/source
  identity and Docker/Compose/Buildx versions, runs `tests/run_all_tests.sh`
  with live-project integration selectors unset, validates development and
  production Compose configurations using a mode-0600 synthetic environment
  file, and builds both Koha images uncached with pulled base images. It does
  not run `docker compose up` or start a service stack.
- Updated G1 in the acceptance matrix and roadmap to require local tests,
  configuration validation, both complete image builds, source/image identity,
  and tool-version evidence instead of a hosted workflow run.
- Updated the Phase F release guide and README to document the local command
  and operator-controlled image publication.
- Added `KOHA_ENV_FILE` host-side path selection to `stack-alpine.sh` and
  `netcheck.sh`. The selected file is used for host-side configuration reads;
  the stack wrapper also selects it as the container env file unless
  `KOHA_CONTAINER_ENV_FILE` is explicitly supplied. Removed the startup-time
  rewrite of tracked `env/.env` that previously changed `SYNC_REPO`.
- Added static and Compose regression assertions for alternate environment
  file selection and the absence of startup-time tracked-file rewriting.

The owner later authorized current-worktree remediation and reports that
potentially active credentials have been rotated. Credential assignments were
cleared from tracked environment files and OpenSearch templates; existing
OpenSearch user hashes and Dashboards password material are now generated into
an ignored local-config directory. Compose no longer supplies weak database or
broker password fallbacks, and the Koha entrypoint/helper scripts now fail
explicitly when required credentials are unset. The OpenSearch setup helper
now restricts local secret files and no longer prints salts, master keys, or
password hashes. The 401 diagnostic no longer prints a prefix of the password.

G0 remains partial pending final verification and an owner-approved Git
history/remotes disposition. No credential values were copied into a new
tracked file, tracker entry, build argument, image, or test output.

At this checkpoint, the local procedure ran through the repository tests and
both Compose configuration checks: 276 passed, 0 failed, 29 expected opt-in
skips; both configurations passed. Full image builds were deliberately not
attempted because only 8.8 GiB was free on the Docker data filesystem, below
the script's 15 GiB safety threshold. The existing unrelated containers were
observed running; none was started, stopped, or modified. G1 remains pending
until the full dev/prod builds pass, as do the Z39.50, Koha workflow,
Ubuntu-data migration, backup/restore, operational readiness, independent
handoff, and owner-sign-off gates.

## Current declaration

**Alpine image implementation: substantially validated for the recorded
release. End-to-end Ubuntu-to-Alpine migration and production recovery: pending
the required rehearsals and owner approval.**

## Follow-up verification and credential-example cleanup — 2026-10-29

This addendum records the final credential-hygiene and local-validation
follow-up after the implementation described above. It does not change the
acceptance decision: end-to-end migration remains incomplete.

### Changes made

- Removed credential-like literal values from tracked historical examples in
  `9-yards.md`, `README.md`, OpenSearch documentation, Alpine migration
  documentation, tracker records, and architecture notes. Sensitive config
  keys remain documented with explicit local-generation/configuration
  placeholders. This was limited to credential-bearing examples; Git history
  and remotes were not rewritten.
- Kept tracked env files and OpenSearch authentication templates free of
  configured secrets. OpenSearch hashes and Dashboards credentials are
  generated under the ignored `OpenSearch-3.6/assets/local-config/` directory.
- Extended `tests/test_credential_hygiene_static.sh` to assert that Compose
  requires non-empty database and broker credentials, that OpenSearch mounts
  generated auth files read-only, and that setup scripts do not print secret
  material. It also checks that the OpenSearch password is passed to the hash
  container through its environment rather than interpolated into Docker CLI
  arguments. The suite checks tracked environment files and auth templates.
- Added explicit empty prefix/suffix settings to the synthetic environment
  used by `scripts/validate-release-local.sh`, removing harmless Compose
  interpolation warnings while retaining isolated validation values.

### Verification and safety

- Branch confirmed as `phase`; `bash -n` passed for the changed shell scripts
  and `git diff --check` passed.
- `tests/run_all_tests.sh`: **279 passed, 0 failed, 29 expected skips**.
- `bash scripts/validate-release-local.sh`: repository tests passed again and
  development and production Compose configuration checks passed. The script
  stopped before image builds because Docker storage had **8.7 GiB free**, below
  its explicit 15 GiB minimum. Both Compose checks emitted no missing-variable
  warnings after the synthetic environment was completed. OpenSearch Compose
  configuration also passed with the local env file; no OpenSearch services
  were started.
- A value-safe scan of tracked config and documentation found no remaining
  literal assignments under the checked credential keys; output contained
  paths/keys only, never values.
- No services were started, and no existing containers, databases, or Docker
  volumes were changed. No Docker cleanup was run.

### Remaining work

G0 remains partial until the owner records the Git history/remotes disposition
and completes final exposure/rotation verification. G1 remains pending until
both uncached image builds pass with at least 15 GiB free. Z39.50, full
authenticated Koha workflows, representative Ubuntu-data migration,
consistent backup/restore and rollback, operational handoff, and owner
sign-off remain open as recorded in the acceptance matrix.

## G1 completion — local release validation passed

After the owner freed Docker build cache (about 90 GB available), the full
`scripts/validate-release-local.sh` run completed: 279 passed, 0 failed,
29 expected skips; dev and prod Compose checks passed; both images built
uncached with `--pull`. Production image `sha256:de43d04901f3…`
(labels `26.05.01-1` / `v26.05.01-1`); dev image `sha256:c4fe71c0d5cc…`.
Built from a dirty worktree on base revision `6d4a58958b2b`; commit the
changes before treating the images as a release candidate. No Compose
services were started and no volumes were touched. G1 is PASS; G0 (history
disposition), G2–G9 remain open.

## G0 decision — Git history left unchanged

The service owner decided to leave Git history and remotes as they are and to
document the residual risk. Old commits, existing clones, forks, and the remote
may still expose former credential-capable values. The accepted mitigation is
the owner-reported rotation of all potentially active credentials; anything
reused elsewhere must also be rotated. No history rewrite, force-push, or
remote change was performed. The current tree is clean of credential literals
(value-safe scan) and covered by `tests/test_credential_hygiene_static.sh`.
G0 is PASS with this owner-accepted residual risk; revisit if exposure or
rotation status changes. G2–G9 remain open.
