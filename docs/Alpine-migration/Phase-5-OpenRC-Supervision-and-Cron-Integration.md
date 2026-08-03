# Phase 5: OpenRC Service Supervision & Cron Integration

## Roadmap reference

[Alpine-deeper-integration.md](Alpine-deeper-integration.md) — Phase 5 section:

> **Action**: Add OpenRC init scripts for `koha-plack`, `koha-worker`, `apache2`, and `crond`.
>
> **Validation**: Verify background workers automatically restart if terminated, and scheduled cron jobs execute via Alpine `crond`.

---

## 0. Executive Summary

Phase 5 closes the final architectural gap from the deeper integration roadmap: unmonitored background process management and the absence of scheduled maintenance tasks.

Prior to Phase 5:
- `koha-plack` and `koha-worker` were started once at container boot via unmonitored `start-stop-daemon --background` calls. If they crashed, nothing restarted them.
- Container kept alive with `sleep infinity & wait`; SIGTERM was ignored rather than causing graceful shutdown.
- Alpine `crond` was not started; Koha's scheduled cron tasks (Zebra rebuild, overdue notices, hold expiry cleanup) never ran inside the container.

Phase 5 delivers:
1. **OpenRC init scripts** for `koha-plack`, `koha-worker`, and `apache2` — providing a standard service management interface.
2. **Service watchdog** (`run_service_watchdog`) in `run-sh-alpine.sh` — monitors running services and restarts them if they crash.
3. **Alpine `crond`** started at container boot, with Koha maintenance tasks in `/etc/periodic/`.
4. **Graceful container shutdown** — SIGTERM stops koha-plack and koha-worker cleanly before container exits.

---

## 1. Files Delivered

### 1.1 OpenRC Init Scripts (`files-alpine/openrc/`)

| File | Installed to | Role |
|---|---|---|
| `files-alpine/openrc/koha-plack` | `/etc/init.d/koha-plack` | OpenRC service for Plack/Starman PSGI server |
| `files-alpine/openrc/koha-worker` | `/etc/init.d/koha-worker` | OpenRC service for background job worker |
| `files-alpine/openrc/apache2` | `/etc/init.d/apache2` | OpenRC service for Alpine httpd (replaces crude shim) |

Each script follows the `#!/sbin/openrc-run` format and delegates to the Alpine-native admin commands (`/usr/sbin/koha-plack`, `/usr/sbin/koha-worker`, `/usr/sbin/httpd`).

Note: The `apache2` script replaces the crude 15-line `cat <<'EOF'` shim that was injected via `Dockerfile-Alpine`. The new script is a proper OpenRC service file.

### 1.2 Cron Scripts (`files-alpine/cron/`)

| File | Installed to | Schedule | Task |
|---|---|---|---|
| `files-alpine/cron/koha-hourly` | `/etc/periodic/hourly/koha-hourly` | Every hour | Zebra index rebuild (delta), process message queue |
| `files-alpine/cron/koha-daily` | `/etc/periodic/daily/koha-daily` | Daily at 02:00 | Database cleanup, cancel expired holds, overdue notices |
| `files-alpine/cron/koha-monthly` | `/etc/periodic/monthly/koha-monthly` | Monthly | Statistical archiving |

All cron scripts guard on `KOHA_CONF` existence — they exit silently if the instance has not been bootstrapped yet.

### 1.3 Helper Functions in `files-alpine/lib/run-sh-alpine.sh`

**`start_crond()`**:
- Starts Alpine BusyBox `crond` in background mode (`crond -b -l 2`).
- Safe no-op if `crond` is not available.

**`run_service_watchdog()`**:
- Observes which services are running when called (after `start_koha_service` completes).
- Only supervises services that were successfully started — does not interfere with disabled services.
- Monitors `koha-plack --status` and `koha-worker --status` every 30 seconds.
- Restarts any service that stops responding.
- Handles SIGTERM/SIGINT: stops supervised services cleanly and exits.
- Replaces the old `sleep infinity & wait` blocking-loop pattern.

### 1.4 `run.sh` changes

- Added `start_crond` call after `start_apache_service`.
- Replaced the old `sleep infinity` blocking loop with `run_service_watchdog "${KOHA_INSTANCE}"`.

### 1.5 `Dockerfile-Alpine` changes

- Added `COPY files-alpine/openrc/` → `/etc/init.d/` for all three init scripts.
- Added `COPY files-alpine/cron/koha-{hourly,daily,monthly}` → `/etc/periodic/{hourly,daily,monthly}/`.
- Added `RUN` step to ensure `/etc/crontabs/root` has `run-parts` entries for the periodic directories.

---

## 2. Architecture Notes

### 2.1 Why OpenRC init scripts + watchdog (not OpenRC full init)

OpenRC is designed to be the PID 1 init system. In this container, PID 1 is bash running `run.sh`. Attempting to fully delegate process management to OpenRC as a non-init service manager inside the container leads to unstable behavior.

The pragmatic architecture adopted here:
- OpenRC init scripts at `/etc/init.d/` provide the correct service management interface for `rc-service` calls (from admin tooling, future OpenRC integration, or manual operator use).
- The `run_service_watchdog` function provides the actual crash-recovery behavior using the native `koha-plack --status` / `koha-worker --status` exit codes from the Phase 4 Alpine scripts.

This is the container-idiomatic approach used by production Alpine images (e.g., linuxserver.io containers), where lightweight watchdog loops complement but do not replace the init script registry.

### 2.2 crond and `/etc/periodic/`

BusyBox crond reads `/etc/crontabs/root`. The Alpine base image includes `run-parts` entries for the `/etc/periodic/` subdirectories. Phase 5 ensures these entries exist (via the Dockerfile `RUN` guard) and installs Koha maintenance scripts into the correct directories.

The dev container is not a production mail server; cron tasks that fail (e.g., no SMTP relay) exit quietly via `>/dev/null 2>&1 || true`.

### 2.3 Graceful shutdown

Prior to Phase 5, `run.sh` trapped SIGTERM and ignored it (`trap : TERM INT`), requiring Docker to use SIGKILL after the 10-second grace period. The new `run_service_watchdog` trap:
1. Receives SIGTERM
2. Stops `koha-worker` and `koha-plack` cleanly via their `--stop` actions
3. Exits 0

This allows `docker stop` to complete within the grace period without SIGKILL.

---

## 3. Validation Criteria (from roadmap)

> "Verify background workers automatically restart if terminated, and scheduled cron jobs execute via Alpine `crond`."

**Static test assertions** (`tests/test_phase5_supervision.sh` — 35 static checks):
- OpenRC init scripts exist, have the correct shebang, and delegate to native commands.
- Dockerfile installs OpenRC scripts and cron tasks.
- Cron scripts guard on `KOHA_CONF` existence.
- `run-sh-alpine.sh` defines `start_crond()` and `run_service_watchdog()`.
- `run.sh` calls both functions and does not use the old blocking-loop pattern.
- `run_service_watchdog` handles SIGTERM and monitors `koha-plack`/`koha-worker` status and restart.

**Runtime smoke tests** (require running container — skipped without image):
- `crond` process is active.
- `/etc/periodic/` cron scripts are present.
- `/etc/init.d/koha-plack` and `/etc/init.d/koha-worker` are installed.
- `/ktd_ready` marker is present (container is alive and watchdog is running).

**Manual restart-recovery test**:
```bash
# Kill the starman master process inside the container
docker exec koha pkill starman
# Wait one check interval (30 s)
sleep 35
# Verify koha-plack has been restarted by the watchdog
docker exec koha koha-plack --status kohadev
# Expected: exit 0 (running)
```

---

## 4. Implementation Status

- [x] 4.1 `files-alpine/openrc/koha-plack` — OpenRC init script
- [x] 4.2 `files-alpine/openrc/koha-worker` — OpenRC init script
- [x] 4.3 `files-alpine/openrc/apache2` — OpenRC init script (replaces crude shim)
- [x] 4.4 `files-alpine/cron/koha-hourly` — Hourly cron script
- [x] 4.5 `files-alpine/cron/koha-daily` — Daily cron script
- [x] 4.6 `files-alpine/cron/koha-monthly` — Monthly cron script
- [x] 4.7 `start_crond()` in `run-sh-alpine.sh`
- [x] 4.8 `run_service_watchdog()` in `run-sh-alpine.sh`
- [x] 4.9 `run.sh` updated (crond start + watchdog replaces sleep loop)
- [x] 4.10 `Dockerfile-Alpine` updated (OpenRC + cron install steps)
- [x] 4.11 `tests/test_phase5_supervision.sh` — 35 static + 6 runtime checks
- [x] 4.12 `tests/run_all_tests.sh` updated (Phase 5 suite added)
- [ ] 4.13 Runtime verification: manual restart-recovery test on built image (pending image rebuild)
