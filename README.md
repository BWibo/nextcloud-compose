# Nextcloud using Docker compose, Postgres and Caddy reverse proxy

## Quick start

### Create volumes

```bash
docker volume create nextcloud_caddy_data
docker volume create nextcloud_data
docker volume create nextcloud_db_data
```

### Configuration

Adapt `.env` for your requirements:

```bash
# General settings
DOMAIN=localhost        # FQDN of your host or localhost for local testing.
ADMIN_EMAIL=a@b.de      # eMail address for Let's Encrypt auto SSL certificate account.

# Nextcloud
NEXTCLOUD_VERSION=24.0.4-fpm
NEXTCLOUD_ADMIN_USER=admin          # Change username and password!!
NEXTCLOUD_ADMIN_PASSWORD=admin

# DB
POSTGRES_VERSION=14-alpine
POSTGRES_PASSWORD=nextcloud
POSTGRES_DB=nextcloud	            # Change username and password!!
POSTGRES_USER=nextcloud
```

### Run nextcloud

```bash
docker compose up -d
```

Your instance will be available after a couple of seconds unter https://localhost or https://DOMAIN, as specified in `.env`.
