#!/usr/bin/env bash
# =============================================================================
# scan-ble.sh — BLE Device Scanner
# =============================================================================
#
# Scans for nearby Meshtastic Bluetooth devices and displays their
# MAC addresses. Use this to find a device's MAC before running setup.sh,
# or to verify a device is visible when troubleshooting BLE connectivity.
#
# Usage:
#   ./scan-ble.sh
#
# Requirements:
#   - Docker must be installed and running
#   - Pi must have Bluetooth hardware (Pi 3B+, 4, 5 all have it built-in)
#   - The Meshtastic device must be powered on and within ~10 meters
# =============================================================================

set -euo pipefail

echo
echo "  MeshMonitor Pi — BLE Device Scanner"
echo "  ──────────────────────────────────────────────────────"
echo "  Scanning for nearby Meshtastic devices..."
echo "  (this may take 10-15 seconds)"
echo

docker run --rm --privileged \
  -v /var/run/dbus:/var/run/dbus \
  -v /var/lib/bluetooth:/var/lib/bluetooth:ro \
  ghcr.io/yeraze/meshtastic-ble-bridge:latest --scan

echo
echo "  ──────────────────────────────────────────────────────"
echo "  Copy the MAC address above and run ./setup.sh to add"
echo "  this device as a BLE node."
echo
