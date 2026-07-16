# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Split the restic backup exclude list into separate files for the local and Azure targets (`backup/exclude_local.txt`, `backup/exclude_azure.txt`), configured via the new `NEXTCLOUD_RESTIC_EXCLUDE_FILE_LOCAL` and `NEXTCLOUD_RESTIC_EXCLUDE_FILE_AZURE` environment variables, replacing the shared `backup/exclude.txt` and `NEXTCLOUD_RESTIC_EXCLUDE_FILE`.
- Split the restic backup include list into separate files for the local and Azure targets (`backup/include_local.txt`, `backup/include_azure.txt`), configured via the new `NEXTCLOUD_RESTIC_INCLUDE_FILE_LOCAL` and `NEXTCLOUD_RESTIC_INCLUDE_FILE_AZURE` environment variables, replacing the shared `backup/include.txt` and `NEXTCLOUD_RESTIC_INCLUDE_FILE`.

### Fixed

- Disabled OPcache JIT in the Nextcloud image to stop php-fpm workers from crashing with SIGSEGV during app install/upgrade on ARM64 hosts such as the Raspberry Pi 5 (upstream PHP aarch64 JIT bug; see nextcloud/docker#2576).
- Fixed the backup script ignoring the built-in default restic repository paths when `NEXTCLOUD_RESTIC_REPO_LOCAL` or `NEXTCLOUD_RESTIC_REPO_AZURE` are unset.

[Unreleased]: https://github.com/BWibo/nextcloud-compose/commits/HEAD
