# 2026-09-07 - MariaDB TLS CA self-heal and zero-state certificate bootstrap

Status: Completed
Severity: High (bootstrap blocker during fresh setup / certificate drift)
Scope: stack orchestration, TLS bootstrap, docs cleanup

---

## Context

The Alpine Koha stack depends on MariaDB TLS material under `files-alpine/mariadb-ssl/`.
The helper command `./stack-alpine.sh tls-client-cert` was originally designed to re-use the client cert pair, but it still assumed the local CA already existed and was valid.

That assumption broke in real-world zero-state and drifted-state scenarios:

1. `ca-cert.pem` was missing, stale, or no longer usable.
2. `KOHA_DB_ROOT_PASSWORD` had been changed as required in `env/.env`.
3. The helper aborted immediately with a failure such as:
   - `Missing CA certificate: .../files-alpine/mariadb-ssl/ca-cert.pem`
4. The stack could not proceed with the MariaDB TLS trust chain even though the certificate directory was still in the repo structure.

This was a bootstrap blocker: the helper was validating a prerequisite that was not guaranteed to exist or be valid.

---

## Root cause

The previous implementation in `stack-alpine.sh` did this:

- required `ca-cert.pem` and `ca-key.pem` to already exist
- failed immediately if they were missing or unreadable
- only generated the client certificate pair, assuming the project CA was already trustworthy

In other words, it was not actually robust against the condition where a clean repo checkout or a rotated environment had no viable CA material at all.

---

## Fix implemented

The fix was applied in `stack-alpine.sh` and makes the helper self-heal from zero:

1. Validates the local CA certificate and private key.
2. If either file is missing or invalid, generates a brand-new CA locally.
3. Regenerates the MariaDB server certificate if it is missing or not signed by that CA.
4. Regenerates the Koha client certificate if it is missing or not signed by the CA.
5. Rewrites the runtime env vars in `env/.env`:
   - `KOHA_DB_TLS_CA_CERTIFICATE=/etc/mysql/ssl/ca-cert.pem`
   - `KOHA_DB_TLS_CLIENT_CERTIFICATE=/etc/mysql/ssl/client-cert.pem`
   - `KOHA_DB_TLS_CLIENT_KEY=/etc/mysql/ssl/client-key.pem`
6. Supports the forced-reset path with `--force-client-tls-regen`.

The helper now behaves as a true bootstrap and recovery mechanism instead of a narrow client-cert re-use utility.

---

## Documentation correction

The SSL Certificate Management section in `README.md` was also corrected so it no longer states or implies that a working CA already exists in the repo.

The documentation now clearly describes the actual behavior:

- the helper is the source of truth
- it can generate the full CA + server + client chain from scratch
- it is safe to run in a fresh setup or after cert drift
- the README reflects the real zero-state recovery workflow

---

## Validation

Verified with:

```bash
cd /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-alpine
bash -n stack-alpine.sh && ./stack-alpine.sh tls-client-cert
```

Result: the helper now creates a fresh CA, server cert, and client cert instead of aborting on the missing CA file.

---

## Operational follow-up

If a local TLS set is broken or stale, the safe recovery path is now:

```bash
cd /path/to/koha-alpine
./stack-alpine.sh tls-client-cert
./stack-alpine.sh restart --no-logs
```

This restores the certificate chain deterministically without requiring any pre-existing CA bundle to be in working order.

---

## Follow-up issue discovered during live startup

After the CA/bootstrap fix, another real startup problem surfaced during a fresh dev bootstrap:

1. `docker volume ls` still showed the persistent MariaDB volume `koha-alpine_koha-db-data`.
2. The DB container was running but rejecting the configured root password.
3. The MariaDB logs also showed a second blocker before authentication:
   - `SSL error: Unable to get private key from '/etc/mysql/ssl/server-key.pem'`
4. This meant the real fix required both of these actions:
   - remove the stale MariaDB volume so the old root password is not reused, and
   - ensure the generated server/client private keys are readable by the `mysql` process.

### Recovery flow that worked

```bash
cd /media/expansion/DEVELOPMENT/KOHA-DOCKER-SOLUTIONS/koha-alpine

docker compose -f docker-compose-alpinekoha.yml down -v --remove-orphans
docker volume rm koha-alpine_koha-db-data || true
chmod 644 files-alpine/mariadb-ssl/server-key.pem files-alpine/mariadb-ssl/client-key.pem
./stack-alpine.sh tls-client-cert
./stack-alpine.sh start --image-mode dev
```

### Why this mattered

- `KOHA_DB_ROOT_PASSWORD` is tied to the initial MariaDB data volume.
- Changing it later does not rotate the stored root password in that volume.
- The server TLS key also must be readable by the `mysql` process or MariaDB aborts before DB auth is even possible.

This issue is now documented as a required recovery step for any user who changes the password after the initial volume was created or who sees SSL setup failures during startup.
