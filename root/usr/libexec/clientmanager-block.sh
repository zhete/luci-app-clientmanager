#!/bin/sh
# Client Manager - Device Blocking Script
# Usage: clientmanager-block.sh <mac_address> [action]
# Actions: block, unblock, check

MAC="$1"
ACTION="${2:-block}"

# Validate MAC address
if [ -z "$MAC" ] || ! echo "$MAC" | grep -qE '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'; then
    echo "Error: Invalid MAC address format"
    exit 1
fi

# Normalize MAC to uppercase
MAC=$(echo "$MAC" | tr '[:lower:]' '[:upper:]')

# Get IP address for this MAC
get_ip_by_mac() {
    local mac="$1"
    cat /proc/net/arp | grep -i "$mac" | awk '{print $1}' | head -1
}

# Block device using iptables
block_device() {
    local mac="$1"
    local ip=$(get_ip_by_mac "$mac")

    # Check if already blocked
    if iptables -C FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null; then
        echo "Device $mac is already blocked"
        return 0
    fi

    # Add iptables rules
    iptables -I FORWARD -m mac --mac-source "$mac" -j DROP
    iptables -I INPUT -m mac --mac-source "$mac" -j DROP

    # Also block by IP if available
    if [ -n "$ip" ]; then
        iptables -I FORWARD -s "$ip" -j DROP
        iptables -I FORWARD -d "$ip" -j DROP
    fi

    # Add to UCI config
    uci add_list clientmanager.global.blocked="$mac"
    uci commit clientmanager

    echo "Device $mac blocked successfully"
    return 0
}

# Unblock device
unblock_device() {
    local mac="$1"
    local ip=$(get_ip_by_mac "$mac")

    # Remove iptables rules
    iptables -D FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null
    iptables -D INPUT -m mac --mac-source "$mac" -j DROP 2>/dev/null

    if [ -n "$ip" ]; then
        iptables -D FORWARD -s "$ip" -j DROP 2>/dev/null
        iptables -D FORWARD -d "$ip" -j DROP 2>/dev/null
    fi

    # Remove from UCI config
    uci del_list clientmanager.global.blocked="$mac"
    uci commit clientmanager

    echo "Device $mac unblocked successfully"
    return 0
}

# Check if device is blocked
check_device() {
    local mac="$1"

    if iptables -C FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null; then
        echo "blocked"
    else
        echo "unblocked"
    fi
    return 0
}

# Main case
case "$ACTION" in
    block)
        block_device "$MAC"
        ;;
    unblock)
        unblock_device "$MAC"
        ;;
    check)
        check_device "$MAC"
        ;;
    *)
        echo "Usage: $0 <mac_address> [block|unblock|check]"
        exit 1
        ;;
esac

exit 0
