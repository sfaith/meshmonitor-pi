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

# Require Docker
if ! command -v docker &>/dev/null; then
  echo "[ERROR] Docker is not installed. Run setup.sh first."
  exit 1
fi

# Ensure Bluetooth adapter is powered on
if ! bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
  echo "  Bluetooth adapter is off — enabling..."
  sudo rfkill unblock bluetooth 2>/dev/null || true
  sleep 2
  sudo bluetoothctl power on 2>/dev/null || true
  sleep 2
  if ! bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
    echo "[ERROR] Could not enable Bluetooth adapter. Check hardware."
    exit 1
  fi
  echo "[OK]    Bluetooth adapter enabled."
fi

echo "  Scanning for nearby Meshtastic devices..."
echo "  (this may take 10-15 seconds — press Ctrl+C to abort)"
echo

docker run --rm --privileged \
  -v /var/run/dbus:/var/run/dbus \
  -v /var/lib/bluetooth:/var/lib/bluetooth:ro \
  ghcr.io/yeraze/meshtastic-ble-bridge:latest --scan > /tmp/mm-ble-scan.txt 2>/dev/null &
SCAN_PID=$!
trap "kill $SCAN_PID 2>/dev/null; rm -f /tmp/mm-ble-scan.txt; echo; exit 130" INT
spinner='|/-\'
i=0
while kill -0 $SCAN_PID 2>/dev/null; do
  printf "\r  Scanning... %s" "${spinner:$(( i % 4 )):1}"
  i=$(( i + 1 ))
  sleep 0.2
done
printf "\r  Scanning... done\n\n"
cat /tmp/mm-ble-scan.txt
rm -f /tmp/mm-ble-scan.txt

echo
echo "  ──────────────────────────────────────────────────────"
echo "  Copy the MAC address above and run ./setup.sh to add"
echo "  this device as a BLE node."
echo
