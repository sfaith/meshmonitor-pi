# Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.6] - 2026-06-07

### Added
- launch.sh: `write_result()` helper writes SUCCESS/FAILED + timestamp + reason
  to ~/.meshmonitor-upgrade-result after every pull and up -d attempt
- launch.sh: `notify_failure()` helper fires a push notification via ntfy.sh on
  upgrade failure; no-op if NTFY_TOPIC is unset or WAN is down
- launch.sh: `status` subcommand now shows last upgrade outcome (✓/✗), age with
  staleness warning if >48h, and NTFY alert configuration status
- env.example: NTFY_TOPIC documented with setup instructions
- .gitignore: .meshmonitor-upgrade-result added (runtime file, Pi-local)

## [0.3.5] - 2026-06-07

### Added
- launch.sh: `prune` subcommand — removes all unused Docker images, containers,
  and networks via `docker system prune -af`; volumes never touched; output
  logged to ~/meshmonitor-upgrade.log with timestamp header
- setup.sh: weekly prune cron installed in step 7 (Sundays at 04:00, one hour
  after nightly upgrade); uses its own cron marker so it doesn't collide with
  the upgrade cron on re-runs
- Motivated by 19 GB → 6.4 GB reclaim on production Pi — daily auto-upgrades
  accumulate stale image layers without periodic pruning

## [0.3.4] - 2026-05-24

### Added
- setup.sh: Remove node — option 6 fully implemented. Lists nodes, confirms
  removal, unpairs BLE device from host, stops and removes bridge containers,
  renumbers remaining nodes in .env, instructs user to delete source in Dashboard
- setup.sh: BLE pairing offered for devices added from remaining scan results —
  previously pairing was skipped for second/third BLE devices from the same scan
- setup.sh: Pairing flow now uses interactive bluetoothctl session for full PIN
  support — resolves AuthenticationFailed on PIN/passkey-protected devices
- setup.sh: edit_node BLE — pairing flow offered when MAC address is changed,
  with option to pair immediately or defer; old address unpaired automatically
- launch.sh: `status` subcommand — shows container health, last upgrade time,
  disk usage, and uptime: `./launch.sh status`
- scan-ble.sh: Spinner during BLE scan — 10-15 second wait now shows progress
- scan-ble.sh: Docker availability check — clear error if Docker not installed
- tests/test_setup.sh: logic test suite — 56 tests covering IP/MAC/port/time
  validation, node renumber logic, and .env hash comparison; no Pi or Docker
  required; exit code 0 on full pass
- README: Quick Start collapsible step 4 split into separate setup and reboot
  commands with Docker-relaunch note; step numbering updated accordingly
- README: BLE 'connecting' troubleshooting entry with manual pairing procedure
- README: Quick Start fully rewritten — two-phase setup (Pi ready / install app),
  collapsible expert section, bootstrap commands, non-techie callout

### Fixed
- setup.sh: All `nc` port checks replaced with `bash /dev/tcp` — nc not
  pre-installed on Pi OS Lite
- setup.sh: Post-start BLE/serial readiness checks use `docker inspect` instead
  of `nc` inside container — nc not available in minimal bridge images
- setup.sh: Bridge action output uses plain-text section — eliminates Unicode
  box rendering issues across terminal emulators
- setup.sh: Reboot notice shown on first run only — suppressed on re-runs
- setup.sh: `is_first_run` captured before stack launch — correct behavior when
  user skips step 8
- setup.sh: Double connectivity test when choosing option 5 — test now runs once
- setup.sh: `test_all_nodes` BLE check uses fast `docker ps` — replaces slow
  10-15s blocking docker scan per BLE node
- setup.sh: Post-start serial bridge aligned to `docker inspect` for consistency
- setup.sh: "Add more nodes" BLE loop bounds validation — rejects non-numeric
  and out-of-range input, prevents blank MAC address written to .env
- setup.sh: IP address validation added to `add_tcp_node` and `edit_node` TCP
  path — invalid format warns and returns instead of writing bad values to .env
- setup.sh: Step 1 values (PI_IP, HOST_PORT, TZ, UPGRADE_TIME, SESSION_SECRET)
  now preserved across Docker-install relaunch via secure temp state file;
  stale state files from aborted runs cleaned up automatically on next start
- setup.sh: Invalid BLE MAC address in manual entry now warns and returns instead
  of hard-exiting — user input from prior steps is preserved
- setup.sh: Empty BLE MAC address in manual entry now warns and returns instead
  of hard-exiting
- setup.sh: `test_all_nodes` re-test loop converted from recursion to while loop
  — eliminates unbounded call stack growth on repeated re-test
- setup.sh: noatime sed now verifies the change landed and warns with manual
  instructions if fstab format was not matched (e.g. non-PARTUUID or non-ext4)
- launch.sh: Compose command array-quoted — paths with spaces no longer break
  docker compose invocation
- launch.sh: Running with no subcommand now prints a clear usage error instead
  of passing empty args to docker compose
- scan-ble.sh: Ctrl+C trap added — kills scan process and removes temp file
  cleanly on interrupt
- launch.sh: Comment updated to reflect manual use cases

### Changed
- setup.sh: BLE pairing is now the recommended default (option 1) — previously
  "connect without pairing" was default, causing silent failures on PIN devices
- setup.sh: Serial bridge prerequisite command updated — adds missing
  `--set serial.echo false` and `--set serial.baud BAUD_115200`
- README: Serial node prerequisite command updated to match setup.sh
- README: Prerequisites merged into Quick Start — removed as separate section
- README: Day-to-Day Operations simplified, `./launch.sh status` added
- README: Auto-Upgrade and troubleshooting sections tightened
- README: Various stale docker compose references replaced with launch.sh

## [0.3.3] - 2026-05-23

### Added
- setup.sh: End-of-wizard node summary block — lists all configured nodes with
  a checkmark so users can confirm their setup at a glance
- setup.sh: Bridge action-required box — prominent box at end of wizard listing
  each BLE/serial bridge container name, host, and port to add as a TCP source
  in MeshMonitor Dashboard → Sources. Shown only when bridge nodes are
  configured. Saved to ~/meshmonitor-next-steps.txt for later reference
- setup.sh: OPTIONAL section (Virtual Node, permissions) removed from terminal
  output — retained in ~/meshmonitor-next-steps.txt only

### Fixed
- setup.sh: BLE connectivity check in `test_all_nodes` replaced slow blocking
  docker scan (10-15s per node) with instant `docker ps` container check —
  avoids redundant re-scan after a node was just added, gives accurate status
- setup.sh: Post-start BLE bridge readiness check replaced `nc` inside container
  (not available in minimal bridge image) with `docker inspect` — reliable
  regardless of what is installed in the bridge image
- setup.sh: Post-start serial bridge check aligned to `docker inspect` for
  consistency with BLE check
- setup.sh: "Add more nodes" BLE scan results loop now validates user input —
  rejects non-numeric and out-of-range entries to prevent blank MAC address
  being written to .env silently
- setup.sh: Post-setup output refactored to use direct print functions —
  eliminates variable interpolation artifacts that caused box rendering issues
- setup.sh: set -e safe returns in print functions — prevents early script exit
  when no bridge nodes are configured

### Changed
- README: Serial node section rewritten — replace stale manual .env/compose
  instructions with "re-run setup.sh" workflow
- README: Session secret step rewritten — auto-generation is the default,
  manual openssl method documented for technically inclined users
- README: Setup steps renumbered (6 steps, down from 7)
- README: Prerequisites broadened to cover TCP, BLE, and serial node options
- README: Day-to-Day Operations note added directing users to setup.sh for
  config changes; manual upgrade command updated to use launch.sh
- README: Upgrade log path corrected to ~/meshmonitor-upgrade.log
- README: MQTT section notes that credentials shown are Arizona regional mesh only
- README: Version badge updated to 0.3.3

## [0.3.2] - 2026-05-24

### Fixed
- launch.sh: Generated compose now references network as
  `meshmonitor-pi_meshtastic_net` (the actual Docker-assigned name) rather
  than declaring it external without a name — fixes "network could not be
  found" error when starting bridge containers
- launch.sh: Added `--progress=tty` to restore animated Docker pull output

## [0.3.1] - 2026-05-24

### Fixed
- setup.sh: BLE scan regex updated to match actual bridge output format
  (`NAME - MAC` with dash separator, not `NAME (MAC)` with parentheses)
- setup.sh: Bluetooth adapter auto-enabled before scan — detects soft-block
  via rfkill and runs `sudo rfkill unblock bluetooth` + `bluetoothctl power on`
  automatically so scan never fails due to powered-off adapter
- setup.sh: Node name prompt moved to after device selection in BLE flow —
  now defaults to the scanned device name instead of generic "BLE Node"
- setup.sh: Removed "press Enter to accept" from node name prompt in BLE flow
- setup.sh: Removed privileged mode NOTE from BLE header (implementation detail,
  not actionable by user)
- setup.sh: Added spinner progress indicator during BLE scan with Ctrl+C callout
- setup.sh: Fixed REMAINING_SCAN_NAMES bug — was incorrectly populated from
  SCAN_ADDRS instead of SCAN_NAMES
- launch.sh: Fixed double banner — summary was printed twice (once for pull,
  once for up -d) due to banner living before exec
- CLAUDE.md: Removed stale references to docker-compose.ble.yml and start.sh

## [0.3.0] - 2026-05-23

### Added
- BLE (Bluetooth) node support via `meshtastic-ble-bridge` sidecar container
- Serial/USB node support via `meshtastic-serial-bridge` sidecar container
- `launch.sh` — thin non-interactive launcher called by systemd and cron.
  Reads .env, generates docker-compose.generated.yml for bridge services,
  runs the correct docker compose command. Never needs rewriting when nodes change.
- `scan-ble.sh` — standalone BLE scanner for discovering nearby Meshtastic devices
- Numbered node model in .env: NODE_1_TYPE, NODE_1_IP, NODE_2_TYPE,
  NODE_2_BLE_ADDRESS, NODE_3_TYPE, NODE_3_SERIAL_DEVICE, etc.
- Loop-until-gap node detection — no NODE_COUNT var needed
- Migration step converts legacy MESHTASTIC_NODE_IP vars on re-run
- SESSION_SECRET auto-generated by setup.sh on first run — never shown to user
- setup.sh output tee'd to ~/meshmonitor-setup.log
- Post-setup instructions written to ~/meshmonitor-next-steps.txt
- Upgrade log moved to persistent ~/meshmonitor-upgrade.log (trimmed to 500 lines)
- Password change warning box (first run only)
- Bridge node post-setup instructions with actual container names and host values
- Serial node prerequisite prompt (must enable serial mode on device before setup)
- Avahi/mDNS mount omitted by design — Docker internal DNS is sufficient

### Changed
- setup.sh restructured from 7-step to 8-step wizard
- Step 3 is now Node Connections — asks connection type before anything else
- systemd unit always rewritten by setup.sh to reference launch.sh correctly
- Cron job always updated to reference launch.sh
- docker-compose.yml: serial bridge stub removed (generated dynamically now)
- env.example updated to numbered node model

### Removed
- Static `docker-compose.ble.yml` overlay — replaced by dynamic generation
- Hardcoded MESHTASTIC_NODE_IP default in setup.sh prompt

## [0.2.5] - 2026-05-23

### Fixed
- setup.sh step 5: WATCHDOG_ENABLED check used a pipe under set -euo pipefail —
  `systemctl is-enabled | grep -q` could exit fatally if systemctl returned
  non-zero. Fixed by capturing to a variable first.
- CLAUDE.md: Project Summary updated to reflect multi-board support (Pi 3/4/5)

## [0.2.4] - 2026-05-23

### Fixed
- setup.sh step 5: Strip whitespace from fuser output before comparison.
  `fuser /dev/watchdog0` returns `'     1'` with leading spaces — exact string
  match against `"1"` was silently failing. Fixed with `tr -d ' '`.

## [0.2.3] - 2026-05-23

### Fixed
- setup.sh step 5: Switch watchdog detection to `sudo fuser /dev/watchdog0`.
  Checks direct kernel state (PID 1 = systemd holds the device) rather than
  parsing logs. Reliable regardless of journal storage mode or dmesg restrictions.
  Previous journalctl approach failed because volatile journal doesn't retain
  early boot messages from before the journal service fully initialised.

## [0.2.2] - 2026-05-23

### Fixed
- setup.sh step 5: Capture journalctl output into a variable before grepping
  to avoid set -euo pipefail trapping journalctl's exit code inside a pipe.
  Previous approach `journalctl -b | grep -q` failed silently under pipefail
  even though journalctl was working correctly interactively.

## [0.2.1] - 2026-05-23

### Fixed
- setup.sh step 5: Switched watchdog detection from `sudo dmesg` to
  `journalctl -b` — more reliable in script context (no sudo required, no
  rate limiting). Previous dmesg-based detection was silently failing, causing
  the script to fall through to the userspace daemon install path on every run.

## [0.2.0] - 2026-05-23

### Fixed
- setup.sh step 5: When systemd owns the hardware watchdog, now also stops and
  disables the userspace watchdog daemon if present. On Pi OS Bookworm, systemd
  claims /dev/watchdog at boot so the daemon can never open it (errno 16), leaving
  misleading error messages. The daemon is redundant and is cleanly removed.

### Changed
- Version bump to 0.2.0 — first fully verified, end-to-end tested deployment.
  All components confirmed working: healthcheck, systemd service, hardware watchdog,
  noatime, tmpfs mounts, volatile journal, Docker log limits, auto-upgrade cron.
  Running MeshMonitor v4.6.6.

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
