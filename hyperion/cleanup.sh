#!/system/bin/sh
# =============================================================================
# Hyperion Project - Cleanup Script
# Made by ShadowBytePrjkt
# =============================================================================
# Runs on module uninstall to clean up all modifications
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"

# ─── Stop all services ───────────────────────────────────────────────────────
stop_services() {
    # Kill daemon
    if [ -f "$HYPERION_DIR/data/daemon.pid" ]; then
        kill "$(cat $HYPERION_DIR/data/daemon.pid)" 2>/dev/null
    fi

    # Kill by process name
    pkill -f "hyperion" 2>/dev/null

    # Remove socket
    rm -f /dev/hyperion.sock 2>/dev/null
    rm -f /dev/hyperion_ws.sock 2>/dev/null
}

# ─── Reset system settings ──────────────────────────────────────────────────
reset_settings() {
    # Reset CPU governor to default
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$cpu" ] && echo "schedutil" > "$cpu" 2>/dev/null
    done

    # Reset GPU
    for gpu in /sys/class/kgsl/kgsl-3d0/devfreq/governor; do
        [ -f "$gpu" ] && echo "msm-adreno-tz" > "$gpu" 2>/dev/null
    done

    # Reset memory
    echo "60" > /proc/sys/vm/swappiness 2>/dev/null

    # Reset network
    sysctl -w net.ipv4.tcp_congestion_control=cubic 2>/dev/null

    echo "System settings reset to defaults"
}

# ─── Remove data files (optional) ─────────────────────────────────────────────
remove_data() {
    # Ask user via property or default to keep data
    if [ "$HYPERION_CLEANUP_DATA" = "true" ]; then
        rm -rf "$HYPERION_DIR/data"
        rm -rf "$HYPERION_DIR/logs"
        echo "All data removed"
    else
        echo "Keeping data files (set HYPERION_CLEANUP_DATA=true to remove)"
    fi
}

# ─── Main ───────────────────────────────────────────────────────────────────
echo "Hyperion Project - Cleanup started"

stop_services
reset_settings
remove_data

echo "Cleanup complete"
exit 0
