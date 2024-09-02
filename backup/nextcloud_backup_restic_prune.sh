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
RESTIC_PRUNE_ARGS="${NEXTCLOUD_RESTIC_PRUNE_ARGS:-}"

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
printf "\nPruning repo - local...\n" >> ${LOGFILE}
export RESTIC_REPOSITORY="${NEXTCLOUD_RESTIC_REPO_LOCAL}"
echo "$RESTIC_PRUNE_ARGS" | xargs \
restic prune >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "prune restic snapshots - local " $errtmp >> ${LOGFILE}
printf "\nPruning repo - local...done!\n" >> ${LOGFILE}

printf "\nChecking repo - local...\n" >> ${LOGFILE}
restic check >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "check restic repo - local" $errtmp >> ${LOGFILE}
printf "\nChecking repo - local...done!\n" >> ${LOGFILE}

# Azure
printf "\nPruning repo - Azure...\n" >> ${LOGFILE}
export RESTIC_REPOSITORY="${NEXTCLOUD_RESTIC_REPO_AZURE}"
echo "$RESTIC_PRUNE_ARGS" | xargs \
restic prune >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "prune restic snapshots - Azure " $errtmp >> ${LOGFILE}
printf "\nPruning repo - Azure...done!\n" >> ${LOGFILE}

printf "\nChecking repo - Azure...\n" >> ${LOGFILE}
restic check >> ${LOGFILE} 2>&1

errtmp=$?
ERR=$(($ERR + $errtmp))
echo "check restic repo - Azure " $errtmp >> ${LOGFILE}
printf "\nChecking repo - Azure...done!\n" >> ${LOGFILE}

printf "\n\n" >> ${LOGFILE}
echo "Total ERR" $ERR >> ${LOGFILE}
echo "-- Nextcloud restic prune" `date --utc +%FT%TZ` "done!-----------------------------" \
  >> ${LOGFILE}
printf "\n\n" >> ${LOGFILE}
