#!/system/bin/sh
# =============================================================================
# Hyperion Project - Memory Optimization Script
# Made by ShadowBytePrjkt
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/memory.log"

mlog() {
    local level="$1"; local msg="$2"
    local ts; ts=$(date -u +%H:%M:%S)
    echo "[$ts][MEM][$level] $msg" >> "$LOG_FILE"
    echo "[$ts][MEM][$level] $msg"
}

write() {
    local path="$1"; local value="$2"
    if [ -f "$path" ] && [ -w "$path" ]; then
        echo "$value" > "$path" 2>/dev/null && \
            mlog "DEBUG" "write $path = $value" || \
            mlog "WARN" "failed write $path = $value"
    fi
}

# ─── Get Total RAM in MB ──────────────────────────────────────────────────────
get_total_ram_mb() {
    awk '/MemTotal/{print int($2/1024)}' /proc/meminfo
}

# ─── Configure ZRAM ───────────────────────────────────────────────────────────
configure_zram() {
    local size_mb="$1"
    local algorithm="$2"  # lz4, zstd, lzo, lzo-rle

    mlog "INFO" "Configuring ZRAM: size=${size_mb}MB algo=${algorithm}"

    local ZRAM="/dev/block/zram0"
    local ZRAM_SYS="/sys/block/zram0"

    if [ ! -b "$ZRAM" ]; then
        mlog "WARN" "ZRAM device not found"
        return 1
    fi

    # Disable existing swap
    swapoff "$ZRAM" 2>/dev/null

    # Reset ZRAM
    echo "1" > "$ZRAM_SYS/reset" 2>/dev/null

    # Set compression algorithm
    if [ -f "$ZRAM_SYS/comp_algorithm" ]; then
        local avail_algos
        avail_algos=$(cat "$ZRAM_SYS/comp_algorithm")
        if echo "$avail_algos" | grep -q "$algorithm"; then
            echo "$algorithm" > "$ZRAM_SYS/comp_algorithm"
            mlog "INFO" "ZRAM algorithm: $algorithm"
        else
            # Fallback to lz4 or lzo
            for fallback in lz4 zstd lzo-rle lzo; do
                if echo "$avail_algos" | grep -q "$fallback"; then
                    echo "$fallback" > "$ZRAM_SYS/comp_algorithm"
                    mlog "INFO" "ZRAM algorithm fallback: $fallback"
                    break
                fi
            done
        fi
    fi

    # Set size
    local size_bytes=$((size_mb * 1024 * 1024))
    echo "$size_bytes" > "$ZRAM_SYS/disksize"

    # Enable swap with priority
    mkswap "$ZRAM" 2>/dev/null
    swapon -p 32767 "$ZRAM" 2>/dev/null

    mlog "INFO" "ZRAM configured: $(cat $ZRAM_SYS/disksize 2>/dev/null) bytes"
}

# ─── KSM (Kernel Same-page Merging) ──────────────────────────────────────────
configure_ksm() {
    local enabled="$1"
    local KSM="/sys/kernel/mm/ksm"

    if [ ! -d "$KSM" ]; then
        mlog "WARN" "KSM not available"
        return
    fi

    if [ "$enabled" = "1" ]; then
        write "$KSM/run" "1"
        write "$KSM/sleep_millisecs" "1000"
        write "$KSM/pages_to_scan" "100"
        mlog "INFO" "KSM enabled"
    else
        write "$KSM/run" "0"
        mlog "INFO" "KSM disabled"
    fi
}

# ─── LMK (Low Memory Killer) Tuning ──────────────────────────────────────────
configure_lmk() {
    local mode="$1"
    local LMK="/sys/module/lowmemorykiller/parameters"

    if [ ! -d "$LMK" ]; then
        mlog "WARN" "LMK not available (using LMKD)"
        # LMKD configuration via properties
        case "$mode" in
            aggressive)
                setprop ro.lmk.low 1001
                setprop ro.lmk.medium 800
                setprop ro.lmk.critical 0
                setprop ro.lmk.critical_upgrade false
                setprop ro.lmk.upgrade_pressure 100
                setprop ro.lmk.downgrade_pressure 100
                setprop ro.lmk.kill_heaviest_task true
                ;;
            conservative)
                setprop ro.lmk.low 1001
                setprop ro.lmk.medium 800
                setprop ro.lmk.critical 0
                setprop ro.lmk.kill_heaviest_task false
                ;;
        esac
        return
    fi

    case "$mode" in
        aggressive)
            # Kill apps more aggressively to free RAM
            write "$LMK/minfree" "18432,23040,27648,32256,55296,80640"
            write "$LMK/adj" "0,1,2,4,9,12"
            mlog "INFO" "LMK: aggressive mode"
            ;;
        balanced)
            write "$LMK/minfree" "18432,23040,27648,32256,55296,80640"
            write "$LMK/adj" "0,1,2,4,9,15"
            mlog "INFO" "LMK: balanced mode"
            ;;
        conservative)
            # Keep more apps in RAM
            write "$LMK/minfree" "4096,8192,12288,16384,24576,32768"
            write "$LMK/adj" "0,1,2,4,9,15"
            mlog "INFO" "LMK: conservative mode"
            ;;
    esac
}

# ─── OOM Score Adjustment ─────────────────────────────────────────────────────
protect_critical_processes() {
    mlog "INFO" "Protecting critical processes from OOM"

    # Protect system_server
    local ss_pid
    ss_pid=$(pgrep -f "system_server" | head -1)
    if [ -n "$ss_pid" ]; then
        echo "-900" > "/proc/$ss_pid/oom_score_adj" 2>/dev/null
    fi

    # Protect surfaceflinger
    local sf_pid
    sf_pid=$(pgrep -f "surfaceflinger" | head -1)
    if [ -n "$sf_pid" ]; then
        echo "-1000" > "/proc/$sf_pid/oom_score_adj" 2>/dev/null
    fi
}

# ─── Apply Profile ────────────────────────────────────────────────────────────
apply_profile() {
    local profile="$1"
    local total_ram
    total_ram=$(get_total_ram_mb)
    mlog "INFO" "Applying memory profile: $profile (RAM: ${total_ram}MB)"

    case "$profile" in
        gaming|performance)
            # Maximize available RAM for foreground app
            write "/proc/sys/vm/swappiness" "10"
            write "/proc/sys/vm/vfs_cache_pressure" "50"
            write "/proc/sys/vm/dirty_ratio" "20"
            write "/proc/sys/vm/dirty_background_ratio" "5"
            write "/proc/sys/vm/dirty_expire_centisecs" "200"
            write "/proc/sys/vm/dirty_writeback_centisecs" "500"
            write "/proc/sys/vm/page-cluster" "0"
            write "/proc/sys/vm/min_free_kbytes" "8192"
            write "/proc/sys/vm/extra_free_kbytes" "24576"
            configure_ksm "0"
            configure_lmk "conservative"
            # ZRAM: smaller, faster compression
            local zram_size=$((total_ram / 4))
            configure_zram "$zram_size" "lz4"
            protect_critical_processes
            mlog "INFO" "Gaming/Performance memory profile applied"
            ;;
        balanced)
            write "/proc/sys/vm/swappiness" "60"
            write "/proc/sys/vm/vfs_cache_pressure" "100"
            write "/proc/sys/vm/dirty_ratio" "30"
            write "/proc/sys/vm/dirty_background_ratio" "10"
            write "/proc/sys/vm/dirty_expire_centisecs" "3000"
            write "/proc/sys/vm/dirty_writeback_centisecs" "500"
            write "/proc/sys/vm/page-cluster" "3"
            write "/proc/sys/vm/min_free_kbytes" "4096"
            configure_ksm "1"
            configure_lmk "balanced"
            local zram_size=$((total_ram / 2))
            configure_zram "$zram_size" "lz4"
            mlog "INFO" "Balanced memory profile applied"
            ;;
        battery|powersave)
            write "/proc/sys/vm/swappiness" "100"
            write "/proc/sys/vm/vfs_cache_pressure" "200"
            write "/proc/sys/vm/dirty_ratio" "40"
            write "/proc/sys/vm/dirty_background_ratio" "15"
            write "/proc/sys/vm/dirty_expire_centisecs" "6000"
            write "/proc/sys/vm/dirty_writeback_centisecs" "1500"
            write "/proc/sys/vm/page-cluster" "3"
            write "/proc/sys/vm/min_free_kbytes" "2048"
            configure_ksm "1"
            configure_lmk "aggressive"
            local zram_size=$((total_ram * 3 / 4))
            configure_zram "$zram_size" "zstd"
            mlog "INFO" "Battery/Powersave memory profile applied"
            ;;
    esac

    # Drop caches (safe - they'll be repopulated)
    sync
    echo "3" > /proc/sys/vm/drop_caches 2>/dev/null
    mlog "INFO" "Cache dropped"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
PROFILE="${1:-balanced}"
apply_profile "$PROFILE"
