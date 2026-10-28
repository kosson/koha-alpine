# Phase C: Fresh Database, Plack API Routing, and Browser Validation

**Date:** 2026-10-28  
**Branch:** `phase`  
**Status:** Phase C exit gate passed; current dev-target rebuild remains a follow-up

## Outcome

Validated a fresh development Koha database boot, a restart against the populated database, Plack/socket health, OPAC and intranet API routing, web assets, and both browser pages using a new isolated Compose project. The run exposed and fixed a REST API routing defect in the custom Alpine development vhost.

## Issue found and change made

### REST API endpoints returned 404

Before the fix, `GET /api/v1/patrons/` returned `404 Not Found` from both the OPAC and staff HTTP ports. The Plack Unix socket was active, but the development vhost sent `/api` directly to the Plack socket without rewriting Koha's public API path to the API app mount.

Koha's `plack.psgi` mounts its API application at `/api/v1/app.pl`. The upstream Koha Plack Apache configuration rewrites public routes such as `/api/v1/patrons/` to `/api/v1/app.pl/api/v1/patrons/` before proxying. The custom vhost omitted that rewrite in both virtual hosts.

**Fix:** added the upstream-compatible `RewriteCond` and `RewriteRule` to both OPAC and intranet sections of [koha-vhost.conf.in](../../files-alpine/templates/koha-vhost.conf.in), ahead of the `/api` proxy directives. No API application or authentication behavior was changed.

### Regression coverage

- [test_phase3_dual_mode_templating_static.sh](../../tests/test_phase3_dual_mode_templating_static.sh) now asserts the API rewrite rule and the guard that avoids rewriting requests already addressed to `app.pl`.
- [test_alpine_startup_smoke.sh](../../tests/test_alpine_startup_smoke.sh) now verifies the Plack status and socket, and requests `/api/v1/patrons/` through both HTTP virtual hosts. An unauthenticated request is expected to return HTTP 401; that confirms the API application handled the request, whereas the previously observed 404 signaled a routing failure.

## Isolated runtime procedure and results

- Project: `koha-alpine-test-phasec-dev-20261028a`.
- Test image: `koha-alpine:phase-roadmap-validation`, image ID `sha256:5102268254536ebc8ed6c1bf57d5bb160b8a29174b9a791802fb53e3d7b8f8e5`.
- This previously built dev image was reused; inspection confirmed Node v22.23.4, Alpine 3.20.10, the `locale` binary, and compiled OPAC CSS. The current Dockerfile's `dev-runtime` target passes `docker buildx build --check`.
- Host ports 18280/18281 were confirmed free before starting. The Koha service was attached only to the project network.
- The project DB/RabbitMQ volumes were verified absent before startup:
  - `koha-alpine-test-phasec-dev-20261028a_koha-db-data`
  - `koha-alpine-test-phasec-dev-20261028a_koha-rabbitmq-data`
- MariaDB became healthy. Koha initialized the empty database, created one `admin` superlibrarian (`cardnumber=1`), ran the schema upgrades, and logged startup complete. The database reported version `26.0501000`.
- Initial startup smoke before the API routing fix passed 7/7 checks. After editing the vhost, only the Koha service was recreated; the populated DB stayed in place. The restart integration passed **4/4**, and the expanded startup smoke passed **10/10**.
- `koha-plack --status kohadev` reported running and `/var/run/koha/kohadev/plack.sock` existed. A direct API request over that socket returned HTTP 401 JSON, as expected without credentials.
- Both `/api/v1/patrons/` virtual-host requests returned `401` with `application/json; charset=utf8`, replacing the prior 404.
- OPAC and staff pages rendered in the browser. The OPAC home page and staff login page showed the expected Koha UI.
- Assets parsed from the actual pages all returned HTTP 200: OPAC 2 CSS and 17 JavaScript resources; staff 8 CSS and 20 JavaScript resources.

## Test results

- `bash tests/test_phase3_dual_mode_templating_static.sh`: **26 passed, 0 failed**.
- `bash -n tests/test_alpine_startup_smoke.sh tests/test_phase3_dual_mode_templating_static.sh`: passed.
- `bash tests/test_alpine_startup_smoke.sh` against the selected project: **10 passed, 0 failed**.
- `bash tests/test_restart_integration.sh` against the selected project: **4 passed, 0 failed**.
- `bash tests/run_all_tests.sh`: **231 passed, 0 failed, 34 skipped**. Runtime integration checks are opt-in and skip in the default invocation without a selected project/env.
- `git diff --check`: passed.

## Build note

A full `dev-runtime` rebuild from the updated Dockerfile was attempted. The new shared Perl dependency installer invalidated the dependency-layer cache and began reinstalling Koha's complete CPAN set, so that redundant build was stopped rather than prolonging the Phase C runtime verification. Runtime validation used the previously built and validated dev image identified above. The current Dockerfile target passes `buildx --check`, and the Phase B production build successfully exercised the shared dependency installer. A full rebuild of the current dev target remains a reproducibility follow-up; this limitation is explicitly retained in the roadmap.

## Data safety and cleanup

After validation, the test project was stopped with `docker compose down` (without `-v`). Its two newly created volumes remain present for later inspection/reuse only if explicitly selected; do not treat them as new test data for a future "fresh DB" check. The temporary synthetic environment and Compose override files in the session workspace were removed. No existing Koha volume was reused or removed. `koha-docker-db-1` remained running, and `koha-docker_koha-db-data` remained present.

## Next work

Phase C is complete. Phase D remains open for watchdog recovery after a controlled Plack failure, worker restart behavior, scheduled-task verification, graceful shutdown, and the remaining `koha-shell` compatibility check.
