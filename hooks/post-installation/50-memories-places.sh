#!/bin/bash
# Set up Memories reverse-geocoding (planet database). Runs on fresh install AND after
# every upgrade (symlinked into hooks/post-upgrade).
#
# Idempotent: `memories:places-setup` skips when already set up (use -f to force a
# re-download). Non-fatal: a failed/timed-out download must not brick startup.
#
# Hooks already run as www-data (entrypoint uses `su -p www-data`), so call occ directly.
set -euo pipefail

occ() { php /var/www/html/occ "$@"; }

echo "hook: memories:places-setup"
occ memories:places-setup -n \
  || echo "WARN: memories:places-setup failed; re-run: occ memories:places-setup" >&2
