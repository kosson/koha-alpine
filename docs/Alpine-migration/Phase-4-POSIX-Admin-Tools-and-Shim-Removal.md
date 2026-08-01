# Phase 4: POSIX Admin Tools & Shim Removal

## Roadmap reference

[Alpine-deeper-integration.md](Alpine-deeper-integration.md) — Phase 4 section:

> **Action**: Refactor `koha-create`, `koha-shell`, `koha-plack`, and `koha-worker` to native POSIX shell. Delete shim scripts (`a2ensite`, `a2enmod`, `adduser`, `daemon`, `init-functions`).
>
> **Validation**: Run full instance bootstrap (`koha-create --create-db kohadev`) without any missing command warnings or shim interventions.

---

## 0. Executive Summary

Phase 4 is the highest-complexity phase of the deeper integration roadmap. Every previous phase (1–3) eliminated specific wrapper layers while keeping the Koha Debian scripts largely intact. Phase 4 attacks the scripts themselves: `koha-create` (941 lines), `koha-plack` (501 lines), `koha-worker` (252 lines), `koha-shell` (111 lines Perl), and `koha-functions.sh` (514 lines) — 2 319 lines of Debian-specific shell and Perl.

These scripts live inside `koha/debian/scripts/` which is the Koha source tree. **They must not be modified.** The project's answer to this constraint is to provide project-owned Alpine replacements that intercept the same command names at a higher path priority. This is what the user describes as the `alpine/` subfolder mirroring `debian/scripts/`.

The current `files-alpine/` tree already partially satisfies this role:

- `files-alpine/lib/run-sh-alpine.sh` provides Alpine-compatible functions called from `run.sh`.

- `files-alpine/misc4dev/cp_alpine_files.pl` replaced `cp_debian_files.pl` for file staging.

- `files-alpine/templates/koha-vhost.conf.in` (Phase 3) replaced the gitify-rewritten vhost.

Phase 4 extends this pattern by adding a full `files-alpine/scripts/` directory that ships Alpine-native versions of the admin commands, installed to `/usr/sbin/` at image build time ahead of the Debian-sourced copies.

---

## 1. Constraint: No Modifications to `koha/`

The Koha source tree under `koha/` must never be touched. Every fix must be expressed as:

1. A project-owned script in `files-alpine/scripts/<command>` that overrides the upstream script by being installed first (or to a higher-priority path).

2. A patch in `patches/` applied at build time via `apply-patches.sh`, only as a last resort when a behaviour cannot be intercepted externally.

3. A shim in `Dockerfile-Alpine` or `files-alpine/lib/run-sh-alpine.sh` for isolated one-call problems.

The `alpine/` subfolder concept: `files-alpine/scripts/` mirrors `koha/debian/scripts/` structurally. Each file in `files-alpine/scripts/` is the Alpine-native replacement for the same-named file in `koha/debian/scripts/`. The Dockerfile copies `files-alpine/scripts/*` to `/usr/sbin/` **after** `build-alpine-package.sh` has staged the Debian originals — ensuring the Alpine version wins at runtime.

---

## 2. Current Shim Inventory (Technical Debt in Dockerfile-Alpine)

The following shims exist today. Each one compensates for a gap that Phase 4 is responsible for closing permanently.

### 2.1 `apachectl` / `apache2ctl` (Dockerfile-Alpine ~L231–L248)

**Why it exists**: `koha-create` checks `apachectl -M` to assert `mpm_itk_module`, `rewrite_module`, `cgi_module`, and `ssl_module` are loaded. Alpine Apache does not have `mpm_itk` at all.

**Current behaviour**: Returns hardcoded strings including `mpm_itk_module (shared)`, tricking `koha-create` into passing its module assertions.

**Phase 4 target**: `koha-create` must not gate on `mpm_itk`. The project-owned `files-alpine/scripts/koha-create` bypasses the `mpm_itk` check entirely and verifies only the modules that Alpine actually provides (`event`, `rewrite`, `cgi`).

**Shim fate**: The `apachectl` shim can be simplified to a thin pass-through to `/usr/sbin/httpd` once the Alpine `koha-create` no longer queries for `mpm_itk`. The fake `-M` output can be removed.

---

### 2.2 `a2ensite` / `a2dissite` / `a2enmod` / `a2dismod` (Dockerfile-Alpine ~L251–L278)

**Why they exist**: `koha-create` calls `a2ensite $name` and `a2ensite ${name}.conf` (L903–904). `koha-plack` calls `a2enmod` for proxy modules. No Alpine package ships these commands.

**Current behaviour**:

- `a2ensite`: creates a symlink from `sites-enabled/$site` → `sites-available/$site`.

- `a2dissite`: removes that symlink.

- `a2enmod` / `a2dismod`: no-ops (exit 0).

**Phase 4 target**: The project-owned `files-alpine/scripts/koha-create` renders the vhost and calls `a2ensite` itself via the existing shim, OR manages `sites-enabled` symlinks directly without the shim. Either path is acceptable; the goal is that removing the shims leaves nothing broken.

**Strange behaviour risk**: `koha-create` calls both `a2ensite "$name"` and `a2ensite "${name}.conf"` in sequence. If only the `.conf` variant succeeds, two symlinks may exist. The shim currently creates both silently. Alpine `koha-create` should call only one canonical form.

---

### 2.3 `adduser` long-option translation (Dockerfile-Alpine ~L289–L363)

**Why it exists**: `koha-create` L775 calls:

```sh
adduser --no-create-home --disabled-password \
        --gecos "Koha instance $instance" \
        --home "/var/lib/koha/$instance" \
        "$instance-koha"
```

Alpine BusyBox `adduser` uses short flags only; long options (`--disabled-password`, `--gecos`, `--home`, `--no-create-home`) are Debian-specific.

**Current behaviour**: The shim translates long flags to Alpine equivalents and delegates to `/usr/sbin/adduser`.

**Phase 4 target**: The project-owned `files-alpine/scripts/koha-create` calls `/usr/sbin/adduser` directly with Alpine short flags. The translation shim can be removed.

**Strange behaviour risk**: The shim at L324 prints an `Unsupported adduser option` error and exits 2 for any unrecognised `--*` flag. If `koha-create` adds a new option in a Koha upgrade, startup silently fails user creation. A project-owned Alpine `koha-create` uses only the exact set of flags needed, eliminating this fragility.

---

### 2.4 `daemon` utility (Dockerfile-Alpine ~L366–L386)

**Why it exists**: `koha-worker` calls `daemon $DAEMONOPTS -- $worker_DAEMON --queue ${queue}`, and `koha-functions.sh` calls `daemon --name="$instancename-koha-sip"`, `daemon --name="...-koha-zebra"`, `daemon --name="...-koha-indexer"`, `daemon --name="...-koha-es-indexer"`, and a generic `daemon --name="$name"` pattern.

`daemon` is a Debian utility (`libdaemon0`) that forks a process, writes a PID file, drops privileges, and can stop/restart by PID file. Alpine has no equivalent package.

**Current behaviour**: The shim strips all `--`-prefixed options and then executes the remaining arguments as a background shell job with `&`. This means:

- No PID file is written.
- No privilege dropping occurs.
- No stop/restart by PID is possible.
- The process runs as root, not as the instance user.

**Strange behaviour risk**: This is the most dangerous current shim. Because no PID file is written, `koha-worker` cannot stop or restart a running worker — the `--stop` and `--restart` calls look up a PID file that does not exist and silently fail. This means background workers launched at startup run without any management handle. Phase 4 must fix this.

**Phase 4 target**:

- `files-alpine/scripts/koha-worker`: replace `daemon` calls with direct `su`/`runuser`-based process management that writes a PID file.
- `files-alpine/scripts/koha-functions.sh` (Alpine version): replace `daemon --name=...` calls with Alpine-compatible `start-stop-daemon` invocations or direct process management.
- Or: install `start-stop-daemon` (available as `busybox-extras` or standalone APK) and use it in place of `daemon`.

---

### 2.5 `/lib/lsb/init-functions` (Dockerfile-Alpine ~L389–L399)

**Why it exists**: `koha-plack` and `koha-worker` both source `. /lib/lsb/init-functions` at their top level (L23 in `koha-plack`, L20 in `koha-worker`). This provides `log_daemon_msg`, `log_end_msg`, `log_success_msg`, `log_warning_msg`, and `log_failure_msg`.

**Current behaviour**: A no-op stub that echoes every message. Logging is functionally preserved; status reporting to init systems is suppressed.

**Phase 4 target**: This shim is safe to leave in place (it is not causing functional regressions) but must remain present as long as the Debian scripts are sourced. The project-owned Alpine `koha-plack` and `koha-worker` either source it or use plain `echo` equivalents.

---

### 2.6 `rc-service` / `service` shims (Dockerfile-Alpine ~L402–L438)

**Why they exist**: `koha-create` L422 and L908 call `service apache2 restart`. Alpine does not have the Debian `service` command; it has `rc-service` (OpenRC). The shim intercepts `service apache2` and `service koha-common` as no-ops.

**Current behaviour**: Prints a log line and exits 0, silently skipping Apache restarts.

**Strange behaviour risk**: This means Apache is **never restarted** during `koha-create` execution. The instance is created, configuration files are written, but Apache does not pick them up until the next explicit restart. In the current flow, `run.sh` starts Apache after `bootstrap_koha_instance` finishes, so the sequence is acceptable. But if `koha-create` is called standalone after initial startup, Apache will not hot-reload the new vhost.

**Phase 4 target**: The project-owned `files-alpine/scripts/koha-create` performs an explicit `httpd -k graceful` or equivalent at the points where the Debian original calls `service apache2 restart`. The `service` shim can remain as a safety net for any remaining call sites.

---

### 2.7 `/etc/init.d/apache2` shim (Dockerfile-Alpine ~L430–L441)

**Why it exists**: Some scripts test for the presence of `/etc/init.d/apache2`. The shim satisfies that existence check.

**Current behaviour**: Prints a no-op log line and exits 0.

**Phase 4 target**: Can be removed if no Alpine replacement script calls `invoke-rc.d apache2` or `/etc/init.d/apache2`. Audit after other shims are removed.

---

### 2.8 Runtime `AssignUserID` comment-out (run.sh ~L654–L656)

**Why it exists**: `koha-create` reads `koha/debian/templates/apache-site.conf.in` which contains `AssignUserID __UNIXUSER__ __UNIXGROUP__` in both VirtualHost blocks. After Phase 3 this vhost is replaced by `render_vhost`, which does not contain `AssignUserID`. But the `service apache2 restart` shim silently skips the reload, so if the Debian-generated vhost were ever loaded, its `AssignUserID` would crash Alpine Apache.

**Phase 4 target**: This `sed` line in `run.sh` can be removed once the project-owned `files-alpine/scripts/koha-create` no longer generates a vhost from `apache-site.conf.in` at all (because `render_vhost` in Phase 3 already handles it).

---

## 3. Script-by-Script Refactoring Analysis

### 3.1 `koha-create` (941 lines) — Highest Complexity

#### Debian dependencies to neutralise

| Line range | Dependency | Current workaround | Phase 4 action |
| --- | --- | --- | --- |
| L193–L215 | `apachectl -M` / `mpm_itk` check | `apachectl` shim fakes `mpm_itk_module` | Omit check; Alpine doesn't use mpm_itk |
| L222–L253 | `a2enmod rewrite/cgi/ssl` | `a2enmod` is a no-op shim | Verify modules are loaded in `httpd.conf` at build time; remove runtime check |
| L377–L389 | `dpkg-query`, `apt-cache`, `lsb_release`, `apt-get` for LetsEncrypt | Not shimmed; just fails silently | Replace with `apk info letsencrypt` / `apk add certbot` guard or remove entirely (TLS handled by Traefik) |
| L385 | `lsb_release -c -s` | Not shimmed | Remove; unused in Alpine context |
| L422, L908 | `service apache2 restart` | `service` shim is a no-op | Replace with `httpd -k graceful \|\| true` |
| L775 | `adduser --no-create-home --disabled-password --gecos --home` | `adduser` shim translates flags | Use Alpine `adduser -D -H -h /var/lib/koha/$inst -g "Koha $inst" $inst-koha` directly |
| L903–904 | `a2ensite "$name"` / `a2ensite "${name}.conf"` | `a2ensite` shim creates symlink | Phase 3 `render_vhost` already writes to `sites-available`; just ensure `a2ensite` creates the `sites-enabled` symlink correctly |
| L136–137 | `__UNIXUSER__` / `__UNIXGROUP__` substitution into `apache-site.conf.in` | Phase 3 `render_vhost` now owns the vhost | Skip the `apache-site.conf.in` template entirely in Alpine `koha-create` |

#### Architecture decision: full rewrite vs selective override

Because `koha-create` is 941 lines and touches DB creation, instance directory creation, user creation, Apache setup, Zebra configuration, Memcached, RabbitMQ, and SIP — a full rewrite is extremely high risk. The recommended approach for Phase 4 is a **selective Alpine override**:

1. Write `files-alpine/scripts/koha-create` as a thin wrapper that:
   - Exports `ALPINE_KOHA=yes` to the environment.
   - Delegates to the upstream `koha/debian/scripts/koha-create` via `exec`.
   - But first replaces/wraps the exact functions that call Debian tools.

2. Alternatively, use `source`/function-overriding: source `koha/debian/scripts/koha-functions.sh` then redefine the Alpine-incompatible functions before sourcing `koha/debian/scripts/koha-create` logic.

However, `koha-create` is a shell script, not a function library. It cannot be selectively sourced. The cleanest safe approach is:

**Write `files-alpine/scripts/koha-create` as a full Alpine implementation** that reproduces exactly the actions taken by the upstream `koha-create --create-db` path, but using Alpine-native tools. Scope it to the minimal path that `run.sh` actually exercises: `--create-db` with the specific options passed by `bootstrap_koha_instance`.

Do not implement the full 941-line feature set (TLS, Zebra cluster, HTTPS site generation, etc.) until each feature is actively tested in Alpine context.

---

### 3.2 `koha-shell` (111 lines Perl) — Medium Complexity

`koha-shell` is a Perl script. It:

1. Reads `/etc/default/koha-common` for `PERL5LIB`.
2. Calls `. /usr/share/koha/bin/koha-functions.sh; if is_git_install $instance; then echo 1; fi` via backtick shell-out.
3. Constructs a `sudo --preserve-env --login -u $instance-koha env ... /bin/sh` command.

**Problems on Alpine**:

- `/etc/default/koha-common` exists (staged by `build-alpine-package.sh`), so the read works.
- The backtick call to `is_git_install` sources `koha-functions.sh` which calls `daemon` and `start-stop-daemon` — but `is_git_install` itself does not exercise those paths. It only reads `koha-conf.xml` and returns 1 if it looks like a git install. This path is safe.
- `sudo` is installed. The `sudo -u $instance-koha env KOHA_CONF=... PERL5LIB=... /bin/sh -c 'cd ...; /bin/sh'` command works on Alpine if the sudoers file is set up correctly. Phase 3 already handles the sudoers template.

**Conclusion**: `koha-shell` as-is is likely functional on Alpine with the existing sudoers setup. No Alpine override is needed for Phase 4 unless `is_git_install` detection causes a mismatch.

**Latent risk**: `read_perl5lib` reads `PERL5LIB` from `/etc/default/koha-common`. If the value there does not include `/kohadevbox/koha`, `koha-shell` will launch with an incomplete `PERL5LIB`. The `run.sh` environment already exports the correct `PERL5LIB`; the instance `bashrc` template sets it for instance-user shells. But `koha-shell` overrides it with whatever is in `/etc/default/koha-common`. **This is a bug that can cause `Compilation failed in require` errors when running scripts via `koha-shell`**. Phase 4 must ensure `/etc/default/koha-common` contains the correct Alpine `PERL5LIB`.

---

### 3.3 `koha-plack` (501 lines) — High Complexity

`koha-plack` sources `/lib/lsb/init-functions` and uses:

- `log_daemon_msg` / `log_end_msg` — covered by the no-op shim.

- `start-stop-daemon` — **this is a real Debian binary** for daemon lifecycle management.

- `apachectl`/`apache2ctl` — checked for proxy module presence (L317–L336).

- `a2enmod` — called if proxy modules are missing (L336).

`start-stop-daemon` in Alpine: It is **available** in Alpine via the `dpkg` package (which provides `start-stop-daemon` as a standalone binary) or via `busybox-extras`. This is one of the few cases where the Debian utility can be installed natively.

**Recommended approach**: Install `start-stop-daemon` in `Dockerfile-Alpine` via `apk add dpkg` or compile it. Then `koha-plack` works almost unmodified.

**Remaining issue**: The module check at L317–L336 calls `apache2ctl -v` and `apachectl -M` to check for `proxy_module`, `proxy_http_module`, `proxy_fcgi_module`. The current `apachectl` shim returns `mpm_itk_module` but not proxy modules. If `koha-plack` is asked to configure Plack in proxy mode, this check will fail to detect the modules as loaded and will call `a2enmod` (which is a no-op). The proxy modules must actually be loaded in `httpd.conf`.

**Phase 4 action for `koha-plack`**:

1. Install `start-stop-daemon` natively.

2. Extend the `apachectl -M` shim to also echo proxy module names, OR load them unconditionally in `httpd.conf` so the check passes.

3. Optionally write `files-alpine/scripts/koha-plack` that calls `start-stop-daemon` directly and skips the Apache module check.

---

### 3.4 `koha-worker` (252 lines) — Medium-High Complexity

`koha-worker` sources `/lib/lsb/init-functions` and uses `daemon $DAEMONOPTS -- $worker_DAEMON` for start/stop/restart.

As documented in §2.4, the current `daemon` shim is fundamentally broken for stop/restart: it forks to background with no PID file, so `--stop` is a silent no-op.

**Impact on current runtime**: Background workers are started once at container boot by `koha-worker --start`. They cannot be stopped or restarted without killing the container. For development this is tolerable; for production this is a reliability defect.

`DAEMONOPTS` is set by `koha-worker` to something like:

```bash
DAEMONOPTS="--name=${name}-worker --pidfile=${PIDFILE} --user=${name}-koha"
```

```text
`daemon` understands these options. The shim strips them all.
```

**Phase 4 action for `koha-worker`**: Write `files-alpine/scripts/koha-worker` that replaces `daemon` calls with:

```sh
start-stop-daemon --start \
    --pidfile "${PIDFILE}" \
    --chuid "${instance}-koha" \
    --background \
    --make-pidfile \
    --exec "$worker_DAEMON" -- --queue "${queue}"

```text

And stop:

```sh
start-stop-daemon --stop \
    --pidfile "${PIDFILE}" \
    --user "${instance}-koha" \
    --retry QUIT/30/KILL/5

```text

This is a self-contained rewrite of the relevant section; the rest of `koha-worker` (option parsing, queue management, status reporting) is Alpine-compatible.

---

### 3.5 `koha-functions.sh` (514 lines) — Medium Complexity

`koha-functions.sh` is sourced by almost every Koha admin script. Its Debian dependencies are:

| Function | Debian dependency | Alpine situation |
| --- | --- | --- |
| `koha_sip_start` | `daemon --name=...-koha-sip` | Same `daemon` PID problem as §2.4 |
| `koha_zebra_start` | `daemon --name=...-koha-zebra` | Same |
| `koha_indexer_start` | `daemon --name=...-koha-indexer` | Same |
| `koha_es_indexer_start` | `daemon --name=...-koha-es-indexer` | Same |
| `generic_start` | `daemon --name=$name` | Same |
| `plack_stop` | `start-stop-daemon --pidfile ...` | Works if `start-stop-daemon` is installed |
| `z3950_stop` | `start-stop-daemon --pidfile ...` | Works if `start-stop-daemon` is installed |
| `is_git_install` | reads `koha-conf.xml` via `xmlstarlet` | `xmlstarlet` is installed in Alpine image |
| `is_plack_enabled*` | reads `/etc/koha/plack.conf` | Works if file exists; may not exist in Alpine |

**Phase 4 action for `koha-functions.sh`**: Write `files-alpine/scripts/koha-functions.sh` (Alpine override) that:

1. Sources the upstream `koha-functions.sh`.

2. Redefines `koha_sip_start`, `koha_zebra_start`, `koha_indexer_start`, `koha_es_indexer_start`, and `generic_start` to use `start-stop-daemon` instead of `daemon`.

3. All other functions are inherited as-is.

---

## 4. The `files-alpine/scripts/` Model

### 4.1 Why `files-alpine/scripts/` satisfies the constraint

`files-alpine/` already plays the role the user identifies as the "alpine subfolder that mirrors the original arrangement":

| `koha/debian/scripts/` | `files-alpine/scripts/` (proposed) | Role |
| --- | --- | --- |
| `koha-create` | `files-alpine/scripts/koha-create` | Full Alpine override |
| `koha-functions.sh` | `files-alpine/scripts/koha-functions.sh` | Partial override (redefines daemon functions only) |
| `koha-plack` | `files-alpine/scripts/koha-plack` | Partial override (start-stop-daemon + module check) |
| `koha-worker` | `files-alpine/scripts/koha-worker` | Full override (daemon → start-stop-daemon) |
| `koha-shell` | not needed yet | Upstream Perl script works on Alpine |
| `koha-enable` | not needed | Sources only koha-functions.sh; Alpine-safe |
| `koha-rebuild-zebra` | not needed | Alpine-safe once koha-functions.sh is overridden |

### 4.2 Dockerfile installation order

```dockerfile
# Stage Koha Debian scripts at build time
RUN /usr/local/bin/build-alpine-package.sh /kohadevbox/koha
# ... (already done; stages debian/scripts/* to /usr/sbin/)

# Alpine overrides: installed AFTER Debian scripts, so they win by path
COPY files-alpine/scripts/ /usr/sbin/
RUN chmod 0755 /usr/sbin/koha-create /usr/sbin/koha-functions.sh \
                /usr/sbin/koha-plack /usr/sbin/koha-worker

```text

This mirrors the established pattern from Phase 2 and Phase 3 where project-owned files supersede Debian-originated files.

### 4.3 Key invariant

Every file in `files-alpine/scripts/` is 100% owned and maintained by this project. It may internally delegate to the upstream Debian script where safe to do so, but it is the single point of truth for Alpine-runtime behaviour of that command.

---

## 5. Strange Behaviours and Risk Register

### 5.1 `koha-create` TLS and LetsEncrypt path (lines 377–389)

`koha-create` has a LetsEncrypt installation path guarded by `dpkg-query` and `apt-get`. On Alpine, `dpkg-query` does not exist, so this guard produces a command-not-found error. The error is non-fatal (continues past it), but it may pollute logs. The Alpine `koha-create` must remove this block entirely, as TLS is handled by Traefik in this project.

### 5.2 `service apache2 restart` races (koha-create L422 and L908)

The current shim silently skips these restarts. As a result:

- L422: Apache is not restarted after initial module-load changes. Since `httpd.conf` is already correct at image build time, this is safe.

- L908: Apache is not restarted after enabling the new vhost site. `run.sh` starts Apache explicitly after `bootstrap_koha_instance` returns, so the vhost is loaded correctly. If `koha-create` is called again later (e.g., `--use-db` restart path), the vhost is already in `sites-enabled` and Apache is already running — no restart needed.

**Residual risk**: calling `koha-create` standalone outside of `run.sh` will not reload Apache. Acceptable for development; must be documented.

### 5.3 `start-stop-daemon` availability gap

`start-stop-daemon` is used directly by `koha-plack` (`koha-plack` L151, L185) and `koha-functions.sh` (L321, L345). Unlike `daemon`, `start-stop-daemon` **is available on Alpine** via `apk add busybox-extras` (BusyBox extended tools). This is the cleanest resolution: one APK add, and both `koha-plack` and `koha-functions.sh` stop/restart calls work natively.

**Verification needed**: Alpine `start-stop-daemon` is a BusyBox implementation. Confirm it supports `--make-pidfile`, `--background`, `--chuid`, `--retry QUIT/30/KILL/5`, which are the exact flags used in `koha-plack` and `koha-worker`.

### 5.4 `is_git_install` detection in `koha-shell`

`koha-shell` calls `is_git_install` via a backtick shell-out. `is_git_install` (koha-functions.sh L383) reads `koha-conf.xml` and returns 1 if `<intranetdir>` does not equal the package default. After Phase 3, `<intranetdir>` is set to `${KOHA_PATH}` which resolves to `/kohadevbox/koha` — this **will** trigger `is_git_install = 1`. `koha-shell` then reads `PERL5LIB` from the `intranetdir` XML entry. This is correct for dev; `PERL5LIB` will be `/kohadevbox/koha:/kohadevbox/koha/lib`. **This is the right behaviour.**

### 5.5 `koha-enable` / `koha-disable` — safe but must be verified

`koha-enable` sources `koha-functions.sh` and calls `a2ensite` (via `enable_instance`). Since `a2ensite` is a shim that creates `sites-enabled` symlinks, this works. After Phase 4 shim removal, if `a2ensite` is removed, `koha-enable` will fail. The Alpine `koha-create` must perform the `sites-enabled` symlink itself, making the `koha-enable` call redundant for the initial creation path.

### 5.6 `AssignUserID` in the Debian-generated `apache-site.conf.in` vhost

After Phase 3, `run.sh` calls `render_vhost` which writes the project-owned vhost to `sites-available`. It then calls `koha-enable` which calls `a2ensite` creating the `sites-enabled` symlink. However, `bootstrap_koha_instance` calls `koha-create`, which internally also writes a vhost from `apache-site.conf.in`. This means there are **two vhost files**:

1. `/etc/apache2/sites-available/$INST.conf` — written by `koha-create` from `apache-site.conf.in`, contains `AssignUserID`.

2. The `render_vhost` output — overwrites file 1 with our correct template.

The sequence is: `bootstrap_koha_instance` → `render_vhost` (overwrites). So file 1 is immediately replaced before Apache loads it. The `AssignUserID sed` strip in `run.sh` is thus redundant but harmless. Phase 4 can remove it once we confirm `render_vhost` always runs before `koha-enable` / `a2ensite`.

### 5.7 `koha-plack --enable` and plack configuration files

`koha-plack --enable $instance` is called from `enable_instance_services` in `run-sh-alpine.sh`. This writes `/etc/koha/plack.conf` or modifies `/etc/koha/sites/$INST/koha-conf.xml` to enable Plack. The actual Plack startup (`koha-plack --start`) uses `start-stop-daemon`. If `start-stop-daemon` is not installed, the `--enable` call succeeds but `--start` silently skips.

### 5.8 The `__UNIXUSER__` / `__UNIXGROUP__` substitution issue

`koha-create` performs `sed -e "s/__UNIXUSER__/$username/g" -e "s/__UNIXGROUP__/$username/g"` on templates at L136–137. After Phase 3, the vhost is from our template — not from `apache-site.conf.in`. But `koha-create` still processes `apache-site.conf.in` internally and writes the result to `sites-available`. `render_vhost` then overwrites it. This double-write is wasteful but not harmful. The Alpine `koha-create` can skip the `apache-site.conf.in` processing entirely.

### 5.9 Group management gap

`koha-create` calls `adduser --no-create-home --disabled-password ...` but also calls `adduser` with a `--ingroup` flag in some code paths (for adding the instance user to groups). The current `adduser` shim does not handle `--ingroup`. If any `koha-create` code path uses `--ingroup`, it will hit the `Unsupported adduser option` error and exit 2. Audit needed.

---

## 6. What Phase 4 Does NOT Require

The following items appear related but are out of Phase 4 scope:

- **`start-stop-daemon` for Plack in Plack-disabled mode**: When Plack is disabled (CGI mode), `koha-plack --start` is never called. Most dev containers run in CGI mode. Phase 4 still installs `start-stop-daemon` so the code path is correct, but it is not a current-state regression.

- **Full `koha-create` feature parity**: LetsEncrypt, HTTPS site generation, multi-site Zebra clustering, and LDAP setup are not exercised in this project's startup path. The Alpine `koha-create` needs only the `--create-db` and `--use-db` paths.

- **`koha-remove`**: Instance removal is not part of the container lifecycle. Out of scope.

- **`koha-upgrade-schema`**: Called by `do_all_you_can_do.pl` → `koha-upgrade-schema` is a simple Perl wrapper around `C4::Installer`. It has no Debian tool dependencies. Not needed in Phase 4.

---

## 7. Implementation Sequence

```text

7.1  apk add busybox-extras (or dpkg) → provides start-stop-daemon
7.2  files-alpine/scripts/koha-functions.sh
        → redefines daemon-based start functions to use start-stop-daemon
7.3  files-alpine/scripts/koha-worker
        → replaces daemon calls with start-stop-daemon; self-contained rewrite
7.4  files-alpine/scripts/koha-plack
        → replaces daemon/start-stop-daemon calls; removes apache2ctl module check
7.5  files-alpine/scripts/koha-create
        → Alpine --create-db path: removes mpm_itk check, replaces adduser,
           replaces service apache2 restart, skips apache-site.conf.in templating,
           removes lsb_release / dpkg-query / apt-get blocks
7.6  /etc/default/koha-common population
        → ensure PERL5LIB is set correctly for koha-shell
7.7  Dockerfile-Alpine: COPY files-alpine/scripts → /usr/sbin/ (after build-alpine-package.sh stage)
7.8  Dockerfile-Alpine: apk add busybox-extras
7.9  Remove or simplify shims that are no longer needed:
        - apachectl fake -M mpm_itk output
        - adduser long-option translation
        - AssignUserID sed strip in run.sh
7.10 tests/test_phase4_posix_admin_tools_static.sh
        → assert no mpm_itk in apachectl shim
        → assert adduser shim references are gone
        → assert files-alpine/scripts/* exist and are executable
        → assert no daemon-based calls remain in project-owned scripts

```text

Steps 7.2–7.5 are independent of each other once `start-stop-daemon` is available (7.1).

---

## 8. Validation Criteria (from roadmap)

> "Run full instance bootstrap (`koha-create --create-db kohadev`) without any missing command warnings or shim interventions."

**Static test assertions**:

1. No `mpm_itk` string appears in the Alpine `koha-create` or `apachectl` shim output path.

2. No `daemon` (Debian utility) call in any `files-alpine/scripts/` file.

3. No `adduser --disabled-password` (long-option form) in any `files-alpine/scripts/` file.

4. All `files-alpine/scripts/koha-*` files are executable.

5. `start-stop-daemon --version` succeeds inside the built image.

**Runtime smoke test**:

```bash
docker exec koha koha-create --create-db kohatest 2>&1 | grep -iE 'error|warn|shim|mpm_itk|not found|command not found' | wc -l
# Expected: 0

```text

---

## 9. Open Questions for Decision Before Implementation

1. **`start-stop-daemon` source**: Use `apk add busybox-extras` (BusyBox implementation) or compile the standalone Debian utility? BusyBox version is simpler but may not support all flags. Needs a compatibility matrix check against `koha-plack` and `koha-worker` usage.

2. **Alpine `koha-create` scope**: Full rewrite of the `--create-db` path vs thin wrapper with function overrides? The thin-wrapper approach is more maintainable across Koha version upgrades; the full rewrite is more predictable and testable.

3. **`apachectl` shim fate after Phase 4**: Once Alpine `koha-create` no longer checks `mpm_itk`, can the fake `-M` output be removed entirely? Yes, if `koha-plack`'s module check is also removed or bypassed. This simplifies `apachectl` back to a clean pass-through to `/usr/sbin/httpd`.

4. **`koha-enable` call in `run.sh`**: After Phase 4, `bootstrap_koha_instance` (Alpine `koha-create`) handles vhost creation via `render_vhost`. Should `koha-enable` still be called? Its only useful work is creating `sites-enabled` symlinks and writing `plack.conf`. If `render_vhost` and `koha-plack --enable` are called directly by `run.sh`, `koha-enable` becomes redundant.

5. **Interaction with Phase 5 (OpenRC)**: `koha-plack` and `koha-worker` use `start-stop-daemon` for background process management. Phase 5 moves these to OpenRC `init.d` scripts. If Phase 4 makes `koha-plack` and `koha-worker` work correctly with `start-stop-daemon`, Phase 5 can replace the daemon lifecycle with OpenRC without affecting the command interface.
