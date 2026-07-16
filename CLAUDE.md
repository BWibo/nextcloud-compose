# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Docker Compose stack to run a self-hosted Nextcloud. There is no application source code here — the value lives in:

- `docker-compose.yml` — the four-service stack (Caddy, Postgres, Redis, Nextcloud-FPM + cron)
- `caddy/Caddyfile` — TLS termination + Nextcloud-specific routing/headers/forbidden paths
- `.env` + `nextcloud.env` — all tunables (versions, secrets, PHP limits, Nextcloud `NC_*` config keys)
- `nextcloud/Dockerfile` — extends the upstream `nextcloud:${VERSION}` image (currently only adds `ffmpeg`)
- `backup/` — standalone restic-based backup scripts run from cron on the host (not part of the compose stack)

## Common commands

```bash
# Bring the stack up (creates required external volumes first)
./create.sh                  # docker volume create x3 + docker compose up -d --build

# Foreground/dev variant (compose up without -d)
./create_interactive.sh

# Pull new images and rebuild after bumping versions in .env
./update.sh                  # docker compose pull && docker compose up -d --build

# Recreate Caddy only (after editing caddy/Caddyfile)
./caddy_update.sh            # docker compose up -d (recreates changed services)

# Wipe everything (DESTRUCTIVE — removes the three named volumes)
./purge.sh
./reset.sh                   # purge.sh + create.sh

# Run an occ command inside the running app container
docker exec -i --user 33 nextcloud-app-1 ./occ <command>
# Example: manually process the preview generation queue (normally drained
# every 5 min by the previewgenerator app's built-in background job via cron)
docker exec -i --user 33 nextcloud-app-1 ./occ preview:pre-generate -vv
```

There are no tests, linters, or build steps beyond `docker compose build`.

## Architecture notes that aren't obvious from one file

### Service topology
All services share a single user-defined bridge network `net` whose subnet is fixed via `DOCKER_NET_SUBNET` (default `172.20.0.0/24`). Caddy gets a **fixed** IPv4 address (`CADDY_IP`, default `172.20.0.10`) so it can be referenced as a trusted proxy from Nextcloud's perspective; all other containers get random IPs from the same subnet via Docker IPAM. Both `CADDY_IP` and `DOCKER_NET_SUBNET` use `:?` in compose, so the stack will refuse to start if either is unset.

### Volume sharing between Caddy and Nextcloud
`nextcloud_data` is mounted **rw** in `app` and `cron`, and **ro** in `caddy` at `/var/www/html`. This is intentional: Caddy serves static assets directly from disk via `file_server` while routing PHP requests to `app:9000` over FastCGI. Don't change the ro mount on Caddy — Nextcloud writes are owned by the app container.

### Cron container reuses the app image
The `cron` service uses `volumes_from: app` and `entrypoint: /cron.sh`. It must use the **same image** as `app` (same `NEXTCLOUD_VERSION` and same custom Dockerfile) — both build from `./nextcloud` with `no_cache: true`.

### Caddyfile structure
The site block (`{$TLS_DOMAINS}`) does several Nextcloud-specific things that look unusual but are required:

- `redir /.well-known/carddav|caldav → /remote.php/dav/ 301` and `redir /.well-known/* → /index.php{uri} 301` — implements Nextcloud's service-discovery contract.
- `respond /.well-known/acme-challenge 404` and `/.well-known/pki-validation 404` — explicit 404s so they don't get caught by the wildcard redirect above.
- `@forbidden` block — denies direct HTTP access to internal Nextcloud paths (`/config/*`, `/data/*`, `/lib/*`, `/.htaccess`, etc.) that would otherwise be served by `file_server`.
- `Strict-Transport-Security` is enabled by default. **If you uncomment `acme_ca` for Let's Encrypt staging, you must also comment out the HSTS header** — there is a comment to that effect in the file. Same applies if switching to `tls internal` for LAN/self-signed.
- `CADDY_TLS` env var is intentionally substituted as a raw directive line (`{$CADDY_TLS}`) so users can swap between ACME, `tls internal`, or `tls /certs/...`.

### Configuration layering for Nextcloud
Nextcloud accepts config via three channels, all wired up here:

1. Top-level Compose env vars (`NEXTCLOUD_TRUSTED_DOMAINS`, `POSTGRES_*`, `REDIS_HOST`, `PHP_MEMORY_LIMIT`, `PHP_UPLOAD_LIMIT`) — consumed by upstream `nextcloud:fpm` entrypoint.
2. `nextcloud.env` env_file — uses the `NC_<key>` prefix convention (e.g. `NC_default_phone_region=DE`) which the upstream image translates into `config.php` keys. See the file's header comment for links to the upstream PR and config reference.
3. Manual `occ config:system:set` from inside the container for anything not covered above.

### Fresh-install hooks (app pre-install)
`hooks/post-installation/` is bind-mounted **ro** into the `app` service at `/docker-entrypoint-hooks.d/post-installation`. The upstream entrypoint runs executable `*.sh` scripts there **once, on a fresh install only** (empty `nextcloud_data` volume), after Nextcloud is installed but before first run. `10-install-apps.sh` uses this to `occ app:install` a user-maintained list of apps. It does **not** re-run on restart or upgrade, and it never fires on `cron` (that service overrides the entrypoint with `/cron.sh`). Hooks run as root, so `occ` is invoked via `su ... www-data`.

### Imaginary (optional preview backend)
Defined in a separate `imaginary.yml` compose file because it's intended to be deployed as a Swarm stack on its own (`endpoint_mode: vip`, multiple replicas). To enable: deploy that stack, uncomment the `img` external network in `docker-compose.yml`, uncomment the `img` network on `app` and `cron`, and uncomment `NC_preview_imaginary_url` in `nextcloud.env`.

### Backups
`backup/*.sh` are **host-side** scripts (run from root crontab, not from compose). They `docker exec` into `nextcloud-app-1` to toggle maintenance mode and dump the DB, then run `restic` against either local disk or Azure Blob storage. Container name `nextcloud-app-1` is hard-coded in these scripts — it depends on the compose project name being `nextcloud` (set via `name:` at the top of `docker-compose.yml`).

## Conventions to keep

- Every variable referenced in `docker-compose.yml` uses the `${VAR:?VAR not set}` form. Preserve this when adding new env vars — it makes misconfiguration fail loudly at `compose up` time instead of silently at runtime.
- Version pinning lives **only** in `.env` (`NEXTCLOUD_VERSION`, `POSTGRES_VERSION`). `caddy:alpine` and `redis:alpine` float on purpose with `pull_policy: always`.
- `nextcloud/Dockerfile` is built `no_cache: true` so apt-get pulls the latest `ffmpeg` on every rebuild.
