#!/bin/sh
# Client Manager - Watchdog script (runs as procd service)
# Periodically collects traffic data, tracks online status,
# enforces scheduled blocking, and cleans up old records

DATA_DIR="/etc/clientmanager"
LAST_CLEANUP_FILE="$DATA_DIR/.last_cleanup"
LAST_SCHEDULE_FILE="$DATA_DIR/.last_schedule"

cleanup_if_needed() {
    local retention_days=$(uci get clientmanager.global.data_retention 2>/dev/null || echo 30)
    local now=$(date '+%s')
    local last_cleanup=0

    if [ -f "$LAST_CLEANUP_FILE" ]; then
        last_cleanup=$(cat "$LAST_CLEANUP_FILE" 2>/dev/null)
    fi

    local cleanup_interval=$((24 * 3600))
    if [ $((now - last_cleanup)) -ge "$cleanup_interval" ]; then
        /usr/libexec/clientmanager-traffic.sh cleanup "$retention_days" 2>/dev/null
        echo "$now" > "$LAST_CLEANUP_FILE"
    fi
}

enforce_schedules() {
    local now=$(date '+%s')
    local last_schedule=0

    if [ -f "$LAST_SCHEDULE_FILE" ]; then
        last_schedule=$(cat "$LAST_SCHEDULE_FILE" 2>/dev/null)
    fi

    if [ $((now - last_schedule)) -lt 60 ]; then
        return
    fi

    echo "$now" > "$LAST_SCHEDULE_FILE"

    local current_day=$(date '+%a' | tr '[:upper:]' '[:lower:]')
    local current_time=$(date '+%H:%M')
    local current_mins=$(echo "$current_time" | awk -F: '{print ($1 * 60) + $2}')

    uci show clientmanager 2>/dev/null | grep "schedule\[" | while read -r line; do
        local section=$(echo "$line" | cut -d'.' -f2 | cut -d'=' -f1)
        local mac=$(uci get "clientmanager.${section}.mac" 2>/dev/null)
        local action=$(uci get "clientmanager.${section}.action" 2>/dev/null)
        local name=$(uci get "clientmanager.${section}.name" 2>/dev/null)

        [ -z "$mac" ] && continue

        local day_start_key="${current_day}_start"
        local day_end_key="${current_day}_end"

        local start_time=$(uci get "clientmanager.${section}.${day_start_key}" 2>/dev/null)
        local end_time=$(uci get "clientmanager.${section}.${day_end_key}" 2>/dev/null)

        [ -z "$start_time" ] || [ -z "$end_time" ] && continue

        local start_mins=$(echo "$start_time" | awk -F: '{print ($1 * 60) + $2}')
        local end_mins=$(echo "$end_time" | awk -F: '{print ($1 * 60) + $2}')

        if [ "$current_mins" -ge "$start_mins" ] && [ "$current_mins" -lt "$end_mins" ] 2>/dev/null; then
            if [ "$action" = "block" ]; then
                /usr/libexec/clientmanager-block.sh "$mac" block 2>/dev/null
            else
                /usr/libexec/clientmanager-block.sh "$mac" unblock 2>/dev/null
            fi
        else
            if [ "$action" = "block" ]; then
                /usr/libexec/clientmanager-block.sh "$mac" unblock 2>/dev/null
            else
                /usr/libexec/clientmanager-block.sh "$mac" block 2>/dev/null
            fi
        fi
    done
}

check_whitelist_mode() {
    local mode=$(uci get clientmanager.global.mode 2>/dev/null)
    [ "$mode" != "whitelist" ] && return

    local allowed_list=$(uci get_list clientmanager.global.allowed 2>/dev/null)
    local chain_exists=$(iptables -L CLIENTMGR_WHITELIST -n 2>/dev/null | head -1)

    if [ -z "$chain_exists" ]; then
        iptables -N CLIENTMGR_WHITELIST 2>/dev/null
        iptables -I FORWARD -j CLIENTMGR_WHITELIST 2>/dev/null
    else
        iptables -F CLIENTMGR_WHITELIST 2>/dev/null
    fi

    for mac in $allowed_list; do
        [ -z "$mac" ] && continue
        iptables -A CLIENTMGR_WHITELIST -m mac --mac-source "$mac" -j RETURN 2>/dev/null
    done

    iptables -A CLIENTMGR_WHITELIST -j DROP 2>/dev/null
}

check_new_devices() {
    local alert=$(uci get clientmanager.global.new_device_alert 2>/dev/null || echo 0)
    [ "$alert" != "1" ] && return

    local known_devices_file="$DATA_DIR/known_devices.list"
    touch "$known_devices_file"

    while read -r line; do
        local mac=$(echo "$line" | awk '{print $4}')
        [ -z "$mac" ] || [ "$mac" = "00:00:00:00:00:00" ] && continue
        ! echo "$mac" | grep -qE '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$' && continue

        local mac_upper=$(echo "$mac" | tr '[:lower:]' '[:upper:]')

        if ! grep -qi "^${mac_upper}$" "$known_devices_file" 2>/dev/null; then
            echo "$mac_upper" >> "$known_devices_file"

            local ip=$(echo "$line" | awk '{print $1}')
            local hostname=$(grep -i "$mac_upper" /tmp/dhcp.leases 2>/dev/null | awk '{print $4}')

            local log_line="$(date '+%Y-%m-%d %H:%M:%S')|new_device|$mac_upper|${hostname:-Unknown}"
            echo "$log_line" >> "$DATA_DIR/events.log"

            local notification_enabled=$(uci get clientmanager.notification.enabled 2>/dev/null || echo 0)
            if [ "$notification_enabled" = "1" ]; then
                local email=$(uci get clientmanager.notification.email 2>/dev/null)
                if [ -n "$email" ]; then
                    echo "New device detected: $mac_upper ($hostname) at $ip" | \
                        mail -s "Client Manager: New Device Alert" "$email" 2>/dev/null
                fi
            fi
        fi
    done < /proc/net/arp
}

while true; do
    ENABLED=$(uci get clientmanager.global.enabled 2>/dev/null)
    [ "$ENABLED" = "1" ] || {
        sleep 60
        continue
    }

    TRAFFIC_MONITOR=$(uci get clientmanager.global.traffic_monitor 2>/dev/null || echo 0)
    if [ "$TRAFFIC_MONITOR" = "1" ]; then
        /usr/libexec/clientmanager-traffic.sh collect 2>/dev/null
    fi

    enforce_schedules

    check_whitelist_mode

    check_new_devices

    cleanup_if_needed

    INTERVAL=$(uci get clientmanager.global.scan_interval 2>/dev/null || echo 60)
    sleep "$INTERVAL"
done
