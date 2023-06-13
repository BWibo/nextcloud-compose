# Backup Nextcloud with Restic

* Backup to a local HDD
* Backup to Azure Blog storage

## Backup every night a 04:00

Add this to `sudo crontab -e`. Root is required!

```text
0 4 * * * /home/me/nextcloud-compose/nextcloud-backup-restic.sh >/dev/null 2>&1
```

## Env

```shell
###############################################################################
# Nextcloud restic backup settings
###############################################################################

# General settings
NEXTCLOUD_BACKUP_LOGFILE="$HOME/nextcloud-backup-restic.log"
NEXTCLOUD_BACKUPDIR_TEMP="/tmp/nextcloud/backup"

# Restic settings
NEXTCLOUD_RESTIC_INCLUDE_FILE="/nextcloud/backup/include.txt"
NEXTCLOUD_RESTIC_EXCLUDE_FILE="/nextcloud/backup/exclude.txt"
NEXTCLOUD_RESTIC_PASSWORD="changeMe"
NEXTCLOUD_RESTIC_FORGET_POLICY="--keep-within-daily 56d --keep-within-weekly 6m --keep-within-monthly 1y --keep-within-yearly 5y"
NEXTCLOUD_RESTIC_REPO_LOCAL="/media/intenso/restic/nextcloud"
NEXTCLOUD_RESTIC_REPO_AZURE="azure:restic:/nextcloud"

# Azure account name and key
NEXTCLOUD_AZURE_ACCOUNT_NAME="accountname"
NEXTCLOUD_AZURE_ACCOUNT_KEY="changeMe"

# Nextcloud database credentials
NEXTCLOUD_DB_HOST=db
NEXTCLOUD_DB_NAME=nextcloud
NEXTCLOUD_DB_USER=nextcloud
NEXTCLOUD_DB_PASSWORD=changeMe
```
