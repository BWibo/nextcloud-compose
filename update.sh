#!/usr/bin/env bash

# 1. Change image versions in .env

# Update
docker compose pull
docker compose up -d --build