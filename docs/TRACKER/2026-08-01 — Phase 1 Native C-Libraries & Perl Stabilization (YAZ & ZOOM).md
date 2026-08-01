# Phase 1: Native C-Libraries & Perl Stabilization (YAZ & Net::Z3950::ZOOM)

## Overview & Scope
As part of the [Alpine Deeper Integration Roadmap](file:///mnt/beckie2/DEVELOPMENT/koha-alpine/docs/Alpine-migration/Alpine-deeper-integration.md), Phase 1 eliminates the mock `ZOOM.pm` stub in [Dockerfile-Alpine](file:///mnt/beckie2/DEVELOPMENT/koha-alpine/Dockerfile-Alpine) and establishes native compilation of Index Data's YAZ Z39.50/SRU toolkit for Alpine Linux (`musl` libc).

## Root Cause Analysis & Compiler Adjustments
1. **Alpine Repository Deficit**: Alpine Linux 3.24 repositories do not ship pre-packaged `yaz` binaries or development headers (`libyaz-dev`).
2. **GCC 14+ / C23 Build Compatibility**:
   - `yaz-5.34.0` standard C source includes identifiers named `bool` in `cql2ccl.c` which break under GCC 14+ default C23 standard semantics (`-std=c23`).
   - GCC 14+ treats missing function declarations (`atoi` in `xmlquery.c` and `record_conv.c`) as hard errors (`-Werror=implicit-function-declaration`).
3. **Remediation**:
   - Added `readline-dev` to base APK packages.
   - Configured `yaz` compilation with `CFLAGS="-std=gnu17 -Wno-error=implicit-function-declaration -D_GNU_SOURCE"`.

## Changes Applied
- Modified [Dockerfile-Alpine](file:///mnt/beckie2/DEVELOPMENT/koha-alpine/Dockerfile-Alpine):
  - Added native build step for `yaz-5.34.0`.
  - Removed 150-line mock `ZOOM.pm` inline stub.
  - Added `cpanm --notest Net::Z3950::ZOOM` to compile genuine `Net::Z3950::ZOOM` (v1.32) against native `libyaz`.

## Verification Results
- **Docker Image Build**: Built `koha-base` stage cleanly (`156.4s`).
- **Module Inspection**:
  - `Net::Z3950::ZOOM` version `1.32` compiled and installed at `/usr/local/lib/perl5/site_perl/Net/Z3950/ZOOM.pm` and `/usr/local/lib/perl5/site_perl/ZOOM.pm`.
- **Koha Runtime Integration**:
  - Executed runtime test inside container loading `C4::Breeding`, `C4::AuthoritiesMarc`, and `C4::Search`:
    ```
    All Koha Z3950/ZOOM modules loaded cleanly!
    ```
