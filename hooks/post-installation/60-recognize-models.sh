#!/bin/bash
# Download Recognize ML models (~1.2 GB). Runs on fresh install AND after every upgrade
# (symlinked into hooks/post-upgrade).
#
# `recognize:download-models` deletes models/ and re-downloads the archive matched to
# the installed recognize version. To stay idempotent AND refresh after a recognize
# upgrade, we skip only when models for the *current* recognize version are already
# present, tracked via an app-config marker (survives upgrades; no app-signature side
# effects, unlike a stray file inside the app dir). Non-fatal.
#
# Hooks already run as www-data (entrypoint uses `su -p www-data`), so call occ directly.
set -euo pipefail

occ() { php /var/www/html/occ "$@"; }

models_dir=/var/www/html/custom_apps/recognize/models
want=$(occ config:app:get recognize installed_version 2>/dev/null || true)
have=$(occ config:app:get recognize models_downloaded_version 2>/dev/null || true)

if [ -n "$want" ] && [ "$want" = "$have" ] \
  && [ -d "$models_dir" ] && [ -n "$(ls -A "$models_dir" 2>/dev/null)" ]; then
  echo "hook: recognize models for $want already present; skipping"
elif occ recognize:download-models; then
  occ config:app:set recognize models_downloaded_version --value="$want"
else
  echo "WARN: recognize:download-models failed; re-run: occ recognize:download-models" >&2
fi
