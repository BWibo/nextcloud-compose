<h1 align="center">Nextcloud using Docker compose, Postgres and Caddy reverse proxy</h1>

## :zzz: TL;DR

1. Set domain and eMail address in `.env`

    ```bash
    # General settings
    # Domain used for trusted domains (config.php)
    DOMAIN=localhost

    # Domains for TLS certificates. Items separated by comma + space: ", "
    TLS_DOMAINS="localhost, nextcloud.local"
    ADMIN_EMAIL=a@b.de
   ```

2. Create volumes

    ```bash
    docker volume create nextcloud_caddy_data
    docker volume create nextcloud_data
    docker volume create nextcloud_db_data
    ```

3. Deploy Nextcloud

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

Adapt `.env` for your requirements.

```bash
# General settings
# Domain used for trusted domains (config.php)
DOMAIN=localhost

# Domains for TLS certificates. Items separated by comma + space: ", "
TLS_DOMAINS="localhost, nextcloud.local"
ADMIN_EMAIL=a@b.de

# Nextcloud
NEXTCLOUD_VERSION=27.1.2-fpm
NEXTCLOUD_ADMIN_USER=admin      # Change username and password!!
NEXTCLOUD_ADMIN_PASSWORD=changeMe

# Nextcloud PHP settings
PHP_MEMORY_LIMIT=1024M
PHP_UPLOAD_LIMIT=16G

# DB
POSTGRES_VERSION=14-alpine
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

## :chart_with_upwards_trend: Imaginary support

Follow the steps to use a imaginary stack as your image preview provider.

1. Deploy imaginary stack: `docker stack deploy -c imaginary.yml imaginary`
2. Uncomment imaginary network in `docker-compose.yml`
3. Uncomment imaginary settings in `nextcloud.env`
4. Add Imaginary to preview provider in `config.php`
5. Re-deploy the stack `docker compose up -d --build`
