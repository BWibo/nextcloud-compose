#!/bin/bash
# post-installation hook: reproduce `trusted_domains` from the previous instance.
# Runs once on a fresh install. Overwrites indices deterministically so the result
# is identical regardless of what NEXTCLOUD_TRUSTED_DOMAINS seeded at install time.
# Hooks already run as www-data (entrypoint uses `su -p www-data`), so call occ directly.
set -euo pipefail

occ() { php /var/www/html/occ "$@"; }

# One domain per line, in the desired index order (index 0 = localhost).
domains=(
  localhost
  cloud.brunowillenborg.de
  www.cloud.brunowillenborg.de
  bwibo.duckdns.org
)

i=0
for d in "${domains[@]}"; do
  echo "trusted_domains[$i] = $d"
  occ config:system:set trusted_domains "$i" --value="$d"
  i=$((i + 1))
done
