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
  - `copy_runtime_files` is now a strict no-op with an explicit Phase 2 message.
  - Removed runtime execution paths for:
    - `/usr/local/bin/build-alpine-package.sh`
    - `cp_alpine_files.pl`
    - `cp_debian_files.pl`

1. Enforced build-time staging for all image modes (base layer).

- Updated Dockerfile-Alpine:
  - Added `COPY koha /tmp/koha-build-src`.
  - Added `RUN /usr/local/bin/build-alpine-package.sh /tmp/koha-build-src && rm -rf /tmp/koha-build-src`.
  - Set `ENV SKIP_RUNTIME_ASSET_COPY=yes` at base-image level.

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

To validate the koha-base staging path end-to-end, the image target was built and checked from inside a launched container.

Executed:

```bash
IMAGE_TAG=koha-alpine:phase2-koha-base-e2e
docker build --target koha-base -f Dockerfile-Alpine -t "$IMAGE_TAG" .
docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -lc '<assertions>'
```

Assertions passed:

- `/usr/share/koha` exists.
- `/usr/share/koha/intranet/htdocs` is non-empty.
- `/usr/share/koha/opac/htdocs` is non-empty.
- `/usr/share/koha/lib/C4` exists.
- `/usr/share/koha/lib/Koha` exists.
- `/usr/share/koha/bin/koha-functions.sh` exists.
- `/etc/koha/koha-conf-site.xml.in` exists.
- `/etc/koha/apache-shared-intranet.conf` exists.
- `/etc/koha/apache-shared-opac.conf` exists.
- `/etc/default/koha-common` exists.
- `/etc/init.d/koha-common` exists.
- `/etc/logrotate.d/koha-common` exists.
- `/usr/share/man/man8/koha-*.8.gz` manpages exist.

Final runtime output:

```text
[PASS] koha-base build-time staging validation complete
```
