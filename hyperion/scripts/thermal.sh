#!/system/bin/sh
# =============================================================================
# Hyperion Project - Thermal Management Script
# Made by ShadowBytePrjkt
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/thermal.log"

tlog() {
    local level="$1"; local msg="$2"
    local ts; ts=$(date -u +%H:%M:%S)
    echo "[$ts][THERMAL][$level] $msg" >> "$LOG_FILE"
    echo "[$ts][THERMAL][$level] $msg"
}

write() {
    local path="$1"; local value="$2"
    [ -f "$path" ] && [ -w "$path" ] && echo "$value" > "$path" 2>/dev/null
}

# ─── Get Current Temperature ──────────────────────────────────────────────────
get_temp() {
    local zone="${1:-0}"
    local temp_path="/sys/class/thermal/thermal_zone${zone}/temp"
    if [ -f "$temp_path" ]; then
        local raw
        raw=$(cat "$temp_path" 2>/dev/null)
        # Convert millidegrees to degrees if needed
        if [ "$raw" -gt 1000 ] 2>/dev/null; then
            echo $((raw / 1000))
        else
            echo "$raw"
        fi
    else
        echo "0"
    fi
}

# ─── Get Battery Temperature ──────────────────────────────────────────────────
get_battery_temp() {
    local bat_temp="/sys/class/power_supply/battery/temp"
    if [ -f "$bat_temp" ]; then
        local raw
        raw=$(cat "$bat_temp" 2>/dev/null)
        echo $((raw / 10))
    else
        echo "0"
    fi
}

# ─── List All Thermal Zones ───────────────────────────────────────────────────
list_thermal_zones() {
    for zone in /sys/class/thermal/thermal_zone*/; do
        local zone_num
        zone_num=$(basename "$zone" | tr -d 'thermal_zone')
        local zone_type
        zone_type=$(cat "${zone}type" 2>/dev/null)
        local temp
        temp=$(get_temp "$zone_num")
        echo "Zone $zone_num ($zone_type): ${temp}°C"
    done
}

# ─── Configure Thermal Engine ─────────────────────────────────────────────────
configure_thermal_engine() {
    local mode="$1"

    # Qualcomm thermal engine
    local THERMAL_ENGINE="/sys/module/msm_thermal/parameters"
    if [ -d "$THERMAL_ENGINE" ]; then
        case "$mode" in
            performance)
                write "$THERMAL_ENGINE/enabled" "N"
                write "$THERMAL_ENGINE/core_limit_temp_degC" "90"
                write "$THERMAL_ENGINE/freq_limit_temp_degC" "85"
                tlog "INFO" "Qualcomm thermal engine: performance mode"
                ;;
            balanced)
                write "$THERMAL_ENGINE/enabled" "Y"
                write "$THERMAL_ENGINE/core_limit_temp_degC" "80"
                write "$THERMAL_ENGINE/freq_limit_temp_degC" "75"
                tlog "INFO" "Qualcomm thermal engine: balanced mode"
                ;;
            conservative)
                write "$THERMAL_ENGINE/enabled" "Y"
                write "$THERMAL_ENGINE/core_limit_temp_degC" "70"
                write "$THERMAL_ENGINE/freq_limit_temp_degC" "65"
                tlog "INFO" "Qualcomm thermal engine: conservative mode"
                ;;
        esac
    fi

    # MediaTek thermal
    local MTK_THERMAL="/proc/mtkthermal"
    if [ -f "$MTK_THERMAL" ]; then
        case "$mode" in
            performance)
                echo "disable" > "$MTK_THERMAL" 2>/dev/null
                ;;
            *)
                echo "enable" > "$MTK_THERMAL" 2>/dev/null
                ;;
        esac
    fi

    # Generic thermal zones - set trip points
    for zone in /sys/class/thermal/thermal_zone*/; do
        local zone_type
        zone_type=$(cat "${zone}type" 2>/dev/null)

        # Only modify CPU/GPU thermal zones
        if echo "$zone_type" | grep -qi "cpu\|gpu\|soc\|skin"; then
            for trip in "${zone}"trip_point_*_temp; do
                if [ -f "$trip" ] && [ -w "$trip" ]; then
                    local current_trip
                    current_trip=$(cat "$trip" 2>/dev/null)
                    case "$mode" in
                        performance)
                            # Raise trip points by 10°C
                            local new_trip=$((current_trip + 10000))
                            write "$trip" "$new_trip"
                            ;;
                        conservative)
                            # Lower trip points by 5°C
                            local new_trip=$((current_trip - 5000))
                            [ "$new_trip" -gt 0 ] && write "$trip" "$new_trip"
                            ;;
                    esac
                fi
            done
        fi
    done
}

# ─── Cooling Device Control ───────────────────────────────────────────────────
configure_cooling() {
    local mode="$1"

    for cooling in /sys/class/thermal/cooling_device*/; do
        local cooling_type
        cooling_type=$(cat "${cooling}type" 2>/dev/null)
        local max_state
        max_state=$(cat "${cooling}max_state" 2>/dev/null)

        case "$mode" in
            performance)
                # Minimize cooling (allow higher performance)
                write "${cooling}cur_state" "0"
                ;;
            balanced)
                # Let thermal engine manage
                ;;
            conservative)
                # Maximize cooling
                write "${cooling}cur_state" "$max_state"
                ;;
        esac
    done
}

# ─── Skin Temperature Limit ───────────────────────────────────────────────────
set_skin_temp_limit() {
    local limit_c="$1"

    # Qualcomm skin temperature
    local SKIN_TEMP="/sys/class/thermal/thermal_zone*/type"
    for zone_type_file in /sys/class/thermal/thermal_zone*/type; do
        local zone_type
        zone_type=$(cat "$zone_type_file" 2>/dev/null)
        if echo "$zone_type" | grep -qi "skin\|xo-therm\|pa-therm"; then
            local zone_dir
            zone_dir=$(dirname "$zone_type_file")
            for trip in "${zone_dir}"/trip_point_*_temp; do
                [ -w "$trip" ] && write "$trip" "$((limit_c * 1000))"
            done
        fi
    done

    tlog "INFO" "Skin temperature limit: ${limit_c}°C"
}

# ─── Apply Profile ────────────────────────────────────────────────────────────
apply_profile() {
    local profile="$1"
    tlog "INFO" "Applying thermal profile: $profile"

    case "$profile" in
        gaming)
            configure_thermal_engine "performance"
            configure_cooling "performance"
            set_skin_temp_limit "48"
            tlog "INFO" "Gaming thermal profile applied (limit: 48°C)"
            ;;
        performance)
            configure_thermal_engine "performance"
            configure_cooling "performance"
            set_skin_temp_limit "45"
            tlog "INFO" "Performance thermal profile applied (limit: 45°C)"
            ;;
        balanced)
            configure_thermal_engine "balanced"
            configure_cooling "balanced"
            set_skin_temp_limit "42"
            tlog "INFO" "Balanced thermal profile applied (limit: 42°C)"
            ;;
        battery|powersave)
            configure_thermal_engine "conservative"
            configure_cooling "conservative"
            set_skin_temp_limit "38"
            tlog "INFO" "Battery thermal profile applied (limit: 38°C)"
            ;;
    esac

    # Log current temperatures
    local cpu_temp bat_temp
    cpu_temp=$(get_temp 0)
    bat_temp=$(get_battery_temp)
    tlog "INFO" "Current temps - CPU: ${cpu_temp}°C, Battery: ${bat_temp}°C"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
case "$1" in
    list)   list_thermal_zones ;;
    temp)   get_temp "${2:-0}" ;;
    *)      apply_profile "${1:-balanced}" ;;
esac
