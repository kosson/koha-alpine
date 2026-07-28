# 2026-07-28 - Auth get_session failure root cause, detection, and remediation

Status: Resolved and validated
Severity: High (staff and OPAC paths returned HTTP 500)
Scope: Koha session initialization in Alpine runtime

---

## Incident summary

Observed runtime errors:

- `Auth ERROR: Cannot get_session() at /kohadevbox/koha/C4/Auth.pm line 1026`
- `End of script output before headers` from `mainpage.pl`, `opac-main.pl`, and `errors/500.pl`

Impact:

- Intranet and OPAC returned HTTP 500 during anonymous/session bootstrap flows.

---

## Causes

Primary root cause:

1. Koha session creation uses `Koha::Session` with `CGI::Session` driver path:
   - DSN: `serializer:yamlxs;driver:MySQL;id:md5`
2. The `id:md5` path loads `CGI::Session::ID::md5`.
3. `CGI::Session::ID::md5` requires Perl module `Crypt::SysRandom`.
4. `Crypt::SysRandom` was missing in the built Alpine image.
5. Result: `CGI::Session->new(...)` failed and returned undef, which triggered:
   - `die "Auth ERROR: Cannot get_session()"` in `C4/Auth.pm`.

Non-causes confirmed during diagnosis:

- Database connectivity was healthy (`C4::Context->dbh` and `SELECT 1` succeeded).
- `SessionStorage` syspref was set to `mysql`.
- `sessions` table existed in `koha_kohadev`.

---

## How the issue was detected and isolated

1. Collected repeated Apache CGI errors from Koha logs showing `Cannot get_session()`.
2. Traced the call path in source:
   - `C4/Auth.pm` -> `get_session()` -> `Koha::Session->get_session()`.
3. Reproduced session creation directly inside container with a focused Perl probe.
4. Captured low-level runtime error from `CGI::Session`:
   - `couldn't load CGI::Session::ID::md5: Can't locate Crypt/SysRandom.pm in @INC`
5. Verified this was the immediate blocker by testing module load directly.

---

## Modifications applied

### 1) Image dependency fix

File:

- `Dockerfile-Alpine`

Change:

- Added CPAN install step:
  - `RUN cpanm --notest Crypt::SysRandom`

Purpose:

- Ensure `CGI::Session::ID::md5` can initialize and generate session IDs.

### 2) Regression guard test

Files:

- `tests/test_dockerfile_perl_deps_static.sh` (new)
- `tests/run_all_tests.sh` (updated to include the new test suite)

Change:

- Added static checks ensuring both:
  - `perl-cgi-session` package remains present
  - `cpanm --notest Crypt::SysRandom` remains present in Dockerfile

Purpose:

- Prevent future image changes from reintroducing the same runtime failure.

### 3) Troubleshooting documentation update

File:

- `README.md`

Change:

- Added a new "Common 500 signatures and fixes" item for:
  - `Auth ERROR: Cannot get_session()`
- Included verification and recovery commands:
  - module-presence probe
  - rebuild + recreate flow

Purpose:

- Make operational diagnosis and recovery straightforward for future incidents.

---

## Validation performed

1. Rebuilt Koha image and recreated Koha container.
2. Confirmed module availability in container:
   - `perl -MCrypt::SysRandom -e 'print "ok\n"'`
3. Confirmed session creation success with direct probe:
   - `Koha::Session->get_session({})` returned `SESSION_OK`.
4. Confirmed endpoints healthy:
   - OPAC HTTP 200
   - Intranet HTTP 200
5. Ran full aggregate suite:
   - `bash tests/run_all_tests.sh`
   - Result: `59 passed, 0 failed, 0 skipped`
6. Post-fix log scan:
   - No new `Cannot get_session()` or `Auth ERROR` entries.

---

## Final outcome

Issue resolved.

The failure was caused by a missing runtime dependency (`Crypt::SysRandom`) required by Koha's CGI session ID backend. The dependency is now baked into the image, regression-tested in CI/local suite, documented in troubleshooting guidance, and validated with runtime and integration checks.
