#!/bin/bash
# post-upgrade hook: add DB schema that a new Nextcloud/app version introduced.
# All idempotent (add-missing-* only add what's absent). The admin overview flags these.
#
# Hooks already run as www-data (entrypoint uses `su -p www-data`), so call occ directly.
set -euo pipefail

occ() { php /var/www/html/occ "$@"; }

occ db:add-missing-indices
occ db:add-missing-columns
occ db:add-missing-primary-keys
