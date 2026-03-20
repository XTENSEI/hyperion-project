#!/system/bin/sh
# =============================================================================
# Hyperion Project - CPU Optimization Script
# Made by ShadowBytePrjkt
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/cpu.log"

# ─── Logging ──────────────────────────────────────────────────────────────────
clog() {
    local level="$1"
    local msg="$2"
    local ts
    ts=$(date -u +%H:%M:%S)
    echo "[$ts][CPU][$level] $msg" >> "$LOG_FILE"
    echo "[$ts][CPU][$level] $msg"
}

# ─── Write to sysfs safely ────────────────────────────────────────────────────
write() {
    local path="$1"
    local value="$2"
    if [ -f "$path" ] && [ -w "$path" ]; then
        echo "$value" > "$path" 2>/dev/null && \
            clog "DEBUG" "write $path = $value" || \
            clog "WARN" "failed write $path = $value"
    fi
}

# ─── Get CPU count ────────────────────────────────────────────────────────────
get_cpu_count() {
    ls /sys/devices/system/cpu/ | grep -c "^cpu[0-9]"
}

# ─── Get available governors ──────────────────────────────────────────────────
get_governors() {
    local cpu0_gov="/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"
    if [ -f "$cpu0_gov" ]; then
        cat "$cpu0_gov"
    else
        echo "performance schedutil conservative powersave"
    fi
}

# ─── Check if governor is available ──────────────────────────────────────────
governor_available() {
    local gov="$1"
    get_governors | grep -qw "$gov"
}

# ─── Set CPU Governor ─────────────────────────────────────────────────────────
set_governor() {
    local governor="$1"
    local cpu_count
    cpu_count=$(get_cpu_count)

    # Fallback governor chain
    if ! governor_available "$governor"; then
        clog "WARN" "Governor '$governor' not available, trying fallbacks..."
        for fallback in schedutil interactive ondemand performance powersave; do
            if governor_available "$fallback"; then
                governor="$fallback"
                clog "INFO" "Using fallback governor: $governor"
                break
            fi
        done
    fi

    clog "INFO" "Setting governor: $governor (${cpu_count} CPUs)"
    for i in $(seq 0 $((cpu_count - 1))); do
        write "/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor" "$governor"
    done
}

# ─── Set CPU Frequency Limits ─────────────────────────────────────────────────
set_freq() {
    local min_freq="$1"
    local max_freq="$2"
    local cpu_count
    cpu_count=$(get_cpu_count)

    clog "INFO" "Setting freq: min=${min_freq} max=${max_freq}"
    for i in $(seq 0 $((cpu_count - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpufreq"
        if [ -d "$cpu_path" ]; then
            # Get available frequencies
            local avail_freqs
            avail_freqs=$(cat "$cpu_path/scaling_available_frequencies" 2>/dev/null | tr ' ' '\n' | sort -n)

            if [ -n "$avail_freqs" ]; then
                local actual_min actual_max
                actual_min=$(echo "$avail_freqs" | head -1)
                actual_max=$(echo "$avail_freqs" | tail -1)

                # Clamp to available range
                [ "$min_freq" = "min" ] && min_freq="$actual_min"
                [ "$max_freq" = "max" ] && max_freq="$actual_max"

                # Calculate percentage-based freq
                if echo "$min_freq" | grep -q "%"; then
                    local pct
                    pct=$(echo "$min_freq" | tr -d '%')
                    min_freq=$(echo "$avail_freqs" | awk "NR==int(NF*${pct}/100+0.5){print}")
                fi
                if echo "$max_freq" | grep -q "%"; then
                    local pct
                    pct=$(echo "$max_freq" | tr -d '%')
                    max_freq=$(echo "$avail_freqs" | awk "END{print int(NR*${pct}/100+0.5)}" | head -1)
                fi
            fi

            write "$cpu_path/scaling_min_freq" "$min_freq"
            write "$cpu_path/scaling_max_freq" "$max_freq"
        fi
    done
}

# ─── Set Big.LITTLE Asymmetric Tuning ────────────────────────────────────────
set_biglittle() {
    local little_gov="$1"
    local big_gov="$2"
    local little_max="$3"
    local big_max="$4"

    # Detect cluster topology
    local cluster0_cpus cluster1_cpus
    if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/related_cpus" ]; then
        cluster0_cpus=$(cat /sys/devices/system/cpu/cpu0/cpufreq/related_cpus)
        # Find big cluster (higher max freq)
        local cpu_count
        cpu_count=$(get_cpu_count)
        local last_cpu=$((cpu_count - 1))
        cluster1_cpus=$(cat "/sys/devices/system/cpu/cpu${last_cpu}/cpufreq/related_cpus" 2>/dev/null)
    fi

    clog "INFO" "big.LITTLE: little=$little_gov/$little_max big=$big_gov/$big_max"

    # Apply to little cluster (cpu0 group)
    for cpu in $cluster0_cpus; do
        write "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor" "$little_gov"
        [ -n "$little_max" ] && write "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_max_freq" "$little_max"
    done

    # Apply to big cluster
    for cpu in $cluster1_cpus; do
        write "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor" "$big_gov"
        [ -n "$big_max" ] && write "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_max_freq" "$big_max"
    done
}

# ─── CPU Boost Control ────────────────────────────────────────────────────────
set_boost() {
    local enabled="$1"  # 0 or 1
    clog "INFO" "CPU boost: $enabled"

    # Generic boost
    write "/sys/devices/system/cpu/cpufreq/boost" "$enabled"

    # Qualcomm specific
    write "/sys/module/cpu_boost/parameters/input_boost_enabled" "$enabled"
    write "/sys/module/msm_performance/parameters/cpu_max_freq" "0:4294967295 1:4294967295 2:4294967295 3:4294967295"

    # MediaTek specific
    write "/proc/ppm/enabled" "$enabled"
    write "/proc/cpufreq/cpufreq_power_mode" "$enabled"
}

# ─── IRQ Affinity ─────────────────────────────────────────────────────────────
set_irq_affinity() {
    local mode="$1"  # performance or balanced
    clog "INFO" "IRQ affinity mode: $mode"

    if [ "$mode" = "performance" ]; then
        # Spread IRQs across all CPUs
        local cpu_count
        cpu_count=$(get_cpu_count)
        local mask=$((2**cpu_count - 1))
        local hex_mask
        hex_mask=$(printf '%x' "$mask")
        for irq in /proc/irq/*/smp_affinity; do
            echo "$hex_mask" > "$irq" 2>/dev/null
        done
    else
        # Pin IRQs to little cores (cpu0-3)
        for irq in /proc/irq/*/smp_affinity; do
            echo "f" > "$irq" 2>/dev/null
        done
    fi
}

# ─── CPU Idle States ──────────────────────────────────────────────────────────
set_idle_states() {
    local mode="$1"  # performance (disable deep idle) or powersave (enable all)
    clog "INFO" "CPU idle states: $mode"

    local cpu_count
    cpu_count=$(get_cpu_count)

    for i in $(seq 0 $((cpu_count - 1))); do
        local idle_path="/sys/devices/system/cpu/cpu${i}/cpuidle"
        if [ -d "$idle_path" ]; then
            for state in "$idle_path"/state*/disable; do
                if [ "$mode" = "performance" ]; then
                    echo "1" > "$state" 2>/dev/null  # Disable deep idle
                else
                    echo "0" > "$state" 2>/dev/null  # Enable all idle states
                fi
            done
        fi
    done
}

# ─── Schedutil Tuning ─────────────────────────────────────────────────────────
tune_schedutil() {
    local up_rate="$1"    # rate_limit_us for scaling up (lower = more responsive)
    local down_rate="$2"  # rate_limit_us for scaling down

    clog "INFO" "Schedutil: up_rate=${up_rate} down_rate=${down_rate}"

    local cpu_count
    cpu_count=$(get_cpu_count)
    for i in $(seq 0 $((cpu_count - 1))); do
        local gov_path="/sys/devices/system/cpu/cpu${i}/cpufreq/schedutil"
        if [ -d "$gov_path" ]; then
            write "$gov_path/rate_limit_us" "$up_rate"
            write "$gov_path/hispeed_load" "90"
            write "$gov_path/hispeed_freq" "$(cat /sys/devices/system/cpu/cpu${i}/cpufreq/cpuinfo_max_freq 2>/dev/null)"
        fi
    done
}

# ─── Apply Profile ────────────────────────────────────────────────────────────
apply_profile() {
    local profile="$1"
    clog "INFO" "Applying CPU profile: $profile"

    case "$profile" in
        gaming)
            set_governor "performance"
            set_freq "min" "max"
            set_boost 1
            set_idle_states "performance"
            set_irq_affinity "performance"
            # Qualcomm specific
            write "/sys/module/msm_performance/parameters/touchboost" "1"
            write "/proc/sys/kernel/sched_boost" "1"
            clog "INFO" "Gaming CPU profile applied"
            ;;
        performance)
            set_governor "performance"
            set_freq "min" "max"
            set_boost 1
            set_idle_states "performance"
            write "/proc/sys/kernel/sched_boost" "1"
            clog "INFO" "Performance CPU profile applied"
            ;;
        balanced)
            set_governor "schedutil"
            set_freq "min" "max"
            set_boost 0
            set_idle_states "balanced"
            tune_schedutil "500" "20000"
            write "/proc/sys/kernel/sched_boost" "0"
            clog "INFO" "Balanced CPU profile applied"
            ;;
        battery)
            set_governor "schedutil"
            set_freq "min" "75%"
            set_boost 0
            set_idle_states "powersave"
            tune_schedutil "2000" "50000"
            write "/proc/sys/kernel/sched_boost" "0"
            clog "INFO" "Battery CPU profile applied"
            ;;
        powersave)
            set_governor "powersave"
            set_freq "min" "50%"
            set_boost 0
            set_idle_states "powersave"
            write "/proc/sys/kernel/sched_boost" "0"
            clog "INFO" "Powersave CPU profile applied"
            ;;
        *)
            clog "WARN" "Unknown profile: $profile, using balanced"
            apply_profile "balanced"
            ;;
    esac
}

# ─── Main ─────────────────────────────────────────────────────────────────────
PROFILE="${1:-balanced}"
apply_profile "$PROFILE"
