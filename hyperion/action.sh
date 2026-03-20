#!/system/bin/sh
# =============================================================================
# Hyperion Project - Action Handler
# Made by ShadowBytePrjkt
# =============================================================================

MODID="hyperion_project"
MODPATH="/data/adb/modules/$MODID"
CONFIG_DIR="/data/adb/.config/hyperion"

# Open WebUI - uses KSU WebUI apps
open_webui() {
    # Method 1: MMRL WebUI X (most common)
    if pm path com.dergoogler.mmrl.wx >/dev/null 2>&1; then
        am start -n "com.dergoogler.mmrl.wx/.ui.activity.webui.WebUIActivity" -e id "$MODID" > /dev/null 2>&1
        exit 0
    fi
    
    # Method 2: MMRL
    if pm path com.dergoogler.mmrl >/dev/null 2>&1; then
        am start -n "com.dergoogler.mmrl/.ui.activity.webui.WebUIActivity" -e MOD_ID "$MODID" > /dev/null 2>&1
        exit 0
    fi
    
    # Method 3: KSU WebUI Standalone
    if pm path io.github.a13e300.ksuwebui >/dev/null 2>&1; then
        am start -n "io.github.a13e300.ksuwebui/.WebUIActivity" -e id "$MODID" > /dev/null 2>&1
        exit 0
    fi
    
    # Method 4: KernelSU built-in (try direct)
    if pm path com.ksun.manager >/dev/null 2>&1; then
        am start -n "com.ksun.manager/.ui.WebUIActivity" -e id "$MODID" > /dev/null 2>&1
        exit 0
    fi
    
    # If nothing found, show message
    echo "[!] WebUI app not found"
    echo "[!] Please install MMRL WebUI X from PlayStore"
    am start -a android.intent.action.VIEW -d "https://play.google.com/store/apps/details?id=com.dergoogler.mmrl.wx" > /dev/null 2>&1
}

# Toggle AI
toggle_ai() {
    if [ -f "$CONFIG_DIR/ai_enabled" ]; then
        current=$(cat "$CONFIG_DIR/ai_enabled")
        if [ "$current" = "true" ]; then
            echo "false" > "$CONFIG_DIR/ai_enabled"
            echo "AI disabled"
        else
            echo "true" > "$CONFIG_DIR/ai_enabled"
            echo "AI enabled"
        fi
    else
        echo "true" > "$CONFIG_DIR/ai_enabled"
        echo "AI enabled"
    fi
}

# Apply gaming profile
gaming_mode() {
    sh "$MODPATH/scripts/profile_manager.sh" apply gaming 2>/dev/null
    echo "Gaming mode enabled"
}

# Toggle preload (SAC-style)
toggle_preload() {
    local data_dir="$CONFIG_DIR"
    mkdir -p "$data_dir"
    
    if [ -f "$data_dir/preload_enabled" ]; then
        current=$(cat "$data_dir/preload_enabled")
        if [ "$current" = "true" ]; then
            echo "false" > "$data_dir/preload_enabled"
            echo "Preload disabled"
        else
            echo "true" > "$data_dir/preload_enabled"
            echo "Preload enabled"
        fi
    else
        echo "true" > "$data_dir/preload_enabled"
        echo "Preload enabled"
    fi
}

# Start services
start_services() {
    sh "$MODPATH/service.sh" start
    echo "Services started"
}

# Stop services
stop_services() {
    sh "$MODPATH/service.sh" stop
    echo "Services stopped"
}

# Main handler
case "$1" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    webui|ui|launch)
        open_webui
        ;;
    toggle)
        toggle_ai
        ;;
    gaming)
        gaming_mode
        ;;
    preload)
        toggle_preload
        ;;
    *)
        open_webui
        ;;
esac
