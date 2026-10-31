# 2026-10-31 — Session suspension note (G6 closed, G7 in progress)

## Status at suspension
| Gate | State | Commit |
|---|---|---|
| G5 backup and recovery | PASS (isolated rehearsal) | `18c2e43` |
| G6 volume identity and cutover | PASS (isolated rehearsal) | `42105c9` |
| G7 security and operations | PARTIAL, work **uncommitted** | none |
| G8, G9 | Open | none |

Nothing has been pushed. No containers, volumes or networks from the rehearsals remain. `koha-docker-db-1`, its volume and the G4 candidate image `koha-alpine-g4:26.06.00.003-c355bb8` are untouched.

## Uncommitted G7 changes
- `stack-alpine.sh`:
  - `reject_demo_credentials`: prod mode refuses `demo-*`, `change_me*`, `password` and `koha`. Override: `KOHA_ALLOW_DEMO_CREDENTIALS=yes`.
  - Prod startup banner no longer prints the staff password.
  - Prod mode warns that the demo CA key `files-alpine/mariadb-ssl/ca-key.pem` is tracked in Git.
- `files-alpine/run.sh`: renders the `__DB_USE_TLS__` and `__DB_TLS_*__` placeholders in `koha-conf.xml` (default `KOHA_DB_USE_TLS=no`). It only takes effect after an image rebuild.
- `env/demo-credentials.env`: new file with public demo values (all prefixed `demo-`).
- `tests/test_stack_sh_static.sh`: 50/0. The full suite passes.
- Docs: the acceptance matrix (scope clarification and G7 pointer), the roadmap, `Phase-F-release-operations.md`, and `2026-10-31 — G7 security and operations audit.md`.

## Owner clarification
The credentials in tracked env files are public demo defaults for test sessions, not secrets. G7's secret criteria apply to a real production deployment with its own untracked env file.

## Open decisions and work for G7
1. **Koha to MariaDB TLS.** The image's `DBD::mysql` 4.052 is linked against MariaDB Connector/C and rejects `mysql_ssl=1` ("Enforcing SSL encryption is not supported"). Options:
   - rebuild `DBD::mysql` against MySQL client libraries;
   - move to `DBD::MariaDB` and patch Koha;
   - accept plaintext on the private `kohanet` bridge for a single-host deployment.
   Do not set `require_secure_transport=ON` until a TLS-capable driver is in place. It would break Koha.
2. Move the CA private key out of the mounted TLS directory, and tighten key file modes (currently 0644).
3. Add log rotation (`logging` options) to the compose files.
4. Check OpenSearch TLS and client authentication on a live endpoint.
5. Owner inputs: monitoring target, alert ownership, retention and capacity numbers, and the base and service image update policy and owner.
6. Rebuild the image to carry the `run.sh` change, then re-verify.

## Next steps
Resolve the TLS decision, then finish items 2–6 and commit G7. After that, G8 (independent operator walkthrough) and G9 (owner sign-off).

## Reminders
- Use isolated, disposable projects with fresh volumes. Never touch the source DB or the shared global networks `frontend`, `knonikl` and `opensearch-36_osearch`.
- Commit only when asked, with the Co-authored-by trailer.
- Test runners: `bash tests/test_stack_sh_static.sh` and `bash tests/run_all_tests.sh`.
