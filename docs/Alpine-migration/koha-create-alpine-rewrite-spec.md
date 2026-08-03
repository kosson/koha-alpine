# koha-create Alpine Rewrite Specification

## 1. Purpose

This document defines exactly what rewriting koha-create for Alpine must include in this repository, based on:

- upstream script behavior in [koha/debian/scripts/koha-create](koha/debian/scripts/koha-create)
- current Alpine runtime integration in [files-alpine/lib/run-sh-alpine.sh](files-alpine/lib/run-sh-alpine.sh) and [files-alpine/run.sh](files-alpine/run.sh)
- current compatibility shim model in [Dockerfile-Alpine](Dockerfile-Alpine)
- migration constraints in [docs/Alpine-migration/Phase-4-POSIX-Admin-Tools-and-Shim-Removal.md](docs/Alpine-migration/Phase-4-POSIX-Admin-Tools-and-Shim-Removal.md)

Primary goal: provide a clean-cut Alpine-native implementation for the startup path this project uses, centered on --create-db and --use-db.

## 2. Scope and Non-Goals

### In scope

1. Full Alpine-native rewrite of koha-create for:
1. --create-db
1. --use-db
1. Option compatibility required by current bootstrap call:
1. --memcached-servers
1. --mb-host
1. --mb-port
1. --mb-user
1. --mb-pass
1. --mb-vhost
1. Instance user/group creation, instance directories, DB create/use, config generation, Apache site activation, service start hooks.

### Out of scope for first cut

1. --request-db and --populate-db.
1. LetsEncrypt flow and apt/dpkg era package installation logic.
1. Full parity for every historical CLI option not used by this repo startup path.

## 3. Current Invocation Contract in This Repo

The bootstrap entrypoint currently calls koha-create in [files-alpine/lib/run-sh-alpine.sh](files-alpine/lib/run-sh-alpine.sh):

1. Select mode:
1. --create-db by default.
1. Switch to --use-db if DB already exists.
1. Pass message broker and memcached options.

The surrounding sequence in [files-alpine/run.sh](files-alpine/run.sh) matters for rewrite design:

1. /etc/koha templates are rendered before koha-create runs.
1. koha-create runs before render_vhost and koha-enable calls.
1. Additional TLS alignment and permission fixes happen after koha-create.

Implication: Alpine koha-create should not depend on Debian service tooling and should be idempotent in restart/resume runs.

## 4. Upstream Behavior Map (What Must Be Preserved)

Upstream script reference: [koha/debian/scripts/koha-create](koha/debian/scripts/koha-create).

Core behavior to preserve for this repo:

1. Parse options, resolve instance name, verify root execution.
1. Resolve DB credentials from passwd file, CLI, defaults.
1. For create/use paths:
1. create instance system user/group.
1. call koha-create-dirs.
1. generate koha-conf.xml and related site configs from /etc/koha templates.
1. For --create-db:
1. create database.
1. create/grant DB user.
1. For create/populate/use paths:
1. enable Apache site.
1. restart/reload Apache.
1. start zebra and workers.

Behavior that must be removed in Alpine rewrite:

1. Apache mpm_itk requirement checks.
1. a2enmod dependency as module management mechanism.
1. apt-cache, apt-get, dpkg-query, lsb_release, letsencrypt package bootstrap.
1. Debian service restart command assumptions.

## 5. Debian-to-Alpine Dependency Replacement Matrix

| Debian-era dependency | Where used in koha-create flow | Alpine rewrite approach |
| --- | --- | --- |
| apachectl -M with mpm_itk expectation | Apache compatibility check | Remove mpm_itk gate entirely. Validate only needed modules or skip runtime check if preloaded by image build. |
| a2ensite/a2dissite conventions | Site enablement | Create canonical symlink directly in /etc/apache2/sites-enabled or use Alpine helper script with deterministic .conf target only. |
| a2enmod/a2dismod | Runtime module management | Do not modify modules at runtime. Ensure modules are loaded in image build phase. |
| adduser long options | User creation | Use BusyBox/native options directly, no translation shim. |
| service apache2 restart | Apache reload | Use httpd -k graceful with safe fallback handling. |
| dpkg/apt/lsb_release + letsencrypt flow | Optional TLS bootstrap | Remove from first-cut Alpine implementation. |

## 6. Target Alpine koha-create Interface

Recommended first-cut CLI contract for the replacement script:

1. Supported modes:
1. --create-db
1. --use-db
1. Supported options:
1. --memcached-servers
1. --memcached-prefix
1. --mb-host
1. --mb-port
1. --mb-user
1. --mb-pass
1. --mb-vhost
1. --database
1. --dbhost
1. --passwdfile
1. --configfile
1. --marcflavor
1. --zebralang
1. --tmp-path
1. --upload-path
1. --template-cache-dir
1. Unsupported mode behavior:
1. explicit error with non-zero exit for unsupported modes (--request-db/--populate-db) in first cut.

## 7. Rewrite Architecture

Create a project-owned script at files-alpine/scripts/koha-create and install it after Debian script staging so it wins in /usr/sbin.

Implementation style:

1. Pure POSIX shell for command logic.
1. No runtime delegation to the Debian koha-create script.
1. Reuse existing helper commands where stable:
1. koha-create-dirs
1. koha-zebra
1. koha-worker
1. get_worker_queues via koha-functions.sh if needed.
1. Keep config generation deterministic from /etc/koha/*.in templates.

## 8. Detailed Implementation Steps

### Step 1: Add script overlay directory

1. Create files-alpine/scripts.
1. Add executable files-alpine/scripts/koha-create.

### Step 2: Install overlay after build staging

1. Update [Dockerfile-Alpine](Dockerfile-Alpine):
1. keep build-alpine-package.sh staging.
1. copy files-alpine/scripts/koha-create to /usr/sbin/koha-create after staging.
1. set mode 0755.

### Step 3: Implement strict argument parser

1. Parse supported modes and options.
1. Validate presence of instance name and root execution.
1. Reject unsupported options/modes with clear errors.

### Step 4: Resolve runtime config values

1. Load /etc/default/koha-common and optional config file.
1. Resolve:
1. instance name
1. DB host/name/user/password
1. memcached namespace/servers
1. message broker host/port/user/pass/vhost
1. Resolve precedence:
1. CLI > passwd file > defaults.

### Step 5: Implement safe, idempotent user/group creation

1. Instance user format: <instance>-koha.
1. Create group/user only if absent.
1. Use Alpine-native adduser flags directly.
1. Ensure home path /var/lib/koha/<instance> is consistent.

### Step 6: Create directory tree

1. Call koha-create-dirs <instance>.
1. Verify key paths exist and ownership is correct:
1. /etc/koha/sites/<instance>
1. /var/lib/koha/<instance>
1. /var/log/koha/<instance>
1. /var/run/koha/<instance>
1. /var/lock/koha/<instance>

### Step 7: Implement DB path

For --create-db:

1. Build mysql client options using /etc/mysql/koha-common.cnf when present.
1. Create database if missing.
1. Create/alter DB user grant for localhost host entry as required by this stack.
1. Grant privileges and flush.

For --use-db:

1. Skip CREATE DATABASE/CREATE USER.
1. Validate connectivity and required credentials.

### Step 8: Generate site configuration files

1. Render from /etc/koha templates into /etc/koha/sites/<instance>:
1. koha-conf.xml
1. log4perl.conf
1. zebra configs and zebra.passwd
1. Avoid Apache template generation from Debian apache-site.conf.in if Phase 3 render_vhost owns vhost output.

### Step 9: Apache site activation

1. Ensure /etc/apache2/sites-enabled exists.
1. Create one canonical symlink target only:
1. /etc/apache2/sites-enabled/<instance>.conf -> /etc/apache2/sites-available/<instance>.conf
1. Do not call both instance and instance.conf variants.
1. Reload Apache with httpd -k graceful, tolerate non-fatal reload errors during first-boot race conditions.

### Step 10: Service bootstrap hooks

1. Start zebra via koha-zebra --start <instance>.
1. Start workers per queue:
1. read worker queues from koha-functions helper.
1. invoke koha-worker with queue and --start.
1. Keep failures non-fatal where current runtime already tolerates partial service bring-up.

### Step 11: Logging and exit codes

1. Use clear prefixed log messages ([koha-create-alpine]).
1. Exit non-zero for hard failures (argument parsing, DB auth failure, config generation failure).
1. Return success for tolerated optional steps only when core instance/bootstrap succeeded.

### Step 12: Wire tests and acceptance gates

1. Add static test script for koha-create rewrite invariants.
1. Extend runtime deterministic test to include a direct koha-create invocation and verify:
1. no missing command warnings
1. no mpm_itk references
1. site symlink present
1. koha-conf.xml rendered

## 9. Suggested Script Skeleton

Recommended function layout for files-alpine/scripts/koha-create:

1. usage
1. log_info/log_warn/log_err
1. die
1. require_root
1. parse_args
1. load_defaults
1. resolve_db_settings
1. ensure_instance_user
1. ensure_instance_dirs
1. db_create_if_needed
1. generate_site_configs
1. enable_apache_site
1. reload_apache
1. start_runtime_services
1. main

## 10. Required Changes Outside koha-create

1. [Dockerfile-Alpine](Dockerfile-Alpine):
1. copy script overlay to /usr/sbin after build staging.
1. remove adduser translation shim when no longer referenced.
1. simplify apachectl shim once mpm_itk checks are gone.
1. [files-alpine/run.sh](files-alpine/run.sh):
1. remove AssignUserID post-processing once vhost ownership is fully moved away from Debian template flow.
1. keep render_vhost ordering deterministic before site enablement.
1. Optional: keep service shim as fallback only while other scripts are being migrated.

## 11. Test Plan

### Static tests

1. Replacement script exists and is executable.
1. Script does not call:
1. apt-get
1. apt-cache
1. dpkg-query
1. lsb_release
1. mpm_itk
1. service apache2 restart
1. Script uses canonical site symlink form only (<instance>.conf).

### Runtime tests

1. Fresh DB path:
1. run koha-create --create-db <instance> with current bootstrap options.
1. verify DB/schema objects exist.
1. verify /etc/koha/sites/<instance>/koha-conf.xml exists.
1. verify /etc/apache2/sites-enabled/<instance>.conf exists.
1. Existing DB path:
1. rerun with --use-db.
1. verify idempotent behavior and no duplicate user/group failures.
1. verify no shim-dependent warnings in output.

### Regression tests

1. Ensure existing Phase 4 start-stop-daemon test still passes in [tests/test_phase4_start_stop_daemon.sh](tests/test_phase4_start_stop_daemon.sh).
1. Add a dedicated koha-create Alpine test script in tests to gate future changes.

## 12. Rollout Strategy

1. Introduce Alpine koha-create behind a feature toggle:
1. KOHA_CREATE_IMPL=alpine|debian (default alpine once validated).
1. During bake-in period, keep Debian script at alternate path for emergency rollback only.
1. After stable validation, remove toggle and lock to Alpine implementation.

## 13. Definition of Done

The rewrite is complete when all are true:

1. Bootstrap in this repo succeeds using Alpine-native koha-create for --create-db and --use-db.
1. No runtime dependency on Debian-specific koha-create logic.
1. No missing command warnings caused by removed Debian tool expectations.
1. Test suite includes static and runtime koha-create rewrite checks and passes.
1. Dockerfile shims are reduced to only those still required by non-rewritten scripts.

## 14. Immediate Next Actions

1. Create files-alpine/scripts/koha-create with parser + core create/use flow.
1. Wire Dockerfile overlay copy.
1. Add tests/test_phase4_koha_create_rewrite.sh.
1. Run deterministic integration script and capture before/after logs.

## 15. Implementation Status (2026-08-03)

### Step status

- [x] Step 1: Add script overlay directory
- [x] Step 2: Install overlay after build staging
- [x] Step 3: Implement strict argument parser
- [x] Step 4: Resolve runtime config values
- [x] Step 5: Implement safe, idempotent user/group creation
- [x] Step 6: Create directory tree
- [x] Step 7: Implement DB path
- [x] Step 8: Generate site configuration files
- [x] Step 9: Apache site activation
- [x] Step 10: Service bootstrap hooks
- [x] Step 11: Logging and exit codes
- [x] Step 12: Wire tests and acceptance gates

### Step 12 detail

- [x] Static rewrite test added: tests/test_phase4_koha_create_rewrite.sh
- [x] Runtime rewrite assertions added for command target and apachectl mpm_itk removal
- [x] Static checks for `--db-user`, `--db-password`, `--db-name` CLI arg support added
- [x] Live-container section added: `/etc/koha/passwd` entry, `koha-conf.xml` presence, idempotent `--use-db` re-invocation, no `Access denied` in re-invocation output

### Required changes outside koha-create

- [x] Dockerfile overlay copy/wiring complete
- [x] Adduser translation shim removed
- [x] Apachectl fake mpm_itk output removed
- [ ] run.sh AssignUserID post-processing removal is still pending (deferred — retained as harmless safety net; see TRACKER 2026-08-03 Part 1)
- [x] render_vhost ordering remains deterministic before site enablement
- [x] service shim fallback updated (apache2 now maps to real httpd control; koha-common remains compat-no-op)

### Validation status

- [x] Rewrite guardrails test passing (static and runtime checks)
- [x] Deterministic integration run passing (OpenSearch test pass-with-skip when cluster is absent)
- [x] Bootstrap path works with valid SYNC_REPO
- [x] Argument-ordering bug fixed: `${KOHA_INSTANCE}` moved to after all flags in `bootstrap_koha_instance()` call so the CLI parser receives `--db-*` args correctly
- [x] `--db-user`, `--db-password`, `--db-name` CLI args added to koha-create; passwd file written on first use

### Rollout status

- [ ] KOHA_CREATE_IMPL feature toggle not implemented (deferred — single implementation, no rollback path needed at this stage)
- [ ] Toggle removal/final lock not applicable until/if toggle is introduced
