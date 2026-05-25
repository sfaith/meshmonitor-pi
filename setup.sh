#!/usr/bin/env bash
# =============================================================================
# setup.sh — MeshMonitor Pi Setup Wizard v0.3.3
# =============================================================================
#
# Interactive 8-step configuration wizard. Run this on first install and
# any time you want to add nodes, change settings, or reconfigure the stack.
#
# Do NOT call this from systemd or cron — use launch.sh for that.
#
# Steps:
#   1. Pi Configuration
#   2. Docker Installation
#   3. Node Connections
#   4. SD Card Write Minimization
#   5. Docker Daemon Configuration
#   6. Hardware Watchdog
#   7. systemd Boot Service + Auto-Upgrade Cron
#   8. Pull Images and Start Stack
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE="${SCRIPT_DIR}/env.example"
DAEMON_JSON="${SCRIPT_DIR}/daemon.json"
LAUNCH_SH="${SCRIPT_DIR}/launch.sh"
LOG_FILE="${HOME}/meshmonitor-setup.log"
NEXT_STEPS_FILE="${HOME}/meshmonitor-next-steps.txt"
UPGRADE_LOG="${HOME}/meshmonitor-upgrade.log"
# Tee all output to setup log from this point forward
exec > >(tee -a "$LOG_FILE") 2>&1

# If Docker is installed but we're not in the docker group, relaunch now.
if command -v docker &>/dev/null && ! docker info &>/dev/null 2>&1; then
  echo "Docker is installed but not accessible — relaunching under 'newgrp docker'..."
  exec newgrp docker <<NEWGRP
    cd "${SCRIPT_DIR}" && bash setup.sh
NEWGRP
fi

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
info()    { echo -e "\n\e[1;34m[INFO]\e[0m  $*"; }
success() { echo -e "\e[1;32m[OK]\e[0m    $*"; }
warn()    { echo -e "\e[1;33m[WARN]\e[0m  $*"; }
error()   { echo -e "\e[1;31m[ERROR]\e[0m $*" >&2; exit 1; }

prompt() {
  local var="$1" label="$2" current="$3"
  local input
  echo -en "\n  ${label}"
  [[ -n "$current" ]] && echo -en " \e[2m[${current}]\e[0m"
  echo -en " (press Enter to accept): "
  read -r input
  if [[ -n "$input" ]]; then
    printf -v "$var" '%s' "$input"
  else
    printf -v "$var" '%s' "$current"
  fi
}

menu() {
  # menu <variable_name> <default_choice> <option1> <option2> ...
  local var="$1" default="$2"
  shift 2
  local i=1
  for opt in "$@"; do
    if [[ "$i" == "$default" ]]; then
      echo "    ${i}) ${opt}  ← default"
    else
      echo "    ${i}) ${opt}"
    fi
    i=$(( i + 1 ))
  done
  local answer
  echo -en "\n  Choice [${default}]: "
  read -r answer
  [[ -z "$answer" ]] && answer="$default"
  printf -v "$var" '%s' "$answer"
}

# Detect first run by checking if the MeshMonitor Docker volume exists
is_first_run() {
  ! docker volume inspect meshmonitor-pi_meshmonitor-data &>/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# Banner
# -----------------------------------------------------------------------------
echo
echo "============================================================"
echo "  MeshMonitor Pi — Setup Wizard v0.3.3"
echo "  github.com/sfaith/meshmonitor-pi"
echo "============================================================"
echo
echo "  This wizard will:"
echo "    1. Review and confirm your Pi settings"
echo "    2. Install Docker (if not present)"
echo "    3. Configure your Meshtastic node connections"
echo "    4. Harden the OS for SD card longevity"
echo "    5. Configure Docker daemon log limits"
echo "    6. Enable hardware watchdog (auto-reboot on hang)"
echo "    7. Install systemd boot service and auto-upgrade cron"
echo "    8. Pull images and start the stack"
echo
echo "  Setup output is being logged to:"
echo "    ${LOG_FILE}"
echo
echo "  Press Ctrl+C at any time to abort."

# -----------------------------------------------------------------------------
# Step 1 — Pi Configuration
# -----------------------------------------------------------------------------
info "Step 1/8 — Pi Configuration"

if [[ ! -f "$ENV_FILE" ]]; then
  [[ ! -f "$ENV_EXAMPLE" ]] && error "env.example not found in ${SCRIPT_DIR}."
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  warn ".env not found — created from env.example."
fi

set +u
# shellcheck disable=SC1090
source "$ENV_FILE"
set -u

# Migrate legacy single-node vars if present
if [[ -n "${MESHTASTIC_NODE_IP:-}" ]] && [[ -z "${NODE_1_TYPE:-}" ]]; then
  warn "Migrating legacy MESHTASTIC_NODE_IP to numbered node model..."
  NODE_1_TYPE=tcp
  NODE_1_NAME="Meshtastic Node"
  NODE_1_IP="${MESHTASTIC_NODE_IP}"
  NODE_1_PORT="${MESHTASTIC_NODE_PORT:-4403}"
  success "Migrated: NODE_1_TYPE=tcp, NODE_1_IP=${NODE_1_IP}"
fi

echo
echo "  Current settings (press Enter to accept each):"
prompt PI_IP         "Pi IP address      " "${PI_IP:-}"
prompt HOST_PORT     "MeshMonitor port   " "${HOST_PORT:-8080}"
prompt TZ            "Timezone           " "${TZ:-America/Phoenix}"
prompt UPGRADE_TIME  "Auto-upgrade time  " "${UPGRADE_TIME:-03:00}"

# Auto-generate SESSION_SECRET on first run, never overwrite
if [[ -z "${SESSION_SECRET:-}" ]] || [[ "${SESSION_SECRET}" == *"REPLACE_WITH"* ]]; then
  SESSION_SECRET=$(openssl rand -hex 32 2>/dev/null || \
    cat /proc/sys/kernel/random/uuid | tr -d '-' | head -c 32)
  success "Session secret generated automatically."
else
  success "Session secret already configured — keeping existing value."
fi

ALLOWED_ORIGINS="http://${PI_IP}:${HOST_PORT}"
echo
echo "  ── Derived settings ──────────────────────────────────"
echo "  ALLOWED_ORIGINS : ${ALLOWED_ORIGINS}"
echo "  ──────────────────────────────────────────────────────"
[[ -z "${PI_IP:-}" ]] && error "Pi IP address is required."

# -----------------------------------------------------------------------------
# Step 2 — Docker Installation
# -----------------------------------------------------------------------------
info "Step 2/8 — Docker Installation"

if command -v docker &>/dev/null; then
  success "Docker already installed: $(docker --version)"
else
  echo
  echo "  Docker not found. Install now using the official script?"
  echo "    NOTE: Uses get.docker.com — the official, Pi-supported method."
  menu INSTALL_DOCKER 1 "Yes, install Docker" "No, abort"
  [[ "$INSTALL_DOCKER" == "2" ]] && error "Docker is required. Aborting."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "${USER}"
  success "Docker installed."
  warn "Relaunching under 'newgrp docker' to continue..."
  exec newgrp docker <<NEWGRP
    cd "${SCRIPT_DIR}" && bash setup.sh
NEWGRP
fi

if ! docker compose version &>/dev/null; then
  error "Docker Compose v2 not found. Ensure Docker Engine >= 23 is installed."
fi
success "Docker Compose v2 confirmed."

# -----------------------------------------------------------------------------
# Step 3 — Node Connections
# -----------------------------------------------------------------------------
info "Step 3/8 — Node Connections"

# Count existing nodes (loop-until-gap)
NODE_COUNT=0
while true; do
  TYPE_VAR="NODE_$(( NODE_COUNT + 1 ))_TYPE"
  [[ -z "${!TYPE_VAR:-}" ]] && break
  NODE_COUNT=$(( NODE_COUNT + 1 ))
done

# Initialize remaining scan arrays
REMAINING_SCAN_NAMES=()
REMAINING_SCAN_ADDRS=()

# ── Node helper functions ─────────────────────────────────────────────────────

add_tcp_node() {
  local idx="$1"
  echo
  echo "  ── TCP Node ─────────────────────────────────────────"
  prompt "NODE_${idx}_NAME" "Node name          " "Meshtastic Node"
  prompt "NODE_${idx}_IP"   "Node IP address    " ""
  local ip_var="NODE_${idx}_IP"
  local ip_val="${!ip_var:-}"
  echo
  echo "  Testing connectivity..."
  if ping -c1 -W2 "$ip_val" &>/dev/null 2>&1; then success "Ping ${ip_val} OK"
  else warn "Cannot ping ${ip_val} — check the IP and try again."; fi
  local port_var="NODE_${idx}_PORT"
  prompt "NODE_${idx}_PORT" "Node port          " "${!port_var:-4403}"
  local pv="${!port_var:-4403}"
  if bash -c "echo >/dev/tcp/${ip_val}/${pv}" 2>/dev/null; then success "Port ${pv} reachable OK"
  else warn "Port ${pv} not reachable — node may not be ready yet."; fi
  eval "NODE_${idx}_TYPE=tcp"
  success "TCP node ${idx} configured: ${ip_val}:${pv}"
}

add_ble_node() {
  local idx="$1"
  echo
  echo "  ── BLE Node ─────────────────────────────────────────"
  echo "  Connects a nearby Meshtastic node via Bluetooth."
  echo "  Device must be powered on and within ~10 meters."
  echo
  echo "  Do you know your node's BLE MAC address?"
  menu BLE_MAC_CHOICE 1 \
    "No  — scan for nearby Meshtastic devices" \
    "Yes — I will enter it manually"

  local ble_addr="" ble_name=""

  if [[ "$BLE_MAC_CHOICE" == "1" ]]; then
    # Ensure Bluetooth adapter is powered on
    if ! bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
      echo
      echo "  Bluetooth adapter is off — enabling..."
      sudo rfkill unblock bluetooth 2>/dev/null || true
      sleep 2
      sudo bluetoothctl power on 2>/dev/null || true
      sleep 2
      if ! bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
        warn "Could not enable Bluetooth adapter. Check hardware and try again."
        return 1
      fi
      success "Bluetooth adapter enabled."
    fi

    echo
    echo "  Scanning for Meshtastic devices..."
    echo "  (this may take 10-15 seconds — press Ctrl+C to abort)"
    echo

    docker run --rm --privileged \
      -v /var/run/dbus:/var/run/dbus \
      -v /var/lib/bluetooth:/var/lib/bluetooth:ro \
      ghcr.io/yeraze/meshtastic-ble-bridge:latest --scan > /tmp/mm-ble-scan.txt 2>/dev/null &
    SCAN_PID=$!
    spinner='|/-\'
    i=0
    while kill -0 $SCAN_PID 2>/dev/null; do
      printf "\r  Scanning... %s" "${spinner:$(( i % 4 )):1}"
      i=$(( i + 1 ))
      sleep 0.2
    done
    printf "\r  Scanning... done\n"
    SCAN_OUTPUT=$(cat /tmp/mm-ble-scan.txt 2>/dev/null || true)
    rm -f /tmp/mm-ble-scan.txt

    if [[ -z "$SCAN_OUTPUT" ]]; then
      warn "No Meshtastic devices found. Ensure device is powered on and in range."
      return 1
    fi

    # Parse output format: "  NAME - MAC"
    declare -a SCAN_NAMES=() SCAN_ADDRS=()
    while IFS= read -r line; do
      if [[ "$line" =~ ^[[:space:]]+(.+)[[:space:]]+-[[:space:]]+([0-9A-Fa-f:]{17})[[:space:]]*$ ]]; then
        SCAN_NAMES+=("${BASH_REMATCH[1]}")
        SCAN_ADDRS+=("${BASH_REMATCH[2]}")
      fi
    done <<< "$SCAN_OUTPUT"

    if [[ "${#SCAN_ADDRS[@]}" -eq 0 ]]; then
      warn "Scan completed but no devices were parsed. Try entering MAC manually."
      return 1
    fi

    echo
    echo "  Found devices:"
    for i in "${!SCAN_ADDRS[@]}"; do
      echo "    $(( i + 1 ))) ${SCAN_NAMES[$i]}  —  ${SCAN_ADDRS[$i]}"
    done
    echo
    local pick
    echo -en "  Select device [1]: "
    read -r pick
    [[ -z "$pick" ]] && pick=1
    local pidx=$(( pick - 1 ))
    ble_addr="${SCAN_ADDRS[$pidx]}"
    ble_name="${SCAN_NAMES[$pidx]}"
    success "Selected: ${ble_name} (${ble_addr})"

    # Name prompt after selection, defaulting to scanned device name
    local name_var="NODE_${idx}_NAME"
    prompt "$name_var" "Node name          " "${ble_name}"

    # Store remaining devices for "add another" loop
    REMAINING_SCAN_NAMES=()
    REMAINING_SCAN_ADDRS=()
    for i in "${!SCAN_ADDRS[@]}"; do
      [[ "$i" == "$pidx" ]] && continue
      REMAINING_SCAN_NAMES+=("${SCAN_NAMES[$i]}")
      REMAINING_SCAN_ADDRS+=("${SCAN_ADDRS[$i]}")
    done
  else
    prompt "NODE_${idx}_BLE_ADDRESS" "BLE MAC address    " ""
    local av="NODE_${idx}_BLE_ADDRESS"
    ble_addr="${!av:-}"
    local name_var="NODE_${idx}_NAME"
    prompt "$name_var" "Node name          " "BLE Node"
  fi

  eval "NODE_${idx}_BLE_ADDRESS='${ble_addr}'"
  eval "NODE_${idx}_TYPE=ble"

  echo
  echo "  ── Bluetooth Pairing ────────────────────────────────"
  echo "  Pairing ensures a stable connection, especially if"
  echo "  your device has a custom PIN or passkey set."
  echo
  echo "  If your device has a PIN or passkey:"
  echo "    • Watch your device screen — a 6-digit code may appear"
  echo "    • Type it here when prompted"
  echo "    • If no code appears, just press Enter to continue"
  echo
  echo "  If your device has no PIN, pairing still recommended"
  echo "  but can be skipped if the device doesn't support it."
  echo
  menu PAIR_CHOICE 1 \
    "Pair now  (recommended for PIN/passkey devices)" \
    "Skip pairing  (only for devices with no PIN)"

  if [[ "$PAIR_CHOICE" == "1" ]]; then
    echo
    echo "  ── Bluetooth Pairing ────────────────────────────────"
    echo "  Make sure your device is:"
    echo "    • Powered on and nearby (within ~10 meters)"
    echo "    • Not connected to another phone or app"
    echo
    echo "  You will now be dropped into a bluetoothctl session."
    echo "  Run these commands:"
    echo
    echo "    scan on"
    echo "    (wait for ${ble_name:-your device} to appear)"
    echo "    pair ${ble_addr}"
    echo "    trust ${ble_addr}"
    echo "    exit"
    echo
    echo "  If a PIN appears on your device screen, type it when prompted."
    echo "  Power cycle your device first if pairing is rejected."
    echo
    echo -en "  Press Enter to launch bluetoothctl: "
    read -r _
    echo

    # Hand control directly to bluetoothctl — full interactive PIN support
    bluetoothctl

    echo
    if bluetoothctl info "$ble_addr" 2>/dev/null | grep -q "Paired: yes"; then
      success "Pairing confirmed: ${ble_addr}"
    else
      warn "Pairing not detected. The bridge may still connect but"
      warn "PIN-protected devices will likely fail to send data."
      warn "Re-run setup.sh and pair again if the connection fails."
    fi
  else
    warn "Skipping pairing. If the device has a PIN, the bridge"
    warn "may connect but fail to exchange data with MeshMonitor."
    warn "Re-run setup.sh and choose to pair if this happens."
  fi
  success "BLE node ${idx} configured: ${ble_addr}"
}

add_serial_node() {
  local idx="$1"
  echo
  echo "  ── Serial/USB Node ──────────────────────────────────"
  echo
  echo "  PREREQUISITE: Serial mode must be enabled on the device."
  echo "  If not done, run from a computer connected to the device:"
  echo
  echo "    meshtastic --set serial.enabled true"
  echo "    meshtastic --set serial.echo false"
  echo "    meshtastic --set serial.mode SIMPLE"
  echo "    meshtastic --set serial.baud BAUD_115200"
  echo
  menu SERIAL_PREREQ 1 "Yes, serial mode is enabled" "No, I need to do that first"
  if [[ "$SERIAL_PREREQ" == "2" ]]; then
    warn "Enable serial mode first, then re-run setup.sh."
    return 1
  fi

  prompt "NODE_${idx}_NAME" "Node name          " "Serial Node"
  echo
  echo "  Available serial devices:"
  ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | nl -w2 -s') ' || \
    echo "    (none detected — ensure the device is plugged in)"
  echo
  prompt "NODE_${idx}_SERIAL_DEVICE" "Device path        " "/dev/ttyACM0"
  prompt "NODE_${idx}_BAUD"          "Baud rate          " "115200"
  local dev_var="NODE_${idx}_SERIAL_DEVICE"
  local dev_val="${!dev_var:-/dev/ttyACM0}"
  if [[ -e "$dev_val" ]]; then success "Device ${dev_val} found."
  else warn "Device ${dev_val} not found — ensure it is plugged in."; fi
  eval "NODE_${idx}_TYPE=serial"
  success "Serial node ${idx} configured: ${dev_val}"
}

remove_node() {
  echo
  echo "  ── Remove a Node ────────────────────────────────────"
  if [[ "$NODE_COUNT" -eq 0 ]]; then
    warn "No nodes configured."; return
  fi
  echo
  for i in $(seq 1 "$NODE_COUNT"); do
    t_var="NODE_${i}_TYPE" n_var="NODE_${i}_NAME"
    ip_var="NODE_${i}_IP" port_var="NODE_${i}_PORT"
    addr_var="NODE_${i}_BLE_ADDRESS" dev_var="NODE_${i}_SERIAL_DEVICE"
    node_type="${!t_var:-}" node_name="${!n_var:-Node ${i}}"
    case "$node_type" in
      tcp)    echo "    ${i}) TCP    — ${!ip_var:-?}:${!port_var:-4403} (${node_name})" ;;
      ble)    echo "    ${i}) BLE    — ${!addr_var:-?} (${node_name})" ;;
      serial) echo "    ${i}) Serial — ${!dev_var:-?} (${node_name})" ;;
    esac
  done
  local last=$(( NODE_COUNT + 1 ))
  echo "    ${last}) Cancel"
  echo -en "\n  Which node to remove [${last}]: "
  read -r RM_CHOICE
  [[ -z "$RM_CHOICE" ]] && RM_CHOICE="$last"
  if ! [[ "$RM_CHOICE" =~ ^[0-9]+$ ]] || \
     [[ "$RM_CHOICE" -lt 1 ]] || \
     [[ "$RM_CHOICE" -gt "$last" ]]; then
    warn "Invalid choice."; return
  fi
  [[ "$RM_CHOICE" -eq "$last" ]] && return

  local ridx="$RM_CHOICE"
  local t_var="NODE_${ridx}_TYPE" n_var="NODE_${ridx}_NAME"
  local node_type="${!t_var:-}" node_name="${!n_var:-Node ${ridx}}"
  local addr_var="NODE_${ridx}_BLE_ADDRESS"
  local ble_addr="${!addr_var:-}"

  echo
  echo "  Remove Node ${ridx}: ${node_name} (${node_type})?"
  menu CONFIRM_REMOVE 2 "Yes, remove this node" "No, cancel"
  [[ "$CONFIRM_REMOVE" == "2" ]] && return

  # BLE — unpair from host and stop bridge container
  if [[ "$node_type" == "ble" ]] && [[ -n "$ble_addr" ]]; then
    echo
    echo "  Removing Bluetooth pairing for ${ble_addr}..."
    bluetoothctl remove "$ble_addr" 2>/dev/null || true
    success "Bluetooth pairing removed."

    local ble_idx=0
    for j in $(seq 1 "$ridx"); do
      t_j="NODE_${j}_TYPE"
      [[ "${!t_j:-}" == "ble" ]] && ble_idx=$(( ble_idx + 1 ))
    done
    local container="meshmonitor-ble-${ble_idx}"
    if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
      docker stop "$container" 2>/dev/null || true
      docker rm "$container" 2>/dev/null || true
      success "Bridge container ${container} removed."
    fi

    echo
    echo "  ── MeshMonitor Source ────────────────────────────────"
    echo "  If you added this node as a source in MeshMonitor,"
    echo "  remove it manually:"
    echo "    Dashboard → Sources → ${node_name} → Delete"
    echo "  ─────────────────────────────────────────────────────"
  fi

  # Serial — stop and remove bridge container
  if [[ "$node_type" == "serial" ]]; then
    local ser_idx=0
    for j in $(seq 1 "$ridx"); do
      t_j="NODE_${j}_TYPE"
      [[ "${!t_j:-}" == "serial" ]] && ser_idx=$(( ser_idx + 1 ))
    done
    local container="meshmonitor-serial-${ser_idx}"
    if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
      docker stop "$container" 2>/dev/null || true
      docker rm "$container" 2>/dev/null || true
      success "Bridge container ${container} removed."
    fi

    echo
    echo "  ── MeshMonitor Source ────────────────────────────────"
    echo "  If you added this node as a source in MeshMonitor,"
    echo "  remove it manually:"
    echo "    Dashboard → Sources → ${node_name} → Delete"
    echo "  ─────────────────────────────────────────────────────"
  fi

  # Renumber remaining nodes by rebuilding env vars
  echo
  echo "  ── Stack will restart in step 8 to apply changes ────"
  local new_count=0
  for i in $(seq 1 "$NODE_COUNT"); do
    [[ "$i" -eq "$ridx" ]] && continue
    new_count=$(( new_count + 1 ))
    for suffix in TYPE NAME IP PORT BLE_ADDRESS SERIAL_DEVICE BAUD; do
      src_var="NODE_${i}_${suffix}"
      [[ -n "${!src_var:-}" ]] && eval "NODE_${new_count}_${suffix}='${!src_var}'"
    done
  done
  # Clear the last node slot
  for suffix in TYPE NAME IP PORT BLE_ADDRESS SERIAL_DEVICE BAUD; do
    eval "NODE_$(( new_count + 1 ))_${suffix}=''"
  done
  NODE_COUNT="$new_count"
  success "Node ${ridx} (${node_name}) removed. ${NODE_COUNT} node(s) remaining."
}

test_all_nodes() {
  echo
  echo "  ── Testing Node Connectivity ────────────────────────"
  local all_ok=true
  for i in $(seq 1 "$NODE_COUNT"); do
    local t_var="NODE_${i}_TYPE" n_var="NODE_${i}_NAME"
    local node_type="${!t_var:-}" node_name="${!n_var:-Node ${i}}"
    case "$node_type" in
      tcp)
        local ip_var="NODE_${i}_IP" port_var="NODE_${i}_PORT"
        local ip="${!ip_var:-}" port="${!port_var:-4403}"
        printf "  Node %d (%s)\n    Ping %s..." "$i" "$node_name" "$ip"
        if ping -c1 -W2 "$ip" &>/dev/null 2>&1; then echo " [OK]"
        else echo " [WARN] unreachable"; all_ok=false; fi
        printf "    Port %s..." "$port"
        if bash -c "echo >/dev/tcp/${ip}/${port}" 2>/dev/null; then echo " [OK]"
        else echo " [WARN] not reachable"; all_ok=false; fi
        ;;
      ble)
        local ble_idx=0
        for j in $(seq 1 "$i"); do
          t_j="NODE_${j}_TYPE"
          [[ "${!t_j:-}" == "ble" ]] && ble_idx=$(( ble_idx + 1 ))
        done
        local container="meshmonitor-ble-${ble_idx}"
        printf "  Node %d (%s)\n    BLE bridge %s..." "$i" "$node_name" "$container"
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
          echo " [OK] container running"
        else
          echo " [not started yet — will verify after stack launch]"
        fi
        ;;
      serial)
        local dev_var="NODE_${i}_SERIAL_DEVICE"
        local dev="${!dev_var:-}"
        printf "  Node %d (%s)\n    Device %s..." "$i" "$node_name" "$dev"
        if [[ -e "$dev" ]]; then echo " [OK]"
        else echo " [WARN] not found"; all_ok=false; fi
        ;;
    esac
  done
  echo "  ─────────────────────────────────────────────────────"
  if [[ "$all_ok" == "true" ]]; then
    success "All nodes reachable."
  else
    warn "One or more nodes have connectivity issues."
    echo
    menu TEST_ACTION 2 "Re-test all nodes" "Continue anyway" "Abort and fix issues first"
    case "$TEST_ACTION" in
      1) test_all_nodes ;;
      3) error "Aborting. Fix connectivity issues and re-run setup.sh." ;;
    esac
  fi
}

# ── Display existing nodes or fresh start menu ────────────────────────────────
if [[ "$NODE_COUNT" -gt 0 ]]; then
  echo
  echo "  ── Current node configuration ───────────────────────"
  for i in $(seq 1 "$NODE_COUNT"); do
    t_var="NODE_${i}_TYPE" n_var="NODE_${i}_NAME"
    ip_var="NODE_${i}_IP" port_var="NODE_${i}_PORT"
    addr_var="NODE_${i}_BLE_ADDRESS" dev_var="NODE_${i}_SERIAL_DEVICE"
    node_type="${!t_var:-}" node_name="${!n_var:-Node ${i}}"
    case "$node_type" in
      tcp)    echo "  Node ${i}: TCP    — ${!ip_var:-?}:${!port_var:-4403} (${node_name})" ;;
      ble)    echo "  Node ${i}: BLE    — ${!addr_var:-?} (${node_name})" ;;
      serial) echo "  Node ${i}: Serial — ${!dev_var:-?} (${node_name})" ;;
    esac
  done
  echo "  ─────────────────────────────────────────────────────"
  echo
  echo "  What would you like to do?"
  menu NODE_ACTION 1 \
    "Keep current configuration" \
    "Add a TCP/IP node" \
    "Add a BLE (Bluetooth) node" \
    "Add a serial/USB node" \
    "Test connectivity on all nodes" \
    "Remove a node"
else
  echo
  echo "  No nodes configured yet."
  echo
  echo "  How is your Meshtastic node connected?"
  menu NODE_ACTION 1 \
    "TCP/IP  — node on your LAN via WiFi or Ethernet" \
    "BLE     — node nearby via Bluetooth" \
    "Serial  — node physically connected via USB" \
    "Skip    — I will add sources via the Dashboard later"
  case "$NODE_ACTION" in
    1) NODE_ACTION=2 ;;
    2) NODE_ACTION=3 ;;
    3) NODE_ACTION=4 ;;
    4) NODE_ACTION=1 ;;
  esac
fi

# ── Execute node action ───────────────────────────────────────────────────────
ADD_MORE=true
NEXT_NODE=$(( NODE_COUNT + 1 ))
SKIP_CONNECTIVITY_TEST=false

case "$NODE_ACTION" in
  1) ADD_MORE=false ;;
  2) add_tcp_node    "$NEXT_NODE" && NODE_COUNT=$(( NODE_COUNT + 1 )) || true ;;
  3) add_ble_node    "$NEXT_NODE" && NODE_COUNT=$(( NODE_COUNT + 1 )) || true ;;
  4) add_serial_node "$NEXT_NODE" && NODE_COUNT=$(( NODE_COUNT + 1 )) || true ;;
  5) test_all_nodes; ADD_MORE=false; SKIP_CONNECTIVITY_TEST=true ;;
  6) remove_node; ADD_MORE=false ;;
esac

# ── Add more nodes loop ───────────────────────────────────────────────────────
while [[ "$ADD_MORE" == "true" ]]; do
  NEXT_NODE=$(( NODE_COUNT + 1 ))

  # Offer remaining BLE scan results first if available
  if [[ "${#REMAINING_SCAN_ADDRS[@]}" -gt 0 ]]; then
    echo
    echo "  Remaining devices from scan:"
    for i in "${!REMAINING_SCAN_ADDRS[@]}"; do
      echo "    $(( i + 1 ))) ${REMAINING_SCAN_NAMES[$i]}  —  ${REMAINING_SCAN_ADDRS[$i]}"
    done
    last=$(( ${#REMAINING_SCAN_ADDRS[@]} + 1 ))
    echo "    ${last}) No — done adding nodes"
    echo -en "\n  Choice [${last}]: "
    read -r MORE_CHOICE
    [[ -z "$MORE_CHOICE" ]] && MORE_CHOICE="$last"
    if ! [[ "$MORE_CHOICE" =~ ^[0-9]+$ ]] || \
       [[ "$MORE_CHOICE" -lt 1 ]] || \
       [[ "$MORE_CHOICE" -gt "$last" ]]; then
      warn "Invalid choice — please enter a number between 1 and ${last}."
      continue
    fi
    if [[ "$MORE_CHOICE" -lt "$last" ]]; then
      ridx=$(( MORE_CHOICE - 1 ))
      local_addr="${REMAINING_SCAN_ADDRS[$ridx]}"
      local_name="${REMAINING_SCAN_NAMES[$ridx]}"
      eval "NODE_${NEXT_NODE}_TYPE=ble"
      eval "NODE_${NEXT_NODE}_BLE_ADDRESS='${local_addr}'"
      eval "NODE_${NEXT_NODE}_NAME='${local_name}'"
      REMAINING_SCAN_NAMES=("${REMAINING_SCAN_NAMES[@]:0:$ridx}" "${REMAINING_SCAN_NAMES[@]:$(( ridx + 1 ))}")
      REMAINING_SCAN_ADDRS=("${REMAINING_SCAN_ADDRS[@]:0:$ridx}" "${REMAINING_SCAN_ADDRS[@]:$(( ridx + 1 ))}")
      NODE_COUNT=$(( NODE_COUNT + 1 ))
      # Offer pairing for this device
      echo
      echo "  ── Bluetooth Pairing ────────────────────────────────"
      echo "  Pair now for a stable connection (recommended for"
      echo "  PIN/passkey devices), or skip for devices with no PIN."
      echo
      menu PAIR_CHOICE 1 \
        "Pair now  (recommended for PIN/passkey devices)" \
        "Skip pairing  (only for devices with no PIN)"
      if [[ "$PAIR_CHOICE" == "1" ]]; then
        echo
        echo "  You will now be dropped into a bluetoothctl session."
        echo "  Run: scan on → pair ${local_addr} → trust ${local_addr} → exit"
        echo
        echo -en "  Press Enter to launch bluetoothctl: "
        read -r _
        bluetoothctl
        if bluetoothctl info "$local_addr" 2>/dev/null | grep -q "Paired: yes"; then
          success "Pairing confirmed: ${local_addr}"
        else
          warn "Pairing not detected — re-run setup.sh to pair if connection fails."
        fi
      else
        warn "Skipping pairing — re-run setup.sh to pair if connection fails."
      fi
      continue
    else
      ADD_MORE=false; break
    fi
  fi

  echo
  echo "  Add another node?"
  menu MORE_ACTION 4 \
    "Add another BLE node (new scan)" \
    "Add a TCP/IP node" \
    "Add a serial/USB node" \
    "No — done adding nodes"
  case "$MORE_ACTION" in
    1) add_ble_node    "$NEXT_NODE" && NODE_COUNT=$(( NODE_COUNT + 1 )) || true ;;
    2) add_tcp_node    "$NEXT_NODE" && NODE_COUNT=$(( NODE_COUNT + 1 )) || true ;;
    3) add_serial_node "$NEXT_NODE" && NODE_COUNT=$(( NODE_COUNT + 1 )) || true ;;
    4) ADD_MORE=false ;;
  esac
done

# Connectivity test before writing .env (skip if user already ran it via option 5)
[[ "$NODE_COUNT" -gt 0 ]] && [[ "$SKIP_CONNECTIVITY_TEST" == "false" ]] && test_all_nodes

# ── Node summary ──────────────────────────────────────────────────────────────
echo
echo "  ── Node Summary ─────────────────────────────────────"
if [[ "$NODE_COUNT" -eq 0 ]]; then
  echo "  No nodes configured — add via Dashboard → Sources after startup."
else
  for i in $(seq 1 "$NODE_COUNT"); do
    t_var="NODE_${i}_TYPE" n_var="NODE_${i}_NAME"
    ip_var="NODE_${i}_IP" port_var="NODE_${i}_PORT"
    addr_var="NODE_${i}_BLE_ADDRESS" dev_var="NODE_${i}_SERIAL_DEVICE"
    node_type="${!t_var:-}" node_name="${!n_var:-Node ${i}}"
    case "$node_type" in
      tcp)    echo "  Node ${i}: TCP    — ${!ip_var:-?}:${!port_var:-4403} (${node_name})" ;;
      ble)    echo "  Node ${i}: BLE    — ${!addr_var:-?} (${node_name})" ;;
      serial) echo "  Node ${i}: Serial — ${!dev_var:-?} (${node_name})" ;;
    esac
  done
fi
echo "  ─────────────────────────────────────────────────────"
success "Node configuration complete."

# ── Write .env ────────────────────────────────────────────────────────────────
{
cat <<EOF
# Generated by setup.sh on $(date)
# Managed by setup.sh — do not edit manually.
# DO NOT commit this file to git.

# ── Pi settings ───────────────────────────────────────────────────────────────
PI_IP=${PI_IP}
HOST_PORT=${HOST_PORT}
ALLOWED_ORIGINS=${ALLOWED_ORIGINS}
TRUST_PROXY=false
COOKIE_SECURE=false
SESSION_SECRET=${SESSION_SECRET}
TZ=${TZ}
UPGRADE_TIME=${UPGRADE_TIME:-03:00}

# ── Node connections ───────────────────────────────────────────────────────────
# Read by launch.sh. Loop-until-gap: read in order until NODE_N_TYPE is missing.
EOF
for i in $(seq 1 "$NODE_COUNT"); do
  t_var="NODE_${i}_TYPE"  n_var="NODE_${i}_NAME"
  ip_var="NODE_${i}_IP"   port_var="NODE_${i}_PORT"
  addr_var="NODE_${i}_BLE_ADDRESS"
  dev_var="NODE_${i}_SERIAL_DEVICE" baud_var="NODE_${i}_BAUD"
  node_type="${!t_var:-}"  node_name="${!n_var:-Node ${i}}"
  echo "NODE_${i}_TYPE=${node_type}"
  echo "NODE_${i}_NAME=\"${node_name}\""
  case "$node_type" in
    tcp)    echo "NODE_${i}_IP=${!ip_var:-}"; echo "NODE_${i}_PORT=${!port_var:-4403}" ;;
    ble)    echo "NODE_${i}_BLE_ADDRESS=${!addr_var:-}" ;;
    serial) echo "NODE_${i}_SERIAL_DEVICE=${!dev_var:-/dev/ttyACM0}"; echo "NODE_${i}_BAUD=${!baud_var:-115200}" ;;
  esac
done
} > "$ENV_FILE"
success ".env written."

# -----------------------------------------------------------------------------
# Step 4 — SD Card Write Minimization
# -----------------------------------------------------------------------------
info "Step 4/8 — SD Card Write Minimization"

if grep -q 'noatime' /etc/fstab; then
  success "noatime already set in /etc/fstab."
else
  echo
  echo "  Add noatime mount option to root partition?"
  echo "  NOTE: Reduces SD writes by not recording access timestamps."
  menu NOATIME_CHOICE 1 "Yes  (recommended)" "No"
  if [[ "$NOATIME_CHOICE" == "1" ]]; then
    sudo sed -i 's|\(PARTUUID=[^ ]*\s\+/\s\+ext4\s\+\)\(defaults\)|\1defaults,noatime|' /etc/fstab
    success "noatime added to /etc/fstab (takes effect on next reboot)."
  else warn "Skipped noatime."; fi
fi

JOURNAL_CONF="/etc/systemd/journald.conf.d/volatile.conf"
if [[ -f "$JOURNAL_CONF" ]]; then
  success "Volatile journal already configured."
else
  echo
  echo "  Configure systemd journal as volatile (RAM only, lost on reboot)?"
  echo "  NOTE: System logs cleared on reboot. MeshMonitor data unaffected."
  menu JOURNAL_CHOICE 1 "Yes  (recommended)" "No"
  if [[ "$JOURNAL_CHOICE" == "1" ]]; then
    sudo mkdir -p /etc/systemd/journald.conf.d
    sudo tee "$JOURNAL_CONF" > /dev/null <<'JEOF'
# MeshMonitor Pi — volatile journal to minimize SD card writes
[Journal]
Storage=volatile
RuntimeMaxUse=32M
JEOF
    sudo systemctl restart systemd-journald
    success "Volatile journal configured."
  else warn "Skipped volatile journal."; fi
fi

if grep -q 'tmpfs.*/var/log' /etc/fstab; then
  success "tmpfs /var/log already in /etc/fstab."
else
  echo
  echo "  Mount /var/log as tmpfs (RAM, 64MB, lost on reboot)?"
  echo "  NOTE: System log files go to RAM. Typical usage under 5MB."
  menu TMPFS_CHOICE 1 "Yes  (recommended)" "No"
  if [[ "$TMPFS_CHOICE" == "1" ]]; then
    echo "tmpfs  /var/log  tmpfs  defaults,noatime,size=64m  0  0" | sudo tee -a /etc/fstab > /dev/null
    success "tmpfs /var/log added to /etc/fstab (takes effect on next reboot)."
  else warn "Skipped tmpfs /var/log."; fi
fi

# -----------------------------------------------------------------------------
# Step 5 — Docker Daemon Configuration
# -----------------------------------------------------------------------------
info "Step 5/8 — Docker Daemon Configuration"

DOCKER_DAEMON="/etc/docker/daemon.json"
if [[ -f "$DOCKER_DAEMON" ]]; then
  warn "${DOCKER_DAEMON} already exists:"
  cat "$DOCKER_DAEMON"
  echo
  echo "  Overwrite with MeshMonitor Pi log limits?"
  echo "  NOTE: Per-container limits in docker-compose.yml apply regardless."
  menu DAEMON_CHOICE 1 \
    "No  — contents match, keep as-is" \
    "Yes — overwrite with repo version"
  if [[ "$DAEMON_CHOICE" == "2" ]]; then
    sudo cp "$DAEMON_JSON" "$DOCKER_DAEMON"
    sudo systemctl restart docker
    success "daemon.json updated and Docker restarted."
  else warn "Skipped daemon.json update."; fi
else
  sudo mkdir -p /etc/docker
  sudo cp "$DAEMON_JSON" "$DOCKER_DAEMON"
  sudo systemctl restart docker
  success "daemon.json installed. System-wide Docker log limits active."
fi

# -----------------------------------------------------------------------------
# Step 6 — Hardware Watchdog
# -----------------------------------------------------------------------------
info "Step 6/8 — Hardware Watchdog"

# fuser output has leading spaces — strip with tr -d ' ' before comparison
WATCHDOG_OWNER=$(sudo fuser /dev/watchdog0 2>/dev/null | tr -d ' ' || true)
if [[ "$WATCHDOG_OWNER" == "1" ]]; then
  success "Hardware watchdog active — managed by systemd (Broadcom BCM2835)."
  if grep -q 'dtparam=watchdog=on' /boot/firmware/config.txt 2>/dev/null; then
    success "dtparam=watchdog=on already set in /boot/firmware/config.txt."
  else
    echo "dtparam=watchdog=on" | sudo tee -a /boot/firmware/config.txt > /dev/null
    success "dtparam=watchdog=on added to /boot/firmware/config.txt."
  fi
  WATCHDOG_STATUS=$(systemctl is-enabled watchdog 2>/dev/null || true)
  if [[ "$WATCHDOG_STATUS" == "enabled" ]]; then
    warn "Disabling redundant userspace watchdog daemon (systemd handles this on Bookworm)."
    sudo systemctl stop watchdog 2>/dev/null || true
    sudo systemctl disable watchdog 2>/dev/null || true
    success "Userspace watchdog daemon disabled."
  fi
else
  if systemctl is-active --quiet watchdog 2>/dev/null; then
    success "Userspace watchdog daemon already active."
  else
    echo
    echo "  Enable hardware watchdog (auto-reboot on system hang)?"
    menu WD_CHOICE 1 "Yes  (recommended)" "No"
    if [[ "$WD_CHOICE" == "1" ]]; then
      if ! grep -q 'dtparam=watchdog=on' /boot/firmware/config.txt 2>/dev/null; then
        echo "dtparam=watchdog=on" | sudo tee -a /boot/firmware/config.txt > /dev/null
        success "dtparam=watchdog=on added to /boot/firmware/config.txt."
      fi
      if ! command -v watchdog &>/dev/null; then sudo apt-get install -y watchdog; fi
      sudo tee /etc/watchdog.conf > /dev/null <<'WEOF'
# MeshMonitor Pi — hardware watchdog configuration
watchdog-device = /dev/watchdog
watchdog-timeout = 15
interval = 5
max-load-1 = 24
WEOF
      echo 'bcm2835_wdt' | sudo tee /etc/modules-load.d/bcm2835_wdt.conf > /dev/null
      sudo systemctl enable watchdog
      sudo systemctl start watchdog
      success "Hardware watchdog daemon enabled."
    else warn "Skipped hardware watchdog."; fi
  fi
fi

# -----------------------------------------------------------------------------
# Step 7 — systemd Boot Service + Auto-Upgrade Cron
# -----------------------------------------------------------------------------
info "Step 7/8 — systemd Boot Service + Auto-Upgrade Cron"

SYSTEMD_UNIT="/etc/systemd/system/meshmonitor.service"
echo
echo "  Installing systemd service (always updated to reflect current config)..."

sudo tee "$SYSTEMD_UNIT" > /dev/null <<SEOF
[Unit]
Description=MeshMonitor Pi Stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${SCRIPT_DIR}
ExecStart=${SCRIPT_DIR}/launch.sh up -d
ExecStop=${SCRIPT_DIR}/launch.sh down
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
SEOF

sudo systemctl daemon-reload
sudo systemctl enable meshmonitor.service
success "meshmonitor.service installed and enabled."

# Auto-upgrade cron (always update to reflect current SCRIPT_DIR and time)
CRON_MARKER="meshmonitor-pi auto-upgrade"
UPGRADE_HOUR=$(echo "${UPGRADE_TIME:-03:00}" | cut -d: -f1)
UPGRADE_MIN=$(echo "${UPGRADE_TIME:-03:00}"  | cut -d: -f2)
CRON_LINE="${UPGRADE_MIN} ${UPGRADE_HOUR} * * * cd ${SCRIPT_DIR} && ${SCRIPT_DIR}/launch.sh pull && ${SCRIPT_DIR}/launch.sh up -d >> ${UPGRADE_LOG} 2>&1 && tail -500 ${UPGRADE_LOG} > /tmp/mm-trim && mv /tmp/mm-trim ${UPGRADE_LOG} # ${CRON_MARKER}"

EXISTING_CRON=$(crontab -l 2>/dev/null || true)
CLEAN_CRON=$(echo "$EXISTING_CRON" | grep -v "$CRON_MARKER" || true)
echo -e "${CLEAN_CRON}\n${CRON_LINE}" | crontab -
success "Auto-upgrade cron installed/updated (daily at ${UPGRADE_TIME:-03:00})."
success "Upgrade log: ${UPGRADE_LOG}"

# -----------------------------------------------------------------------------
# Step 8 — Pull Images and Start Stack
# -----------------------------------------------------------------------------
info "Step 8/8 — Start MeshMonitor Stack"

echo
echo "  Pull latest images and start the stack now?"
echo "  NOTE: Safe on re-runs — containers restart only if configuration changed."
menu START_CHOICE 1 "Yes  (recommended)" "No — I will start manually"

# Capture first-run state before stack launch changes it
FIRST_RUN=false
is_first_run && FIRST_RUN=true

if [[ "$START_CHOICE" == "1" ]]; then
  cd "$SCRIPT_DIR"
  chmod +x "$LAUNCH_SH"
  "$LAUNCH_SH" pull
  echo
  "$LAUNCH_SH" up -d

  echo
  echo "  Waiting for stack to become healthy..."
  sleep 5

  echo
  echo "  ── Post-start connectivity ──────────────────────────"
  BLE_IDX=0; SERIAL_IDX=0
  for i in $(seq 1 "$NODE_COUNT"); do
    t_var="NODE_${i}_TYPE" n_var="NODE_${i}_NAME"
    node_type="${!t_var:-}" node_name="${!n_var:-Node ${i}}"
    case "$node_type" in
      tcp)
        ip_var="NODE_${i}_IP" port_var="NODE_${i}_PORT"
        printf "  Node %d (%s — TCP): " "$i" "$node_name"
        if bash -c "echo >/dev/tcp/${!ip_var:-}/${!port_var:-4403}" 2>/dev/null; then
          echo "[OK] connected"
        else echo "[WARN] not reachable — check node is online"; fi
        ;;
      ble)
        BLE_IDX=$(( BLE_IDX + 1 ))
        CONTAINER="meshmonitor-ble-${BLE_IDX}"
        printf "  Node %d (%s — BLE bridge %d): " "$i" "$node_name" "$BLE_IDX"
        attempts=0; ready=false
        while [[ $attempts -lt 6 ]]; do
          if docker inspect --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q "true"; then
            ready=true; break
          fi
          sleep 5; attempts=$(( attempts + 1 ))
        done
        if [[ "$ready" == "true" ]]; then echo "[OK] container running"
        else echo "[starting] check: docker logs ${CONTAINER}"; fi
        ;;
      serial)
        SERIAL_IDX=$(( SERIAL_IDX + 1 ))
        CONTAINER="meshmonitor-serial-${SERIAL_IDX}"
        printf "  Node %d (%s — serial bridge %d): " "$i" "$node_name" "$SERIAL_IDX"
        if docker inspect --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q "true"; then
          echo "[OK] container running"
        else echo "[WARN] container not found — check: docker compose logs"; fi
        ;;
    esac
  done
  echo "  ─────────────────────────────────────────────────────"
  success "Stack started."
else
  warn "Stack not started. Start manually with:"
  echo "    cd ${SCRIPT_DIR} && ./launch.sh up -d"
fi

# -----------------------------------------------------------------------------
# Post-setup communication
# -----------------------------------------------------------------------------

# ── Node summary ──────────────────────────────────────────────────────────────
print_node_summary() {
  local ble_c=0 ser_c=0
  echo "  ── Configured nodes ──────────────────────────────────"
  for i in $(seq 1 "$NODE_COUNT"); do
    t_var="NODE_${i}_TYPE" n_var="NODE_${i}_NAME"
    node_type="${!t_var:-}" node_name="${!n_var:-Node ${i}}"
    case "$node_type" in
      tcp)
        ip_var="NODE_${i}_IP" port_var="NODE_${i}_PORT"
        printf "  ✓  TCP    — %s:%s (%s)\n" "${!ip_var:-?}" "${!port_var:-4403}" "$node_name"
        ;;
      ble)
        ble_c=$(( ble_c + 1 ))
        printf "  ✓  BLE    — meshmonitor-ble-%d (%s)\n" "$ble_c" "$node_name"
        ;;
      serial)
        ser_c=$(( ser_c + 1 ))
        printf "  ✓  Serial — meshmonitor-serial-%d (%s)\n" "$ser_c" "$node_name"
        ;;
    esac
  done
  echo "  ─────────────────────────────────────────────────────"
}

# ── Bridge action block ───────────────────────────────────────────────────────
print_bridge_box() {
  local ble_c=0 ser_c=0 has_bridges=false
  for i in $(seq 1 "$NODE_COUNT"); do
    t_var="NODE_${i}_TYPE"
    if [[ "${!t_var:-}" == "ble" || "${!t_var:-}" == "serial" ]]; then
      has_bridges=true
    fi
  done
  [[ "$has_bridges" == "false" ]] && return 0

  echo "  ── ACTION REQUIRED — ADD YOUR BRIDGE NODES ──────────"
  echo
  echo "  Your bridge containers are running but MeshMonitor"
  echo "  doesn't know about them yet."
  echo
  echo "  For each node below, go to:"
  echo "  Dashboard → Sources → Add Source → TCP"
  echo
  echo "  NOTE: Even though these are Bluetooth/serial nodes,"
  echo "  you add them as TCP sources — the bridge translates"
  echo "  the connection behind the scenes."
  echo
  for i in $(seq 1 "$NODE_COUNT"); do
    t_var="NODE_${i}_TYPE" n_var="NODE_${i}_NAME"
    node_type="${!t_var:-}" node_name="${!n_var:-Node ${i}}"
    case "$node_type" in
      ble)
        ble_c=$(( ble_c + 1 ))
        echo "  BLE — ${node_name}"
        echo "    Host : meshmonitor-ble-${ble_c}"
        echo "    Port : 4403"
        echo
        ;;
      serial)
        ser_c=$(( ser_c + 1 ))
        echo "  Serial — ${node_name}"
        echo "    Host : meshmonitor-serial-${ser_c}"
        echo "    Port : 4403"
        echo
        ;;
    esac
  done
  echo "  ─────────────────────────────────────────────────────"
}

# ── Password box — first run only ────────────────────────────────────────────
print_password_box() {
  [[ "$FIRST_RUN" == "true" ]] || return 0
  cat <<EOF

  ╔══════════════════════════════════════════════════════╗
  ║  ⚠️  ACTION REQUIRED — CHANGE YOUR PASSWORD NOW      ║
  ║                                                      ║
  ║  MeshMonitor is using default credentials.           ║
  ║  Anyone on your network can log in until you         ║
  ║  change this.                                        ║
  ║                                                      ║
  ║  URL      : http://${PI_IP}:${HOST_PORT}             ║
  ║  Username : admin                                    ║
  ║  Password : changeme                                 ║
  ║                                                      ║
  ║  Top-right menu → admin → Change Password            ║
  ╚══════════════════════════════════════════════════════╝
EOF
}

# ── Static notes block ────────────────────────────────────────────────────────
print_notes() {
  cat <<EOF

  ── TROUBLESHOOTING ───────────────────────────────────

  BLE bridge not connecting?
    docker logs meshmonitor-ble-1  (or meshmonitor-ble-2, etc.)

  Serial bridge not connecting?
    docker logs meshmonitor-serial-1

  Node not appearing after adding source?
    Dashboard → Sources — check the status indicator

  Re-run setup to add nodes or change settings:
    cd ${SCRIPT_DIR} && ./setup.sh

  MeshMonitor changelog (check before upgrades):
    https://github.com/Yeraze/meshmonitor/blob/main/CHANGELOG.md

  Community support:
    https://discord.gg/JVR3VBETQE

  ── YOUR SETUP NOTES ──────────────────────────────────

  These instructions saved to: ${NEXT_STEPS_FILE}
  Full setup log saved to:     ${LOG_FILE}
  Upgrade log (nightly):       ${UPGRADE_LOG}

  To view next steps at any time:
    cat ${NEXT_STEPS_FILE}
EOF
}

# ── Print to terminal ─────────────────────────────────────────────────────────
echo
echo "============================================================"
echo "  Setup complete."
echo "============================================================"
echo
print_node_summary
print_password_box
if [[ "$FIRST_RUN" == "true" ]]; then
  echo
  echo "  ── REBOOT REQUIRED ───────────────────────────────────"
  echo
  echo "  Run this now to apply SD card optimizations:"
  echo "    sudo reboot"
  echo
fi
echo
print_bridge_box
print_notes
echo "============================================================"

# ── Write next-steps file ─────────────────────────────────────────────────────
{
  echo "MeshMonitor Pi — Setup Notes"
  echo "Generated: $(date)"
  echo "Web UI: http://${PI_IP}:${HOST_PORT}"
  echo
  print_node_summary
  print_password_box
  echo
  print_bridge_box
  print_notes
} > "$NEXT_STEPS_FILE"

success "Next steps saved to ${NEXT_STEPS_FILE}"
