#!/system/bin/sh
# =============================================================================
# Hyperion Project - I/O Scheduler & Block Device Optimization
# Made by ShadowBytePrjkt
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/io.log"

iolog() {
    local level="$1"; local msg="$2"
    local ts; ts=$(date -u +%H:%M:%S)
    echo "[$ts][IO][$level] $msg" >> "$LOG_FILE"
    echo "[$ts][IO][$level] $msg"
}

write() {
    local path="$1"; local value="$2"
    [ -f "$path" ] && [ -w "$path" ] && echo "$value" > "$path" 2>/dev/null
}

# ─── Get All Block Devices ────────────────────────────────────────────────────
get_block_devices() {
    ls /sys/block/ | grep -v "^loop\|^ram\|^zram\|^dm-"
}

# ─── Set I/O Scheduler ────────────────────────────────────────────────────────
set_scheduler() {
    local device="$1"
    local scheduler="$2"
    local sched_path="/sys/block/${device}/queue/scheduler"

    if [ ! -f "$sched_path" ]; then
        return
    fi

    local avail
    avail=$(cat "$sched_path" 2>/dev/null)

    # Try preferred scheduler, fallback chain
    local schedulers_to_try="$scheduler mq-deadline kyber bfq cfq noop none"
    for sched in $schedulers_to_try; do
        if echo "$avail" | grep -qw "$sched"; then
            echo "$sched" > "$sched_path" 2>/dev/null
            iolog "INFO" "Scheduler $device: $sched"
            return
        fi
    done
}

# ─── Set Read-Ahead ───────────────────────────────────────────────────────────
set_readahead() {
    local device="$1"
    local kb="$2"
    write "/sys/block/${device}/queue/read_ahead_kb" "$kb"
}

# ─── Set Queue Depth ──────────────────────────────────────────────────────────
set_queue_depth() {
    local device="$1"
    local depth="$2"
    write "/sys/block/${device}/queue/nr_requests" "$depth"
    write "/sys/block/${device}/queue/iosched/quantum" "$depth"
}

# ─── Set I/O Queue Parameters ─────────────────────────────────────────────────
tune_queue() {
    local device="$1"
    local mode="$2"
    local queue="/sys/block/${device}/queue"

    case "$mode" in
        performance)
            write "$queue/add_random" "0"
            write "$queue/rq_affinity" "2"
            write "$queue/nomerges" "0"
            write "$queue/rotational" "0"
            write "$queue/iostats" "0"
            write "$queue/iosched/low_latency" "1"
            write "$queue/iosched/back_seek_penalty" "1"
            write "$queue/iosched/slice_idle" "0"
            write "$queue/iosched/group_idle" "0"
            ;;
        balanced)
            write "$queue/add_random" "0"
            write "$queue/rq_affinity" "1"
            write "$queue/nomerges" "0"
            write "$queue/rotational" "0"
            write "$queue/iostats" "1"
            ;;
        powersave)
            write "$queue/add_random" "0"
            write "$queue/rq_affinity" "0"
            write "$queue/nomerges" "2"
            write "$queue/rotational" "0"
            ;;
    esac
}

# ─── FSTRIM ───────────────────────────────────────────────────────────────────
run_fstrim() {
    iolog "INFO" "Running FSTRIM..."
    fstrim -v /data 2>/dev/null && iolog "INFO" "FSTRIM /data: done"
    fstrim -v /cache 2>/dev/null && iolog "INFO" "FSTRIM /cache: done"
    fstrim -v /system 2>/dev/null && iolog "INFO" "FSTRIM /system: done"
}

# ─── F2FS Tuning ──────────────────────────────────────────────────────────────
tune_f2fs() {
    local mode="$1"

    for f2fs_dev in /sys/fs/f2fs/*/; do
        case "$mode" in
            performance)
                write "${f2fs_dev}gc_idle_interval" "0"
                write "${f2fs_dev}gc_min_sleep_time" "20"
                write "${f2fs_dev}gc_max_sleep_time" "100"
                write "${f2fs_dev}gc_no_gc_sleep_time" "300"
                write "${f2fs_dev}iostat_enable" "0"
                ;;
            balanced)
                write "${f2fs_dev}gc_idle_interval" "1000"
                write "${f2fs_dev}gc_min_sleep_time" "30"
                write "${f2fs_dev}gc_max_sleep_time" "500"
                write "${f2fs_dev}gc_no_gc_sleep_time" "10000"
                ;;
            powersave)
                write "${f2fs_dev}gc_idle_interval" "5000"
                write "${f2fs_dev}gc_min_sleep_time" "100"
                write "${f2fs_dev}gc_max_sleep_time" "2000"
                write "${f2fs_dev}gc_no_gc_sleep_time" "30000"
                ;;
        esac
    done
}

# ─── EXT4 Tuning ──────────────────────────────────────────────────────────────
tune_ext4() {
    local mode="$1"

    # EXT4 commit interval
    case "$mode" in
        performance)
            # More frequent commits = less data loss risk, slightly more I/O
            for dev in $(mount | grep ext4 | awk '{print $1}'); do
                tune2fs -E lazy_itable_init=0 "$dev" 2>/dev/null
            done
            ;;
        powersave)
            # Less frequent commits = less I/O = more battery
            ;;
    esac
}

# ─── Apply Profile ────────────────────────────────────────────────────────────
apply_profile() {
    local profile="$1"
    iolog "INFO" "Applying I/O profile: $profile"

    local devices
    devices=$(get_block_devices)

    for device in $devices; do
        case "$profile" in
            gaming|performance)
                set_scheduler "$device" "mq-deadline"
                set_readahead "$device" "2048"
                set_queue_depth "$device" "128"
                tune_queue "$device" "performance"
                ;;
            balanced)
                set_scheduler "$device" "bfq"
                set_readahead "$device" "512"
                set_queue_depth "$device" "64"
                tune_queue "$device" "balanced"
                ;;
            battery|powersave)
                set_scheduler "$device" "kyber"
                set_readahead "$device" "128"
                set_queue_depth "$device" "32"
                tune_queue "$device" "powersave"
                ;;
        esac
    done

    # Filesystem-specific tuning
    tune_f2fs "$profile"
    tune_ext4 "$profile"

    # Run FSTRIM on balanced/battery profiles (maintenance)
    if [ "$profile" = "balanced" ] || [ "$profile" = "battery" ]; then
        # Only run if last trim was >24h ago
        local last_trim_file="$HYPERION_DIR/data/last_fstrim"
        local now
        now=$(date +%s)
        local last_trim=0
        [ -f "$last_trim_file" ] && last_trim=$(cat "$last_trim_file")
        local elapsed=$((now - last_trim))
        if [ "$elapsed" -gt 86400 ]; then
            run_fstrim
            echo "$now" > "$last_trim_file"
        fi
    fi

    iolog "INFO" "I/O profile '$profile' applied to $(echo $devices | wc -w) devices"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
case "$1" in
    fstrim) run_fstrim ;;
    *)      apply_profile "${1:-balanced}" ;;
esac
