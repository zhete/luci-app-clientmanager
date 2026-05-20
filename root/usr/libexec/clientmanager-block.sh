#!/bin/sh
# Client Manager - Device Blocking Script
# Usage: clientmanager-block.sh <mac_address> [action]
# Actions: block, unblock, check, restore

MAC="$1"
ACTION="${2:-block}"

if [ -n "$MAC" ]; then
    if ! echo "$MAC" | grep -qE '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'; then
        echo "Error: Invalid MAC address format"
        exit 1
    fi
    MAC=$(echo "$MAC" | tr '[:lower:]' '[:upper:]')
fi

get_ip_by_mac() {
    local mac="$1"
    cat /proc/net/arp 2>/dev/null | grep -i "$mac" | awk '{print $1}' | head -1
}

block_device() {
    local mac="$1"
    local ip=$(get_ip_by_mac "$mac")

    if iptables -C FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null; then
        echo "Device $mac is already blocked"
        return 0
    fi

    iptables -I FORWARD -m mac --mac-source "$mac" -j DROP
    iptables -I INPUT -m mac --mac-source "$mac" -j DROP

    if [ -n "$ip" ]; then
        iptables -I FORWARD -s "$ip" -j DROP
        iptables -I FORWARD -d "$ip" -j DROP
    fi

    if ! echo "$mac" | grep -qi "^[0-9a-f]" || [ -z "$(uci get_list clientmanager.global.blocked 2>/dev/null | grep -i "$mac")" ]; then
        uci add_list clientmanager.global.blocked="$mac"
        uci commit clientmanager
    fi

    echo "Device $mac blocked successfully"
    return 0
}

unblock_device() {
    local mac="$1"
    local ip=$(get_ip_by_mac "$mac")

    iptables -D FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null
    iptables -D INPUT -m mac --mac-source "$mac" -j DROP 2>/dev/null

    if [ -n "$ip" ]; then
        iptables -D FORWARD -s "$ip" -j DROP 2>/dev/null
        iptables -D FORWARD -d "$ip" -j DROP 2>/dev/null
    fi

    uci del_list clientmanager.global.blocked="$mac" 2>/dev/null
    uci commit clientmanager

    echo "Device $mac unblocked successfully"
    return 0
}

check_device() {
    local mac="$1"

    if iptables -C FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null; then
        echo "blocked"
    else
        echo "unblocked"
    fi
    return 0
}

restore_rules() {
    local blocked_list=$(uci get_list clientmanager.global.blocked 2>/dev/null)

    for mac in $blocked_list; do
        [ -z "$mac" ] && continue
        
        # 验证 MAC 格式
        if ! echo "$mac" | grep -qE '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'; then
            continue
        fi

        if ! iptables -C FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null; then
            iptables -I FORWARD -m mac --mac-source "$mac" -j DROP
            iptables -I INPUT -m mac --mac-source "$mac" -j DROP

            local ip=$(get_ip_by_mac "$mac")
            if [ -n "$ip" ]; then
                iptables -I FORWARD -s "$ip" -j DROP 2>/dev/null
                iptables -I FORWARD -d "$ip" -j DROP 2>/dev/null
            fi
        fi
    done

    echo "Blocked device rules restored"
}

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
    restore)
        restore_rules
        ;;
    *)
        echo "Usage: $0 <mac_address> [block|unblock|check|restore]"
        exit 1
        ;;
esac

exit 0
