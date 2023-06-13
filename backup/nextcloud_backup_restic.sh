#!/usr/bin/env bash

# Crontab entry ---------------------------------------------------------------
# 0 4 * * * $HOME/myzsh/tools/nextcloud/nextcloud-backup.sh >/dev/null 2>&1

# config ----------------------------------------------------------------------
# General settings
LOGFILE="${NEXTCLOUD_BACKUP_LOGFILE:-$HOME/nextcloud-backup-restic.log}"
BACKUPDIR_DB_TEMP="${NEXTCLOUD_BACKUPDIR_TEMP:-/tmp/nextcloud/backup}"

# Restic setings
INCLUDE_FILE="${NEXTCLOUD_RESTIC_INCLUDE_FILE:-/nextcloud/backup/include.txt}"
EXCLUDE_FILE="${NEXTCLOUD_RESTIC_EXCLUDE_FILE:-/nextcloud/backup/exclude.txt}"
export RESTIC_PASSWORD="${NEXTCLOUD_RESTIC_PASSWORD:-changeMe}"
FORGET_POLICY="${NEXTCLOUD_RESTIC_FORGET_POLICY:---keep-within-daily 7d --keep-within-weekly 6m}"
RESTIC_REPOSITORY_LOCAL="${NEXTCLOUD_RESTIC_REPO_LOCAL:-/media/myhdd/restic/nextcloud}"
RESTIC_REPOSITORY_AZURE="${NEXTCLOUD_RESTIC_REPO_AZURE:-azure:restic:/nextcloud}"
DRY_RUN="${NEXTCLOUD_RESTIC_DRY_RUN:-}"

# Azure Storage Account name and key
export AZURE_ACCOUNT_NAME="${NEXTCLOUD_AZURE_ACCOUNT_NAME:-accountname}"
export AZURE_ACCOUNT_KEY="${NEXTCLOUD_AZURE_ACCOUNT_KEY:-changeMe}"

# Nextcloud database
NEXTCLOUD_DB_HOST="${NEXTCLOUD_DB_HOST:-db}"
NEXTCLOUD_DB_NAME="${NEXTCLOUD_DB_NAME:-nextcloud}"
NEXTCLOUD_DB_USER="${NEXTCLOUD_DB_USER:-nextcloud}"
NEXTCLOUD_DB_PASSWORD="${NEXTCLOUD_DB_PASSWORD:-changeMe}"

# script ----------------------------------------------------------------------
ERR=0
printf "\n\n" >> ${LOGFILE}
echo "-- Nextcloud backup " `date --utc +%FT%TZ` "-----------------------------" \
  >> ${LOGFILE}

# Enable maintenance mode
docker exec -i --user 33 nextcloud-app-1 ./occ maintenance:mode --on \
  >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "nextcloud enable maintenance mode " $errtmp >> ${LOGFILE} 2>&1

# Dump database
mkdir -p -v "$BACKUPDIR_DB_TEMP"

docker run -i --rm --name pgdump \
    -v "$BACKUPDIR_DB_TEMP":/data \
    --entrypoint pg_dump \
    --network nextcloud_net \
    -e PGPASSWORD="$NEXTCLOUD_DB_PASSWORD" \
  postgres:14-alpine \
    -v -h "$NEXTCLOUD_DB_HOST" -U "$NEXTCLOUD_DB_USER" \
    -d "NEXTCLOUD_DB_NAME" -f /data/nextcloud-sqlbkp.bak \
    >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "dump nextcloud db " $errtmp >> ${LOGFILE}

# Create testic snapshot - local
# Local restic repo
export RESTIC_REPOSITORY="${NEXTCLOUD_RESTIC_REPO_LOCAL}"
echo "$DRY_RUN" | xargs \
restic backup --no-scan \
  --files-from "${INCLUDE_FILE}" \
  --iexclude-file "${EXCLUDE_FILE}" >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "create restic snapshot - local" $errtmp >> ${LOGFILE}

# Create restic snapshot - Azure
export RESTIC_REPOSITORY="${NEXTCLOUD_RESTIC_REPO_AZURE}"
echo "$DRY_RUN" | xargs \
restic backup --no-scan \
  --files-from "${INCLUDE_FILE}" \
  --iexclude-file "${EXCLUDE_FILE}" >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "create restic snapshot - Azure" $errtmp >> ${LOGFILE}

# Disable maintenance mode
docker exec -i --user 33 nextcloud-app-1 ./occ maintenance:mode --off \
  >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "nextcloud disable maintenance mode " $errtmp >> ${LOGFILE}

# Remove tmp db Backup
rm -r -f "$BACKUPDIR_DB_TEMP"

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "cleanup backup dir " $errtmp >> ${LOGFILE}

# Cleanup restic repos
# local
export RESTIC_REPOSITORY="${NEXTCLOUD_RESTIC_REPO_LOCAL}"
echo "$FORGET_POLICY" "$DRY_RUN"  | xargs \
restic forget --prune >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "cleanup restic snapshots - local " $errtmp >> ${LOGFILE}

# Azure
export RESTIC_REPOSITORY="${NEXTCLOUD_RESTIC_REPO_AZURE}"
echo "$FORGET_POLICY" "$DRY_RUN"  | xargs \
restic forget --prune >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "cleanup restic snapshots - Azure " $errtmp >> ${LOGFILE}

echo "Total ERR" $ERR >> ${LOGFILE}
