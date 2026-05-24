# Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.9] - 2026-05-23

### Fixed
- setup.sh step 5: On Pi OS Bookworm, systemd automatically claims /dev/watchdog
  at boot — the userspace watchdog daemon fails with errno 16 (device busy) even
  though the hardware watchdog IS active and working. Step 5 now detects systemd
  watchdog ownership via dmesg and reports correctly rather than attempting a
  conflicting daemon install. Falls back to daemon install on older systems.
- setup.sh step 5: Added dtparam=watchdog=on to /boot/firmware/config.txt to
  ensure hardware watchdog persists correctly across reboots on all Pi models.
- env.example: replaced hardcoded node IP (10.45.72.250) with YOUR_NODE_IP_HERE
- setup.sh: removed hardcoded node IP default from prompt — reads from .env only
- README: "static IP" wording corrected to "DHCP reservation" throughout
- README: troubleshooting node IP replaced with YOUR_NODE_IP placeholder

## [0.1.8] - 2026-05-23

### Added
- README: Hardware section covering tested configuration, board compatibility
  table (Pi 3B/4/5/Zero 2W), RAM requirements and estimates, and SD card
  selection guidance (recommended brands, size rationale)
- README: Platform badge updated to cover all Pi models (not just Pi 4)
- README: Horizontal rule separators between major sections for readability
- README: Prerequistes section restored with cleaner wording

### Changed
- README: section order — Hardware → SD Card Write Minimization → Prerequisites
  → First-Time Setup (was: SD Card → Prerequisites)
- README: description updated to reflect multi-board scope

## [0.1.7] - 2026-05-23

### Fixed
- env.example: replaced hardcoded Pi IP with placeholder (YOUR_PI_IP_HERE)
- docker-compose.yml: removed stale Watchtower label from serial-bridge stub;
  folded standalone auto-upgrade comment into header; cleaned up usage block
- setup.sh: removed "Replaces Watchtower" from cron prompt (no longer relevant)
- setup.sh: added NOTE/Recommended guidance to daemon.json overwrite prompt
- setup.sh: added comment in systemd unit warning about WorkingDirectory
  being set at install time (re-run setup.sh if repo is moved)
- setup.sh: step 7 prompt now accurately describes re-run behavior
- README: "all containers" → "the container" (single container stack)
- README: noted setup.sh is safe to re-run (idempotent)

## [0.1.6] - 2026-05-23

### Fixed
- setup.sh: cron job check killed script under set -euo pipefail when crontab
  was empty (grep -q returning exit 1 treated as fatal). Fixed by storing
  result in a variable before the if block.

## [0.1.5] - 2026-05-23

### Removed
- mqtt-proxy sidecar — node already publishes MQTT directly; MeshMonitor 4.0
  supports MQTT as a native source via Dashboard → Sources → Add → MQTT
- MQTT-related env vars (MQTT_BROKER, MQTT_PORT, MQTT_USERNAME, MQTT_PASSWORD,
  MQTT_TOPIC) removed from env.example and setup.sh

## [0.1.4] - 2026-05-23

### Fixed
- Removed ENABLE_VIRTUAL_NODE and VIRTUAL_NODE_PORT env vars — removed in
  MeshMonitor 4.0 (now configured per-source in Dashboard UI)
- Healthcheck now probes HTTP /api/health instead of Virtual Node port 4404
- mqtt-proxy no longer requires service_healthy — starts alongside meshmonitor
  and retries naturally once Virtual Node port is enabled via UI

## [0.1.3] - 2026-05-23

### Changed
- Replaced Watchtower with a cron-based auto-upgrade (Watchtower archived upstream,
  incompatible with Docker Engine 29+)
- Auto-upgrade schedule now configured as HH:MM time in .env (UPGRADE_TIME)
- setup.sh step 6 now installs both systemd boot service and upgrade cron job

### Removed
- Watchtower container from docker-compose.yml

## [0.1.2] - 2026-05-23

### Fixed
- setup.sh: automatically relaunch under `newgrp docker` if Docker group
  membership is not yet active, preventing permission denied errors at step 7

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
