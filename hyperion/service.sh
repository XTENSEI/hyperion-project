#!/system/bin/sh
# Hyperion Service - Simple daemon that keeps the binary running
# Based on Stellar's architecture - simple and reliable

MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
MODDIR=${MODDIR%/*}

# Simple loop that keeps the daemon running
while true; do
    if ! pgrep -x hyperiond; then
        $MODDIR/core/hyperiond daemon
    else
        exit 0
    fi
    sleep 5
done
