#!/bin/bash
# Run repair steps, including the expensive ones. Runs on fresh install AND after every
# upgrade (symlinked into hooks/post-upgrade). Idempotent: repair steps are safe to re-run.
#
# Hooks already run as www-data (entrypoint uses `su -p www-data`), so call occ directly.
set -euo pipefail

php /var/www/html/occ maintenance:repair --include-expensive
