# Consolidated Detailed Alpine Implementation Change Record

**Date:** 2026-10-28  
**Branch:** `phase`  
**Scope:** Development-runtime restoration and isolated validation, Phase B pinned production image, and Phase C fresh-database/API/browser validation.

## Purpose and status

This note consolidates the implementation changes made while continuing the Koha Alpine migration. It explains the problems each group of changes addressed and the evidence gathered. More focused records remain available for the development-runtime work ([phase continuation](./2026-10-28%20%E2%80%94%20Alpine%20phase%20continuation%2C%20isolated%20runtime%20validation%2C%20and%20Node%2022%20bootstrap%20fixes.md)), the pinned production image ([Phase B](./2026-10-28%20%E2%80%94%20Phase%20B%20pinned%20production%20image%20and%20isolated%20startup.md)), and fresh development runtime validation ([Phase C](./2026-10-28%20%E2%80%94%20Phase%20C%20fresh%20database%20Plack%20API%20routing%20and%20browser%20validation.md)).

Phase B and Phase C exit gates passed. The Phase C full rebuild of the latest development target remains outstanding: its Dockerfile check passed, but the end-to-end Phase C run used the already-built and previously validated development image. Phase D lifecycle checks are still open. Changes are uncommitted.

## 1. Development image and Alpine runtime restoration

### Docker build and runtime wiring

- [`Dockerfile-Alpine`](../../Dockerfile-Alpine) was restored as a coherent multi-target build. Shared runtime setup is separated from source-bearing development and pinned production stages. Debian-manifest runtime assets are staged before project-owned Alpine replacements are installed, so upstream packaging does not overwrite the Alpine-compatible `koha-create`, `koha-plack`, `koha-worker`, and `koha-functions.sh`.
- The runtime image's `PATH` now includes `/usr/sbin` and `/sbin`. This makes staged Koha commands and Alpine's `start-stop-daemon` discoverable at runtime.
- The runtime once again includes Phase 5 OpenRC and periodic-task wiring, required Perl dependencies, and `busybox-extras`, which the service wrappers rely on.
- Development runtime dependencies now include `musl-locales` and `musl-locales-lang`. The Node executable from the existing Node builder is used in the development image (Node v22.23.4), avoiding Alpine 3.20's Node 20.15.1, which did not meet Koha frontend package engine requirements.
- The build's frontend setup was corrected to create `/kohadevbox` before copying Koha, execute Yarn in the Koha source directory, and propagate dependency or asset-build failures instead of concealing them.
- [`scripts/build-alpine-package.sh`](../../scripts/build-alpine-package.sh) now creates the expected OPAC and intranet `htdocs` directories before applying the Debian install manifest. This prevents a manifest entry such as `unavailable.html` from creating a path as a file when later entries require it to be a directory.

### Alpine command and startup behavior

- [`files-alpine/run.sh`](../../files-alpine/run.sh) now treats frontend asset installation/build failures as fatal. It prepares ownership for Koha instance configuration, log, run, data, cache, and lock directories before running bootstrap commands as the Koha instance user. Failure to create the initial superlibrarian is reported and stops startup instead of leaving a partially initialized instance that appears healthy.
- [`files-alpine/scripts/koha-create`](../../files-alpine/scripts/koha-create) adapts instance creation to Alpine utilities and accepts the database connection options needed by the container runtime.
- [`files-alpine/scripts/koha-functions.sh`](../../files-alpine/scripts/koha-functions.sh) uses Alpine-compatible service/process checks.
- [`files-alpine/scripts/koha-plack`](../../files-alpine/scripts/koha-plack) implements the Alpine service behavior and makes help handling side-effect-free.
- [`files-alpine/scripts/koha-worker`](../../files-alpine/scripts/koha-worker) supports queue-specific actions and discovers Koha's current `misc/workers/background_jobs_worker.pl` location.
- [`docker-compose-alpinekoha.yml`](../../docker-compose-alpinekoha.yml) selects the `dev-runtime` target explicitly, removes fixed container names so Compose project names can isolate test stacks, and permits selecting a Koha env-file path instead of hard-coding the default.

## 2. Isolated test and integration harness changes

The previous integration helpers could bind to the default Compose project, infer fixed container names, or risk operating on an unintended database volume. The integration path was changed to require explicit test-project/environment selection and to inspect only the selected, already-running stack.

- [`test-plack-stack.sh`](../../test-plack-stack.sh) resolves the Koha container through the selected Compose project rather than assuming a static container name.
- [`tests/run_all_tests.sh`](../../tests/run_all_tests.sh) keeps runtime integrations opt-in; the ordinary suite does not start or select an unrequested stack.
- [`tests/run_integration_deterministic.sh`](../../tests/run_integration_deterministic.sh) requires an explicitly named isolated test project/environment, checks that the database volume is project-scoped and absent before creation, and does not remove volumes.
- [`tests/test_alpine_compose_isolation.sh`](../../tests/test_alpine_compose_isolation.sh) checks project naming and volume isolation without starting services.
- [`tests/test_authority_groupby_sqlmode_integration.sh`](../../tests/test_authority_groupby_sqlmode_integration.sh) and [`tests/test_mariadb_auth_readiness_integration.sh`](../../tests/test_mariadb_auth_readiness_integration.sh) require explicit test-stack selection; they no longer select or create services from the repository's default deployment.
- [`tests/test_restart_integration.sh`](../../tests/test_restart_integration.sh) resolves the selected Koha container dynamically, verifies the DB volume namespace, and looks for the actual Alpine startup-complete message.
- [`tests/test_alpine_startup_smoke.sh`](../../tests/test_alpine_startup_smoke.sh) waits for Koha's OPAC and staff HTTP endpoints rather than the obsolete `/ktd_ready` marker, accommodates a cold frontend build with a longer wait, and checks runtime readiness. Phase C later extended it to verify Plack status/socket and both public API routes.
- The Phase 4 static and image-backed guardrails—[`test_dockerfile_perl_deps_static.sh`](../../tests/test_dockerfile_perl_deps_static.sh), [`test_phase2_build_staging_static.sh`](../../tests/test_phase2_build_staging_static.sh), [`test_phase3_dual_mode_templating_static.sh`](../../tests/test_phase3_dual_mode_templating_static.sh), [`test_phase4_koha_create_rewrite.sh`](../../tests/test_phase4_koha_create_rewrite.sh), [`test_phase4_koha_functions_rewrite.sh`](../../tests/test_phase4_koha_functions_rewrite.sh), [`test_phase4_koha_plack_rewrite.sh`](../../tests/test_phase4_koha_plack_rewrite.sh), [`test_phase4_koha_worker_rewrite.sh`](../../tests/test_phase4_koha_worker_rewrite.sh), and [`test_phase4_start_stop_daemon.sh`](../../tests/test_phase4_start_stop_daemon.sh)—were aligned with the restored image wiring and Alpine command behavior.
- [`tests/test_run_sh_static.sh`](../../tests/test_run_sh_static.sh) checks that asset failures propagate, directory ownership is prepared before the initial admin step, and an admin-creation failure is fatal.

The testing guidance in [`Alpine-Koha-test-grounds.md`](../Alpine-migration/Alpine-Koha-test-grounds.md) documents the isolated-stack procedure and the rule to preserve volumes.

## 3. Phase B: pinned production image

### Source/dependency consistency and provenance

- [`Dockerfile-Alpine`](../../Dockerfile-Alpine) now has a `prod-source` stage that requires a release tag or full commit ID, explicitly fetches tags, rejects branch-style refs, and checks out the selected object detached. It records the requested ref, source URL, and resolved commit.
- The production source stage builds Koha assets from that selected source and removes `.git`, `node_modules`, and temporary frontend caches before the source is copied into runtime layers.
- A new [`scripts/install-koha-perl-dependencies.sh`](../../scripts/install-koha-perl-dependencies.sh) centralizes Koha's `cpanfile` dependency installation and the project's required additional Perl modules. It fails the image build on dependency errors. Development dependencies are installed from the development checkout; the `prod-deps` stage installs from the exact tree produced by `prod-source`, preventing source/dependency revision drift.
- The production runtime receives release-matched Perl libraries, source, manifest-selected runtime assets, and Alpine command overlays. OCI source/version/revision labels and `/usr/share/koha/source-revision`, `source-ref`, and `source-url` metadata make the built source identity inspectable. Production defaults skip runtime Yarn/dependency work and development-only settings.

### Production Compose contract and regression coverage

- [`docker-compose.prod.yml`](../../docker-compose.prod.yml) requires production release version and source ref, uses them to select the production build/image, and sets production-safe defaults (including no demo data by default and no runtime Yarn install).
- The production Koha volume list uses Compose `!override` semantics to replace the development list, not merge with it. The merged config therefore cannot inherit the `/kohadevbox/koha` checkout mount.
- [`tests/test_dockerfile_perl_deps_static.sh`](../../tests/test_dockerfile_perl_deps_static.sh) now checks the extracted shared installer and its failure behavior.
- [`tests/test_phase2_build_staging_static.sh`](../../tests/test_phase2_build_staging_static.sh) checks pinning, branch rejection, fetched-source dependency alignment, provenance, volume isolation, production defaults, and baked asset staging.
- [`docs/Alpine-migration/koha-fixed-version-production-image-strategy.md`](../Alpine-migration/koha-fixed-version-production-image-strategy.md) now describes the implemented stages, immutable source model, metadata locations, and the runtime reduction work that remains for Phase E.

### Phase B verification

- Built `koha-alpine-prod:phase-b-26.05.01` from upstream tag `v26.05.01-1`, resolving to commit `dacce7d3fc15860d26d06444c1f5c9a2d0d6a4a9`. Image ID: `sha256:55ebedb671552e58ef26737a0e8f2d1e5103b6d34b8dd2a4ffde246917130d6c`.
- Verified the source metadata, OCI labels, baked OPAC/intranet CSS, absence of `.git` and `node_modules`, and absence of the development source mount. A nonexistent source tag failed at fetch as expected; missing release inputs were rejected by Compose.
- Started a fresh isolated production project with newly verified-absent project-scoped MariaDB and RabbitMQ volumes and dedicated ports. MariaDB became healthy, Koha logged startup complete, the production smoke test passed **7/7**, and OPAC, staff, and both CSS endpoints returned HTTP 200.
- Phase B static checks passed: **33** production staging checks and **7** dependency checks. The then-current full suite passed **229**, with **0 failures** and **34 skipped**.

## 4. Phase C: fresh development database and API routing

### Defect and fix

In the fresh Phase C project, `GET /api/v1/patrons/` returned `404 Not Found` on both OPAC and intranet ports even though Plack was running and its socket existed. The custom Apache vhosts proxied `/api` without Koha's rewrite from the public route to the API app mount at `/api/v1/app.pl`.

[`files-alpine/templates/koha-vhost.conf.in`](../../files-alpine/templates/koha-vhost.conf.in) now applies Koha-compatible `RewriteCond`/`RewriteRule` logic in both virtual hosts before proxying. This preserves existing behavior for requests already addressed to `app.pl` and routes ordinary API paths to the mounted Koha API. After restarting only the Koha service, both unauthenticated API requests returned JSON HTTP 401—the expected result once routing reaches the API and authentication is required.

### Regression and runtime checks

- [`tests/test_phase3_dual_mode_templating_static.sh`](../../tests/test_phase3_dual_mode_templating_static.sh) asserts that both vhosts contain the rewrite and that the guard avoids rewriting a request already containing `app.pl`.
- [`tests/test_alpine_startup_smoke.sh`](../../tests/test_alpine_startup_smoke.sh) now checks Plack status, the Plack socket, and API responses through both virtual hosts.
- The runtime check used project `koha-alpine-test-phasec-dev-20261028a`, ports 18280/18281, and image `koha-alpine:phase-roadmap-validation` (`sha256:5102268254536ebc8ed6c1bf57d5bb160b8a29174b9a791802fb53e3d7b8f8e5`). The DB/RabbitMQ volume names were verified absent before startup.
- MariaDB became healthy; Koha bootstrapped the fresh schema to `26.0501000` and created one `admin` superlibrarian with `cardnumber=1`. The post-fix restart against the same populated database passed **4/4**; the expanded startup smoke passed **10/10**.
- OPAC and staff pages rendered in the browser. All page-linked assets checked returned HTTP 200: OPAC 2 CSS and 17 JavaScript resources; staff 8 CSS and 20 JavaScript resources.
- Phase C static vhost checks passed **26/26**. The full suite then passed **231**, with **0 failures** and **34 skipped**. Shell syntax and `git diff --check` passed.

The current `dev-runtime` Dockerfile passed `docker buildx build --check`. A full rebuild was started, but the shared installer invalidated the dependency cache and began reinstalling Koha's complete CPAN set; that redundant rebuild was stopped. The Phase C runtime evidence therefore applies to the previously built image specified above, not a full rebuild from the latest Dockerfile.

## 5. Roadmap and documentation

- [`2026-10-roadmap-and-state-assessment.md`](../Alpine-migration/2026-10-roadmap-and-state-assessment.md) records the current implementation map, marks the production-image and fresh development runtime exit gates complete, preserves the dev-target rebuild caveat, and identifies Phase D lifecycle/scheduled-work checks as next.
- The production strategy document was updated to reflect actual implemented stages and metadata rather than proposal-only behavior.
- The three focused tracker notes linked at the top preserve phase-specific evidence and procedures. This consolidated note serves as an index and file-by-file explanation of the overall change set.

## 6. Isolation, cleanup, and data preservation

All runtime checks used unique Compose project names and test-specific ports. New test DB and RabbitMQ volumes were verified absent before their respective test stacks were started. Stacks were stopped with ordinary `docker compose down`, never `down -v`; their test volumes remain present and must not be mistaken for empty volumes in a future fresh-database check. Temporary synthetic env and Compose override files were removed.

The existing `koha-docker-db-1` container and `koha-docker_koha-db-data` volume were preserved and were not used for these tests. No existing Koha volume was removed. The production Phase B and development Phase C test volumes remain separate from one another and from the pre-existing deployment.

## 7. Current remaining work

1. Rebuild the latest `dev-runtime` image end to end to complete reproducibility evidence for the extracted shared Perl installer in the development path.
2. Complete Phase D against a current image: controlled Plack failure and watchdog recovery, worker restart with a real worker, an `/etc/periodic/` task, graceful Docker stop, orphan-process checks, and the remaining `koha-shell` compatibility check.
3. Continue the later roadmap items for runtime image reduction/least privilege, CI coverage, architecture-document alignment, and production release/rollback procedures.
