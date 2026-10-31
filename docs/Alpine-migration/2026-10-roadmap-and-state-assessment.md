# Alpine Migration: State Assessment and Forward Roadmap

**Review date:** 2026-10-31

**Branch:** `phase`
**Scope:** Alpine container adaptation, its Koha Debian compatibility layer, migration records, tracker, and architecture references.

## Executive assessment

The project has moved past the initial Alpine port. It has a functioning development-image architecture, Alpine-specific Koha administration wrappers, a Plack/Apache integration, startup bootstrap logic, external database/broker/cache services, and static plus image-backed test suites. The migration notes mark the first five deeper-integration phases complete.

That status needs qualification:

1. The initial review found that `Dockerfile-Alpine` lacked the `prod-runtime` target required by `docker-compose.prod.yml`. Phase B added and validated the pinned production target.
2. The initial Phase 3 static test required an obsolete comment marker for a removed `koha-gitify` shim. The implementation was consistent with removing the shim; the assertion was corrected.
3. Phase 5's manual lifecycle gates were still open after the initial review. Phase D has now validated watchdog recovery, a controlled periodic task, broker connectivity, and graceful shutdown against a freshly built image.
4. The architecture pages under `docs/architecture/` mostly describe the original Ubuntu-oriented stack. Phase F adds explicit legacy notices and a current Alpine architecture page; the old material remains historical context, not an authoritative description of Alpine image internals.
5. An earlier review reported merge-conflict markers in configuration, but the current inspection found no conflict markers or duplicate keys in `env/.env`. The tracked environment and OpenSearch auth templates previously contained credential-capable values; those values were scrubbed from the current worktree, and the owner reports potentially active credentials have been rotated. Historical Git/remotes still need an owner-approved disposition before G0 can pass. `OpenSearch-3.6/.env` remains ignored and local.
6. Re-running Phase 4 guardrails exposed drift in `Dockerfile-Alpine` and `koha-worker`: the development image did not install its Alpine command overlays or `busybox-extras`, and the worker wrapper missed Koha's current `misc/workers` path and queue options. Those gaps were restored and exercised in the Phase D image.

The Alpine implementation has substantial evidence for the recorded pinned release: production and development images started in separate isolated projects, a fresh development database bootstrapped and passed Plack/API and browser checks, lifecycle checks passed, runtime reduction/least-privilege gates passed, and G2–G4 passed on 2026-10-30. G4 rehearsed an Ubuntu database copy using a production image built from the source's exact Koha commit; one malformed MARCXML record already present in the source is documented as a data-quality caveat. G5's 2026-10-31 rehearsal demonstrated database backup/restore across Koha versions and OpenSearch rebuild/search, but remains **PARTIAL** because RabbitMQ state, private keys/real host assets, failed-upgrade handling, and the built-in full restore path are unproven. **The overall end-to-end migration is not complete or accepted.** G6's volume-identity/cutover proof, G7's operations readiness, G8's independent operator walkthrough, and G9's owner sign-off remain open. See the [end-to-end acceptance gates](./End-to-end-migration-acceptance.md) and [G5 tracker record](../TRACKER/2026-10-31%20%E2%80%94%20G5%20backup%20and%20recovery%20rehearsal.md).

## Evidence-based implementation map

| Area | Present implementation | Assessment |
|---|---|---|
| Alpine build | `Dockerfile-Alpine` separates shared runtime, development source, and production source/runtime stages. | The Phase D dev image runs Node 22.23.4, locale support, compiled assets, the Alpine command layer, and `xmlstarlet`. It was built from the current Dockerfile; both runtime targets pass `buildx --check`. Phase C used the previously built dev image while the extracted Perl dependency installer was being rebuilt. |
| Development orchestration | `docker-compose-alpinekoha.yml` runs Koha with MariaDB, RabbitMQ, and Memcached; OpenSearch/Traefik networks are external. | Fixed container names have been removed, so Compose generates per-project names. Project-scoped DB/RabbitMQ volumes enable isolated validation without reusing the default deployment's data. |
| Koha bootstrap | `files-alpine/run.sh` renders Koha configuration, waits for MariaDB, initializes an empty DB, prepares assets and Apache, then starts Koha services and the watchdog. | A new isolated Phase C project completed the empty-database bootstrap, created the initial admin, upgraded to Koha 26.05.01, and restarted successfully against the populated database without deleting its volumes. |
| Shared helpers | `files-alpine/lib/run-sh-alpine.sh` contains Alpine-oriented service, vhost, cron, and watchdog behavior. | Phase D verified watchdog recovery of Plack and a real default-queue worker, ran a controlled periodic task, and confirmed the SIGTERM shutdown trap. |
| Admin commands | `files-alpine/scripts/` contains Alpine replacements for selected Debian `koha-*` tools; remaining upstream scripts and templates are sourced from `koha/debian`. | Build-time override installation, `busybox-extras`, and the worker's queue/path compatibility are restored. Phase E also ensures production `PATH` exposes the staged `/usr/sbin` commands; `koha-shell` and its packaged `PERL5LIB` were verified in both targets. |
| Build staging | `scripts/build-alpine-package.sh` reads `koha/debian/koha-common.install` and stages runtime resources. | Production build wiring was added in Phase B; the pinned production image contains the staged runtime assets and Alpine command overrides. |
| Production path | `docker-compose.prod.yml` requests `prod-runtime`, requires a release version/ref, and replaces the dev source-volume list. | The pinned `v26.05.01-1` image built successfully; provenance, baked assets, no source mount, pruned packages, production defaults, and a fresh isolated production startup were verified. |
| Tests | `tests/run_all_tests.sh` combines static, unit, image-backed, and integration checks. | The G2 closeout run passed 292 checks with 0 failures and 29 expected opt-in skips; Phase 5 supervision passed 50 checks with 0 failures and 1 expected runtime skip. Earlier Phase E/F results remain historical, separate runs rather than one combined acceptance result. |
| Upstream baseline | `koha/debian/scripts`, `koha/debian/templates`, and the Debian install manifest define the compatibility source of truth. | Keep Debian-specific packaging details at the boundary; avoid carrying a full Debian runtime/package manager into Alpine. |

### Phase completion, with remaining gates

| Phase | Recorded outcome | Remaining evidence or work |
|---|---|---|
| 1 — Native C libraries and Perl | YAZ 5.34.0 and Perl ZOOM modules are present in the pinned production image. | G2 passed a controlled outbound Z39.50 query and MARC result parse through Koha's configured search path. Inbound responder support remains explicitly excluded. |
| 2 — Build-time asset staging | Dev/prod image stages runtime assets from the Debian manifest at build time and installs Alpine overrides afterward. | G2 reconciled manifest payload staging, override precedence, PATH, and Alpine-specific exclusions against the rebuilt production candidate. |
| 3 — Dual-mode templating / Gitify removal | Project-owned templates and vhost rendering replace runtime Gitify behavior. | Keep the test assertions aligned to the actual no-Gitify contract. |
| 4 — POSIX admin tools / shim removal | Alpine rewrites exist for selected lifecycle commands; image overlay wiring and worker queue/path compatibility are restored. | The `koha-shell` config/`PERL5LIB` check passed in Phase D; broader compatibility coverage remains part of subsequent hardening. |
| 5 — OpenRC, watchdog, cron | OpenRC wrappers, periodic tasks, and a SIGTERM-aware watchdog are installed in the image. | Phase D runtime gates passed: Plack and worker recovery, controlled periodic work, and graceful shutdown with no orphaned container processes. |
| Dev/production split | Compose overlay and `stack-alpine.sh` mode selection exist. | G2 compatibility/Z39.50 and G3 production-feature acceptance passed on 2026-10-30 for Koha `v26.05.01-1`; the G4 imported-data rehearsal passed on Koha `26.06.00.003` from the exact source commit. G5–G9 remain open. The G2 candidate includes the hourly Zebra guard and has a distinct image ID from the earlier G3 run. |

## Decisions and safety rules

1. Keep the existing Debian-derived instance layout where it preserves Koha behavior; replace only OS/package/service assumptions that Alpine cannot provide.
2. Keep MariaDB, Memcached, RabbitMQ, and OpenSearch on explicit service/network boundaries. Keep Apache with Koha until lifecycle commands no longer mutate local web-server configuration.
3. Keep the source bind mount exclusive to development. Production must fetch a specified Koha ref at build time and must not inherit a source `VOLUME`.
4. Run verification stacks with a unique Compose project name. This gives test DB and RabbitMQ volumes unique names; do not use `down -v` against an existing or production project.
5. Treat HTTP status alone as insufficient: check real Koha HTML, static CSS/JS delivery, Plack health, CGI execution, and browser behavior.
6. Preserve pre-existing merge conflicts and unrelated worktree files. Resolve conflicts only with explicit owner direction.

## Forward roadmap

### Phase A — Reproducible, isolated baseline (complete)

- [x] Remove hard-coded Alpine service container names so a project-specific Compose name can isolate the test services.
- [x] Make the Alpine service's container env file overridable without editing the conflicted default file.
- [x] Set the development build target explicitly.
- [x] Add a Compose-only test that checks generated container naming and project-scoped DB/broker volumes without creating containers.
- [x] Run the static/unit suites against the current worktree; integration checks now require an explicitly selected test project and env file, and never start services or create volumes.
- [x] Build the dev image and run it only under a unique test project after checking the synthetic env, ports, and network isolation.

**Exit gate: passed.** Compose config proves unique volume names; the Alpine Docker build completes; no existing container or volume is reused.

### Phase B — Restore the immutable production image path (complete)

- [x] Add a separate source stage that fetches the configured Git ref and builds Koha assets.
- [x] Keep production based on a runtime-only base, not the development source-bearing stage.
- [x] Stage Debian-manifest runtime assets during the production build and reapply Alpine command overrides.
- [x] Set the production runtime to skip development-time asset installation/copy work.
- [x] Verify `KOHA_GIT_REF` is mandatory, branch refs are rejected, and an unavailable tag fails source resolution.
- [x] Build the production target from an explicit tag and inspect labels, source tree, assets, and absence of `.git`/`node_modules`.
- [x] Build production Perl dependencies from the fetched release source instead of the checked-out build-context source.
- [x] Start the production Compose stack under a new project with verified-absent project volumes, isolated ports/network, and production defaults; verify Koha HTTP and stylesheet delivery.

**Exit gate: passed.** Production Compose renders and builds from a pinned ref, contains the fetched source and built assets, has no source bind/anonymous source volume, and starts with its production defaults. The tested image was built from `v26.05.01-1`, resolving to `dacce7d3fc15860d26d06444c1f5c9a2d0d6a4a9`.

### Phase C — Fresh development-stack runtime validation (complete)

- [x] Use a new Compose project name and a valid, non-conflicted test env file.
- [x] Confirm DB and RabbitMQ volume names carry the test project prefix before starting.
- [x] Use the previously built, validated `dev-runtime` image; verify the current `dev-runtime` Dockerfile with `buildx --check`; start only after checking host ports and using the project network.
- [x] Bootstrap an empty database with the corrected admin-directory ownership, then confirm a populated-database restart.
- [x] Verify OPAC/staff HTTP and page-referenced CSS/JavaScript delivery.
- [x] Validate the Plack process and Unix socket, verify REST API routing on both virtual hosts, and perform a browser pass.
- [x] Restart Koha against the same populated isolated database without deleting its volumes.

**Exit gate: passed.** Fresh project `koha-alpine-test-phasec-dev-20261028a` completed an empty-database boot and a populated-database Koha restart. Database health, initial admin creation, schema version, OPAC/staff HTTP, referenced CSS/JS delivery, Plack socket, and both REST API routes were verified. The API probes return HTTP 401 with Koha JSON for unauthenticated requests, confirming the requests reach the API application rather than failing with 404.

### Phase D — Lifecycle and scheduled-work verification

- [x] Kill the Plack process in the isolated container and verify the watchdog detects it on the next 30-second poll; record recovery time including Plack startup.
- [x] Verify worker restart behavior when a real default-queue worker process is enabled for the test instance.
- [x] Trigger one controlled `/etc/periodic/` task and verify its observable marker.
- [x] Verify Docker stop completes within the configured grace period and leaves no orphaned Koha daemons.
- [x] Close the open Phase 4 `koha-shell` configuration check.

**Exit gate: passed.** The freshly built development image passed watchdog recovery, real-worker restart, a controlled `run-parts` task, RabbitMQ STOMP authentication, `koha-shell` configuration detection, and SIGTERM shutdown. Plack recovery completed in 33.46 seconds: the 30-second watchdog interval plus service startup. The worker recovered in 1.70 seconds. Docker stop completed in 0.52 seconds on the first run and 0.54 seconds on a second stop; all observed container processes exited with status 0 and no orphans.

### Phase E — Runtime reduction and least-privilege hardening (complete)

- [x] Move Node.js/npm/Yarn, Git, Perl build utilities, and MariaDB development headers out of the shared runtime package layer; keep the frontend toolchain in the development target.
- [x] Stop copying the complete `files-alpine` source tree into shared runtime layers. Keep only the entrypoint, startup helper, vhost template, OpenRC scripts, and periodic jobs needed at runtime; mount build overlays transiently and stage Alpine command wrappers during image assembly.
- [x] Replace world-writable runtime paths/socket permissions with a least-privilege Apache/Koha group contract in the entrypoint and Plack wrapper.
- [x] Replace `cap_add: ALL` with `cap_drop: ALL` and the explicitly reviewed `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `KILL`, `NET_BIND_SERVICE`, `SETGID`, and `SETUID` allowlist.
- [x] Make required database inspection, admin creation, service startup, and asset-build failures explicit; keep optional service/profile behavior logged.
- [x] Add an inherited Compose healthcheck for Plack status/socket and local OPAC and staff HTTP requests.
- [x] Build and inspect the final pinned production image; record exact size and verify build-only packages, source caches, private-key helper trees, and development-only files are absent.
- [x] Complete fresh dev and production runtime gates under the capability allowlist, including bootstrap, both web endpoints, socket/group permissions, health, worker/watchdog recovery, and graceful shutdown behavior.

**Exit gate: passed.** The pinned production image is 2,011,314,063 bytes, a reduction of 90,379,042 bytes (4.30%) from the 2,101,693,105-byte Phase B production baseline. The final image omits Node.js/npm/Yarn, Git, MariaDB development headers, CPAN build utilities, source caches, `.git`, `node_modules`, and the development TLS/helper trees. Both `dev-runtime` and `prod-runtime` passed `buildx --check`; the production image reports source ref `v26.05.01-1` and resolved commit `dacce7d3fc15860d26d06444c1f5c9a2d0d6a4a9`. Separate fresh-volume projects passed startup/API, health, permissions, credential-file, and supervision checks. The complete test runner passed 296 checks with 0 failures and 19 expected skips.

### Phase F — Release process and documentation alignment

- [x] Keep release validation independent of hosted CI; add a local procedure for tests, both Compose configs, and pinned development/production builds.
- [x] Update architecture pages that describe Ubuntu-only paths or obsolete ports so Alpine runtime behavior is clearly separated.
- [x] Document release tagging, source-ref provenance, image labels, rollback, secrets injection, and data-volume backup/restore.
- [x] Keep completed tracker work as historical evidence and maintain one current status/roadmap entry.

**Implementation complete; core recovery path partially validated.** The documented procedure covers building, inspecting, deploying, validating, and restoring a versioned production image. The 2026-10-31 G5 rehearsal verified a quiesced database backup, a separate-volume restore using the previous image, and an OpenSearch rebuild; it did not validate full external-state recovery or the built-in full restore command. See the [G5 tracker record](../TRACKER/2026-10-31%20%E2%80%94%20G5%20backup%20and%20recovery%20rehearsal.md). Rollback remains conditional on a successful pre-upgrade backup and availability of matching images and external TLS/host assets; the bundled backup is not a full-volume snapshot.

### End-to-end migration acceptance — not complete

The phase deliverables track implementation of the Alpine runtime. They do not,
by themselves, prove migration of an existing Ubuntu service. The separate
end-to-end acceptance gates remain open until their evidence is recorded:

- [x] G0: Record the owner-approved Git-history/remotes disposition, verify
  rotated credentials, and close out the sanitized tracked-config and
  external-injection review.
- [x] G1: Run the local CI-independent validation script and record both full
  builds, test results, Koha commit, image IDs/digests, and tool versions.
- [x] G2: Rebuild/run the candidate production image, reconcile Debian
  manifest/runtime commands, and execute a configured Koha Z39.50
  query/result parse. Evidence: candidate image
  `koha-alpine-acceptance:26.05.01-1-g2`; see the dated G2 tracker addendum.
- [x] G3: Pass production-mode login, catalogue create/edit, patron, circulation,
  background-job, OpenSearch TLS/auth/search, and MARCXML import checks. Evidence:
  isolated project `koha-alpine-test-g3tls`, 16/16 checks, 2026-10-30; the current
  G2 candidate additionally passed a fresh OpenSearch rebuild/import/search recheck.
  See the acceptance matrix and dated tracker addenda. The full 16-check workflow
  was not repeated on the current candidate.
- [x] G4: Rehearse migration of a protected representative Ubuntu data copy in
  an isolated project and reconcile schema/data/operations. Evidence:
  project `koha-g4-20261030`, exact Koha source commit, baseline record/patron/
  item/branch counts, authenticated workflows, TLS, and OpenSearch search passed.
  One pre-existing malformed MARCXML record is recorded as a source-data caveat;
  see the G4 tracker record and acceptance matrix.
- [ ] G5: **PARTIAL (2026-10-31).** Database backup/restore, previous-image
  recovery, and OpenSearch rebuild/search were observed on separate volumes.
  RabbitMQ state, private keys/real host assets, an intentional failed upgrade,
  and the helper's full restore path remain open; see the G5 tracker record.
- [ ] G6: Verify the exact production Compose project and DB/RabbitMQ volumes;
  prove no fresh-bootstrap/reset path is used for migrated data.
- [ ] G7: Verify production secret/TLS controls, health/monitoring, retention,
  capacity, and operational ownership.
- [ ] G8: Complete an independent operator walkthrough of the updated runbook.
- [ ] G9: Record service-owner sign-off and approved scope/exclusions.

See the [acceptance matrix and evidence requirements](./End-to-end-migration-acceptance.md).
Until all required gates pass, use the status: **Alpine image implementation
validated for the recorded releases; the G4 Ubuntu-data rehearsal passed and
the G5 database recovery path is partially validated, but full production
recovery and owner approval remain pending.**

## Current review changes

The initial migration continuation advanced Phases A through C, and follow-up work completed the pinned production image, fresh development-stack validation, and Phase D lifecycle gates:

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
- The production dependency stage now installs the release `cpanfile` requirements and Koha-specific modules from the exact source fetched by `prod-source`; dev and production share one dependency-install script. This avoids pairing a release's source with Perl dependencies from a potentially different development checkout.
- Production source refs are required, branch refs are rejected, tag refs are fetched explicitly under `refs/tags/`, and 40-/64-character commit IDs are accepted. The resolved Git commit, source URL, and requested ref are saved in image metadata files; OCI source/version/revision labels are emitted.
- The production Compose override now replaces (rather than inherits) the development volume list. A merged config check confirms the production target/image tag and absence of `/kohadevbox/koha` source mount. Compose also rejects a missing release ref/version.
- The upstream tag `v26.05.01-1` exists and resolves to `dacce7d3fc15860d26d06444c1f5c9a2d0d6a4a9`. A production source build with a nonexistent tag fails at Git fetch as expected. The full production image built successfully as `koha-alpine-prod:phase-b-26.05.01` (image ID `sha256:55ebedb671552e58ef26737a0e8f2d1e5103b6d34b8dd2a4ffde246917130d6c`, 2,101,693,105 bytes). Its metadata files report the source URL, requested tag, and exact resolved commit; `.git`, `node_modules`, and declared image volumes are absent.
- A production Compose project was started as `koha-alpine-prod-test-phaseb-20261028` after confirming its DB/RabbitMQ volumes did not exist, ports 18180/18181 were free, and the Koha service had no checkout mount. The fresh MariaDB became healthy; Koha completed startup and the isolated production startup smoke passed 7/7. OPAC/staff returned HTTP 200, and the baked OPAC and intranet CSS URLs returned HTTP 200. The starter stylesheet is under `intranet-tmpl/prog/css/` (not `prog/en/css/`); runtime template symlinks resolve correctly.

Phase C's API probe found that the custom development vhost proxied `/api` directly to Plack without Koha's standard rewrite to `/api/v1/app.pl/api/v1/...`; valid API calls returned 404 on both virtual hosts. Added the upstream-compatible rewrite to the OPAC and staff vhosts and regression assertions to the Phase 3 static test. After recreating only the Koha service against the same test DB, both paths returned Koha's JSON HTTP 401 authentication response. The startup smoke test now checks the Plack process/socket and both API routes.

Fresh development runtime project `koha-alpine-test-phasec-dev-20261028a` used verified-absent project DB/RabbitMQ volumes and dedicated ports 18280/18281. The empty DB was initialized, the `admin` superlibrarian was created, the schema upgraded to version `26.0501000`, and MariaDB reported healthy. The first-boot smoke passed before the API regression was found; after the vhost fix, the populated-DB restart passed 4/4 and the expanded startup smoke passed 10/10. A browser pass rendered the OPAC home page and staff login page. Local linked assets checked from the actual HTML returned HTTP 200: OPAC 2 CSS and 17 JavaScript files; staff 8 CSS and 20 JavaScript files. The Plack Unix socket exists and reports running.

Phase D used a fresh build tagged `koha-alpine:phase-d-20261028` (image ID `sha256:ff58b63548292ccf303b749e921a43b52bd8da790d94dfbe93c4973bc57e5412`, 3,608,750,482 bytes) in project `koha-alpine-test-phased-20261028a`, with dedicated ports 18380/18381 and newly verified-absent DB/RabbitMQ volumes. The current image passed `buildx --check`; its isolated database bootstrapped to schema `26.0501000` with one admin borrower row, MariaDB became healthy, both web endpoints returned 200, and the Koha container had no source-checkout mount (only the read-only MariaDB CA certificate bind).

Phase D exposed two runtime integration gaps. `koha-shell` needs `xmlstarlet` to detect the instance's Git-install state; it is now installed in the shared runtime base, and the runtime check selected `/usr/share/koha/lib` from `/etc/default/koha-common` for this installed-style instance. Separately, the entrypoint had rendered literal RabbitMQ `guest` credentials despite Compose supplying broker credentials. It now renders `MESSAGE_BROKER_USER`, `MESSAGE_BROKER_PASS`, and `MESSAGE_BROKER_VHOST`, escaping values for the `sed` replacement context. The active STOMP session was confirmed with RabbitMQ's STOMP-specific `list_stomp_connections` command as user `koha`, in `running` state with protocol `STOMP`; the configured `koha_kohadev` vhost grants that user permissions. The initially empty `list_connections` result was not evidence of failure: RabbitMQ documents that command as AMQP 0.9.1-only.

The watchdog recovered Plack in 33.46 seconds end-to-end (one 30-second poll interval plus Plack startup) and the real default-queue worker in 1.70 seconds; both recovery events were logged. A controlled executable marker in `/etc/periodic/hourly/` ran through `run-parts` and wrote the expected marker. The Phase 5 supervision test passed 45/45 against the selected container. Graceful Docker stop completed in 0.52 and 0.54 seconds against the configured 60-second grace period, PID 1 completed its shutdown trap with exit code 0, and all 16/14 observed host process IDs exited without orphans. `docker compose down` removed the isolated containers and network without `-v`; the new test volumes were retained, and the pre-existing `koha-docker-db-1` and its data volume remained untouched.

During the initial review, the image `koha-alpine:phase-roadmap-validation` (image ID `sha256:5102268254536ebc8ed6c1bf57d5bb160b8a29174b9a791802fb53e3d7b8f8e5`) was reused while a full rebuild was deferred because the dependency-stage cache had been invalidated. That limitation was resolved in Phase D/E: the current dev target was fully rebuilt with the shared Perl dependency installer and the pinned production target was also rebuilt. The Phase C containers were stopped without `down -v`, preserving their new volumes; the existing `koha-docker-db-1` container and `koha-docker_koha-db-data` volume remain untouched. The conflicted `env/.env` and OpenSearch security file have not been edited or resolved; `.vscode/` is pre-existing untracked content and is outside this change.

Phase E completed the runtime split, transient build overlays, capability allowlist, restrictive runtime permissions, explicit required-startup failures, and Compose readiness check. The production runtime audit also found that its `PATH` omitted `/usr/sbin`, preventing access to packaged Koha administrative commands; the production target now includes the Alpine system command directories. The `koha-create` live guardrail uncovered an empty optional config path being passed to the POSIX `.` builtin; that path is now guarded, and the test checks the actual CLI invocation rather than assuming normal entrypoint startup creates `/etc/koha/passwd`. The final pinned production image is 2,011,314,063 bytes, 4.30% below the Phase B baseline, and both fresh Phase E projects passed startup/API and Phase 5 runtime checks. See the Phase E tracker for per-file changes, image evidence, and data-volume handling.

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
| Full test runner | Final selected-project run: 296 passed, 0 failed, 19 expected skips. Separately, the final Phase E dev and production startup smoke tests each passed 10/10. |
| Frontend build stage | Koha `yarn install` and `yarn build` completed successfully during the first isolated build attempt; image assembly was stopped to incorporate the newly identified Phase 4 fixes. |
| Corrected dev image build / container start | Phase D rebuilt the current dev target with the shared Perl dependency installer and runtime `xmlstarlet`; Node is v22.23.4, locale and compiled OPAC CSS are present, both Dockerfile targets pass `buildx --check`, all five image-backed Phase 4 scripts pass, and the isolated persistent-DB restart passed 4/4 checks. |
| Fresh runtime stack | Phase C project `koha-alpine-test-phasec-dev-20261028a`; new verified-absent project DB/RabbitMQ volumes. Empty DB bootstrap and populated-DB restart passed; MariaDB healthy; Koha 26.05.01 schema and initial admin verified. Expanded smoke passed 10/10 including Plack socket and both API routes. |
| Browser and static assets | OPAC and staff login pages rendered in the browser. Actual page references checked: OPAC 2 CSS/17 JS and staff 8 CSS/20 JS, all HTTP 200. OPAC/staff home endpoints return 200. |
| Runtime isolation | Phase C used dedicated ports 18280/18281 and only its project network; its new volumes are preserved after stopping containers without `down -v`. Existing `koha-docker-db-1` and `koha-docker_koha-db-data` remain untouched. |
| Phase D lifecycle | Fresh project `koha-alpine-test-phased-20261028a`; new verified-absent volumes; ports 18380/18381; no source checkout mount. Database bootstrapped, schema `26.0501000`, admin row present, and OPAC/staff returned 200. Watchdog recovered Plack in 33.46s (30s poll plus startup) and worker in 1.70s; periodic marker ran; broker STOMP session authenticated as `koha`; `koha-shell` detected the instance and loaded `/usr/share/koha/lib`. Selected-container supervision checks passed 45/45. |
| Phase D shutdown and data safety | Graceful stop completed in 0.52s and 0.54s within 60s; exit code 0, shutdown trap completed, and 16/14 observed processes exited. Ordinary `docker compose down` removed containers/network but retained both Phase D volumes. Existing `koha-docker-db-1` remained running with its original volume. |
| Phase C API regression | Custom vhost now applies Koha's rewrite to the Plack-mounted `/api/v1/app.pl` route for OPAC and intranet. Unauthenticated `/api/v1/patrons/` returns the expected Koha JSON 401 on both ports instead of 404. |
| Production runtime | Fresh project `koha-alpine-prod-test-phaseb-20261028`; new, verified-absent DB/RabbitMQ volumes; ports 18180/18181; no source checkout mount. Startup smoke 7/7; OPAC and staff HTTP 200; OPAC and intranet CSS HTTP 200; runtime template links and `koha-create` verified. Stack stopped without deleting volumes. |
| Phase B source checks | `prod-source`/`prod-runtime` `buildx --check` passes; release tag availability/commit verified; missing Compose ref and invalid fetched tag fail; production Compose has no inherited source bind. Pinned image, provenance, assets, production defaults, and isolated runtime all verified. |
| Phase E image reduction | Dev image `sha256:ef182b494ea9762761fd2fe4be5354b4f09e61f01cd602a0ffc04da1633d6052`, 3,582,352,569 bytes. Production image `sha256:842ca5dfcabcd0fefe04179186361a64577840502c309ece3a08f2e38e937f37`, 2,011,314,063 bytes; 90,379,042 bytes (4.30%) below the Phase B production baseline. Build-only packages and development-only paths are absent; source provenance files are present. |
| Phase E runtime evidence | Fresh dev project `koha-alpine-test-phasee-20261028a` used ports 18380/18381 and fresh project DB/RabbitMQ volumes. Fresh production project `koha-alpine-test-phasee-prod-20261028a` used ports 18480/18481 and separate fresh volumes; merged Compose mounts contain no Koha checkout. Both smoke tests passed 10/10 and both Phase 5 runtime audits passed 64/64. Plack and the default worker recovered under new PIDs after targeted termination. Generated MySQL client files are root-owned mode 0600; health, capabilities, group/socket permissions, `koha-shell`, and packaged `PERL5LIB` checks passed. |
| Phase E full validation | `tests/run_all_tests.sh`: 296 passed, 0 failed, 19 expected skips. Both `buildx --check` targets, shell syntax checks, and `git diff --check` passed. The pre-existing `koha-docker-db-1` remained running; both Phase E projects used project-scoped volumes and are torn down without volume deletion after validation. |
| Phase F implementation checks | Earlier local test runner: 268 passed, 0 failed, 29 opt-in skips. After credential hygiene hardening, the current suite passed 276 tests with 0 failures and 29 expected opt-in skips; both Compose configs passed. Full builds were safely blocked because Docker storage had only 8.8 GiB free, below the 15 GiB preflight threshold. No services or volumes were started or modified; unrelated existing containers remained running. The hosted workflow was removed to honor the CI-independence decision. Full builds and a disposable restore rehearsal remain pending. |

## Source and document references

- [Alpine deeper-integration roadmap](./Alpine-deeper-integration.md)
- [Phase 3 specification](./Phase-3-Dual-Mode-Templating-and-koha-gitify-Elimination.md)
- [Phase 4 specification](./Phase-4-POSIX-Admin-Tools-and-Shim-Removal.md)
- [Phase 5 specification](./Phase-5-OpenRC-Supervision-and-Cron-Integration.md)
- [Fixed-version production image strategy](./koha-fixed-version-production-image-strategy.md)
- [Phase B pinned production image and isolated startup tracker](../TRACKER/2026-10-28%20%E2%80%94%20Phase%20B%20pinned%20production%20image%20and%20isolated%20startup.md)
- [Phase C fresh database, Plack API routing, and browser validation tracker](../TRACKER/2026-10-28%20%E2%80%94%20Phase%20C%20fresh%20database%20Plack%20API%20routing%20and%20browser%20validation.md)
- [Phase D lifecycle, worker, cron, broker, and graceful shutdown tracker](../TRACKER/2026-10-28%20%E2%80%94%20Phase%20D%20lifecycle%20worker%20cron%20broker%20and%20graceful%20shutdown.md)
- [Phase E runtime reduction and production validation tracker](../TRACKER/2026-10-28%20%E2%80%94%20Phase%20E%20runtime%20reduction%20and%20production%20validation.md)
- [Phase F release operations](./Phase-F-release-operations.md)
- [End-to-end migration acceptance gates](./End-to-end-migration-acceptance.md)
- [Current migration and upgrade runbook](./koha-version-migration-runbook.md)
- [Phase F release operations and architecture tracker](../TRACKER/2026-10-29%20%E2%80%94%20Phase%20F%20CI%20release%20operations%20and%20architecture%20alignment.md)
- [End-to-end migration closure assessment tracker](../TRACKER/2026-10-29%20%E2%80%94%20End-to-end%20migration%20acceptance%20gates%20and%20runbook%20alignment.md)
- [Alpine test grounds](./Alpine-Koha-test-grounds.md)
- [Compose architecture reference](../architecture/03%20-%20Docker%20Compose%20Deep%20Dive.md)
- [Debian installation dynamics](./koha-debian-installation-dynamics.md)
- [koha-common gap analysis](./koha-common-alpine-gap-analysis.md)
