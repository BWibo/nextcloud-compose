#!/usr/bin/env bash

# Cleanup
docker compose down -v

docker volume rm nextcloud_data
docker volume rm nextcloud_db_data
docker volume rm nextcloud_caddy_data
