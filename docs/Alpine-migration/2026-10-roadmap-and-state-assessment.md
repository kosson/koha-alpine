# Alpine Migration: State Assessment and Forward Roadmap

**Review date:** 2026-10-28  
**Branch:** `phase`  
**Scope:** Alpine container adaptation, its Koha Debian compatibility layer, migration records, tracker, and architecture references.

## Executive assessment

The project has moved past the initial Alpine port. It has a functioning development-image architecture, Alpine-specific Koha administration wrappers, a Plack/Apache integration, startup bootstrap logic, external database/broker/cache services, and static plus image-backed test suites. The migration notes mark the first five deeper-integration phases complete.

That status needs qualification:

1. The repository's current `Dockerfile-Alpine` did not define the `prod-runtime` target required by `docker-compose.prod.yml`. The Phase 2 test already exposed this: its two production-staging assertions failed.
2. The Phase 3 static test required an obsolete comment marker for a removed `koha-gitify` shim. The implementation was consistent with removing the shim; the assertion was not.
3. Phase 5's plan still lists the manual watchdog crash/restart check as pending. The August tracker records successful runtime checks, but does not close that specific manual recovery criterion.
4. The architecture pages under `docs/architecture/` mostly describe the original Ubuntu-oriented stack. They are useful for shared topology, but must not be treated as an authoritative description of the Alpine image internals.
5. At review time, `env/.env` and the OpenSearch `internal_users.yml` have unresolved merge conflicts. They are preserved. No container was started or volume modified during this review.
6. Re-running Phase 4 guardrails exposed drift in `Dockerfile-Alpine` and `koha-worker`: the development image did not install its Alpine command overlays or `busybox-extras`, and the worker wrapper missed Koha's current `misc/workers` path and queue options. Those gaps are being restored before runtime validation.

The immediate direction is therefore to restore and verify the production image target, make Alpine test stacks safely separable by Compose project name, and then establish a clean runtime baseline before taking on further migration work.

## Evidence-based implementation map

| Area | Present implementation | Assessment |
|---|---|---|
| Alpine build | `Dockerfile-Alpine` separates shared runtime, development source, and production source/runtime stages. | The missing production target is restored. The dev image must stage upstream assets before reapplying Alpine command overrides; the corrected image build is in progress. |
| Development orchestration | `docker-compose-alpinekoha.yml` runs Koha with MariaDB, RabbitMQ, and Memcached; OpenSearch/Traefik networks are external. | Good separation for dev, but fixed container names prevented independent project instances. Named volumes are Compose-project-scoped unless explicitly named otherwise. |
| Koha bootstrap | `files-alpine/run.sh` renders Koha configuration, waits for MariaDB, initializes an empty DB, prepares assets and Apache, then starts Koha services and the watchdog. | Substantial runtime adaptation exists. A clean boot/restart still needs fresh, isolated runtime evidence. |
| Shared helpers | `files-alpine/lib/run-sh-alpine.sh` contains Alpine-oriented service, vhost, cron, and watchdog behavior. | Phase 5 behavior exists in code. The current Dockerfile had omitted its OpenRC/periodic files; image wiring is restored in this review, but crash-and-restart behavior still needs a newly built image. |
| Admin commands | `files-alpine/scripts/` contains Alpine replacements for selected Debian `koha-*` tools; remaining upstream scripts and templates are sourced from `koha/debian`. | Build-time override installation and `busybox-extras` are restored. The worker now handles queues and Koha's current worker-script location; image-backed lifecycle coverage remains incomplete. |
| Build staging | `scripts/build-alpine-package.sh` reads `koha/debian/koha-common.install` and stages runtime resources. | The helper existed, but was not wired into the production target in the current Dockerfile. |
| Production path | `docker-compose.prod.yml` requests `prod-runtime`, passes a Git URL/ref/depth/version, and removes the source bind mount. | Broken until the matching Docker stage exists and is validated. The ref must be immutable for release builds. |
| Tests | `tests/run_all_tests.sh` combines static, unit, image-backed, and integration checks. | Previous tracker results are useful historical evidence, not a substitute for re-running tests against current files and a fresh image. |
| Upstream baseline | `koha/debian/scripts`, `koha/debian/templates`, and the Debian install manifest define the compatibility source of truth. | Keep Debian-specific packaging details at the boundary; avoid carrying a full Debian runtime/package manager into Alpine. |

### Phase completion, with remaining gates

| Phase | Recorded outcome | Remaining evidence or work |
|---|---|---|
| 1 — Native C libraries and Perl | YAZ/ZOOM work is recorded as complete. | Reconfirm through the production image build and targeted Z39.50 checks. |
| 2 — Build-time asset staging | Build-time staging helper and static test exist. | Restore the `prod-runtime` wiring and make production build failure explicit. |
| 3 — Dual-mode templating / Gitify removal | Project-owned templates and vhost rendering replace runtime Gitify behavior. | Keep the test assertions aligned to the actual no-Gitify contract. |
| 4 — POSIX admin tools / shim removal | Alpine rewrites exist for selected lifecycle commands; this review restores image overlay wiring and worker queue/path compatibility. | Close the open `/etc/default/koha-common`/`koha-shell` check and finish image-backed compatibility coverage. |
| 5 — OpenRC, watchdog, cron | OpenRC wrappers, periodic tasks, and a SIGTERM-aware watchdog exist; Dockerfile installation wiring is restored in this review. | Build the updated image, run the documented crash/restart test, and observe at least one scheduled task in a fresh container. |
| Dev/production split | Compose overlay and `stack-alpine.sh` mode selection exist. | Production build target was missing from the current Dockerfile; verify pinned-source, baked-asset, and no-source-volume behavior. |

## Decisions and safety rules

1. Keep the existing Debian-derived instance layout where it preserves Koha behavior; replace only OS/package/service assumptions that Alpine cannot provide.
2. Keep MariaDB, Memcached, RabbitMQ, and OpenSearch on explicit service/network boundaries. Keep Apache with Koha until lifecycle commands no longer mutate local web-server configuration.
3. Keep the source bind mount exclusive to development. Production must fetch a specified Koha ref at build time and must not inherit a source `VOLUME`.
4. Run verification stacks with a unique Compose project name. This gives test DB and RabbitMQ volumes unique names; do not use `down -v` against an existing or production project.
5. Treat HTTP status alone as insufficient: check real Koha HTML, static CSS/JS delivery, Plack health, CGI execution, and browser behavior.
6. Preserve pre-existing merge conflicts and unrelated worktree files. Resolve conflicts only with explicit owner direction.

## Forward roadmap

### Phase A — Reproducible, isolated baseline (active)

- [x] Remove hard-coded Alpine service container names so a project-specific Compose name can isolate the test services.
- [x] Make the Alpine service's container env file overridable without editing the conflicted default file.
- [x] Set the development build target explicitly.
- [x] Add a Compose-only test that checks generated container naming and project-scoped DB/broker volumes without creating containers.
- [x] Run the static/unit suites against the current worktree; integration checks now require an explicitly selected test project and env file, and never start services or create volumes.
- [x] Build the dev image and run it only under a unique test project after checking the synthetic env, ports, and network isolation.

**Exit gate:** Compose config proves unique volume names; the Alpine Docker build completes; no existing container or volume is reused.

### Phase B — Restore the immutable production image path (active)

- [x] Add a separate source stage that fetches the configured Git ref and builds Koha assets.
- [x] Keep production based on a runtime-only base, not the development source-bearing stage.
- [x] Stage Debian-manifest runtime assets during the production build and reapply Alpine command overrides.
- [x] Set the production runtime to skip development-time asset installation/copy work.
- [ ] Verify `KOHA_GIT_REF` is mandatory and a bad/unavailable ref fails the build.
- [ ] Build the production target from an explicit tag or commit and inspect labels, source tree, assets, and absence of `.git`/`node_modules`.
- [ ] Resolve whether production Perl dependencies must also be built from the fetched release source rather than the checked-out build-context source.

**Exit gate:** production Compose renders and builds from a pinned ref, contains the fetched source and built assets, has no source bind/anonymous source volume, and starts with its production defaults.

### Phase C — Fresh development-stack runtime validation (active)

- [x] Use a new Compose project name and a valid, non-conflicted test env file.
- [x] Confirm DB and RabbitMQ volume names carry the test project prefix before starting.
- [x] Build the `dev-runtime` image, then start the stack only after checking host ports and using an internal-only project network.
- [ ] Repeat an empty-database bootstrap with the corrected admin-directory ownership, then confirm a populated-database restart.
- [x] Verify OPAC/staff HTTP and page-referenced CSS/JavaScript delivery.
- [ ] Validate Plack socket/API health and perform one browser pass.
- [x] Recreate the same isolated project and verify restart idempotency without deleting its volumes.

**Exit gate:** two successive boots of an isolated project pass without bootstrap crashes, static asset gaps, or false-ready state.

### Phase D — Lifecycle and scheduled-work verification

- [ ] Kill the Plack process in the isolated container and verify the watchdog restores it within one poll interval.
- [ ] Verify worker restart behavior when a real worker process is enabled for the test instance.
- [ ] Trigger one controlled `/etc/periodic/` task and verify its observable effect/log.
- [ ] Verify `docker stop` terminates within the configured grace period and leaves no orphaned Koha daemons.
- [ ] Close the open Phase 4 `koha-shell` configuration check.

**Exit gate:** restart, cron, and graceful-shutdown checks pass against the same freshly built image.

### Phase E — Runtime reduction and least-privilege hardening

- [ ] Measure production image contents and remove build-only tools, caches, Git metadata, and development-only helper trees without changing runtime behavior.
- [ ] Replace world-writable runtime paths/socket permissions with a least-privilege Apache/Koha group contract.
- [ ] Reduce `cap_add: ALL`; document and test only capabilities required by the container.
- [ ] Review startup operations that intentionally tolerate failure; make required failures fatal and optional failures explicit in logs.
- [ ] Add image health/readiness checks that distinguish process liveness from a usable Koha endpoint.

**Exit gate:** all endpoint and lifecycle gates remain green after each hardening change; image size and privileges are recorded for comparison.

### Phase F — Release process and documentation alignment

- [ ] Add CI checks for both Compose modes: config, dev build, production build with a pinned ref, and static/unit suites.
- [ ] Update architecture pages that describe Ubuntu-only paths or obsolete ports so Alpine runtime behavior is clearly separated.
- [ ] Document release tagging, source-ref provenance, image labels, rollback, secrets injection, and data-volume backup/restore.
- [ ] Archive completed tracker work as historical evidence and maintain one current status/roadmap entry.

**Exit gate:** a maintainer can build, inspect, deploy, validate, and roll back a versioned production image using the documented commands.

## Current review changes

This review advances Phases A through C:

- The Alpine Compose file now explicitly builds `dev-runtime`, has no hard-coded service container names, and accepts `KOHA_CONTAINER_ENV_FILE` as an override. The default remains `env/.env`.
- `Dockerfile-Alpine` now separates the shared runtime base from the development source-bearing stage and defines `prod-source`/`prod-runtime`. Production source is fetched by the supplied ref and its frontend assets are built before temporary build artifacts are removed.
- The production stage invokes the manifest staging helper and reapplies Alpine command overrides after Debian scripts are staged.
- Static tests now check the production contract and exercise Compose config with a synthetic project name; the obsolete Phase 3 test assertion was changed to enforce absence of the removed Gitify shim.
- The root Plack harness resolves the Koha container through Compose instead of assuming a fixed container name.
- The current Dockerfile had also omitted the Phase 5 OpenRC/cron installation and two Perl dependency checks; those image-layer omissions are restored. The run.sh static test had assertions for an older entrypoint and now verifies the current Alpine database bootstrap.
- The frontend build stage now creates `/kohadevbox` before copying Koha, builds from the Koha source directory, and fails instead of masking Yarn or asset-copy errors. An initial build confirmed `yarn install` and `yarn build` complete; that build was stopped before the full image stage when additional Phase 4 image-wiring gaps were found.
- The Phase 4 base image again includes `busybox-extras`. Dev and production targets stage Debian assets, then install the project-owned Alpine command overlays; the worker supports queue actions and locates Koha's `misc/workers/background_jobs_worker.pl`.
- The authority SQL-mode and startup smoke integration tests no longer select the repository's default Compose project or start services. They require explicit `KOHA_TEST_PROJECT`/`KOHA_TEST_ENV_FILE` values and inspect only an already-running selected project; an optional `KOHA_TEST_COMPOSE_OVERRIDE` supports isolated network/port configuration.
- The restart integration check now uses an explicitly selected Compose project and dynamic container IDs. The deterministic integration runner and its MariaDB readiness test require a new `koha-alpine-test-<suffix>` project, verify that its DB volume is project-scoped and absent, and no longer delete volumes.
- The image build exposed an asset-staging order bug: `debian/unavailable.html` was copied to the htdocs path before the path existed as a directory. The staging helper now creates the Koha htdocs directories before processing the Debian manifest, and the dev image built successfully.
- Image-backed Phase 4 checks then exposed that the runtime `PATH` omitted Alpine's `/usr/sbin` and `/sbin`. This hid the staged Koha commands and `start-stop-daemon` even though their files were present. Adding both directories fixed all five image-backed Phase 4 guardrails.
- A fresh stack was started under `koha-alpine-test-roadmap-20261028a` after verifying new project-scoped DB/RabbitMQ volume names, free ports 18080/18081, and an internal-only service network. MariaDB became healthy; Koha initialized/upgraded its schema through 26.05.01, logged startup complete, and started Plack, the background worker, Apache, and crond. OPAC and staff HTTP both returned 200. The startup smoke test exposed missing `locale`; `musl-locales` and `musl-locales-lang` are now added to the image. Its obsolete `/ktd_ready` check was also replaced with actual OPAC/staff HTTP readiness, since the current Alpine entrypoint signals readiness via those endpoints instead.
- The same runtime run showed Alpine 3.20's Node 20.15.1 cannot install Koha's frontend dependencies, which require Node 20.19+/22.13+; the warning fallback then let startup continue without CSS. The dev image now takes Node 22 from the already-used Node builder, and `run.sh` treats asset-build failures as fatal instead of serving a success-shaped but unstyled stack.
- The authority GROUP BY/SQL-mode integration passed all seven checks against the isolated, populated DB. The restart test's expected success banner has been aligned with the actual Alpine `Startup complete - OPAC on` log.
- The rebuilt dev image now reports Node v22.23.4 and includes `/usr/bin/locale`; `buildx --check` passes for both dev and production targets. All five image-backed Phase 4 guardrail scripts pass.
- The first Node 22 runtime startup required about a minute for Yarn dependency installation and CSS/JS/API compilation, exceeding the smoke test's old 90-second deadline. Once startup completed, OPAC/staff and their linked CSS/JS resources returned HTTP 200. The smoke-test default is now 300 seconds and passes 7/7 checks.
- That cold startup also exposed that initial Koha instance directories were owned by root when `create_superlibrarian.pl` ran; the admin insert failed with a log-permission error while the entrypoint continued. `run.sh` now changes ownership before running Koha as the instance user and fails explicitly if initial admin creation fails. On the isolated DB restart, the missing admin was created (`cardnumber=1` count: 1), startup completed, and the restart integration passed 4/4.
- The authority SQL-mode integration passed 7/7 against the isolated DB. The full test runner passes 209 checks, 0 failures, and 34 skips.

The isolated runtime is now healthy, but Phase C remains open until the corrected entrypoint is rebuilt into the image and a new empty-database bootstrap is verified; API/socket checks and browser validation also remain. The isolated project's two new volumes are preserved (no `down -v`); the existing `koha-docker-db-1` container and `koha-docker_koha-db-data` volume remain untouched. One temporary `docker run --rm` invocation used the image's default entrypoint and was stopped while waiting for an unavailable DB; it had no mounted volumes and left no running container. The conflicted `env/.env` and OpenSearch security file have not been edited or resolved; `.vscode/` is pre-existing untracked content and is outside this change.

## Validation record

| Check | Result at review |
|---|---|
| Branch | `phase` |
| Worktree | Pre-existing unresolved merge conflicts in `env/.env` and `OpenSearch-3.6/assets/opensearch/config/os01/opensearch-security/internal_users.yml`; pre-existing untracked `.vscode/` |
| Phase 2 static test, before this change | 6 passed, 2 failed: production staging command and `SKIP_RUNTIME_ASSET_COPY` were absent |
| Phase 3 static test, before this change | 23 passed, 1 failed: obsolete expectation for a comment marker |
| Docker Compose version | Available; direct config against the conflicted default env file fails as expected |
| Dockerfile parse checks | `buildx --check` passes for `dev-runtime` and `prod-runtime` after the latest stage changes. |
| Focused build / migration tests | Phase 2, Phase 3, Phase 4 command rewrites, Phase 5 supervision, DB bootstrap, and Compose isolation checks pass; all five image-backed Phase 4 guardrails pass. |
| Full test runner | 209 passed, 0 failed, 34 skipped; default invocation no longer parses the conflicted env file or starts a service. |
| Frontend build stage | Koha `yarn install` and `yarn build` completed successfully during the first isolated build attempt; image assembly was stopped to incorporate the newly identified Phase 4 fixes. |
| Corrected dev image build / container start | Final dev image build includes the admin-permission fix; Node is v22.23.4, locale and compiled OPAC CSS are present, both Dockerfile targets pass `buildx --check`, all five image-backed Phase 4 scripts pass, and the final image's isolated persistent-DB restart passes 4/4 checks. |
| Fresh runtime stack | Isolated DB/RabbitMQ volumes only; DB healthy, schema upgrades completed, and Plack/worker/Apache/crond started. Smoke is 7/7; restart is 4/4; authority SQL-mode is 7/7; OPAC/staff and sampled CSS/JS resources return HTTP 200. The startup permission fix created the missing admin record on restart. A fresh empty-DB bootstrap against the final image remains pending. |
| Runtime isolation | Existing `koha-docker-db-1` and `koha-docker_koha-db-data` are untouched. External network `knonikl` was absent; the isolated override connected only to the project network. Ports 18080/18081 were free and are used by the test project. |

## Source and document references

- [Alpine deeper-integration roadmap](./Alpine-deeper-integration.md)
- [Phase 3 specification](./Phase-3-Dual-Mode-Templating-and-koha-gitify-Elimination.md)
- [Phase 4 specification](./Phase-4-POSIX-Admin-Tools-and-Shim-Removal.md)
- [Phase 5 specification](./Phase-5-OpenRC-Supervision-and-Cron-Integration.md)
- [Fixed-version production image strategy](./koha-fixed-version-production-image-strategy.md)
- [Alpine test grounds](./Alpine-Koha-test-grounds.md)
- [September Plack/Apache recovery tracker](../TRACKER/2026-09-01%20%E2%80%94%20Plack%20Apache%20stack%20recovery%20stale-image%20drift%20missing%20mod_proxy%20broken%20asset%20symlinks.md)
- [Compose architecture reference](../architecture/03%20-%20Docker%20Compose%20Deep%20Dive.md)
- [Debian installation dynamics](./koha-debian-installation-dynamics.md)
- [koha-common gap analysis](./koha-common-alpine-gap-analysis.md)
