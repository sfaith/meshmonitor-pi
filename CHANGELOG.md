# Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-05-23

### Changed
- setup.sh: added explanatory notes and recommended answer to every confirm prompt

## [0.1.0] - 2026-05-23

### Added
- Initial Docker Compose stack for Raspberry Pi 4 (arm64)
- MeshMonitor container with TCP node support
- mqtt-proxy sidecar for upstream Meshtastic MQTT bridging
- Watchtower sidecar for automatic daily image updates (label-scoped)
- Serial bridge service pre-stubbed and commented out for future use
- SD card write minimization (local log driver, tmpfs, ACCESS_LOG_ENABLED=false)
- Interactive setup.sh for first-boot configuration
- Hardware watchdog support (bcm2835_wdt) via setup.sh
- systemd meshmonitor.service for stack auto-start on boot via setup.sh
- OS hardening via setup.sh (noatime, volatile journal, tmpfs /var/log)
- Docker daemon.json for system-wide log capping
- env.example with all configurable variables documented
