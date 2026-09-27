#!/usr/bin/env bash

# Cold backup of named Docker volumes to compressed tar archives.
#
# Intended as a one-shot safety net before destructive operations such as
# Postgres major-version upgrades (see "Database migration" in the top-level
# README.md). This is NOT a replacement for the restic backups — a volume
# tar is only consistent while no container is using the volume, so the
# stack must be stopped first (docker compose down).
#
# Usage:
#   ./volume_backup.sh [volume ...]        # default: nextcloud_db_data
#
# Restore into a fresh volume:
#   docker volume create <volume>
#   docker run --rm -v <volume>:/target -v "$BACKUPDIR":/backup \
#     alpine tar -xzf /backup/<archive>.tar.gz -C /target

# config ----------------------------------------------------------------------
BACKUPDIR="${NEXTCLOUD_VOLUME_BACKUP_DIR:-/media/myhdd/volume-backups}"

# script ----------------------------------------------------------------------
set -u

VOLUMES=("${@:-nextcloud_db_data}")
TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
ERR=0

echo "-- Docker volume backup $(date --utc +%FT%TZ) ----------------------------"
echo "Target directory: ${BACKUPDIR}"

mkdir -p "${BACKUPDIR}" || exit 1

for VOLUME in "${VOLUMES[@]}"; do
  printf "\nBacking up volume '%s'...\n" "${VOLUME}"

  # Volume must exist
  if ! docker volume inspect "${VOLUME}" > /dev/null 2>&1; then
    echo "ERROR: volume '${VOLUME}' does not exist, skipping."
    ERR=$((ERR + 1))
    continue
  fi

  # A tar of a volume in use (e.g. a live Postgres data dir) is inconsistent
  CONTAINERS="$(docker ps --quiet --filter volume="${VOLUME}")"
  if [ -n "${CONTAINERS}" ]; then
    echo "ERROR: volume '${VOLUME}' is used by running container(s):"
    docker ps --filter volume="${VOLUME}" --format '  {{.Names}} ({{.ID}})'
    echo "Stop the stack first (docker compose down), skipping."
    ERR=$((ERR + 1))
    continue
  fi

  ARCHIVE="${VOLUME}_${TIMESTAMP}.tar.gz"
  docker run --rm \
    -v "${VOLUME}":/source:ro \
    -v "${BACKUPDIR}":/backup \
    alpine tar -czf "/backup/${ARCHIVE}" -C /source .

  errtmp=$?
  ERR=$((ERR + errtmp))
  if [ ${errtmp} -eq 0 ]; then
    echo "Created:"
    ls -lh "${BACKUPDIR}/${ARCHIVE}"
  else
    echo "ERROR: backup of '${VOLUME}' failed (exit ${errtmp})."
  fi
done

printf "\nRestore hint:\n"
echo "  docker volume create <volume>"
echo "  docker run --rm -v <volume>:/target -v \"${BACKUPDIR}\":/backup \\"
echo "    alpine tar -xzf /backup/<archive>.tar.gz -C /target"

printf "\nTotal ERR %s\n" "${ERR}"
echo "-- Docker volume backup $(date --utc +%FT%TZ) done!-----------------------"
exit "${ERR}"
