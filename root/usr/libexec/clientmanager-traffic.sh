#!/bin/sh
# Client Manager - Traffic Monitoring Script
# Usage: clientmanager-traffic.sh [action] [parameters]
# Actions: collect, stats, reset, device, cleanup, realtime, track_online

DATA_DIR="/etc/clientmanager"
TRAFFIC_FILE="$DATA_DIR/traffic.db"
ONLINE_FILE="$DATA_DIR/online.db"
SPEED_FILE="$DATA_DIR/speed.db"
ACTION="${1:-collect}"

mkdir -p "$DATA_DIR"

init_db() {
    if [ ! -f "$TRAFFIC_FILE" ]; then
        echo "# Client Manager Traffic Database" > "$TRAFFIC_FILE"
        echo "# Format: MAC|IP|HOSTNAME|DOWNLOAD|UPLOAD|LAST_SEEN|FIRST_SEEN" >> "$TRAFFIC_FILE"
    fi
}

ensure_accounting_rules() {
    local chain_exists
    chain_exists=$(iptables -L CLIENTMGR_ACCT -n 2>/dev/null | head -1)
    if [ -z "$chain_exists" ]; then
        iptables -N CLIENTMGR_ACCT 2>/dev/null
        iptables -I FORWARD -j CLIENTMGR_ACCT 2>/dev/null
    fi
}

add_accounting_rule() {
    local mac="$1"
    local ip="$2"

    if [ -z "$mac" ]; then
        return 1
    fi

    if ! iptables -C CLIENTMGR_ACCT -m mac --mac-source "$mac" -j RETURN 2>/dev/null; then
        iptables -A CLIENTMGR_ACCT -m mac --mac-source "$mac" -j RETURN 2>/dev/null
    fi

    if [ -n "$ip" ]; then
        if ! iptables -C CLIENTMGR_ACCT -s "$ip" -j RETURN 2>/dev/null; then
            iptables -A CLIENTMGR_ACCT -s "$ip" -j RETURN 2>/dev/null
        fi
        if ! iptables -C CLIENTMGR_ACCT -d "$ip" -j RETURN 2>/dev/null; then
            iptables -A CLIENTMGR_ACCT -d "$ip" -j RETURN 2>/dev/null
        fi
    fi

    return 0
}

get_traffic_for_device() {
    local mac="$1"
    local ip="$2"
    local download=0
    local upload=0

    if [ -n "$ip" ]; then
        download=$(iptables -L CLIENTMGR_ACCT -v -n -x 2>/dev/null | grep -i "$mac" | head -1 | awk '{print $2}')
        [ -z "$download" ] && download=0

        upload=$(iptables -L CLIENTMGR_ACCT -v -n -x 2>/dev/null | grep -i "$mac" | head -1 | awk '{print $2}')
        [ -z "$upload" ] && upload=0

        if [ "$download" = "0" ] && [ "$upload" = "0" ]; then
            local dl_src=$(iptables -L CLIENTMGR_ACCT -v -n -x -s "$ip" 2>/dev/null | head -1 | awk '{print $2}')
            local ul_dst=$(iptables -L CLIENTMGR_ACCT -v -n -x -d "$ip" 2>/dev/null | head -1 | awk '{print $2}')
            [ -n "$dl_src" ] && [ "$dl_src" != "0" ] && upload=$dl_src
            [ -n "$ul_dst" ] && [ "$ul_dst" != "0" ] && download=$ul_dst
        fi
    fi

    echo "$download $upload"
}

collect_traffic() {
    init_db
    ensure_accounting_rules

    local temp_file=$(mktemp)
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')

    while read -r line; do
        local ip=$(echo "$line" | awk '{print $1}')
        local mac=$(echo "$line" | awk '{print $4}' | tr '[:lower:]' '[:upper:]')
        local flags=$(echo "$line" | awk '{print $3}')

        [ -z "$mac" ] || [ "$mac" = "00:00:00:00:00:00" ] && continue

        local hostname=$(grep -i "$mac" /tmp/dhcp.leases 2>/dev/null | awk '{print $4}')
        [ -z "$hostname" ] || [ "$hostname" = "*" ] && hostname="Unknown"

        local traffic=$(get_traffic_for_device "$mac" "$ip")
        local new_download=$(echo "$traffic" | awk '{print $1}')
        local new_upload=$(echo "$traffic" | awk '{print $2}')

        local existing=$(grep -i "^${mac}|" "$TRAFFIC_FILE" 2>/dev/null | tail -1)
        local total_download=$new_download
        local total_upload=$new_upload
        local first_seen="$current_time"

        if [ -n "$existing" ]; then
            local old_download=$(echo "$existing" | cut -d'|' -f4)
            local old_upload=$(echo "$existing" | cut -d'|' -f5)
            local old_first_seen=$(echo "$existing" | cut -d'|' -f7)
            [ -n "$old_first_seen" ] && first_seen="$old_first_seen"

            if [ "$new_download" != "0" ] && [ "$old_download" != "0" ]; then
                if [ "$new_download" -ge "$old_download" ] 2>/dev/null; then
                    total_download=$new_download
                    total_upload=$new_upload
                else
                    total_download=$old_download
                    total_upload=$old_upload
                fi
            elif [ "$new_download" != "0" ]; then
                total_download=$((old_download + new_download))
                total_upload=$((old_upload + new_upload))
            else
                total_download=$old_download
                total_upload=$old_upload
            fi
        fi

        add_accounting_rule "$mac" "$ip"

        echo "$mac|$ip|$hostname|$total_download|$total_upload|$current_time|$first_seen" >> "$temp_file"
    done < /proc/net/arp

    echo "# Client Manager Traffic Database" > "$TRAFFIC_FILE"
    echo "# Format: MAC|IP|HOSTNAME|DOWNLOAD|UPLOAD|LAST_SEEN|FIRST_SEEN" >> "$TRAFFIC_FILE"
    cat "$temp_file" >> "$TRAFFIC_FILE"
    rm -f "$temp_file"
}

track_online() {
    local current_ts=$(date '+%s')
    local current_arp=$(mktemp)
    local prev_online=$(mktemp)

    grep -v '^#' "$ONLINE_FILE" 2>/dev/null | while IFS='|' read -r mac start_ts end_ts; do
        [ -z "$mac" ] && continue
        echo "$mac|$start_ts|$end_ts" >> "$prev_online"
    done

    cat /proc/net/arp 2>/dev/null | while read -r line; do
        local mac=$(echo "$line" | awk '{print $4}')
        local flags=$(echo "$line" | awk '{print $3}')

        [ -z "$mac" ] || [ "$mac" = "00:00:00:00:00:00" ] && continue
        ! echo "$mac" | grep -qE '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$' && continue

        local is_online="0"
        [ "$flags" = "0x2" ] || [ "$flags" = "0x6" ] && is_online="1"

        local mac_upper=$(echo "$mac" | tr '[:lower:]' '[:upper:]')

        if [ "$is_online" = "1" ]; then
            local existing_start=$(grep "^${mac_upper}|" "$prev_online" 2>/dev/null | tail -1 | cut -d'|' -f2)
            if [ -n "$existing_start" ] && [ "$existing_start" != "" ]; then
                echo "${mac_upper}|${existing_start}|${current_ts}"
            else
                echo "${mac_upper}|${current_ts}|${current_ts}"
            fi
        fi
    done > "$current_arp"

    while IFS='|' read -r mac start_ts end_ts; do
        [ -z "$mac" ] && continue
        if ! grep -q "^${mac}|" "$current_arp" 2>/dev/null; then
            echo "${mac}|${start_ts}|${end_ts}"
        fi
    done < "$prev_online" >> "$current_arp"

    cat "$current_arp" > "$ONLINE_FILE"
    rm -f "$current_arp" "$prev_online"
}

get_realtime_speed() {
    local prev_file="$DATA_DIR/.speed_prev"
    local current_ts=$(date '+%s')

    echo "{"
    echo "  \"devices\": ["

    local first=1
    while read -r line; do
        [ -z "$line" ] && continue
        [ "${line:0:1}" = "#" ] && continue

        local mac=$(echo "$line" | cut -d'|' -f1)
        local ip=$(echo "$line" | cut -d'|' -f2)
        local hostname=$(echo "$line" | cut -d'|' -f3)
        local total_dl=$(echo "$line" | cut -d'|' -f4)
        local total_ul=$(echo "$line" | cut -d'|' -f5)

        local dl_speed=0
        local ul_speed=0

        if [ -f "$prev_file" ]; then
            local prev_line=$(grep "^${mac}|" "$prev_file" 2>/dev/null)
            if [ -n "$prev_line" ]; then
                local prev_dl=$(echo "$prev_line" | cut -d'|' -f2)
                local prev_ul=$(echo "$prev_line" | cut -d'|' -f3)
                local prev_ts=$(echo "$prev_line" | cut -d'|' -f4)
                local time_diff=$((current_ts - prev_ts))

                if [ "$time_diff" -gt 0 ] 2>/dev/null; then
                    dl_speed=$(( (total_dl - prev_dl) / time_diff ))
                    ul_speed=$(( (total_ul - prev_ul) / time_diff ))
                    [ "$dl_speed" -lt 0 ] && dl_speed=0
                    [ "$ul_speed" -lt 0 ] && ul_speed=0
                fi
            fi
        fi

        if [ $first -eq 0 ]; then
            echo ","
        fi
        first=0

        hostname=$(echo "$hostname" | sed 's/"/\\"/g')

        echo -n "    {"
        echo -n "\"mac\":\"$mac\","
        echo -n "\"ip\":\"$ip\","
        echo -n "\"hostname\":\"$hostname\","
        echo -n "\"download_speed\":$dl_speed,"
        echo -n "\"upload_speed\":$ul_speed"
        echo -n "}"

    done < "$TRAFFIC_FILE"

    echo ""
    echo "  ]"
    echo "}"

    local speed_temp=$(mktemp)
    while read -r line; do
        [ -z "$line" ] || [ "${line:0:1}" = "#" ] && continue
        local mac=$(echo "$line" | cut -d'|' -f1)
        local dl=$(echo "$line" | cut -d'|' -f4)
        local ul=$(echo "$line" | cut -d'|' -f5)
        echo "$mac|$dl|$ul|$current_ts" >> "$speed_temp"
    done < "$TRAFFIC_FILE"
    cat "$speed_temp" > "$prev_file"
    rm -f "$speed_temp"
}

get_stats() {
    init_db

    local format="${2:-text}"

    if [ "$format" = "json" ]; then
        echo "{"
        echo "  \"devices\": ["

        local first=1
        while IFS='|' read -r mac ip hostname download upload last_seen first_seen; do
            [ -z "$mac" ] && continue
            [ "${mac:0:1}" = "#" ] && continue

            if [ $first -eq 0 ]; then
                echo ","
            fi
            first=0

            hostname=$(echo "$hostname" | sed 's/"/\\"/g')
            last_seen=$(echo "$last_seen" | sed 's/"/\\"/g')

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
        printf "%-17s %-15s %-20s %12s %12s %s\n" "MAC" "IP" "Hostname" "Download" "Upload" "Last Seen"
        echo "-----------------------------------------------------------------------------------------------"

        while IFS='|' read -r mac ip hostname download upload last_seen first_seen; do
            [ -z "$mac" ] && continue
            [ "${mac:0:1}" = "#" ] && continue

            printf "%-17s %-15s %-20s %12s %12s %s\n" "$mac" "$ip" "$hostname" "$download" "$upload" "$last_seen"
        done < "$TRAFFIC_FILE"
    fi
}

reset_stats() {
    rm -f "$TRAFFIC_FILE"
    rm -f "$SPEED_FILE"
    rm -f "$DATA_DIR/.speed_prev"
    init_db
    iptables -F CLIENTMGR_ACCT 2>/dev/null
    echo "Traffic statistics reset"
}

get_device_traffic() {
    local mac="$1"
    mac=$(echo "$mac" | tr '[:lower:]' '[:upper:]')

    grep -i "^$mac|" "$TRAFFIC_FILE" 2>/dev/null
}

cleanup_old_data() {
    init_db

    local retention_days="${2:-30}"
    local cutoff_time=$(date -d "-${retention_days} days" '+%s' 2>/dev/null)

    if [ -z "$cutoff_time" ]; then
        cutoff_time=$(date -v-${retention_days}d '+%s' 2>/dev/null)
    fi

    if [ -z "$cutoff_time" ]; then
        echo "Warning: Cannot calculate cutoff date, skipping cleanup"
        return 1
    fi

    local temp_file=$(mktemp)
    echo "# Client Manager Traffic Database" > "$temp_file"
    echo "# Format: MAC|IP|HOSTNAME|DOWNLOAD|UPLOAD|LAST_SEEN|FIRST_SEEN" >> "$temp_file"

    while IFS='|' read -r mac ip hostname download upload last_seen first_seen; do
        [ -z "$mac" ] && continue
        [ "${mac:0:1}" = "#" ] && continue

        local last_ts=$(date -d "$last_seen" '+%s' 2>/dev/null)
        if [ -n "$last_ts" ] && [ "$last_ts" -lt "$cutoff_time" ] 2>/dev/null; then
            continue
        fi

        echo "$mac|$ip|$hostname|$download|$upload|$last_seen|$first_seen" >> "$temp_file"
    done < "$TRAFFIC_FILE"

    cat "$temp_file" > "$TRAFFIC_FILE"
    rm -f "$temp_file"

    local events_file="$DATA_DIR/events.log"
    if [ -f "$events_file" ]; then
        local events_temp=$(mktemp)
        while IFS='|' read -r ts event mac name; do
            [ -z "$ts" ] && continue
            local event_ts=$(date -d "$ts" '+%s' 2>/dev/null)
            if [ -n "$event_ts" ] && [ "$event_ts" -lt "$cutoff_time" ] 2>/dev/null; then
                continue
            fi
            echo "$ts|$event|$mac|$name" >> "$events_temp"
        done < "$events_file"
        cat "$events_temp" > "$events_file"
        rm -f "$events_temp"
    fi

    echo "Cleaned up data older than $retention_days days"
}

case "$ACTION" in
    collect)
        collect_traffic
        track_online
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
    cleanup)
        cleanup_old_data "$@"
        ;;
    realtime)
        get_realtime_speed
        ;;
    track_online)
        track_online
        ;;
    *)
        echo "Usage: $0 [collect|stats|reset|device <mac>|cleanup [days]|realtime|track_online]"
        echo ""
        echo "Actions:"
        echo "  collect           - Collect current traffic data and track online status"
        echo "  stats [json]      - Show traffic statistics"
        echo "  reset             - Reset all statistics"
        echo "  device <mac>      - Show traffic for specific device"
        echo "  cleanup [days]    - Remove data older than N days (default: 30)"
        echo "  realtime          - Show real-time speed for all devices (JSON)"
        echo "  track_online      - Track online/offline status changes"
        exit 1
        ;;
esac

exit 0
