# 2026-10-31 — G7 security and operations audit

**Result: PARTIAL.** Technical findings are fixed or documented below. TLS between Koha and MariaDB is a known limitation, and several items need an owner decision.

## Scope clarification (owner)
The credentials in the tracked env files are public demo defaults for test sessions, not secrets. G7's secret-handling criteria apply to a real production deployment with its own untracked env file.

## Verified
| Check | Result |
|---|---|
| Image labels, env and history (G4 candidate image) | No passwords, tokens or secrets. Labels carry only OCI title, version, revision and source. No `ARG ...PASS/SECRET/TOKEN` in `Dockerfile-Alpine`. |
| Koha container | Drops all capabilities and adds back CHOWN, DAC_OVERRIDE, FOWNER, KILL, NET_BIND_SERVICE, SETGID and SETUID. It has a compose healthcheck (plack status, socket, OPAC and staff HTTP). |
| MariaDB server TLS | `have_ssl=YES`, TLS 1.2 and 1.3. The server certificate SAN includes `db`, `localhost` and `127.0.0.1`. The application user connects over TLS with and without a client certificate (including `--ssl-verify-server-cert`). |
| Backup files | Created with mode 0600 (G5). |

## Findings and actions
1. **Demo credentials could run production.** Fixed: `reject_demo_credentials` refuses `demo-*`, `change_me*`, `password` and `koha` in prod mode. The override is `KOHA_ALLOW_DEMO_CREDENTIALS=yes`. `env/demo-credentials.env` holds the public demo values.
2. **The startup banner printed the staff password.** Fixed: in prod mode it now says the password comes from the env file.
3. **`koha-conf.xml` TLS placeholders were never substituted.** The literal `__DB_USE_TLS__`, `__DB_TLS_CA_CERTIFICATE__` and similar strings stayed in the file, so Koha's own DB connection did not use TLS even though the server offers it. `run.sh` now renders them from `KOHA_DB_USE_TLS` (default `no`, so existing behaviour is unchanged), `KOHA_DB_TLS_CA_CERTIFICATE`, `KOHA_DB_TLS_CLIENT_CERTIFICATE` and `KOHA_DB_TLS_CLIENT_KEY`. This only takes effect in a rebuilt image. The prod image bakes in its own `run.sh`, because the dev bind mounts are absent in prod mode.
4. **Koha cannot enforce TLS to MariaDB on this Perl stack (known limitation).** With TLS enabled, bootstrap failed with `SSL connection error: Enforcing SSL encryption is not supported`. The image's `DBD::mysql` 4.052 is linked against MariaDB Connector/C, which rejects `mysql_ssl=1`. Server-side `require_secure_transport=ON` rejected plain connections (error 1045) but would also break Koha, so I did not ship that option.
   - **Current posture:** Koha to DB traffic is plaintext on the private `kohanet` bridge. The DB is not published to the host (only 8080/8081 are).
   - **Options:**
     - Rebuild `DBD::mysql` against MySQL client libraries.
     - Add `DBD::MariaDB` and patch Koha.
     - Accept the risk for a single-host deployment.
   - This needs an owner decision.
5. **TLS keys, including the CA private key, are tracked and world-readable (0644).** The whole `files-alpine/mariadb-ssl/` directory, including `ca-key.pem`, is mounted into the Koha container. Prod mode now warns about this. Production should use private TLS material, with the CA key kept out of the mounted directory.
6. **The container runs as root and has no log rotation.** The compose files set no `logging` limits. Docker's default `json-file` driver has no cap.

## Not yet done (G7 remaining)
- Owner items: alert ownership, monitoring target, log retention and capacity numbers, and the image and base-image update policy and owner.
- A decision on TLS option 4.
- Moving or protecting the CA key (finding 5) and adding log-rotation settings (finding 6).
- Rebuilding the image to carry finding 3, then verifying.
- OpenSearch TLS and client authentication on a live endpoint (not exercised in this session).

## Method
The isolated rehearsals used disposable projects with synthetic credentials, with no shared networks and no touch to `koha-docker-db-1`. All of them were removed afterwards.
