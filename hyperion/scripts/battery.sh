#!/system/bin/sh
# =============================================================================
# Hyperion Project - Battery Optimization Script
# Made by ShadowBytePrjkt
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/battery.log"

blog() {
    local level="$1"; local msg="$2"
    local ts; ts=$(date -u +%H:%M:%S)
    echo "[$ts][BAT][$level] $msg" >> "$LOG_FILE"
    echo "[$ts][BAT][$level] $msg"
}

write() {
    local path="$1"; local value="$2"
    [ -f "$path" ] && [ -w "$path" ] && echo "$value" > "$path" 2>/dev/null
}

# ─── Get Battery Info ─────────────────────────────────────────────────────────
get_battery_level() {
    cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "50"
}

get_charging_status() {
    local status
    status=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
    echo "$status"
}

is_charging() {
    local status
    status=$(get_charging_status)
    [ "$status" = "Charging" ] || [ "$status" = "Full" ]
}

# ─── Charging Current Limits ──────────────────────────────────────────────────
set_charging_current() {
    local current_ma="$1"
    local current_ua=$((current_ma * 1000))

    blog "INFO" "Setting charging current: ${current_ma}mA"

    # Generic paths
    for path in \
        /sys/class/power_supply/battery/constant_charge_current_max \
        /sys/class/power_supply/battery/input_current_limit \
        /sys/class/power_supply/usb/input_current_limit \
        /sys/class/power_supply/ac/input_current_limit; do
        write "$path" "$current_ua"
    done

    # Qualcomm specific
    write "/sys/class/power_supply/battery/charge_control_limit" "$current_ma"

    # MediaTek specific
    write "/proc/mtk_battery_cmd/current_cmd" "0x${current_ma}"
}

# ─── Charging Voltage Limit ───────────────────────────────────────────────────
set_charging_voltage() {
    local voltage_mv="$1"
    local voltage_uv=$((voltage_mv * 1000))

    blog "INFO" "Setting charging voltage: ${voltage_mv}mV"

    for path in \
        /sys/class/power_supply/battery/constant_charge_voltage_max \
        /sys/class/power_supply/battery/voltage_max; do
        write "$path" "$voltage_uv"
    done
}

# ─── Wakelock Blocking ────────────────────────────────────────────────────────
block_wakelocks() {
    local mode="$1"
    local WAKELOCK_DIR="/sys/class/wakeup"

    if [ ! -d "$WAKELOCK_DIR" ]; then
        blog "WARN" "Wakelock sysfs not available"
        return
    fi

    case "$mode" in
        aggressive)
            # Block known battery-draining wakelocks
            for wakelock in \
                "wlan_rx_wake" \
                "wlan_ctrl_wake" \
                "wlan_txfl_wake" \
                "IPA_WS" \
                "qcom_rx_wakelock" \
                "netmgr_wl" \
                "NETLINK" \
                "event0-1-1"; do
                for wl_path in "$WAKELOCK_DIR"/*/name; do
                    if [ "$(cat $wl_path 2>/dev/null)" = "$wakelock" ]; then
                        local wl_dir
                        wl_dir=$(dirname "$wl_path")
                        write "${wl_dir}/prevent_suspend_time" "0"
                    fi
                done
            done
            blog "INFO" "Aggressive wakelock blocking enabled"
            ;;
        normal)
            blog "INFO" "Normal wakelock mode"
            ;;
    esac
}

# ─── Doze Mode Enhancement ────────────────────────────────────────────────────
enhance_doze() {
    local enabled="$1"

    if [ "$enabled" = "1" ]; then
        # Force aggressive doze
        dumpsys deviceidle enable 2>/dev/null
        dumpsys deviceidle force-idle 2>/dev/null
        # Reduce doze entry time
        settings put global device_idle_constants \
            "light_after_inactive_to=15000,light_pre_idle_to=30000,light_idle_to=180000,light_idle_factor=2.0,light_max_idle_to=900000,light_idle_maintenance_min_budget=30000,light_idle_maintenance_max_budget=60000,min_time_to_alarm=60000,idle_after_inactive_to=30000,sensing_to=0,locating_to=0,location_accuracy=2000,motion_inactive_to=0,idle_to=900000,idle_factor=2.0,max_idle_pending_factor=2.0,idle_pending_factor=2.0,max_idle_pending_to=120000,idle_pending_to=60000,max_travel_detect_to=0,travel_detect_to=0,inactive_to=15000" \
            2>/dev/null
        blog "INFO" "Enhanced doze mode enabled"
    else
        dumpsys deviceidle disable 2>/dev/null
        settings delete global device_idle_constants 2>/dev/null
        blog "INFO" "Doze mode: default"
    fi
}

# ─── Background Process Limits ────────────────────────────────────────────────
set_bg_process_limit() {
    local limit="$1"

    # Limit background processes
    settings put global background_process_limit "$limit" 2>/dev/null
    blog "INFO" "Background process limit: $limit"
}

# ─── Screen-off Optimizations ─────────────────────────────────────────────────
screen_off_optimize() {
    blog "INFO" "Applying screen-off optimizations"

    # Reduce CPU frequency when screen is off
    local cpu_count
    cpu_count=$(ls /sys/devices/system/cpu/ | grep -c "^cpu[0-9]")
    for i in $(seq 0 $((cpu_count - 1))); do
        local max_freq
        max_freq=$(cat "/sys/devices/system/cpu/cpu${i}/cpufreq/cpuinfo_max_freq" 2>/dev/null)
        if [ -n "$max_freq" ]; then
            local limited_freq=$((max_freq / 3))
            write "/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_max_freq" "$limited_freq"
        fi
    done

    # Disable GPU when screen is off
    write "/sys/class/kgsl/kgsl-3d0/force_clk_on" "0"
    write "/sys/class/kgsl/kgsl-3d0/force_bus_on" "0"
}

# ─── Apply Profile ────────────────────────────────────────────────────────────
apply_profile() {
    local profile="$1"
    local bat_level
    bat_level=$(get_battery_level)
    local charging
    charging=$(is_charging && echo "yes" || echo "no")

    blog "INFO" "Applying battery profile: $profile (level: ${bat_level}%, charging: $charging)"

    case "$profile" in
        gaming|performance)
            # Allow maximum charging current for fast charge
            set_charging_current "3000"
            set_charging_voltage "4400"
            block_wakelocks "normal"
            enhance_doze "0"
            set_bg_process_limit "32"
            blog "INFO" "Gaming/Performance battery profile applied"
            ;;
        balanced)
            set_charging_current "2000"
            set_charging_voltage "4350"
            block_wakelocks "normal"
            enhance_doze "0"
            set_bg_process_limit "16"
            blog "INFO" "Balanced battery profile applied"
            ;;
        battery)
            set_charging_current "1500"
            set_charging_voltage "4300"
            block_wakelocks "aggressive"
            enhance_doze "1"
            set_bg_process_limit "4"
            blog "INFO" "Battery saving profile applied"
            ;;
        powersave)
            set_charging_current "1000"
            set_charging_voltage "4200"
            block_wakelocks "aggressive"
            enhance_doze "1"
            set_bg_process_limit "2"
            screen_off_optimize
            blog "INFO" "Powersave battery profile applied"
            ;;
    esac

    # Critical battery emergency
    if [ "$bat_level" -lt 5 ] && ! is_charging; then
        blog "WARN" "Critical battery! Applying emergency powersave"
        set_bg_process_limit "1"
        enhance_doze "1"
        block_wakelocks "aggressive"
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
case "$1" in
    level)   get_battery_level ;;
    status)  get_charging_status ;;
    *)       apply_profile "${1:-balanced}" ;;
esac
