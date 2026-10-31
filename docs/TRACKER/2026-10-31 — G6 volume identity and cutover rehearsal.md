# 2026-10-31 — G6 volume identity and cutover rehearsal

**Result: PASS (isolated rehearsal).**

## Hazard
The production Compose project defaults to `koha-prod-<version-slug>`. Changing the release version with `KOHA_PROD_PROJECT` unset selects an empty volume pair, which looks like a fresh deployment. In addition, `restart` dropped the database without any prompt, and `start` accepted a generic `yes`.

## Changes (`stack-alpine.sh`)
- `guard_prod_volume_identity`: refuses to start when the project has no DB volume but a sibling `koha-prod-*` project does. `KOHA_ACCEPT_NEW_VOLUMES=yes` overrides it.
- `verify_running_volume_identity`: after `start`, `restart` and `restore`, checks that the DB and RabbitMQ containers mount exactly `<project>_koha-db-data` and `<project>_koha-rabbitmq-data`.
- `confirm_prod_destructive`: on a populated production DB, `start` and `restart` without `--no-fresh-db`, and `reset`, require the exact project name to be typed.
- New `volumes` command. `start` and `stop` honor `KOHA_MANAGE_SHARED_SERVICES=no`.
- 5 new static assertions (46/0).

## Rehearsal (project `koha-prod-26-06-00-003`, fresh volumes, synthetic secrets, no shared networks)
| Step | Observed |
|---|---|
| S1 first deployment, version A | Project `koha-prod-26-06-00-003`; healthy; marker biblio imported (biblios=1). |
| S2 version B, `KOHA_PROD_PROJECT` unset, `--no-fresh-db` | **Refused**, naming the sibling project. No B containers or volumes were created, and A's volumes were untouched. |
| S3 version B with `KOHA_PROD_PROJECT` pinned to A's exact project | Same volumes reused. Running container reports `KOHA_IMAGE=26.06.00.004`. biblios=1 and the marker is present. Mounts verified. |
| S4 `start`/`restart` without `--no-fresh-db` (empty answer, wrong answer) and `reset` (wrong answer) | All cancelled with "Nothing was changed". biblios=1, volumes intact, container healthy. |
| S5 positive control: `restart` with the exact name typed | Wipe proceeds (biblios=0). Mounts are verified afterwards, so the guard blocks accidents without blocking a deliberate action. |

## Caveats
- The "upgrade" reused the G4 candidate image under two version labels. It tested naming and volume selection, not a real version change. Real data migration was already proven in G4.
- A first script run was started twice and the two runs overlapped. A stray container was removed and S5 was re-run on its own. S1–S4 output was consistent across both runs.
- The helper still logs "bootstrap marker missing" in prod with `--no-fresh-db`. This is harmless noise, because the container inspects the DB itself.

## Cleanup
The project, volumes, network and `/tmp` workspace were removed. `koha-docker-db-1`, its volume and the G4 image were untouched. The global networks were not created or modified.
