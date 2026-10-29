# Phase F — CI, release operations, and architecture alignment

**Date:** 2026-10-29  
**Branch:** `phase`  
**Result:** Phase F implementation completed; hosted workflow execution and a disposable restore rehearsal remain validation gates.

## Scope and outcome

Phase F establishes repeatable CI checks for the development and pinned production
Compose targets, documents a cautious production release and recovery process,
and clarifies which architecture notes describe the current Alpine runtime.
Repository tests, local Compose config validation, Dockerfile build checks, YAML
parsing, and patch whitespace checks passed.

No containers or Docker Compose projects were started for this phase. No
database, RabbitMQ, OpenSearch, or other volumes were modified. The new GitHub
Actions workflow has not yet been executed by GitHub, full image builds were not
repeated locally, and restore/rollback was not rehearsed against a disposable
stack. Production readiness still requires those operational validation steps.

## Changes and issues addressed

### GitHub Actions validation

Added `.github/workflows/alpine.yml`:

- Runs `tests/run_all_tests.sh` with no implicit integration project selected.
- Validates the development and production Compose configurations using a
  generated, non-secret environment file.
- Builds both Compose targets with Koha release `v26.05.01-1`.
- Clones the pinned Koha source into the ignored `koha/` build-context directory
  for the development target. The production Dockerfile independently fetches
  its pinned source ref.
- Uses repository read-only permissions. It does not publish images, use
  registry credentials, or request deployment secrets.
- Serializes target image builds to limit resource and network pressure on
  hosted runners.

This addresses the missing CI workflow and the fact that the Koha source tree is
ignored rather than checked into this repository. The production Compose overlay
uses the `!override` tag, so the workflow depends on modern Docker Compose.

Added `.dockerignore` to keep docs, tests, local services, backups, generated
TLS files, local environment files, caches, and Git metadata out of the Docker
build context. The production build fetches its own source; the development
runtime receives its live source through the host bind mount.

### Stable production Compose project support

`stack-alpine.sh` previously derived production project names from the selected
Koha version. Since the database and RabbitMQ volumes are project-scoped, a
release change could silently select a new, empty volume pair and make an
upgrade look like a new deployment.

The script now accepts optional `KOHA_PROD_PROJECT` configuration:

- If set, it uses the supplied project name across releases and validates it
  against Docker Compose's lower-case project-name character rules.
- If unset, existing behavior is preserved: production continues to use the
  version-derived `koha-prod-<version-slug>` name.
- Runtime configuration reloads the setting so backup/restore and other
  reloaded commands continue using the configured project.
- Help text explains the option.

`tests/test_stack_sh_static.sh` now checks that the stable override is selected,
validated, reloaded, and does not remove the version-specific default.

For an existing deployment, the configured stable name must equal the exact
current project name to reuse its current volumes. Choosing a new name selects
different volumes; the guide warns against guessing or changing it during a
release.

### Release, secrets, backup, and rollback documentation

Added `docs/Alpine-migration/Phase-F-release-operations.md` with:

- The CI workflow's pinned refs, job scope, and no-publish/security boundaries.
- Koha source URL, requested-ref labels, resolved revision files, and image
  digest recording.
- Stable Compose project naming and the effect of project-scoped data volumes.
- Production build, backup, deployment, validation, rollback, and restore
  rehearsal steps.
- A warning not to roll back only the application image after a database schema
  upgrade.
- An exact inventory of backup-helper coverage: environment files and MariaDB
  dump are included, but RabbitMQ volumes, OpenSearch data, certificates/private
  keys, and other host-mounted assets are not.

The documentation explicitly identifies a repository configuration hygiene
limitation: `env/.env` is currently tracked and is read by `stack-alpine.sh`.
It must remain non-sensitive in Git. Production credentials must not be staged
or committed; the current wrapper does not provide a general alternate path for
its main environment file. Backup archives also contain plaintext environment
files and therefore require encryption and access control.

Updated README production guidance to point to the safer release guide and
removed the previous image-only rollback example, which did not account for
schema compatibility or the version-specific project volume behavior.

### Architecture documentation alignment

Added `docs/architecture/18 - Alpine Runtime Architecture.md` as the current
architecture entry point. It records the actual Alpine 3.20 default, dev/prod
image distinction, container services, direct Koha ports 8080/8081, production
source provenance, project-scoped MariaDB/RabbitMQ volumes, runtime health, and
backup boundaries.

Updated the architecture map of content and marked pages 01–17 as historical
Ubuntu-era references so stale images, service sets, bind mounts, capability
settings, ports, and commands are not mistaken for Alpine behavior.

Updated README architecture and version sections to remove obsolete Alpine
3.24.1 assertions, old build-stage/package descriptions, and a stale rollback
recipe. README now links to the current architecture and Phase F operations
guide. The runtime base version is read from the Dockerfile default, not inferred
from the older docs.

Updated `docs/Alpine-migration/2026-10-roadmap-and-state-assessment.md` with
Phase F implementation status and links to this tracker and the release guide.

## Validation evidence

| Check | Result |
|---|---|
| `bash tests/run_all_tests.sh` | **268 passed, 0 failed, 29 skipped**. Skips are opt-in integration checks that require an explicitly selected running project. |
| `bash -n stack-alpine.sh` | Passed. |
| Development and production `docker compose ... config --quiet` using a synthetic non-secret env file | Passed for both configurations. No services were started. |
| `docker buildx build --check -f Dockerfile-Alpine --target dev-runtime .` | Passed with no warnings. |
| `docker buildx build --check -f Dockerfile-Alpine --target prod-runtime .` | Passed with no warnings. |
| Ruby Psych parse of `.github/workflows/alpine.yml` | Passed. |
| `git diff --check` | Passed after all changes. |

The local test run did not select a live test project, so its higher skip count
is expected and does not reproduce the prior Phase E runtime integration
evidence. The new CI workflow will perform full image builds after it is run on
GitHub.

## Files changed

- `.github/workflows/alpine.yml` — added CI workflow.
- `.dockerignore` — excluded irrelevant and potentially sensitive build context.
- `stack-alpine.sh` — added optional validated stable production project naming.
- `tests/test_stack_sh_static.sh` — added checks for stable project selection,
  validation, reload, and existing default.
- `docs/Alpine-migration/Phase-F-release-operations.md` — added CI, release,
  secrets, backup, rollback, and rehearsal guide.
- `docs/Alpine-migration/2026-10-roadmap-and-state-assessment.md` — updated
  Phase F status and references.
- `docs/architecture/00 - MOC - Map of Content.md` — established the current
  Alpine architecture entry point.
- `docs/architecture/01 - Architecture Overview.md` through
  `docs/architecture/17 - Perl Integration in Koha.md` — labeled legacy pages
  and pointed to the current implementation where appropriate.
- `docs/architecture/18 - Alpine Runtime Architecture.md` — added the current
  Alpine architecture description.
- `README.md` — corrected stale runtime/version details and linked current
  architecture and release procedures.

## Remaining validation gates

1. Run the GitHub Actions workflow and confirm both full builds and the test job
   pass on the hosted runner.
2. Rehearse the documented backup and restore with a disposable project and
   distinct volumes; do not use production volumes for the rehearsal.
3. Decide whether to replace the tracked `env/.env` workflow with an explicit
   external-secret-file interface in a separate, carefully tested change.
4. Do not treat the documentation as proof of schema rollback compatibility:
   validate the actual Koha upgrade and recovery path before production use.

## Follow-up decision — local validation, no hosted CI

After this Phase F record, the service owner explicitly chose to keep the
project independent of CI tooling. The GitHub Actions workflow described above
was removed without being run. Its hosted-build gates are superseded by
`scripts/validate-release-local.sh`, documented in
`docs/Alpine-migration/Phase-F-release-operations.md` and the end-to-end
acceptance matrix. This is a policy change, not a claim that the historical
workflow executed or that the remaining acceptance gates have passed.

The local release script now provides test execution, dev/prod Compose
configuration validation, and full uncached builds from an exact local Koha
release checkout. That script has not yet been run; the full builds and
disposable restore rehearsal remain pending.
