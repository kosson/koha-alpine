# Alpine phase continuation, isolated runtime validation, and Node 22 bootstrap fixes

**Date:** 2026-10-28  
**Branch:** `phase`  
**Status:** Development image and isolated persistent-DB runtime validation passed; production and additional lifecycle gates remain open.

## Summary

This work resumed the Alpine migration from the phase branch after reviewing the migration notes, tracker history, architecture references, current Koha Debian packaging inputs, and the implementation. A comprehensive state assessment and forward roadmap was added at [`docs/Alpine-migration/2026-10-roadmap-and-state-assessment.md`](../Alpine-migration/2026-10-roadmap-and-state-assessment.md).

The work restored the dev/prod build and Alpine lifecycle wiring, made integration tests explicitly select isolated Compose projects, and advanced runtime validation using a new project with fresh project-scoped DB and RabbitMQ volumes. Runtime checks uncovered two startup blockers: Alpine's packaged Node was too old for Koha's frontend dependency requirements, and the newly provisioned instance log directory was not writable by the Koha account when the initial admin was created. Both were addressed. The final dev image produced compiled assets, and the isolated persistent-database startup/restart checks passed.

## Issues found and addressed

### Build and image wiring

- **Missing production target:** `docker-compose.prod.yml` requested `prod-runtime`, but `Dockerfile-Alpine` did not define it. The Dockerfile now has a shared runtime base, a source-bearing dev runtime, and production source/runtime stages. Production source is fetched by the configured Git ref and assets are built and staged during image construction.
- **Alpine overrides could be lost or omitted:** Koha Debian-manifest assets must be staged before applying the project-owned Alpine command scripts. Dev and production build flows now run the staging helper and then install the Alpine `koha-create`, `koha-plack`, `koha-worker`, and `koha-functions.sh` overrides.
- **Asset staging failed on htdocs path type:** Debian's `unavailable.html` manifest entries could create an htdocs destination as a file before later entries expected directories. The build helper now creates the OPAC and intranet htdocs directories before manifest staging.
- **Runtime command discovery failed:** `/usr/sbin` and `/sbin` were absent from the image `PATH`, hiding Koha commands and `start-stop-daemon`. Those directories are now included.
- **Missing Phase 5 and dependency wiring:** The runtime image again installs the OpenRC/periodic-task files and required Perl dependencies, and includes `busybox-extras` for the expected daemon utility behavior.
- **Node engine incompatibility:** Alpine 3.20's Node 20.15.1 did not satisfy Koha frontend package requirements (`^20.19.0 || ^22.13.0 || >=24`). `node-builder` already used Node 22, so the dev runtime now copies its Node executable and uses v22.23.4.
- **Missing locale utility:** Runtime smoke checks found `locale` absent. `musl-locales` and `musl-locales-lang` are installed in the image.
- **Frontend build failures were hidden:** `run.sh` previously piped Yarn output through `tail` without `pipefail`, then warned and continued if install/build failed. It now enables `pipefail` in that pipeline and exits on a failed required asset build rather than serving pages without compiled CSS/JS.

### Koha startup and lifecycle behavior

- **Initial admin creation failed on a fresh instance:** The first Node 22 startup showed the instance log directory was still root-owned when `create_superlibrarian.pl` ran as the Koha instance user. `run.sh` now assigns ownership of Koha's per-instance config, log, run, data, cache, and lock directories before database bootstrap/admin creation.
- **Admin creation failure was success-shaped:** The entrypoint previously warned and continued after `create_superlibrarian.pl` failed. It now reports an error and exits, preventing startup from claiming success without the initial admin. A test confirms directory ownership precedes admin creation and that this failure is fatal.
- **Worker behavior drifted from current Koha:** The Alpine worker wrapper now supports the configured queue options and locates Koha's current `misc/workers/background_jobs_worker.pl` path.
- **Plack help had side effects:** The Alpine Plack wrapper's help handling now returns without performing setup.
- **Restart-test expectation was stale:** The restart integration check expected the wrong banner; it now matches the Alpine `Startup complete - OPAC on` message.

### Test safety, readiness, and documentation

- **Compose project collisions and volume risk:** Hard-coded container names were removed from the Alpine Compose file, its dev target is explicit, and the Koha container env file can be overridden. Tests now require an explicitly selected `koha-alpine-test-<suffix>` project where appropriate, verify that the DB volume belongs to that project and is absent before creation, and do not delete volumes.
- **Integration tests could start or select unintended services:** Authority, MariaDB readiness, restart, and startup smoke checks now require explicit test project/env selection; deterministic integration setup checks project identity and volume safety before proceeding.
- **Smoke test used obsolete readiness marker:** The startup smoke test now checks the OPAC and staff HTTP endpoints rather than `/ktd_ready`, a marker not provided by this Alpine entrypoint. Its default wait is 300 seconds to allow cold Node/Yarn dependency installation and frontend compilation.
- **Regression coverage:** Static assertions were updated for production build wiring, Compose isolation, current entrypoint behavior, frontend error propagation, Node 22 use, and current lifecycle scripts.
- **Test guidance:** [`docs/Alpine-migration/Alpine-Koha-test-grounds.md`](../Alpine-migration/Alpine-Koha-test-grounds.md) now documents isolated runtime testing and volume-preservation requirements.

## Files changed

### Build and runtime

- [`Dockerfile-Alpine`](../../Dockerfile-Alpine) — restored dev/prod image stages and manifest staging; reinstalled Alpine overlays after staging; restored runtime tooling and dependencies; added `/usr/sbin` and `/sbin` to `PATH`; added locale packages and Node 22 for the dev runtime.
- [`docker-compose-alpinekoha.yml`](../../docker-compose-alpinekoha.yml) — removed fixed container names, explicitly selects `dev-runtime`, and allows an overridable Koha env-file path.
- [`scripts/build-alpine-package.sh`](../../scripts/build-alpine-package.sh) — creates the expected htdocs directories before applying the Debian install manifest.
- [`files-alpine/run.sh`](../../files-alpine/run.sh) — builds frontend assets with failure propagation; prepares instance directory ownership before bootstrap; fails explicitly if initial admin creation fails.
- [`files-alpine/scripts/koha-create`](../../files-alpine/scripts/koha-create) — adapts Koha instance creation to Alpine utilities and supports database connection options used by the runtime.
- [`files-alpine/scripts/koha-functions.sh`](../../files-alpine/scripts/koha-functions.sh) — uses Alpine-compatible service/process checks.
- [`files-alpine/scripts/koha-plack`](../../files-alpine/scripts/koha-plack) — provides Alpine service behavior and side-effect-free help handling.
- [`files-alpine/scripts/koha-worker`](../../files-alpine/scripts/koha-worker) — supports queue-specific actions and current Koha worker script discovery.

### Tests, harnesses, and documentation

- [`test-plack-stack.sh`](../../test-plack-stack.sh) — resolves containers through the selected Compose project rather than a fixed container name.
- [`tests/run_all_tests.sh`](../../tests/run_all_tests.sh) — includes the current test set and continues to avoid invoking unselected integration stacks by default.
- [`tests/run_integration_deterministic.sh`](../../tests/run_integration_deterministic.sh) — requires an isolated test project/env and validates project-scoped volume safety.
- [`tests/test_alpine_compose_isolation.sh`](../../tests/test_alpine_compose_isolation.sh) — verifies Compose naming and volume isolation without starting services.
- [`tests/test_alpine_startup_smoke.sh`](../../tests/test_alpine_startup_smoke.sh) — validates service readiness through HTTP, locale, timezone, and web runtime, with a longer cold-start allowance.
- [`tests/test_authority_groupby_sqlmode_integration.sh`](../../tests/test_authority_groupby_sqlmode_integration.sh) — runs only against an explicitly selected running project.
- [`tests/test_mariadb_auth_readiness_integration.sh`](../../tests/test_mariadb_auth_readiness_integration.sh) — restricts DB readiness tests to a new isolated project and avoids volume deletion.
- [`tests/test_restart_integration.sh`](../../tests/test_restart_integration.sh) — selects an isolated project, derives the Koha container dynamically, verifies the DB volume namespace, and checks the actual Alpine startup banner.
- [`tests/test_dockerfile_perl_deps_static.sh`](../../tests/test_dockerfile_perl_deps_static.sh), [`tests/test_phase2_build_staging_static.sh`](../../tests/test_phase2_build_staging_static.sh), [`tests/test_phase3_dual_mode_templating_static.sh`](../../tests/test_phase3_dual_mode_templating_static.sh), [`tests/test_phase4_koha_create_rewrite.sh`](../../tests/test_phase4_koha_create_rewrite.sh), [`tests/test_phase4_koha_functions_rewrite.sh`](../../tests/test_phase4_koha_functions_rewrite.sh), [`tests/test_phase4_koha_plack_rewrite.sh`](../../tests/test_phase4_koha_plack_rewrite.sh), [`tests/test_phase4_koha_worker_rewrite.sh`](../../tests/test_phase4_koha_worker_rewrite.sh), and [`tests/test_phase4_start_stop_daemon.sh`](../../tests/test_phase4_start_stop_daemon.sh) — align static and image-backed assertions with the restored image wiring and Alpine behavior.
- [`tests/test_run_sh_static.sh`](../../tests/test_run_sh_static.sh) — asserts fail-fast frontend compilation, correct ownership ordering, and fatal initial-admin failure handling.
- [`docs/Alpine-migration/2026-10-roadmap-and-state-assessment.md`](../Alpine-migration/2026-10-roadmap-and-state-assessment.md) — records the implementation assessment, validation, and sequenced remaining roadmap.
- [`docs/Alpine-migration/Alpine-Koha-test-grounds.md`](../Alpine-migration/Alpine-Koha-test-grounds.md) — adds isolated-stack and volume-safety instructions.

## Validation results

- Branch is `phase`.
- Full test runner: **209 passed, 0 failed, 34 skipped**.
- Focused entrypoint static assertions: **11 passed**.
- Dockerfile `buildx --check`: both `dev-runtime` and `prod-runtime` passed without warnings.
- Final dev image: built as `koha-alpine:phase-roadmap-validation`; runtime reports Node `v22.23.4`, `locale` is available, and compiled OPAC CSS is present.
- Image-backed Phase 4 guardrails: all five scripts passed (Koha create, functions, Plack, worker, and `start-stop-daemon`).
- Isolated startup smoke: **7/7 passed**.
- Isolated persistent-DB restart: **4/4 passed**. The previously missing initial admin was created after the ownership fix; the restarted container completed startup.
- Authority SQL-mode integration: **7/7 passed** against the isolated populated database.
- OPAC and staff pages returned HTTP 200. Five sampled CSS/JS resources from each page also returned HTTP 200.
- `git diff --check` passed for changed files, excluding the two pre-existing conflicted files.

## Runtime isolation and preserved data

Runtime validation used Compose project `koha-alpine-test-roadmap-20261028a`, ports 18080/18081, a synthetic env file, and an internal-only project network. The test project's volumes were new and project-scoped:

- `koha-alpine-test-roadmap-20261028a_koha-db-data`
- `koha-alpine-test-roadmap-20261028a_koha-rabbitmq-data`

After validation, the isolated stack was stopped with `docker compose down` (without `-v`). Its new volumes remain present. The existing `koha-docker_koha-db-data` volume and `koha-docker` containers were not used or modified. Temporary synthetic env/override files were removed.

The unresolved merge conflicts in [`env/.env`](../../env/.env) and [`OpenSearch-3.6/assets/opensearch/config/os01/opensearch-security/internal_users.yml`](../../OpenSearch-3.6/assets/opensearch/config/os01/opensearch-security/internal_users.yml), and pre-existing untracked `.vscode/` content, were left untouched.

## Remaining work

1. Re-run a fresh empty-database bootstrap using the final image and verify schema initialization plus initial admin creation end to end. The final image's admin ownership fix was validated on restart against the isolated populated DB, but not yet with a new empty DB volume.
2. Verify Plack socket and API endpoints, then perform a browser pass.
3. Exercise Phase 5 watchdog recovery, worker restart behavior, a scheduled periodic task, and graceful container shutdown.
4. Build and inspect `prod-runtime` from a pinned immutable Koha ref; verify source provenance, baked assets, absence of `.git`/`node_modules`, and no source bind/anonymous source volume.
5. Continue runtime reduction/least-privilege work and align architecture docs with the Alpine deployment.
