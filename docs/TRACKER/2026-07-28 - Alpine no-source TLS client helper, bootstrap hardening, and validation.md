# 2026-07-28 - Alpine no-source TLS client helper, bootstrap hardening, and validation

Status: Completed
Severity: High (bootstrap blocker + endpoint outage + no-source constraint)
Scope: stack orchestration, TLS material workflow, test adaptation, documentation

---

## User constraints and goal

The objective was to stabilize the Alpine Koha stack and endpoint/test workflows while respecting a strict rule:

1. Do not modify Koha source files in the nested `koha` repository.
2. Keep remediation in repo-level orchestration/config/docs/tests.

---

## Hurdles solved in this cycle

1. `stack-alpine.sh` clone path failure (`mkdir: Permission denied`).
   - Root cause: non-writable `SYNC_REPO` parent path from env.
   - Resolution: corrected local path and re-ran bootstrap.

2. Endpoint checks failed while stack was running.
   - Root cause: test scripts still targeted legacy `koha-docker` assumptions.
   - Resolution: adapted Alpine test suite and endpoint harness to use:
     - `docker-compose-alpinekoha.yml`
     - dynamic instance/container naming
     - Alpine-specific paths and behavior.

3. Koha schema stayed empty (`systempreferences` missing), HTTP returned installer/maintenance/500.
   - Root cause: bootstrap DB connection failures in TLS flow.
   - Intermediate blockers identified:
      - unresolved TLS placeholders
      - empty TLS client fields in DBI paths
     - unsupported certificate when server cert was used as client cert.

4. Source patch vs no-source requirement conflict.
   - A temporary source-level fix in `koha/C4/Installer.pm` was identified as effective,
     but disallowed by user rule.
   - Resolution: reverted source change and moved to infra-only strategy.

5. No-source TLS strategy initially failed under CGI runtime.
   - Root cause: generated client key existed but was unreadable by CGI/DBI context.
   - Resolution: generated proper client cert/key pair signed by local CA and ensured
     readable bind-mount permissions.

6. Final stability confirmation.
   - DB schema populated (table count healthy, `systempreferences` exists).
   - OPAC and Intranet both return HTTP 200.
   - Endpoint script and full test suite pass.

---

## Permanent implementation (no Koha source edits)

### 1) New integrated helper in stack manager

File: `stack-alpine.sh`

Added:

1. Command: `tls-client-cert`
   - Generates or reuses MariaDB client TLS cert/key.
   - Auto-writes env keys:
     - `KOHA_DB_TLS_CLIENT_CERTIFICATE=/etc/mysql/ssl/client-cert.pem`
     - `KOHA_DB_TLS_CLIENT_KEY=/etc/mysql/ssl/client-key.pem`

2. Flags:
   - `--prepare-db-client-tls`
     - Runs helper before `start`, `restart`, or `build`.
   - `--force-client-tls-regen`
     - Regenerates client cert/key even if present.

3. Internal behavior:
   - Validates CA files in `files-alpine/mariadb-ssl/`.
   - Creates client cert/key signed by local CA.
   - Applies read permissions required by runtime DBI/CGI context.
   - Updates `env/.env` in-place via script helper.

### 2) TLS material updates (infrastructure only)

Files under `files-alpine/mariadb-ssl/`:

1. Added `client-ext.cnf`.
2. Added `client-cert.pem`.
3. Added `client-key.pem`.

### 3) Documentation updates

1. `README.md`
   - Added helper command usage (`tls-client-cert`).
   - Added `--prepare-db-client-tls` and force-regenerate examples.
   - Documented no-source TLS workflow and generated files.

2. `docs/TRACKER` (this file)
   - Captures the chronology and final architecture decision.

---

## Validation snapshot

Representative final state after no-source path:

1. DB schema: populated (`systempreferences` present).
2. HTTP endpoints:
   - `http://localhost:8080` -> 200
   - `http://localhost:8081` -> 200
3. Endpoint suite: `./test-endpoints.sh` passed key checks.
4. Full suite: `bash tests/run_all_tests.sh` -> all suites passed.

---

## Operational note

If Koha source updates or local SSL files are reset, rerun:

```bash
./stack-alpine.sh tls-client-cert --force-client-tls-regen
./stack-alpine.sh restart --prepare-db-client-tls --no-logs
```

This restores the no-source bootstrap path deterministically.
