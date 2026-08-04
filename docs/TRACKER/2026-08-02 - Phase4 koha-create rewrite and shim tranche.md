---
title: "Phase 4 koha-create rewrite and shim tranche"
date: 2026-08-02
tags:
  - alpine
  - phase4
  - koha-create
  - shims
  - validation
---
# 2026-08-02 - Phase 4 koha-create rewrite and shim tranche

## Scope executed

This tracker entry captures the full Phase 4 operations executed in this session:

1. Introduced a project-owned Alpine koha-create implementation.
2. Wired Alpine koha-create so it remains authoritative after both build-time and runtime Debian staging steps.
3. Removed the adduser translation shim.
4. Removed fake mpm_itk module spoofing from apachectl -M.
5. Converted apache service no-op shims to real httpd control behavior.
6. Added dedicated Phase 4 rewrite tests.
7. Executed deterministic integration validation after SYNC_REPO was corrected.

## Detailed operations

### A) New Alpine koha-create command

Added new script:

- files-alpine/scripts/koha-create

Implemented first-cut full Alpine-native behavior for the active project path:

1. Supports --create-db and --use-db modes.
2. Parses active bootstrap options (memcached and message broker options plus key DB/config options).
3. Performs root validation and instance name sanity checks.
4. Creates/ensures instance user/group with Alpine-native adduser/addgroup flags.
5. Handles DB create/use and grants.
6. Renders Koha site config files from /etc/koha templates.
7. Enables canonical Apache symlink target only: sites-enabled/<instance>.conf.
8. Reloads Apache with httpd -k graceful.
9. Starts zebra and worker hooks.

### B) Command ownership and staging order

Updated staging/wiring to ensure Alpine script wins:

- Dockerfile-Alpine
- files-alpine/lib/run-sh-alpine.sh

Key actions:

1. Copy files-alpine/scripts into image.
2. Install /usr/sbin/koha-create from Alpine scripts during build.
3. Re-apply Alpine koha-create after prod build-time staging.
4. Re-apply Alpine koha-create after runtime build-alpine-package.sh staging.

### C) Shim reduction tranche

Updated Dockerfile-Alpine:

1. apachectl -M now pass-through exec to httpd -M (removed fake mpm_itk/rewrite/cgi/ssl echoes).
2. Removed /usr/local/bin/adduser translation shim entirely.
3. Updated rc-service/service/apache2 shim behavior for apache2 from no-op to real httpd operations:
   - start -> httpd -k start
   - stop -> httpd -k stop
   - restart/reload/graceful -> httpd -k graceful
4. Kept koha-common service path as compatibility no-op.

### D) Tests and docs

Added:

- tests/test_phase4_koha_create_rewrite.sh
- docs/Alpine-migration/koha-create-alpine-rewrite-spec.md

Updated:

- docs/Alpine-migration/Phase-4-POSIX-Admin-Tools-and-Shim-Removal.md

## Validation runs

### Phase 4 rewrite test

Command:

- bash tests/test_phase4_koha_create_rewrite.sh

Result:

- Passed: 14
- Failed: 0
- Skipped: 0

Validated both static and runtime assertions, including:

1. no apt/dpkg/lsb_release usage in Alpine koha-create
2. no mpm_itk spoof path
3. no adduser shim in Dockerfile
4. runtime command target at /usr/sbin/koha-create

### Deterministic integration suite

Command:

- bash tests/run_integration_deterministic.sh

Artifact directory:

- tests/artifacts/integration-20260802T190703Z

Summary:

- total tests: 5
- passed: 4
- pass-with-skip: 1
- failed: 0

Per test outcomes:

1. test_mariadb_auth_readiness_integration.sh -> pass
2. test_restart_integration.sh -> pass
3. test_authority_groupby_sqlmode_integration.sh -> pass
4. test_opensearch_os01_auth_integration.sh -> pass-with-skip (OpenSearch stack not running)
5. test_alpine_startup_smoke.sh -> pass

## Status

### Completed

1. Alpine koha-create rewrite scaffold is active and validated.
2. Build/runtime staging precedence is enforced.
3. adduser shim removed.
4. apachectl module spoof removal completed.
5. apache2 service no-op shim replaced with real control behavior.
6. Rewrite test coverage added and passing.
7. Deterministic integration green in this environment (with expected OpenSearch skip).

### Remaining Phase 4 follow-up

1. Extend Alpine koha-create behavior coverage only where project paths require it.
2. Continue daemon/service shim retirement as koha-worker/koha-plack/koha-functions replacements mature.
3. Optionally add a dedicated test for apache service shim semantics in long-lived container context (status behavior in one-shot test containers can be noisy due process model).
