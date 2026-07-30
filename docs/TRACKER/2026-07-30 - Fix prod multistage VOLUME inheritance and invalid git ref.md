# 2026-07-30 - Fix prod multistage VOLUME inheritance and invalid git ref

Status: Completed
Severity: Critical (prod image was silently broken; Koha source never visible at runtime)
Scope: Dockerfile-Alpine (stage restructure), README.md (documentation corrections)

---

## Problem statement

Building the production image with:

```bash
./stack-alpine.sh build --image-mode prod --koha-version 26.11.00 --koha-ref v26.11.00 --build-koha
```

failed with:

```
fatal: couldn't find remote ref v26.11.00
```

Investigation revealed two independent bugs, one fatal at build time and one silently fatal at runtime.

---

## Root cause analysis

### Bug 1 — Non-existent git tag (build-time failure)

`v26.11.00` does not exist as a git tag on the Koha community repository.
Koha 26.11 is the November 2026 release cycle; it has not been tagged yet.

Verified available 26.x refs via:

```bash
git ls-remote --tags https://git.koha-community.org/Koha-community/Koha.git | grep "v26\."
```

Result:

```
refs/tags/v26.05.00
refs/tags/v26.05.01-1
```

Available branches:

```bash
git ls-remote --heads https://git.koha-community.org/Koha-community/Koha.git | grep "26\."
```

Result:

```
refs/heads/26.05.x
```

The active development branch for unreleased code (including 26.11) is `main`.

### Bug 2 — Inherited `VOLUME` hides baked Koha source at runtime (silent runtime failure)

`prod-runtime` was declared as `FROM dev-runtime AS prod-runtime`.

`dev-runtime` contains `VOLUME /kohadevbox/koha`.

Docker's VOLUME inheritance rule: when a child image inherits from a parent that declares a VOLUME, the volume declaration is also inherited. At container startup, Docker creates an anonymous volume over that path. This anonymous volume is always empty on first run and permanently shadows any files baked into the image layer at that path.

Consequence: even if the git fetch had succeeded, the cloned Koha source would have been invisible inside the running container. The prod image appeared to build but the Koha tree was never reachable.

The docker-compose.prod.yml has no explicit volume mount for `/kohadevbox/koha`, so there was no bind mount to override the anonymous volume from the host side either.

This bug was pre-existing from the first implementation of the dual-mode image strategy (noted as a known caveat in the previous tracker entry).

---

## Changes implemented

### A) Dockerfile-Alpine — stage restructure

**Before:**

```
FROM alpine:3.24.1 AS dev-runtime
  ...
  VOLUME /kohadevbox/koha
  COPY / RUN / EXPOSE / CMD ...

FROM dev-runtime AS prod-runtime
  ARG KOHA_GIT_REF ...
  RUN git fetch ... origin "${KOHA_GIT_REF}" ...
```

**After:**

```
FROM alpine:3.24.1 AS koha-base
  ...
  # NO VOLUME here
  COPY / RUN / EXPOSE / CMD ...

FROM koha-base AS dev-runtime
  VOLUME /kohadevbox/koha          # bind-mount anchor for dev, not inherited by prod

FROM koha-base AS prod-runtime     # no VOLUME; baked source persists at runtime
  ARG KOHA_GIT_REF ...
  RUN git fetch ... origin "${KOHA_GIT_REF}" ...
```

Specific edits:

1. Line 1: `FROM alpine:3.24.1 AS dev-runtime` → `FROM alpine:3.24.1 AS koha-base`
2. Removed the `VOLUME /kohadevbox/koha` instruction and its comment from the base stage.
3. After the `CMD` instruction at the end of the base content, inserted:
   ```dockerfile
   # dev-runtime: thin wrapper that declares the koha source volume for bind-mount at runtime.
   FROM koha-base AS dev-runtime
   VOLUME /kohadevbox/koha
   ```
4. `FROM dev-runtime AS prod-runtime` → `FROM koha-base AS prod-runtime`

Behavioral guarantees after this change:

- `dev-runtime` still declares `VOLUME /kohadevbox/koha`; the docker-compose bind mount
  (`${SYNC_REPO}:/kohadevbox/koha`) continues to override it at runtime as before.
- `prod-runtime` has no `VOLUME` declaration; the Koha source fetched via git is stored
  in the image layer and is visible inside the container at runtime.
- Both targets inherit CMD, EXPOSE, run.sh, templates, and all system setup from `koha-base`.
- The `target: dev-runtime` reference in `docker-compose-alpinekoha.yml` continues to work
  unchanged because `dev-runtime` still exists as a named stage.

### B) README.md — documentation corrections

**Build Stages table** (section: "Build Stages (Dockerfile-Alpine)"):
- Replaced the generic "Runtime" row with three explicit rows:
  - `koha-base` — shared setup stage, no VOLUME
  - `dev-runtime` — thin wrapper adding `VOLUME /kohadevbox/koha`
  - `prod-runtime` — inherits `koha-base`, bakes Koha source via git fetch

**Mode comparison table** (section: "Dual Image Modes"):
- Clarified `dev-runtime` column: "VOLUME declared so compose bind-mount takes precedence"
- Clarified `prod-runtime` column: "no VOLUME so the baked tree is visible at runtime"

**Prod build/start examples** (section: "Build and start in Production context"):
- Split into two explicit blocks:
  - Released version: uses git tag (`v26.05.01-1`)
  - Pre-release / development version: uses branch (`main`)
- Updated `--koha-ref` flag description to note the distinction between tags and branches.

**Optional direct Compose usage** (section: "Optional direct Docker Compose usage"):
- Split into released and pre-release variants, same ref logic as above.

**Deployment steps** (section: "Deployment Steps"):
- Build and start examples: `--koha-ref v26.11.00` → `--koha-ref main`
- Direct Compose block: `KOHA_RELEASE_REF=v26.11.00` → `KOHA_RELEASE_REF=main`

**Rollback pattern** (section: "Rollback Pattern"):
- `--koha-ref v26.11.00` → `--koha-ref main`

---

## File-level change inventory

Modified:

1. `Dockerfile-Alpine`
   - Stage renamed: `dev-runtime` → `koha-base`
   - VOLUME moved: out of base, into new thin `dev-runtime` wrapper
   - prod-runtime parent changed: `dev-runtime` → `koha-base`

2. `README.md`
   - Build Stages table expanded with three final-stage rows
   - Mode comparison table clarified for VOLUME behavior
   - All `v26.11.00` git ref examples corrected (released: tag; pre-release: `main`)

---

## Validation

Stage structure confirmed after edits:

```bash
grep -n "^FROM\|^VOLUME\|^EXPOSE\|^CMD\|^ARG KOHA_GIT" Dockerfile-Alpine
```

Expected output (abbreviated):

```
1:FROM alpine:3.24.1 AS koha-base
620:EXPOSE 6001 8080 8081
622:CMD ["/bin/bash", "/kohadevbox/run.sh"]
625:FROM koha-base AS dev-runtime
626:VOLUME /kohadevbox/koha
628:FROM koha-base AS prod-runtime
630:ARG KOHA_GIT_URL=...
631:ARG KOHA_GIT_REF=v25.11.05-1
632:ARG KOHA_GIT_DEPTH=1
```

No stale `v26.11.00` git ref references remain in README.md (confirmed via grep).

---

## Ref format reference

| Situation | Correct `--koha-ref` value | Example |
|-----------|---------------------------|---------|
| Released Koha version | git tag matching the release | `v26.05.01-1` |
| Pre-release / development | active development branch | `main` |
| Specific commit (any) | full or short SHA | `d7efb559` |

The `configure_koha_mode()` function in `stack-alpine.sh` auto-derives `KOHA_RELEASE_REF`
as `v${KOHA_RELEASE_VERSION}` when `--koha-ref` is omitted. This derivation is only correct
for released versions. For pre-release builds, always supply `--koha-ref main` explicitly.

---

## Relation to previous tracker entry

The 2026-07-30 dual-mode tracker noted under "Risks and caveats":

> `prod-runtime` currently inherits from `dev-runtime`, so production image still includes
> development tooling footprint. This is intentional for first iteration speed/safety.

The VOLUME inheritance side-effect of that decision was not identified at that time.
This entry resolves it. The dev tooling footprint (misc4dev, gitify, qa-test-tools) remains
in the `koha-base` shared stage and is therefore still present in the prod image; that is a
separate concern deferred to future hardening.

---

## Recommended next steps (carried forward from previous entry)

1. Trim `koha-base` / `prod-runtime` contents to remove dev-only helpers and reduce image size.
2. Add explicit prod startup profile in `run.sh` to skip non-essential dev bootstrap branches.
3. Add release runbook: build fixed ref → tag/push image → start with `--image-mode prod` → rollback by previous image tag.
4. Add automated CI checks for both compose modes (`dev` + `prod`).
5. When Koha 26.11 is released (November 2026), verify the `v26.11.00-1` (or equivalent) tag exists before using it as `--koha-ref`.
