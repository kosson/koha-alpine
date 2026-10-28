# Phase D — Lifecycle, Worker, Cron, Broker, and Graceful Shutdown

**Date:** 2026-10-28  
**Branch:** `phase`  
**Result:** Phase D exit gate passed against a freshly built Alpine development image.

## Scope

Phase D closes the lifecycle and scheduled-work checks left open by the Phase 5 OpenRC/watchdog work:

- Recover Plack and a real background worker after forced process termination.
- Run a controlled task through Alpine's `/etc/periodic/` and `run-parts`.
- Verify that the worker reaches RabbitMQ over STOMP with the configured identity.
- Confirm `koha-shell` detects the running instance's install mode and loads its correct Perl library path.
- Stop the Koha container gracefully within the Compose grace period and ensure no container processes remain.

## Changes made

### `Dockerfile-Alpine`

Added `xmlstarlet` to the shared `runtime-base` package set. Koha's upstream `koha-shell` invokes XML parsing helpers to inspect `koha-conf.xml` and distinguish a Git install from an installed-style instance. Without this runtime dependency, the command could not complete its configuration detection. Because this is a shared runtime dependency, both development and production targets inherit it.

### `files-alpine/run.sh`

Changed the generated Koha broker configuration to use the Compose-provided `MESSAGE_BROKER_USER`, `MESSAGE_BROKER_PASS`, and `MESSAGE_BROKER_VHOST` instead of writing literal `guest` credentials. The values are escaped for the existing `sed` replacement context before insertion. This fixes configuration drift between the environment supplied by Compose and the broker credentials actually written to Koha's instance configuration.

### `docker-compose-alpinekoha.yml`

Set `stop_grace_period: 60s` for the Koha service. This gives PID 1's watchdog shutdown trap time to stop the supervised Koha services before Docker forcibly terminates the container.

### Regression and runtime checks

- `tests/test_run_sh_static.sh` now checks that broker username, password, and vhost come from the corresponding environment values rather than hard-coded `guest` settings.
- `tests/test_alpine_compose_isolation.sh` checks the 60-second graceful-stop setting.
- `tests/test_phase5_supervision.sh` requires an explicitly selected `KOHA_CONTAINER`, avoiding an unsafe implicit/default container target. It no longer treats the obsolete `/ktd_ready` signal as readiness; it verifies the live `run.sh` PID 1 and watchdog startup instead. It also checks `xmlstarlet`, `koha-shell`, and the packaged `PERL5LIB` in the selected container.

## Isolated runtime setup

The test used project `koha-alpine-test-phased-20261028a`, with OPAC and staff ports 18380/18381. Before the first startup, both project-specific data volumes were confirmed absent:

- `koha-alpine-test-phased-20261028a_koha-db-data`
- `koha-alpine-test-phased-20261028a_koha-rabbitmq-data`

The stack used the newly built image `koha-alpine:phase-d-20261028`, image ID `sha256:ff58b63548292ccf303b749e921a43b52bd8da790d94dfbe93c4973bc57e5412`, size 3,608,750,482 bytes. Dockerfile `buildx --check` passed. The Koha service did not mount the source checkout; its only bind mount was the read-only MariaDB CA certificate.

MariaDB became healthy, the fresh database completed bootstrap at schema version `26.0501000`, and one initial admin borrower row was present. The OPAC and staff endpoints both returned HTTP 200. The default-queue background worker, Plack, Apache, and `crond` were running.

## Runtime results

### Watchdog recovery

- Forced termination of Plack was followed by watchdog recovery under a new PID. Recovery completed in **33.46 seconds**. The watchdog poll is 30 seconds; the additional time is Plack startup after detection. This is recorded as one polling interval plus service startup, not as a claim that the entire recovery completed in under 30 seconds.
- Forced termination of the real `background_jobs_worker.pl --queue default` process was followed by recovery under a new PID in **1.70 seconds**.
- Container logs recorded both watchdog restart events.

### Periodic task

Installed a temporary executable marker task in `/etc/periodic/hourly/`, ran it through `run-parts`, and verified that it wrote the expected marker. The temporary task was removed after the check.

### RabbitMQ STOMP connection

Koha's generated `koha-conf.xml` contained broker user `koha` and vhost `koha_kohadev`. RabbitMQ's `list_stomp_connections` command showed a live STOMP connection with `auth_login=koha`, `connection_state=running`, protocol `STOMP`, and the STOMP header authentication mechanism. `rabbitmqctl list_permissions --vhost koha_kohadev` confirmed that this user has permissions on the configured vhost.

An earlier diagnostic queried `rabbitmqctl list_connections` and received an empty list. This was the wrong protocol-specific view: RabbitMQ's CLI help describes `list_connections` as an AMQP 0.9.1 connection listing and provides the separate `list_stomp_connections` command for STOMP. Using the latter confirmed the expected live authenticated worker session.

### `koha-shell`

The Phase 5 supervision test confirmed that `koha-shell` is executable and can inspect the instance configuration. This runtime instance is installed-style (`git_install=0`), so the expected `PERL5LIB` is `/usr/share/koha/lib`, not a Git checkout path. The selected-container runtime assertion passed with that value.

### Graceful shutdown and orphan check

Compose resolved the Koha service grace period to 60 seconds. `docker compose stop koha` completed in **0.52 seconds** during the initial run and **0.54 seconds** after the broker diagnostic restart. In both runs:

- The container exited with status 0.
- PID 1 logged that it received the shutdown signal and completed its watchdog shutdown trap.
- Every observed container process host PID exited; no orphan process remained.

The Phase 5 supervision test passed **45/45** checks against the explicitly selected running container.

## Data and environment safety

After validation, the stack was stopped with ordinary `docker compose down` (never `down -v`). The isolated containers and project network were removed, while both new Phase D data volumes remain present. The existing `koha-docker-db-1` container remains running with its original `koha-docker_koha-db-data` volume. Temporary Phase D Compose environment and override files were removed from the session files directory.

## Validation summary

| Validation | Result |
|---|---|
| Current development image build | Completed; tag and image ID recorded above |
| Dockerfile check | `buildx --check` passed |
| Full configured test runner | 231 passed, 0 failed, 29 skipped |
| Shell syntax and whitespace | Changed shell files passed `bash -n`; `git diff --check` passed |
| Isolated fresh DB | MariaDB healthy; schema `26.0501000`; admin row present |
| OPAC and staff | Both HTTP 200 |
| Plack watchdog recovery | New process; 33.46 seconds including 30-second poll and startup |
| Real worker watchdog recovery | New process; 1.70 seconds |
| Periodic task | `run-parts` executed task and marker was verified |
| RabbitMQ | Active STOMP connection authenticated as `koha`; configured vhost permission verified |
| `koha-shell` | Configuration detection passed; `PERL5LIB=/usr/share/koha/lib` |
| Phase 5 supervision checks | 45 passed, 0 failed, 0 skipped |
| Graceful stop | 0.52/0.54 seconds within 60 seconds; exit code 0; no orphan processes |
| Cleanup | Containers/network removed; test volumes preserved; existing DB container/volume untouched |

Phase E can proceed from this lifecycle baseline. The next gates are runtime reduction, least-privilege permissions/capabilities, explicit startup failure policy, and health/readiness checks.
