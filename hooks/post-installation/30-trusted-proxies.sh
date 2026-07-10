#!/bin/bash
# post-installation hook: reproduce reverse-proxy config from the previous instance.
# Runs once on a fresh install.
#
# These four proxy IPs mirror values already in .env (kept in sync by hand):
#   index 0/2 = edge proxy hop  -> CADDY_TRUSTED_PROXIES ("172.30.0.2/32 fd00::2/128")
#   index 1/3 = this stack Caddy -> CADDY_IP / CADDY_IP_V6
# Both hops must be listed so Nextcloud trusts the X-Forwarded-* chain end to end.
# Hooks already run as www-data (entrypoint uses `su -p www-data`), so call occ directly.
set -euo pipefail

occ() { php /var/www/html/occ "$@"; }

proxies=(
  172.30.0.2   # edge proxy (IPv4)
  172.20.0.10  # stack Caddy = CADDY_IP
  fd00::2      # edge proxy (IPv6)
  fd20:20::10  # stack Caddy = CADDY_IP_V6
)

i=0
for p in "${proxies[@]}"; do
  echo "trusted_proxies[$i] = $p"
  occ config:system:set trusted_proxies "$i" --value="$p"
  i=$((i + 1))
done

# Reverse-proxy companions (TLS terminates at the edge, so Nextcloud must be told
# the real external scheme/URL rather than inferring it from the FastCGI request).
occ config:system:set overwriteprotocol --value=https
occ config:system:set overwrite.cli.url --value=https://cloud.brunowillenborg.de
