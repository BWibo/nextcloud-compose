#!/bin/bash
# Set up Memories reverse-geocoding (planet database). Runs on fresh install AND after
# every upgrade (symlinked into hooks/post-upgrade).
#
# `memories:places-setup` has NO idempotent flag: on a fresh instance (geomCount == 0)
# it downloads+imports the planet DB; once set up it insists on --force to drop and
# re-download, which fails under -n ("use --force for non-interactive mode"). We do NOT
# want to re-download on every upgrade, so: run it once, and treat its explicit
# "Database is already set up" message as a successful no-op. Non-fatal either way.
#
# Hooks already run as www-data (entrypoint uses `su -p www-data`), so call occ directly.
set -euo pipefail

occ() { php /var/www/html/occ "$@"; }

echo "hook: memories:places-setup"
if out=$(occ memories:places-setup -n 2>&1); then
  printf '%s\n' "$out"                       # fresh install: downloaded + set up
elif printf '%s' "$out" | grep -qiE 'already set up'; then
  echo "hook: memories places already set up; skipping"
else
  printf '%s\n' "$out" >&2
  echo "WARN: memories:places-setup failed; re-run: occ memories:places-setup" >&2
fi
