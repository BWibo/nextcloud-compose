#!/usr/bin/env bash

# Crontab entry ---------------------------------------------------------------
# Note: Make sure restic in on cron's PATH!
# 0 4 * * * $HOME/myzsh/tools/nextcloud/nextcloud-backup.sh >/dev/null 2>&1

# config ----------------------------------------------------------------------
# General settings
LOGFILE="${NEXTCLOUD_BACKUP_LOGFILE:-/home/me/nextcloud-backup-restic.log}"

# Restic setings
export RESTIC_PASSWORD="${NEXTCLOUD_RESTIC_PASSWORD:-changeMe}"
RESTIC_REPOSITORY_LOCAL="${NEXTCLOUD_RESTIC_REPO_LOCAL:-/media/myhdd/restic/nextcloud}"
RESTIC_REPOSITORY_AZURE="${NEXTCLOUD_RESTIC_REPO_AZURE:-azure:restic:/nextcloud}"
DRY_RUN="${NEXTCLOUD_RESTIC_DRY_RUN:-}"

# Azure Storage Account name and key
export AZURE_ACCOUNT_NAME="${NEXTCLOUD_AZURE_ACCOUNT_NAME:-accountname}"
export AZURE_ACCOUNT_KEY="${NEXTCLOUD_AZURE_ACCOUNT_KEY:-changeMe}"

# script ----------------------------------------------------------------------
ERR=0
printf "\n\n" >> ${LOGFILE}
echo "-- Nextcloud restic prune" `date --utc +%FT%TZ` "-----------------------------" \
  >> ${LOGFILE}
printf "\n\n" >> ${LOGFILE}

# Cleanup restic repos
# local
export RESTIC_REPOSITORY="${NEXTCLOUD_RESTIC_REPO_LOCAL}"
echo "$DRY_RUN" | xargs \
restic prune >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "prune restic snapshots - local " $errtmp >> ${LOGFILE}

restic check >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "check restic repo - local " $errtmp >> ${LOGFILE}

# Azure
export RESTIC_REPOSITORY="${NEXTCLOUD_RESTIC_REPO_AZURE}"
echo "$DRY_RUN" | xargs \
restic prune >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "prune restic snapshots - Azure " $errtmp >> ${LOGFILE}

restic check >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "check restic repo - Azure " $errtmp >> ${LOGFILE}

printf "\n\n" >> ${LOGFILE}
echo "Total ERR" $ERR >> ${LOGFILE}
echo "-- Nextcloud restic prune" `date --utc +%FT%TZ` "done!-----------------------------" \
  >> ${LOGFILE}
printf "\n\n" >> ${LOGFILE}
