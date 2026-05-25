#!/usr/bin/env bash
# =============================================================================
# launch.sh — MeshMonitor Pi Stack Launcher
# =============================================================================
#
# NON-INTERACTIVE. Called by systemd on boot and by the cron job for upgrades.
# Also used for manual operations: ./launch.sh up -d, ./launch.sh down, ./launch.sh pull, ./launch.sh status
#
# What this script does:
#   1. Reads node configuration from .env
#   2. Generates docker-compose.generated.yml for BLE/serial bridge services
#   3. Runs docker compose with the correct file set
#
# docker-compose.generated.yml is overwritten on every run. Do not edit it.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
GENERATED_COMPOSE="${SCRIPT_DIR}/docker-compose.generated.yml"

# -----------------------------------------------------------------------------
# Status subcommand
# -----------------------------------------------------------------------------
if [[ "${1:-}" == "status" ]]; then
  echo
  echo "  ── MeshMonitor Pi — Stack Status ─────────────────────"
  echo
  # Container health
  echo "  Containers:"
  docker ps --format "{{.Names}}\t{{.Status}}" | grep "^meshmonitor" | sed 's/^/    /' || \
    echo "    (no meshmonitor containers running)"
  echo

  # MeshMonitor health endpoint and version
  if docker inspect --format '{{.State.Running}}' meshmonitor 2>/dev/null | grep -q "true"; then
    HEALTH=$(docker inspect --format '{{.State.Health.Status}}' meshmonitor 2>/dev/null || echo "unknown")
    VERSION=$(docker exec meshmonitor cat /app/package.json 2>/dev/null | grep '"version"' | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/' || echo "unknown")
    echo "  Health  : ${HEALTH}"
    echo "  Version : v${VERSION}"
  fi

  # Web UI URL
  if [[ -f "$ENV_FILE" ]]; then
    set +u
    source "$ENV_FILE" 2>/dev/null || true
    set -u
    PI_IP="${PI_IP:-?}"
    HOST_PORT="${HOST_PORT:-8080}"
    echo "  URL     : http://${PI_IP}:${HOST_PORT}"
  fi

  # Last upgrade
  UPGRADE_LOG="${HOME}/meshmonitor-upgrade.log"
  if [[ -f "$UPGRADE_LOG" ]]; then
    LAST_DATE=$(stat -c '%y' "$UPGRADE_LOG" 2>/dev/null | cut -d. -f1 || echo "unknown")
    # Look for pulled image digest or "up-to-date" confirmation
    LAST_LINE=$(grep -E "(ghcr\.io|Status:|up-to-date|newer|pulled)" "$UPGRADE_LOG" 2>/dev/null | tail -1 || true)
    echo "  Last upgrade : ${LAST_DATE}"
    [[ -n "$LAST_LINE" ]] && echo "    ${LAST_LINE}"
  else
    echo "  Last upgrade : no log found"
  fi
  echo

  # Disk usage
  echo "  Disk:"
  df -h / | awk 'NR==2 {printf "    Used: %s / %s (%s)\n", $3, $2, $5}'
  echo

  # Uptime
  echo "  Uptime: $(uptime -p 2>/dev/null || uptime)"
  echo
  echo "  ─────────────────────────────────────────────────────"
  echo
  exit 0
fi

# -----------------------------------------------------------------------------
# Load .env
# -----------------------------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERROR] .env not found in ${SCRIPT_DIR}. Run setup.sh first." >&2
  exit 1
fi

set +u
# shellcheck disable=SC1090
source "$ENV_FILE"
set -u

# -----------------------------------------------------------------------------
# Read numbered node configuration
# Loop until a missing NODE_N_TYPE is found — no NODE_COUNT needed.
# -----------------------------------------------------------------------------
BLE_COUNTER=0
SERIAL_COUNTER=0
HAS_BRIDGES=false
BRIDGE_SERVICES=""
BRIDGE_SUMMARY=""

N=1
while true; do
  TYPE_VAR="NODE_${N}_TYPE"
  NODE_TYPE="${!TYPE_VAR:-}"
  [[ -z "$NODE_TYPE" ]] && break

  NAME_VAR="NODE_${N}_NAME"
  NODE_NAME="${!NAME_VAR:-Node ${N}}"

  case "$NODE_TYPE" in
    tcp)
      IP_VAR="NODE_${N}_IP"
      PORT_VAR="NODE_${N}_PORT"
      BRIDGE_SUMMARY+="  Node ${N}: TCP    — ${!IP_VAR:-?}:${!PORT_VAR:-4403} (${NODE_NAME})\n"
      ;;

    ble)
      BLE_COUNTER=$(( BLE_COUNTER + 1 ))
      HAS_BRIDGES=true
      ADDR_VAR="NODE_${N}_BLE_ADDRESS"
      BLE_ADDR="${!ADDR_VAR:-}"
      CONTAINER="meshmonitor-ble-${BLE_COUNTER}"
      BRIDGE_SUMMARY+="  Node ${N}: BLE    — ${BLE_ADDR} → ${CONTAINER} (${NODE_NAME})\n"
      BRIDGE_SERVICES+="
  ${CONTAINER}:
    image: ghcr.io/yeraze/meshtastic-ble-bridge:latest
    container_name: ${CONTAINER}
    privileged: true
    restart: unless-stopped
    command: \"${BLE_ADDR}\"
    volumes:
      - /var/run/dbus:/var/run/dbus
      - /var/lib/bluetooth:/var/lib/bluetooth:ro
    networks:
      - meshtastic_net
    logging:
      driver: local
      options:
        max-size: \"100k\"
        max-file: \"2\"
"
      ;;

    serial)
      SERIAL_COUNTER=$(( SERIAL_COUNTER + 1 ))
      HAS_BRIDGES=true
      DEV_VAR="NODE_${N}_SERIAL_DEVICE"
      BAUD_VAR="NODE_${N}_BAUD"
      SERIAL_DEV="${!DEV_VAR:-/dev/ttyACM0}"
      SERIAL_BAUD="${!BAUD_VAR:-115200}"
      CONTAINER="meshmonitor-serial-${SERIAL_COUNTER}"
      BRIDGE_SUMMARY+="  Node ${N}: Serial — ${SERIAL_DEV} → ${CONTAINER} (${NODE_NAME})\n"
      BRIDGE_SERVICES+="
  ${CONTAINER}:
    image: ghcr.io/yeraze/meshtastic-serial-bridge:latest
    container_name: ${CONTAINER}
    restart: unless-stopped
    devices:
      - ${SERIAL_DEV}:${SERIAL_DEV}
    environment:
      - SERIAL_DEVICE=${SERIAL_DEV}
      - BAUD_RATE=${SERIAL_BAUD}
    networks:
      - meshtastic_net
    logging:
      driver: local
      options:
        max-size: \"100k\"
        max-file: \"2\"
"
      ;;

    *)
      echo "[WARN] Unknown node type '${NODE_TYPE}' for NODE_${N} — skipping." >&2
      ;;
  esac

  N=$(( N + 1 ))
done

# -----------------------------------------------------------------------------
# Generate docker-compose.generated.yml if any bridge nodes exist
# -----------------------------------------------------------------------------
if [[ "$HAS_BRIDGES" == "true" ]]; then
  cat > "$GENERATED_COMPOSE" <<EOF
# =============================================================================
# docker-compose.generated.yml — AUTO-GENERATED by launch.sh
# Do not edit — this file is overwritten on every launch.
# Edit .env and re-run setup.sh to change node configuration.
# =============================================================================

services:
${BRIDGE_SERVICES}
networks:
  meshtastic_net:
    external: true
    name: meshmonitor-pi_meshtastic_net
EOF
fi

# -----------------------------------------------------------------------------
# Build and run compose command
# -----------------------------------------------------------------------------
COMPOSE_ARGS=(docker compose -f "${SCRIPT_DIR}/docker-compose.yml")
if [[ "$HAS_BRIDGES" == "true" ]]; then
  COMPOSE_ARGS+=(-f "${GENERATED_COMPOSE}")
fi

# Require a subcommand — running with no args passes nothing to docker compose
# which prints its own help, but we give a clearer message first.
if [[ $# -eq 0 ]]; then
  echo "[ERROR] No subcommand given. Usage: launch.sh <up -d | down | pull | status>" >&2
  exit 1
fi

# Print summary once, then exec compose
echo "  MeshMonitor Pi — launching stack"
echo "  ─────────────────────────────────────────────────────"
printf "%b" "$BRIDGE_SUMMARY"
echo "  ─────────────────────────────────────────────────────"

exec "${COMPOSE_ARGS[@]}" --progress=tty "$@"
