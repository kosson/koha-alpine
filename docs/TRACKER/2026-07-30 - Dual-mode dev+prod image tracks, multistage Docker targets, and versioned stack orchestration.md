# 2026-07-30 - Dual-mode dev+prod image tracks, multistage Docker targets, and versioned stack orchestration

Status: Completed
Severity: High (architecture-level change with release/deploy impact)
Scope: Docker build model, Compose topology, stack orchestration, migration documentation

---

## Objective of this move

Implement the first practical iteration toward split runtime modes:

1. Keep current Alpine workflow for development/testing.
2. Add a production-oriented fixed-version image path with baked Koha source.
3. Add orchestration controls to select dev/prod mode and version metadata cleanly.

This is the first concrete step from:

- docs/Alpine-migration/koha-fixed-version-production-image-strategy.md

---

## Summary of implemented modifications

## A) Documentation changes

### 1) New strategy document (production fixed-version track)

File:

- docs/Alpine-migration/koha-fixed-version-production-image-strategy.md

What was added:

1. Dual-track model (dev vs prod).
2. Multistage Docker design concept.
3. Fixed-version pinning model and image metadata strategy.
4. Version-based naming conventions.
5. Compose split recommendation (`docker-compose.prod.yml` overlay).
6. Phased rollout and acceptance criteria.

Operational purpose:

- Establish architectural contract for immutable production images while preserving current developer ergonomics.

### 2) Expanded koha-gitify dependency report

File:

- docs/Alpine-migration/koha-gitify-function-and-dependency-elimination-report.md

What was added/clarified:

1. Strong clarification that `koha-gitify` rewrites config paths and does not create bind mounts/symlinks.
2. Upstream intent and assumptions extracted from local `gitify/README.md` and `gitify/koha-gitify` comments/POD.
3. Appendix table mapping each touched config file to replacement patterns and runtime effects.

Operational purpose:

- Make dependency elimination technically auditable and reduce ambiguity in future refactors.

---

## B) Build pipeline changes

### 1) Dockerfile converted to explicit dual targets

File:

- Dockerfile-Alpine

Key changes:

1. Renamed original single-stage image to named target:
   - `FROM alpine:3.24.1 AS dev-runtime`
2. Added new production target:
   - `FROM dev-runtime AS prod-runtime`
3. Added production build args:
   - `KOHA_GIT_URL`
   - `KOHA_GIT_REF`
   - `KOHA_GIT_DEPTH`
   - `KOHA_VERSION`
4. Added OCI labels for production target:
   - title/version/source.
5. Added baked-source production build logic:
   - fresh init under `/kohadevbox/koha`
   - fetch pinned ref
   - detached checkout from fetched head
6. Added build-time yarn dependency installation in prod target:
   - `yarn install --frozen-lockfile`
7. Set default runtime optimization flag in prod target:
   - `SKIP_YARN_INSTALL=yes`

Operational purpose:

- Enable immutable Koha code in image layers for production use.

### 2) Development compose made explicit about build target

File:

- docker-compose-alpinekoha.yml

Key change:

- `build.target: dev-runtime` for service `koha`.

Operational purpose:

- Preserve existing behavior as default while introducing new prod target.

---

## C) Production Compose overlay (new)

### 1) Added production override file

File:

- docker-compose.prod.yml

Key behavior:

1. Uses `prod-runtime` target.
2. Passes production build args for fixed ref/version.
3. Sets production image tag variable:
   - `KOHA_ALPINE_PROD_IMAGE_TAG` fallback uses release version.
4. Overrides `koha` volumes to remove source bind mount.
   - Keeps only TLS/CA runtime mounts needed by this stack.
5. Forces runtime skip of yarn install by default.

Operational purpose:

- Make production profile source-immutable and version-addressable with minimal churn to base compose.

---

## D) Stack orchestration changes (`stack-alpine.sh`)

### 1) Compose profile and project naming controls

Added:

1. `KOHA_COMPOSE_PROD_FILE` path.
2. Dynamic compose wrapper:
   - always includes base compose
   - adds prod override when `--image-mode prod`
3. Explicit compose project name (`-p`) support via script-generated value.

Result:

- Dev mode project name: defaults to repo-derived value.
- Prod mode project name: `koha-prod-<version-slug>`.

### 2) Production mode config variables

Added env-derived variables:

- `KOHA_IMAGE_MODE`
- `KOHA_RELEASE_VERSION`
- `KOHA_RELEASE_REF`
- `KOHA_RELEASE_GIT_URL`
- `KOHA_RELEASE_GIT_DEPTH`
- `KOHA_ALPINE_PROD_IMAGE_TAG`

Added helpers:

1. `version_slug()`
2. `configure_koha_mode()`

`configure_koha_mode()` responsibilities:

1. Validate mode (`dev|prod`).
2. Derive missing ref/version pair where possible.
3. Compute default prod image tag when absent.
4. Compute compose project name for prod.
5. Export production build values.
6. Recompute DB container name from selected compose project.

### 3) Command-line interface additions

Added options:

- `--image-mode <dev|prod>`
- `--koha-version <ver>`
- `--koha-ref <ref>`

Updated usage/examples accordingly.

### 4) Mode-aware behavior adjustments

Changed logic so host source bootstrap is only done for dev mode:

- `start`
- `restart`
- `build`
- `restore`

Each now avoids `ensure_koha_source` in prod mode.

### 5) Build log clarity

`build_koha()` now logs:

1. current image mode,
2. prod image tag (if prod),
3. prod Koha ref (if prod).

### 6) Prereq checks tightened for prod mode

`check_prereqs()` now validates presence of:

- `docker-compose.prod.yml` when in prod mode.

Operational purpose of all stack changes:

- Allow deterministic selection of dev/prod build+run topology from one script without duplicating orchestration logic.

---

## Validation evidence captured

The following checks were executed and passed:

1. Shell syntax validation:

```bash
bash -n stack-alpine.sh
```

2. Compose profile merge validation:

```bash
docker compose -f docker-compose-alpinekoha.yml -f docker-compose.prod.yml --env-file env/.env config --services
```

Observed service list included expected core services:

- `db`
- `memcached`
- `rabbitmq`
- `koha`

3. CLI help validation for new flags:

```bash
./stack-alpine.sh --help
```

Confirmed presence of:

- `--image-mode`
- `--koha-version`
- `--koha-ref`

4. Grep-based traceability checks for key anchors across edited files.

---

## File-level change inventory (this move)

Modified:

1. `Dockerfile-Alpine`
2. `docker-compose-alpinekoha.yml`
3. `stack-alpine.sh`
4. `docs/Alpine-migration/koha-gitify-function-and-dependency-elimination-report.md`

Created:

1. `docker-compose.prod.yml`
2. `docs/Alpine-migration/koha-fixed-version-production-image-strategy.md`
3. `docs/TRACKER/2026-07-30 - Dual-mode dev+prod image tracks, multistage Docker targets, and versioned stack orchestration.md` (this entry)

Observed but not introduced in this change set:

1. `env/.env` had a machine-local `SYNC_REPO` path drift already present in working changes.
   - Treated as environment-local state, not a core design change.

---

## Behavioral impact

## Development mode (default)

- Remains source-mounted and workflow-compatible with existing setup.
- Build path explicitly targets `dev-runtime`.

## Production mode (new)

- Supports baked Koha source by fixed ref/version.
- Uses compose overlay that removes source bind mount.
- Uses version-derived compose project naming for clearer runtime identity.

---

## Risks and caveats

1. `prod-runtime` currently inherits from `dev-runtime`, so production image still includes development tooling footprint.
   - This is intentional for first iteration speed/safety.
2. No full runtime integration load test for prod profile in this cycle (only syntax/config validation).
3. Runtime bootstrap path (`run.sh`) is not yet deeply specialized for prod-only minimal startup.

---

## Recommended next hardening steps

1. Trim `prod-runtime` contents to remove dev-only helpers and reduce image size.
2. Add explicit prod startup profile in `run.sh` to skip non-essential dev bootstrap branches.
3. Add release runbook:
   - build fixed ref,
   - tag/push image,
   - start with `--image-mode prod`,
   - rollback by previous image tag.
4. Add automated CI checks for both compose modes (`dev` + `prod`).

---

## Quick operator examples (post-change)

Build prod image for a fixed Koha version:

```bash
./stack-alpine.sh build --image-mode prod --koha-version 26.11.00 --koha-ref v26.11.00 --build-koha
```

Start stack in prod mode:

```bash
./stack-alpine.sh start --image-mode prod --koha-version 26.11.00 --koha-ref v26.11.00
```

Use unchanged dev mode:

```bash
./stack-alpine.sh start
```

---

## Decision log

This cycle intentionally prioritizes architecture separation over full optimization:

- deliver mode split and version-pin path first,
- keep dev behavior stable,
- defer deeper production slimming to next iteration.

That decision reduces migration risk while unlocking deterministic production image workflows immediately.
