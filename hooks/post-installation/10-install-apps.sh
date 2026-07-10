#!/bin/bash
# Runs once, on a fresh Nextcloud install only (nextcloud/docker post-installation
# hook). Installs the apps listed below. Apps persist in the nextcloud_data volume,
# so this does not re-run on restart/upgrade.
#
# App IDs are the identifiers shown by `occ app:list` / in the app store URL.
#
# Hooks already run as www-data (the entrypoint invokes them via `su -p www-data`),
# so occ is called directly — no inner `su`.
set -euo pipefail

occ() { php /var/www/html/occ "$@"; }

# One app ID per line. Leave the array empty to install nothing.
apps=(
  # bookmarks
  calendar
  contacts
  cospend
  # deck
  groupfolders
  memories
  recognize
  previewgenerator
)

for app in "${apps[@]}"; do
  # Idempotent: skip if already listed (enabled or disabled) — app:install errors otherwise.
  if occ app:list | grep -qE "^[[:space:]]+- ${app}:"; then
    echo "post-installation hook: app already present, skipping '${app}'"
  else
    echo "post-installation hook: installing app '${app}'"
    occ app:install --force "${app}"
  fi
done
