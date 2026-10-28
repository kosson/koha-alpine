# Phase B: Pinned Production Image and Isolated Startup

**Date:** 2026-10-28  
**Branch:** `phase`  
**Status:** Phase B exit gate passed

## Outcome

Built a production Koha Alpine image from the pinned upstream tag `v26.05.01-1`, aligned its Perl dependencies with the exact fetched Koha source, verified image provenance and baked assets, and started it successfully in a fresh isolated Compose project. The project had new, project-scoped database and RabbitMQ volumes, no development checkout mount, and dedicated host ports. The production startup smoke test passed.

## Implementation and issues addressed

| Issue | Change |
|---|---|
| Production source and Perl dependencies could come from different Koha revisions. | Added a production dependency stage that installs from the source fetched by `prod-source`; dev and production use the shared fail-fast `scripts/install-koha-perl-dependencies.sh` installer. |
| Production builds could use a mutable branch or lack a source ref. | Require a release ref, reject branch refs, fetch tags explicitly, accept full commit IDs, and persist the resolved commit, requested ref, and source URL in the image. |
| Production Compose inherited the development checkout mount. | Replace the production Koha volume list with `!override`; the merged production config contains no `/kohadevbox/koha` checkout mount. |
| Production defaults were not explicit. | Production Compose disables runtime Yarn, demo data, and development-only settings unless deliberately overridden. It requires a release version and ref. |
| The production image path had not been exercised through a real startup. | Built the pinned image and ran it with fresh MariaDB/RabbitMQ volumes and an internal-only Compose network. |
| An earlier manual content assertion used the wrong intranet stylesheet path. | The pinned Koha release stores `staff-global.css` at `intranet-tmpl/prog/css/staff-global.css`, not `prog/en/css/`. Runtime links resolve to the baked templates; both the stylesheet and OPAC CSS are present and served successfully. This was an incorrect validation assumption, not a missing production asset. |

## Files changed for Phase B

- `Dockerfile-Alpine` — pinned source resolution, production source/dependency/runtime stages, metadata, and production staging.
- `scripts/install-koha-perl-dependencies.sh` — shared fail-fast Koha Perl dependency installation.
- `docker-compose.prod.yml` — required release inputs, production defaults, and source-volume isolation.
- `tests/test_dockerfile_perl_deps_static.sh` — checks the shared installer and dependency failure behavior.
- `tests/test_phase2_build_staging_static.sh` — checks source/dependency alignment, pinning, provenance, volume isolation, and production defaults.
- `docs/Alpine-migration/2026-10-roadmap-and-state-assessment.md` — Phase B status and verification evidence.
- `docs/Alpine-migration/koha-fixed-version-production-image-strategy.md` — production-image strategy and source-pinning design.

## Verification

### Build and provenance

- Built `koha-alpine-prod:phase-b-26.05.01`.
- Image ID: `sha256:55ebedb671552e58ef26737a0e8f2d1e5103b6d34b8dd2a4ffde246917130d6c`.
- Image size: 2,101,693,105 bytes (about 2.1 GB).
- Upstream tag `v26.05.01-1` resolves to commit `dacce7d3fc15860d26d06444c1f5c9a2d0d6a4a9`.
- OCI version/revision labels and `/usr/share/koha/source-revision`, `source-ref`, and `source-url` metadata were checked.
- `.git`, `node_modules`, and image-declared volumes are absent from the production image.
- A nonexistent tag fails at source fetch; Compose rejects a missing release ref/version.
- `docker buildx build --check` passes for both `prod-runtime` and `dev-runtime`.

### Isolated production startup

- Compose project: `koha-alpine-prod-test-phaseb-20261028`.
- Fresh, verified-absent volumes: `koha-alpine-prod-test-phaseb-20261028_koha-db-data` and `koha-alpine-prod-test-phaseb-20261028_koha-rabbitmq-data`.
- Dedicated ports: host 18180/18181; the Koha service uses only the project network.
- The running Koha container has no `/kohadevbox/koha` source-checkout mount.
- MariaDB became healthy; Koha logged `Startup complete`.
- `tests/test_alpine_startup_smoke.sh`: **7 passed, 0 failed**.
- OPAC and intranet returned HTTP 200 from both the container and host-published ports.
- OPAC CSS at `/opac-tmpl/bootstrap/css/opac.css` and intranet CSS at `/intranet-tmpl/prog/css/staff-global.css` returned HTTP 200.
- Runtime template symlinks and `/usr/sbin/koha-create` were verified.

### Test suite

- `tests/test_phase2_build_staging_static.sh`: **33 passed, 0 failed**.
- `tests/test_dockerfile_perl_deps_static.sh`: **7 passed, 0 failed**.
- `bash tests/run_all_tests.sh`: **229 passed, 0 failed, 34 skipped**.

## Data safety and cleanup

The production test stack was stopped without `down -v`; its new test volumes were preserved. No existing Koha container or volume was reused or removed. The production Compose validation was performed with synthetic test values rather than the repository's conflicted environment file.

## Remaining work

Phase B is complete. Phase C remains focused on the development target: repeat an empty-database bootstrap, check Plack/API/socket health, and perform a browser pass. Phase D lifecycle and scheduled-task verification, Phase E image-size/privilege hardening, and Phase F release/rollback/CI documentation remain open.

## Detailed modification record

This section records the concrete implementation and documentation changes behind the Phase B result, including why each was needed and how the behavior was checked.

### `Dockerfile-Alpine`

#### Pinned production source stage (`prod-source`)

Added a dedicated `prod-source` stage based on the already-used Node 22 Alpine builder image. It accepts `KOHA_GIT_URL`, `KOHA_GIT_REF`, and `KOHA_GIT_DEPTH`; the ref and a positive fetch depth are required for a successful stage.

Before fetching, the stage distinguishes tag refs from commit IDs and rejects branch-style refs (`refs/heads/*`, `refs/remotes/*`) and unsupported `refs/*` forms. A plain release name is converted into an explicit `refs/tags/<name>` fetch; a full 40- or 64-character hexadecimal commit is fetched as a commit ID. This keeps production source selection immutable rather than silently following a moving branch. Git checks out the fetched object detached, and the stage records both the requested ref and the resolved `HEAD` commit, as well as the source URL.

The stage installs the frontend dependencies from the frozen Yarn lockfile, builds Koha assets, and then removes `node_modules`, `.git`, and Yarn/Cypress caches before the source is copied into the runtime. As a result, the runtime gets the source and compiled assets but not the Git checkout metadata, JavaScript dependency tree, or temporary build caches.

#### Shared Perl dependency installation and source alignment

Added a shared `install-koha-perl-dependencies.sh` invocation to the builder flow. The `koha-deps` stage copies the development checkout and uses the installer there; the new `prod-deps` stage instead copies the exact tree from `prod-source` and runs the same installer against it. The resulting `/opt/koha-perl` tree is therefore produced from the same Koha revision that production will execute, rather than from whichever source happens to be in the local build context.

The production stage copies the release-matched Perl library from `prod-deps`, while the dev stage continues to use the development-matched library. The common installer performs both `cpanm --installdeps .` for Koha's declared `cpanfile` requirements and the project's existing explicit list of additional runtime Perl modules. It uses `set -eu` and does not suppress `cpanm` errors, so a failed required dependency install fails the image build instead of producing an image that only fails later at runtime.

#### Production runtime staging, provenance, and behavior

Introduced `runtime-base` as the shared point for Alpine runtime setup and Koha service wiring, and made both dev and production final targets derive from it. The `prod-runtime` target copies in the fetched release, release-matched Perl dependencies, and Koha Debian templates; it invokes the existing manifest-based `build-alpine-package.sh` against that fetched source and then installs the project-owned Alpine replacements for `koha-create`, `koha-plack`, `koha-worker`, and `koha-functions.sh`.

The image now carries:

- OCI title, version, source, and requested-ref revision labels.
- `/usr/share/koha/source-revision` with the exact resolved commit.
- `/usr/share/koha/source-url` and `/usr/share/koha/source-ref` with the upstream URL and requested tag/commit.

The distinction matters because a tag label identifies the requested name while the revision metadata file records the exact commit fetched at build time. The production environment also sets `SKIP_RUNTIME_ASSET_COPY=yes` and `SKIP_YARN_INSTALL=yes`, since source assets were built and staged during the image build; startup should not repeat development-time checkout or frontend-build work.

### `scripts/install-koha-perl-dependencies.sh`

Added this POSIX shell helper to centralize Koha CPAN dependency installation. It requires the caller to provide the Koha source directory, changes into that directory, installs the source-declared dependencies, and then installs the additional Koha application modules already required by this image. Centralizing the commands prevents the dev and production stages from drifting into different dependency lists. The fail-fast shell behavior intentionally propagates dependency errors to Docker's build, rather than hiding them with `|| true`.

### `docker-compose.prod.yml`

#### Required release identity

Production image naming and build arguments now fail during Compose interpolation if `KOHA_RELEASE_VERSION` or `KOHA_RELEASE_REF` is missing. The version is used consistently for the default image tag, `KOHA_VERSION` build argument, and runtime `KOHA_IMAGE`; the ref is passed to the Docker build as the source pin. The Git URL and fetch depth remain overrideable, with the Koha Community Git URL and shallow depth as defaults. This prevents a production build from accidentally using an unspecified or floating source.

#### Development mount isolation

Changed the Koha service's volume declaration to Compose's `!override` merge behavior. The base development Compose file mounts the local Koha checkout for live editing; ordinary list merging would retain that checkout in production even after adding the production volume list. `!override` replaces the inherited list entirely, retaining only the intended OpenSearch CA and MariaDB SSL mounts. A rendered merged config confirmed that `/kohadevbox/koha` is not a host source mount.

#### Production environment defaults

Made production's runtime settings explicit: disable CPAN and extra development/CI settings, skip Cypress ownership work, skip Yarn installation, and default demo-data loading to `no`. The demo-data setting can still be intentionally selected with `KOHA_PROD_LOAD_DEMO_DATA`. These defaults keep an ordinary production startup from performing development-only dependency installs or loading demo records.

### `tests/test_dockerfile_perl_deps_static.sh`

Updated the static dependency guard to look for the shared installer rather than assuming all dependency commands live inline in the Dockerfile. It now verifies the helper runs Koha's `--installdeps .`, checks the Dockerfile calls the helper, and checks neither the Dockerfile path nor the helper suppresses installer failures. The previous location-specific assertion would have failed after the intentional extraction, despite equivalent or stronger behavior.

### `tests/test_phase2_build_staging_static.sh`

Expanded the Phase 2 contract checks to cover the actual production guarantees: required pinned refs, branch rejection, explicit tag fetching, fetched-source use for production dependencies, resolved-commit metadata, OCI revision labeling, production Compose target and required version/ref, replacement of inherited dev volumes, absence of the dev checkout binding, production asset-build defaults, no demo data by default, and disabled development CPAN extras. These assertions guard against regression in both the Dockerfile stages and the merged production Compose contract.

### `docs/Alpine-migration/koha-fixed-version-production-image-strategy.md`

Replaced proposal-era stage descriptions with the implemented stage layout and clarified what the production target currently does. The strategy now accurately distinguishes the shared runtime package base from build tools omitted from the final image, identifies the source-aligned dependency stages, documents tag/commit-only pinning, and explains where to find the resolved commit versus the requested-ref OCI label. It also explicitly leaves remaining runtime package reduction for Phase E rather than claiming the production image is already fully minimized.

### `docs/Alpine-migration/2026-10-roadmap-and-state-assessment.md`

Updated the assessment and evidence-based implementation map to mark the production image build and inspection as complete rather than in progress. The Phase B checklist now records the successful pinned build, provenance and asset inspection, dependency/source alignment, and isolated production startup. The verification record includes the image and runtime evidence; the next open development work is described under Phase C, without conflating production startup validation with the separate development-target empty-database/API/browser gates. Added a link to this tracker record.

### This tracker note

Added this Phase B record, then expanded it with the file-by-file explanation above. It captures the reason for each code, test, and documentation change, in addition to the measurable build and runtime results earlier in the note.

### Validation-only files and runtime changes

For Compose validation and the production smoke run, created a synthetic env file and a small Compose override under the session workspace, not in the repository. The env supplied non-production test values, the pinned image/tag, and the isolated container env-file path; the override published Koha only on ports 18180/18181 and restricted the stack to its project network. The project name was `koha-alpine-prod-test-phaseb-20261028`; both expected DB/RabbitMQ volume names were checked absent before `up`.

After startup checks, the Compose containers and project network were stopped/removed with ordinary `docker compose down`, deliberately not `down -v`. The two newly created test volumes were verified to remain. The temporary synthetic env and Compose override files were then removed. The existing `koha-docker-db-1` container and `koha-docker_koha-db-data` volume were confirmed still present. No repository environment file or existing Koha volume was changed.

The first image-content assertion looked for staff CSS at `intranet-tmpl/prog/en/css/`; inspection showed the pinned Koha release places it at `intranet-tmpl/prog/css/staff-global.css`. The assertion was corrected for validation only—no product code change was needed. The runtime-created intranet and OPAC template symlinks resolve to the baked source, and the actual OPAC/staff and stylesheet URLs all returned HTTP 200.
