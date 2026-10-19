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
| `web/nginx.conf`, `web/Dockerfile` | `caddy/Caddyfile`, translated from nginx to Caddy. For example: `location ~ ^/(?:build\|tests\|config\|...)` → `@forbidden`; `fastcgi_param` → `php_fastcgi { env ... }` (shared via the `(nextcloud_fastcgi)` snippet); `add_header` → `header`; `.well-known` block → `route /.well-known/*`; the `rewrite` inside `location ~ \.php(?:$\|/)` → `@php_not_entrypoint`; `map $arg_v $asset_immutable` → `map {query.v} {asset_immutable}`; `fastcgi_request_buffering on` → `request_buffers` on the `@body_without_length` `php_fastcgi` |
| `proxy/` (nginx-proxy + acme companion) | No counterpart, since Caddy terminates TLS itself. Only relevant if the change touches headers, body size or timeouts |

The admin manual's [`nginx-root.conf.sample`](https://github.com/nextcloud/documentation/blob/master/admin_manual/installation/nginx-root.conf.sample) is the second reference. It evolves independently of nextcloud/docker (it carried the `composer.json`/`package.json`/`core/shipped.json` 404 rule first), so diff it as well; its `# Version` header line identifies the revision. Last reviewed: `Version 2026-06-09`.

Mark changes that don't apply here (nginx-only mechanics such as resolver re-resolution). **Stop after the report.** Write a migration plan only if the user asks for one. When porting anything, the no-private-domains/IPs convention still applies.

After the user has seen the report, update this line to the newest reviewed commit:

Last reviewed upstream commit: `5c23d91182` (2026-03-26T23:15:51Z, "Update postgres volume for 18+ (#2556)")

## Architecture notes that aren't obvious from one file

### Network and trusted proxies
All services share one dual-stack bridge network `net` (`DOCKER_NET_SUBNET` + `DOCKER_NET_SUBNET_V6`). Caddy publishes 80, 443 and 443/udp (HTTP/3; Caddy advertises it via `Alt-Svc`, so the UDP port has to be reachable or clients probe it in vain before falling back to TCP). Caddy gets **fixed** addresses (`CADDY_IP`, `CADDY_IP_V6`) so Nextcloud can list it as a trusted proxy; other containers get IPAM-assigned addresses. Trust is configured in two places that must agree:

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
- `/.well-known/*` is handled in a `route` block on purpose. Caddy evaluates `redir` before `respond` regardless of their position in the file, so outside a `route` the `acme-challenge`/`pki-validation` 404s would never beat the catch-all `redir * /index.php{uri}`. `carddav`/`caldav` → `/remote.php/dav/`.
- Only Nextcloud's entry points (`index`, `remote`, `public`, `cron`, `status`, `ocs/v[12]`, `ocs-provider/*`, `core/ajax/update`, `updater/*`, `*/richdocumentscode(_arm64)/proxy`) reach php-fpm directly. `@php_not_entrypoint` rewrites every other `*.php` request to `/index.php{uri}`, mirroring the `rewrite` inside nginx's `location ~ \.php(?:$|/)` (the `.htaccess` pretty-URL rule). Without it, php-fpm executes any `.php` file in the webroot and leaks PHP fatal errors.
- There are two `php_fastcgi` blocks, both importing the `(nextcloud_fastcgi)` snippet (`front_controller_active`, `modHeadersAvailable`). The first one matches `@body_without_length` (no `Content-Length`, non-GET/HEAD/OPTIONS) and adds `request_buffers {$CADDY_CHUNKED_BODY_BUFFER}`: Caddy's FastCGI transport answers 411 for bodies of unknown length beyond its 4 KiB default buffer, which breaks chunked WebDAV uploads (macOS Finder, Cyberduck, DAVx5, ...). The buffer is RAM per concurrent chunked upload (in-memory only, no disk spooling; a 500 MiB upload peaks at ~1.5x while the buffer grows), so the size lives in `.env`; bodies larger than it still get 411. `CADDY_GOMEMLIMIT` (Go's `GOMEMLIMIT`) is the companion knob: without it Go keeps the freed buffers resident for minutes (measured 2.3 GiB after two 500 MiB uploads), with it resident memory stays around the limit. Requests that carry `Content-Length` (web UI, desktop/mobile clients) are streamed and never buffered. `modHeadersAvailable` tells Nextcloud (`lib/OC.php`) not to emit its own copies of the security headers.
- Cache-Control: `@assets`/`@fonts` match by extension and require `file` (real files only, like nginx's `try_files $uri`). `map {query.v} {asset_immutable}` appends `, immutable` only for cache-busted `?v=` URLs (nginx `map $arg_v`).
- `@forbidden` blocks internal directories with and without trailing slash, every root dotfile (`/.*`; `.well-known` is routed before it), prefix rules (`/occ*`, `/db_*`, `/console*`, ...) and dependency metadata (`composer.json`, `composer.lock`, `package.json`, `package-lock.json`, `core/shipped.json`). `file_server` would otherwise serve all of them. Multiple `path` lines inside one named matcher are OR'ed; mixing matcher types would AND them.
- `log_skip @assets`/`@fonts`/`/robots.txt` keeps existing static files out of the optional access log (nginx `access_log off`); missing assets still log because the matchers require `file`. `respond /204 204` (and `/index.php/204`) answers the clients' connectivity check without php-fpm (`.htaccess` `RedirectMatch 204`).
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
