#!/system/bin/sh
# =============================================================================
# Hyperion Project - FPS Overlay & Live Stats Control
# Made by ShadowBytePrjkt
# =============================================================================
# Control FPS counter overlay, game mode indicators, and live performance stats
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
STATS_DIR="$HYPERION_DIR/data"
FPS_PID_FILE="$STATS_DIR/fps_overlay.pid"

# ─── Check if su is available ────────────────────────────────────────────────
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Root required"
        exit 1
    fi
}

# ─── Get Current FPS ──────────────────────────────────────────────────────────
get_fps() {
    # Try gfxinfo (most reliable)
    local fps=0
    local target_app="$1"

    if [ -z "$target_app" ]; then
        target_app=$(dumpsys window | grep -E "mCurrentFocus|mFocusedApp" | head -1 | awk -F'/' '{print $1}' | awk '{print $NF}')
    fi

    # Use gfxinfo for FPS (only works for debuggable apps)
    local fps_data
    fps_data=$(dumpsys gfxinfo "$target_app" framestats 2>/dev/null | tail -20)

    if [ -n "$fps_data" ]; then
        # Calculate FPS from frame times
        fps=$(echo "$fps_data" | grep -oE "[0-9]+\.[0-9]+ ms" | head -10 | awk '
        BEGIN { total=0; count=0 }
        {
            gsub(/ ms/, "", $1)
            if ($1 < 100) { total += $1; count++ }
        }
        END { if (count > 0) printf "%.0f", 1000 / (total / count) }')
    fi

    echo "${fps:-0}"
}

# ─── Get GPU Frequency ───────────────────────────────────────────────────────
get_gpu_freq() {
    local gpu_path="/sys/class/kgsl/kgsl-3d0"

    # Try different paths
    [ -f "$gpu_path/gpuclk" ] && cat "$gpu_path/gpuclk"
    [ -f "$gpu_path/devfreq/cur_freq" ] && cat "$gpu_path/devfreq/cur_freq"
    [ -f "$gpu_path/gpu_frequency" ] && cat "$gpu_path/gpu_frequency"
}

# ─── Get CPU Frequencies (all cores) ─────────────────────────────────────────
get_cpu_freqs() {
    local freqs=""
    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
        [ -f "$cpu/cpufreq/scaling_cur_freq" ] || continue
        local freq
        freq=$(cat "$cpu/cpufreq/scaling_cur_freq" 2>/dev/null)
        if [ -n "$freq" ]; then
            freq=$((freq / 1000))
            freqs="${freqs}${freq} "
        fi
    done
    echo "$freqs"
}

# ─── Get Current Temperature ──────────────────────────────────────────────────
get_temp() {
    # Try various thermal zones
    for zone in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$zone" ] || continue
        local temp
        temp=$(cat "$zone" 2>/dev/null)
        if [ -n "$temp" ] && [ "$temp" -gt 20000 ] && [ "$temp" -lt 120000 ]; then
            echo "$((temp / 1000))°C"
            return
        fi
    done
    echo "N/A"
}

# ─── Get Memory Usage ─────────────────────────────────────────────────────────
get_memory() {
    local meminfo
    meminfo=$(cat /proc/meminfo 2>/dev/null)

    local total
    total=$(echo "$meminfo" | grep MemTotal | awk '{print $2}')

    local available
    available=$(echo "$meminfo" | grep MemAvailable | awk '{print $2}')

    if [ -n "$total" ] && [ -n "$available" ]; then
        local used=$((total - available))
        local percent=$((used * 100 / total))
        echo "${percent}%"
    else
        echo "N/A"
    fi
}

# ─── Create FPS Overlay Service ───────────────────────────────────────────────
start_overlay() {
    check_root

    # Kill existing if any
    stop_overlay

    # Create overlay service script
    cat > "$STATS_DIR/overlay_service.sh" << 'OVLSCRIPT'
#!/system/bin/sh
HYPERION_DIR="/data/adb/hyperion"
STATS_DIR="$HYPERION_DIR/data"

while true; do
    # Get stats
    cpu_freqs=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null | head -1)
    cpu_freq=$((cpu_freqs / 1000))

    gpu_freq=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null || echo "0")
    gpu_freq=$((gpu_freq / 1000000))

    temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    [ -n "$temp" ] && temp=$((temp / 1000)) || temp=0

    mem_used=$(awk '/MemAvailable/{available=$2} /MemTotal/{total=$2} END{print int((total-available)*100/total)}' /proc/meminfo)

    # Try to get FPS of foreground app
    fps=0
    for pkg in $(dumpsys window | grep -oE "^[a-zA-Z0-9_]+\.[a-zA-Z0-9_]+" | sort -u); do
        fps_data=$(dumpsys gfxinfo "$pkg" framestats 2>/dev/null | tail -5)
        [ -n "$fps_data" ] && break
    done

    # Write to shared file
    echo "{\"cpu\":\"${cpu_freq}MHz\",\"gpu\":\"${gpu_freq}MHz\",\"temp\":\"${temp}C\",\"mem\":\"${mem_used}%\",\"fps\":\"$fps\"}" > "$STATS_DIR/live_stats.json"

    sleep 0.5
done
OVLSCRIPT

    chmod 755 "$STATS_DIR/overlay_service.sh"
    nohup "$STATS_DIR/overlay_service.sh" > /dev/null 2>&1 &
    echo $! > "$FPS_PID_FILE"

    echo "FPS Overlay started"
}

# ─── Stop FPS Overlay ──────────────────────────────────────────────────────────
stop_overlay() {
    if [ -f "$FPS_PID_FILE" ]; then
        local pid
        pid=$(cat "$FPS_PID_FILE")
        if [ -n "$pid" ]; then
            kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$FPS_PID_FILE"
    fi

    # Also kill any orphan processes
    pkill -f "overlay_service.sh" 2>/dev/null

    echo "FPS Overlay stopped"
}

# ─── Get Live Stats ───────────────────────────────────────────────────────────
get_stats() {
    if [ -f "$STATS_DIR/live_stats.json" ]; then
        cat "$STATS_DIR/live_stats.json"
    else
        # Fallback to direct reads
        cpu_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
        cpu_freq=$((cpu_freq / 1000))

        gpu_freq=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null || echo "0")
        gpu_freq=$((gpu_freq / 1000000))

        temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        [ -n "$temp" ] && temp=$((temp / 1000)) || temp=0

        mem_used=$(awk '/MemAvailable/{a=$2} /MemTotal/{t=$2} END{print int((t-a)*100/t)}' /proc/meminfo)

        echo "{\"cpu\":\"${cpu_freq}MHz\",\"gpu\":\"${gpu_freq}MHz\",\"temp\":\"${temp}C\",\"mem\":\"${mem_used}%\"}"
    fi
}

# ─── Game Mode Indicator ─────────────────────────────────────────────────────
set_game_mode() {
    local enabled="$1"

    # Enable/disable game mode features
    if [ "$enabled" = "true" ]; then
        # Disable dex2oat
        settings put global dex2oat_enabled 0

        # Disable JIT
        settings put global jit_enabled 0

        # Set game mode in hyperion
        echo "true" > "$STATS_DIR/game_mode.active"

        echo "Game mode enabled"
    else
        # Re-enable dex2oat
        settings put global dex2oat_enabled 1

        # Re-enable JIT
        settings put global jit_enabled 1

        # Clear game mode
        echo "false" > "$STATS_DIR/game_mode.active"

        echo "Game mode disabled"
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────
case "$1" in
    start)    start_overlay ;;
    stop)     stop_overlay ;;
    stats)    get_stats ;;
    fps)      get_fps "${2:-}" ;;
    gpu)      get_gpu_freq ;;
    cpu)      get_cpu_freqs ;;
    temp)     get_temp ;;
    memory)   get_memory ;;
    game_mode) set_game_mode "$2" ;;
    *)        echo "Usage: $0 {start|stop|stats|fps|gpu|cpu|temp|memory|game_mode}"
esac
