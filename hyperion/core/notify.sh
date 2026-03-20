#!/system/bin/sh
# =============================================================================
# Hyperion Project - Android Notification System (SAC-style)
# Made by ShadowBytePrjkt
# =============================================================================
# Uses cmd notification post - the most reliable Android notification method
# Inspired by SAC module notification implementation
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
CONFIG_DIR="/data/adb/.config/hyperion"
NOTIFY_ENABLED_FILE="$HYPERION_DIR/data/notify_enabled"

# ─── Alias cmd for performance ───────────────────────────────────────────────
alias cmd='/system/bin/nice -n 19 /system/bin/cmd'

# ─── Check if notifications are enabled ──────────────────────────────────────
is_notify_enabled() {
    # Check config file first
    if [ -f "$CONFIG_DIR/config.json" ]; then
        enabled=$(grep -o '"enabled":[ ]*true' "$CONFIG_DIR/config.json" 2>/dev/null)
        [ -z "$enabled" ] && return 1
    fi
    [ -f "$NOTIFY_ENABLED_FILE" ] && [ "$(cat $NOTIFY_ENABLED_FILE)" = "1" ]
}

# ─── Profile Icons ────────────────────────────────────────────────────────────
get_profile_icon() {
    case "$1" in
        gaming)      echo "🎮" ;;
        performance) echo "⚡" ;;
        balanced)    echo "⚖️" ;;
        battery)     echo "🔋" ;;
        powersave)   echo "🌙" ;;
        custom)      echo "🔧" ;;
        *)           echo "🚀" ;;
    esac
}

get_profile_color() {
    case "$1" in
        gaming)      echo "0xFFFF4444" ;;
        performance) echo "0xFFFF8800" ;;
        balanced)    echo "0xFF00D4FF" ;;
        battery)     echo "0xFF44FF88" ;;
        powersave)   echo "0xFF8844FF" ;;
        custom)      echo "0xFFFFDD00" ;;
        *)           echo "0xFF00D4FF" ;;
    esac
}

# ─── Toast Notification (SAC-style using cmd notification post) ──────────────
send_toast() {
    local message="$1"
    local duration="${2:-short}"
    
    # Primary: cmd notification post (most reliable - like SAC)
    cmd notification post -t "$message" hyperion >/dev/null 2>&1
    
    # Fallback: su context notification (for when running as root)
    su -lp 2000 -c "cmd notification post -t '$message' hyperion" >/dev/null 2>&1
    
    # Fallback: am broadcast (older ROMs)
    am broadcast -a android.intent.action.SHOW_TOAST --es message "$message" 2>/dev/null
}

# ─── Status Bar Notification (SAC-style) ─────────────────────────────────────
send_notification() {
    local title="$1"
    local message="$2"
    local icon="${3:-}"
    local priority="${4:-0}"

    # Primary: cmd notification post (like SAC)
    cmd notification post -t "$title" -e "$message" hyperion >/dev/null 2>&1
    
    # Fallback: su context notification
    su -lp 2000 -c "cmd notification post -t '$title' -e '$message' hyperion" >/dev/null 2>&1
    
    # Fallback: Termux notification
    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification --title "$title" --content "$message" 2>/dev/null
    fi
}

# ─── Profile Change Notification ─────────────────────────────────────────────
notify_profile_change() {
    local from_profile="$1"
    local to_profile="$2"
    local reason="${3:-}"

    local icon
    icon=$(get_profile_icon "$to_profile")

    local title="Hyperion: Profile Changed"
    local message="${icon} Switched to $(echo $to_profile | sed 's/./\u&/') mode"

    if [ -n "$reason" ]; then
        message="$message (${reason})"
    fi

    # Send toast (brief notification)
    send_toast "$message" "short"

    # Send status bar notification
    send_notification "$title" "$message" "ic_settings" "0"

    # Log the notification
    echo "$(date -u +%H:%M:%S) [NOTIFY] Profile: $from_profile → $to_profile ($reason)" \
        >> "$HYPERION_DIR/logs/notifications.log"
}

# ─── AI Decision Notification ─────────────────────────────────────────────────
notify_ai_decision() {
    local profile="$1"
    local confidence="$2"
    local reason="$3"

    local icon
    icon=$(get_profile_icon "$profile")
    local message="${icon} AI: ${profile} (${confidence}% confidence)"

    send_toast "$message" "short"
}

# ─── Thermal Warning ──────────────────────────────────────────────────────────
notify_thermal_warning() {
    local temp="$1"
    local action="$2"

    local message="🌡️ High temperature: ${temp}°C - ${action}"
    send_toast "$message" "long"
    send_notification "Hyperion: Thermal Warning" "$message" "ic_warning" "1"
}

# ─── Battery Warning ──────────────────────────────────────────────────────────
notify_battery_warning() {
    local level="$1"

    local message="🔋 Battery critical: ${level}% - Switching to Powersave"
    send_toast "$message" "long"
    send_notification "Hyperion: Battery Warning" "$message" "ic_battery_alert" "2"
}

# ─── Module Status ────────────────────────────────────────────────────────────
notify_module_status() {
    local status="$1"  # started, stopped, error

    case "$status" in
        started)
            send_toast "🚀 Hyperion Project activated" "short"
            ;;
        stopped)
            send_toast "⏹️ Hyperion Project deactivated" "short"
            ;;
        error)
            send_notification "Hyperion: Error" "Module encountered an error. Check logs." "ic_error" "2"
            ;;
    esac
}

# ─── Preload Notifications (SAC-style) ─────────────────────────────────────────
# Shows notifications when game booster preloads apps
notify_preload_start() {
    local app_name="$1"
    
    # Like SAC: cmd notification post -t Preloading -i "$img" -I "$img" apl $top_app
    cmd notification post -t "⚡ Preloading $app_name" hyperion >/dev/null 2>&1
    su -lp 2000 -c "cmd notification post -t '⚡ Preloading $app_name' hyperion" >/dev/null 2>&1
}

notify_preload_done() {
    local app_name="$1"
    
    # Like SAC: cmd notification post -t Preloaded -i "$img" -I "$img" apl $top_app
    cmd notification post -t "✅ Preloaded $app_name" hyperion >/dev/null 2>&1
    su -lp 2000 -c "cmd notification post -t '✅ Preloaded $app_name' hyperion" >/dev/null 2>&1
}

# ─── Game Booster Status ─────────────────────────────────────────────────────
notify_game_booster() {
    local status="$1"  # enabled, disabled, game_detected
    local game_name="$2"

    case "$status" in
        enabled)
            send_toast "🎮 Game Booster activated" "short"
            cmd notification post -t "🎮 Game Booster ON" hyperion >/dev/null 2>&1
            ;;
        disabled)
            send_toast "⚖️ Game Booster deactivated" "short"
            cmd notification post -t "⚖️ Game Booster OFF" hyperion >/dev/null 2>&1
            ;;
        game_detected)
            send_toast "🎮 Detected: $game_name" "short"
            cmd notification post -t "🎮 Game Mode: $game_name" hyperion >/dev/null 2>&1
            ;;
    esac
}

# ─── Main ─────────────────────────────────────────────────────────────────────
case "$1" in
    profile)
        notify_profile_change "$2" "$3" "$4"
        ;;
    ai)
        notify_ai_decision "$2" "$3" "$4"
        ;;
    thermal)
        notify_thermal_warning "$2" "$3"
        ;;
    battery)
        notify_battery_warning "$2"
        ;;
    status)
        notify_module_status "$2"
        ;;
    toast)
        send_toast "$2" "${3:-short}"
        ;;
    preload)
        # Usage: notify.sh preload start|done <app_name>
        case "$2" in
            start)
                notify_preload_start "$3"
                ;;
            done)
                notify_preload_done "$3"
                ;;
        esac
        ;;
    game)
        # Usage: notify.sh game enabled|disabled|game_detected <game_name>
        notify_game_booster "$2" "$3"
        ;;
    *)
        echo "Usage: notify.sh <profile|ai|thermal|battery|status|toast|preload|game> [args...]"
        echo "  profile <from> <to> [reason]"
        echo "  ai <profile> <confidence> <reason>"
        echo "  thermal <temp> <action>"
        echo "  battery <level>"
        echo "  status <started|stopped|error>"
        echo "  toast <message> [short|long]"
        echo "  preload start|done <app_name>"
        echo "  game enabled|disabled|game_detected <game_name>"
        ;;
esac
