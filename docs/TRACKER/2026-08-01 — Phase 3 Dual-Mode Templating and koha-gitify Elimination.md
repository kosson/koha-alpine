# Phase 3: Dual-Mode Templating & `koha-gitify` Elimination

## Roadmap reference

[Alpine-deeper-integration.md](../Alpine-migration/Alpine-deeper-integration.md) — Phase 3 section.
[Phase-3-Dual-Mode-Templating-and-koha-gitify-Elimination.md](../Alpine-migration/Phase-3-Dual-Mode-Templating-and-koha-gitify-Elimination.md) — detailed plan.

---

## Actions Applied

### Step 3.1 — `KOHA_PATH` detection in `files-alpine/run.sh`

Added a detection block immediately after the `about.pl` early-exit check:

```bash
if [ -d "${BUILD_DIR}/koha/koha-tmpl" ]; then
    export KOHA_PATH="${BUILD_DIR}/koha"
else
    export KOHA_PATH="/usr/share/koha"
fi
export KOHA_LIB_PATH="${KOHA_PATH}/lib"
```

Both variables were added to the `VARS_TO_SUB` manual additions line so `envsubst` substitutes them in all templates processed by `run.sh`.

Result: dev-runtime and prod-runtime both resolve `KOHA_PATH=/kohadevbox/koha` because the source tree is present in both cases. The `/usr/share/koha` fallback covers a future fully-packaged Alpine install.

---

### Step 3.2 — `files-alpine/templates/koha-conf-site.xml.in` — 21 hardcoded paths replaced

All `/usr/share/koha` occurrences replaced with `${KOHA_PATH}` or `${KOHA_LIB_PATH}`:

| Original value | Replacement |
| --- | --- |
| `/usr/share/koha/intranet/htdocs/intranet-tmpl/prog/en/xslt/` (×13) | `${KOHA_PATH}/koha-tmpl/intranet-tmpl/prog/en/xslt/` |
| `<intranetdir>/usr/share/koha/intranet/cgi-bin</intranetdir>` | `<intranetdir>${KOHA_PATH}</intranetdir>` |
| `<opacdir>/usr/share/koha/opac/cgi-bin/opac</opacdir>` | `<opacdir>${KOHA_PATH}/opac</opacdir>` |
| `<opachtdocs>/usr/share/koha/opac/htdocs/opac-tmpl</opachtdocs>` | `<opachtdocs>${KOHA_PATH}/koha-tmpl/opac-tmpl</opachtdocs>` |
| `<intrahtdocs>/usr/share/koha/intranet/htdocs/intranet-tmpl</intrahtdocs>` | `<intrahtdocs>${KOHA_PATH}/koha-tmpl/intranet-tmpl</intrahtdocs>` |
| `<includes>/usr/share/koha/intranet/htdocs/intranet-tmpl/prog/en/includes/</includes>` | `<includes>${KOHA_PATH}/koha-tmpl/intranet-tmpl/prog/en/includes/</includes>` |
| `<install_log>/usr/share/koha/misc/koha-install-log</install_log>` | `<install_log>${KOHA_PATH}/misc/koha-install-log</install_log>` |
| `<docdir>/usr/share/doc/koha-common</docdir>` | `<docdir>${KOHA_PATH}/docs</docdir>` |
| `<backend_directory>/usr/share/koha/lib/Koha/Illbackends</backend_directory>` | `<backend_directory>${KOHA_LIB_PATH}/Koha/Illbackends</backend_directory>` |

Post-change `grep -c 'usr/share/koha'` returned `0`.

---

### Step 3.3 — New file `files-alpine/templates/koha-vhost.conf.in`

New project-owned dual-mode Apache vhost template. Replaces the two-step process of `koha-create` generating a vhost and `koha-gitify` rewriting it.

Contains:

- Intranet `VirtualHost` on `${KOHA_INTRANET_PORT}` with `DocumentRoot`, `ScriptAlias`, `SetEnv KOHA_CONF`, `SetEnv PERL5LIB`, and `Include /etc/koha/apache-shared-intranet.conf`.
- OPAC `VirtualHost` on `${KOHA_OPAC_PORT}` with equivalent directives and `Include /etc/koha/apache-shared-opac.conf`.
- Both blocks include `Options +ExecCGI +FollowSymlinks` and `AddHandler cgi-script .pl` inside `<Directory "${KOHA_PATH}">`, replacing the runtime `sed` injection that previously patched `apache-shared-*-git.conf`.
- All path tokens use `${KOHA_PATH}` and `${KOHA_LIB_PATH}`; hostname/port tokens use existing `VARS_TO_SUB` variables.

---

### Step 3.4 — `render_vhost` function in `files-alpine/lib/run-sh-alpine.sh`

Added after `copy_runtime_files`:

```bash
render_vhost() {
    local instance=$1
    mkdir -p /etc/apache2/sites-available
    envsubst "${VARS_TO_SUB}" \
        < "${BUILD_DIR}/templates/koha-vhost.conf.in" \
        > "/etc/apache2/sites-available/${instance}.conf"
    chmod 644 "/etc/apache2/sites-available/${instance}.conf"
    echo "[render_vhost] Wrote /etc/apache2/sites-available/${instance}.conf (KOHA_PATH=${KOHA_PATH})"
}
```

Runs a single `envsubst` pass using the `VARS_TO_SUB` set from `run.sh` (global scope). Writes the rendered vhost directly to `sites-available`; `a2ensite` then creates the `sites-enabled` symlink.

---

### Step 3.5 — `files-alpine/run.sh` — gitify Stage C replaced, sed injection removed

**Removed** the direct `koha-gitify` invocation block:

```bash
# gitify instance
cd ${BUILD_DIR}/gitify
if [ -x ./koha-gitify ]; then
    ./koha-gitify ${KOHA_INSTANCE} "/kohadevbox/koha"
else
    echo "[koha-gitify] WARNING: koha-gitify helper not available; skipping"
fi
cd ${BUILD_DIR}
```

**Replaced with**:

```bash
# Phase 3: render vhost from dual-mode template (KOHA_PATH already set above)
render_vhost "${KOHA_INSTANCE}"
```

**Removed** the `chown -R "${KOHA_INSTANCE}-koha" ${BUILD_DIR}/gitify` line — the gitify directory is now a stub with no instance-owned state.

**Removed** the entire runtime `sed` injection block (~8 lines) that patched `apache-shared-opac-git.conf` and `apache-shared-intranet-git.conf` with `Options +ExecCGI` and `AddHandler cgi-script .pl` — these directives now live in the `koha-vhost.conf.in` template (Step 3.3).

---

### Step 3.6 — `files-alpine/run.sh` — `--gitify_dir` removed from `do_all_you_can_do.pl` call

Removed `--gitify_dir ${BUILD_DIR}/gitify` from the `do_all_you_can_do.pl` invocation.

The internal `cp_debian_files.pl → koha-gitify` chain inside `do_all_you_can_do.pl` now runs against the no-op stub installed in Step 3.8. The stub exits 0, so the internal chain completes without rewriting any config that `render_vhost` already set correctly.

---

### Step 3.7 — `files-alpine/misc4dev/cp_alpine_files.pl` — gitify call removed

Removed:

- `$gitify_dir` variable declaration.
- `'gitify_dir=s' => \$gitify_dir` from `GetOptions`.
- `die "Missing mandatory option 'gitify_dir'"` guard.
- Three-line block: `sudo cp apache-shared*.conf`, `sudo rm apache-shared-*-git.conf`, and `cd $gitify_dir; sudo ./koha-gitify`.

The script retains its `chown` step and all other file staging. The `gitify_dir` argument is no longer accepted, so passing it to the script would produce a `GetOptions` unknown-option warning but not a fatal error.

---

### Step 3.8 — `Dockerfile-Alpine` — live gitify clone replaced with no-op stub

**Removed**: `git clone https://gitlab.com/koha-community/koha-gitify.git gitify`

**Replaced with**:

```dockerfile
mkdir -p gitify \
&& printf '#!/bin/sh\n# Phase 3: koha-gitify eliminated; no-op stub\nexit 0\n' > gitify/koha-gitify \
&& chmod 0755 gitify/koha-gitify
```

The `gitify/` directory still exists at `/kohadevbox/gitify` so any legacy path reference does not cause a missing-directory crash. The stub `koha-gitify` exits immediately without performing any configuration rewrites. No network fetch; no external repository dependency.

---

### Step 3.9 — `files-alpine/templates/bash_aliases` — `--gitify_dir` removed from operator aliases

- Removed `--gitify_dir=/kohadevbox/gitify` from the `cp_debian_files` alias.
- Removed `--gitify_dir ${BUILD_DIR}/gitify` from the `reset_all` function's `do_all_you_can_do.pl` invocation.

---

### New test — `tests/test_phase3_dual_mode_templating_static.sh`

24 assertions covering:

- `run.sh` sets and exports `KOHA_PATH` / `KOHA_LIB_PATH` and includes them in `VARS_TO_SUB`.
- `run.sh` contains no `./koha-gitify`, no `--gitify_dir`, no gitify `chown`, no `apache-shared-*-git.conf` sed injection.
- `run.sh` calls `render_vhost`.
- `run-sh-alpine.sh` contains `render_vhost()` referencing `koha-vhost.conf.in`.
- `koha-vhost.conf.in` exists and contains `${KOHA_PATH}`, `${KOHA_LIB_PATH}`, `ExecCGI`, and both port variables.
- `koha-conf-site.xml.in` contains no `/usr/share/koha` and uses `${KOHA_PATH}` / `${KOHA_LIB_PATH}`.
- `Dockerfile-Alpine` contains no `koha-gitify.git` clone and contains the no-op stub marker.
- `cp_alpine_files.pl` contains no `gitify_dir` or `koha-gitify`.

Test registered in `tests/run_all_tests.sh`.

---

## Validation Evidence

```bash
bash tests/test_phase3_dual_mode_templating_static.sh
bash tests/test_phase2_build_staging_static.sh
bash tests/test_run_sh_static.sh
bash tests/test_dockerfile_perl_deps_static.sh
bash tests/test_stack_sh_static.sh
```

Results:

- `test_phase3_dual_mode_templating_static.sh`: Passed 24, Failed 0.
- `test_phase2_build_staging_static.sh`: Passed 8, Failed 0.
- `test_run_sh_static.sh`: Passed 12, Failed 0.
- `test_dockerfile_perl_deps_static.sh`: Passed 2, Failed 0.
- `test_stack_sh_static.sh`: Passed 15, Failed 0.

Total: **61 passed, 0 failed**. Editor diagnostics on all modified files: no errors.

---

## Constraint Compliance

No files under `koha/` (Koha source directory) were modified at any point during Phase 3 implementation.
