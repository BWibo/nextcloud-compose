# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `backup/volume_backup.sh`: cold backup of named Docker volumes to compressed tar archives, as a safety net for destructive maintenance such as Postgres major upgrades. Refuses to run while a container is using the volume.
- README section "Database migration" documenting the dump → recreate volume → restore procedure (and rollback) for Postgres major-version upgrades.
- Caddyfile: only Nextcloud's entry points (`index.php`, `remote.php`, `public.php`, `cron.php`, `status.php`, `ocs/v1|2.php`, `ocs-provider/`, `core/ajax/update.php`, `updater/`, Collabora proxy) are executed directly; every other `*.php` request is routed through the front controller, as in the upstream nginx config. Previously php-fpm executed any PHP file in the webroot (and leaked PHP fatal errors).
- Caddyfile: request bodies without `Content-Length` (chunked WebDAV uploads from macOS Finder, Cyberduck/Mountain Duck, DAVx5, ...) are buffered in RAM so php-fpm receives a length (nginx `fastcgi_request_buffering on`). Such uploads above 4 KiB previously failed with `411 Length Required`. The buffer size is the new `CADDY_CHUNKED_BODY_BUFFER` variable (`.env.example`: `512MiB`; it is memory per concurrent chunked upload, larger bodies still get 411). The new `CADDY_GOMEMLIMIT` (`.env.example`: `1GiB`) sets Go's soft memory limit for Caddy so the freed buffers are returned to the OS instead of staying resident. **Add both to your `.env`**, the stack refuses to start without them.
- Caddyfile: `/204` and `/index.php/204` (the clients' connectivity check) are answered by Caddy without php-fpm, as in `.htaccess`.
- Caddyfile: existing static assets, fonts and `robots.txt` are excluded from the optional access log (`log_skip`), as in the nginx reference.
- `docker-compose.yml`: publish `443/udp` so the HTTP/3 (QUIC) that Caddy already advertises via `Alt-Svc` is actually reachable.
- Caddyfile: Microsoft WebDAV client (`DavClnt`) requests for `/` are redirected to `/remote.php/webdav/` (rule from `.htaccess` / nginx).
- Caddyfile: `composer.json`, `composer.lock`, `package.json`, `package-lock.json`, `core/shipped.json`, all root dotfiles and the bare internal directories (`/config`, `/lib`, ...) now return 404 (admin manual nginx config, June 2026).

### Changed

- Bumped Nextcloud to 35.0.2 (`NEXTCLOUD_VERSION=35.0.2-fpm` in `.env.example`).
- Upgraded Postgres to 18 (`POSTGRES_VERSION=18-alpine` in `.env.example`). Existing instances must migrate via dump/restore — see the new "Database migration" section in the README.
- Moved the `db` service volume mount from `/var/lib/postgresql/data` to `/var/lib/postgresql`: the Postgres 18+ images declare `VOLUME /var/lib/postgresql` and default `PGDATA` to `/var/lib/postgresql/<major>/docker`, so the old mount path would silently `initdb` into an anonymous volume (docker-library/postgres#1370).

- Split the restic backup exclude list into separate files for the local and Azure targets (`backup/exclude_local.txt`, `backup/exclude_azure.txt`), configured via the new `NEXTCLOUD_RESTIC_EXCLUDE_FILE_LOCAL` and `NEXTCLOUD_RESTIC_EXCLUDE_FILE_AZURE` environment variables, replacing the shared `backup/exclude.txt` and `NEXTCLOUD_RESTIC_EXCLUDE_FILE`.
- Split the restic backup include list into separate files for the local and Azure targets (`backup/include_local.txt`, `backup/include_azure.txt`), configured via the new `NEXTCLOUD_RESTIC_INCLUDE_FILE_LOCAL` and `NEXTCLOUD_RESTIC_INCLUDE_FILE_AZURE` environment variables, replacing the shared `backup/include.txt` and `NEXTCLOUD_RESTIC_INCLUDE_FILE`.
- Caddyfile: static asset caching aligned with `.htaccess`/nginx: `public, max-age=15778463` (~6 months) for the full upstream extension list instead of `max-age=360` for four extensions, `immutable` added for cache-busted `?v=` URLs, fonts (`otf`, `woff`, `woff2`) cached for 7 days.
- Caddyfile: pass `modHeadersAvailable=true` to php-fpm so Nextcloud no longer sends its own copies of the security headers that Caddy sets.
- Caddyfile: removed the legacy `X-Download-Options` and `X-XSS-Protection` headers (dropped upstream; `X-XSS-Protection` is deprecated), and compress `application/wasm`.

### Fixed

- Disabled OPcache JIT in the Nextcloud image to stop php-fpm workers from crashing with SIGSEGV during app install/upgrade on ARM64 hosts such as the Raspberry Pi 5 (upstream PHP aarch64 JIT bug; see nextcloud/docker#2576).
- Fixed the backup script ignoring the built-in default restic repository paths when `NEXTCLOUD_RESTIC_REPO_LOCAL` or `NEXTCLOUD_RESTIC_REPO_AZURE` are unset.
- Caddyfile: `/.well-known/acme-challenge/*` and `/.well-known/pki-validation/*` now return 404 as intended. The `respond ... 404` lines never matched because Caddy evaluates `redir` before `respond`, so these paths were redirected to `/index.php/...`.
- Caddyfile: the font `Cache-Control` header was never applied (`path /core/fonts` matched only that exact path).
- Caddyfile: removed a mangled `encode` match entry (`application/atom+xmlapplication/javascript*`).

[Unreleased]: https://github.com/BWibo/nextcloud-compose/commits/HEAD
