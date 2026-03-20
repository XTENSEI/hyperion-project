#!/system/bin/sh
# =============================================================================
# Hyperion Project - Display Color Control
# Made by ShadowBytePrjkt
# =============================================================================
# Control display saturation, contrast, hue, and refresh rate
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/display.log"

klog() {
    echo "[$(date -u +%H:%M:%S)][DISPLAY] $1" | tee -a "$LOG_FILE"
}

write() {
    [ -f "$1" ] && [ -w "$1" ] && echo "$2" > "$1" 2>/dev/null
}

# ─── Check Available Controls ────────────────────────────────────────────────
check_available() {
    local available=""
    
    # Check for color correction
    if [ -d "/sys/class/graphics/fb0" ]; then
        [ -f "/sys/class/graphics/fb0/msm_fb_panel_info" ] && available="${available}panel,"
        [ -f "/sys/class/graphics/fb0/dsi_display" ] && available="${available}dsi,"
    fi
    
    # Check for color settings
    [ -d "/sys/devices/virtual/graphics/fb0" ] && available="${available}graphics,"
    
    # Check for display color sysfs
    [ -d "/sys/class/display" ] && available="${available}display,"
    
    # Check for brightness
    [ -f "/sys/class/leds/lcd-backlight/brightness" ] && available="${available}brightness,"
    
    # Check for refresh rate
    if [ -f "/sys/class/graphics/fb0/modes" ]; then
        available="${available}refresh_rate,"
    fi
    
    echo "$available"
}

# ─── Set Saturation ──────────────────────────────────────────────────────────
set_saturation() {
    local value="$1"  # 0-200
    klog "Setting saturation to $value%"
    
    # Try various methods
    # Method 1: DSI display
    if [ -f "/sys/class/graphics/fb0/dsi_display" ]; then
        write /sys/class/graphics/fb0/dsi_display "saturation,$value"
    fi
    
    # Method 2: MSM display
    if [ -f "/sys/class/graphics/fb0/msm_fb_para" ]; then
        write /sys/class/graphics/fb0/msm_fb_para "sat,$value"
    fi
    
    # Method 3: Color adjustment via SurfaceFlinger
    # This would require a separate binary
    
    klog "Saturation set to $value"
}

# ─── Set Contrast ───────────────────────────────────────────────────────────
set_contrast() {
    local value="$1"  # 0-200
    klog "Setting contrast to $value%"
    
    if [ -f "/sys/class/graphics/fb0/dsi_display" ]; then
        write /sys/class/graphics/fb0/dsi_display "contrast,$value"
    fi
    
    if [ -f "/sys/class/graphics/fb0/msm_fb_para" ]; then
        write /sys/class/graphics/fb0/msm_fb_para "contrast,$value"
    fi
    
    klog "Contrast set to $value"
}

# ─── Set Hue ─────────────────────────────────────────────────────────────────
set_hue() {
    local value="$1"  # 0-360
    klog "Setting hue to $value°"
    
    if [ -f "/sys/class/graphics/fb0/dsi_display" ]; then
        write /sys/class/graphics/fb0/dsi_display "hue,$value"
    fi
    
    if [ -f "/sys/class/graphics/fb0/msm_fb_para" ]; then
        write /sys/class/graphics/fb0/msm_fb_para "hue,$value"
    fi
    
    klog "Hue set to $value"
}

# ─── Set Brightness ─────────────────────────────────────────────────────────
set_brightness() {
    local value="$1"  # 0-255
    klog "Setting brightness to $value"
    
    # Standard backlight
    write /sys/class/leds/lcd-backlight/brightness "$value"
    
    # Try secondary paths
    write /sys/class/backlight/panel-backlight/brightness "$value"
    write /sys/devices/soc/800000.qcom,mdss_mdp/800000.qcom,mdss_mdp:qcom,mdss_fb_primary/leds/lcd-backlight/brightness "$value"
    
    klog "Brightness set to $value"
}

# ─── Set Refresh Rate ────────────────────────────────────────────────────────
set_refresh_rate() {
    local rate="$1"  # 60, 90, 120, 144
    klog "Setting refresh rate to ${rate}Hz"
    
    # Check available modes
    if [ -f "/sys/class/graphics/fb0/modes" ]; then
        local current_modes
        current_modes=$(cat /sys/class/graphics/fb0/modes 2>/dev/null)
        
        # Try to find the requested mode
        local mode_found=""
        case "$rate" in
            60)  mode_found=$(echo "$current_modes" | grep -o "mode60" | head -1) ;;
            90)  mode_found=$(echo "$current_modes" | grep -o "mode90" | head -1) ;;
            120) mode_found=$(echo "$current_modes" | grep -o "mode120" | head -1) ;;
            144) mode_found=$(echo "$current_modes" | grep -o "mode144" | head -1) ;;
        esac
        
        if [ -n "$mode_found" ]; then
            write /sys/class/graphics/fb0/mode "$mode_found"
            klog "Refresh rate set to ${rate}Hz via mode"
        else
            # Try panel info
            if [ -f "/sys/class/graphics/fb0/msm_fb_panel_info" ]; then
                write /sys/class/graphics/fb0/msm_fb_panel_info "mipi_cmd_video,${rate}"
            fi
        fi
    fi
    
    # Try alternative paths for MIUI/other ROMs
    write /sys/class/drm/card0/card0-DSI-1/mode "120hz" 2>/dev/null
    write /sys/devices/virtual/graphics/fb0/panel/panel_name "120hz" 2>/dev/null
    
    klog "Refresh rate command sent for ${rate}Hz"
}

# ─── Apply Display Preset ───────────────────────────────────────────────────
apply_preset() {
    local preset="$1"
    klog "Applying display preset: $preset"
    
    case "$preset" in
        default)
            set_saturation 100
            set_contrast 100
            set_hue 0
            ;;
        vivid)
            set_saturation 140
            set_contrast 120
            set_hue 0
            ;;
        warm)
            set_saturation 90
            set_contrast 100
            set_hue 30
            ;;
        cool)
            set_saturation 100
            set_contrast 110
            set_hue -20
            ;;
        amoled)
            set_saturation 130
            set_contrast 140
            set_hue 0
            ;;
        reading)
            set_saturation 70
            set_contrast 130
            set_hue 0
            ;;
        *)
            klog "Unknown preset: $preset"
            ;;
    esac
    
    # Save current settings
    echo "$preset" > "$HYPERION_DIR/data/display_preset.txt" 2>/dev/null
}

# ─── Get Current Settings ───────────────────────────────────────────────────
get_settings() {
    python3 -c "
import json

settings = {
    'saturation': 100,
    'contrast': 100,
    'hue': 0,
    'refresh_rate': 120,
    'brightness': 128
}

# Try to read from saved config
try:
    with open('$HYPERION_DIR/data/display_preset.txt') as f:
        preset = f.read().strip()
        presets = {
            'default': {'saturation': 100, 'contrast': 100, 'hue': 0},
            'vivid': {'saturation': 140, 'contrast': 120, 'hue': 0},
            'warm': {'saturation': 90, 'contrast': 100, 'hue': 30},
            'cool': {'saturation': 100, 'contrast': 110, 'hue': -20},
            'amoled': {'saturation': 130, 'contrast': 140, 'hue': 0},
            'reading': {'saturation': 70, 'contrast': 130, 'hue': 0}
        }
        if preset in presets:
            settings.update(presets[preset])
except:
    pass

print(json.dumps(settings))
"
}

# ─── Main ────────────────────────────────────────────────────────────────────
case "$1" in
    saturation)  set_saturation "${2:-100}" ;;
    contrast)    set_contrast "${2:-100}" ;;
    hue)         set_hue "${2:-0}" ;;
    brightness)  set_brightness "${2:-128}" ;;
    refresh_rate) set_refresh_rate "${2:-120}" ;;
    preset)      apply_preset "${2:-default}" ;;
    settings)    get_settings ;;
    available)   check_available ;;
    *)           
        echo "Usage: $0 {saturation|contrast|hue|brightness|refresh_rate|preset|settings|available} [value]"
        ;;
esac
