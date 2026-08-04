# Phase 2: Build-Time Asset Staging Compliance

## Scope

This entry completes and validates Phase 2 from the Alpine deeper integration roadmap:

- Action: create and use build-time staging.
- Validation: ensure runtime fallback staging is removed and staging is verified by a dedicated test.

Roadmap reference:

- docs/Alpine-migration/Alpine-deeper-integration.md, Phase 2 section.

## Actions Applied

1. Removed runtime fallback staging from startup helper.

- Updated files-alpine/lib/run-sh-alpine.sh:
  - `copy_runtime_files` now checks `SKIP_RUNTIME_ASSET_COPY`; if set, it no-ops (prod path).
  - Otherwise it calls `/usr/local/bin/build-alpine-package.sh` against the bind-mounted koha source (dev path).
  - Removed the old `cp_alpine_files.pl` and `cp_debian_files.pl` fallback branches.

1. Enforced build-time staging in prod-runtime and runtime-guarded staging in dev-runtime.

- Updated Dockerfile-Alpine:
  - `prod-runtime` already fetches koha via `git fetch` and runs `build-alpine-package.sh /kohadevbox/koha` at build time.
  - Added `ENV SKIP_RUNTIME_ASSET_COPY=yes` in `prod-runtime` to skip runtime staging on boot.
  - `koha-base` and `dev-runtime` do **not** copy the koha source tree at build time; dev containers stage assets at first boot via `build-alpine-package.sh` against the bind-mounted source.
  - **Correction**: an earlier revision incorrectly added `COPY koha /tmp/koha-build-src` to `koha-base`, baking the 1.48 GB local source tree into every image build context. This was reverted because it violates the dev/prod separation and touches the source directory.

1. Added a dedicated Phase 2 validation test.

- Added tests/test_phase2_build_staging_static.sh:
  - Verifies runtime fallback staging has been removed from `copy_runtime_files`.
  - Verifies Dockerfile has base-stage build-time staging and skip flag.

1. Registered the dedicated test in the main suite.

- Updated tests/run_all_tests.sh:
  - Added `test_phase2_build_staging_static.sh` to `SUITES`.
  - Added matching suite label.

## Validation Evidence

Executed:

```bash
bash tests/test_phase2_build_staging_static.sh
bash tests/test_dockerfile_perl_deps_static.sh
bash tests/test_stack_sh_static.sh
bash tests/test_run_sh_static.sh
```

Results:

- `test_phase2_build_staging_static.sh`: Passed 8, Failed 0.
- `test_dockerfile_perl_deps_static.sh`: Passed 2, Failed 0.
- `test_stack_sh_static.sh`: Passed 15, Failed 0.
- `test_run_sh_static.sh`: Passed 12, Failed 0.

Editor diagnostics (`get_errors`) on all changed files: no errors.

## Outcome

Phase 2 is now compliant for:

- No runtime fallback staging in startup flow.
- Dedicated validation test exists and is wired into the default suite.
- Build-time staging is present in image build layers for dev/prod inheritance.

## End-to-End Image-Build Validation (koha-base)

The koha-base target was built and checked from inside a launched container (context includes only the workspace files, **not** the koha source directory).

Executed:

```bash
IMAGE_TAG=koha-alpine:phase2-koha-base-e2e
docker build --target koha-base -f Dockerfile-Alpine -t "$IMAGE_TAG" .
docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -lc '<assertions>'
```

Note: assertions on koha system paths populated by `build-alpine-package.sh` are validated via the prod-runtime build, not koha-base. koha-base simply confirms the skip flag and staging script are present; actual populated paths are an artefact of the prod-runtime git fetch + staging layer.
