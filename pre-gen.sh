#!/usr/bin/env bash

echo "--- $(date --utc +%FT%TZ) ----------------------------------------" >>$HOME/pre-generate.log 2>&1
docker exec -i --user 33 nextcloud-app-1 ./occ preview:pre-generate -vv >>$HOME/pre-generate.log 2>&1
