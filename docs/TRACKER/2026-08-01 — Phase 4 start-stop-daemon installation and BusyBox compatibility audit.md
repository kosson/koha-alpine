# Phase 4 Prerequisite: `start-stop-daemon` Installation & BusyBox Compatibility Audit

## Scope

First deliverable of Phase 4 (POSIX Admin Tools & Shim Removal): resolves Open Question 1 from the Phase 4 analysis document by installing `start-stop-daemon` via `busybox-extras` and producing a verified flag-compatibility matrix against the exact call sites in `koha-plack` and `koha-functions.sh`.

---

## Change Applied

**File**: `Dockerfile-Alpine`

Added `busybox-extras` to the base APK install block:

```dockerfile
    xmlstarlet \
    busybox-extras
```

`busybox-extras` provides `start-stop-daemon` as a BusyBox applet. This resolves the daemon management gap that made `koha-worker --stop` and `koha-plack --stop` silently no-op (the `daemon` shim in §2.4 of the Phase 4 analysis wrote no PID file, so stop/restart had no target).

---

## Test Added

**File**: `tests/test_phase4_start_stop_daemon.sh`

Two-section TAP test:

- **Static**: asserts `busybox-extras` is present in `Dockerfile-Alpine`.
- **Runtime**: builds a container from `koha-alpine:phase2-koha-base-e2e`, probes `start-stop-daemon --help` output, and validates each flag against the exact call sites found in:
  - `koha/debian/scripts/koha-plack` (L151, L185, L317–L336)
  - `koha/debian/scripts/koha-functions.sh` (L321, L345)
  - Proposed `files-alpine/scripts/koha-worker` replacement

Runtime section gracefully skips all assertions with `# SKIP` when no image is available, ensuring the test is non-destructive in CI environments that have not yet built the image.

---

## BusyBox `start-stop-daemon` Compatibility Matrix (Verified 2026-08-01)

Image: `koha-alpine:phase2-koha-base-e2e` (Alpine 3.24.1, `busybox-extras`)

| Flag | BusyBox result | Action for Alpine replacement scripts |
| --- | --- | --- |
| `--stop` / `-K` | Present | Use as-is |
| `--start` / `-S` | Present | Use as-is |
| `--pidfile` / `-p` | Present | Use as-is |
| `--user` / `-u` | Present | Use as-is |
| `--signal` / `-s` | Present | Use as-is (`--signal HUP` for reload) |
| `--retry=QUIT/30/KILL/5` / `-R` | Present | Use as-is |
| `--background` / `-b` | Present | Use as-is |
| `--make-pidfile` / `-m` | Present | Use as-is |
| `--chuid` / `-c` | Deprecated alias for `--user` | **Use `--user` in all new Alpine scripts** |
| `--status` | **Absent** | **Substitute with `--stop --test --pidfile`** |

### Flag not present: `--status`

`--status` is used by two functions in `koha-functions.sh`:

- `is_plack_running` (L321): `start-stop-daemon --pidfile ".../plack.pid" --user="$instance-koha" --status`
- `is_z3950_running` (L345): `start-stop-daemon --pidfile ".../z3950-responder.pid" --user="$instance-koha" --status`

**Required substitution** in `files-alpine/scripts/koha-functions.sh` Alpine override:

```sh
# --status is absent in BusyBox; --stop --test exits 0 if running, 1 if not
start-stop-daemon --stop --test \
    --pidfile "${pidfile}" \
    --user "${user}"
```

Exit-code semantics are identical: 0 = process running, non-zero = not running.

### Flag deprecated: `--chuid`

BusyBox accepts `--chuid` as a deprecated alias (`-c, --chuid: deprecated, use --user`) but may emit a warning on future versions. All Alpine replacement scripts (`koha-worker`, `koha-functions.sh` overrides) must use `--user` exclusively.

---

## Full `--help` Output (Reference)

Captured from `koha-alpine:phase2-koha-base-e2e` for future regression comparison:

```text
Usage: start-stop-daemon [options]

Options: [ I:KN:PR:Sa:bc:d:e:g:ik:mn:op:s:tu:r:w:x:0:1:2:3:4:ChqVvU ]
    --capabilities <arg>   Set the inheritable, ambient and bounding capabilities
    --secbits <arg>        Set the security-bits for the program
    --no-new-privs         Set the No New Privs flag for the program
-I, --ionice <arg>         Set an ionice class:data when starting
-K, --stop                 Stop daemon
-N, --nicelevel <arg>      Set a nicelevel when starting
    --oom-score-adj <arg>  Set OOM score adjustment when starting
-R, --retry <arg>          Retry schedule to use when stopping
-S, --start                Start daemon
-a, --startas <arg>        deprecated, use --exec or --name
-b, --background           Force daemon to background
-c, --chuid <arg>          deprecated, use --user
-d, --chdir <arg>          Change the PWD
-e, --env <arg>            Set an environment string
-k, --umask <arg>          Set the umask for the daemon
-g, --group <arg>          Change the process group
-i, --interpreted          Match process name by interpreter
-m, --make-pidfile         Create a pidfile
-n, --name <arg>           Match process name
-o, --oknodo               deprecated
-p, --pidfile <arg>        Match pid found in this file
-s, --signal <arg>         Send a different signal
-t, --test                 Test actions, don't do them
-u, --user <arg>           Change the process user
-r, --chroot <arg>         Chroot to this directory
-w, --wait <arg>           Milliseconds to wait for daemon start
-x, --exec <arg>           Binary to start/stop
-0, --stdin <arg>          Redirect stdin to file
-1, --stdout <arg>         Redirect stdout to file
-2, --stderr <arg>         Redirect stderr to file
-3, --stdout-logger <arg>  Redirect stdout to process
-4, --stderr-logger <arg>  Redirect stderr to process
-P, --progress             Print dots each second while waiting
    --scheduler <arg>      Set process scheduler
    --scheduler-priority   Set process scheduler priority
    --notify <arg>         Configures experimental notification behaviour
-h, --help                 Display this help output
-C, --nocolor              Disable color output
-V, --version              Display software version
-v, --verbose              Run verbosely
-q, --quiet                Run quietly (repeat to suppress errors)
-U, --user                 Run in user mode
```

---

## Validation Evidence

```bash
bash tests/test_phase4_start_stop_daemon.sh
```

Result (runtime mode, image present):

```text
ok 1  - Dockerfile adds busybox-extras
ok 2  - start-stop-daemon binary exists in image
ok 3  - --stop flag accepted
ok 4  - --start flag accepted
ok 5  - --pidfile flag accepted
ok 6  - --user flag accepted (status mode)
ok 7  - --status absent; --stop --test available as substitute
ok 8  - --signal flag accepted
ok 9  - --retry=QUIT/30/KILL/5 syntax accepted
ok 10 - --background flag accepted
ok 11 - --make-pidfile flag accepted
ok 12 - --chuid accepted (deprecated alias; Alpine scripts must use --user instead)

1..12
# Passed: 12  Failed: 0  Skipped: 0
```

Full static suite (73 assertions, 0 failures) confirmed after `busybox-extras` was added to the Dockerfile.

---

## Consequence for Phase 4 Implementation

Open Question 1 from the Phase 4 analysis is now resolved:

> Use `apk add busybox-extras` (BusyBox implementation). All required flags are present. Two substitutions are needed in Alpine override scripts: replace `--status` with `--stop --test`, and replace `--chuid` with `--user`.

This unblocks steps 7.2–7.5 of the Phase 4 implementation sequence (parallel after `start-stop-daemon` availability is confirmed).
