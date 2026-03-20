#!/system/bin/sh
# =============================================================================
# Hyperion Project - Installation Customization
# Made by ShadowBytePrjkt
# =============================================================================

MODID="hyperion_project"
MODPATH="/data/adb/modules/$MODID"
CONFIG_DIR="/data/adb/.config/hyperion"

# ─── Logging ──────────────────────────────────────────────────────────────────
hlog() {
    local level="$1"
    local msg="$2"
    echo "[$level] $msg"
}

# ─── Banner ──────────────────────────────────────────────────────────────────
print_banner() {
    echo ""
    echo "=============================================="
    echo "     HYPERION PROJECT v1.0.1"
    echo "     Universal Performance Module"
    echo "=============================================="
    echo ""
}

# ─── Device Detection ────────────────────────────────────────────────────────
detect_device() {
    DEVICE_MODEL=$(getprop ro.product.model 2>/dev/null | tr ' ' '_' || echo "Unknown")
    ANDROID_VERSION=$(getprop ro.build.version.release 2>/dev/null || echo "Unknown")
    CPU_CORES=$(nproc 2>/dev/null || echo "4")
    TOTAL_MEM=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{printf "%.0f", $2/1024/1024}' || echo "0")
    
    echo "Device: $DEVICE_MODEL | Android: $ANDROID_VERSION"
    echo "CPU: ${CPU_CORES} cores | RAM: ${TOTAL_MEM}GB"
    echo ""
}

# ─── Compile Daemon ────────────────────────────────────────────────────────
compile_daemon() {
    hlog "INFO" "Checking for pre-compiled binaries..."
    
    # Check if we already have pre-compiled binaries from CI
    if [ -f "$MODPATH/system/bin/hyperion" ] && [ -f "$MODPATH/system/bin/hyperiond" ]; then
        hlog "INFO" "Pre-compiled binaries found, skipping on-device compilation"
        chmod 755 "$MODPATH/system/bin/"* 2>/dev/null
        return 0
    fi
    
    # Check if we have the source
    if [ ! -f "$MODPATH/core/hyperion_daemon.c" ]; then
        hlog "WARN" "Daemon source not found, skipping"
        return 0
    fi
    
    # Create bin directory
    mkdir -p "$MODPATH/system/bin"
    
    # Try to compile (works on device with gcc/clang)
    if command -v gcc >/dev/null 2>&1; then
        cd "$MODPATH/core"
        gcc -O2 -Wall -Wextra -s -o "$MODPATH/system/bin/hyperion" hyperion_daemon.c 2>/dev/null
        if [ -f "$MODPATH/system/bin/hyperion" ]; then
            hlog "INFO" "Daemon compiled successfully"
            chmod 755 "$MODPATH/system/bin/hyperion"
        else
            hlog "WARN" "Daemon compilation failed"
        fi
    elif command -v clang >/dev/null 2>&1; then
        cd "$MODPATH/core"
        clang -O2 -Wall -Wextra -s -o "$MODPATH/system/bin/hyperion" hyperion_daemon.c 2>/dev/null
        if [ -f "$MODPATH/system/bin/hyperion" ]; then
            hlog "INFO" "Daemon compiled successfully"
            chmod 755 "$MODPATH/system/bin/hyperion"
        else
            hlog "WARN" "Daemon compilation failed"
        fi
    else
        hlog "WARN" "No compiler found (gcc/clang), using shell fallback"
    fi
}

# ─── Compatibility Checks ─────────────────────────────────────────────────────
check_compatibility() {
    hlog "INFO" "Checking compatibility..."
    
    # Check GPU
    if [ -d "/sys/class/kgsl/kgsl-3d0" ]; then
        hlog "INFO" "Adreno GPU detected"
    elif [ -d "/sys/class/devfreq" ]; then
        hlog "INFO" "Mali/other GPU detected"
    fi
    
    hlog "INFO" "Compatibility check complete"
}

# ─── Initialize Config ───────────────────────────────────────────────────────
init_config() {
    # Create config directory
    mkdir -p "$CONFIG_DIR"
    
    # Set default profile
    if [ ! -f "$CONFIG_DIR/current_profile" ]; then
        echo "balanced" > "$CONFIG_DIR/current_profile"
    fi
    
    # Set default AI state
    if [ ! -f "$CONFIG_DIR/ai_enabled" ]; then
        echo "true" > "$CONFIG_DIR/ai_enabled"
    fi
    
    hlog "INFO" "Config initialized"
}

# ─── Setup WebUI Symlink ─────────────────────────────────────────────────────
setup_webui() {
    MODULES_DIR="/data/adb/modules"
    if [ -d "$MODULES_DIR" ]; then
        # Create webroot symlink for WebUI apps
        if [ ! -L "$MODULES_DIR/$MODID/webroot" ] && [ -d "$MODPATH/webroot" ]; then
            ln -sf "$MODPATH/webroot" "$MODULES_DIR/$MODID/webroot" 2>/dev/null
            hlog "INFO" "WebUI symlink created"
        fi
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
print_banner
detect_device
compile_daemon
check_compatibility
init_config
setup_webui

echo "=============================================="
echo "Installation complete!"
echo "Open WebUI via action button"
echo "=============================================="
echo ""
