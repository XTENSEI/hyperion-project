#!/system/bin/sh
# =============================================================================
# Hyperion Project - GPU Optimization Script
# Made by ShadowBytePrjkt
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/gpu.log"

# ─── Logging ──────────────────────────────────────────────────────────────────
glog() {
    local level="$1"
    local msg="$2"
    local ts
    ts=$(date -u +%H:%M:%S)
    echo "[$ts][GPU][$level] $msg" >> "$LOG_FILE"
    echo "[$ts][GPU][$level] $msg"
}

# ─── Write to sysfs safely ────────────────────────────────────────────────────
write() {
    local path="$1"
    local value="$2"
    if [ -f "$path" ] && [ -w "$path" ]; then
        echo "$value" > "$path" 2>/dev/null && \
            glog "DEBUG" "write $path = $value" || \
            glog "WARN" "failed write $path = $value"
    fi
}

# ─── Detect GPU Type ──────────────────────────────────────────────────────────
detect_gpu() {
    if [ -d "/sys/class/kgsl/kgsl-3d0" ]; then
        echo "adreno"
    elif [ -d "/sys/devices/platform/mali.0" ] || [ -d "/sys/class/misc/mali0" ]; then
        echo "mali"
    elif [ -d "/sys/class/devfreq" ]; then
        # Check devfreq for GPU
        for dev in /sys/class/devfreq/*/; do
            if echo "$dev" | grep -qi "gpu\|kgsl\|mali\|pvr"; then
                echo "devfreq:$dev"
                return
            fi
        done
        echo "devfreq"
    else
        echo "unknown"
    fi
}

# ─── Adreno GPU Tuning ────────────────────────────────────────────────────────
tune_adreno() {
    local profile="$1"
    local KGSL="/sys/class/kgsl/kgsl-3d0"

    glog "INFO" "Tuning Adreno GPU: $profile"

    # Get available frequencies
    local avail_freqs
    avail_freqs=$(cat "$KGSL/gpu_available_frequencies" 2>/dev/null | tr ' ' '\n' | sort -n)
    local min_freq max_freq
    min_freq=$(echo "$avail_freqs" | head -1)
    max_freq=$(echo "$avail_freqs" | tail -1)

    case "$profile" in
        gaming|performance)
            # Maximum GPU performance
            write "$KGSL/devfreq/governor" "performance"
            write "$KGSL/min_pwrlevel" "0"
            write "$KGSL/max_pwrlevel" "0"
            write "$KGSL/default_pwrlevel" "0"
            write "$KGSL/force_clk_on" "1"
            write "$KGSL/force_bus_on" "1"
            write "$KGSL/force_rail_on" "1"
            write "$KGSL/idle_timer" "10000"
            write "$KGSL/devfreq/min_freq" "$max_freq"
            write "$KGSL/devfreq/max_freq" "$max_freq"
            # Adreno boost
            write "$KGSL/throttling" "0"
            write "$KGSL/thermal_pwrlevel" "0"
            glog "INFO" "Adreno: max performance mode"
            ;;
        balanced)
            write "$KGSL/devfreq/governor" "msm-adreno-tz"
            write "$KGSL/min_pwrlevel" "6"
            write "$KGSL/max_pwrlevel" "0"
            write "$KGSL/default_pwrlevel" "3"
            write "$KGSL/idle_timer" "64"
            write "$KGSL/devfreq/min_freq" "$min_freq"
            write "$KGSL/devfreq/max_freq" "$max_freq"
            write "$KGSL/throttling" "1"
            glog "INFO" "Adreno: balanced mode"
            ;;
        battery|powersave)
            write "$KGSL/devfreq/governor" "powersave"
            write "$KGSL/min_pwrlevel" "6"
            write "$KGSL/max_pwrlevel" "5"
            write "$KGSL/default_pwrlevel" "6"
            write "$KGSL/idle_timer" "32"
            write "$KGSL/devfreq/min_freq" "$min_freq"
            write "$KGSL/devfreq/max_freq" "$(echo "$avail_freqs" | awk 'NR==int(NF/3){print}')"
            write "$KGSL/throttling" "1"
            glog "INFO" "Adreno: powersave mode"
            ;;
    esac

    # Adreno-specific: GPU bus bandwidth
    local GPU_BUS="/sys/class/devfreq/soc:qcom,gpubw"
    if [ -d "$GPU_BUS" ]; then
        case "$profile" in
            gaming|performance)
                write "$GPU_BUS/governor" "performance"
                write "$GPU_BUS/max_freq" "$(cat $GPU_BUS/max_freq 2>/dev/null)"
                ;;
            battery|powersave)
                write "$GPU_BUS/governor" "powersave"
                ;;
            *)
                write "$GPU_BUS/governor" "bw_vbif"
                ;;
        esac
    fi
}

# ─── Mali GPU Tuning ──────────────────────────────────────────────────────────
tune_mali() {
    local profile="$1"
    local MALI="/sys/devices/platform/mali.0"
    local MALI_ALT="/sys/class/misc/mali0"

    [ ! -d "$MALI" ] && MALI="$MALI_ALT"

    glog "INFO" "Tuning Mali GPU: $profile"

    case "$profile" in
        gaming|performance)
            write "$MALI/power_policy" "always_on"
            write "$MALI/dvfs_governor" "performance"
            write "$MALI/highspeed_load" "60"
            write "$MALI/highspeed_delay" "0"
            # DevFreq Mali
            for dev in /sys/class/devfreq/*/; do
                if echo "$dev" | grep -qi "mali\|gpu"; then
                    write "${dev}governor" "performance"
                    write "${dev}max_freq" "$(cat ${dev}max_freq 2>/dev/null)"
                fi
            done
            glog "INFO" "Mali: max performance mode"
            ;;
        balanced)
            write "$MALI/power_policy" "coarse_demand"
            write "$MALI/dvfs_governor" "interactive"
            write "$MALI/highspeed_load" "80"
            write "$MALI/highspeed_delay" "1"
            for dev in /sys/class/devfreq/*/; do
                if echo "$dev" | grep -qi "mali\|gpu"; then
                    write "${dev}governor" "simple_ondemand"
                fi
            done
            glog "INFO" "Mali: balanced mode"
            ;;
        battery|powersave)
            write "$MALI/power_policy" "demand"
            write "$MALI/dvfs_governor" "powersave"
            write "$MALI/highspeed_load" "95"
            write "$MALI/highspeed_delay" "5"
            for dev in /sys/class/devfreq/*/; do
                if echo "$dev" | grep -qi "mali\|gpu"; then
                    write "${dev}governor" "powersave"
                    write "${dev}min_freq" "$(cat ${dev}min_freq 2>/dev/null)"
                fi
            done
            glog "INFO" "Mali: powersave mode"
            ;;
    esac
}

# ─── Generic DevFreq GPU Tuning ───────────────────────────────────────────────
tune_devfreq_gpu() {
    local profile="$1"
    glog "INFO" "Tuning DevFreq GPU: $profile"

    for dev in /sys/class/devfreq/*/; do
        local name
        name=$(basename "$dev")
        if echo "$name" | grep -qi "gpu\|kgsl\|mali\|pvr\|sgx"; then
            case "$profile" in
                gaming|performance)
                    write "${dev}governor" "performance"
                    write "${dev}max_freq" "$(cat ${dev}max_freq 2>/dev/null)"
                    write "${dev}min_freq" "$(cat ${dev}max_freq 2>/dev/null)"
                    ;;
                balanced)
                    write "${dev}governor" "simple_ondemand"
                    write "${dev}min_freq" "$(cat ${dev}min_freq 2>/dev/null)"
                    write "${dev}max_freq" "$(cat ${dev}max_freq 2>/dev/null)"
                    ;;
                battery|powersave)
                    write "${dev}governor" "powersave"
                    write "${dev}max_freq" "$(cat ${dev}min_freq 2>/dev/null)"
                    ;;
            esac
        fi
    done
}

# ─── Apply Profile ────────────────────────────────────────────────────────────
apply_profile() {
    local profile="$1"
    glog "INFO" "Applying GPU profile: $profile"

    local gpu_type
    gpu_type=$(detect_gpu)
    glog "INFO" "Detected GPU: $gpu_type"

    case "$gpu_type" in
        adreno)
            tune_adreno "$profile"
            ;;
        mali)
            tune_mali "$profile"
            ;;
        devfreq*)
            tune_devfreq_gpu "$profile"
            ;;
        *)
            glog "WARN" "Unknown GPU type, attempting generic tuning"
            tune_devfreq_gpu "$profile"
            ;;
    esac

    # Universal: DRAM frequency (affects GPU bandwidth)
    for dram in /sys/class/devfreq/*/; do
        if echo "$dram" | grep -qi "ddr\|dram\|bus\|mem"; then
            case "$profile" in
                gaming|performance)
                    write "${dram}governor" "performance"
                    ;;
                battery|powersave)
                    write "${dram}governor" "powersave"
                    ;;
                *)
                    write "${dram}governor" "simple_ondemand"
                    ;;
            esac
        fi
    done

    glog "INFO" "GPU profile '$profile' applied"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
PROFILE="${1:-balanced}"
apply_profile "$PROFILE"
