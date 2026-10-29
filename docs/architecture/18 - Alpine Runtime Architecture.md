---
title: "Alpine Runtime Architecture"
tags: [architecture, alpine, compose, production, volumes, release]
---
# Alpine Runtime Architecture

This page describes the current implementation in this repository. For production
release, backup, and rollback procedures, see
[Phase F release operations](../Alpine-migration/Phase-F-release-operations.md).

## Runtime shape

```text
Browser
  ├── direct HTTP :8080 (OPAC) / :8081 (staff)
  └── optional Traefik routing and TLS
         │
         ▼
      koha container ───── db (MariaDB 10.11)
         │                 memcached (1.6-alpine)
         ├──────────────── rabbitmq (STOMP + management)
         └──────────────── OpenSearch cluster (separate Compose project)
```

`docker-compose-alpinekoha.yml` defines Koha, MariaDB, Memcached, and RabbitMQ.
OpenSearch and Traefik are orchestrated from their own Compose directories by
`stack-alpine.sh`. The Koha service also joins the external networks needed for
those optional integrations.

The current Dockerfile's default runtime base is Alpine 3.20 (`ALPINE_VERSION`
build argument). Do not infer Alpine behavior from the historical Ubuntu
architecture pages in this directory.

## Development and production images

`Dockerfile-Alpine` defines distinct `dev-runtime` and `prod-runtime` targets:

- **Development:** Koha source is copied into the development image at build time
  and bind-mounted from `SYNC_REPO` when running. The dev target includes the
  development toolchain.
- **Production:** the image fetches Koha from `KOHA_RELEASE_GIT_URL` at the
  required `KOHA_RELEASE_REF`, builds its assets, and includes the source and
  resolved Git revision. `docker-compose.prod.yml` overrides the development
  source mount, so runtime uses the baked source.

The production image publishes OCI title, version, source URL, and requested
revision labels. `/usr/share/koha/source-revision` records the resolved commit;
use that file to verify what was actually built when the requested ref is a tag.

## Ports and routing

Koha binds host ports `8080` (OPAC) and `8081` (staff) in the main Compose file.
Those are separate from Traefik's configurable listener ports. The service
listens on container ports `8080` and `8081`; do not use the historical Ubuntu
docs' `8000` / `8443` values as Koha ports. Compose labels route OPAC and staff
hosts through Traefik when the proxy is enabled.

## Persistence and project names

MariaDB and RabbitMQ use named Compose volumes (`koha-db-data` and
`koha-rabbitmq-data`). Docker scopes their actual names by the Compose project.
The default production project is version-specific:
`koha-prod-<version-slug>`. Consequently, changing Koha versions without
overriding the project name selects a different set of volumes.

Set `KOHA_PROD_PROJECT` to a validated, stable lower-case Compose project name
when production releases should use the same MariaDB and RabbitMQ volumes.
Keep that value unchanged across build, start, backup, and restore commands.
The default remains version-specific when the variable is unset.

OpenSearch data and generated TLS material are stored outside these two named
volumes. The built-in backup archives runtime environment files and a MariaDB
dump; it does not capture RabbitMQ volume contents, OpenSearch data, certificates,
or other host assets. Protect and back up those separately when required.

## Entrypoint and health

The Alpine image runs `/usr/local/bin/run.sh`, which prepares the Koha instance
and starts the required runtime services. Compose health depends on Plack status,
its Unix socket, and successful local HTTP requests to both Koha endpoints.
The container drops all Linux capabilities by default and adds only the
explicitly configured runtime allowlist in `docker-compose-alpinekoha.yml`.

## Source of truth

Use the repository's [README](../../README.md), `Dockerfile-Alpine`,
`docker-compose-alpinekoha.yml`, `docker-compose.prod.yml`, and
`stack-alpine.sh` for current behavior. The other pages in this directory are
retained as legacy context and should not override those files.
