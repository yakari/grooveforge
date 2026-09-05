#!/usr/bin/env bash
#
# adb-wifi.sh — re-arm wireless adb for a phone plugged in over USB.
#
# Wireless adb does not survive a reboot, a long idle, or the phone dropping
# off the network, and re-establishing it by hand is four commands with a
# device-specific IP in the middle. Plug the phone in, run this, unplug.
#
# Usage:
#   scripts/adb-wifi.sh              # re-arm and connect
#   scripts/adb-wifi.sh --status     # just report what is connected
#   scripts/adb-wifi.sh --off        # drop the wireless connection
#
# Exits non-zero if the phone could not be reached wirelessly, so it is safe
# to chain.

set -uo pipefail

PORT="${ADB_WIFI_PORT:-5555}"
# The interface to take the address from. Deliberately not "whatever adb
# reports first": a phone on a VPN also has a tun0, and connecting to that
# address fails with "No route to host" from the desktop.
IFACE="${ADB_WIFI_IFACE:-wlan0}"

say() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }

# Desktop notification when available, so this reads sensibly from a dash
# shortcut where nobody sees stdout.
notify() {
    local urgency="$1" title="$2" body="$3"
    command -v notify-send >/dev/null 2>&1 &&
        notify-send --urgency="$urgency" --app-name="adb-wifi" "$title" "$body"
    return 0
}

command -v adb >/dev/null 2>&1 || {
    err "adb not found in PATH"
    notify critical "adb-wifi" "adb is not installed or not in PATH"
    exit 1
}

# ── Device discovery ─────────────────────────────────────────────────────────

# Serial of a device attached over USB. Wireless entries are "ip:port", so a
# serial without a colon is the cable.
usb_serial() {
    adb devices | awk 'NR>1 && $2=="device" && $1 !~ /:/ {print $1; exit}'
}

# Any wireless entry currently registered, as "ip:port".
wifi_entry() {
    adb devices | awk 'NR>1 && $2=="device" && $1 ~ /:/ {print $1; exit}'
}

status() {
    local usb wifi
    usb="$(usb_serial)"
    wifi="$(wifi_entry)"
    say "USB:      ${usb:-none}"
    say "Wireless: ${wifi:-none}"
    [ -n "$wifi" ]
}

case "${1:-}" in
    --status)
        status
        exit $?
        ;;
    --off)
        entry="$(wifi_entry)"
        if [ -n "$entry" ]; then
            adb disconnect "$entry" >/dev/null 2>&1
            say "Disconnected $entry"
            notify normal "adb-wifi" "Wireless adb disconnected"
        else
            say "No wireless connection to drop"
        fi
        exit 0
        ;;
    -h|--help)
        sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac

# ── Re-arm ───────────────────────────────────────────────────────────────────

# Give a freshly plugged phone a moment to enumerate, rather than failing on a
# race the user cannot see.
serial="$(usb_serial)"
if [ -z "$serial" ]; then
    say "Waiting for a USB device (plug the phone in, allow the prompt)…"
    for _ in $(seq 1 20); do
        sleep 0.5
        serial="$(usb_serial)"
        [ -n "$serial" ] && break
    done
fi

if [ -z "$serial" ]; then
    err "No USB device. Is the cable in, USB debugging on, and the prompt allowed?"
    notify critical "adb-wifi" "No phone found over USB"
    exit 1
fi

ip="$(adb -s "$serial" shell ip -o addr show "$IFACE" 2>/dev/null |
      awk '$3=="inet" {split($4, a, "/"); print a[1]; exit}')"

if [ -z "$ip" ]; then
    err "No IPv4 address on $IFACE. Is the phone on Wi-Fi?"
    notify critical "adb-wifi" "Phone has no Wi-Fi address on $IFACE"
    exit 1
fi

# Drop any stale entry for this phone first. Reconnecting on top of a dead one
# is what produces "device offline" rather than a clean failure.
old="$(wifi_entry)"
[ -n "$old" ] && adb disconnect "$old" >/dev/null 2>&1

say "Phone $serial is at $ip — restarting adbd on port $PORT…"
adb -s "$serial" tcpip "$PORT" >/dev/null 2>&1

# adbd needs a moment to come back up on the new port; connecting too early
# fails with "Connection refused".
for attempt in 1 2 3 4 5 6; do
    sleep 1
    if adb connect "$ip:$PORT" 2>&1 | grep -qE 'connected to|already connected'; then
        break
    fi
    [ "$attempt" = 6 ] && {
        err "Could not connect to $ip:$PORT"
        notify critical "adb-wifi" "Could not reach $ip:$PORT"
        exit 1
    }
done

# Confirm rather than trust the connect message.
if [ "$(adb -s "$ip:$PORT" get-state 2>/dev/null)" != "device" ]; then
    err "Connected but the device is not responding at $ip:$PORT"
    notify critical "adb-wifi" "$ip:$PORT is not responding"
    exit 1
fi

model="$(adb -s "$ip:$PORT" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
say "Wireless adb ready: ${model:-device} at $ip:$PORT — you can unplug the cable."
notify normal "adb-wifi" "${model:-Device} connected at $ip:$PORT. Safe to unplug."
