#!/usr/bin/env bash
# =============================================================================
# launch.sh — MeshMonitor Pi Stack Launcher
# =============================================================================
#
# NON-INTERACTIVE. Called by systemd on boot and by the cron job for upgrades.
# Also used for manual operations: ./launch.sh up -d, ./launch.sh down, ./launch.sh pull, ./launch.sh status, ./launch.sh prune
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
UPGRADE_LOG="${HOME}/meshmonitor-upgrade.log"
RESULT_FILE="${HOME}/.meshmonitor-upgrade-result"

# -----------------------------------------------------------------------------
# Helpers — alerting and result tracking
# -----------------------------------------------------------------------------

# Write outcome to result file. Args: SUCCESS|FAILED [reason]
write_result() {
  local outcome="${1}"
  local reason="${2:-}"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  {
    echo "OUTCOME=${outcome}"
    echo "TIMESTAMP=\"${ts}\""
    echo "REASON=\"${reason}\""
  } > "${RESULT_FILE}"
}

# Fire ntfy.sh notification on upgrade failure. No-op if NTFY_TOPIC unset.
notify_failure() {
  local reason="${1:-unknown failure}"
  # Load .env for NTFY_TOPIC if not already in environment
  if [[ -z "${NTFY_TOPIC:-}" && -f "${ENV_FILE}" ]]; then
    set +u
    # shellcheck disable=SC1090
    NTFY_TOPIC="$(source "${ENV_FILE}" 2>/dev/null; echo "${NTFY_TOPIC:-}")"
    set -u
  fi
  [[ -z "${NTFY_TOPIC:-}" ]] && return 0
  curl -s --max-time 10 \
    -H "Title: MeshMonitor Upgrade Failed" \
    -H "Priority: high" \
    -H "Tags: warning" \
    -d "Host: $(hostname) | $(date '+%Y-%m-%d %H:%M') | ${reason}" \
    "https://ntfy.sh/${NTFY_TOPIC}" > /dev/null 2>&1 || true
}

# -----------------------------------------------------------------------------
# Prune subcommand
# -----------------------------------------------------------------------------
if [[ "${1:-}" == "prune" ]]; then
  echo
  echo "  ── MeshMonitor Pi — Docker Prune ─────────────────────"
  echo
  echo "  Removing unused images, containers, and networks..."
  echo "  (volumes are never touched)"
  echo
  {
    echo "──────────────────────────────────────────────────────"
    echo "  Docker prune — $(date)"
    echo "──────────────────────────────────────────────────────"
    docker system prune -af 2>&1
    echo
  } | tee -a "${UPGRADE_LOG}"
  echo "  ─────────────────────────────────────────────────────"
  echo
  exit 0
fi

# -----------------------------------------------------------------------------
# Status subcommand
# -----------------------------------------------------------------------------
if [[ "${1:-}" == "status" ]]; then
  echo
  echo "  ── MeshMonitor Pi — Stack Status ─────────────────────"
  echo
  # Container health
  echo "  Containers:"
  docker ps --format "{{.Names}}  —  {{.Status}}" | grep "^meshmonitor" | sed 's/^/    /' || \
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

  # Last upgrade result
  if [[ -f "$RESULT_FILE" ]]; then
    set +u
    # shellcheck disable=SC1090
    source "$RESULT_FILE" 2>/dev/null || true
    set -u
    OUTCOME="${OUTCOME:-unknown}"
    TIMESTAMP="${TIMESTAMP:-unknown}"
    REASON="${REASON:-}"

    # Calculate staleness
    STALE_WARNING=""
    if [[ "$TIMESTAMP" != "unknown" ]]; then
      LAST_EPOCH=$(date -d "$TIMESTAMP" +%s 2>/dev/null || echo 0)
      NOW_EPOCH=$(date +%s)
      AGE_HOURS=$(( (NOW_EPOCH - LAST_EPOCH) / 3600 ))
      AGE_DAYS=$(( AGE_HOURS / 24 ))
      if [[ $AGE_HOURS -lt 24 ]]; then
        AGE_STR="${AGE_HOURS}h ago"
      else
        AGE_STR="${AGE_DAYS}d ago"
      fi
      [[ $AGE_HOURS -gt 48 ]] && STALE_WARNING=" ── cron may not be running"
    else
      AGE_STR="unknown"
    fi

    if [[ "$OUTCOME" == "SUCCESS" ]]; then
      echo "  Last upgrade : ✓ SUCCESS  (${AGE_STR})${STALE_WARNING}"
    else
      echo "  Last upgrade : ✗ FAILED   (${AGE_STR})${STALE_WARNING}"
      [[ -n "$REASON" ]] && echo "    Reason: ${REASON}"
    fi
  else
    echo "  Last upgrade : no result recorded yet"
  fi

  # ntfy alerting status
  NTFY_STATUS="not configured"
  if [[ -f "$ENV_FILE" ]]; then
    set +u
    _NTFY="$(source "${ENV_FILE}" 2>/dev/null; echo "${NTFY_TOPIC:-}")"
    set -u
    [[ -n "$_NTFY" ]] && NTFY_STATUS="configured"
  fi
  echo "  NTFY alerts  : ${NTFY_STATUS}"
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
  echo "[ERROR] No subcommand given. Usage: launch.sh <up -d | down | pull | status | prune>" >&2
  exit 1
fi

# Print summary once, then exec or run compose
echo "  MeshMonitor Pi — launching stack"
echo "  ─────────────────────────────────────────────────────"
printf "%b" "$BRIDGE_SUMMARY"
echo "  ─────────────────────────────────────────────────────"

# pull and up -d get result tracking and failure alerting.
# All other subcommands (down, etc.) pass straight through.
if [[ "${1:-}" == "pull" ]]; then
  set +e
  "${COMPOSE_ARGS[@]}" --progress=tty pull
  PULL_EXIT=$?
  set -e
  if [[ $PULL_EXIT -ne 0 ]]; then
    write_result "FAILED" "docker compose pull exited ${PULL_EXIT}"
    notify_failure "docker compose pull failed (exit ${PULL_EXIT})"
    echo "[ERROR] docker compose pull failed (exit ${PULL_EXIT})" >&2
    exit $PULL_EXIT
  fi
  exit 0
fi

if [[ "${1:-}" == "up" ]]; then
  set +e
  "${COMPOSE_ARGS[@]}" --progress=tty "$@"
  UP_EXIT=$?
  set -e
  if [[ $UP_EXIT -ne 0 ]]; then
    write_result "FAILED" "docker compose up exited ${UP_EXIT}"
    notify_failure "docker compose up failed (exit ${UP_EXIT})"
    echo "[ERROR] docker compose up failed (exit ${UP_EXIT})" >&2
    exit $UP_EXIT
  fi
  write_result "SUCCESS"
  exit 0
fi

exec "${COMPOSE_ARGS[@]}" --progress=tty "$@"
