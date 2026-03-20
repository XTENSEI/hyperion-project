#!/system/bin/sh
# =============================================================================
# Hyperion Project - Profile Manager
# Made by ShadowBytePrjkt
# =============================================================================
# Main profile application script - applies all tuning scripts for a profile
# Also triggers notification on profile change
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
SCRIPTS_DIR="$HYPERION_DIR/scripts"
PROFILES_DIR="$HYPERION_DIR/profiles"
NOTIFY_SCRIPT="$HYPERION_DIR/core/notify.sh"

# ─── Logging ──────────────────────────────────────────────────────────────────
plog() {
    local level="$1"; local msg="$2"
    local ts; ts=$(date -u +%H:%M:%S)
    echo "[$ts][PROFILE][$level] $msg" | tee -a "$HYPERION_DIR/logs/profile_manager.log"
}

# ─── Get Profile from JSON ───────────────────────────────────────────────────
get_json_value() {
    local profile="$1"
    local key="$2"
    python3 -c "
import json
try:
    with open('$PROFILES_DIR/${profile}.json') as f:
        data = json.load(f)
    keys = '$key'.split('.')
    val = data
    for k in keys:
        val = val.get(k, {})
    print(val)
except Exception as e:
    print('')
" 2>/dev/null
}

# ─── Apply CPU Settings ──────────────────────────────────────────────────────
apply_cpu() {
    local profile="$1"
    plog "INFO" "Applying CPU settings for $profile..."

    local governor min_freq max_freq
    governor=$(get_json_value "$profile" "cpu.governor")
    min_freq=$(get_json_value "$profile" "cpu.min_freq")
    max_freq=$(get_json_value "$profile" "cpu.max_freq")

    "$SCRIPTS_DIR/cpu.sh" "$profile" 2>&1 | while read line; do
        plog "DEBUG" "CPU: $line"
    done
}

# ─── Apply GPU Settings ──────────────────────────────────────────────────────
apply_gpu() {
    local profile="$1"
    plog "INFO" "Applying GPU settings for $profile..."

    "$SCRIPTS_DIR/gpu.sh" "$profile" 2>&1 | while read line; do
        plog "DEBUG" "GPU: $line"
    done
}

# ─── Apply Memory Settings ──────────────────────────────────────────────────
apply_memory() {
    local profile="$1"
    plog "INFO" "Applying memory settings for $profile..."

    "$SCRIPTS_DIR/memory.sh" "$profile" 2>&1 | while read line; do
        plog "DEBUG" "Memory: $line"
    done
}

# ─── Apply Thermal Settings ──────────────────────────────────────────────────
apply_thermal() {
    local profile="$1"
    plog "INFO" "Applying thermal settings for $profile..."

    "$SCRIPTS_DIR/thermal.sh" "$profile" 2>&1 | while read line; do
        plog "DEBUG" "Thermal: $line"
    done
}

# ─── Apply Network Settings ──────────────────────────────────────────────────
apply_network() {
    local profile="$1"
    plog "INFO" "Applying network settings for $profile..."

    "$SCRIPTS_DIR/network.sh" "$profile" 2>&1 | while read line; do
        plog "DEBUG" "Network: $line"
    done
}

# ─── Apply I/O Settings ─────────────────────────────────────────────────────
apply_io() {
    local profile="$1"
    plog "INFO" "Applying I/O settings for $profile..."

    "$SCRIPTS_DIR/io.sh" "$profile" 2>&1 | while read line; do
        plog "DEBUG" "IO: $line"
    done
}

# ─── Apply VM Settings ──────────────────────────────────────────────────────
apply_vm() {
    local profile="$1"
    plog "INFO" "Applying VM settings for $profile..."

    "$SCRIPTS_DIR/vm.sh" "$profile" 2>&1 | while read line; do
        plog "DEBUG" "VM: $line"
    done
}

# ─── Apply Battery Settings ──────────────────────────────────────────────────
apply_battery() {
    local profile="$1"
    plog "INFO" "Applying battery settings for $profile..."

    "$SCRIPTS_DIR/battery.sh" "$profile" 2>&1 | while read line; do
        plog "DEBUG" "Battery: $line"
    done
}

# ─── Apply Display Settings ─────────────────────────────────────────────────
apply_display() {
    local profile="$1"
    plog "INFO" "Applying display settings for $profile..."

    "$SCRIPTS_DIR/display.sh" "$profile" 2>&1 | while read line; do
        plog "DEBUG" "Display: $line"
    done
}

# ─── Apply Doze Settings ────────────────────────────────────────────────────
apply_doze() {
    local profile="$1"
    plog "INFO" "Applying doze settings for $profile..."

    "$SCRIPTS_DIR/doze.sh" "$profile" 2>&1 | while read line; do
        plog "DEBUG" "Doze: $line"
    done
}

# ─── Main Profile Apply ─────────────────────────────────────────────────────
apply_profile() {
    local profile="$1"
    local old_profile=""

    # Validate profile
    case "$profile" in
        gaming|performance|balanced|battery|powersave|custom);;
        *) plog "ERROR" "Invalid profile: $profile"; return 1 ;;
    esac

    # Get old profile
    if [ -f "$HYPERION_DIR/current_profile" ]; then
        old_profile=$(cat "$HYPERION_DIR/current_profile")
    fi

    plog "INFO" "========================================"
    plog "INFO" "Applying profile: $profile (was: $old_profile)"
    plog "INFO" "========================================"

    # Record session start for learning
    if [ -f "$HYPERION_DIR/core/learning_engine.py" ]; then
        python3 "$HYPERION_DIR/core/learning_engine.py" record "$profile" "manual" 2>/dev/null &
    fi

    # Apply all subsystems in parallel for speed
    apply_cpu "$profile" &
    apply_gpu "$profile" &
    apply_memory "$profile" &
    apply_thermal "$profile" &
    apply_network "$profile" &
    apply_io "$profile" &
    apply_vm "$profile" &
    apply_battery "$profile" &
    apply_display "$profile" &
    apply_doze "$profile" &

    # Wait for all to complete
    wait

    # Save current profile
    echo "$profile" > "$HYPERION_DIR/current_profile"

    plog "INFO" "Profile '$profile' applied successfully!"

    # Send notification
    if [ -x "$NOTIFY_SCRIPT" ]; then
        "$NOTIFY_SCRIPT" profile "$old_profile" "$profile" "manual" 2>/dev/null
    fi

    return 0
}

# ─── Main ─────────────────────────────────────────────────────────────────────
PROFILE="${1:-balanced}"
apply_profile "$PROFILE"
