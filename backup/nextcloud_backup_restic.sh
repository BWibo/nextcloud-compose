#!/usr/bin/env bash

# Crontab entry ---------------------------------------------------------------
# 0 4 * * * $HOME/myzsh/tools/nextcloud/nextcloud-backup.sh >/dev/null 2>&1

# config ----------------------------------------------------------------------
# Nextcloud data, config and themees path, space separated
NEXTCLOUD_BACKUP_PATHS="/my/nextcloud/data/ /my/nextcloud/config/ /my/nextcloud/themes/"
# Log file path
LOGFILE="/home/me/nextcloud.log"
# Temp dir for DB dump
BACKUPDIR_DB_TEMP=/tmp/nextcloud_backup/db
ERR=0

# Restic repo password
export RESTIC_PASSWORD=""
RESTIC_REPOSITORY_LOCAL="/media/myhdd/restic/nextcloud"
RESTIC_REPOSITORY_AZURE="azure:restic:/nextcloud"

# Azure Storage Account name and key
export AZURE_ACCOUNT_NAME=""
export AZURE_ACCOUNT_KEY=""

# Nextcloud database
NEXTCLOUD_DB_HOST=db
NEXTCLOUD_DB_NAME=nextcloud
NEXTCLOUD_DB_USER=nextcloud
NEXTCLOUD_DB_PASSWORD=changeMe

# script ----------------------------------------------------------------------
printf "\n\n" >> ${LOGFILE}
echo "-- Nextcloud backup " `date --utc +%FT%TZ` "-----------------------------" >> ${LOGFILE}

# Enable maintenance mode
docker exec -i --user 33 nextcloud-app-1 ./occ maintenance:mode --on >> ${LOGFILE} 2>&1

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
    -v -h "$NEXTCLOUD_DB_HOST" -U "$NEXTCLOUD_DB_USER" -d "NEXTCLOUD_DB_NAME" -f /data/nextcloud-sqlbkp.bak >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "dump nextcloud db " $errtmp >> ${LOGFILE}

# Create testic snapshot - local
# Local restic repo
export RESTIC_REPOSITORY="$RESTIC_REPOSITORY_LOCAL"
echo "$BACKUPDIR_DB_TEMP $NEXTCLOUD_BACKUP_PATHS" | \
  xargs \
  restic backup --no-scan >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "create restic snapshot - local" $errtmp >> ${LOGFILE}

# Create restic snapshot - Azure
export RESTIC_REPOSITORY="$RESTIC_REPOSITORY_AZURE"
echo "$BACKUPDIR_DB_TEMP $NEXTCLOUD_BACKUP_PATHS" | \
  xargs \
  restic backup --no-scan >> ${LOGFILE} 2>&1

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
export RESTIC_REPOSITORY="$RESTIC_REPOSITORY_LOCAL"
restic forget --prune --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --keep-yearly 5

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "cleanup restic snapshots - local " $errtmp >> ${LOGFILE}

# Azure
export RESTIC_REPOSITORY="$RESTIC_REPOSITORY_AZURE"
restic forget --prune --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --keep-yearly 2

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "cleanup restic snapshots - Azure " $errtmp >> ${LOGFILE}

echo "Total ERR" $ERR >> ${LOGFILE}
