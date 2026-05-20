#!/bin/sh
# Client Manager - Traffic Monitoring Script
# Usage: clientmanager-traffic.sh [action] [parameters]
# Actions: collect, stats, reset

DATA_DIR="/tmp/clientmanager"
TRAFFIC_FILE="$DATA_DIR/traffic.db"
ACTION="${1:-collect}"

# Create data directory if not exists
mkdir -p "$DATA_DIR"

# Initialize traffic database
init_db() {
    if [ ! -f "$TRAFFIC_FILE" ]; then
        echo "# Client Manager Traffic Database" > "$TRAFFIC_FILE"
        echo "# Format: MAC|IP|HOSTNAME|DOWNLOAD|UPLOAD|LAST_SEEN" >> "$TRAFFIC_FILE"
    fi
}

# Get current traffic from iptables (if using accounting rules)
get_traffic_from_iptables() {
    local mac="$1"
    iptables -L FORWARD -v -n -x 2>/dev/null | grep -i "$mac" | awk '{print $2}'
}

# Collect traffic data for all devices
collect_traffic() {
    init_db

    local temp_file=$(mktemp)
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')

    # Read ARP table to get all known devices
    while read -r line; do
        local ip=$(echo "$line" | awk '{print $1}')
        local mac=$(echo "$line" | awk '{print $4}' | tr '[:lower:]' '[:upper:]')
        local iface=$(echo "$line" | awk '{print $6}')

        # Skip invalid entries
        [ -z "$mac" ] || [ "$mac" = "00:00:00:00:00:00" ] && continue

        # Get hostname from DHCP leases
        local hostname=$(grep -i "$mac" /tmp/dhcp.leases 2>/dev/null | awk '{print $4}')
        [ -z "$hostname" ] || [ "$hostname" = "*" ] && hostname="Unknown"

        # Get traffic stats (placeholder - would need iptables rules for real accounting)
        local download=0
        local upload=0

        # Check if device exists in database
        local existing=$(grep -i "^$mac|" "$TRAFFIC_FILE" 2>/dev/null)
        if [ -n "$existing" ]; then
            # Update existing entry
            local old_download=$(echo "$existing" | cut -d'|' -f4)
            local old_upload=$(echo "$existing" | cut -d'|' -f5)
            download=$((old_download + 0))
            upload=$((old_upload + 0))
        fi

        # Write to temp file
        echo "$mac|$ip|$hostname|$download|$upload|$current_time" >> "$temp_file"
    done < /proc/net/arp

    # Update database
    echo "# Client Manager Traffic Database" > "$TRAFFIC_FILE"
    echo "# Format: MAC|IP|HOSTNAME|DOWNLOAD|UPLOAD|LAST_SEEN" >> "$TRAFFIC_FILE"
    cat "$temp_file" >> "$TRAFFIC_FILE"

    rm -f "$temp_file"
}

# Get traffic statistics
get_stats() {
    init_db

    local format="${2:-text}"

    if [ "$format" = "json" ]; then
        echo "{"
        echo "  \"devices\": ["

        local first=1
        while IFS='|' read -r mac ip hostname download upload last_seen; do
            [ -z "$mac" ] && continue
            [ "${mac:0:1}" = "#" ] && continue

            if [ $first -eq 0 ]; then
                echo ","
            fi
            first=0

            echo -n "    {"
            echo -n "\"mac\":\"$mac\","
            echo -n "\"ip\":\"$ip\","
            echo -n "\"hostname\":\"$hostname\","
            echo -n "\"download\":$download,"
            echo -n "\"upload\":$upload,"
            echo -n "\"last_seen\":\"$last_seen\""
            echo -n "}"
        done < "$TRAFFIC_FILE"

        echo ""
        echo "  ]"
        echo "}"
    else
        # Text format
        printf "%-17s %-15s %-20s %12s %12s %s\n" "MAC" "IP" "Hostname" "Download" "Upload" "Last Seen"
        echo "-----------------------------------------------------------------------------------------------"

        while IFS='|' read -r mac ip hostname download upload last_seen; do
            [ -z "$mac" ] && continue
            [ "${mac:0:1}" = "#" ] && continue

            printf "%-17s %-15s %-20s %12s %12s %s\n" "$mac" "$ip" "$hostname" "$download" "$upload" "$last_seen"
        done < "$TRAFFIC_FILE"
    fi
}

# Reset traffic statistics
reset_stats() {
    rm -f "$TRAFFIC_FILE"
    init_db
    echo "Traffic statistics reset"
}

# Get traffic for specific device
get_device_traffic() {
    local mac="$1"
    mac=$(echo "$mac" | tr '[:lower:]' '[:upper:]')

    grep -i "^$mac|" "$TRAFFIC_FILE" 2>/dev/null
}

# Main case
case "$ACTION" in
    collect)
        collect_traffic
        ;;
    stats)
        get_stats "$@"
        ;;
    reset)
        reset_stats
        ;;
    device)
        get_device_traffic "$2"
        ;;
    *)
        echo "Usage: $0 [collect|stats|reset|device <mac>]"
        echo ""
        echo "Actions:"
        echo "  collect           - Collect current traffic data"
        echo "  stats [json]      - Show traffic statistics"
        echo "  reset             - Reset all statistics"
        echo "  device <mac>      - Show traffic for specific device"
        exit 1
        ;;
esac

exit 0
