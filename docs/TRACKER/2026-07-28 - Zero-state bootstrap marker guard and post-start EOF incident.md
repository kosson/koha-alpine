# 2026-07-28 - Zero-state bootstrap marker guard and post-start EOF incident

Status: In progress (primary mitigation implemented, runtime EOF incident logged)
Severity: High (repeated OPAC/Intranet 500 with Auth session failure on zero-style starts)
Scope: stack orchestration, bootstrap state detection, startup reproducibility, diagnostics

---

## User-reported recurring symptom

On another machine (and intermittently during local reproduction), OPAC and Intranet returned repeated HTTP 500 with:

- `Auth ERROR: Cannot get_session() at /kohadevbox/koha/C4/Auth.pm line 1026`
- `End of script output before headers`

This happened even when DB/TLS looked mostly configured.

---

## Findings collected in this session

1. Session backend preference looked normal in DB:
   - `SessionStorage = mysql`
2. `sessions` table existed and was non-empty-capable (`COUNT(*)` check passed).
3. The failure pattern aligned with a partially initialized install being resumed as if it were complete.
4. Existing logic used `systempreferences` as a proxy for database readiness; that can be true even when first bootstrap is not fully complete.
5. A stale local path in `env/.env` was found:
   - `SYNC_REPO` still pointed to an old machine path and caused `mkdir: Permission denied` during source checks.

---

## Changes implemented

### 1) Marker-aware startup guard in stack manager

File:
- `stack-alpine.sh`

Added:

1. `BOOTSTRAP_MARKER="${SYNC_REPO}/.alpine-bootstrap-complete"`
2. `koha_bootstrap_marker_present()` helper
3. `start --no-fresh-db` behavior change:
   - if DB has `systempreferences` and marker exists -> reuse DB (resume)
   - if DB has `systempreferences` but marker missing -> force full bootstrap path (`ALPINE_BOOTSTRAP_PROFILE=full`)
   - if DB is empty -> fallback to fresh bootstrap (`reset_database`)
4. `restart --no-fresh-db` mirrors the same marker-aware behavior

Goal: prevent false resume on half-initialized databases that trigger auth/session breakage.

### 2) Persist bootstrap completion marker from container runtime

File:
- `files-alpine/run.sh`

Added after readiness stage:

- `touch /kohadevbox/koha/.alpine-bootstrap-complete`

This writes a durable host-side completion marker only after runtime reaches final startup.

### 3) Clear marker when state is destructively reset

File:
- `stack-alpine.sh`

Added:

1. Marker removal on `reset` command end
2. Marker removal inside `reset_database()` so DB recreation cannot leave a stale “complete” marker

### 4) Fixed stale machine-local source path

File:
- `env/.env`

Updated:

- `SYNC_REPO=/media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-alpine/koha`

This removed the local path mismatch causing source-tree preparation failures.

### 5) Static test coverage extension

File:
- `tests/test_stack_sh_static.sh`

Added assertions for:

1. marker presence check function
2. marker cleanup on reset

---

## Validation outcomes

### Static / syntax checks

1. `bash -n stack-alpine.sh` -> `STACK_SYNTAX_OK`
2. `bash tests/test_stack_sh_static.sh` -> pass (`15` checks)

### Live startup behavior (key observations)

1. Stack startup now logs:
   - `--no-fresh-db: bootstrap marker missing, forcing full bootstrap on existing DB`
   - `Alpine bootstrap profile: full (forcing DB population/reindex on existing DB)`
2. This confirms the new guard is active and no longer trusts a partially initialized state.
3. During the observed run, bootstrap advanced through long full-path tasks (`do_all_you_can_do.pl`, `koha-rebuild-zebra`), so OPAC/Intranet remained `000` while services were still initializing.

---

## Incident captured during this same run

At the end of one long startup run, the shell reported:

- `stack-alpine.sh: line 1274: unexpected EOF while looking for matching "`'

Additional facts recorded immediately after:

1. `wc -l stack-alpine.sh` -> `1274`
2. `bash -n stack-alpine.sh` -> syntax OK

Interpretation:

- The EOF report is recorded as an observed runtime incident from that run output.
- Current file syntax checks cleanly, so the error may have been triggered by a transient/older in-memory script copy, shell state, or an intermediate file state during that specific execution.
- Keep this incident tracked until reproduced under controlled rerun.

---

## Current state at log time

1. Marker file currently not yet present:
   - `.alpine-bootstrap-complete` missing (full bootstrap still in progress when checked)
2. Core infra was up (Traefik/OpenSearch/DB/Memcached/RabbitMQ), while Koha was still executing full bootstrap/index tasks.
3. No fresh `Auth ERROR: Cannot get_session()` lines were seen in container log scans during the tracked bootstrap window.

---

## Next verification pass recommended

1. Let full bootstrap finish until:
   - `/ktd_ready` exists
   - `.alpine-bootstrap-complete` exists
2. Re-check endpoints:
   - OPAC 8080
   - Intranet 8081
3. Re-scan Koha/Apache logs for:
   - `Cannot get_session`
   - `End of script output before headers`
4. Rerun with `--no-fresh-db` a second time to confirm marker-driven resume path is stable and fast.
