# Nextcloud using Docker compose, Postgres and Caddy reverse proxy

## Quick start

### Create volumes

```bash
docker volume create nextcloud_caddy_data
docker volume create nextcloud_data
docker volume create nextcloud_db_data
```

### Configuration

Adapt `.env` for your requirements.

```bash
# General settings
# Domain used for trusted domains (config.php)
DOMAIN=localhost

# Domains for TLS certificates. Items separated by comma + space: ", "
TLS_DOMAINS="localhost, nextcloud.local"
ADMIN_EMAIL=a@b.de

# Nextcloud
NEXTCLOUD_VERSION=27.0.2-fpm
NEXTCLOUD_ADMIN_USER=admin      # Change username and password!!
NEXTCLOUD_ADMIN_PASSWORD=changeMe

# DB
POSTGRES_VERSION=14-alpine
POSTGRES_DB=nextcloud           # Change username and password!!
POSTGRES_USER=nextcloud
POSTGRES_PASSWORD=changeMe
```

### Run nextcloud

```bash
docker compose up -d --build
```

Your instance will be available after a couple of seconds unter https://localhost or https://DOMAIN, as specified in `.env`.

## Imaginary support

Follow the steps to use a imaginary stack as your image preview provider.

1. Deploy imaginary stack: `docker stack deploy -c imaginary.yml imaginary`
2. Uncomment imaginary network in `docker-compose.yml`
3. Uncomment imaginary settings in `nextcloud.env`
4. Add Imaginary to preview provider in `config.php`
5. Restart the deployment
