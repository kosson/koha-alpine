# Phase E — Runtime reduction and production validation

**Date:** 2026-10-28  
**Branch:** `phase`  
**Result:** Phase E exit gate passed against freshly built development and pinned production images.

## Scope and outcome

Phase E reduced the production runtime, tightened filesystem and Linux capability permissions, made required startup failures visible, and verified the resulting images in separate Docker projects. Both test projects used new project-scoped MariaDB and RabbitMQ volumes; neither reused the default deployment's volumes. The projects were stopped with ordinary `docker compose down`, without `-v`, and all four test volumes were retained.

## Changes and issues addressed

### `Dockerfile-Alpine`

- Removed Node.js/npm/Yarn, Git, Perl CPAN build utilities, `perl-local-lib`, and MariaDB development headers from the shared/final runtime package layers. The frontend toolchain remains in the development target, and Perl build dependencies remain in builder stages.
- Narrowed runtime file staging instead of copying the complete `files-alpine` tree. Only files needed at runtime are retained; Alpine command overlays and build helpers are exposed through transient BuildKit mounts during image construction. Development-only helper trees are copied only into `dev-runtime`.
- Kept the production target's Koha source and Perl dependencies aligned to the same pinned upstream source, while retaining the resolved source revision, requested ref, and URL as image metadata files.
- Added `/usr/local/sbin`, `/usr/sbin`, and `/sbin` to the production `PATH`. The production runtime audit found that `koha-shell` was installed but inaccessible through `PATH`; adding the system command directories restored access to staged Koha administration commands.

### `docker-compose-alpinekoha.yml` and `docker-compose.prod.yml`

- Replaced `cap_add: ALL` with `cap_drop: ALL` and the explicit allowlist `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `KILL`, `NET_BIND_SERVICE`, `SETGID`, and `SETUID`.
- Added a healthcheck requiring Plack status, the Plack socket, and local HTTP responses from both OPAC and staff endpoints. Retained the 60-second graceful-stop window.
- Preserved production Compose's required release ref/version and its replacement of development source mounts. The merged production config was verified to mount neither `/kohadevbox/koha` nor the development source checkout.

### `files-alpine/run.sh` and `files-alpine/lib/run-sh-alpine.sh`

- Tightened ownership and modes for Koha config, cache, log, run, upload, and temporary paths. Plack's socket is group-scoped rather than world-writable.
- Wired secure MySQL client configuration generation into early startup. Generated `/etc/mysql/koha-common.cnf`, `/etc/mysql/debian.cnf`, and the instance client file are root-owned and mode `0600`; the helper uses `DB_HOST` and the configured root credential variable.
- Made schema inspection, initial admin creation, required Plack/worker/Apache/crond startup, and required asset builds fail explicitly. Watchdog restart failures are logged rather than treated as success.
- Corrected the `bootstrap_koha_instance` helper to pass the entrypoint's defined `DB_PASS` variable instead of the undefined `DB_PASSWORD` name.
- Preserved optional profile/service behavior while ensuring required services cannot silently fail into a healthy-looking startup.

### `files-alpine/scripts/koha-plack`

- Applied a restrictive umask and changed the Plack socket to `0660` with the shared Koha/Apache group. This allows Apache access without granting world write access.

### `files-alpine/scripts/koha-create` and its guardrail

- The live guardrail found that an empty optional `CLO_CONFIGFILE` reached the POSIX `.` builtin and caused the script to exit with status 2 when no `--configfile` was supplied. The script now sources a config only when a non-empty readable path is provided.
- Updated `tests/test_phase4_koha_create_rewrite.sh` to test the current behavior accurately: the entrypoint renders its own Koha configuration rather than invoking `koha-create` during normal startup, so the test invokes `koha-create --use-db` explicitly before checking the generated `/etc/koha/passwd` entry.
- The test now supplies the in-container DB and broker values and captures a non-zero command result without `set -e` aborting before reporting it.

### Tests and documentation

- Updated Compose isolation, package-stage, build-staging, startup, run-script, Phase 4, and Phase 5 assertions to cover the capability allowlist, production `PATH`, restricted client credential files, startup health, image staging, and corrected `koha-create` behavior.
- Updated the Phase 5 specification with the current 47 static and 17 runtime checks, removed the obsolete `/ktd_ready` readiness assumption, and marked runtime recovery verification complete.
- Updated the roadmap and production-image strategy with Phase E completion, final size evidence, runtime findings, and the next Phase F work.

## Build and image evidence

| Target | Image | Image ID | Docker-reported size |
|---|---|---|---:|
| Development | `koha-alpine:phase-e-20261028` | `sha256:ef182b494ea9762761fd2fe4be5354b4f09e61f01cd602a0ffc04da1633d6052` | 3,582,352,569 bytes |
| Production | `koha-alpine-prod:phase-e-26.05.01` | `sha256:842ca5dfcabcd0fefe04179186361a64577840502c309ece3a08f2e38e937f37` | 2,011,314,063 bytes |

The production image is **90,379,042 bytes (4.30%) smaller** than the Phase B production baseline of 2,101,693,105 bytes. Its OCI version/ref labels identify Koha `26.05.01-1` / `v26.05.01-1`; `/usr/share/koha/source-revision` records resolved commit `dacce7d3fc15860d26d06444c1f5c9a2d0d6a4a9`.

Inspection confirmed the production image excludes the `nodejs`, `npm`, `yarn`, `git`, `mariadb-dev`, `perl-app-cpanminus`, and `perl-local-lib` packages; CPAN/Yarn caches; `.git`; `node_modules`; and the copied development TLS/helper trees. The required provenance files, Koha source, runtime startup helper, vhost template, OpenRC scripts, and periodic jobs are present. Both `dev-runtime` and `prod-runtime` pass `docker buildx build --check`.

## Isolated runtime validation

### Development project

- Project: `koha-alpine-test-phasee-20261028a`
- Ports: 18380/18381
- Fresh volumes: `koha-alpine-test-phasee-20261028a_koha-db-data` and `koha-alpine-test-phasee-20261028a_koha-rabbitmq-data`
- Startup smoke: **10 passed, 0 failed**. OPAC/staff returned HTTP 200; unauthenticated API routes returned Koha JSON HTTP 401.
- Phase 4 `koha-create` guardrail: **20 passed, 0 failed, 2 expected skips**.
- Phase 5 runtime audit: **64 passed, 0 failed, 0 skipped**.
- Plack and the default worker were each terminated by their exact in-container PID and recovered under new PIDs. Health, capability allowlist, Apache group membership, socket mode, runtime path permissions, `koha-shell`, and root-only MySQL client files passed.

### Production project

- Project: `koha-alpine-test-phasee-prod-20261028a`
- Ports: 18480/18481
- Fresh volumes: `koha-alpine-test-phasee-prod-20261028a_koha-db-data` and `koha-alpine-test-phasee-prod-20261028a_koha-rabbitmq-data`
- Compose configuration selected the pinned local image, used no source checkout mount, and confirmed both volume names were absent before first startup.
- Startup smoke: **10 passed, 0 failed**. OPAC/staff returned HTTP 200; unauthenticated API routes returned Koha JSON HTTP 401.
- Phase 5 runtime audit: **64 passed, 0 failed, 0 skipped**, including `koha-shell` availability and `/usr/share/koha/lib` detection after the production `PATH` correction.

### Consolidated validation and cleanup

- `tests/run_all_tests.sh`: **296 passed, 0 failed, 19 expected skips** against the explicitly selected isolated development project.
- Shell syntax checks, both Dockerfile `buildx --check` targets, and `git diff --check` passed.
- Both Phase E Compose projects were stopped with ordinary `docker compose down`; their DB/RabbitMQ volumes remain present. The pre-existing `koha-docker-db-1` remains running with its existing data volume untouched.
- No commit was created.

## Next phase

Phase E is complete. Phase F should add CI coverage for development and pinned-production builds, align architecture documentation with the Alpine runtime, and document release provenance, secrets, rollback, and volume backup/restore.
