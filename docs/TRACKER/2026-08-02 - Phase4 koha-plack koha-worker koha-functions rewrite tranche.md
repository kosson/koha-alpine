# 2026-08-02 - Phase4 koha-plack koha-worker koha-functions rewrite tranche

## Context

Continuation of Phase 4 (POSIX admin tools and shim reduction) after the first koha-create rewrite tranche.

Goal of this tranche:

1. Implement first-cut Alpine-native replacements for remaining high-impact lifecycle scripts used in this repository startup path:
1. koha-plack
1. koha-worker
1. koha-functions.sh (override layer)
1. Add dedicated guardrail tests for each rewrite.
1. Wire script overlays so Alpine variants win after both build-time and runtime Debian restaging.
1. Update migration docs with completed/pending status and validated outcomes.

## Scope implemented

### 1) Alpine koha-plack rewrite

Added:

- files-alpine/scripts/koha-plack

Key behavior implemented:

1. Strict action parser for:
1. --start
1. --stop
1. --restart
1. --reload
1. --status
1. --enable
1. --disable
1. --quiet, debugger, development flags retained
1. Apache vhost include toggling logic for enable/disable retained (idempotent behavior preserved).
1. Plack start path:
1. per-instance pid/socket/log handling
1. KOHA_CONF export
1. starman launch with instance settings and debug mode handling
1. BusyBox-safe stop/status semantics:
1. avoids Debian-specific retry syntax usage
1. uses start-stop-daemon when compatible
1. falls back to pidfile + kill -0 + TERM/KILL sequence
1. Warning/remediation text adjusted to Alpine assumptions (no Debian a2enmod runtime expectation).

### 2) Alpine koha-worker rewrite

Added:

- files-alpine/scripts/koha-worker

Key behavior implemented:

1. Strict action parser for:
1. --start
1. --stop
1. --restart
1. --status
1. --queue
1. --quiet
1. Worker naming and queue behavior aligned with helper conventions.
1. Process model:
1. BusyBox-compatible start-stop-daemon usage for start/stop
1. pidfile naming tied to worker name
1. fallback start via instance user shell + pid capture when needed
1. fallback stop via pidfile TERM/KILL sequence
1. No dependency on Debian daemon utility invocation paths.

### 3) Alpine koha-functions override

Added:

- files-alpine/scripts/koha-functions.sh

Architecture:

1. Source upstream helper first from /usr/share/koha/bin/koha-functions.sh.
1. Override only daemon-/status-sensitive running checks with Alpine-safe implementations.

Overridden functions:

1. is_sip_running
1. is_zebra_running
1. is_indexer_running
1. is_es_indexer_running
1. is_worker_running
1. is_plack_running
1. is_z3950_running

Replacement strategy:

1. Prefer pidfile + kill -0 liveness checks.
1. Use start-stop-daemon --stop --test when available as a compatibility path.
1. Avoid start-stop-daemon --status dependency and avoid daemon utility usage.

### 4) Sourcing precedence update (rewritten scripts)

Updated scripts to prefer Alpine koha-functions override first:

1. files-alpine/scripts/koha-create
1. files-alpine/scripts/koha-plack
1. files-alpine/scripts/koha-worker

Order now:

1. source /usr/sbin/koha-functions.sh when present
1. fallback to /usr/share/koha/bin/koha-functions.sh

### 5) Overlay installation and re-apply wiring

Updated build-time installs in Dockerfile-Alpine to include:

1. /usr/sbin/koha-plack
1. /usr/sbin/koha-worker
1. /usr/sbin/koha-functions.sh

Applied in both:

1. base runtime stage install block
1. prod runtime post-staging reapply block

Updated runtime restaging reapply in files-alpine/lib/run-sh-alpine.sh:

1. loop now reinstalls:
1. koha-create
1. koha-plack
1. koha-worker
1. koha-functions.sh

Rationale:

1. build-alpine-package.sh can restage Debian koha-* scripts into /usr/sbin
1. Alpine overrides must be re-applied after that restage to remain active

## Tests added and outcomes

### Added tests

1. tests/test_phase4_koha_plack_rewrite.sh
1. tests/test_phase4_koha_worker_rewrite.sh
1. tests/test_phase4_koha_functions_rewrite.sh

### Existing tests rerun

1. tests/test_phase4_koha_create_rewrite.sh
1. tests/test_phase4_start_stop_daemon.sh

### Deterministic test mode used for rewrite guards

To avoid environment drift from unavailable local image tags during static invariant validation:

1. KOHA_TEST_IMAGE=koha-alpine:no-such-image

This forces runtime checks to skip and keeps static checks deterministic.

### Final observed test outcomes

1. test_phase4_koha_create_rewrite.sh
1. Passed: 12
1. Failed: 0
1. Skipped: 2
1. test_phase4_koha_plack_rewrite.sh
1. Passed: 13
1. Failed: 0
1. Skipped: 2
1. test_phase4_koha_worker_rewrite.sh
1. Passed: 12
1. Failed: 0
1. Skipped: 2
1. test_phase4_koha_functions_rewrite.sh
1. Passed: 12
1. Failed: 0
1. Skipped: 1
1. test_phase4_start_stop_daemon.sh
1. Passed: 1
1. Failed: 0
1. Skipped: 11

Notes on skips:

1. Runtime checks skipped due absent expected built image tag(s) in local environment.
1. Static rewrite invariants are currently green.

## Notable debugging events during implementation

1. Initial koha-plack guardrail failure due literal "a2enmod" in warning text.
1. Fixed by replacing wording with generic Alpine guidance.
1. Initial koha-worker guardrail false-positive due regex matching daemon substring within start-stop-daemon.
1. Fixed test pattern to detect daemon utility invocation form only.

## Documentation updates made

Updated:

- docs/Alpine-migration/Phase-4-POSIX-Admin-Tools-and-Shim-Removal.md

Changes captured:

1. Phase sequence/status section updated:
1. 7.2 koha-functions marked completed (first cut)
1. 7.3 koha-worker marked completed (first cut)
1. 7.4 koha-plack already completed (first cut)
1. validation outcomes now include koha-functions and koha-worker guardrail results
1. remaining work narrowed to image-backed runtime verification and residual legacy paths

## Current risk and remaining work

### Remaining technical work

1. Build and run a compatible test image and execute runtime sections for:
1. koha-create guardrail test
1. koha-plack guardrail test
1. koha-worker guardrail test
1. koha-functions guardrail test
1. Validate less-used legacy service lifecycle paths that still depend on broader koha-common behaviors.
1. Evaluate whether additional helper overrides are required beyond running-check functions for full legacy parity.

### Risk notes for later debug

1. pidfile naming conventions must stay aligned between scripts and helper checks.
1. If upstream script behaviors change, helper overrides may drift and require update.
1. start-stop-daemon option support can vary by BusyBox build; fallback branches should be exercised in image-backed runtime tests.

## File-level change index for this tranche

1. Added files-alpine/scripts/koha-plack
1. Added files-alpine/scripts/koha-worker
1. Added files-alpine/scripts/koha-functions.sh
1. Updated files-alpine/scripts/koha-create (helper sourcing precedence)
1. Updated files-alpine/scripts/koha-plack (helper sourcing precedence + warning text)
1. Updated files-alpine/scripts/koha-worker (helper sourcing precedence)
1. Updated files-alpine/lib/run-sh-alpine.sh (runtime override reapply list)
1. Updated Dockerfile-Alpine (override installation blocks)
1. Added tests/test_phase4_koha_plack_rewrite.sh
1. Added tests/test_phase4_koha_worker_rewrite.sh
1. Added tests/test_phase4_koha_functions_rewrite.sh
1. Updated docs/Alpine-migration/Phase-4-POSIX-Admin-Tools-and-Shim-Removal.md

## Suggested next debug-first action

1. Build a fresh koha-alpine phase image tag locally and run all Phase 4 rewrite guardrails without forced runtime skip.
1. If runtime deltas appear, capture:
1. command path resolution output
1. pidfile/socket existence checks
1. stop/restart behavior traces
1. logs under /var/log/koha/<instance>/

## Umbrella runner added

Added:

1. tests/run_phase4_rewrite_guardrails.sh

Purpose:

1. Single-command execution of all Phase 4 rewrite guardrails:
1. test_phase4_koha_create_rewrite.sh
1. test_phase4_koha_plack_rewrite.sh
1. test_phase4_koha_worker_rewrite.sh
1. test_phase4_koha_functions_rewrite.sh
1. test_phase4_start_stop_daemon.sh
1. Prints per-test PASS/FAIL plus consolidated suite summary.

Validated run:

1. KOHA_TEST_IMAGE=koha-alpine:no-such-image ./tests/run_phase4_rewrite_guardrails.sh
1. Suite summary:
1. Passed test scripts: 5
1. Failed test scripts: 0
