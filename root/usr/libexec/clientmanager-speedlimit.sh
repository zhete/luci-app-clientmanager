#!/bin/sh
# Client Manager - Speed Limit Script
# Usage: clientmanager-speedlimit.sh <mac_address> <download_kbps> <upload_kbps>

MAC="$1"
DOWNLOAD="${2:-0}"
UPLOAD="${3:-0}"

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

# Get interface for this MAC
get_iface_by_mac() {
    local mac="$1"
    cat /proc/net/arp | grep -i "$mac" | awk '{print $6}' | head -1
}

# Remove existing speed limit rules
remove_limit() {
    local mac="$1"
    local ip=$(get_ip_by_mac "$mac")

    # Remove tc filters
    local iface=$(get_iface_by_mac "$mac")
    [ -z "$iface" ] && iface="br-lan"

    # Remove iptables mark rules
    iptables -t mangle -D PREROUTING -m mac --mac-source "$mac" -j MARK --set-mark 0x2 2>/dev/null
    iptables -t mangle -D POSTROUTING -d "$ip" -j MARK --set-mark 0x3 2>/dev/null

    echo "Speed limit removed for $mac"
}

# Apply speed limit using tc (traffic control)
apply_limit() {
    local mac="$1"
    local download="$2"
    local upload="$3"
    local ip=$(get_ip_by_mac "$mac")
    local iface=$(get_iface_by_mac "$mac")

    [ -z "$iface" ] && iface="br-lan"

    # Remove existing limits first
    remove_limit "$mac"

    # If both limits are 0, just remove the limit
    if [ "$download" = "0" ] && [ "$upload" = "0" ]; then
        # Remove from UCI config
        uci delete clientmanager.limit 2>/dev/null
        uci commit clientmanager
        return 0
    fi

    # Setup tc qdisc if not exists
    tc qdisc del dev "$iface" root 2>/dev/null
    tc qdisc add dev "$iface" root handle 1: htb default 12

    # Create class for download limit
    if [ "$download" != "0" ]; then
        local download_rate="${download}kbit"
        tc class add dev "$iface" parent 1: classid 1:2 htb rate "$download_rate" ceil "$download_rate"
        tc filter add dev "$iface" protocol ip parent 1:0 prio 1 handle 3 fw classid 1:2
    fi

    # Create class for upload limit
    if [ "$upload" != "0" ]; then
        local upload_rate="${upload}kbit"
        tc class add dev "$iface" parent 1: classid 1:3 htb rate "$upload_rate" ceil "$upload_rate"
        tc filter add dev "$iface" protocol ip parent 1:0 prio 1 handle 2 fw classid 1:3
    fi

    # Mark packets with iptables
    iptables -t mangle -I PREROUTING -m mac --mac-source "$mac" -j MARK --set-mark 0x2
    if [ -n "$ip" ]; then
        iptables -t mangle -I POSTROUTING -d "$ip" -j MARK --set-mark 0x3
    fi

    # Save to UCI config
    local section=$(uci show clientmanager | grep "limit.*mac=.$mac." | cut -d'.' -f2 | head -1)
    if [ -z "$section" ]; then
        section=$(uci add clientmanager limit)
    fi

    uci set clientmanager.$section.mac="$mac"
    uci set clientmanager.$section.download="$download"
    uci set clientmanager.$section.upload="$upload"
    uci commit clientmanager

    echo "Speed limit applied to $mac: Download ${download}kbps, Upload ${upload}kbps"
    return 0
}

# Show current limits
show_limits() {
    echo "Current Speed Limits:"
    echo "===================="
    printf "%-17s %-12s %-12s\n" "MAC" "Download" "Upload"
    echo "-------------------------------------------"

    uci show clientmanager 2>/dev/null | grep "limit\[" | while read -r line; do
        local section=$(echo "$line" | cut -d'.' -f2)
        local mac=$(uci get clientmanager.$section.mac 2>/dev/null)
        local download=$(uci get clientmanager.$section.download 2>/dev/null)
        local upload=$(uci get clientmanager.$section.upload 2>/dev/null)

        if [ -n "$mac" ]; then
            printf "%-17s %-12s %-12s\n" "$mac" "${download}kbps" "${upload}kbps"
        fi
    done
}

# Main case
if [ $# -eq 0 ]; then
    show_limits
    exit 0
fi

if [ $# -lt 3 ]; then
    echo "Usage: $0 <mac_address> <download_kbps> <upload_kbps>"
    echo "       $0 (show current limits)"
    echo ""
    echo "Examples:"
    echo "  $0 AA:BB:CC:DD:EE:FF 1000 500    # Limit to 1000kbps down, 500kbps up"
    echo "  $0 AA:BB:CC:DD:EE:FF 0 0          # Remove limits"
    exit 1
fi

apply_limit "$MAC" "$DOWNLOAD" "$UPLOAD"

exit 0
