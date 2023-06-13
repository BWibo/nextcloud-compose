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
NEXTCLOUD_BACKUP_PATHS="/media/samsung/nextcloud/data/data/ /media/samsung/nextcloud/data/config/ /media/samsung/nextcloud/data/themes/"

NEXTCLOUD_RESTIC_REPO_LOCAL="/media/intenso/restic/nextcloud"
NEXTCLOUD_RESTIC_REPO_AZURE="azure:restic:/nextcloud"
NEXTCLOUD_RESTIC_PASSWORD="changeMe"
NEXTCLOUD_AZURE_ACCOUNT_NAME="accountname"
NEXTCLOUD_AZURE_ACCOUNT_KEY="changeMe"


```
