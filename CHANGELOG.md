# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Disabled OPcache JIT in the Nextcloud image to stop php-fpm workers from crashing with SIGSEGV during app install/upgrade on ARM64 hosts such as the Raspberry Pi 5 (upstream PHP aarch64 JIT bug; see nextcloud/docker#2576).

[Unreleased]: https://github.com/BWibo/nextcloud-compose/commits/HEAD
