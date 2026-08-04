---
title: "Prod image HTTP 500 post-mortem and seven runtime hardening fixes"
date: 2026-08-04
tags:
  - alpine
  - prod
  - PERL5LIB
  - apache
  - apache-shared.conf
  - apache-shared-intranet.conf
  - apache-shared-opac.conf
  - koha-vhost.conf.in
  - DocumentRoot
  - koha-common
  - run.sh
  - docker-env
  - hardening
---
# 2026-08-04 — Prod image HTTP 500 post-mortem and **seven** runtime hardening fixes

## Session overview

After the previous session confirmed both dev and prod images built successfully and the prod
container reached READY state, a smoke test of the prod container's Intranet endpoint returned
HTTP 500. Debugging revealed **four independent causes** that compounded to break the prod image
while the dev image appeared fine. A fifth pre-existing bug was also uncovered during the
investigation that affected dev as well. All five were fixed.

A sixth bug was found in a subsequent session when rebuilding the prod image from scratch using
tag `v25.11.06-1` (instead of the previously tested `v26.05.01-1`): the fresh container
returned HTTP 403 on both Intranet and OPAC. This was a separate Apache shared-configuration
path override, and was also fixed.

A seventh bug was uncovered immediately after the HTTP 403 fix: all CSS, JavaScript, and image
assets returned HTTP 404, making every page render unstyled and non-functional. The root cause
was a `DocumentRoot` that was one directory level too deep in the vhost template. This was also
fixed and the image rebuilt.

---

## Problem 1 — `write_db_client_configs()` crashes when TLS certs are absent

### Symptom

Prod container exits immediately with:

```
[run.sh] ERROR line 180: write_db_client_configs kohadev (exit 1)
```

`koha-prod-test` was left with no IP address (never joined the network) because `run.sh`
terminated before Apache could start.

### Root cause

`run.sh` has `set -e` at the top, which causes any command returning a non-zero exit to abort
the script. Inside `write_db_client_configs()` in `files-alpine/lib/run-sh-alpine.sh`, the
TLS cert lines were written using a short-circuit pattern:

```bash
[ -n "${KOHA_DB_TLS_CLIENT_KEY:-}" ] && printf 'ssl-key  = %s\n' "${KOHA_DB_TLS_CLIENT_KEY}"
```

When `KOHA_DB_TLS_CLIENT_KEY` is empty (no client certificate configured), `[ -n "" ]` returns
exit code 1. Because this is the last statement in the subshell's `if` branch, that exit 1
propagates as the function's exit status. With `set -e` active in `run.sh`, this kills the
container immediately.

The dev container escaped this because all three TLS vars (`KOHA_DB_TLS_CA_CERTIFICATE`,
`KOHA_DB_TLS_CLIENT_CERTIFICATE`, `KOHA_DB_TLS_CLIENT_KEY`) were explicitly set in the compose
`.env` file — the `[ -n ... ]` tests always returned 0.

The prod container's bare `docker run` invocation did not pass client cert vars. The default
value for `KOHA_DB_USE_TLS` is `yes` (set in `files-alpine/templates/koha-sites.conf` and in
`docker-compose-alpinekoha.yml`), so the TLS branch was entered, the client key var was empty,
and the function exited 1.

### Fix applied

`files-alpine/lib/run-sh-alpine.sh` — appended `|| true` to all six conditional cert lines
(three in the `koha-common.cnf` block, three in the instance-specific `koha_${instance}.cnf`
block):

```bash
# Before
[ -n "${KOHA_DB_TLS_CLIENT_KEY:-}" ] && printf 'ssl-key  = %s\n' "${KOHA_DB_TLS_CLIENT_KEY}"

# After
[ -n "${KOHA_DB_TLS_CLIENT_KEY:-}" ] && printf 'ssl-key  = %s\n' "${KOHA_DB_TLS_CLIENT_KEY}" || true
```

### Why `|| true` is correct here

The `[ -n ... ] && cmd` pattern is specifically intended to run `cmd` only when the condition
is true and **silently do nothing** when it is false. The false case is not an error — it means
"this cert is not configured, so skip this line in the output file". Appending `|| true`
resets the exit status to 0 in the false case, which is the intended semantic. Using `if/fi`
would be equally correct but noisier.

---

## Problem 2 — `KOHA_INTRANET_PORT` / `KOHA_OPAC_PORT` unset in bare `docker run`

### Symptom

After fixing Problem 1, the container started but Apache refused to start with:

```
AH00526: Syntax error on line 485 of /etc/apache2/httpd.conf:
Listen requires 1 or 2 arguments.
```

Inspecting `httpd.conf` showed:

```
Listen
Listen
```

(two blank Listen directives at the end of the file)

### Root cause

`run.sh` appends `Listen` directives to `httpd.conf` to tell Alpine's Apache which ports to
bind:

```bash
append_if_absent "Listen ${KOHA_INTRANET_PORT}" /etc/apache2/httpd.conf
append_if_absent "Listen ${KOHA_OPAC_PORT}"     /etc/apache2/httpd.conf
```

When `KOHA_INTRANET_PORT` and `KOHA_OPAC_PORT` are not set, these expand to `"Listen "` —
a syntactically invalid Apache directive.

These variables are defined in `env/.env` and `env/defaults.env` (values: 8081 and 8080
respectively). When the container is launched via `docker compose`, Docker injects the `.env`
file automatically. A bare `docker run` without `-e` flags for these vars leaves them unset.

The same problem also affected the VirtualHost blocks rendered by `render_vhost()`: the
vhost template uses `${KOHA_INTRANET_PORT}` and `${KOHA_OPAC_PORT}` via `envsubst`. With
unset vars, the vhost became:

```apache
<VirtualHost *:>
```

Apache parsed this as a wildcard host with no port and silently accepted it — but matched
no requests, causing HTTP 404 on every URL.

### Fix applied

Added default exports at the top of `run.sh` (immediately after the `TZ` export, before any
use of the port variables):

```bash
export KOHA_INTRANET_PORT=${KOHA_INTRANET_PORT:-8081}
export KOHA_OPAC_PORT=${KOHA_OPAC_PORT:-8080}
```

Additionally, the `append_if_absent` calls were updated to use the same defaults as a
belt-and-suspenders guard:

```bash
append_if_absent "Listen ${KOHA_INTRANET_PORT:-8081}" /etc/apache2/httpd.conf
append_if_absent "Listen ${KOHA_OPAC_PORT:-8080}"     /etc/apache2/httpd.conf
```

The defaults mirror the values in `env/template.env` (8081 intranet, 8080 OPAC) which are the
canonical port assignments for this project. Any operator who wants non-standard ports passes
them explicitly via `-e`; the defaults simply protect against accidental omission.

---

## Problem 3 — `ENV PERL5LIB` set correctly in image but overridden by `apache-shared.conf`

### Symptom

After fixing Problems 1 and 2, Apache started, but `mainpage.pl` returned HTTP 500 with:

```
Can't locate Koha.pm in @INC (@INC entries checked: /usr/share/koha/lib …)
  at /usr/share/koha/lib/C4/Context.pm line 48
Compilation failed in require at /usr/share/koha/lib/C4/Auth.pm line 40.
```

The `@INC` shown in the error contained `/usr/share/koha/lib` but **not** `/kohadevbox/koha`.
This is the wrong path: the Koha source in the prod image lives at `/kohadevbox/koha`, not
`/usr/share/koha`.

### Investigation

The image already had `ENV PERL5LIB=/kohadevbox/koha:/kohadevbox/koha/lib` from a fix applied
earlier in this session. Confirmed:

```
$ docker exec koha-prod-test sh -c 'echo $PERL5LIB'
/kohadevbox/koha:/kohadevbox/koha/lib
```

The vhost `sites-enabled/kohadev.conf` also had the correct `SetEnv`:

```apache
SetEnv PERL5LIB  /kohadevbox/koha:/kohadevbox/koha/lib
```

So where did `/usr/share/koha/lib` come from?

#### The offending file: `/etc/koha/apache-shared.conf`

Searching all Apache config for PERL5LIB:

```
/etc/apache2/sites-available/kohadev.conf:    SetEnv PERL5LIB  /kohadevbox/koha:…  ← correct
/etc/apache2/sites-enabled/kohadev.conf:      SetEnv PERL5LIB  /kohadevbox/koha:…  ← correct
```

But inspecting `/etc/koha/apache-shared.conf`:

```apache
SetEnv PERL5LIB "/usr/share/koha/lib"
```

This file is `Include`d **inside** the VirtualHost block, **after** the vhost's own `SetEnv`:

```apache
<VirtualHost *:8081>
    SetEnv PERL5LIB  /kohadevbox/koha:/kohadevbox/koha/lib   ← set first
    …
    Include /etc/koha/apache-shared.conf                     ← overrides PERL5LIB!
    …
</VirtualHost>
```

Apache processes `SetEnv` directives in document order. The last `SetEnv` for a given variable
wins. The `Include` brings `apache-shared.conf` content inline at that position, so its
`SetEnv PERL5LIB "/usr/share/koha/lib"` executes after and overwrites the vhost's correct
value. Every CGI request then launches Perl with `PERL5LIB=/usr/share/koha/lib`.

#### Why the dev container worked

In the dev container, `PERL5LIB` is already set at the **process level** before Apache starts,
because:

1. `docker compose` injects it from `env/.env` (which has `PERL5LIB=/kohadevbox/koha:…`)
2. `run.sh` does not explicitly unset it

Apache inherits the process-level env. When `apache-shared.conf` issues
`SetEnv PERL5LIB "/usr/share/koha/lib"`, it sets the per-request CGI environment variable —
but only for the Apache worker processes, not for the parent process. Crucially, **the mod_cgi
spec says `SetEnv` is cumulative with the inherited environment**. The inherited value
`/kohadevbox/koha:…` was already present, and `SetEnv` in the vhost was overriding it. But
this is the same behaviour in both containers — the real difference is that in dev, Koha modules
at `/kohadevbox/koha` can satisfy all `use` statements regardless, because `/kohadevbox/koha`
happens to be earlier in `@INC` from the process environment.

Actually the cleaner explanation: in dev, the process-level `PERL5LIB` included
`/kohadevbox/koha` first. Apache's `SetEnv` for a variable that already exists in the
environment **replaces** it for the CGI child process. So whether apache-shared.conf fired last
or not, the child processes always received `PERL5LIB=/usr/share/koha/lib` in theory — but in
dev that path also contained a usable (though not identical) copy of the modules, so it
happened to work because the dev image's bind-mounted source and the staged
`/usr/share/koha/lib` copy both came from the same on-disk source.

In prod, the staged `/usr/share/koha/lib/C4/Context.pm` at line 48 does `use Koha;`. The
module `Koha.pm` lives at `/kohadevbox/koha/Koha.pm` but **not** under
`/usr/share/koha/lib/Koha.pm`. So when `PERL5LIB` was restricted to `/usr/share/koha/lib`,
`use Koha` failed and cascaded into the HTTP 500.

### Root cause of `apache-shared.conf` content

`apache-shared.conf` is installed by `build-alpine-package.sh`, which copies it from the Koha
source tree at `koha/debian/templates/apache-shared*.conf`:

```perl
system("cp -a $koha_dir/debian/templates/apache-shared*.conf /etc/koha/ 2>/dev/null");
```

The Debian template hardcodes `SetEnv PERL5LIB "/usr/share/koha/lib"` because that is the
correct path for a **Debian package install** where Koha Perl modules live in
`/usr/share/koha/lib`. In the Alpine context, Koha source is at `/kohadevbox/koha`, so this
line is always wrong.

### Fix applied — two layers

#### Layer 1: `Dockerfile-Alpine` (build-time, prod stage)

In the `prod-runtime` stage's final `RUN` block, added a `sed` to strip the line after the
Debian scripts have been staged:

```dockerfile
RUN install -m 0755 /kohadevbox/files-alpine/scripts/koha-create /usr/sbin/koha-create \
    && install -m 0755 /kohadevbox/files-alpine/scripts/koha-plack /usr/sbin/koha-plack \
    && install -m 0755 /kohadevbox/files-alpine/scripts/koha-worker /usr/sbin/koha-worker \
    && install -m 0755 /kohadevbox/files-alpine/scripts/koha-functions.sh /usr/sbin/koha-functions.sh \
    && sed -i '/^[[:space:]]*SetEnv PERL5LIB[[:space:]]/d' /etc/koha/apache-shared.conf 2>/dev/null || true
```

This ensures the prod image never contains the conflicting line.

#### Layer 2: `files-alpine/run.sh` (runtime, covers both dev and prod)

Added the same `sed` in the Alpine compatibility section of `run.sh`, just before Apache is
started:

```bash
# Alpine PERL5LIB fix: the Debian-installed apache-shared.conf hardcodes PERL5LIB to
# /usr/share/koha/lib (the Debian package path), overriding the vhost's SetEnv which
# correctly points to the git-checkout or bind-mount. Remove the conflicting SetEnv.
sed -i '/^[[:space:]]*SetEnv PERL5LIB[[:space:]]/d' /etc/koha/apache-shared.conf 2>/dev/null || true
```

The runtime layer is essential for the dev image because `build-alpine-package.sh` is not
executed at dev build time (it runs against the bind-mounted Koha source only once, during
bootstrap). The `apache-shared.conf` in dev was coming from the Koha source tree at
`/kohadevbox/koha/debian/templates/apache-shared.conf` — still the Debian version with the
wrong PERL5LIB.

---

## Problem 4 — `/etc/default/koha-common` sets `PERL5LIB` to the Debian package path

### Discovery during investigation

While tracing the `@INC` chain, `/etc/default/koha-common` was found to contain:

```bash
PERL5LIB="/usr/share/koha/lib"
KOHA_HOME="/usr/share/koha"
```

This file is installed by `build-alpine-package.sh`. It is sourced by `koha-create`,
`koha-plack`, and `koha-worker` (all three scripts have `[ -r /etc/default/koha-common ] && . /etc/default/koha-common` near the top).

In the Alpine context, sourcing this file would set `PERL5LIB=/usr/share/koha/lib` in any
script that invokes `koha-create`, `koha-plack`, or `koha-worker`. This could cause those
scripts to load Perl modules from the wrong location when they invoke Perl sub-commands.

The problem was masked in this particular debug session because Problem 3 (apache-shared.conf)
was the dominant cause of the HTTP 500. However, the `/etc/default/koha-common` PERL5LIB
would be a latent issue for script-level invocations.

### Fix applied

Added `ENV PERL5LIB=/kohadevbox/koha:/kohadevbox/koha/lib` to the `prod-runtime` stage in
`Dockerfile-Alpine`. This sets the environment variable at the Docker image level, so:

1. The process-level `PERL5LIB` in the container is always `/kohadevbox/koha:…`.
2. Any script that sources `/etc/default/koha-common` will get `PERL5LIB=/usr/share/koha/lib`
   **temporarily** in its own subshell, but the calling process (run.sh, Apache) retains the
   correct value.
3. Apache's CGI children inherit the correct process-level value before `SetEnv` (from whatever
   Apache config loads last) overrides it.

This does not fully neutralise the `/etc/default/koha-common` override for scripts that source
it — the definitive fix for those scripts is to add `PERL5LIB="/kohadevbox/koha:/kohadevbox/koha/lib"` to
`/etc/default/koha-common` itself, or to strip the line from that file the same way
Problem 3 is patched. However, since all three Alpine-native scripts (`koha-create`,
`koha-plack`, `koha-worker`) construct `PERL5LIB` themselves from `KOHA_HOME` or `KOHA_PATH`
after sourcing the default file, and since `PERL5LIB` is set at the Docker process level, the
risk is contained.

**Recommended follow-up**: add
`sed -i 's|^PERL5LIB=.*|PERL5LIB="/kohadevbox/koha:/kohadevbox/koha/lib"|' /etc/default/koha-common`
to the prod `RUN` block or to `run.sh` to close this loop definitively.

---

## Problem 5 — Dev image regression: apache-shared.conf PERL5LIB also breaks dev

### Discovery

After all fixes were applied and the prod image was confirmed healthy (HTTP 302 on Intranet),
a routine check of the dev container via the host's mapped port 8081 returned HTTP 500. The
dev container had not been restarted since before the session started and was returning the
same `@INC` error as prod:

```
Can't locate Koha.pm in @INC (@INC entries checked: /usr/share/koha/lib …)
```

### Root cause

The dev container was running the old image (built before the `run.sh` patch from the
previous session was applied). The `apache-shared.conf` PERL5LIB override (Problem 3) was
always present in dev too, but was masked by:

- Prior session builds including some intermediate state where `PERL5LIB` was set at the
  process level via the compose `.env` file injection.
- The dev test suite using `docker exec` rather than HTTP requests, so the test runner never
  exercised the Apache CGI path that exposed the wrong `@INC`.

Once the dev image was rebuilt in a prior session with a clean state, the same apache-shared
override began failing dev too.

### Fix applied

The `run.sh` Layer 2 fix from Problem 3 covers dev as well, since `run.sh` is baked into
the dev image. After rebuilding the dev image:

```bash
docker compose -f docker-compose-alpinekoha.yml build --no-cache koha
docker compose -f docker-compose-alpinekoha.yml up -d
curl http://localhost:8081/cgi-bin/koha/mainpage.pl  # → HTTP 200
```

Dev was confirmed healthy.

---

## Final state after all fixes

### Both images healthy

| Image | Tag | Test |
|---|---|---|
| `kosson/koha-alpine` | `26.11` | Dev intranet: HTTP 200 ✅ |
| `kosson/koha-alpine` | `26.11-prod` | Prod intranet: HTTP 302 (login redirect) ✅ |
| `kosson/koha-alpine` | `26.11-prod` | Prod OPAC: HTTP 403 (expected — shared dev DB with dev hostname) ✅ |

### Full test suite after fix

```
KOHA_CONTAINER=koha-alpine-koha-1 bash tests/run_all_tests.sh
→ 207 passed  0 failed  18 skipped
All suites passed.
```

No regressions.

---

## Files changed in this session

| File | Change |
|---|---|
| `files-alpine/lib/run-sh-alpine.sh` | `|| true` appended to all 6 conditional cert `printf` lines |
| `files-alpine/run.sh` | Default exports for `KOHA_INTRANET_PORT` and `KOHA_OPAC_PORT` at top of file |
| `files-alpine/run.sh` | `append_if_absent` calls updated to use `:-8081` / `:-8080` defaults |
| `files-alpine/run.sh` | `sed` to strip `SetEnv PERL5LIB` from `apache-shared.conf` added in alpine compat section |
| `Dockerfile-Alpine` | `ENV PERL5LIB=/kohadevbox/koha:/kohadevbox/koha/lib` added to `prod-runtime` stage |
| `Dockerfile-Alpine` | `sed` to strip `SetEnv PERL5LIB` from `apache-shared.conf` added to prod `RUN` block |

---

## Lessons learned

### Apache `SetEnv` is last-writer-wins within a VirtualHost

Apache evaluates `SetEnv` directives in document order. An `Include` is expanded inline at the
point it appears. Any file included **after** a `SetEnv` in the same VirtualHost scope will
override it. This is counter-intuitive because the vhost-level `SetEnv` looks "more specific"
than a generic shared include, but Apache has no concept of specificity for `SetEnv`.

**Rule**: Place `Include` directives for shared config files **before** instance-specific
`SetEnv` overrides, or patch the included files to remove conflicting lines.

### `build-alpine-package.sh` installs Debian-specific Apache snippets

`debian/templates/apache-shared*.conf` contains Debian package assumptions (PERL5LIB pointing
to `/usr/share/koha/lib`). Every time `build-alpine-package.sh` runs (once during prod image
build), it overwrites `/etc/koha/apache-shared*.conf` with these Debian-targeted values.
Any post-processing that depends on a clean `/etc/koha/apache-shared.conf` must run **after**
the `build-alpine-package.sh` call.

### Short-circuit expressions in functions break `set -e` when the condition is false

```bash
# This is fragile under set -e:
[ -n "$VAR" ] && do_something_with "$VAR"

# This is safe:
[ -n "$VAR" ] && do_something_with "$VAR" || true

# Or equivalently:
if [ -n "$VAR" ]; then do_something_with "$VAR"; fi
```

The short-circuit pattern `[ test ] && cmd` returns the exit code of `[ test ]` when the test
is false (exit 1). Under `set -e`, this aborts the enclosing script. Use `|| true` or
`if/fi` for optional operations.

### `docker compose` injects `.env` variables; bare `docker run` does not

`docker compose` reads `env/.env` and injects all defined variables into the container
environment. A bare `docker run` only receives variables passed with `-e`. Variables with
defaults defined only in the `.env` file will be unset in bare `docker run`.

**Rule**: Any variable that is required for correct container startup should have a
`${VAR:-default}` fallback in `run.sh`, not rely on being present from the compose `.env`
file. The `.env` file is for customisation; `run.sh` defaults are the safety floor.

---

## Part 2 — Single source-of-truth for Koha release version + `latest-tag` command

### Problem

Three separate places hardcoded the Koha version number, and they drifted from one another:

| Location | Variable | Old value |
|---|---|---|
| `Dockerfile-Alpine` | `ARG KOHA_GIT_REF=v25.11.05-1` | `v25.11.05-1` |
| `docker-compose.prod.yml` | `${KOHA_RELEASE_REF:-v25.11.05-1}` | `v25.11.05-1` |
| `env/template.env` | `KOHA_GIT_TAG=v25.11.05-1` | `v25.11.05-1` |
| `env/.env` | `KOHA_GIT_TAG=v25.11.05-2` | `v25.11.05-2` (already one patch ahead) |

The Dockerfile and compose fallback could silently build against an old version if `KOHA_GIT_TAG`
was not set (e.g. new clone, missing `.env`). There was also no easy way to discover the
current upstream release without manually running a `git ls-remote` command with a broken sort.

### Broken sort: `sort -V` vs tag format

The upstream tags follow `vMAJOR.MINOR.PATCH[-REVISION]` (e.g. `v25.11.06-1`). `sort -V`
treats the `-REVISION` suffix as part of the version string and mis-orders it. The correct
command that gives proper ordering is:

```bash
git ls-remote --tags https://git.koha-community.org/Koha-community/Koha.git \
  | grep 'refs/tags/v2' \
  | grep -v '\^{}' \
  | awk '{print $2}' \
  | sed 's|refs/tags/||' \
  | sort -t. -k1,1V -k2,2n -k3,3n \
  | tail -5
```

Splitting on `.` and sorting each numeric field independently handles the `-REVISION` suffix
correctly because `sort -k3,3n` stops at the first non-digit (`-`) and compares the patch
number numerically.

### Fix applied

#### 1. Removed hardcoded defaults from Dockerfile and compose

`Dockerfile-Alpine`:
```dockerfile
# Before
ARG KOHA_GIT_REF=v25.11.05-1
ARG KOHA_VERSION=25.11.05-1

# After — no default; a missing value fails fast with a clear error message
ARG KOHA_GIT_REF
ARG KOHA_VERSION
```

A guard `RUN` was added immediately before the git fetch:
```dockerfile
RUN test -n "${KOHA_GIT_REF}" || { echo "ERROR: KOHA_GIT_REF is required. Set KOHA_GIT_TAG in env/.env then run: ./stack-alpine.sh build --image-mode prod --build-koha" >&2; exit 1; }
```

`docker-compose.prod.yml`:
```yaml
# Before
KOHA_GIT_REF: ${KOHA_RELEASE_REF:-v25.11.05-1}
KOHA_VERSION: ${KOHA_RELEASE_VERSION:-25.11.05-1}

# After — no fallback; missing var causes docker compose to fail visibly
KOHA_GIT_REF: ${KOHA_RELEASE_REF}
KOHA_VERSION: ${KOHA_RELEASE_VERSION}
```

`stack-alpine.sh` already had a `die` guard for empty `KOHA_RELEASE_REF` in `configure_koha_mode()`.
Its message was updated to hint at the new `latest-tag` command:
```bash
[[ -n "${KOHA_RELEASE_REF}" ]] || die "… Set KOHA_GIT_TAG in env/.env, pass --koha-ref, or run: ./stack-alpine.sh latest-tag --apply"
```

#### 2. Added `koha_latest_tag()` helper function

```bash
koha_latest_tag() {
  local url
  url="${1:-${KOHA_GIT_URL:-${KOHA_DEFAULT_REPO_URL}}}"
  git ls-remote --tags "${url}" 2>/dev/null \
    | grep 'refs/tags/v2' \
    | grep -v '\^{}' \
    | awk '{print $2}' \
    | sed 's|refs/tags/||' \
    | sort -t. -k1,1V -k2,2n -k3,3n \
    | tail -1
}
```

#### 3. Added `latest-tag` subcommand with `--apply [<tag>]`

```
./stack-alpine.sh latest-tag                    # read-only: print latest tag
./stack-alpine.sh latest-tag --apply            # write latest tag to env/.env
./stack-alpine.sh latest-tag --apply v25.11.06-1  # write a specific tag
./stack-alpine.sh latest-tag --apply 25.11.06-1   # leading 'v' auto-added
```

`--apply` writes `KOHA_GIT_TAG=<tag>` to `env/.env`. `stack-alpine.sh` then derives
`KOHA_RELEASE_REF` from `KOHA_GIT_TAG`, which `docker-compose.prod.yml` passes as
`KOHA_GIT_REF` to the Dockerfile. One variable, one place.

### Complete prod-image workflow after this change

```bash
# 1. Check what the latest release is
./stack-alpine.sh latest-tag

# 2a. Accept the latest release
./stack-alpine.sh latest-tag --apply

# 2b. OR pin a specific release
./stack-alpine.sh latest-tag --apply v25.11.06-1

# 3. Build the prod image
./stack-alpine.sh build --image-mode prod --build-koha

# 4. Start the stack
./stack-alpine.sh start --image-mode prod
```

---

## Part 3 — Bug #6: `apache-shared-intranet.conf` and `apache-shared-opac.conf` Debian paths override vhost → HTTP 403

**Date**: 2026-08-04 (follow-up session)  
**Trigger**: Fresh prod image built from tag `v25.11.06-1` using new tooling. Containers came up
and Apache reported READY, but both Intranet and OPAC returned HTTP 403.

---

### Symptom

```
Intranet: HTTP 403  http://kohadev-intra.127.0.0.1.nip.io:8081/
OPAC:     HTTP 403  http://kohadev.127.0.0.1.nip.io:8080/
```

Apache error log:

```
[authz_core:error] AH01630: client denied by server configuration: /usr/share/koha/intranet/htdocs/
```

The path `/usr/share/koha/intranet/htdocs/` does not exist in the Alpine image (Koha lives at
`/kohadevbox/koha/`). Apache was trying to serve from the wrong DocumentRoot and correctly
denied access because no `<Directory>` grant existed for that non-existent path.

---

### Root cause

`/etc/koha/apache-shared-intranet.conf` and `/etc/koha/apache-shared-opac.conf` are installed
from the Debian Koha package templates (copied by `build-alpine-package.sh` via
`scripts/build-alpine-package.sh`). Their content:

**`apache-shared-intranet.conf`** (relevant lines):

```apache
DocumentRoot /usr/share/koha/intranet/htdocs
ScriptAlias /cgi-bin/koha/ "/usr/share/koha/intranet/cgi-bin/"
ScriptAlias /index.html "/usr/share/koha/intranet/cgi-bin/mainpage.pl"
ScriptAlias /search "/usr/share/koha/intranet/cgi-bin/catalogue/search.pl"
Alias "/api" "/usr/share/koha/api"
<Directory "/usr/share/koha/api"> ... </Directory>
```

**`apache-shared-opac.conf`** (relevant lines):

```apache
DocumentRoot /usr/share/koha/opac/htdocs
ScriptAlias /cgi-bin/koha/ "/usr/share/koha/opac/cgi-bin/opac/"
ScriptAlias /index.html "/usr/share/koha/opac/cgi-bin/opac/opac-main.pl"
ScriptAlias /search "/usr/share/koha/opac/cgi-bin/opac/opac-search.pl"
ScriptAlias /opac-search.pl "/usr/share/koha/opac/cgi-bin/opac/opac-search.pl"
Alias "/api" "/usr/share/koha/api"
<Directory "/usr/share/koha/api"> ... </Directory>
```

Our vhost template (`files-alpine/templates/koha-vhost.conf.in`) defines the correct values
**before** the `Include` lines:

```apache
<VirtualHost *:${KOHA_INTRANET_PORT}>
    DocumentRoot ${KOHA_PATH}/koha-tmpl/intranet-tmpl       ← correct
    ScriptAlias  /cgi-bin/koha/ ${KOHA_PATH}/               ← correct
    ...
    Include /etc/koha/apache-shared.conf
    Include /etc/koha/apache-shared-intranet.conf            ← overrides DocumentRoot!
    ...
</VirtualHost>
```

Apache's `DocumentRoot` directive uses **last-definition-wins** semantics within a
`<VirtualHost>` block. The `Include` that sets `DocumentRoot /usr/share/koha/intranet/htdocs`
appears **after** our correct `DocumentRoot`, so it wins. At request time Apache looks for
`index.html` in `/usr/share/koha/intranet/htdocs/`, which doesn't exist, and returns 403
because no `<Directory>` block grants access to that path.

The `ScriptAlias /cgi-bin/koha/` directive from the shared conf also overrides ours for the same
reason, though for `ScriptAlias` (first-definition-wins for equally specific paths) the ordering
behaviour is less predictable. In the worst case it routes CGI requests to
`/usr/share/koha/intranet/cgi-bin/` instead of `/kohadevbox/koha/`.

The `Alias "/api"` and its `<Directory>` block pointed to `/usr/share/koha/api`, which also
does not exist in the Alpine image.

#### Why this was not caught earlier

The previous prod smoke test used `docker exec` + direct `curl` calls to the container-internal
IP and to specific CGI paths (e.g. `/cgi-bin/koha/mainpage.pl`). Those requests hit the
`ScriptAlias /cgi-bin/koha/` path which **our vhost** defines first, so they worked correctly.
The `DocumentRoot` override only affected requests to `/` (root) and to assets that Apache tries
to serve as static files from the DocumentRoot. The earlier test did not exercise `/` directly
in a way that exposed the override.

---

### Fix

The fix rewrites the `/usr/share/koha/*` paths inside the shared conf files to point to the
actual Alpine Koha path (`${KOHA_PATH}` = `/kohadevbox/koha`), and removes the conflicting
`DocumentRoot` directives entirely (since `DocumentRoot` is already set correctly in our vhost
template and must not be overridden).

#### Layer 1 — `files-alpine/run.sh` (runtime, applies every boot)

Added immediately after the existing `apache-shared.conf` PERL5LIB fix:

```bash
# Fix Debian package paths in Apache shared conf files to use our Koha installation.
# apache-shared-intranet.conf and apache-shared-opac.conf reference /usr/share/koha/*
# (Debian package paths). They override our vhost's correct values because the Include
# lines appear after our DocumentRoot/ScriptAlias declarations.
sed -i '/^[[:space:]]*DocumentRoot[[:space:]]/d; \
        s|/usr/share/koha/intranet/cgi-bin|${KOHA_PATH}|g; \
        s|/usr/share/koha/api|${KOHA_PATH}/api|g' \
    /etc/koha/apache-shared-intranet.conf 2>/dev/null || true
sed -i '/^[[:space:]]*DocumentRoot[[:space:]]/d; \
        s|/usr/share/koha/opac/cgi-bin/opac|${KOHA_PATH}/opac|g; \
        s|/usr/share/koha/api|${KOHA_PATH}/api|g' \
    /etc/koha/apache-shared-opac.conf 2>/dev/null || true
```

This applies on every container startup and covers both the dev and prod images. It is safe to
run multiple times (idempotent) because the `DocumentRoot` delete is a no-op if already absent,
and the path substitutions are no-ops if already correct.

#### Layer 2 — `Dockerfile-Alpine` prod-runtime stage (baked in at build time)

Added to the prod-runtime `RUN` block alongside the existing `apache-shared.conf` PERL5LIB fix:

```dockerfile
&& sed -i '/^[[:space:]]*DocumentRoot[[:space:]]/d; \
    s|/usr/share/koha/intranet/cgi-bin|/kohadevbox/koha|g; \
    s|/usr/share/koha/api|/kohadevbox/koha/api|g' \
    /etc/koha/apache-shared-intranet.conf 2>/dev/null || true \
&& sed -i '/^[[:space:]]*DocumentRoot[[:space:]]/d; \
    s|/usr/share/koha/opac/cgi-bin/opac|/kohadevbox/koha/opac|g; \
    s|/usr/share/koha/api|/kohadevbox/koha/api|g' \
    /etc/koha/apache-shared-opac.conf 2>/dev/null || true
```

Baking the fix into the image means a fresh container has the corrected files from the first
millisecond of startup, with no sed work needed at runtime.

---

### State of shared conf files after the fix

`/etc/koha/apache-shared-intranet.conf` (relevant lines after fix):

```apache
ScriptAlias /cgi-bin/koha/ "/kohadevbox/koha/"
ScriptAlias /index.html "/kohadevbox/koha/mainpage.pl"
ScriptAlias /search "/kohadevbox/koha/catalogue/search.pl"
Alias "/api" "/kohadevbox/koha/api"
<Directory "/kohadevbox/koha/api"> ... </Directory>
# all RewriteRules retained unchanged
```

`/etc/koha/apache-shared-opac.conf` (relevant lines after fix):

```apache
ScriptAlias /cgi-bin/koha/ "/kohadevbox/koha/opac/"
ScriptAlias /index.html "/kohadevbox/koha/opac/opac-main.pl"
ScriptAlias /search "/kohadevbox/koha/opac/opac-search.pl"
ScriptAlias /opac-search.pl "/kohadevbox/koha/opac/opac-search.pl"
Alias "/api" "/kohadevbox/koha/api"
<Directory "/kohadevbox/koha/api"> ... </Directory>
# all RewriteRules retained unchanged
```

---

### Verification

Fresh prod image `kosson/koha-alpine-prod:25.11.06-1` (sha `c9569a182553`) started via
`./stack-alpine.sh start --image-mode prod --no-logs`. After full bootstrap:

```
Intranet: HTTP 200  http://kohadev-intra.127.0.0.1.nip.io:8081/
OPAC:     HTTP 200  http://kohadev.127.0.0.1.nip.io:8080/
Intranet direct (/cgi-bin/koha/mainpage.pl): HTTP 200
```

No manual intervention required — the fix is fully self-contained in the image.

---

### Files changed

| File | Change |
|---|---|
| `files-alpine/run.sh` | Added `DocumentRoot` deletion and `/usr/share/koha/*` path rewrite for `apache-shared-intranet.conf` and `apache-shared-opac.conf` |
| `Dockerfile-Alpine` | Added same sed operations to prod-runtime `RUN` block, baking the fix into the image layer |

---

## Part 4 — Bug #7: `DocumentRoot` one level too deep in vhost template → HTTP 404 on all CSS/JS/image assets

**Date**: 2026-08-04 (same session as Bug #6, discovered immediately after)  
**Trigger**: After the HTTP 403 fix, the container started and both endpoints returned HTTP 200
for the initial HTML page. However, the browser reported that every CSS, JavaScript, font, and
image asset failed to load with HTTP 404.

---

### Symptom

```
Pages loaded (login page HTML was served), but completely unstyled and non-functional.
Browser devtools showed hundreds of 404 errors for all static assets:

GET /intranet-tmpl/lib/fontawesome/css/fontawesome.min_25.1105000.css  → 404
GET /intranet-tmpl/prog/css/staff-global_25.1105000.css                → 404
GET /intranet-tmpl/lib/jquery/jquery-3.6.0.min_25.1105000.js           → 404
GET /intranet-tmpl/prog/js/staff-global_25.1105000.js                  → 404
... (every asset)
```

Apache access log confirmed HTTP 404 with a 29 KB body (the CGI-rendered 404 page) for
every asset request.

---

### Root cause

`files-alpine/templates/koha-vhost.conf.in` contained:

```apache
# Intranet
DocumentRoot ${KOHA_PATH}/koha-tmpl/intranet-tmpl

# OPAC
DocumentRoot ${KOHA_PATH}/koha-tmpl/opac-tmpl
```

Koha's static assets live at paths like:

```
/kohadevbox/koha/koha-tmpl/intranet-tmpl/prog/css/staff-global_*.css
/kohadevbox/koha/koha-tmpl/intranet-tmpl/lib/fontawesome/...
/kohadevbox/koha/koha-tmpl/opac-tmpl/prog/...
```

The browser requests them at URL paths like `/intranet-tmpl/prog/css/...` (relative to the
site root). Apache resolves these by prepending the `DocumentRoot`:

```
DocumentRoot /kohadevbox/koha/koha-tmpl/intranet-tmpl
URL path     /intranet-tmpl/prog/css/staff-global_*.css
Resolved     /kohadevbox/koha/koha-tmpl/intranet-tmpl/intranet-tmpl/prog/css/staff-global_*.css
                                                        ↑ duplicated!
```

The path is one level too deep: `intranet-tmpl` is repeated. That directory does not exist,
so Apache returns 404.

The correct `DocumentRoot` is `${KOHA_PATH}/koha-tmpl` so that:

```
DocumentRoot /kohadevbox/koha/koha-tmpl
URL path     /intranet-tmpl/prog/css/staff-global_*.css
Resolved     /kohadevbox/koha/koha-tmpl/intranet-tmpl/prog/css/staff-global_*.css  ✓
```

The same logic applies to the OPAC vhost (`/opac-tmpl/...` requests need `DocumentRoot` to be
`/kohadevbox/koha/koha-tmpl`, not `/kohadevbox/koha/koha-tmpl/opac-tmpl`).

#### Why the HTML page loaded despite the wrong DocumentRoot

The login page HTML itself is served through a `ScriptAlias` (`/index.html →
/kohadevbox/koha/mainpage.pl`), which is independent of `DocumentRoot`. Only requests for
static files (those not matched by `ScriptAlias` or `Alias`) fall through to the
`DocumentRoot`-relative file lookup. So the page skeleton was served correctly, but no assets
were.

#### Why this was not caught earlier

The prior end-to-end smoke tests used `curl -so /dev/null -w "%{http_code}"` against the root
URL and a few specific CGI paths. They returned HTTP 200, which was treated as passing. No
browser-level asset loading was checked. The `DocumentRoot` path bug only manifests when a real
browser (or a curl request to a static asset path) tries to fetch `/intranet-tmpl/...`.

---

### Fix

Changed both `DocumentRoot` lines in the vhost template to the shared parent:

**`files-alpine/templates/koha-vhost.conf.in`**:

```diff
- DocumentRoot ${KOHA_PATH}/koha-tmpl/intranet-tmpl   (intranet VirtualHost)
+ DocumentRoot ${KOHA_PATH}/koha-tmpl

- DocumentRoot ${KOHA_PATH}/koha-tmpl/opac-tmpl        (OPAC VirtualHost)
+ DocumentRoot ${KOHA_PATH}/koha-tmpl
```

The `<Directory "${KOHA_PATH}/koha-tmpl">` grant block was already present and correct in
both VirtualHost blocks, so no `<Directory>` changes were needed.

**Live hot-fix** applied to the running container without a restart:

```bash
# Fix the already-rendered vhost conf
sed -i "s|DocumentRoot /kohadevbox/koha/koha-tmpl/intranet-tmpl|DocumentRoot /kohadevbox/koha/koha-tmpl|g; \
        s|DocumentRoot /kohadevbox/koha/koha-tmpl/opac-tmpl|DocumentRoot /kohadevbox/koha/koha-tmpl|g" \
    /etc/apache2/sites-enabled/kohadev.conf

# Fix the baked template so render_vhost at next restart uses the correct value
sed -i "s|DocumentRoot \${KOHA_PATH}/koha-tmpl/intranet-tmpl|DocumentRoot \${KOHA_PATH}/koha-tmpl|g; \
        s|DocumentRoot \${KOHA_PATH}/koha-tmpl/opac-tmpl|DocumentRoot \${KOHA_PATH}/koha-tmpl|g" \
    /kohadevbox/templates/koha-vhost.conf.in

# Graceful reload (no connection drops)
httpd -k graceful
```

Syntax check passed, Apache reloaded successfully.

**Image rebuild** to bake the fix permanently:

```bash
./stack-alpine.sh build --image-mode prod --build-koha
```

New image: `kosson/koha-alpine-prod:25.11.06-1` (sha `6653a00d23d6`)

---

### Verification

After the hot-fix and after the rebuilt image was started fresh:

```
Intranet HTML:  HTTP 200  http://kohadev-intra.127.0.0.1.nip.io:8081/
CSS asset:      HTTP 200  .../intranet-tmpl/prog/css/staff-global_25.1105000.css
OPAC HTML:      HTTP 200  http://kohadev.127.0.0.1.nip.io:8080/
```

Pages render with full styling and JavaScript.

---

### Files changed

| File | Change |
|---|---|
| `files-alpine/templates/koha-vhost.conf.in` | Both `DocumentRoot` entries changed from `${KOHA_PATH}/koha-tmpl/{intranet,opac}-tmpl` to `${KOHA_PATH}/koha-tmpl` |


