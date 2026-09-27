# Backup Nextcloud with Restic

* Backup to a local HDD
* Backup to Azure Blog storage

## Cold volume backup (volume_backup.sh)

`volume_backup.sh` tars named Docker volumes to compressed archives. It is a
one-shot safety net for destructive maintenance — e.g. before recreating
`nextcloud_db_data` for a Postgres major upgrade (see "Database migration" in
the top-level README) — not a replacement for the restic backups.

The script refuses to back up a volume that is used by a running container
(a hot tar of a live Postgres data dir is inconsistent), so stop the stack
first with `docker compose down`.

```bash
# Default: backs up nextcloud_db_data to $NEXTCLOUD_VOLUME_BACKUP_DIR
NEXTCLOUD_VOLUME_BACKUP_DIR=/media/myhdd/volume-backups ./volume_backup.sh

# Or name the volumes explicitly
./volume_backup.sh nextcloud_db_data nextcloud_caddy_data
```

Restore into a fresh volume:

```bash
docker volume create <volume>
docker run --rm -v <volume>:/target -v /media/myhdd/volume-backups:/backup \
  alpine tar -xzf /backup/<archive>.tar.gz -C /target
```

## Backup every night at 05:00

Add this to `crontab -e`. The job logs to the systemd journal via `logger` (collected
by the observability stack, which alerts on failed/missing runs) and keeps the local
log file via `tee`; `LOGFILE=/dev/stdout` redirects the script's internal `>>` appends
into the pipe:

```text
0 5 * * * NEXTCLOUD_BACKUP_LOGFILE=/dev/stdout /home/<user>/nextcloud/backup/nextcloud_backup_restic.sh 2>&1 | tee -a /home/<user>/nextcloud-backup-restic.log | logger -t nextcloud-backup
0 3 1 * * NEXTCLOUD_BACKUP_LOGFILE=/dev/stdout /home/<user>/nextcloud/backup/nextcloud_backup_restic_prune.sh 2>&1 | tee -a /home/<user>/nextcloud-backup-restic.log | logger -t nextcloud-prune
```

The `logger -t` tags (`nextcloud-backup`, `nextcloud-prune`) are matched by the
`backup_alerts` Loki rules in the home-monitoring-stack repo — keep them in sync.

## Env

```shell
###############################################################################
# Nextcloud restic backup settings
###############################################################################

# General settings
NEXTCLOUD_BACKUP_LOGFILE="/home/me/nextcloud-backup-restic.log"
NEXTCLOUD_BACKUPDIR_TEMP="/tmp/nextcloud_backup/db"

# Restic settings
NEXTCLOUD_RESTIC_INCLUDE_FILE_LOCAL="/nextcloud/backup/include_local.txt"
NEXTCLOUD_RESTIC_INCLUDE_FILE_AZURE="/nextcloud/backup/include_azure.txt"
NEXTCLOUD_RESTIC_EXCLUDE_FILE_LOCAL="/nextcloud/backup/exclude_local.txt"
NEXTCLOUD_RESTIC_EXCLUDE_FILE_AZURE="/nextcloud/backup/exclude_azure.txt"
NEXTCLOUD_RESTIC_PASSWORD="changeMe"
NEXTCLOUD_RESTIC_FORGET_POLICY="--keep-within-daily 56d --keep-within-weekly 6m --keep-within-monthly 1y --keep-within-yearly 5y"
NEXTCLOUD_RESTIC_REPO_LOCAL="/media/intenso/restic/nextcloud"
NEXTCLOUD_RESTIC_REPO_AZURE="azure:restic:/nextcloud"
# Additional args for backup and forget command
# NEXTCLOUD_RESTIC_ARGS="-vv --dry-run"

# Additional args for restic prune command
# NEXTCLOUD_RESTIC_PRUNE_ARGS="-v"

# Azure account name and key
NEXTCLOUD_AZURE_ACCOUNT_NAME="accountname"
NEXTCLOUD_AZURE_ACCOUNT_KEY="changeMe"

# Nextcloud database credentials
NEXTCLOUD_DB_HOST=db
NEXTCLOUD_DB_NAME=nextcloud
NEXTCLOUD_DB_USER=nextcloud
NEXTCLOUD_DB_PASSWORD=changeMe
```
