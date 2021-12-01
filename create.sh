#!/usr/bin/env bash

docker volume create nextcloud_data
docker volume create nextcloud_db_data
docker volume create nextcloud_caddy_data

docker compose up -d --build