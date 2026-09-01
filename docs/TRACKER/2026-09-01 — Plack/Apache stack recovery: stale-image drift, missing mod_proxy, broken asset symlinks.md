# 2026-09-01 — Plack/Apache stack recovery: stale-image drift, missing mod_proxy, broken asset symlinks

## Context

Entering this session, `files-alpine/run.sh` on the `phase` branch had been reduced
(across commits `t01`–`t15`) to a 161-line script whose final act was:

```bash
exec su kohadev-koha -s /bin/sh -c "... exec plackup --port 5000 --host 0.0.0.0 --env production app.psgi"
```

The user reported being "stuck at making Plack work" and asked for a full audit:
run the stack, identify every dysfunctional piece, and build a test harness.
This tracker covers everything found and fixed across the whole session, in the
order it was discovered, because later findings only make sense with the earlier
ones as context.

## Round 0 — the investigation before any code changed

Before touching anything, the actual `docker-compose-alpinekoha.yml` stack was
brought up and inspected directly (containers, `docker exec`, log tails) rather
than reasoning from source alone. This surfaced the first and most important
finding.

### Finding 1 — the running container was executing a stale image

`docker inspect koha-alpine` showed:

```
Entrypoint: null
Cmd: ["/bin/bash","/kohadevbox/run.sh"]
```

But `Dockerfile-Alpine` (current, on `phase`) declares:

```dockerfile
ENTRYPOINT ["/usr/local/bin/run.sh"]
```

`/kohadevbox/run.sh` inside the running container was a **757-line file**, dated
mid-August, completely different from the 161-line `files-alpine/run.sh` on disk.
`docker compose up -d` alone reuses a cached image and never re-executes the
`Dockerfile`'s `COPY`/`RUN` steps, so every edit made to `files-alpine/run.sh` in
recent sessions had **zero effect** on the running container — the container was
always running old, pre-simplification code. This is the root explanation for
the user's "stuck" experience: they were editing a file that was never actually
being executed.

The 757-line file was extracted for reference before it could be lost
(`docker exec koha-alpine cat /kohadevbox/run.sh`, saved to `/tmp/koha-alpine-stale-run.sh`),
along with its companion library `files-alpine/lib/run-sh-alpine.sh`
(`/tmp/koha-alpine-stale-lib.sh`, 350 lines). Git archaeology
(`git log --all -p -S "run_service_watchdog()"`) showed this fuller
implementation existed as recently as commit `67c9691` ("Alpine middle cut done
- no more shims") and was already reduced to a 24-line stub by `89e9fc9` ("t 10")
— i.e. the regression happened early and was carried forward silently for many
commits, masked by the fact the running container kept using the old, larger,
better-working code underneath.

**Fix**: `docker compose build koha` (not just `up -d`) to force a real rebuild;
this alone made the container start executing the current `files-alpine/run.sh`
for the first time in the session.

**Lesson recorded**: always `docker compose build koha` after any
`Dockerfile-Alpine` or `files-alpine/run.sh` change on this repo — `up -d` silently
keeps old baked-in behavior.

### Finding 2 — the Plack architecture was fundamentally broken, independent of the stale image

Even accounting for the stale image, the *current* `run.sh`'s Plack invocation
could never have worked, for two independent reasons:

1. **Nothing routed traffic to port 5000.** `docker-compose-alpinekoha.yml` only
   publishes/labels ports 8080 (OPAC) and 8081 (staff), matching
   `env/.env`'s `KOHA_OPAC_PORT=8080` / `KOHA_INTRANET_PORT=8081`. Port 5000 was
   never exposed to the host, never referenced by Traefik labels, nothing.
2. **`koha/app.psgi` cannot load in this Koha checkout.** The root-level
   `app.psgi` is a newer, Mojolicious-based dual-port app
   (`Koha::App::Opac` / `Koha::App::Intranet`, differentiated by
   `SERVER_PORT` via `$ENV{KOHA_OPAC_PORT}` / `$ENV{KOHA_INTRANET_PORT}`).
   Confirmed via `find` that `Koha::App::Opac` and `Koha::App::Intranet` **do
   not exist** anywhere in this Koha checkout (branch `main`, commit `8870a45`
   "Bug 30144: dbic"). `plackup ... app.psgi` would fail to load the
   application even if reachable.

The Dockerfile's own dependency list is a strong hint at the intended design:
it installs `CGI::Compile`, `CGI::Emulate::PSGI`, `Starman`, `Starlet` — all of
these exist specifically to bridge classic CGI scripts into a Plack/PSGI
server. That points at `koha/debian/templates/plack.psgi` (a
`Plack::App::CGIBin`-based app that wraps the real `intranet`/`opac` CGI
scripts) as the intended target, not the Mojolicious `app.psgi`. This is also
exactly what real Koha packages (and `koha-testing-docker`) use in production:
Apache + `mod_proxy_http` in front of a Starman process listening on a unix
socket, running `plack.psgi`, per
`koha/debian/templates/apache-shared-{intranet,opac}-plack.conf`.

Further confirming this: `files-alpine/scripts/koha-plack` (the Alpine-native
rewrite of Koha's own `debian/scripts/koha-plack`) had **also** been pointed at
the broken `app.psgi`/port 5000 combination — so the bug wasn't confined to
`run.sh`; every current attempt at "Plack" in this repo used the same
non-working approach.

### Finding 3 — a fuller, working implementation already existed and was abandoned

`files-alpine/lib/run-sh-alpine.sh` at commit `67c9691` (350 lines, matching the
extracted stale-image copy) already implemented the correct architecture:
`bootstrap_koha_instance()` (using a native Alpine `koha-create` port),
`render_vhost()`, `enable_instance_services()` (`koha-plack --enable`),
`start_koha_service()` (`koha-plack --start` + `koha-worker --start`),
`start_apache_service()` / `stop_apache_service()` (`httpd -k start/stop`), and
`run_service_watchdog()` (a proper SIGTERM-aware crash-recovery loop, replacing
an earlier blocking `sleep infinity`). There is also an existing, fairly
extensive test suite already committed under `koha-alpine/tests/` (19 scripts:
`test_phase2_build_staging_static.sh`, `test_phase4_koha_plack_rewrite.sh`,
`test_phase5_supervision.sh`, etc.) and design docs under
`docs/Alpine-migration/`. None of this had been deleted from git — it had simply
stopped being used by `run.sh`, which was rewritten from scratch into the
161-line ad-hoc script in later commits.

### Decision point

Given the size of the regression, the user was asked directly how to proceed
(via a clarifying question) rather than unilaterally reverting several commits'
worth of work. Chosen answers:
- **Restore the proven architecture** (not just patch the minimal script).
- **Build a new consolidated test harness** rather than resurrecting/running
  the existing 19-script `tests/` suite.

## Round 1 fixes (committed by the user afterwards as `t 16`)

1. **Restored `files-alpine/lib/run-sh-alpine.sh`** verbatim from the extracted
   350-line version (self-contained; none of the functions used depend on the
   external `misc4dev` scripts that are no longer vendored into the Alpine
   image, so restoring it was low-risk).

2. **Rewrote `files-alpine/scripts/koha-plack`** (bumped to "v11" in its header
   comment) to stop targeting `app.psgi`/port 5000 and instead run Starman
   against `koha/debian/templates/plack.psgi` (staged at `/etc/koha/plack.psgi`
   by the Dockerfile build) over a **unix socket**
   (`/var/run/koha/<instance>/plack.sock`), with `GIT_INSTALL=1` and
   `KOHA_HOME=$KOHA_PATH` exported so `plack.psgi`'s `Plack::App::CGIBin` roots
   resolve to the git-checkout layout (`$KOHA_PATH`, `$KOHA_PATH/opac`,
   `$KOHA_PATH/svc`) instead of a Debian package layout.

3. **Extended `files-alpine/templates/koha-vhost.conf.in`** (used by
   `render_vhost()`) with `ProxyPass`/`ProxyPassReverse` rules mirroring Koha's
   real `apache-shared-{intranet,opac}-plack.conf`, adapted for the git-install
   root layout: `/index.html`, `/cgi-bin/koha(/svc)`, `/api`, `/search` (OPAC)
   routed to the plack unix socket, registered **before** the
   `Include`-pulled `ScriptAlias` directives from the real Koha
   `apache-shared-{intranet,opac}.conf` files (see "directive ordering" below).
   Added `RewriteRule ^/$ /index.html [PT]` so bare `/` requests also reach the
   proxy instead of Apache's static `DocumentRoot` listing.

4. **Rewrote the tail of `files-alpine/run.sh`**: removed the broken
   `exec plackup ... app.psgi`; now sources the restored library, installs
   `koha-plack`/`koha-worker`/`koha-create`/`koha-functions.sh` into `/usr/sbin`
   at container start (the Dockerfile never did this — only `run.sh` itself
   gets copied to a fixed path), enables `mod_cgi`/`mod_proxy`/
   `mod_proxy_http`/`mod_rewrite` in `/etc/apache2/httpd.conf` (all
   commented-out by default on Alpine), adds
   `IncludeOptional /etc/apache2/sites-enabled/*.conf` to `httpd.conf` (**Alpine's
   `httpd.conf` has no such include by default** — without it the rendered
   vhost is silently ignored and Apache just serves its built-in "It works!"
   page on every port, which was observed and looked identical to "nothing is
   configured"), strips conflicting `DocumentRoot`/`ScriptAlias(index.html,
   search)`/`SetEnv PERL5LIB` lines from the real Koha
   `apache-shared*.conf` files (they hardcode Debian `/usr/share/koha/*`
   paths and would otherwise silently override the git-install vhost), fixes
   `SetEnv PERL5LIB` to include `/opt/koha-perl/lib/perl5` (CGI execution was
   failing with `Can't locate Modern/Perl.pm in @INC` without it — the vhost's
   own `SetEnv` didn't include the CPAN local::lib path), then calls
   `render_vhost` → `start_apache_service` → `enable_instance_services` →
   `start_koha_service` → `start_crond` → `run_service_watchdog` (the watchdog
   runs in the foreground as the container's supervising process, replacing
   the old bare `exec plackup`).

5. **Fixed a container-crashing bug** unrelated to Plack but blocking every
   restart: `create_superlibrarian.pl`'s idempotency check only tested
   `userid='admin'`, not `cardnumber='1'`. A database left over from an
   earlier experiment could have `cardnumber='1'` already taken by a
   differently-named user, which crashed `create_superlibrarian.pl`, and
   because `run.sh` has `set -e`, that took the **entire container** down on
   every single restart (observed: `Field 'cardnumber' must be unique. Value
   '1' is used already.` followed by container exit). Fixed by checking both
   `userid` and `cardnumber`, and treating a creation failure as a warning
   (log and continue) instead of a fatal error.

6. **Alpine packaging gap — the actual root blocker for Plack-via-Apache**:
   Alpine's `apache2` apk package ships **no `mod_proxy` at all** — not even a
   commented-out `LoadModule` line, no `.so` files present anywhere on disk.
   `apk search apache2-proxy` revealed it's a separate subpackage
   (`apache2-proxy-2.4.67-r0`, providing `proxy_module`, `proxy_http_module`,
   and about a dozen other `proxy_*` submodules). Added `apache2-proxy` to the
   `apk add` line in `Dockerfile-Alpine`. Without this, the
   `<IfModule mod_proxy_http.c>` blocks in the rendered vhost were silently
   skipped (Apache's `<IfModule>` doesn't error on a missing module, it just
   omits the block), so every proxied request returned Apache's own 404/plain
   static-file behavior instead of ever reaching Plack — this looked exactly
   like "Plack still isn't working" even after all the other fixes were in
   place, until `httpd -M | grep proxy` was checked directly and came back
   empty.

7. **Unix socket permissions**: `koha-plack`'s Starman process created
   `plack.sock` as `srwxr-xr-x`, owned by the instance user
   (`kohadev-koha`). Apache on Alpine runs as a **different** user (`apache`,
   not in the `kohadev-koha` group, no `AssignUserID`/suexec support like
   Debian has), so it got `(13)Permission denied: AH02454` connecting to the
   socket — surfaced to clients as `503 Service Unavailable`. Fixed with
   `chmod 777 "$SOCKET"` in `koha-plack --start`, right after confirming the
   process is up.

8. **Bind-mounted `files-alpine/{lib,scripts,templates}`** in
   `docker-compose-alpinekoha.yml` (previously only `run.sh` itself was
   bind-mounted), so these newly-restored/rewritten files can be live-edited
   without a full image rebuild, matching the existing `run.sh` workflow.

### Verification (round 1)

Built a new test harness, `test-plack-stack.sh` (superseding the stale
assumptions in `test-endpoints.sh`, which still assumed pure Apache/mod_cgi
with no Plack at all). Checks, in order: image/container freshness (guards
against finding 1 recurring — compares the running container's `run.sh` md5
against the host file), container health, Apache config syntax +
required modules loaded, vhost symlinked into `sites-enabled`, `koha-plack`
process status, socket permissions, a **direct unix-socket curl** to
`plack.psgi` (isolates the Plack backend from Apache), HTTP 200 + real HTML +
no raw-Perl-leakage + no default-Apache-page on both vhosts' `/` and
`/index.html`, REST API and OPAC search reachability through the proxy,
watchdog crash-recovery (kill `-9` the plack pid, wait past the 30s poll
interval, confirm it restarts and HTTP resumes), and restart idempotency
(`--force-recreate` twice in a row without crashing — regression test for
fix #5). All 21 checks passed on a clean, fully-recreated container.

## Round 2 — "8081 doesn't answer, 8080 CSS/JS missing" (reported after round 1 was pushed)

### Finding 4 — service startup ordering race

`run.sh` called `start_apache_service` **before**
`enable_instance_services`/`start_koha_service` (which starts `koha-plack`).
Since the vhost's `ProxyPass` rules cover almost every request path (including
bare `/` via the rewrite rule), Apache could start accepting connections and
503 on literally every request during the ~2 second window before the plack
socket exists. Testing immediately after a fresh boot, whichever vhost got hit
first could appear completely dead. **Fix**: reordered to start
`koha-plack`/`koha-worker` first, then Apache.

### Finding 5 — compiled CSS/JS assets were never built at runtime

Inspecting `koha-tmpl/opac-tmpl/bootstrap/css/` showed only a handful of
static files (`babeltheque.css`, `bootstrap-theme-oai.css`, `hierarchy.css`,
`oai.css`, `overdrive.css`) — the **main** stylesheet (`opac.css`, compiled
from `css/src/opac.scss` via `gulp css` / `yarn css:build`) was entirely
missing. `Koha::Template::Plugin::Asset::url()` (in
`koha/Koha/Template/Plugin/Asset.pm`) does a plain `-e $abspath` filesystem
check and, if the file isn't found, does **nothing but a Perl `warn`** —
`Asset.css(...)`/`Asset.js(...)` silently render as empty strings. The result:
pages returned a perfectly good HTTP 200 with real Koha HTML, just with **zero
`<link rel="stylesheet">` tags** — a bug class invisible to any check that
only looks at HTTP status codes.

Root cause: `Dockerfile-Alpine`'s `node-builder` stage (based on
`node:22-alpine`) does run `yarn install && yarn build`, and its output is
copied into the final image's `/kohadevbox/koha/koha-tmpl` at build time. But
`docker-compose-alpinekoha.yml` bind-mounts the live host `${SYNC_REPO}`
directory over `/kohadevbox/koha` at container start (the whole point of the
dev workflow — live-edit the Koha source) — this **replaces** the
Docker-build-time compiled `koha-tmpl` with the host checkout's raw,
uncompiled SCSS-only source, every single time the container starts.

**Fix**: (a) added `nodejs npm yarn` to the `apk add` line in
`Dockerfile-Alpine` — the final runtime image previously had **no** Node.js
toolchain at all, only the throwaway `node-builder` stage did; (b) added an
idempotent build step to `run.sh`, right after the template symlinks: if
`koha-tmpl/opac-tmpl/bootstrap/css/opac.css` is missing, run
`cd $KOHADEVBOX && yarn install --frozen-lockfile && yarn build`, skippable
via `SKIP_YARN_BUILD=yes`, so it only costs time on the very first boot
against a given checkout (subsequent restarts see `opac.css` already present
and skip straight past it). Verified: the build runs automatically
(`yarn install`, `gulp css` ×2, `rspack build` ×4 bundles, `redocly bundle`,
~29s total), `opac.css` (563KB) is produced and served, and both OPAC (2
stylesheet links) and staff (3 stylesheet links) pages went from **zero**
`<link rel="stylesheet">` tags to a working, styled page.

### Test harness hardening (round 2)

Added a `check_css` flag to the harness's `check_html_endpoint()` helper: it
now fails if a checked page has **zero** `<link rel="stylesheet">` tags, plus
a dedicated check that `/opac-tmpl/bootstrap/css/opac.css` returns 200. This
closes exactly the gap that let finding 5 through round 1's checks (which only
verified HTTP 200 + real HTML + no source leakage — all of which a
CSS-less page still satisfies). Harness went from 21 to 22 checks, all
passing after the fix.

## Round 3 — "8081 is not working" (still not reproducible via curl)

Every `curl` test against `:8081` continued to return clean `200 OK` with
real HTML — the user's report could not be reproduced from the command line.
The user's specific ask was to check whether another process had taken port
8081 and kill it if so. `ss -tlnp` / `lsof -i :8081` on the host confirmed
**no conflict**: the only listener on 8080/8081 was Docker's own
`docker-proxy`, correctly forwarding to the `koha-alpine` container's own
published ports. There was nothing to kill.

### Finding 6 — the bug only manifests in an actual browser

Rather than continuing to test via `curl`, the page was opened in the
integrated browser tool (`open_browser_page` /
`http://localhost:8081/`). The page loaded (title "Log in to Koha", real login
form) but the browser console showed:

```
ReferenceError: $ is not defined       (staff-global_....js:55)
ReferenceError: dayjs is not defined
ReferenceError: $ is not defined       (basket_....js:556, form-submit_....js:37)
ReferenceError: __ is not defined      (show-password-toggle_....js:13)
```

jQuery (and other vendored libraries) never loaded at all — the page had a
functioning HTTP response but **zero interactivity**: the "Show password"
toggle didn't render, and every jQuery-dependent behavior across the page was
silently broken. This is exactly why the user experienced the page as "not
working" even though the server always answered.

Root cause (same *shape* of bug as finding 5, different asset): jQuery is
loaded via `Asset.js("lib/jquery/jquery-3.6.0.min.js")` in
`koha-tmpl/intranet-tmpl/prog/en/includes/js_includes.inc`. `Asset::url()`
resolves this against `<intrahtdocs>`/`<opachtdocs>` (from
`koha-conf.xml`), which point at `/usr/share/koha/{intranet,opac}/htdocs/...`
— a **separate symlink farm** from Apache's own `DocumentRoot` (which points
directly at the real git checkout and therefore always had the file). That
symlink farm was built by `run.sh` cherry-picking specific subdirectories:
`intranet-tmpl/prog` (+ a `prog/en` shortcut) and `opac-tmpl/bootstrap` (+
a `bootstrap/en` shortcut) — but **never** `intranet-tmpl/lib/` or
`opac-tmpl/lib/`, where jQuery, jQuery UI, and other shared plugins actually
live. `Asset::url()` silently returned `undef` (again, just a Perl `warn`,
no visible error), so `Asset.js(...)` emitted **no `<script>` tag at all** for
jQuery — not a 404, not an error, just an absent tag.

**Fix**: replaced the cherry-picked, subdirectory-by-subdirectory symlinks in
`files-alpine/run.sh` with two whole-tree symlinks:

```bash
ln -sf ${KOHADEVBOX}/koha-tmpl/intranet-tmpl /usr/share/koha/intranet/htdocs/intranet-tmpl
ln -sf ${KOHADEVBOX}/koha-tmpl/opac-tmpl     /usr/share/koha/opac/htdocs/opac-tmpl
```

This covers `prog/`, `prog/en/`, `lib/`, `bootstrap/`, `bootstrap/en/`, and any
future subdirectory automatically, eliminating the whack-a-mole. Before
removing the old standalone `intranet-tmpl/en` shortcut symlink, grepped
`koha/C4` and `koha/Koha` for any direct reference to
`intranet-tmpl/en` (without the `prog/` segment in between) to confirm nothing
depended on it — no hits, safe to remove.

**Verified**: `curl http://localhost:8081/` now includes
`src="/intranet-tmpl/lib/jquery/jquery-3.6.0.min_<version>.js"` (200 OK); a
browser reload of the same page (via the integrated browser tool) now renders
the "Show password" checkbox (a jQuery-dependent UI element) and reports
**zero** JS console errors. This fix required no image rebuild —
`files-alpine/run.sh` is bind-mounted, so `--force-recreate` alone was enough.

Added a jQuery-presence check to the harness (grep the staff page for
`lib/jquery/jquery-3`), since — like finding 5 — this bug class cannot be
caught by HTTP-status/HTML-size checks alone. Harness: 22/22 (or 21/22 when
`--no-watchdog-test` is used to skip the ~35s crash-recovery test for a quick
run).

## Cross-cutting lesson

Three separate, unrelated bugs (missing CSS, missing jQuery, and — by
implication — anything else routed through `Koha::Template::Plugin::Asset`)
all share the same failure signature: **the page returns HTTP 200 with
legitimate HTML, and the only symptom is a silently absent `<script>`/`<link>`
tag**, because `Asset::url()` fails open (a `warn`, not a die, not a 404) when
it can't find a file under `<intrahtdocs>`/`<opachtdocs>`. Any HTTP-status-only
test harness (including the entirety of round 1's harness) is blind to this
class of bug. Two concrete defenses were added: (1) an explicit
`<link rel="stylesheet">`-presence check, and (2) an explicit jQuery
`<script>`-presence check. The general principle — verified end-to-end with a
real browser at least once, not just `curl`, whenever a page "renders" but a
user reports something not working — is recorded here for future debugging.

## Files touched this session (all on `phase` branch)

- `Dockerfile-Alpine` — added `apache2-proxy` (mod_proxy for Alpine's apache2)
  and `nodejs npm yarn` to the `apk add` line.
- `files-alpine/run.sh` — idempotency/crash fix for superlibrarian creation;
  whole-tree template symlinks (replacing cherry-picked subdirs); runtime
  `yarn build` step (skippable via `SKIP_YARN_BUILD`); Apache module
  enabling + `sites-enabled` include + Debian-path stripping in the real
  Koha `apache-shared*.conf` files; service startup reordered
  (plack/worker before Apache); replaced the broken
  `exec plackup --port 5000 app.psgi` tail with
  `render_vhost` → `start_apache_service` → `enable_instance_services` →
  `start_koha_service` → `start_crond` → `run_service_watchdog`.
- `files-alpine/lib/run-sh-alpine.sh` — restored in full (350 lines) from the
  version baked into the previously-stale Docker image.
- `files-alpine/scripts/koha-plack` — rewritten (v11) to run Starman against
  `plack.psgi` over a unix socket instead of `plackup`/`app.psgi` on port 5000;
  added `chmod 777` on the socket after start.
- `files-alpine/templates/koha-vhost.conf.in` — added `ProxyPass` rules to the
  plack unix socket (registered before the Include'd `ScriptAlias`
  directives), added the `RewriteRule ^/$ /index.html [PT]` root redirect.
- `docker-compose-alpinekoha.yml` — bind-mounted
  `files-alpine/{lib,scripts,templates}` in addition to the pre-existing
  `run.sh` bind mount, for live editing without rebuilds.
- `test-plack-stack.sh` (new) — 22-check consolidated harness covering image
  freshness, Apache config/modules, Plack process/socket health, HTTP
  endpoints (including CSS and jQuery asset-presence checks), API/search
  reachability, watchdog crash-recovery, and restart idempotency.

## Status at end of session

Round 1 (`t 16`) was committed and pushed by the user between sessions.
Rounds 2 and 3 (Dockerfile nodejs/yarn, run.sh yarn-build step + service
reorder + whole-tree symlinks, koha-plack, koha-vhost.conf.in,
test-plack-stack.sh CSS/jQuery checks) are **working-tree changes, not yet
committed** as of this tracker entry. Both OPAC (`:8080`) and staff (`:8081`)
are confirmed fully functional — correct HTML, correct CSS, correct JS,
interactive UI, no console errors — verified via both `curl` and an actual
browser session.
