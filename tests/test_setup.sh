#!/usr/bin/env bash
# =============================================================================
# tests/test_setup.sh — meshmonitor-pi logic tests
# =============================================================================
# Tests pure validation logic extracted from setup.sh.
# No Docker, no Pi hardware, no network access required.
# Safe for public review — contains no secrets or personal data.
#
# Usage:
#   bash tests/test_setup.sh
#
# Exit code: 0 if all tests pass, 1 if any fail.
# =============================================================================

set -uo pipefail

PASS=0
FAIL=0

# -----------------------------------------------------------------------------
# Test harness
# -----------------------------------------------------------------------------
assert_true() {
  local desc="$1" result="${2:-}"
  if [[ "$result" == "true" ]]; then
    echo "  [PASS] ${desc}"
    PASS=$(( PASS + 1 ))
  else
    echo "  [FAIL] ${desc}"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_eq() {
  local desc="$1" expected="${2:-}" actual="${3:-}"
  if [[ "$expected" == "$actual" ]]; then
    echo "  [PASS] ${desc}"
    PASS=$(( PASS + 1 ))
  else
    echo "  [FAIL] ${desc} — expected '${expected}', got '${actual}'"
    FAIL=$(( FAIL + 1 ))
  fi
}

# -----------------------------------------------------------------------------
# Validation functions (mirrors setup.sh logic exactly)
# -----------------------------------------------------------------------------

is_valid_ip() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

is_valid_mac() {
  [[ "$1" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]
}

is_valid_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] && [[ "$p" -ge 1 ]] && [[ "$p" -le 65535 ]]
}

is_valid_time() {
  [[ "$1" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]
}

# Node renumber: given a removal index (1-based) and a list of node types,
# return the renumbered list one entry per line.
# Mirrors the remove_node() renumber loop in setup.sh.
renumber_nodes() {
  local ridx="$1"; shift
  local -a result=()
  local slot=0
  for t in "$@"; do
    slot=$(( slot + 1 ))
    [[ "$slot" -eq "$ridx" ]] && continue
    result+=("$t")
  done
  printf '%s\n' "${result[@]}"
}

# .env hash comparison: strip lines starting with "# Generated" then md5sum.
# Mirrors the ENV_HASH logic in setup.sh.
env_hash() {
  echo "$1" | grep -v '^# Generated' | md5sum | cut -d' ' -f1
}

# -----------------------------------------------------------------------------
# Tests — IP validation
# NOTE: regex checks format only, not octet range (e.g. 999.x.x.x passes).
# Range enforcement is left to the connectivity test (ping/tcp) which fails
# gracefully with a warning. This matches setup.sh behavior.
# -----------------------------------------------------------------------------
echo
echo "IP Address Validation"
echo "─────────────────────"
assert_true "valid: 192.168.1.40"        "$(is_valid_ip "192.168.1.40"    && echo true || echo false)"
assert_true "valid: 10.0.0.1"            "$(is_valid_ip "10.0.0.1"        && echo true || echo false)"
assert_true "valid: 255.255.255.255"     "$(is_valid_ip "255.255.255.255"  && echo true || echo false)"
assert_true "valid: 0.0.0.0"             "$(is_valid_ip "0.0.0.0"          && echo true || echo false)"
assert_true "invalid: empty string"      "$(is_valid_ip ""                 && echo false || echo true)"
assert_true "invalid: abc"               "$(is_valid_ip "abc"              && echo false || echo true)"
assert_true "invalid: 192.168.1"         "$(is_valid_ip "192.168.1"        && echo false || echo true)"
assert_true "invalid: 192.168.1.40.1"   "$(is_valid_ip "192.168.1.40.1"   && echo false || echo true)"
assert_true "invalid: 192.168.1.40/24"  "$(is_valid_ip "192.168.1.40/24"  && echo false || echo true)"
assert_true "invalid: 192.168.1.abc"    "$(is_valid_ip "192.168.1.abc"    && echo false || echo true)"

# -----------------------------------------------------------------------------
# Tests — MAC address validation
# -----------------------------------------------------------------------------
echo
echo "MAC Address Validation"
echo "──────────────────────"
assert_true "valid: C7:03:DC:E9:D0:66"    "$(is_valid_mac "C7:03:DC:E9:D0:66"  && echo true || echo false)"
assert_true "valid: AA:BB:CC:DD:EE:FF"    "$(is_valid_mac "AA:BB:CC:DD:EE:FF"  && echo true || echo false)"
assert_true "valid: aa:bb:cc:dd:ee:ff"    "$(is_valid_mac "aa:bb:cc:dd:ee:ff"  && echo true || echo false)"
assert_true "valid: 00:00:00:00:00:00"    "$(is_valid_mac "00:00:00:00:00:00"  && echo true || echo false)"
assert_true "invalid: empty string"       "$(is_valid_mac ""                   && echo false || echo true)"
assert_true "invalid: GG:HH:II:JJ:KK:LL" "$(is_valid_mac "GG:HH:II:JJ:KK:LL" && echo false || echo true)"
assert_true "invalid: C7:03:DC:E9:D0"    "$(is_valid_mac "C7:03:DC:E9:D0"     && echo false || echo true)"
assert_true "invalid: C703DCE9D066"       "$(is_valid_mac "C703DCE9D066"       && echo false || echo true)"
assert_true "invalid: C7-03-DC-E9-D0-66" "$(is_valid_mac "C7-03-DC-E9-D0-66"  && echo false || echo true)"
assert_true "invalid: C7:03:DC:E9:D0:666" "$(is_valid_mac "C7:03:DC:E9:D0:666" && echo false || echo true)"

# -----------------------------------------------------------------------------
# Tests — Port validation
# -----------------------------------------------------------------------------
echo
echo "Port Validation"
echo "───────────────"
assert_true "valid: 4403"                "$(is_valid_port "4403"  && echo true || echo false)"
assert_true "valid: 1 (minimum)"         "$(is_valid_port "1"     && echo true || echo false)"
assert_true "valid: 65535 (maximum)"     "$(is_valid_port "65535" && echo true || echo false)"
assert_true "valid: 8080"                "$(is_valid_port "8080"  && echo true || echo false)"
assert_true "invalid: 0"                 "$(is_valid_port "0"     && echo false || echo true)"
assert_true "invalid: 65536"             "$(is_valid_port "65536" && echo false || echo true)"
assert_true "invalid: abc"               "$(is_valid_port "abc"   && echo false || echo true)"
assert_true "invalid: empty string"      "$(is_valid_port ""      && echo false || echo true)"
assert_true "invalid: 80.5 (decimal)"    "$(is_valid_port "80.5"  && echo false || echo true)"
assert_true "invalid: -1 (negative)"     "$(is_valid_port "-1"    && echo false || echo true)"

# -----------------------------------------------------------------------------
# Tests — Upgrade time validation
# -----------------------------------------------------------------------------
echo
echo "Upgrade Time Validation (HH:MM)"
echo "────────────────────────────────"
assert_true "valid: 03:00"               "$(is_valid_time "03:00"    && echo true || echo false)"
assert_true "valid: 00:00"               "$(is_valid_time "00:00"    && echo true || echo false)"
assert_true "valid: 23:59"               "$(is_valid_time "23:59"    && echo true || echo false)"
assert_true "valid: 12:30"               "$(is_valid_time "12:30"    && echo true || echo false)"
assert_true "invalid: 24:00"             "$(is_valid_time "24:00"    && echo false || echo true)"
assert_true "invalid: 3:00 (no pad)"     "$(is_valid_time "3:00"     && echo false || echo true)"
assert_true "invalid: 03:60"             "$(is_valid_time "03:60"    && echo false || echo true)"
assert_true "invalid: abc"               "$(is_valid_time "abc"      && echo false || echo true)"
assert_true "invalid: empty string"      "$(is_valid_time ""         && echo false || echo true)"
assert_true "invalid: 03:00:00"          "$(is_valid_time "03:00:00" && echo false || echo true)"

# -----------------------------------------------------------------------------
# Tests — Node renumber logic
# -----------------------------------------------------------------------------
echo
echo "Node Renumber Logic"
echo "───────────────────"

# Remove middle node from 3-node list (tcp ble serial → tcp serial)
result=$(renumber_nodes 2 tcp ble serial)
assert_eq "remove middle: slot 1 is tcp"      "tcp"    "$(echo "$result" | sed -n '1p')"
assert_eq "remove middle: slot 2 is serial"   "serial" "$(echo "$result" | sed -n '2p')"
assert_eq "remove middle: 2 nodes remain"     "2"      "$(echo "$result" | wc -l | tr -d ' ')"

# Remove first node from 3-node list (tcp ble serial → ble serial)
result=$(renumber_nodes 1 tcp ble serial)
assert_eq "remove first: slot 1 is ble"       "ble"    "$(echo "$result" | sed -n '1p')"
assert_eq "remove first: slot 2 is serial"    "serial" "$(echo "$result" | sed -n '2p')"
assert_eq "remove first: 2 nodes remain"      "2"      "$(echo "$result" | wc -l | tr -d ' ')"

# Remove last node from 3-node list (tcp ble serial → tcp ble)
result=$(renumber_nodes 3 tcp ble serial)
assert_eq "remove last: slot 1 is tcp"        "tcp"    "$(echo "$result" | sed -n '1p')"
assert_eq "remove last: slot 2 is ble"        "ble"    "$(echo "$result" | sed -n '2p')"
assert_eq "remove last: 2 nodes remain"       "2"      "$(echo "$result" | wc -l | tr -d ' ')"

# Remove only node
result=$(renumber_nodes 1 tcp || true)
node_count=$(echo "$result" | grep -c '[a-z]' || true)
assert_eq "remove only node: 0 nodes remain"  "0"      "$node_count"

# Mixed types: remove second of two BLE nodes (tcp ble ble → tcp ble)
result=$(renumber_nodes 3 tcp ble ble)
assert_eq "remove 2nd BLE: slot 1 is tcp"     "tcp"    "$(echo "$result" | sed -n '1p')"
assert_eq "remove 2nd BLE: slot 2 is ble"     "ble"    "$(echo "$result" | sed -n '2p')"
assert_eq "remove 2nd BLE: 2 nodes remain"    "2"      "$(echo "$result" | wc -l | tr -d ' ')"

# -----------------------------------------------------------------------------
# Tests — .env hash comparison
# -----------------------------------------------------------------------------
echo
echo ".env Hash Comparison"
echo "─────────────────────"

ENV_A="# Generated by setup.sh on Mon May 24 2026
PI_IP=192.168.1.40
HOST_PORT=8080
SESSION_SECRET=abc123"

ENV_B="# Generated by setup.sh on Tue May 25 2026
PI_IP=192.168.1.40
HOST_PORT=8080
SESSION_SECRET=abc123"

ENV_C="# Generated by setup.sh on Mon May 24 2026
PI_IP=192.168.1.41
HOST_PORT=8080
SESSION_SECRET=abc123"

ENV_D="# Generated by setup.sh on Mon May 24 2026
PI_IP=192.168.1.40
HOST_PORT=9090
SESSION_SECRET=abc123"

hash_a=$(env_hash "$ENV_A")
hash_b=$(env_hash "$ENV_B")
hash_c=$(env_hash "$ENV_C")
hash_d=$(env_hash "$ENV_D")

assert_eq "same content, different timestamp: hashes equal" "$hash_a" "$hash_b"
if [[ "$hash_a" != "$hash_c" ]]; then
  echo "  [PASS] different IP: hashes differ"
  PASS=$(( PASS + 1 ))
else
  echo "  [FAIL] different IP: hashes should differ"
  FAIL=$(( FAIL + 1 ))
fi
if [[ "$hash_a" != "$hash_d" ]]; then
  echo "  [PASS] different port: hashes differ"
  PASS=$(( PASS + 1 ))
else
  echo "  [FAIL] different port: hashes should differ"
  FAIL=$(( FAIL + 1 ))
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo
echo "============================================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "============================================================"
echo

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
