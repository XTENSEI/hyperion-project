#!/system/bin/sh
# =============================================================================
# Hyperion Project - IO Scheduler Control
# Made by ShadowBytePrjkt
# =============================================================================
# Control IO scheduler and read ahead for storage optimization
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/io.log"

klog() {
    echo "[$(date -u +%H:%M:%S)][IO] $1" | tee -a "$LOG_FILE"
}

write() {
    [ -f "$1" ] && [ -w "$1" ] && echo "$2" > "$1" 2>/dev/null
}

# ─── Get Available Schedulers ────────────────────────────────────────────────
get_available_schedulers() {
    local schedulers=""
    
    for queue in /sys/block/*/queue/scheduler; do
        [ -f "$queue" ] || continue
        local available
        available=$(cat "$queue" 2>/dev/null)
        if [ -n "$available" ]; then
            echo "$available"
            return
        fi
    done
    
    echo "noop deadline cfq bfq"
}

# ─── Set IO Scheduler ────────────────────────────────────────────────────────
set_scheduler() {
    local scheduler="$1"
    klog "Setting IO scheduler to: $scheduler"
    
    local success=0
    local failed=0
    
    for queue in /sys/block/*/queue/scheduler; do
        [ -f "$queue" ] || continue
        [ -w "$queue" ] || continue
        
        local available
        available=$(cat "$queue" 2>/dev/null)
        
        # Check if scheduler is available
        if echo "$available" | grep -q "$scheduler"; then
            echo "$scheduler" > "$queue" 2>/dev/null
            if [ $? -eq 0 ]; then
                success=$((success + 1))
                klog "Set $(basename $(dirname $queue)) to $scheduler"
            else
                failed=$((failed + 1))
            fi
        else
            # Try to find an available one
            local first
            first=$(echo "$available" | grep -oE '\[.*\]' | tr -d '[]')
            if [ -n "$first" ]; then
                echo "$first" > "$queue" 2>/dev/null
            fi
        fi
    done
    
    klog "IO scheduler set: $scheduler (success: $success, failed: $failed)"
}

# ─── Set Read Ahead ───────────────────────────────────────────────────────────
set_readahead() {
    local kb="$1"
    klog "Setting read ahead to ${kb}KB"
    
    for ra in /sys/block/*/queue/read_ahead_kb; do
        [ -f "$ra" ] || continue
        [ -w "$ra" ] || continue
        echo "$kb" > "$ra" 2>/dev/null
    done
    
    # Also set for specific devices
    write /sys/block/sda/queue/read_ahead_kb "$kb"
    write /sys/block/sdb/queue/read_ahead_kb "$kb"
    write /sys/block/mmcblk0/queue/read_ahead_kb "$kb"
    
    klog "Read ahead set to ${kb}KB"
}

# ─── Set Queue Depth ──────────────────────────────────────────────────────────
set_queue_depth() {
    local depth="$1"
    klog "Setting queue depth to $depth"
    
    for device in /sys/block/*/device/queue_depth; do
        [ -f "$device" ] && [ -w "$device" ] && echo "$depth" > "$device" 2>/dev/null
    done
}

# ─── Apply NOOP Preset (Fastest) ─────────────────────────────────────────────
apply_noop_preset() {
    klog "Applying NOOP preset (fastest, least CPU)"
    set_scheduler "noop"
    set_readahead "256"
    set_queue_depth "32"
}

# ─── Apply Deadline Preset (Balanced) ───────────────────────────────────────
apply_deadline_preset() {
    klog "Applying Deadline preset (balanced)"
    set_scheduler "deadline"
    set_readahead "512"
    set_queue_depth "16"
}

# ─── Apply BFQ Preset (IO Heavy) ─────────────────────────────────────────────
apply_bfq_preset() {
    klog "Applying BFQ preset (best for IO heavy)"
    set_scheduler "bfq"
    set_readahead "1024"
    set_queue_depth "8"
}

# ─── Apply MQ-Deadline Preset ────────────────────────────────────────────────
apply_mq_preset() {
    klog "Applying MQ-Deadline preset (multi-queue optimized)"
    set_scheduler "mq-deadline"
    set_readahead "512"
    set_queue_depth "32"
}

# ─── Apply CFQ Preset (Classic) ─────────────────────────────────────────────
apply_cfq_preset() {
    klog "Applying CFQ preset (classic)"
    set_scheduler "cfq"
    set_readahead "512"
    set_queue_depth "8"
}

# ─── Get Current Settings ───────────────────────────────────────────────────
get_settings() {
    python3 -c "
import json
import subprocess

def read_file(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except:
        return 'N/A'

def get_prop(prop):
    try:
        result = subprocess.run(['sysctl', '-n', prop], capture_output=True, text=True)
        return result.stdout.strip()
    except:
        return 'N/A'

settings = {
    'available_schedulers': [],
    'current_scheduler': {},
    'readahead': {},
    'queue_depth': {},
    'nomerges': read_file('/sys/block/sda/queue/nomerges'),
    'rq_affinity': read_file('/sys/block/sda/queue/rq_affinity'),
    'rotational': read_file('/sys/block/sda/queue/rotational')
}

# Get scheduler and readahead for each block device
import os
for device in os.listdir('/sys/block'):
    scheduler_path = f'/sys/block/{device}/queue/scheduler'
    readahead_path = f'/sys/block/{device}/queue/read_ahead_kb'
    qdepth_path = f'/sys/block/{device}/queue/nr_requests'
    
    if os.path.exists(scheduler_path):
        sched = read_file(scheduler_path)
        settings['available_schedulers'].append(sched)
        current = sched.replace('[', '').replace(']', '').split()[0] if '[' in sched else 'unknown'
        settings['current_scheduler'][device] = current
    
    if os.path.exists(readahead_path):
        settings['readahead'][device] = read_file(readahead_path)
    
    if os.path.exists(qdepth_path):
        settings['queue_depth'][device] = read_file(qdepth_path)

print(json.dumps(settings, indent=2))
"
}

# ─── Boost IO Priority ───────────────────────────────────────────────────────
boost_io_priority() {
    local enabled="$1"
    
    if [ "$enabled" = "true" ]; then
        klog "Enabling IO priority boost"
        # Increase nr_requests for better IO batching
        for nr in /sys/block/*/queue/nr_requests; do
            write "$nr" "1024"
        done
        # Enable add random
        write /sys/block/sda/queue/add_random 0
    else
        klog "Disabling IO priority boost"
        for nr in /sys/block/*/queue/nr_requests; do
            write "$nr" "256"
        done
        write /sys/block/sda/queue/add_random 1
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────
case "$1" in
    scheduler)
        set_scheduler "${2:-noop}"
        ;;
    readahead)
        set_readahead "${2:-512}"
        ;;
    queue_depth)
        set_queue_depth "${2:-32}"
        ;;
    noop)
        apply_noop_preset
        ;;
    deadline)
        apply_deadline_preset
        ;;
    bfq)
        apply_bfq_preset
        ;;
    mq-deadline)
        apply_mq_preset
        ;;
    cfq)
        apply_cfq_preset
        ;;
    boost)
        boost_io_priority "${2:-true}"
        ;;
    settings)
        get_settings
        ;;
    available)
        get_available_schedulers
        ;;
    *)
        echo "Usage: $0 {scheduler|readahead|queue_depth|noop|deadline|bfq|mq-deadline|cfq|boost|settings|available}"
        ;;
esac
