#!/usr/bin/env bash

# Local
export RESTIC_PASSWORD="$NEXTCLOUD_RESTIC_PASSWORD"
export RESTIC_REPOSITORY="$NEXTCLOUD_RESTIC_REPO_LOCAL"
restic init

# Azure
export AZURE_ACCOUNT_NAME="${NEXTCLOUD_AZURE_ACCOUNT_NAME}"
export AZURE_ACCOUNT_KEY="${NEXTCLOUD_AZURE_ACCOUNT_KEY}"
export RESTIC_REPOSITORY="$NEXTCLOUD_RESTIC_REPO_AZURE"
restic init