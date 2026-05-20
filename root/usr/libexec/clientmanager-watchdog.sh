#!/bin/sh
# Client Manager - Watchdog script (runs as procd service)
# Periodically collects traffic data and cleans up old records

INTERVAL=$(uci get clientmanager.global.scan_interval 2>/dev/null || echo 60)
TRAFFIC_MONITOR=$(uci get clientmanager.global.traffic_monitor 2>/dev/null || echo 0)
DATA_RETENTION=$(uci get clientmanager.global.data_retention 2>/dev/null || echo 30)

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

    INTERVAL=$(uci get clientmanager.global.scan_interval 2>/dev/null || echo 60)

    DATA_RETENTION=$(uci get clientmanager.global.data_retention 2>/dev/null || echo 30)
    /usr/libexec/clientmanager-traffic.sh cleanup "$DATA_RETENTION" 2>/dev/null

    sleep "$INTERVAL"
done
