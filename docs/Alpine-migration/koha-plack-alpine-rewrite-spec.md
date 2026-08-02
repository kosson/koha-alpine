# koha-plack Alpine Rewrite Specification

## 1. Purpose

This document defines exactly what rewriting koha-plack for Alpine must include in this repository, based on:

- upstream behavior in [koha/debian/scripts/koha-plack](koha/debian/scripts/koha-plack)
- current Alpine runtime integration in [files-alpine/lib/run-sh-alpine.sh](files-alpine/lib/run-sh-alpine.sh)
- current shim model in [Dockerfile-Alpine](Dockerfile-Alpine)
- migration constraints in [docs/Alpine-migration/Phase-4-POSIX-Admin-Tools-and-Shim-Removal.md](docs/Alpine-migration/Phase-4-POSIX-Admin-Tools-and-Shim-Removal.md)

Primary goal: provide a clean-cut Alpine-native implementation of koha-plack that supports the runtime paths this repository actually exercises and removes Debian-era runtime assumptions.

## 2. Scope and Non-Goals

### In scope

1. Alpine-native rewrite of koha-plack at [files-alpine/scripts/koha-plack](files-alpine/scripts/koha-plack).
1. Mode support required by current runtime and operational parity:
1. `--enable`
1. `--disable`
1. `--start`
1. `--stop`
1. `--restart`
1. `--reload`
1. `--status`
1. Compatibility with existing helper and config layout:
1. instance path and config resolution from `/etc/koha/sites/<instance>/...`
1. Starman startup and PID/socket lifecycle under `/var/run/koha/<instance>/`
1. logging targets under `/var/log/koha/<instance>/`
1. BusyBox/Alpine process control semantics for status/stop/reload.

### Out of scope for first cut

1. Perfect behavioral parity for every historical debugger edge case if not used in current workflows.
1. Automatic runtime Apache module installation (`a2enmod`) as a lifecycle action.
1. Supervisord/OpenRC migration of plack lifecycle (Phase 5 workstream).

## 3. Current Invocation Contract in This Repo

Current usage in [files-alpine/lib/run-sh-alpine.sh](files-alpine/lib/run-sh-alpine.sh):

1. During service enablement:
1. `koha-plack --enable ${KOHA_INSTANCE}`
1. During startup:
1. `koha-plack --start ${KOHA_INSTANCE}`
1. Failures are currently tolerated (`|| true` / informational fallback), so startup can continue in CGI mode.

Implications for rewrite design:

1. `--enable` and `--start` are the highest-priority operational paths.
1. Script must be idempotent and safe to run repeatedly.
1. Script must provide deterministic exit codes so run.sh can decide whether to continue/fallback.

## 4. Upstream Behavior Map (What Must Be Preserved)

Upstream reference: [koha/debian/scripts/koha-plack](koha/debian/scripts/koha-plack).

Core behavior to preserve:

1. Parse one action plus one or more instance names.
1. Validate instances using koha helper functions.
1. For `--enable` / `--disable`:
1. toggle include lines in instance Apache vhost config.
1. report no-op or already-enabled/disabled states.
1. For `--start`:
1. resolve per-instance psgi file.
1. set KOHA_CONF and runtime environment.
1. create/fix log file ownership.
1. launch starman with PID and unix socket.
1. For `--stop` / `--reload` / `--status`:
1. target process by pidfile and instance user.

Behavior that must be removed or adapted in Alpine rewrite:

1. Runtime dependency on Debian-specific `start-stop-daemon` flag forms (notably `--retry=QUIT/30/KILL/5` and direct `--status`).
1. Runtime recommendation path that relies on `a2enmod`.
1. Hard dependence on `/lib/lsb/init-functions` formatting semantics.

## 5. Debian-to-Alpine Dependency Replacement Matrix

| Debian-era dependency | Where used in koha-plack flow | Alpine rewrite approach |
| --- | --- | --- |
| `/lib/lsb/init-functions` log helpers | top-level source and log functions | Use internal log functions in script (`log_info`, `log_warn`, `log_err`) and keep output simple/deterministic. |
| `start-stop-daemon --stop --retry=QUIT/30/KILL/5` | stop path | Use BusyBox-compatible stop strategy (integer retry or staged signals via shell logic). |
| `start-stop-daemon --status` expectations in helper paths | status checks via helper functions | Use BusyBox-compatible status probe (`--stop --test --pidfile ...`) or explicit pidfile+process checks. |
| `a2enmod` remediation text | env warning path | Replace with Alpine guidance: modules are preloaded in image build, no runtime a2enmod action. |
| `apachectl -M` based module warning path | check_env_and_warn | Make warning optional and Alpine-aware; do not block start/enable on module hint checks. |

## 6. Target Alpine koha-plack Interface

First-cut CLI contract for replacement script:

1. Supported actions:
1. `--start`
1. `--stop`
1. `--restart`
1. `--reload`
1. `--status`
1. `--enable`
1. `--disable`
1. Supported flags:
1. `--quiet` / `-q`
1. `--development` / `-dev`
1. `--debugger`
1. `--debugger-key`
1. `--debugger-location`
1. `--debugger-path`
1. `--help` / `-h`
1. Inputs:
1. one action per invocation
1. one or more instance names
1. Unsupported behavior:
1. invalid switches return non-zero with explicit usage text.

## 7. Rewrite Architecture

Create project-owned script at [files-alpine/scripts/koha-plack](files-alpine/scripts/koha-plack) and install it after Debian script staging so it is the active command in `/usr/sbin`.

Implementation style:

1. POSIX shell command logic.
1. No runtime delegation to upstream Debian koha-plack.
1. Reuse stable helper commands/functions where safe:
1. source `/usr/share/koha/bin/koha-functions.sh` for `is_instance`, path helpers, and git-install adjustments.
1. replace only process-control and Debian-assumption logic inside this script.
1. Keep Starman launch contract and file locations consistent with existing Koha layout.

## 8. Detailed Implementation Steps

### Step 1: Add script overlay

1. Create executable [files-alpine/scripts/koha-plack](files-alpine/scripts/koha-plack).
1. Include usage text and strict one-action parser.

### Step 2: Install overlay after staging

1. Update [Dockerfile-Alpine](Dockerfile-Alpine):
1. copy `files-alpine/scripts/koha-plack` to `/usr/sbin/koha-plack` after `build-alpine-package.sh` staging.
1. set mode `0755`.
1. Ensure runtime restaging logic in [files-alpine/lib/run-sh-alpine.sh](files-alpine/lib/run-sh-alpine.sh) reapplies this override if staging re-copies Debian scripts.

### Step 3: Parser and execution model

1. Enforce one action (`start|stop|restart|reload|enable|disable|status`).
1. Preserve multi-instance loops.
1. Preserve `--quiet` behavior for non-existing instances.

### Step 4: Alpine-safe logging and error handling

1. Implement internal log helpers.
1. Use deterministic, prefixed messages (`[koha-plack-alpine]`).
1. Return non-zero for hard failures (invalid args, starman launch failure, config edit failure).

### Step 5: `--enable` / `--disable` config toggles

1. Keep upstream behavior of toggling include lines in instance apache config.
1. Continue using helper `get_apache_config_for` for config path resolution.
1. Preserve idempotent outcomes:
1. already-enabled/disabled should not corrupt config.
1. mismatched state should produce warning and non-zero when appropriate.

### Step 6: `--start` implementation

1. Resolve instance user, PID file, socket, psgi path.
1. Ensure log files exist and ownership matches `<instance>-koha`.
1. Build starman options with instance workers/max-requests values (including defaults).
1. Set KOHA_CONF for instance scope.
1. Launch starman with same file contracts used today (pidfile, socket, logs).

### Step 7: `--stop` / `--reload` / `--status` adaptation for BusyBox

1. Replace Debian-specific retry string usage with BusyBox-compatible strategy:
1. either integer `--retry` when available, or
1. staged signal fallback in shell (`TERM`, wait loop, `KILL` fallback).
1. Replace `--status` assumptions with:
1. `start-stop-daemon --stop --test --pidfile ...` when available, or
1. explicit pidfile + `kill -0` process check.
1. Keep user scoping semantics to avoid terminating unrelated processes.

### Step 8: Optional Alpine-aware environment warning path

1. Keep warning checks informational only.
1. Remove Debian-centric remediation text (`a2enmod`).
1. If module checks remain, validate against modules expected to be preloaded in Alpine image.

### Step 9: Debugger/development compatibility

1. Keep debugger flags and env variables (`PERL5DB`, `PERLDB_OPTS`, `DBGP_IDEKEY`, `PLACK_DEBUG`, `PERL5OPT`).
1. Ensure behavior remains non-disruptive when debugger flags are omitted.

### Step 10: Exit code parity and idempotence

1. Maintain clear success/failure semantics across multi-instance execution.
1. Treat already-running/already-stopped states consistently and document any deliberate differences from Debian behavior.

### Step 11: Test coverage and gates

1. Add dedicated static test for koha-plack Alpine invariants.
1. Add runtime probes for enable/start/stop/status on ephemeral instance.
1. Integrate with existing phase test suite and deterministic integration where applicable.

## 9. Suggested Script Skeleton

Recommended function layout for [files-alpine/scripts/koha-plack](files-alpine/scripts/koha-plack):

1. `usage`
1. `log_info` / `log_warn` / `log_err`
1. `die`
1. `set_action`
1. `parse_args`
1. `load_defaults`
1. `validate_instance`
1. `ensure_plack_logs`
1. `is_plack_running`
1. `enable_plack`
1. `disable_plack`
1. `start_plack`
1. `stop_plack`
1. `reload_plack`
1. `plack_status`
1. `_do_instance`
1. `main`

## 10. Required Changes Outside koha-plack

1. [Dockerfile-Alpine](Dockerfile-Alpine):
1. ensure script overlay copy order after Debian staging.
1. keep/start verifying Alpine module load lines in `httpd.conf` for plack-relevant modules.
1. keep `apachectl` pass-through behavior.
1. [files-alpine/lib/run-sh-alpine.sh](files-alpine/lib/run-sh-alpine.sh):
1. optionally tighten fallback handling after rewrite is validated (move from silent tolerate to explicit failure policy if desired).
1. [tests/test_phase4_start_stop_daemon.sh](tests/test_phase4_start_stop_daemon.sh):
1. use as compatibility gate for chosen process-control semantics.

## 11. Test Plan

### Static tests

1. Replacement script exists and is executable.
1. Script does not call Debian package-manager tooling (`apt-get`, `apt-cache`, `dpkg-query`, `lsb_release`).
1. Script does not rely on `--retry=QUIT/30/KILL/5` string form.
1. Script does not require `a2enmod` runtime execution.

### Runtime tests

1. Enable/start flow:
1. run `koha-plack --enable <instance>` and verify expected include lines become active.
1. run `koha-plack --start <instance>` and verify pidfile/socket/log creation.
1. Stop/status flow:
1. verify `--status` reports running after start.
1. verify `--reload` succeeds and process remains active.
1. verify `--stop` terminates plack process and clears running status.
1. Idempotence:
1. repeated `--enable` and `--disable` calls do not corrupt config.
1. repeated `--start` or `--stop` produce deterministic non-destructive results.

### Regression tests

1. Existing [tests/test_phase4_start_stop_daemon.sh](tests/test_phase4_start_stop_daemon.sh) remains green.
1. Add dedicated plack rewrite gate: `tests/test_phase4_koha_plack_rewrite.sh`.
1. Keep deterministic integration suite green with plack enabled and disabled profiles.

## 12. Rollout Strategy

1. Introduce rewrite behind feature toggle:
1. `KOHA_PLACK_IMPL=alpine|debian`.
1. Default to `alpine` after static+runtime gates pass.
1. Keep Debian script available at alternate path during bake-in period for emergency rollback only.
1. Remove toggle after sustained stability window.

## 13. Definition of Done

Rewrite is complete when all are true:

1. Runtime uses Alpine-native koha-plack implementation for `--enable`/`--start` and management actions.
1. No functional dependency on Debian-only process-control semantics.
1. BusyBox/start-stop-daemon compatibility is covered by automated tests.
1. No missing-command or shim-intervention warnings are emitted for supported paths.
1. Phase 4 test gates remain green.

## 14. Immediate Next Actions

1. Create [files-alpine/scripts/koha-plack](files-alpine/scripts/koha-plack) with parser and action handlers.
1. Wire overlay install/reinstall in [Dockerfile-Alpine](Dockerfile-Alpine) and [files-alpine/lib/run-sh-alpine.sh](files-alpine/lib/run-sh-alpine.sh).
1. Add `tests/test_phase4_koha_plack_rewrite.sh` (static + runtime assertions).
1. Run [tests/test_phase4_start_stop_daemon.sh](tests/test_phase4_start_stop_daemon.sh) and deterministic integration to validate chosen stop/status strategy.

## 15. Initial Implementation Status (2026-08-02)

### Baseline status

- [x] start-stop-daemon package prerequisite present in image (`busybox-extras` in Dockerfile).
- [x] Existing runtime already invokes `koha-plack --enable` and `koha-plack --start`.
- [x] Alpine override script `files-alpine/scripts/koha-plack` created.
- [x] Overlay installation for `koha-plack` added after Debian staging.
- [x] Dedicated plack rewrite tests added.

### Known compatibility notes

- [x] Existing compatibility test documents BusyBox differences for status/retry flag behavior.
- [x] Final process-control strategy selected and implemented in rewrite (BusyBox-aware `start-stop-daemon` usage with pidfile/`kill -0` fallback).
- [x] Apache module warning/remediation path finalized for Alpine (informational-only behavior).

### Validation snapshot (2026-08-02)

- [x] `tests/test_phase4_koha_plack_rewrite.sh` passes static checks (13 passed).
- [x] Runtime checks in `tests/test_phase4_koha_plack_rewrite.sh` are wired and currently skip when no test image is available.
- [x] `tests/test_phase4_start_stop_daemon.sh` passes with static checks and runtime skips when no compatible image is available.
