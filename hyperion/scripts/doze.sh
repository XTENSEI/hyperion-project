#!/system/bin/sh
# =============================================================================
# Hyperion Project - Doze Mode & Deep Sleep Optimization
# Made by ShadowBytePrjkt
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/doze.log"

dozelog() {
    local level="$1"; local msg="$2"
    local ts; ts=$(date -u +%H:%M:%S)
    echo "[$ts][DOZE][$level] $msg" >> "$LOG_FILE"
    echo "[$ts][DOZE][$level] $msg"
}

write() {
    local path="$1"; local value="$2"
    [ -f "$path" ] && [ -w "$path" ] && echo "$value" > "$path" 2>/dev/null
}

# ─── Configure Doze Mode ──────────────────────────────────────────────────────
configure_doze() {
    local mode="$1"

    dozelog "INFO" "Configuring doze mode: $mode"

    case "$mode" in
        aggressive)
            # Very aggressive doze - enters quickly, stays long
            settings put global device_idle_constants \
                "inactive_to=5000,sensing_to=0,locating_to=0,location_accuracy=2000,motion_inactive_to=0,idle_after_inactive_to=5000,idle_pending_factor=2.0,max_idle_pending_to=60000,idle_pending_to=30000,idle_factor=2.0,min_time_to_alarm=60000,max_temp_app_whitelist_duration=60000,mms_temp_app_whitelist_duration=30000,sms_temp_app_whitelist_duration=20000,light_after_inactive_to=5000,light_pre_idle_to=10000,light_idle_to=60000,light_idle_factor=2.0,light_max_idle_to=300000,light_idle_maintenance_min_budget=10000,light_idle_maintenance_max_budget=30000" \
                2>/dev/null
            dozelog "INFO" "Aggressive doze configured"
            ;;
        balanced)
            # Moderate doze
            settings put global device_idle_constants \
                "inactive_to=30000,sensing_to=4000,locating_to=30000,location_accuracy=2000,motion_inactive_to=10000,idle_after_inactive_to=30000,idle_pending_factor=2.0,max_idle_pending_to=120000,idle_pending_to=60000,idle_factor=2.0,min_time_to_alarm=60000,light_after_inactive_to=15000,light_pre_idle_to=30000,light_idle_to=180000,light_idle_factor=2.0,light_max_idle_to=900000,light_idle_maintenance_min_budget=30000,light_idle_maintenance_max_budget=60000" \
                2>/dev/null
            dozelog "INFO" "Balanced doze configured"
            ;;
        disabled)
            settings delete global device_idle_constants 2>/dev/null
            dozelog "INFO" "Doze mode: default (disabled custom)"
            ;;
    esac
}

# ─── Whitelist Management ─────────────────────────────────────────────────────
add_doze_whitelist() {
    local package="$1"
    dumpsys deviceidle whitelist "+$package" 2>/dev/null
    dozelog "INFO" "Added to doze whitelist: $package"
}

remove_doze_whitelist() {
    local package="$1"
    dumpsys deviceidle whitelist "-$package" 2>/dev/null
    dozelog "INFO" "Removed from doze whitelist: $package"
}

# ─── Deep Sleep Optimization ──────────────────────────────────────────────────
optimize_deep_sleep() {
    dozelog "INFO" "Optimizing deep sleep..."

    # Disable unnecessary wakeup sources
    # GPS
    write "/sys/class/gps/gps/power" "0"

    # NFC (if not needed)
    # write "/sys/class/nfc/nfc/power" "0"

    # Bluetooth scan interval
    settings put global bluetooth_scan_always_enabled "0" 2>/dev/null

    # WiFi scan throttle
    settings put global wifi_scan_throttle_enabled "1" 2>/dev/null
    settings put global wifi_scan_always_enabled "0" 2>/dev/null

    # Location services
    settings put secure location_mode "0" 2>/dev/null

    # Sync adapter throttle
    settings put global sync_max_retry_delay_sec "7200" 2>/dev/null

    dozelog "INFO" "Deep sleep optimization applied"
}

# ─── Suspend Blockers ─────────────────────────────────────────────────────────
list_wakelocks() {
    cat /sys/kernel/debug/wakeup_sources 2>/dev/null | \
        awk 'NR>1 && $4>0 {print $1, "active_count:", $4, "total_time:", $5}' | \
        sort -k4 -rn | head -20
}

# ─── Apply Profile ────────────────────────────────────────────────────────────
apply_profile() {
    local profile="$1"
    dozelog "INFO" "Applying doze profile: $profile"

    case "$profile" in
        gaming|performance)
            configure_doze "disabled"
            # Keep WiFi/BT active for gaming
            settings put global wifi_scan_always_enabled "0" 2>/dev/null
            dozelog "INFO" "Gaming/Performance: doze disabled"
            ;;
        balanced)
            configure_doze "balanced"
            # Whitelist essential apps
            add_doze_whitelist "com.google.android.gms"
            add_doze_whitelist "com.android.phone"
            dozelog "INFO" "Balanced doze applied"
            ;;
        battery)
            configure_doze "aggressive"
            optimize_deep_sleep
            dozelog "INFO" "Battery doze applied"
            ;;
        powersave)
            configure_doze "aggressive"
            optimize_deep_sleep
            # Force idle immediately
            dumpsys deviceidle force-idle 2>/dev/null
            dozelog "INFO" "Powersave doze applied (forced idle)"
            ;;
    esac
}

# ─── Main ─────────────────────────────────────────────────────────────────────
case "$1" in
    wakelocks)  list_wakelocks ;;
    whitelist)  add_doze_whitelist "$2" ;;
    *)          apply_profile "${1:-balanced}" ;;
esac
