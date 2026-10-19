# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Docker Compose stack to run a self-hosted Nextcloud. There is no application source code here. The value lives in:

- `docker-compose.yml`: the stack (Caddy, Postgres, Redis, Nextcloud-FPM `app` + `cron`; `go-vod` commented out)
- `caddy/Caddyfile`: TLS termination + Nextcloud-specific routing/headers/forbidden paths
- `.env` (gitignored, copied from the tracked `.env.example`) + `nextcloud.env`: all tunables (versions, secrets, PHP limits, network, Nextcloud `NC_*` config keys)
- `nextcloud/Dockerfile`: extends upstream `nextcloud:${NEXTCLOUD_VERSION}`; adds `ffmpeg` and `zz-disable-opcache-jit.ini` (OPcache JIT segfaults php-fpm on ARM64/Raspberry Pi 5; the `zz-` prefix must sort after `opcache-recommended.ini`)
- `hooks/`: upstream entrypoint lifecycle hooks (see below)
- `backup/`: host-side restic + volume backup scripts (not part of the compose stack)

## Common commands

```bash
cp .env.example .env         # first time; then edit domain, e-mail, passwords, # REPLACE values

./create.sh                  # docker volume create x3 + docker compose up -d --build
./create_interactive.sh      # same, foreground
./update.sh                  # docker compose pull && docker compose up -d --build (after bumping versions in .env)
./caddy_update.sh            # docker compose up -d (after editing Caddyfile or CADDY_* vars)

# DESTRUCTIVE: removes the three named volumes
./purge.sh
./reset.sh                   # purge.sh + create.sh

# occ inside the running app container
docker exec -i --user 33 nextcloud-app-1 ./occ <command>

# Validate compose interpolation without starting anything
docker compose config -q
```

There are no tests, linters, or build steps beyond `docker compose build`.

## Updating versions

Standard process when asked to update the stack. Steps 2 and 3 each end at a user gate.

### 1. Check for new releases

For each pinned component, find the highest stable SemVer release on GitHub, then confirm that its image tag is **already published on Docker Hub** with an `arm64` image (the production host is a Raspberry Pi 5). If the release exists but the image doesn't, report it as "released, image pending" and don't bump.

| `.env.example` var | Latest release | Docker Hub tag |
|---|---|---|
| `NEXTCLOUD_VERSION` (`X.Y.Z-fpm`) | `gh api "repos/nextcloud/server/releases?per_page=50" --jq '[.[] \| select(.prerelease == false and .draft == false) \| .tag_name] \| sort_by(ltrimstr("v") \| split(".") \| map(tonumber)) \| reverse \| .[0]'` | `nextcloud:X.Y.Z-fpm` |
| `POSTGRES_VERSION` (`N-alpine`) | `gh api "repos/postgres/postgres/tags?per_page=100" --jq '[.[].name \| select(test("^REL_[0-9]+_[0-9]+$"))] \| .[0]'`. Only a new major `N` matters, because `N-alpine` floats minor versions | `postgres:N-alpine` |

Don't use `releases/latest` for Nextcloud: it returns the most recently *published* release, which is often a backport on an older branch (e.g. `v33.0.10` while 35.x is current).

Docker Hub: `curl -s https://hub.docker.com/v2/repositories/library/<image>/tags/<tag>` returns 404 if the tag doesn't exist. Otherwise check `.images[].architecture` for `arm64` with `jq`.

`caddy:alpine` and `redis:alpine` float on purpose. Nothing to check.

### 2. Bump `.env.example`

- **Patch/minor:** update the value in `.env.example` and add a `CHANGELOG.md` `[Unreleased]` → `Changed` entry. Remind the user to update their gitignored `.env` by hand.
- **Major (Nextcloud or Postgres):** don't edit anything. Report the bump and **wait for confirmation**. Nextcloud can only upgrade one major at a time. A Postgres major needs the dump/restore runbook in README "Database migration".

### 3. Review the upstream reference example

This stack follows `nextcloud/docker`'s [`.examples/docker-compose/with-nginx-proxy/postgres/fpm/`](https://github.com/nextcloud/docker/tree/master/.examples/docker-compose/with-nginx-proxy/postgres/fpm). nextcloud/docker has no per-version tags, so changes are tracked against the baseline commit below.

```bash
gh api "repos/nextcloud/docker/commits?path=.examples/docker-compose/with-nginx-proxy/postgres/fpm&since=<baseline commit date>" \
  --jq '.[] | .sha[0:10] + " " + .commit.committer.date + " " + (.commit.message | split("\n")[0])'
gh api "repos/nextcloud/docker/commits/<sha>" --jq '.files[] | select(.filename | startswith(".examples/docker-compose/with-nginx-proxy/postgres/fpm/")) | .filename + "\n" + .patch'
```

Report each change, mapped to its counterpart here:

| Upstream | Here |
|---|---|
| `compose.yaml` | `docker-compose.yml` |
| `db.env` | `.env.example` |
| `web/nginx.conf`, `web/Dockerfile` | `caddy/Caddyfile`, translated from nginx to Caddy. For example: `location ~ ^/(?:build\|tests\|config\|...)` → `@forbidden`; `fastcgi_param` → `php_fastcgi { env ... }`; `add_header` → `header`; `.well-known` rewrites → `redir` |
| `proxy/` (nginx-proxy + acme companion) | No counterpart, since Caddy terminates TLS itself. Only relevant if the change touches headers, body size or timeouts |

Mark changes that don't apply here (nginx-only mechanics such as resolver re-resolution). **Stop after the report.** Write a migration plan only if the user asks for one. When porting anything, the no-private-domains/IPs convention still applies.

After the user has seen the report, update this line to the newest reviewed commit:

Last reviewed upstream commit: `5c23d91182` (2026-03-26T23:15:51Z, "Update postgres volume for 18+ (#2556)")

## Architecture notes that aren't obvious from one file

### Network and trusted proxies
All services share one dual-stack bridge network `net` (`DOCKER_NET_SUBNET` + `DOCKER_NET_SUBNET_V6`). Caddy gets **fixed** addresses (`CADDY_IP`, `CADDY_IP_V6`) so Nextcloud can list it as a trusted proxy; other containers get IPAM-assigned addresses. Trust is configured in two places that must agree:

- Caddy trusts the upstream edge proxy via `CADDY_TRUSTED_PROXIES` (global `trusted_proxies static ... ` + `trusted_proxies_strict`).
- Nextcloud's `trusted_proxies` must list **both** hops (edge proxy and stack Caddy). This is set by `hooks/post-installation/30-trusted-proxies.sh`, whose IPs are kept in sync with `.env` **by hand**.

### Volume sharing between Caddy and Nextcloud
`nextcloud_data` is mounted **rw** in `app` (and `cron` via `volumes_from: app`) and **ro** in `caddy` at `/var/www/html`. Caddy serves static files directly via `file_server` and sends PHP to `app:9000` over FastCGI. Keep Caddy's mount ro.

### Postgres volume path
`nextcloud_db_data` is mounted at `/var/lib/postgresql`, **not** `/var/lib/postgresql/data`. Postgres 18+ images default `PGDATA` to `/var/lib/postgresql/<major>/docker`; the old path would silently `initdb` into an anonymous volume. Major-version upgrades need dump/restore. The runbook is the "Database migration" section of `README.md`. Nextcloud connects with its own role (`dbuser` in `config.php`, e.g. `oc_admin`), not `POSTGRES_USER`, which is why the runbook carries roles over with `pg_dumpall --globals-only`.

### Cron container reuses the app image
`cron` uses `entrypoint: /cron.sh` and must use the **same image** as `app`. Both build from `./nextcloud` with the same `NEXTCLOUD_VERSION` and `no_cache: true`.

### Caddyfile structure
- Snippets are chosen at parse time by env var: `import {$CADDY_DEBUG_SNIPPET}` (`debug_headers_off`/`debug_headers_on`, the latter adds a JSON access log and a `/caddy-debug-headers` endpoint) and `import {$CADDY_ACCESS_LOG_SNIPPET}` (`access_log_off`/`access_log_on`). The env values must exactly match snippet names. Add a new toggle as an `_off` no-op snippet plus an `_on` snippet, wired through `.env.example` and the compose `caddy.environment` block.
- `{$CADDY_TLS}` is substituted as a raw directive line, so it can be empty (ACME), `tls internal`, or `tls /certs/...` (`./certs` is mounted ro at `/certs`).
- `/.well-known/carddav|caldav` → `/remote.php/dav/`, and `/.well-known/*` → `/index.php{uri}`: Nextcloud service discovery. The explicit 404s for `acme-challenge`/`pki-validation` keep those out of the wildcard redirect.
- `@forbidden` blocks internal paths (`/config/*`, `/data/*`, `/lib/*`, `/occ`, ...) that `file_server` would otherwise serve.
- HSTS is on by default. **If you enable the staging `acme_ca` (or use `tls internal`), comment out the HSTS header.**

### Configuration layering for Nextcloud
1. Compose env vars on `app` (`NEXTCLOUD_TRUSTED_DOMAINS` from `DOMAIN`, `POSTGRES_*`, `REDIS_HOST`, `PHP_*`), read by the upstream entrypoint at install time.
2. `nextcloud.env` env_file with `NC_<key>` vars, which the upstream image maps onto `config.php` keys at runtime.
3. `occ config:system:set`, either run manually or scripted in `hooks/`.

### Lifecycle hooks
`./hooks` is mounted ro at `/docker-entrypoint-hooks.d` in `app`. The upstream entrypoint runs executable `*.sh` files in lexical order, **as www-data** (via `su -p www-data`), so scripts call `php /var/www/html/occ` directly with no `su`. They never run in `cron`, which overrides the entrypoint.

- `post-installation/`: runs **once**, on a fresh install (empty `nextcloud_data`). It installs apps and reproduces trusted domains/proxies, preview config, Memories places, Recognize models, and repair.
- `post-upgrade/`: runs after **every** version upgrade. Most entries are **symlinks** into `post-installation/` so the same script serves both. Those scripts must therefore be idempotent and non-fatal on re-run (see the guards in `50-memories-places.sh` and `60-recognize-models.sh`).
- Domains and proxy IPs in hooks are placeholders at `# REPLACE` markers, substituted locally and never committed.

### Imaginary (optional preview backend)
`imaginary.yml` is a separate stack (Swarm-style, `endpoint_mode: vip`, replicas). To enable it: deploy that stack, uncomment the `img` external network and the `img` network on `app` and `cron`, and uncomment `NC_preview_imaginary_url` in `nextcloud.env`.

### Backups
`backup/nextcloud_backup_restic.sh` runs from the host's root crontab. It enables maintenance mode via `docker exec`, runs `pg_dump`, takes restic snapshots to a local repo and to Azure Blob (separate `include_*/exclude_*` files per target), then disables maintenance mode. `volume_backup.sh` makes cold tar backups of named volumes and refuses to run while a container uses the volume. Container names (`nextcloud-app-1`, `nextcloud-db-1`) and the network `nextcloud_net` are hard-coded and depend on the compose project `name: nextcloud`.

## Conventions to keep

- **No private domains or IPs in the repo, ever.** This repo is public. Never commit real hostnames, domains, email addresses, or infrastructure IPs (LAN, VPN, edge proxies, etc.). Use placeholders: `localhost`, `example.com`/`example.org` (RFC 2606) for domains; `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24` (RFC 5737) for IPv4; `2001:db8::/32` (RFC 3849) for IPv6. The bridge defaults (`172.20.0.0/24`, `172.20.0.10`, `fd20:20::/64`, `fd20:20::10`) are fine. Site-specific values belong in `.env` (untracked) or get substituted locally at `# REPLACE` markers.
- Every variable in `docker-compose.yml` uses `${VAR:?VAR not set}` (`CADDY_TLS` is the deliberate exception, since empty means ACME). New env vars go into both `docker-compose.yml` and `.env.example`.
- Version pinning lives only in `.env`/`.env.example` (`NEXTCLOUD_VERSION`, `POSTGRES_VERSION`). `caddy:alpine` and `redis:alpine` float on purpose with `pull_policy: always`.
- `nextcloud/Dockerfile` is built `no_cache: true` so apt-get pulls the latest `ffmpeg` on every rebuild.
- User-facing changes get an entry under `[Unreleased]` in `CHANGELOG.md` (Keep a Changelog format).
