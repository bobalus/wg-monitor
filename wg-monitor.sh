#!/usr/bin/env bash
set -euo pipefail

# Discover all interfaces when invoked without an interface argument.
if [ "$#" -eq 0 ]; then
    interfaces=$(wg show interfaces) || {
        logger -p daemon.err -t wireguard-monitor "Could not list WireGuard interfaces."
        exit 1
    }
    if [ -z "$interfaces" ]; then
        logger -p daemon.warning -t wireguard-monitor "No WireGuard interfaces found."
        exit 0
    fi
    status=0
    for interface in $interfaces; do
        "$0" "$interface" || status=1
    done
    exit "$status"
fi

# --- CONFIGURATION ---
INTERFACE="$1"
STATE_FILE="/run/wg_monitor_state_${INTERFACE}.txt"
LOG_TAG="wireguard-monitor"
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}" # Optional Discord webhook URL
INACTIVE_THRESHOLD=300 # Seconds without a handshake before treating a peer as inactive
# ---------------------

declare -A PEER_NAMES=(
    # ["WIREGUARD_PUBLIC_KEY"]="Device name"
)

peer_name() {
   local pubkey="$1"
   printf '%s' "${PEER_NAMES[$pubkey]:-Unknown peer}"
}

NOW=$(date +%s)
HOSTNAME=$(hostname)
TMP_CURRENT=$(mktemp)
TMP_PREV=$(mktemp)

cleanup() {
    rm -f "$TMP_CURRENT" "$TMP_PREV"
}
trap cleanup EXIT

# 1. Parse current active peers from WireGuard dump
# Fields in dump: public_key, preshared_key, endpoint, allowed_ips, latest_handshake, rx, tx, persistent_keepalive
wg show "$INTERFACE" dump | tail -n +2 | while read -r pubkey psk endpoint allowed_ips handshake rx tx keepalive; do
    if [ "$handshake" -ne 0 ]; then
        AGE=$((NOW - handshake))
        if [ "$AGE" -le "$INACTIVE_THRESHOLD" ]; then
            # Peer is currently connected
            echo "${pubkey}|${allowed_ips}|${endpoint}" >> "$TMP_CURRENT"
        fi
    fi
done

# Sort current state
sort -u "$TMP_CURRENT" -o "$TMP_CURRENT"

# 2. Handle initial run
if [ ! -f "$STATE_FILE" ]; then
    cp "$TMP_CURRENT" "$STATE_FILE"
    logger -t "$LOG_TAG" "Initialized WireGuard state tracking for interface $INTERFACE."
    exit 0
fi

# Sort previous state
sort -u "$STATE_FILE" -o "$TMP_PREV"

# 3. Detect changes by public key, not endpoint or allowed IPs. Keep the
# complete current/previous records for the alert details. This also accepts
# state files created by older versions of the script.
CONNECTED_PEERS=$(awk -F'|' 'FILENAME == ARGV[1] { previous[$1] = 1; next } !($1 in previous)' "$TMP_PREV" "$TMP_CURRENT")
DISCONNECTED_PEERS=$(awk -F'|' 'FILENAME == ARGV[1] { current[$1] = 1; next } !($1 in current)' "$TMP_CURRENT" "$TMP_PREV")

send_discord() {
    local message="$1"
    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
        local payload
        payload=$(jq -n --arg content "$message" '{"content": $content}')
        curl -s -H "Content-Type: application/json" -X POST -d "$payload" "$DISCORD_WEBHOOK_URL" > /dev/null 2>&1 || true
    fi
}

# 4. Process newly connected peers
if [ -n "$CONNECTED_PEERS" ]; then
    while IFS="|" read -r pubkey ips endpoint; do
		name=$(peer_name "$pubkey")
        MSG="[CONNECTED] Host: $HOSTNAME | Interface: $INTERFACE | Name: $name | Peer: $pubkey | IP: $ips | Endpoint: $endpoint"
		logger -p daemon.info -t "$LOG_TAG" "$MSG"
        printf -v discord_message "🟢 **WireGuard Connected**\n\`\`\`\nHost: %s\nInterface: %s\nName: %s\nPeer: %s\nIP: %s\nEndpoint: %s\n\`\`\`" "$HOSTNAME" "$INTERFACE" "$name" "$pubkey" "$ips" "$endpoint"
		send_discord "$discord_message"
    done <<< "$CONNECTED_PEERS"
fi

# 5. Process disconnected peers
if [ -n "$DISCONNECTED_PEERS" ]; then
    while IFS="|" read -r pubkey ips endpoint; do
		name=$(peer_name "$pubkey")
        MSG="[DISCONNECTED] Host: $HOSTNAME | Interface: $INTERFACE | Name: $name | Peer: $pubkey | IP: $ips"
		logger -p daemon.info -t "$LOG_TAG" "$MSG"
        printf -v discord_message "🔴 **WireGuard Disconnected**\n\`\`\`\nHost: %s\nInterface: %s\nName: %s\nPeer: %s\nIP: %s\n\`\`\`" "$HOSTNAME" "$INTERFACE" "$name" "$pubkey" "$ips"
		send_discord "$discord_message"
    done <<< "$DISCONNECTED_PEERS"
fi

# 6. Save current state for next execution
cp "$TMP_CURRENT" "$STATE_FILE"
