#!/system/bin/sh
# =============================================================================
# Hyperion Project - Bypass Charging Control
# Made by ShadowBytePrjkt
# =============================================================================
# Auto-detect if device supports bypass charging and control it
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/bypass.log"

klog() {
    echo "[$(date -u +%H:%M:%S)][BYPASS] $1" | tee -a "$LOG_FILE"
}

# ─── Check Bypass Support ────────────────────────────────────────────────────
check_bypass_support() {
    # Try various methods to detect bypass charging support
    
    # Method 1: Check for USB PD
    local pd_path="/sys/class/power_supply/usb/pd_supported"
    if [ -f "$pd_path" ]; then
        if [ "$(cat "$pd_path" 2>/dev/null)" = "1" ]; then
            echo "pd"
            return
        fi
    fi
    
    # Method 2: Check for pump_express
    local pe_path="/sys/class/power_supply/battery/pump_express"
    if [ -f "$pe_path" ]; then
        echo "pe"
        return
    fi
    
    # Method 3: Check for wireless reverse charging
    local wr_path="/sys/class/power_supply/battery/reverse_charge"
    if [ -f "$wr_path" ]; then
        echo "wireless"
        return
    fi
    
    # Method 4: Check for bypass in battery stats
    if dumpsys battery | grep -q "USB Power Source"; then
        echo "usb_passthrough"
        return
    fi
    
    # Not supported
    echo "none"
}

# ─── Enable Bypass Charging ───────────────────────────────────────────────────
enable_bypass() {
    local method="$1"
    klog "Enabling bypass charging (method: $method)"
    
    case "$method" in
        pd)
            # USB Power Delivery bypass
            write /sys/class/power_supply/usb/pd_active 1
            write /sys/class/power_supply/usb/present 1
            ;;
        pe)
            # MediaTek Pump Express
            write /sys/class/power_supply/battery/pump_express 1
            ;;
        wireless)
            # Wireless reverse charging
            write /sys/class/power_supply/battery/reverse_charge 1
            ;;
        *)
            klog "Bypass not supported on this device"
            return 1
            ;;
    esac
    
    klog "Bypass charging enabled"
}

# ─── Disable Bypass Charging ─────────────────────────────────────────────────
disable_bypass() {
    local method="$1"
    klog "Disabling bypass charging (method: $method)"
    
    case "$method" in
        pd)
            write /sys/class/power_supply/usb/pd_active 0
            ;;
        pe)
            write /sys/class/power_supply/battery/pump_express 0
            ;;
        wireless)
            write /sys/class/power_supply/battery/reverse_charge 0
            ;;
    esac
    
    klog "Bypass charging disabled"
}

# ─── Get Bypass Status ───────────────────────────────────────────────────────
get_bypass_status() {
    local method="$1"
    
    case "$method" in
        pd)
            cat /sys/class/power_supply/usb/pd_active 2>/dev/null || echo "0"
            ;;
        pe)
            cat /sys/class/power_supply/battery/pump_express 2>/dev/null || echo "0"
            ;;
        wireless)
            cat /sys/class/power_supply/battery/reverse_charge 2>/dev/null || echo "0"
            ;;
        *)
            echo "unsupported"
            ;;
    esac
}

# ─── Main ────────────────────────────────────────────────────────────────────
case "$1" in
    support)
        check_bypass_support
        ;;
    enable)
        method=$(check_bypass_support)
        if [ "$method" != "none" ]; then
            enable_bypass "$method"
            echo "success:$method"
        else
            echo "not_supported"
        fi
        ;;
    disable)
        method=$(check_bypass_support)
        disable_bypass "$method"
        echo "disabled"
        ;;
    status)
        method=$(check_bypass_support)
        if [ "$method" != "none" ]; then
            status=$(get_bypass_status "$method")
            echo "{\"method\":\"$method\",\"enabled\":$status}"
        else
            echo "{\"method\":\"none\",\"enabled\":false}"
        fi
        ;;
    *)
        echo "Usage: $0 {support|enable|disable|status}"
        ;;
esac
