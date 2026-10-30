# G4 — Ubuntu-data migration rehearsal

**Date:** 2026-10-30  
**Branch:** `phase`  
**Result:** **PASS for this version-matched rehearsal**, with one pre-existing source-data caveat. This does not close G5–G9 or approve production cutover.

## Outcome

An owner-approved, sanitized Koha database copy from the running Ubuntu-based
installation was imported into a new isolated MariaDB volume. The Alpine
production image was built from the exact Koha source commit used by the source
database. Koha started with explicit existing-data settings, ran
`updatedatabase.pl`, and became healthy without a fresh bootstrap or database
reset.

Baseline schema and row counts matched. Authenticated staff access, patron
lookup, MARCXML import and catalogue edit, controlled checkout/checkin,
background indexing, TLS, and search through the migrated Koha installation
were exercised. One malformed MARCXML record was found in the source and
remained present in the target; this was not introduced or modified by the
migration.

## Source authorization and provenance

- The source database was `koha-docker-db-1`, MariaDB
  `10.11.18-MariaDB-ubu2204`, on the existing source volume
  `koha-docker_koha-db-data`.
- The owner authorized a read-only export and confirmed that the data copy was
  sanitized for this rehearsal. The source container remained running and was
  not modified.
- All 295 source tables were InnoDB. The protected export used
  `mariadb-dump --single-transaction --quick --hex-blob --routines --triggers
  --events --databases koha_kohadev`, then gzip compression.
- The temporary dump was mode `0600`, in a mode-`0700` directory. SHA-256:
  `d50f33361574da71fa31edb1e228422208139edec8b51f3a061ea0451a204b68`.
- Source Koha was `26.06.00.003`, schema preference `26.0600003`, at commit
  `c355bb8574f62e4a04e774a65a6385feb9b858b0`. The source checkout was clean.

## Candidate image and isolation

- Image: `koha-alpine-g4:26.06.00.003-c355bb8`
- Image ID: `sha256:063ca6c26a9480ebecea54621b78e5c1a856819e3c49547f7c4b8bec0187943e`
- OCI version/revision labels: `26.06.00.003` /
  `c355bb8574f62e4a04e774a65a6385feb9b858b0`
- Compose project: `koha-g4-20261030`
- New project volumes:
  - `koha-g4-20261030_koha-db-data`
  - `koha-g4-20261030_koha-rabbitmq-data`
  - `koha-g4-20261030_opensearch-data`
- The Koha service had no host port bindings and no Koha source-checkout
  mount. Its only bind mounts were the OpenSearch CA and MariaDB TLS material.
  DB, broker, cache, and OpenSearch services used the isolated project network.
- The existing source container and source volume were left in place.

The database export-to-final-verification interval was approximately 36
minutes; this excludes the production image build and prior source
authorization/preparation.

## Configuration and asset reconciliation

The source `koha-conf.xml` was retained only in the protected rehearsal
workspace and was not mounted into the target. Alpine generated a target
configuration with new target DB/broker credentials, the target TLS settings,
and the isolated OpenSearch endpoint. The source had `SearchEngine=Elasticsearch`;
the old endpoint was replaced with the test-cluster hostname and CA. The source
uploads and plugins directories were empty, so no user-uploaded or plugin files
were omitted. This does not prove restoration of non-empty upload/plugin
directories or external OpenSearch/RabbitMQ production state.

## Reconciliation

Counts below were captured after database import and startup, before the
synthetic workflow fixture was added:

| Check | Source | Imported target |
|---|---:|---:|
| Koha schema preference | `26.0600003` | `26.0600003` |
| MariaDB version | `10.11.18-MariaDB-ubu2204` | `10.11.18-MariaDB-ubu2204` |
| Bibliographic records | 436 | 436 |
| Borrowers | 53 | 53 |
| Items | 961 | 961 |
| Branches | 12 | 12 |
| Tables | 295 | 295 |

After workflow tests, the isolated target contained one additional synthetic
bibliographic record and item. Source counts remained unchanged.

The selected source commit and Koha version matched the target image. Startup
ran `updatedatabase.pl`; the schema preference remained unchanged, as expected
for this version-matched rehearsal. A cross-version schema upgrade was not
tested.

## Runtime acceptance results

| Check | Result |
|---|---|
| Target Koha startup and health check | Pass; container healthy and startup completed |
| Staff authentication | Pass; copied superlibrarian password reset through Koha's patron API on the disposable target only; no credentials recorded |
| Authenticated REST API | Pass; authenticated patron-list request returned HTTP 200 |
| Patron lookup | Pass; authenticated staff request returned HTTP 200 |
| OPAC landing page | Pass; HTTP 200 |
| Source-record OPAC search | Pass; a migrated bibliographic record was found |
| MARCXML workflow | Pass; one synthetic record/item imported, then the record was edited through Koha's `C4::Biblio` API |
| Circulation | Pass; a controlled checkout and checkin completed through Koha's `C4::Circulation` API; no open test issue remained |
| Background processing | Pass; an `UpdateElasticIndex` job reached `finished`; both default and elastic-index workers were running and two RabbitMQ STOMP connections were active |
| OpenSearch | Pass; authenticated HTTPS returned HTTP 200, unauthenticated access returned HTTP 401, and the Koha rebuild command exited 0 |
| Search after rebuild | Pass; the edited synthetic record was found through OPAC search |
| MariaDB TLS | Pass; the Koha client connected with CA verification and negotiated TLS |
| Isolation | Pass; no host port bindings, no source-checkout mount, and target DB volume belonged to the G4 project |

The workflow fixture was created only in the disposable target and was removed
when the G4 project resources were cleaned.

## Source-data caveat

XML parsing found one malformed MARCXML row among the 436 source records and the
same single row in the imported target; the synthetic record parsed correctly.
The full index rebuild exited successfully but emitted 16 diagnostics
containing `PCDATA`. A migrated source record and the synthetic record remained
searchable, but the malformed source row may not be indexed. No source or target
record was repaired or deleted. The service owner should decide whether that
pre-existing record requires correction before a production migration.

## Cleanup and remaining gates

After evidence capture, only the G4 project containers, network, and project
volumes were removed. The protected temporary export/configuration workspace
was deleted. The source DB container and volume were verified untouched. The
candidate image is retained locally; no registry publication occurred.

After cleanup, `bash tests/run_all_tests.sh` passed **294 checks, 0 failed,
29 expected skips**. `git diff --check` and the G4 documentation-link check
also passed.

G4 passes for the recorded, version-matched data rehearsal, with the source
record-quality caveat above. G5 backup/restore/rollback, G6 cutover and volume
identity, G7 operational readiness, G8 independent operator walkthrough, and
G9 service-owner sign-off remain open.
