#!/usr/bin/env bash
# Auto-reconnect to a wirelessly paired Android device.
#
# Pairing is one-time (survives reboots). This script handles the
# per-session "adb connect" step automatically before each launch.
#
# How it works:
#   1. If a device is already connected, do nothing.
#   2. Otherwise, discover the device via mDNS (adb mdns services).
#   3. Fall back to the last-known IP saved in .vscode/.adb_device.
#   4. If all else fails, prompt the user.

set -euo pipefail

DEVICE_CACHE="${BASH_SOURCE[0]%/*}/.adb_device"

# Already connected?
if adb devices 2>/dev/null | grep -qE 'device$'; then
    echo "ADB: device already connected"
    exit 0
fi

echo "ADB: no device connected, attempting reconnect..."

# Try mDNS discovery (Android 11+ exposes _adb-tls-connect._tcp)
connect_port=""
if adb mdns services 2>/dev/null | grep -q 'adb-tls-connect'; then
    # Extract IP:port from mDNS output
    mdns_line=$(adb mdns services 2>/dev/null | grep 'adb-tls-connect' | head -1)
    connect_addr=$(echo "$mdns_line" | grep -oP '\d+\.\d+\.\d+\.\d+:\d+' | head -1)
    if [ -n "$connect_addr" ]; then
        echo "ADB: found device via mDNS at $connect_addr"
        if adb connect "$connect_addr" 2>&1 | grep -q 'connected'; then
            echo "$connect_addr" > "$DEVICE_CACHE"
            echo "ADB: connected to $connect_addr"
            exit 0
        fi
    fi
fi

# Try last-known address from cache
if [ -f "$DEVICE_CACHE" ]; then
    cached=$(cat "$DEVICE_CACHE")
    echo "ADB: trying cached address $cached..."
    # Extract IP, scan for the current wireless debugging port
    cached_ip="${cached%%:*}"
    # Try the cached address first (port may not have changed)
    if adb connect "$cached" 2>&1 | grep -q 'connected'; then
        echo "ADB: connected to $cached"
        exit 0
    fi
    echo "ADB: cached port stale, scanning $cached_ip for ADB port..."
    # Quick scan of common high ports where Android wireless debugging listens
    for port in $(seq 37000 2 45000); do
        if timeout 0.05 bash -c "echo >/dev/tcp/$cached_ip/$port" 2>/dev/null; then
            if adb connect "$cached_ip:$port" 2>&1 | grep -q 'connected'; then
                echo "$cached_ip:$port" > "$DEVICE_CACHE"
                echo "ADB: connected to $cached_ip:$port"
                exit 0
            fi
        fi
    done
fi

echo ""
echo "================================================================"
echo "  Could not auto-connect to your Android device."
echo ""
echo "  On your phone: Developer options > Wireless debugging"
echo "  Note the IP:port shown, then run:"
echo ""
echo "    adb connect <IP>:<port>"
echo ""
echo "  (First time? Tap 'Pair' and run: adb pair <IP>:<pair_port>)"
echo "================================================================"
echo ""
exit 1
