#!/system/bin/sh
# =============================================================================
# Hyperion Project - Foreground App Detector
# Made by ShadowBytePrjkt
# =============================================================================
# Detects the currently running foreground app via dumpsys activity
# Outputs: package_name or empty string
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LAST_APP_FILE="$HYPERION_DIR/data/last_foreground_app"
APP_PROFILES_FILE="$HYPERION_DIR/app_profiles.json"

# ─── Get Foreground App ───────────────────────────────────────────────────────
get_foreground_app() {
    local pkg=""

    # Method 1: dumpsys activity activities (most reliable)
    pkg=$(dumpsys activity activities 2>/dev/null | \
        grep -E "mResumedActivity|mCurrentFocus" | \
        grep -oP '[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+' | \
        grep -v "android\|com\.android\." | \
        head -1)

    # Method 2: dumpsys window (fallback)
    if [ -z "$pkg" ]; then
        pkg=$(dumpsys window windows 2>/dev/null | \
            grep -E "mCurrentFocus|mFocusedApp" | \
            grep -oP '[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+' | \
            grep -v "^android$\|^com\.android\." | \
            head -1)
    fi

    # Method 3: dumpsys activity top (Android 10+)
    if [ -z "$pkg" ]; then
        pkg=$(dumpsys activity top 2>/dev/null | \
            grep "ACTIVITY" | \
            grep -oP '[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+' | \
            head -1)
    fi

    echo "$pkg"
}

# ─── Check if App is a Game ───────────────────────────────────────────────────
is_game() {
    local pkg="$1"

    # Check app_profiles.json for gaming override
    if [ -f "$APP_PROFILES_FILE" ]; then
        if grep -q "\"$pkg\".*\"gaming\"" "$APP_PROFILES_FILE" 2>/dev/null; then
            return 0
        fi
    fi

    # Check Android game category
    local category
    category=$(dumpsys package "$pkg" 2>/dev/null | grep "category" | head -1)
    if echo "$category" | grep -qi "game"; then
        return 0
    fi

    # Check known game package patterns
    for pattern in \
        "com.miHoYo" \
        "com.pubg" \
        "com.tencent.ig" \
        "com.activision" \
        "com.ea." \
        "com.gameloft" \
        "com.supercell" \
        "com.king." \
        "com.rovio" \
        "com.mojang" \
        "com.roblox" \
        "com.epicgames" \
        "com.square_enix" \
        "com.bandainamco" \
        "com.netease" \
        "com.garena" \
        "com.levelinfinite" \
        "com.krafton"; do
        if echo "$pkg" | grep -q "$pattern"; then
            return 0
        fi
    done

    return 1
}

# ─── Get Profile for App ──────────────────────────────────────────────────────
get_app_profile() {
    local pkg="$1"

    # Check explicit overrides in app_profiles.json
    if [ -f "$APP_PROFILES_FILE" ]; then
        local profile
        profile=$(python3 -c "
import json, sys
try:
    with open('$APP_PROFILES_FILE') as f:
        data = json.load(f)
    overrides = data.get('overrides', {})
    learned = data.get('learned', {})
    pkg = '$pkg'
    if pkg in overrides:
        print(overrides[pkg])
    elif pkg in learned:
        print(learned[pkg])
except:
    pass
" 2>/dev/null)
        if [ -n "$profile" ]; then
            echo "$profile"
            return
        fi
    fi

    # Check if it's a game
    if is_game "$pkg"; then
        echo "gaming"
        return
    fi

    # Default: no override
    echo ""
}

# ─── Monitor Mode ─────────────────────────────────────────────────────────────
monitor() {
    local interval="${1:-2}"
    local last_pkg=""

    while true; do
        local pkg
        pkg=$(get_foreground_app)

        if [ "$pkg" != "$last_pkg" ] && [ -n "$pkg" ]; then
            last_pkg="$pkg"
            echo "$pkg" > "$LAST_APP_FILE"

            local profile
            profile=$(get_app_profile "$pkg")

            # Output JSON event
            echo "{\"type\":\"app_change\",\"package\":\"$pkg\",\"suggested_profile\":\"$profile\",\"ts\":$(date +%s)}"

            # Write to AI command pipe if profile override exists
            if [ -n "$profile" ]; then
                local pipe="$HYPERION_DIR/data/commands.pipe"
                if [ -p "$pipe" ]; then
                    echo "{\"type\":\"app_profile_override\",\"data\":{\"package\":\"$pkg\",\"profile\":\"$profile\"}}" > "$pipe" 2>/dev/null
                fi
            fi
        fi

        sleep "$interval"
    done
}

# ─── Main ─────────────────────────────────────────────────────────────────────
case "$1" in
    monitor)    monitor "${2:-2}" ;;
    profile)    get_app_profile "${2:-}" ;;
    game)       is_game "${2:-}" && echo "yes" || echo "no" ;;
    *)          get_foreground_app ;;
esac
