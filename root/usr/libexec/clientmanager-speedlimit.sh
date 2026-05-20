#!/bin/sh
# Client Manager - Speed Limit Script
# Usage: clientmanager-speedlimit.sh <mac_address> <download_kbps> <upload_kbps>
# Uses unique tc class/filter per device to avoid conflicts

MAC="$1"
DOWNLOAD="${2:-0}"
UPLOAD="${3:-0}"

if [ -z "$MAC" ] || ! echo "$MAC" | grep -qE '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'; then
    echo "Error: Invalid MAC address format"
    exit 1
fi

MAC=$(echo "$MAC" | tr '[:lower:]' '[:upper:]')

get_ip_by_mac() {
    local mac="$1"
    cat /proc/net/arp 2>/dev/null | grep -i "$mac" | awk '{print $1}' | head -1
}

get_iface_by_mac() {
    local mac="$1"
    cat /proc/net/arp 2>/dev/null | grep -i "$mac" | awk '{print $6}' | head -1
}

mac_to_mark() {
    local mac="$1"
    echo "$mac" | tr -d ':' | awk '{printf "%d\n", "0x" substr($1, 5, 4)}'
}

ensure_tc_root() {
    local iface="$1"

    if ! tc qdisc show dev "$iface" 2>/dev/null | grep -q "htb"; then
        tc qdisc add dev "$iface" root handle 1: htb default 9999 2>/dev/null
        tc class add dev "$iface" parent 1: classid 1:9999 htb rate 1000mbit ceil 1000mbit 2>/dev/null
    fi
}

remove_limit() {
    local mac="$1"
    local iface="$2"
    local mark=$(mac_to_mark "$mac")

    [ -z "$iface" ] && iface="br-lan"

    local class_id=$(printf "1:%x" "$mark")
    local filter_handle=$(printf "0x%x" "$mark")

    tc filter del dev "$iface" parent 1: protocol ip handle "$filter_handle" fw classid "$class_id" 2>/dev/null
    tc class del dev "$iface" parent 1: classid "$class_id" 2>/dev/null

    iptables -t mangle -D PREROUTING -m mac --mac-source "$mac" -j MARK --set-mark "$mark" 2>/dev/null

    local ip=$(get_ip_by_mac "$mac")
    if [ -n "$ip" ]; then
        local dl_mark=$((mark + 32768))
        iptables -t mangle -D POSTROUTING -d "$ip" -j MARK --set-mark "$dl_mark" 2>/dev/null
        tc filter del dev "$iface" parent 1: protocol ip handle "$(printf '0x%x' $dl_mark)" fw classid "$(printf '1:%x' $dl_mark)" 2>/dev/null
        tc class del dev "$iface" parent 1: classid "$(printf '1:%x' $dl_mark)" 2>/dev/null
    fi

    echo "Speed limit removed for $mac"
}

apply_limit() {
    local mac="$1"
    local download="$2"
    local upload="$3"
    local ip=$(get_ip_by_mac "$mac")
    local iface=$(get_iface_by_mac "$mac")

    [ -z "$iface" ] && iface="br-lan"

    if [ "$download" = "0" ] && [ "$upload" = "0" ]; then
        remove_limit "$mac" "$iface"

        local section=""
        local uci_output=$(uci show clientmanager 2>/dev/null | grep "limit\.")
        for line in $uci_output; do
            local sec=$(echo "$line" | cut -d'.' -f2 | cut -d'=' -f1)
            local sec_mac=$(uci get "clientmanager.${sec}.mac" 2>/dev/null)
            if [ "$sec_mac" = "$mac" ]; then
                section="$sec"
                break
            fi
        done

        if [ -n "$section" ]; then
            uci delete "clientmanager.${section}" 2>/dev/null
            uci commit clientmanager
        fi

        echo "Speed limit removed for $mac"
        return 0
    fi

    ensure_tc_root "$iface"

    remove_limit "$mac" "$iface"

    local mark=$(mac_to_mark "$mac")

    if [ "$upload" != "0" ]; then
        local upload_rate="${upload}kbit"
        local ul_class=$(printf "1:%x" "$mark")

        tc class add dev "$iface" parent 1: classid "$ul_class" htb rate "$upload_rate" ceil "$upload_rate" 2>/dev/null
        tc filter add dev "$iface" parent 1: protocol ip prio 1 handle "$(printf '0x%x' "$mark")" fw classid "$ul_class" 2>/dev/null

        iptables -t mangle -I PREROUTING -m mac --mac-source "$mac" -j MARK --set-mark "$mark" 2>/dev/null
    fi

    if [ "$download" != "0" ]; then
        local download_rate="${download}kbit"
        local dl_mark=$((mark + 32768))
        local dl_class=$(printf "1:%x" "$dl_mark")

        tc class add dev "$iface" parent 1: classid "$dl_class" htb rate "$download_rate" ceil "$download_rate" 2>/dev/null
        tc filter add dev "$iface" parent 1: protocol ip prio 1 handle "$(printf '0x%x' "$dl_mark")" fw classid "$dl_class" 2>/dev/null

        if [ -n "$ip" ]; then
            iptables -t mangle -I POSTROUTING -d "$ip" -j MARK --set-mark "$dl_mark" 2>/dev/null
        fi
    fi

    local section=""
    local uci_output=$(uci show clientmanager 2>/dev/null | grep "limit\.")
    for line in $uci_output; do
        local sec=$(echo "$line" | cut -d'.' -f2 | cut -d'=' -f1)
        local sec_mac=$(uci get "clientmanager.${sec}.mac" 2>/dev/null)
        if [ "$sec_mac" = "$mac" ]; then
            section="$sec"
            break
        fi
    done

    if [ -z "$section" ]; then
        section=$(uci add clientmanager limit)
    fi

    uci set "clientmanager.${section}.mac=$mac"
    uci set "clientmanager.${section}.download=$download"
    uci set "clientmanager.${section}.upload=$upload"
    uci commit clientmanager

    echo "Speed limit applied to $mac: Download ${download}kbps, Upload ${upload}kbps"
    return 0
}

show_limits() {
    echo "Current Speed Limits:"
    echo "===================="
    printf "%-17s %-12s %-12s\n" "MAC" "Download" "Upload"
    echo "-------------------------------------------"

    uci show clientmanager 2>/dev/null | grep "limit\[" | while read -r line; do
        local section=$(echo "$line" | cut -d'.' -f2 | cut -d'=' -f1)
        local mac=$(uci get "clientmanager.${section}.mac" 2>/dev/null)
        local download=$(uci get "clientmanager.${section}.download" 2>/dev/null)
        local upload=$(uci get "clientmanager.${section}.upload" 2>/dev/null)

        if [ -n "$mac" ]; then
            printf "%-17s %-12s %-12s\n" "$mac" "${download}kbps" "${upload}kbps"
        fi
    done
}

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
