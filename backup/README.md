# Backup Nextcloud with Restic

* Backup to a local HDD
* Backup to Azure Blog storage

## Backup every night a 04:00

Add this to `sudo crontab -e`. Root is required!

```text
0 4 * * * /home/me/nextcloud-compose/nextcloud-backup-restic.sh >/dev/null 2>&1
```
