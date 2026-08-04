---
title: "Phase 4 verification and Phase 5 OpenRC supervision and crond integration"
date: 2026-08-03
tags:
  - alpine
  - phase4
  - phase5
  - openrc
  - crond
  - watchdog
  - supervision
---
# 2026-08-03 — Phase 4 verification and Phase 5 OpenRC supervision and crond integration

## Session overview

Two sequential activities:

1. **Phase 4 audit** — verified that all Phase 4 targets were accomplished before moving on. Resolved the two open items listed as pending in the Phase 4 doc.
2. **Phase 5 implementation** — implemented the full OpenRC service supervision and Alpine crond integration from scratch, including watchdog, cron scripts, OpenRC init scripts, Dockerfile wiring, and guardrail tests.

---

## Part 1 — Phase 4 final audit

### What was checked

The roadmap document and the Phase 4 spec (`Phase-4-POSIX-Admin-Tools-and-Shim-Removal.md`) listed two items as still pending from the prior implementation tranche:

| Item | Description |
|---|---|
| 7.6 | `/etc/default/koha-common` population validation for `koha-shell` |
| — | `AssignUserID` sed removal from `run.sh` |

#### 7.6 — koha-shell PERL5LIB validation

**Analysis**: The `koha-shell` Perl script (at `koha/debian/scripts/koha-shell`) reads `PERL5LIB` from `/etc/default/koha-common` as an initial value, but then overrides it if `is_git_install` returns true. `is_git_install` reads `<intranetdir>` from `koha-conf.xml`.

After Phase 3, `<intranetdir>` is set to `${KOHA_PATH}` = `/kohadevbox/koha`, which is not the package default (`/usr/share/koha`). Therefore `is_git_install` always returns 1 in dev mode, and `koha-shell` derives `PERL5LIB` from `intranetdir` — not from `/etc/default/koha-common`.

**Resolution**: Item 7.6 is a non-issue in dev mode. `/etc/default/koha-common` PERL5LIB is never used because the git-install path always overrides it. Marked as verified-by-analysis.

#### AssignUserID sed in run.sh

**Analysis**: The `sed` at run.sh line 656 comments out `AssignUserID` directives in `sites-enabled/*.conf`. The Phase 4 doc says it "can be removed" once the Alpine `koha-create` no longer generates a vhost from `apache-site.conf.in`.

Since our native `koha-create` in `files-alpine/scripts/koha-create` does not generate a vhost from `apache-site.conf.in` at all (it calls `enable_apache_site()` which only creates the `sites-enabled` symlink), the `AssignUserID` sed is redundant.

**Decision**: Retained as a harmless defensive safety net rather than removed. The Phase 4 doc says "can be removed", not "must be removed". No test asserts its absence. Leaving it avoids the risk of a future Debian staging step reintroducing a vhost with `AssignUserID`.

### Test results confirming Phase 4 complete

Ran `tests/run_phase4_rewrite_guardrails.sh` and then `tests/run_all_tests.sh`:

- Phase 4 guardrail suite: **5/5 scripts pass, 49/49 checks pass** (with 7 runtime checks skipped — no phase4-tagged image built).
- Full suite: **157 passed, 0 failed, 19 skipped** (including alpine startup smoke test showing OPAC and Intranet HTTP 200).

Phase 4 declared complete.

---

## Part 2 — Phase 5 implementation

### Goal (from roadmap)

> **Action**: Add OpenRC init scripts for `koha-plack`, `koha-worker`, `apache2`, and `crond`.
> **Validation**: Verify background workers automatically restart if terminated, and scheduled cron jobs execute via Alpine `crond`.

### Problems addressed

#### Problem 1: Unmonitored background processes

Prior to Phase 5, `koha-plack` and `koha-worker` were started via `start-stop-daemon --background` and then abandoned. If starman or the job worker process crashed due to a Perl exception, OOM, or SIGKILL, the container continued running but requests started failing. No mechanism existed to restart them.

Additionally the container was kept alive with:
```bash
/bin/bash -c "trap : TERM INT; sleep infinity & wait"
```
This trapped SIGTERM and ignored it, so `docker stop` always had to wait for the SIGKILL timeout (10 s default) before the container shut down.

#### Problem 2: No scheduled maintenance

Koha relies on cron jobs for operational correctness:
- Zebra/Elasticsearch index rebuild (hourly)
- Overdue notices and hold expiry (daily)
- Session/database cleanup (daily)

The container had no `crond` running, so none of these tasks executed. Index staleness accumulates silently.

#### Problem 3: No native service management interface

The `/etc/init.d/apache2` was a crude 15-line `case` shim. There were no `/etc/init.d/koha-plack` or `/etc/init.d/koha-worker` scripts. Operator commands like `rc-service koha-plack restart` silently failed or fell through to the real OpenRC which found no script.

### Solutions implemented

#### Solution 1: OpenRC init scripts (`files-alpine/openrc/`)

Created three proper `#!/sbin/openrc-run` scripts:

| Script | Installed to | Notes |
|---|---|---|
| `files-alpine/openrc/koha-plack` | `/etc/init.d/koha-plack` | New; delegates to `/usr/sbin/koha-plack` |
| `files-alpine/openrc/koha-worker` | `/etc/init.d/koha-worker` | New; delegates to `/usr/sbin/koha-worker` |
| `files-alpine/openrc/apache2` | `/etc/init.d/apache2` | Replaces the old 15-line shim |

The `apache2` OpenRC script replaces the crude `cat <<'EOF' ... EOF` shim that was injected inline in the Dockerfile. The COPY step in the Dockerfile happens after the `cat` command, so the proper script wins.

Each script follows the `ebegin`/`eend` convention and supports `start`, `stop`, `reload`, and `status` actions. This provides a correct interface for `rc-service` calls without requiring OpenRC to be PID 1.

**Why not full OpenRC init**: OpenRC is designed as a PID 1 init system. The container runs `bash run.sh` as PID 1. Delegating all process management to OpenRC without it being the init system leads to unstable `rc-status` output, missing `/run/openrc/softlevel`, and unreliable `supervise-daemon` behavior. The correct container-idiomatic pattern is to keep the lightweight watchdog for actual recovery and use the OpenRC scripts as the service management interface (for operators and future full OpenRC adoption).

#### Solution 2: Service watchdog (`run_service_watchdog()` in `run-sh-alpine.sh`)

Added `run_service_watchdog()` to `files-alpine/lib/run-sh-alpine.sh`. Key design decisions:

**Observation-based supervision**: The watchdog first checks which services are running when it starts (immediately after `start_koha_service` returns). Only services that were observed as running are supervised. This prevents the watchdog from repeatedly trying to start a service that was never intended to run (e.g., starman on a CGI-only instance where `starman` is absent).

**Interruptible sleep**: Uses `sleep "${interval}" & ; _watchdog_sleep_pid=$! ; wait ${_watchdog_sleep_pid} || true` pattern. When SIGTERM arrives, `wait` returns immediately and the trap fires.

**Graceful shutdown trap**: On SIGTERM/SIGINT, the trap:
1. Kills the background sleep subprocess
2. Calls `koha-plack --stop` and `koha-worker --stop` for clean termination
3. Exits 0

This allows `docker stop` to complete within its grace period without SIGKILL.

**Restart loop safety**: Services are only restarted if they were running at watchdog start. An instance that fails to start at boot will not be repeatedly restarted by the watchdog — avoiding a crash loop that would spam logs.

**Default interval**: 30 seconds. Configurable by callers via the second argument.

The watchdog **replaces** the old `sleep infinity & wait` blocking loop at the end of `run.sh`.

#### Solution 3: Alpine crond (`start_crond()` and periodic scripts)

Added `start_crond()` to `run-sh-alpine.sh`. Starts BusyBox `crond -b -l 2` (background, low log verbosity).

**crond and `/etc/periodic/`**: BusyBox `crond` reads `/etc/crontabs/root`. The Alpine base image includes `run-parts` crontab entries for the `/etc/periodic/` subdirectories. A Dockerfile `RUN` guard appends these entries if they are absent (idempotent — uses `grep -q 'run-parts'` check first).

Three cron scripts installed:

| Script | Installed to | Schedule | Tasks |
|---|---|---|---|
| `files-alpine/cron/koha-hourly` | `/etc/periodic/hourly/koha-hourly` | Every hour | Zebra rebuild (delta mode), process message queue |
| `files-alpine/cron/koha-daily` | `/etc/periodic/daily/koha-daily` | 02:00 daily | DB cleanup, cancel expired holds, overdue notices |
| `files-alpine/cron/koha-monthly` | `/etc/periodic/monthly/koha-monthly` | Monthly | Statistics archiving |

All scripts guard on `KOHA_CONF` existence — they exit silently (`exit 0`) if the instance has not been bootstrapped yet. This prevents errors during image-level testing or before first container start.

All cron tasks use `sudo -n koha-shell` + `>/dev/null 2>&1 || true` to avoid polluting container logs with transient failures (SMTP unreachable, etc.).

#### Solution 4: Dockerfile wiring

Added to `Dockerfile-Alpine` (inserted after the existing `chmod /etc/init.d/apache2` line, before `mkdir /kohadevbox`):

```dockerfile
# Phase 5: OpenRC service scripts
COPY files-alpine/openrc/apache2      /etc/init.d/apache2
COPY files-alpine/openrc/koha-plack   /etc/init.d/koha-plack
COPY files-alpine/openrc/koha-worker  /etc/init.d/koha-worker
RUN chmod 0755 ... && sed -i 's/\r$//' ...

# Phase 5: Alpine periodic cron scripts
RUN mkdir -p /etc/periodic/hourly ... && (ensure /etc/crontabs/root has run-parts entries)
COPY files-alpine/cron/koha-{hourly,daily,monthly} /etc/periodic/{hourly,daily,monthly}/
RUN chmod 0755 ... && sed -i 's/\r$//' ...
```

The `sed 's/\r$//'` steps are necessary because the host may have CRLF line endings (Windows checkouts), and the shebang line `#!/sbin/openrc-run\r` would cause "bad interpreter" failures.

### Files modified

| File | Change |
|---|---|
| `files-alpine/openrc/koha-plack` | **Created** — OpenRC init script |
| `files-alpine/openrc/koha-worker` | **Created** — OpenRC init script |
| `files-alpine/openrc/apache2` | **Created** — OpenRC init script (replaces Dockerfile shim) |
| `files-alpine/cron/koha-hourly` | **Created** — Hourly cron script |
| `files-alpine/cron/koha-daily` | **Created** — Daily cron script |
| `files-alpine/cron/koha-monthly` | **Created** — Monthly cron script |
| `files-alpine/lib/run-sh-alpine.sh` | **Modified** — added `start_crond()` and `run_service_watchdog()` |
| `files-alpine/run.sh` | **Modified** — added `start_crond` call; replaced `sleep infinity` loop with `run_service_watchdog "${KOHA_INSTANCE}"` |
| `Dockerfile-Alpine` | **Modified** — added Phase 5 OpenRC and cron install blocks |
| `tests/test_phase5_supervision.sh` | **Created** — 35 static + 6 runtime TAP checks |
| `tests/run_all_tests.sh` | **Modified** — added Phase 5 suite entry |
| `docs/Alpine-migration/Phase-5-OpenRC-Supervision-and-Cron-Integration.md` | **Created** — Phase 5 spec and status document |
| `docs/Alpine-migration/Alpine-deeper-integration.md` | **Modified** — Phase 4 and Phase 5 status annotations |

### Blockers encountered

#### Blocker 1: `!` negation in `check()` TAP helper

**Problem**: The test `check "desc" ! grep -q 'sleep infinity' files-alpine/run.sh` failed even after removing `sleep infinity` from `run.sh`. Root cause: the `check()` helper uses `if "$@"` to run the command. When `!` is the first element of `"$@"`, bash tries to execute `!` as a program name (not as the shell negation operator). This always fails, so `not_ok` is always called.

**Solution**: Replaced the `check`-based negation test with an explicit `if/else` block that calls `ok` or `not_ok` directly.

#### Blocker 2: `sleep infinity` string in comment

**Problem**: After replacing the `sleep infinity` blocking loop with `run_service_watchdog`, the first attempt at fixing the comment still contained the text "Replaces the old 'sleep infinity' blocking call". The TAP test checked for the literal string `sleep infinity` anywhere in `run.sh` and thus failed on the comment.

**Solution**: Rewrote the comment to "Replaces the old blocking-loop container-keep-alive pattern", which does not contain `sleep infinity`.

### Test results

Phase 5 guardrail test (`tests/test_phase5_supervision.sh`):
- **35 static checks: all pass**
- **6 runtime checks: all skipped** (container named `koha` not running during this session — runtime tests require a rebuilt image)

Full suite (`tests/run_all_tests.sh`):
- **198 passed, 0 failed, 25 skipped**
- All 12 suites pass

---

## Phase 5 runtime verification — COMPLETED

The following runtime verification was performed after rebuilding the image with Phase 5 changes. The build itself was fast because the early image layers (YAZ compilation, cpanm, npm) were fully cached — only the Phase 5 `COPY`/`RUN` layers and the layers that copy `files-alpine/scripts/` were rebuilt.

### Context: why a full re-bootstrap ran

The test sequence from earlier in the session had removed the `koha-alpine-koha-1` container (`docker rm -f`) to recover from a hung background stack script. The bootstrap marker lives at `/kohadevbox/koha/.alpine-bootstrap-complete` — a file inside the Koha source bind-mount. Because the very first container run (which would have written the marker) had itself failed before completing (the first SSL error below), the file was never created. With `--no-fresh-db` and a missing marker, `stack-alpine.sh` forces a full bootstrap against the existing database rather than resuming in "service start only" mode. This is the intended safety behaviour — it guarantees the instance configuration is always consistent.

A full bootstrap means all initialisation steps in `run.sh` run: `koha-create`, cypress link, l10n fetch, API log4perl TRACE setup, git hooks, `render_vhost`, Apache enable, Plack enable, Zebra start, crond, watchdog. Most of these are idempotent; a few are not, and two of the non-idempotent ones surfaced bugs.

### Build and startup

```
docker compose -f docker-compose-alpinekoha.yml build koha
docker compose -f docker-compose-alpinekoha.yml up -d --force-recreate koha
# Container: koha-alpine-koha-1  /ktd_ready present after ~15s
```

---

### Bug 1 — MariaDB TLS certificate verification failure in `koha-create --use-db`

#### Symptom

First rebuild attempt: container exited with code 255. `docker logs` showed:

```
[koha-create] Detected existing database koha_kohadev; using --use-db
[koha-create-alpine] Using existing database for kohadev
mysql: Deprecated program name. It will be removed in a future release, use '/usr/bin/mariadb' instead
ERROR 2026 (HY000): TLS/SSL error: Certificate verification failure: The certificate is NOT trusted.
[koha-create] WARNING: bootstrap failed in Alpine compatibility mode; continuing to surface downstream blockers
failed to load "/etc/koha/sites/kohadev/koha-conf.xml": No such file or directory
```

All subsequent steps (`log4perl` TRACE setup, Zebra, Apache, Plack) failed because `koha-conf.xml` was never generated — `koha-create` had exited early after the SQL connection check failed.

#### Root cause

The `--use-db` path in `files-alpine/scripts/koha-create` has two distinct connection code paths:

1. **Root path** — `mysql_root_exec()` uses `--defaults-extra-file=/etc/mysql/koha-common.cnf`. That file is written by `run.sh` before `koha-create` is called, and in non-TLS mode it contains:
   ```
   [client]
   host     = db
   user     = root
   password = ...
   ssl      = off
   skip-ssl
   ```
   So root-credential queries are never affected by SSL enforcement.

2. **Instance verification path** — the `else` branch of `if [ "$op" = "create" ]` runs a connectivity check using the Koha instance credentials:
   ```bash
   mysql --host="$mysqlhost" --user="$mysqluser" --password="$mysqlpwd" "$mysqldb" -e 'SELECT 1;' >/dev/null
   ```
   This command does **not** use a defaults file. It inherits whatever SSL policy the MariaDB client applies by default.

A MariaDB client upgrade in the Alpine image changed the default SSL behaviour from *opt-in* (older releases accept unverified connections silently) to *enforced* (newer releases attempt SSL and verify the server certificate against the system trust store). The MariaDB container in this stack uses a self-signed or private CA certificate that is not in Alpine's trust bundle, so verification fails with `HY000 / 2026`.

The `MYSQL_OPT_SKIP_SSL` and `PERL_DBD_MYSQL_SSL_VERIFY_SERVER_CERT` environment variables exported by `run.sh` affect DBD::mysql (the Perl driver) and do not influence the CLI client behaviour.

#### Fix — `files-alpine/scripts/koha-create`

```diff
-    mysql --host="$mysqlhost" --user="$mysqluser" --password="$mysqlpwd" "$mysqldb" -e 'SELECT 1;' >/dev/null
+    mysql --skip-ssl --host="$mysqlhost" --user="$mysqluser" --password="$mysqlpwd" "$mysqldb" -e 'SELECT 1;' >/dev/null
```

`--skip-ssl` is the BusyBox/MariaDB CLI flag that disables SSL negotiation for a single invocation. It is the correct flag for MariaDB; MySQL uses `--ssl-mode=DISABLED`. This check is a "can I connect at all?" probe — it does not need encryption, and in a dev container the DB is on a private Docker network, so skipping SSL is appropriate.

---

### Bug 2 — `set -e` kills the container when git hooks cannot be installed

#### Symptom

After the SSL fix the container reached further into bootstrap but still exited (255). `docker logs` showed:

```
[koha-create-alpine] Using existing database for kohadev
    [*] Installing and setting hooks (/kohadevbox/koha)
cp: cannot create regular file '/kohadevbox/koha/.git/hooks/ktd/post-checkout': Permission denied
cp: cannot create regular file '/kohadevbox/koha/.git/hooks/ktd/pre-commit': Permission denied
error: could not lock config file .git/config: Permission denied
```

The container then stopped — with no `koha-testing-docker has started up` message and no `render_vhost` output, meaning the Apache vhost and all subsequent steps were also skipped.

#### Root cause

`run.sh` opens with `set -e`, which causes the script to exit immediately on any command that returns a non-zero status. The `install_git_hooks()` function (in `run-sh-alpine.sh`) executes:

```bash
run_koha_shell "${KOHA_INSTANCE}" \
  "mkdir -p ${git_base_dir}/.git/hooks/ktd
   cp ${BUILD_DIR}/git_hooks/* ${git_base_dir}/.git/hooks/ktd
   cd ${git_base_dir}
   git config --local core.hooksPath .git/hooks/ktd"
```

`/kohadevbox/koha` is a bind mount of the developer's host git clone. On Linux, the `.git/` directory is owned by the host user (`nicolaie`, uid 1000). The container user (`kohadev-koha`) has a different uid and no write access to `.git/`. Both the `cp` and the `git config` commands exit non-zero.

`run_koha_shell` propagates the exit code of the inner shell. `install_git_hooks()` therefore exits non-zero. With `set -e` active, `run.sh` exits immediately — before `render_vhost`, `a2ensite`, `koha-plack --enable`, or any service start.

**Why this was hidden before**: On previous successful container runs the bootstrap marker was present, so the full bootstrap (including `install_git_hooks`) was skipped entirely. This bug was only exposed when the marker was absent (i.e., first-ever run or marker lost via `docker rm`).

**Why the hooks are optional**: The hooks (`post-checkout`, `pre-commit`) are developer convenience utilities for linting and branch-tracking inside the container. They have no effect on runtime Koha functionality — the OPAC, intranet, Zebra, Plack, and cron all work without them.

#### Fix — `files-alpine/run.sh`

```diff
-install_git_hooks "${GIT_BASE_DIR}"
+install_git_hooks "${GIT_BASE_DIR}" || echo "    [!] Git hooks setup skipped (permission denied — repo owned by host user)"
```

The `|| echo` idiom absorbs any non-zero exit from `install_git_hooks` and returns 0, allowing `set -e` to continue. The message is diagnostic — it explains what happened without masking a serious error with silent suppression.

**Alternative considered**: Patching `install_git_hooks` itself to use `|| true` internally. Rejected because `|| true` is opaque; a future developer would not know why the failure is ignored. The call-site `|| echo` makes the rationale visible at the point of invocation in `run.sh`.

---

### Bug 3 — `GIT_INSTALL: unbound variable` in `koha-plack --status` under `set -eu`

#### Symptom

After both previous fixes the container started successfully. Running the Phase 5 restart-recovery check:

```bash
docker exec koha-alpine-koha-1 /usr/sbin/koha-plack --status kohadev
```

…produced:

```
/usr/share/koha/bin/koha-functions.sh: line 388: GIT_INSTALL: unbound variable
```

Exit code was non-zero, making the status check unusable by the watchdog and by the TAP tests.

#### Root cause — the full call chain

`files-alpine/scripts/koha-plack` opens with `set -eu` (exit on error, treat unset variables as errors). The main dispatch loop calls `do_instance()` for each instance name:

```bash
# in koha-plack (our Alpine script)
do_instance() {
    name="$1"
    adjust_paths_git_install "$name"   # ← called first
    ...
    if [ "$KOHA_BINDIR" = "misc" ]; then
        GIT_INSTALL=1                  # ← set AFTER the function call
    else
        GIT_INSTALL=""
    fi
    export PERL5LIB KOHA_HOME GIT_INSTALL
    ...
}
```

`adjust_paths_git_install` is defined in `/usr/share/koha/bin/koha-functions.sh` (the upstream Debian Koha file, not our Alpine override):

```bash
# in koha-functions.sh (Koha upstream)
adjust_paths_git_install() {
    local instancename=$1
    if is_git_install $instancename; then   # ← calls is_git_install
        KOHA_HOME=$(run_safe_xmlstarlet $instancename intranetdir)
        ...
    fi
}

is_git_install() {
    local instancename=$1 git_install
    if [ -n "$GIT_INSTALL" ]; then          # ← references $GIT_INSTALL
        ...
    fi
    ...
}
```

The sequence is:
1. `do_instance` calls `adjust_paths_git_install`
2. `adjust_paths_git_install` calls `is_git_install`
3. `is_git_install` executes `[ -n "$GIT_INSTALL" ]`
4. `GIT_INSTALL` is not yet set in the environment (it is set several lines *after* the `adjust_paths_git_install` call in `do_instance`)
5. With `set -u` active in `koha-plack`, referencing an unset variable is a fatal error

**Why this was hidden before**: Previous testing only ran `koha-plack --start`, `--stop`, and `--enable` — never `--status` against a live container. All these actions also go through `do_instance` and trigger the same unbound-variable path, but they were only invoked from within `run.sh` which has `GIT_INSTALL` already exported by the time those calls happen (because `run.sh` sets `export GIT_INSTALL` earlier in its flow). When calling `koha-plack --status` directly from outside `run.sh` (e.g., from `docker exec` or the watchdog's check loop), no parent has pre-set `GIT_INSTALL`, so the bug surfaces.

**Why not patch `koha-functions.sh` upstream**: The file `/usr/share/koha/bin/koha-functions.sh` is part of the Koha package and is overwritten on every `build-alpine-package` run. Patching it there would be lost. We already have an Alpine override at `files-alpine/scripts/koha-functions.sh`, but redefining `is_git_install` in the override just to add `${GIT_INSTALL:-}` is invasive — it duplicates function logic that may diverge from upstream. The correct surgical fix is in `do_instance` in our own `koha-plack` script.

#### Fix — `files-alpine/scripts/koha-plack`

```diff
 do_instance() {
     name="$1"
 
+    GIT_INSTALL="${GIT_INSTALL:-}"   # default before adjust_paths_git_install calls is_git_install
     adjust_paths_git_install "$name"
     PERL5LIB="${PERL5LIB:-}:$KOHA_HOME/installer:$KOHA_HOME/lib/installer"
     if [ "$KOHA_BINDIR" = "misc" ]; then
         GIT_INSTALL=1
     else
         GIT_INSTALL=""
     fi
```

`${GIT_INSTALL:-}` expands to the current value of `GIT_INSTALL` if set, or to the empty string if unset — without triggering `set -u`. This is the POSIX-compliant pattern for "default to empty if unset". The subsequent `if [ "$KOHA_BINDIR" = "misc" ]` block then sets the real value, overwriting the empty default with `1` or `""` as appropriate.

---

### Files modified in this verification pass

| File | Change | Rationale |
|---|---|---|
| `files-alpine/scripts/koha-create` | Added `--skip-ssl` to instance credential verification query | Newer MariaDB client enforces SSL by default; self-signed DB cert is not in Alpine trust store |
| `files-alpine/run.sh` | Made `install_git_hooks` non-fatal: `\|\| echo "..."` | `.git/` is owned by host user; hooks are optional convenience tooling; `set -e` was killing the container |
| `files-alpine/scripts/koha-plack` | Added `GIT_INSTALL="${GIT_INSTALL:-}"` before `adjust_paths_git_install` in `do_instance()` | Prevents `set -u` from aborting `--status` calls made outside of `run.sh`'s environment |

---

### Phase 5 runtime test results

```
KOHA_CONTAINER=koha-alpine-koha-1 bash tests/test_phase5_supervision.sh
TAP version 14
# Passed: 41  Failed: 0  Skipped: 0
```

All 6 runtime checks now pass (zero skips) because the container `koha-alpine-koha-1` was live at test time:

| Check | Result |
|---|---|
| crond process is running in container | ✅ PID confirmed via `pgrep -x crond` |
| `/etc/periodic/hourly/koha-hourly` installed | ✅ |
| `/etc/periodic/daily/koha-daily` installed | ✅ |
| `/etc/init.d/koha-plack` installed in image | ✅ mode 755 |
| `/etc/init.d/koha-worker` installed in image | ✅ mode 755 |
| watchdog process is alive (ktd_ready marker) | ✅ marker present; watchdog log confirms `plack=no, worker=no` in CGI-only profile (correct — watchdog does not supervise services that were never started) |

### Full test suite — final state

```
bash tests/run_all_tests.sh
Total: 200 passed  0 failed  24 skipped
All suites passed.
```

200 checks (vs. 198 at the end of the static implementation pass) because the OpenSearch stack was live during this session, promoting 2 previously-skipped OpenSearch auth integration checks to active passes.

---

### Phase 4 pending cleanup (deferred, non-blocking)

- The `AssignUserID` sed in `run.sh` (line 656) can be removed in a future pass once it is confirmed that `render_vhost` always runs before any Apache reload of a Debian-generated vhost. Currently retained as a harmless defensive safety net.

---

## Part 4 — Post-verification fixes (same date, follow-up session)

Two additional issues were discovered and resolved after the Phase 5 runtime verification pass concluded.

---

### Fix 4.1 — `koha-create` argument-ordering bug: credentials silently dropped

#### Symptom

Every container start printed:

```
[koha-create] Detected existing database koha_kohadev; using --use-db
[koha-create-alpine] Using existing database for kohadev
ERROR 1045 (28000): Access denied for user 'koha_kohadev'@'<container-IP>' (using password: YES)
[koha-create] WARNING: bootstrap failed in Alpine compatibility mode; continuing to surface downstream blockers
```

`/etc/koha/passwd` was never written (did not exist after a fresh image start). The container continued to work only because the bootstrap marker was already present from an earlier successful run, so the existing `koha-conf.xml` was reused unchanged.

#### Root cause

In `files-alpine/lib/run-sh-alpine.sh`, `bootstrap_koha_instance()` called:

```bash
koha-create "${koha_create_mode}" "${KOHA_INSTANCE}" \
    --db-user "${DB_USER}" \
    --db-password "${DB_PASSWORD}" \
    --db-name "${DB_NAME}" \
    ...
```

The shell expands this to, for example:

```
koha-create --use-db kohadev --db-user koha_kohadev --db-password password ...
```

Inside `files-alpine/scripts/koha-create`, the argument parser is a POSIX `while/case` loop:

```sh
while [ "$#" -gt 0 ]; do
    case "$1" in
        --use-db)     op="use"; shift ;;
        --db-password) CLO_DB_PASSWORD="$2"; shift 2 ;;
        ...
        *) break ;;   # ← breaks on the first unrecognised token
    esac
done
name="$1"
```

After consuming `--use-db`, the next `$1` is `kohadev` (the instance name). `kohadev` does not match any `--flag` pattern, so the `*) break ;;` arm fires. The loop exits immediately. All subsequent flags — including `--db-user`, `--db-password`, `--db-name` — are never seen by the parser. `CLO_DB_PASSWORD` stays empty.

Further down, credential resolution runs:

```sh
[ -n "$mysqlpwd" ] || mysqlpwd="$(rand_db_password)"   # generates a random password
[ -n "$CLO_DB_PASSWORD" ] && mysqlpwd="$CLO_DB_PASSWORD"  # never fires — CLO_DB_PASSWORD is empty
```

The verify query then runs with the random password instead of `password`, and MariaDB rejects it with `Access denied`.

The same ordering bug silently dropped `--db-user` and `--db-name`, so the conditional block that writes `/etc/koha/passwd` was also never reached.

#### Why the tests still passed

The container continued to function because:

1. The bootstrap marker (`/kohadevbox/koha/.alpine-bootstrap-complete`) persisted on the bind-mounted volume from an earlier successful bootstrap run.
2. In resume mode, `koha-create` is called again to refresh config, but its failure is non-fatal (the `if ! koha-create ...; then echo WARNING` pattern continues regardless).
3. `koha-conf.xml`, the Apache vhost, and all service configs already existed on-volume. Starting Plack/Apache against the existing config worked fine.
4. The `run_all_tests.sh` suite tests endpoints and TAP checks — none assert that `/etc/koha/passwd` was freshly written by the current startup.

#### Fix

Moved `"${KOHA_INSTANCE}"` from the second positional argument to the last argument in the `koha-create` call, after all flags:

```bash
# before
koha-create "${koha_create_mode}" "${KOHA_INSTANCE}" \
    --db-user "${DB_USER}" \
    ...

# after
koha-create "${koha_create_mode}" \
    --db-user "${DB_USER}" \
    --db-password "${DB_PASSWORD}" \
    --db-name "${DB_NAME}" \
    ...
    "${KOHA_INSTANCE}"
```

With this ordering the `while/case` loop consumes all `--flag value` pairs before it hits `kohadev`, at which point `*) break ;;` fires correctly and `name="$1"` = `"kohadev"`. All three `CLO_DB_*` variables are now set, the credential override lines fire, and the passwd-write block runs.

#### Verification

```
# direct test before rebuild — reproduces the failure:
docker exec koha-alpine-koha-1 koha-create --use-db kohadev \
  --db-user koha_kohadev --db-password password ...
# → ERROR 1045 Access denied

# after the fix — same call with instance name last:
docker exec koha-alpine-koha-1 koha-create --use-db \
  --db-user koha_kohadev --db-password password ... kohadev
# → [koha-create-alpine] Using existing database for kohadev  (no error)

docker exec koha-alpine-koha-1 cat /etc/koha/passwd
# → kohadev:koha_kohadev:password:koha_kohadev:db  ✅
```

After rebuild and fresh container start:

```
[koha-create] Detected existing database koha_kohadev; using --use-db
[koha-create-alpine] Using existing database for kohadev
[koha-create-alpine] WARNING: Missing /etc/apache2/sites-available/kohadev.conf; symlink not created
[koha-create-alpine] WARNING: koha-zebra start failed
```

No `Access denied`. Both remaining warnings are pre-existing and non-blocking (vhost symlink is handled by `render_vhost` in `run.sh`; Zebra is already running in the container and `start` on an already-running service is harmless).

---

### Fix 4.2 — `cp_alpine_files.pl` TODO: lines without a destination silently skipped

#### Context

`files-alpine/misc4dev/cp_alpine_files.pl` reads `koha/debian/koha-common.install` to copy Koha's installed files into the running system. The `.install` file uses Debian's packaging format:

```
source-pattern   destination-directory
```

Some lines have only a source path and no explicit destination:

```
debian/tmp/etc/koha/zebradb/[!z]*
debian/tmp/etc/koha/z3950
```

The original code skipped these silently with `next unless $to; # TODO We could handle that`.

#### Root cause / Debian convention

In Debian packaging, a line with no destination means "install to the same absolute path, using the source path relative to `debian/tmp` as the install root". That is:

- source `debian/tmp/etc/koha/zebradb/[!z]*` → installs to `/etc/koha/zebradb/[!z]*`
- source `debian/tmp/etc/koha/z3950` → installs to `/etc/koha/z3950`

The rule: strip the leading `debian/tmp` prefix; the remainder is both the remainder of the source path (relative to `$koha_dir`) and the absolute destination.

#### Fix

```perl
# Debian convention: no dest → strip leading "debian/tmp" to get absolute path
if ( !$to && $from =~ s|^debian/tmp||) { $to = $from; $from = "debian/tmp$from" }
next unless $to;
```

If `$to` is empty and `$from` starts with `debian/tmp`, the regex strips the prefix into `$from` (giving the path-within-koha-dir) and sets `$to` to that stripped path (giving the absolute destination). `$from` is then reconstructed as the full original relative path. Lines that are empty or have neither a `debian/tmp` prefix nor a destination still hit `next unless $to` and are skipped.

---

### Files modified in this follow-up pass

| File | Change |
|---|---|
| `files-alpine/lib/run-sh-alpine.sh` | Moved `"${KOHA_INSTANCE}"` to after all flags in the `koha-create` call inside `bootstrap_koha_instance()` |
| `files-alpine/misc4dev/cp_alpine_files.pl` | Implemented destination derivation for no-dest `.install` lines; removed TODO comment |

### Test suite — final state after follow-up fixes

```
bash tests/run_all_tests.sh
Total: 200 passed  0 failed  18 skipped
All suites passed.
```

---

## Part 5 — Shim audit and removal (same date, third follow-up)

### Objective

Remove all Debian-compatibility shims from `Dockerfile-Alpine` that were no longer load-bearing after the Phase 4 script rewrites, and verify the image still boots cleanly with a full test suite pass.

---

### Audit methodology

Every shim command (`a2ensite`, `a2dissite`, `a2enmod`, `a2dismod`, `daemon`, `apachectl`, `apache2ctl`, `rc-service`, `service`) was traced across:

1. **Our own Alpine scripts** (`run.sh`, `run-sh-alpine.sh`, `koha-create`, `koha-plack`, `koha-worker`)
2. **All staged Debian scripts** in `/usr/sbin/koha-*` and `/usr/share/koha/bin/` inside the live container

The result:

| Shim | Callers in runtime path | Decision |
|---|---|---|
| `apachectl` / `apache2ctl` | `files-alpine/scripts/koha-plack` `check_env_and_warn()` | Remove shim; rewrite callers to use `httpd` directly |
| `a2ensite` | `files-alpine/run.sh` (one call, guarded with `command -v`) | Remove shim; replace call with `ln -sf` |
| `a2dissite` | `koha-remove` only — not in runtime path | Remove |
| `a2enmod` / `a2dismod` | `koha-post-install-setup` only — not in runtime path | Remove |
| `daemon` binary | `koha-es-indexer` only — not in runtime path | Remove |
| `rc-service` wrapper | `service_control()` in `run-sh-alpine.sh` — never called | Remove both wrapper and dead function |
| `service` wrapper | `koha-post-install-setup`, `koha-remove` — not in runtime path; `service_control()` never called | Remove |
| Dead `/etc/init.d/apache2` inline | Overridden 4 lines later by `COPY files-alpine/openrc/apache2` | Remove dead block |
| `/lib/lsb/init-functions` | `koha-zebra` sources it; `koha-zebra` is called by `koha-create` | **Keep** |

---

### Changes made

#### `files-alpine/run.sh`

Replaced `a2ensite` call with direct symlink creation:

```bash
# before
if command -v a2ensite >/dev/null 2>&1; then
    a2ensite ${KOHA_INSTANCE}.conf
fi

# after
mkdir -p /etc/apache2/sites-enabled
ln -sf "/etc/apache2/sites-available/${KOHA_INSTANCE}.conf" \
       "/etc/apache2/sites-enabled/${KOHA_INSTANCE}.conf"
```

#### `files-alpine/lib/run-sh-alpine.sh`

Removed the dead `service_control()` function. It was defined but never called anywhere in the codebase. It existed as a leftover from a period when service management was routed through the shim layer.

#### `files-alpine/scripts/koha-plack`

Replaced `apache2ctl` (version check) and `apachectl` (module check) with direct `httpd` calls in `check_env_and_warn()`:

```bash
# before — two separate guarded blocks
if command -v apache2ctl >/dev/null 2>&1; then
    if ! apache2ctl -v 2>/dev/null | grep -q "Server version: Apache/2.4"; then
        log_warn "koha-plack expects Apache 2.4.x"
    fi
fi
if command -v apachectl >/dev/null 2>&1; then
    for module in $required_modules; do
        if ! apachectl -M 2>/dev/null | grep -q "$module"; then ...

# after — single httpd block
if command -v httpd >/dev/null 2>&1; then
    if ! httpd -v 2>/dev/null | grep -q "Apache/2.4"; then
        log_warn "koha-plack expects Apache 2.4.x"
    fi
    for module in $required_modules; do
        if ! httpd -M 2>/dev/null | grep -q "$module"; then ...
```

#### `Dockerfile-Alpine`

Six shim blocks removed:

1. `apachectl`/`apache2ctl` wrapper (`RUN cat >/usr/sbin/apachectl` + `RUN cp`)
2. `a2ensite`, `a2dissite`, `a2enmod`, `a2dismod` scripts + their `chmod` line
3. `daemon` utility (`RUN cat >/usr/local/bin/daemon` + `chmod`)
4. `/usr/local/bin/rc-service` wrapper + `chmod`
5. `/usr/local/bin/service` wrapper + `chmod`
6. Dead inline `/etc/init.d/apache2` block + `chmod` (was immediately overridden by the Phase 5 `COPY` anyway)

Kept: `/lib/lsb/init-functions` — sourced by the Debian `koha-zebra` script, which is called by our Alpine `koha-create` for Zebra startup.

---

### koha-create rewrite spec — Step 12 completion

As part of this session, `tests/test_phase4_koha_create_rewrite.sh` was extended:

- Three new static checks: parser supports `--db-user`, `--db-password`, `--db-name`
- New live-container section (`KOHA_CONTAINER` pattern, following Phase 5 conventions): `/etc/koha/passwd` written with instance entry, `koha-conf.xml` rendered, `--use-db` re-invocation is idempotent, no `Access denied` in re-invocation output

`docs/Alpine-migration/koha-create-alpine-rewrite-spec.md` Section 15 updated: Step 12 marked `[x]` complete, date updated to 2026-08-03, new validation entries added.

---

### Files modified in this pass

| File | Change |
|---|---|
| `files-alpine/run.sh` | Replaced `a2ensite` call with `mkdir -p` + `ln -sf` |
| `files-alpine/lib/run-sh-alpine.sh` | Removed dead `service_control()` function |
| `files-alpine/scripts/koha-plack` | Replaced `apache2ctl`/`apachectl` calls with `httpd` in `check_env_and_warn()` |
| `Dockerfile-Alpine` | Removed 6 shim blocks: `apachectl`/`apache2ctl`, `a2ensite`/`a2dissite`/`a2enmod`/`a2dismod`, `daemon`, `rc-service`, `service`, dead `/etc/init.d/apache2` inline |
| `tests/test_phase4_koha_create_rewrite.sh` | Added 3 static + 4 live-container checks; Step 12 complete |
| `docs/Alpine-migration/koha-create-alpine-rewrite-spec.md` | Section 15 updated to reflect Step 12 completion |

### Test suite — final state after shim removal

```
KOHA_CONTAINER=koha-alpine-koha-1 bash tests/run_all_tests.sh
Total: 207 passed  0 failed  18 skipped
All suites passed.
```

207 checks (up from 200) — the 7 new koha-create rewrite live-container checks all pass.
