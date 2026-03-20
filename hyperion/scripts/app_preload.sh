#!/system/bin/sh
# =============================================================================
# Hyperion Project - App Preload Technology
# Made by ShadowBytePrjkt
# =============================================================================
# Pre-load frequently used apps into memory for faster launch
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
PRELOAD_DIR="$HYPERION_DIR/data/preload"
PRELOAD_LIST="$PRELOAD_DIR/apps.txt"
PRELOAD_ENABLED="$PRELOAD_DIR/enabled"
LOG_FILE="$HYPERION_DIR/logs/preload.log"

klog() {
    echo "[$(date -u +%H:%M:%S)][PRELOAD] $1" | tee -a "$LOG_FILE"
}

# ─── Initialize ────────────────────────────────────────────────────────────────
init_preload() {
    mkdir -p "$PRELOAD_DIR"
    [ -f "$PRELOAD_LIST" ] || touch "$PRELOAD_LIST"
}

# ─── Get Frequently Used Apps ───────────────────────────────────────────────
get_frequent_apps() {
    local limit="${1:-5}"
    
    # Get usage stats from usage_stats
    local usage_file="/data/system/usagestats/0/latest"
    if [ -d "/data/system/usagestats" ]; then
        # Get top used apps from usage stats
        local apps
        apps=$(dumpsys usagestats 2>/dev/null | grep -E "^  [a-z]" | head -"$limit" | awk '{print $1}')
        
        if [ -n "$apps" ]; then
            echo "$apps"
            return
        fi
    fi
    
    # Fallback: common apps
    echo "com.android.systemui\ncom.android.launcher"
}

# ─── AI-Based Prediction ──────────────────────────────────────────────────────
ai_predict_apps() {
    local limit="${1:-5}"
    
    # Check time of day
    local hour
    hour=$(date +%H)
    
    # Check day of week
    local day
    day=$(date +%u)
    
    # Read learned patterns
    local patterns_file="$HYPERION_DIR/data/usage_patterns.json"
    
    if [ -f "$patterns_file" ]; then
        # Python-based prediction using learned patterns
        python3 -c "
import json
import datetime

try:
    with open('$patterns_file') as f:
        patterns = json.load(f)
    
    now = datetime.datetime.now()
    hour = now.hour
    day = now.weekday()
    
    scores = {}
    for app, data in patterns.items():
        score = 0
        # Time pattern
        if str(hour) in data.get('hours', []):
            score += 30
        # Day pattern
        if str(day) in data.get('days', []):
            score += 20
        # Frequency
        score += data.get('count', 0) * 5
        scores[app] = score
    
    sorted_apps = sorted(scores.items(), key=lambda x: x[1], reverse=True)
    for app, _ in sorted_apps[:$limit]:
        print(app)
except:
    pass
"
    else
        get_frequent_apps "$limit"
    fi
}

# ─── Preload Apps ────────────────────────────────────────────────────────────
preload_apps() {
    local method="$1"
    local count="${2:-5}"
    
    [ -f "$PRELOAD_ENABLED" ] && [ "$(cat "$PRELOAD_ENABLED")" = "0" ] && return
    
    klog "Preloading apps (method: $method, count: $count)"
    
    local apps=""
    case "$method" in
        frequency)
            apps=$(get_frequent_apps "$count")
            ;;
        recent)
            apps=$(dumpsys recents 2>/dev/null | grep -oE "[a-zA-Z0-9_]+\.[a-zA-Z0-9_]+" | sort -u | head -"$count")
            ;;
        ai|smart)
            apps=$(ai_predict_apps "$count")
            ;;
        *)
            apps=$(ai_predict_apps "$count")
            ;;
    esac
    
    # Preload each app using app launch
    echo "$apps" | while read app; do
        [ -z "$app" ] && continue
        
        # Try to start the app briefly (it will be cached)
        # This is a light preload - just touching the app
        if [ -n "$app" ]; then
            # Use am start with stop to just prepare
            am start -W --user 0 -n "$app/." 2>/dev/null &
        fi
    done
    
    # Save preload list
    echo "$apps" > "$PRELOAD_LIST"
    
    klog "Preload complete: $apps"
}

# ─── Enable/Disable Preload ──────────────────────────────────────────────────
set_preload() {
    local enabled="$1"
    
    if [ "$enabled" = "true" ] || [ "$enabled" = "1" ]; then
        echo "1" > "$PRELOAD_ENABLED"
        klog "App preload enabled"
    else
        echo "0" > "$PRELOAD_ENABLED"
        klog "App preload disabled"
    fi
}

# ─── Get Preload Status ──────────────────────────────────────────────────────
get_status() {
    local enabled="false"
    [ -f "$PRELOAD_ENABLED" ] && [ "$(cat "$PRELOAD_ENABLED")" = "1" ] && enabled="true"
    
    local apps=""
    [ -f "$PRELOAD_LIST" ] && apps=$(cat "$PRELOAD_LIST")
    
    python3 -c "
import json
print(json.dumps({
    'enabled': $enabled,
    'apps': \"$apps\".strip().split('\n') if \"$apps\" else []
}))
"
}

# ─── Add App to Preload List ─────────────────────────────────────────────────
add_app() {
    local package="$1"
    
    if [ -n "$package" ]; then
        if ! grep -q "^$package$" "$PRELOAD_LIST" 2>/dev/null; then
            echo "$package" >> "$PRELOAD_LIST"
            klog "Added $package to preload list"
        fi
    fi
}

# ─── Remove App from Preload List ────────────────────────────────────────────
remove_app() {
    local package="$1"
    
    if [ -n "$package" ]; then
        sed -i "/^$package$/d" "$PRELOAD_LIST"
        klog "Removed $package from preload list"
    fi
}

# ─── Watch Foreground App and Preload ───────────────────────────────────────
watch_and_preload() {
    local last_app=""
    local count="${1:-5}"
    local method="${2:-ai}"
    
    while true; do
        # Get current foreground app
        local current_app
        current_app=$(dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp" | head -1 | awk -F'/' '{print $1}' | awk '{print $NF}')
        
        if [ -n "$current_app" ] && [ "$current_app" != "$last_app" ]; then
            # App changed, preload next likely apps
            preload_apps "$method" "$count"
            last_app="$current_app"
        fi
        
        sleep 30
    done
}

# ─── Main ────────────────────────────────────────────────────────────────────
init_preload

case "$1" in
    start)
        preload_apps "${2:-ai}" "${3:-5}"
        ;;
    watch)
        watch_and_preload "${2:-5}" "${3:-ai}"
        ;;
    enable)
        set_preload "${2:-true}"
        ;;
    disable)
        set_preload "false"
        ;;
    status)
        get_status
        ;;
    add)
        add_app "$2"
        ;;
    remove)
        remove_app "$2"
        ;;
    list)
        cat "$PRELOAD_LIST" 2>/dev/null || echo "No apps in preload list"
        ;;
    predict)
        ai_predict_apps "${2:-5}"
        ;;
    *)
        echo "Usage: $0 {start|watch|enable|disable|status|add|remove|list|predict}"
        ;;
esac
