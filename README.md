<h1 align="center">Nextcloud using Docker compose, Postgres and Caddy reverse proxy</h1>

## :zzz: TL;DR

1. Create your `.env` from the template (`.env` is gitignored, so your domain and
   secrets stay out of the repo)

    ```bash
    cp .env.example .env
    ```

2. Set at least the domain, admin e-mail and the two `changeMe` passwords in `.env`

    ```bash
    # General settings
    # Domain used for trusted domains (config.php)
    DOMAIN=localhost

    # Domains for TLS certificates. Items separated by comma + space: ", "
    TLS_DOMAINS="localhost, nextcloud.local"
    ADMIN_EMAIL=a@b.de

    NEXTCLOUD_ADMIN_PASSWORD=changeMe
    POSTGRES_PASSWORD=changeMe
   ```

3. Create volumes

    ```bash
    docker volume create nextcloud_caddy_data
    docker volume create nextcloud_data
    docker volume create nextcloud_db_data
    ```

4. Deploy Nextcloud

    ```bash
    docker compose up -d --build
    ```

## :rocket: Basic usage

### Create volumes

```bash
docker volume create nextcloud_caddy_data
docker volume create nextcloud_data
docker volume create nextcloud_db_data
```

> **Note:** To use a local folder on your server (bind mount) for Nextcloud data,
> adapt the volume settings in `docker-compose.yml`.
>
> ```yaml
> # ...
> volumes:
>   nextcloud_caddy_data:
>     external: true
>
>   # Comment out and use code below to use a bind mount for data folder
>   nextcloud_data:
>     external: true
>
>   # Use this, if using bind mount
>   # nextcloud_data:
>   #   driver: local
>   #   driver_opts:
>   #     type: none
>   #     o: bind
>   #     device: "${PWD}/data"
>
>   nextcloud_db_data:
>     external: true
>   # ...
> ```

### Configuration

If you haven't already, create your `.env` from the template, then adapt it for your
requirements (`.env` is gitignored — the tracked template is `.env.example`):

```bash
cp .env.example .env
```

```bash
# General settings
# Domain used for trusted domains (config.php)
DOMAIN=localhost

# Domains for TLS certificates. Items separated by comma + space: ", "
TLS_DOMAINS="localhost, nextcloud.local"
ADMIN_EMAIL=a@b.de

# Caddy TLS directive settings
# https://caddyserver.com/docs/caddyfile/directives/tls
# Use this for self-signed certificates, e.g. in your LAN
# CADDY_TLS="tls internal"

# Usage of own certificates
# CADDY_TLS="tls /certs/fullchain.pem /certs/key.key"

# Nextcloud
NEXTCLOUD_VERSION=27.1.3-fpm
NEXTCLOUD_ADMIN_USER=admin      # Change username and password!!
NEXTCLOUD_ADMIN_PASSWORD=changeMe

# Nextcloud PHP settings
PHP_MEMORY_LIMIT=1024M
PHP_UPLOAD_LIMIT=16G

# DB
POSTGRES_VERSION=18-alpine
POSTGRES_DB=nextcloud           # Change username and password!!
POSTGRES_USER=nextcloud
POSTGRES_PASSWORD=changeMe

# Docker settings
DOCKER_LOGGING_MAX_SIZE=5m
DOCKER_LOGGING_MAX_FILE=3
```

### Run Nextcloud

```bash
docker compose up -d --build
```

Your instance will be available after a couple of seconds unter https://localhost or https://DOMAIN, as specified in `.env`.

## :arrows_counterclockwise: Database migration

Postgres major-version upgrades (e.g. 16 → 18) cannot reuse the old data
directory — the cluster has to be dumped, the volume recreated, and the dump
restored into the new version. The steps below are generic; substitute the
new version for `18` where needed.

> **Note (Postgres 18+ image change):** the official image now declares
> `VOLUME /var/lib/postgresql` and defaults `PGDATA` to
> `/var/lib/postgresql/<major>/docker` (to allow side-by-side data dirs for
> `pg_upgrade`). The old `/var/lib/postgresql/data` mount would silently
> `initdb` into an anonymous volume. `docker-compose.yml` in this repo already
> mounts `nextcloud_db_data:/var/lib/postgresql` — don't change it back.
> See [docker-library/postgres#1370](https://github.com/docker-library/postgres/issues/1370).

> **Note (DB role):** Nextcloud does **not** connect as the bootstrap
> `POSTGRES_USER` — at install time it created its own role (typically
> `oc_<adminuser>`, e.g. `oc_admin`) with a generated password, stored in
> `config.php` as `dbuser` / `dbpassword`. The restore below must run **as
> that role** so it owns all restored objects; otherwise the app fails with
> `Role "oc_admin" does not exist` after the migration.

Preparation: pick a time outside the nightly restic backup window and make
sure there is enough free disk space for the dump and the volume tar. Read
the credentials Nextcloud actually uses from `config.php`, then export them
for the commands below:

```bash
docker exec --user 33 nextcloud-app-1 grep -E "'db" /var/www/html/config/config.php

export POSTGRES_PASSWORD=<value from .env>          # bootstrap superuser
export NC_DBUSER=<dbuser from config.php>           # e.g. oc_admin
export NC_DBPASSWORD=<dbpassword from config.php>
DUMPDIR=/media/myhdd/pg-upgrade   # any host folder with enough space
```

If `dbname` in `config.php` is not `nextcloud`, substitute it accordingly
below.

1. **Pre-flight checks** — instance healthy, current version, DB size:

    ```bash
    docker exec -i --user 33 nextcloud-app-1 ./occ status
    docker exec nextcloud-db-1 postgres --version
    docker exec nextcloud-db-1 psql -U nextcloud -c "SELECT pg_size_pretty(pg_database_size('nextcloud'));"
    ```

2. **Enable maintenance mode** — no writes during the dump:

    ```bash
    docker exec -i --user 33 nextcloud-app-1 ./occ maintenance:mode --on
    ```

3. **Logical dump** with the *new* version's client (dumping an older server
   with a newer `pg_dump` is supported):

    ```bash
    mkdir -p "$DUMPDIR"
    docker run -i --rm --network nextcloud_net \
      -v "$DUMPDIR":/data \
      -e PGPASSWORD="$POSTGRES_PASSWORD" \
      --entrypoint pg_dump postgres:18-alpine \
      -h db -U nextcloud -d nextcloud -F c -f /data/nextcloud-pre18.dump
    ```

4. **Stop the stack** (volumes are external and survive this):

    ```bash
    docker compose down
    ```

5. **Cold volume backup** as an extra safety net besides the dump and the
   restic snapshots (see `backup/README.md`):

    ```bash
    NEXTCLOUD_VOLUME_BACKUP_DIR=/media/myhdd/volume-backups ./backup/volume_backup.sh nextcloud_db_data
    ```

    Verify the archive exists and has a plausible size before continuing.

6. **Update versions** — pull the repo changes and set the new version in
   `.env` (gitignored, edit manually):

    ```bash
    git pull
    # .env: POSTGRES_VERSION=18-alpine
    ```

7. **Recreate the DB volume** (safe: dump + tar + restic all exist):

    ```bash
    docker volume rm nextcloud_db_data
    docker volume create nextcloud_db_data
    ```

8. **Start only the db** and wait until healthy — the fresh `initdb` creates
   only the bootstrap superuser and an empty `nextcloud` database from the
   `POSTGRES_*` env vars, **not** the app role from `config.php`:

    ```bash
    docker compose up -d db
    watch docker compose ps db   # wait for "healthy"
    ```

9. **Recreate the app role and its database** (as the bootstrap superuser;
   drop the DB *before* creating the role, so nothing can connect and block
   the drop):

    ```bash
    docker exec -it nextcloud-db-1 psql -U nextcloud -d postgres -c "DROP DATABASE nextcloud;"
    docker exec -it nextcloud-db-1 psql -U nextcloud -d postgres -c "CREATE ROLE $NC_DBUSER LOGIN PASSWORD '$NC_DBPASSWORD';"
    docker exec -it nextcloud-db-1 psql -U nextcloud -d postgres -c "CREATE DATABASE nextcloud OWNER $NC_DBUSER;"
    ```

    Since Postgres 15 the `public` schema belongs to the database owner, so
    owning the database is all the app role needs.

10. **Restore the dump, connecting as the app role.** With `--no-owner`,
    restored objects are owned by the connecting role — which is what we
    want, since Nextcloud's migrations must own its tables:

    ```bash
    docker run -i --rm --network nextcloud_net \
      -v "$DUMPDIR":/data \
      -e PGPASSWORD="$NC_DBPASSWORD" \
      --entrypoint pg_restore postgres:18-alpine \
      -h db -U "$NC_DBUSER" -d nextcloud --no-owner -j 4 /data/nextcloud-pre18.dump
    ```

    A few warnings like `COMMENT ON EXTENSION` or "already exists" are
    harmless; errors on tables or data are not.

11. **Start the full stack** and disable maintenance mode (the flag lives in
    `config.php` on `nextcloud_data`, so it survived):

    ```bash
    ./update.sh
    docker exec -i --user 33 nextcloud-app-1 ./occ maintenance:mode --off
    ```

12. **Verify**:

    ```bash
    docker exec nextcloud-db-1 psql -U nextcloud -c "SELECT version();"
    docker exec -i --user 33 nextcloud-app-1 ./occ status
    ```

    Then log in via the web UI, check Administration → Overview for DB
    warnings, and upload/download a file. The next morning, check that the
    restic backup ran clean against the new version.

13. **Optional:** a freshly restored cluster has no planner statistics — run
    `ANALYZE` once:

    ```bash
    docker exec nextcloud-db-1 psql -U nextcloud -c 'ANALYZE;'
    ```

### Rollback

If anything fails before the instance is verified, go back to the old version:

```bash
docker compose down
# .env: revert POSTGRES_VERSION to the old value
# git: check out the matching docker-compose.yml (volume mount!) if it changed

docker volume rm nextcloud_db_data
docker volume create nextcloud_db_data
docker run --rm -v nextcloud_db_data:/target -v /media/myhdd/volume-backups:/backup \
  alpine tar -xzf /backup/nextcloud_db_data_<timestamp>.tar.gz -C /target

docker compose up -d
docker exec -i --user 33 nextcloud-app-1 ./occ maintenance:mode --off
```

## :chart_with_upwards_trend: Imaginary support

Follow the steps to use a imaginary stack as your image preview provider.

1. Deploy imaginary stack: `docker compose -f imaginary.yml up -d` or `docker stack deploy -c imaginary.yml imaginary`
2. Uncomment imaginary network in `docker-compose.yml`
3. Uncomment imaginary settings in `nextcloud.env`
4. Add Imaginary to preview provider in `config.php`
5. Re-deploy the stack `docker compose up -d --build`

## :file_folder: Store data in host folder

To store the nextcloud data in a host folder, e.g. to make backups easier, uncomment
this section in `docker-compose.yml`:

```yaml
volumes:

# ...

  # Comment out and use code below to use a bind mount for data folder
  # nextcloud_data:
  #   external: true

# Use this, if using bind mount
  nextcloud_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: "${PWD}/data"
```

Create the folder on the host, in this example: ``mkdir data``.
Then you're ready to deploy the stack `docker compose up -d --build`.
