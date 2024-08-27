#!/usr/bin/env bash

# Export ENV for retic usage - Azure

export RESTIC_REPOSITORY=$NEXTCLOUD_RESTIC_REPO_AZURE
export RESTIC_PASSWORD=$NEXTCLOUD_RESTIC_PASSWORD

export AZURE_ACCOUNT_NAME=$NEXTCLOUD_AZURE_ACCOUNT_NAME
export AZURE_ACCOUNT_KEY=$NEXTCLOUD_AZURE_ACCOUNT_KEY
