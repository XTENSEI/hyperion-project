#!/system/bin/sh
# =============================================================================
# Hyperion Project - Game Booster & FPS Overlay
# Made by ShadowBytePrjkt
# =============================================================================
# Real-time FPS counter, game-specific optimizations, GPU boost buttons
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/game_booster.log"
GAME_MODE_FILE="$HYPERION_DIR/data/game_mode.active"
FPS_DATA_FILE="$HYPERION_DIR/data/fps_stats.json"

klog() {
    echo "[$(date -u +%H:%M:%S)][GAME] $1" | tee -a "$LOG_FILE"
}

write() {
    [ -f "$1" ] && [ -w "$1" ] && echo "$2" > "$1" 2>/dev/null
}

# ─── FPS Detection ────────────────────────────────────────────────────────────
detect_fps() {
    local package="$1"
    local fps=0
    
    # Try gfxinfo method (works with debuggable apps)
    if [ -n "$package" ]; then
        local frame_data
        frame_data=$(dumpsys gfxinfo "$package" framestats 2>/dev/null | tail -15)
        
        if [ -n "$frame_data" ]; then
            # Extract frame times and calculate FPS
            fps=$(echo "$frame_data" | awk '
            BEGIN { total=0; count=0 }
            {
                # Match frame time values (e.g., "15.5 ms")
                if ($0 ~ /[0-9]+\.[0-9]+ *ms/) {
                    gsub(/ms/, "", $NF)
                    if ($NF < 100 && $NF > 0) {
                        total += $NF
                        count++
                    }
                }
            }
            END {
                if (count > 0) {
                    avg = total / count
                    printf "%.0f", 1000 / avg
                }
            }')
        fi
    fi
    
    echo "${fps:-0}"
}

# ─── Get Current Game ────────────────────────────────────────────────────────
get_current_game() {
    # Common game packages
    local games="
    com.supercell.clashofclans
    com.supercell.clashroyale
    com.pubg.krmobile
    com.tencent.ig
    com.epicgames.fortnite
    com.garena.game.codm
    com.activision.callofduty.warzone
    com.miHoYo.GenshinImpact
    com.miHoYo.astro
    com.netease.lightsky
    com.netease.mrzh
    com.innerscore.shell
    com.innerspec.shell
    com.sega.strikers
    com.ea.gp.fifamobile
    com.ea.gp.fifaultimate
    com.rovio.battle
    com.king.candycrushsaga
    com.king.candycrushsodaparty
    com.rovio.angrybirdsfriends
    net.wargaming.wot.blitz
    com.gameloft.android.ANMP.GloftA8HM
    com.gameloft.android.GloftA5HM
    com.gameloft.android.ANMP.GloftA7HM
    com.garena.freefiremax
    com.dts.freefireth
    com.dts.freefire
    "
    
    # Check if any game is in foreground
    local foreground
    foreground=$(dumpsys window 2>/dev/null | grep mCurrentFocus | head -1 | awk -F'/' '{print $1}' | awk '{print $NF}')
    
    for game in $games; do
        if [ "$foreground" = "$game" ]; then
            echo "$foreground"
            return
        fi
    done
    
    # Check recent apps for games
    local recent
    recent=$(dumpsys activity recents 2>/dev/null | grep -E "^\s*[a-z]" | head -20)
    for game in $games; do
        if echo "$recent" | grep -q "$game"; then
            echo "$game"
            return
        fi
    done
    
    echo ""
}

# ─── Game Boost ──────────────────────────────────────────────────────────────
game_boost_on() {
    klog "Enabling game boost..."
    
    # CPU optimizations
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$cpu" ] && echo "performance" > "$cpu" 2>/dev/null
    done
    
    # Disable CPU hotplug
    write /sys/module/msm_thermal/core_control/enabled "0"
    
    # GPU max performance
    write /sys/class/kgsl/kgsl-3d0/max_gpuclk "745000000" 2>/dev/null
    write /sys/class/kgsl/kgsl-3d0/force_rail_on "1" 2>/dev/null
    write /sys/class/kgsl/kgsl-3d0/force_clk_on "1" 2>/dev/null
    
    # Enable all cores
    for core in /sys/devices/system/cpu/cpu*/online; do
        [ -f "$core" ] && echo "1" > "$core" 2>/dev/null
    done
    
    # Memory optimizations
    sysctl -w vm.swappiness=10 2>/dev/null
    sysctl -w vm.vfs_cache_pressure=50 2>/dev/null
    
    # IO optimizations
    for queue in /sys/block/*/queue/scheduler; do
        [ -f "$queue" ] && echo "noop" > "$queue" 2>/dev/null
    done
    for ra in /sys/block/*/queue/read_ahead_kb; do
        [ -f "$ra" ] && echo "2048" > "$ra" 2>/dev/null
    done
    
    # Thermal throttling disable
    write /sys/module/msm_thermal/vdd_restriction/enabled "0"
    write /sys/class/thermal/thermal_zone0/mode "disabled" 2>/dev/null
    
    # Boost
    echo "1" > /sys/power/pm_freeze_timeout 2>/dev/null
    
    # Mark game mode active
    echo "true" > "$GAME_MODE_FILE"
    
    # Apply gaming profile
    sh "$HYPERION_DIR/core/profile_manager.sh" apply gaming 2>/dev/null
    
    # Send notification (SAC-style)
    sh "$HYPERION_DIR/core/notify.sh" game enabled 2>/dev/null
    
    klog "Game boost enabled"
}

# ─── Game Boost Off ──────────────────────────────────────────────────────────
game_boost_off() {
    klog "Disabling game boost..."
    
    # Restore CPU
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$cpu" ] && echo "schedutil" > "$cpu" 2>/dev/null
    done
    
    # GPU restore
    write /sys/class/kgsl/kgsl-3d0/force_rail_on "0" 2>/dev/null
    write /sys/class/kgsl/kgsl-3d0/force_clk_on "0" 2>/dev/null
    
    # Restore memory
    sysctl -w vm.swappiness=60 2>/dev/null
    sysctl -w vm.vfs_cache_pressure=100 2>/dev/null
    
    # Mark game mode inactive
    echo "false" > "$GAME_MODE_FILE"
    
    # Send notification (SAC-style)
    sh "$HYPERION_DIR/core/notify.sh" game disabled 2>/dev/null
    
    klog "Game boost disabled"
}

# ─── GPU Boost (Temporary) ─────────────────────────────────────────────────
gpu_boost() {
    local duration="${1:-30}"
    klog "Boosting GPU for ${duration}s..."
    
    # Store original
    local orig_max
    orig_max=$(cat /sys/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null)
    
    # Set max GPU clock
    write /sys/class/kgsl/kgsl-3d0/max_gpuclk "745000000" 2>/dev/null
    
    # Force GPU to max
    write /sys/class/kgsl/kgsl-3d0/force_clk_on "1" 2>/dev/null
    write /sys/class/kgsl/kgsl-3d0/force_rail_on "1" 2>/dev/null
    
    # Wait duration
    sleep "$duration"
    
    # Restore
    if [ -n "$orig_max" ]; then
        write /sys/class/kgsl/kgsl-3d0/max_gpuclk "$orig_max"
    fi
    write /sys/class/kgsl/kgsl-3d0/force_clk_on "0" 2>/dev/null
    write /sys/class/kgsl/kgsl-3d0/force_rail_on "0" 2>/dev/null
    
    klog "GPU boost complete"
}

# ─── FPS Overlay Service ────────────────────────────────────────────────────
start_fps_overlay() {
    klog "Starting FPS overlay service..."
    
    # Kill existing
    stop_fps_overlay
    
    # Create overlay script
    cat > "$HYPERION_DIR/data/fps_overlay_svc.sh" << 'FPSEOF'
#!/system/bin/sh
HYPERION_DIR="/data/adb/hyperion"
DATA_DIR="$HYPERION_DIR/data"

while true; do
    # Get current foreground
    APP=$(dumpsys window 2>/dev/null | grep mCurrentFocus | head -1 | awk -F'/' '{print $1}' | awk '{print $NF}')
    
    # Get FPS
    FPS=0
    if [ -n "$APP" ]; then
        # Try to get FPS from gfxinfo
        FRAMES=$(dumpsys gfxinfo "$APP" framestats 2>/dev/null | tail -20)
        if [ -n "$FRAMES" ]; then
            FPS=$(echo "$FRAMES" | awk '
            BEGIN { total=0; count=0 }
            {
                if ($0 ~ /[0-9]+\.[0-9]+ *ms/) {
                    gsub(/ms/, "", $NF)
                    if ($NF < 100 && $NF > 0) {
                        total += $NF
                        count++
                    }
                }
            }
            END {
                if (count > 0) printf "%.0f", 1000 / (total / count)
            }')
        fi
    fi
    
    # Get CPU/GPU freq
    CPU=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
    CPU=$((CPU / 1000))
    GPU=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null)
    GPU=$((GPU / 1000000))
    
    # Get memory
    MEM=$(awk '/MemAvailable/{a=$2} /MemTotal/{t=$2} END{print int((t-a)*100/t)}' /proc/meminfo)
    
    # Temperature
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    TEMP=$((TEMP / 1000))
    
    # Write to shared file
    echo "{\"fps\":\"${FPS:-0}\",\"cpu\":\"${CPU}MHz\",\"gpu\":\"${GPU}MHz\",\"mem\":\"${MEM}%\",\"temp\":\"${TEMP}C\",\"app\":\"${APP:-None}\"}" > "$DATA_DIR/fps_live.json"
    
    sleep 0.5
done
FPSEOF

    chmod 755 "$HYPERION_DIR/data/fps_overlay_svc.sh"
    nohup "$HYPERION_DIR/data/fps_overlay_svc.sh" > /dev/null 2>&1 &
    echo $! > "$DATA_DIR/fps_overlay.pid"
    
    klog "FPS overlay started"
}

# ─── Stop FPS Overlay ────────────────────────────────────────────────────────
stop_fps_overlay() {
    if [ -f "$HYPERION_DIR/data/fps_overlay.pid" ]; then
        kill -9 "$(cat "$HYPERION_DIR/data/fps_overlay.pid")" 2>/dev/null
        rm -f "$HYPERION_DIR/data/fps_overlay.pid"
    fi
    pkill -f "fps_overlay_svc.sh" 2>/dev/null
    klog "FPS overlay stopped"
}

# ─── Get Live Stats ─────────────────────────────────────────────────────────
get_live_stats() {
    if [ -f "$HYPERION_DIR/data/fps_live.json" ]; then
        cat "$HYPERION_DIR/data/fps_live.json"
    else
        echo '{"fps":"--","cpu":"--MHz","gpu":"--MHz","mem":"--%","temp":"--C","app":"--"}'
    fi
}

# ─── Auto Game Detection ────────────────────────────────────────────────────
# ─── Auto Preload (SAC-style) ───────────────────────────────────────────────
HYPERION_CONFIG="/data/adb/.config/hyperion"

preload_game() {
    local package="$1"
    
    # Check if preload is enabled
    if [ ! -f "$HYPERION_CONFIG/preload_enabled" ]; then
        return
    fi
    
    klog "Preloading game: $package"
    
    # Show preload notification
    sh "$HYPERION_DIR/core/notify.sh" preload start "$package"
    
    # Calculate file limit based on available memory (like SAC)
    local mem_total
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local file_limit
    file_limit=$(echo "$mem_total / 65536" | bc 2>/dev/null || echo 100)
    
    # Find game data directories
    local data_dirs="/data/user/0/$package"
    
    # Try multiple storage paths
    for storage_path in "/storage/emulated/0/Android/data/$package" 
                       "/sdcard/Android/data/$package" 
                       "/data/data/$package"; do
        if [ -d "$storage_path" ]; then
            data_dirs="$data_dirs $storage_path"
        fi
    done
    
    # Get APK path
    local apk_path
    apk_path=$(dumpsys package "$package" 2>/dev/null | grep -o 'codePath=.*' | head -1 | sed 's/codePath=//')
    if [ -n "$apk_path" ] && [ -d "$apk_path" ]; then
        data_dirs="$data_dirs $apk_path"
    fi
    
    # Preload largest files (like SAC)
    local count=0
    for dir in $data_dirs; do
        if [ -d "$dir" ]; then
            for file in $(find "$dir" -type f -exec du -b {} + 2>/dev/null | sort -n | tail -n "$file_limit" | awk '{print $2}'); do
                if [ -f "$file" ]; then
                    # Read file into memory cache
                    cat "$file" > /dev/null 2>/dev/null &
                    count=$((count + 1))
                    # Limit concurrent operations
                    if [ $((count % 20)) -eq 0 ]; then
                        sleep 0.1
                    fi
                fi
            done
        fi
    done
    
    # Show preload done notification
    sh "$HYPERION_DIR/core/notify.sh" preload done "$package"
    
    klog "Preload complete for: $package ($count files)"
}

# ─── Watch Games Loop ─────────────────────────────────────────────────────────
watch_games() {
    local last_game=""
    local preload_enabled="$HYPERION_CONFIG/preload_enabled"
    
    while true; do
        local current_game
        current_game=$(get_current_game)
        
        if [ -n "$current_game" ] && [ "$current_game" != "$last_game" ]; then
            klog "Game detected: $current_game"
            
            # Apply game boost
            game_boost_on
            
            last_game="$current_game"
            
            # Notify user (SAC-style game detection notification)
            sh "$HYPERION_DIR/core/notify.sh" game game_detected "$current_game"
            
            # Auto preload game files (SAC-style)
            if [ -f "$preload_enabled" ]; then
                preload_game "$current_game" &
            fi
        elif [ -z "$current_game" ] && [ -n "$last_game" ]; then
            # Game closed
            klog "Game closed: $last_game"
            
            # Disable boost
            game_boost_off
            
            last_game=""
        fi
        
        sleep 3
    done
}

# ─── Game Profile ────────────────────────────────────────────────────────────
apply_game_profile() {
    local game="$1"
    klog "Applying custom profile for: $game"
    
    # Check for custom profile in config
    local custom_profile
    custom_profile=$(grep -i "$game" "$HYPERION_DIR/config/app_profiles.json" | grep -o "\"profile\":\"[^\"]*\"" | cut -d'"' -f4)
    
    if [ -n "$custom_profile" ]; then
        sh "$HYPERION_DIR/core/profile_manager.sh" apply "$custom_profile"
    else
        # Default to gaming
        game_boost_on
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────
case "$1" in
    start)
        game_boost_on
        ;;
    stop)
        game_boost_off
        ;;
    boost)
        gpu_boost "${2:-30}"
        ;;
    overlay_start)
        start_fps_overlay
        ;;
    overlay_stop)
        stop_fps_overlay
        ;;
    overlay_stats)
        get_live_stats
        ;;
    watch)
        watch_games
        ;;
    detect)
        get_current_game
        ;;
    fps)
        detect_fps "${2:-}"
        ;;
    profile)
        apply_game_profile "${2:-}"
        ;;
    status)
        if [ -f "$GAME_MODE_FILE" ]; then
            cat "$GAME_MODE_FILE"
        else
            echo "false"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|boost|overlay_start|overlay_stop|overlay_stats|watch|detect|fps|profile|status}"
        ;;
esac
