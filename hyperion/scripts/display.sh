#!/system/bin/sh
# =============================================================================
# Hyperion Project - Display Optimization Script
# Made by ShadowBytePrjkt
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/display.log"

dlog() {
    local level="$1"; local msg="$2"
    local ts; ts=$(date -u +%H:%M:%S)
    echo "[$ts][DISP][$level] $msg" >> "$LOG_FILE"
    echo "[$ts][DISP][$level] $msg"
}

write() {
    local path="$1"; local value="$2"
    [ -f "$path" ] && [ -w "$path" ] && echo "$value" > "$path" 2>/dev/null
}

# ─── Get Available Refresh Rates ──────────────────────────────────────────────
get_available_refresh_rates() {
    # Try DRM sysfs
    for drm in /sys/class/drm/card*/; do
        if [ -f "${drm}modes" ]; then
            grep -oP '\d+x\d+@\K\d+' "${drm}modes" 2>/dev/null | sort -nu
            return
        fi
    done
    echo "60"
}

# ─── Set Refresh Rate ─────────────────────────────────────────────────────────
set_refresh_rate() {
    local rate="$1"
    dlog "INFO" "Setting refresh rate: ${rate}Hz"

    # Android settings (works on most devices)
    settings put system peak_refresh_rate "$rate" 2>/dev/null
    settings put system min_refresh_rate "$rate" 2>/dev/null

    # Qualcomm specific
    write "/sys/class/drm/card0-DSI-1/dynamic_fps" "$rate"

    # Samsung specific
    write "/sys/class/backlight/panel0-backlight/refresh_rate" "$rate"

    # Generic DRM
    for drm in /sys/class/drm/card*/; do
        write "${drm}refresh_rate" "$rate"
    done

    dlog "INFO" "Refresh rate set to ${rate}Hz"
}

# ─── Set Adaptive Refresh Rate ────────────────────────────────────────────────
set_adaptive_refresh() {
    local enabled="$1"

    if [ "$enabled" = "1" ]; then
        settings put system peak_refresh_rate "$(get_available_refresh_rates | tail -1)" 2>/dev/null
        settings put system min_refresh_rate "60" 2>/dev/null
        dlog "INFO" "Adaptive refresh rate: enabled"
    else
        local max_rate
        max_rate=$(get_available_refresh_rates | tail -1)
        settings put system peak_refresh_rate "$max_rate" 2>/dev/null
        settings put system min_refresh_rate "$max_rate" 2>/dev/null
        dlog "INFO" "Adaptive refresh rate: disabled (fixed ${max_rate}Hz)"
    fi
}

# ─── Display Color Calibration ────────────────────────────────────────────────
set_color_mode() {
    local mode="$1"

    case "$mode" in
        vivid)
            settings put system display_color_mode "3" 2>/dev/null
            # Qualcomm QDCM
            write "/sys/class/graphics/fb0/color_enhance" "1"
            dlog "INFO" "Color mode: vivid"
            ;;
        natural)
            settings put system display_color_mode "0" 2>/dev/null
            write "/sys/class/graphics/fb0/color_enhance" "0"
            dlog "INFO" "Color mode: natural"
            ;;
        saturated)
            settings put system display_color_mode "2" 2>/dev/null
            dlog "INFO" "Color mode: saturated"
            ;;
    esac
}

# ─── HBM (High Brightness Mode) ──────────────────────────────────────────────
set_hbm() {
    local enabled="$1"

    write "/sys/class/backlight/panel0-backlight/hbm_mode" "$enabled"
    write "/sys/class/drm/card0-DSI-1/hbm_mode" "$enabled"
    write "/sys/class/leds/lcd-backlight/hbm" "$enabled"

    dlog "INFO" "HBM: $enabled"
}

# ─── Screen Timeout ───────────────────────────────────────────────────────────
set_screen_timeout() {
    local ms="$1"
    settings put system screen_off_timeout "$ms" 2>/dev/null
    dlog "INFO" "Screen timeout: ${ms}ms"
}

# ─── Apply Profile ────────────────────────────────────────────────────────────
apply_profile() {
    local profile="$1"
    dlog "INFO" "Applying display profile: $profile"

    case "$profile" in
        gaming)
            # Maximum refresh rate, no adaptive (consistent frame timing)
            local max_rate
            max_rate=$(get_available_refresh_rates | tail -1)
            set_refresh_rate "$max_rate"
            set_adaptive_refresh "0"
            set_color_mode "vivid"
            set_hbm "0"
            dlog "INFO" "Gaming display: ${max_rate}Hz fixed, vivid colors"
            ;;
        performance)
            local max_rate
            max_rate=$(get_available_refresh_rates | tail -1)
            set_refresh_rate "$max_rate"
            set_adaptive_refresh "1"
            set_color_mode "vivid"
            dlog "INFO" "Performance display: ${max_rate}Hz adaptive"
            ;;
        balanced)
            set_adaptive_refresh "1"
            set_color_mode "natural"
            set_hbm "0"
            dlog "INFO" "Balanced display: adaptive refresh"
            ;;
        battery)
            set_refresh_rate "60"
            set_adaptive_refresh "0"
            set_color_mode "natural"
            set_hbm "0"
            set_screen_timeout "30000"
            dlog "INFO" "Battery display: 60Hz fixed"
            ;;
        powersave)
            set_refresh_rate "60"
            set_adaptive_refresh "0"
            set_color_mode "natural"
            set_hbm "0"
            set_screen_timeout "15000"
            # Reduce brightness
            settings put system screen_brightness "50" 2>/dev/null
            dlog "INFO" "Powersave display: 60Hz, reduced brightness"
            ;;
    esac
}

# ─── Main ─────────────────────────────────────────────────────────────────────
case "$1" in
    rates)  get_available_refresh_rates ;;
    *)      apply_profile "${1:-balanced}" ;;
esac
