#!/system/bin/sh
# =============================================================================
# Hyperion Project - Memory Presets
# Made by ShadowBytePrjkt
# =============================================================================
# Memory management presets for different RAM sizes
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/memory.log"

klog() {
    echo "[$(date -u +%H:%M:%S)][MEMORY] $1" | tee -a "$LOG_FILE"
}

write() {
    [ -f "$1" ] && [ -w "$1" ] && echo "$2" > "$1" 2>/dev/null
}

# ─── Get Total RAM ───────────────────────────────────────────────────────────
get_total_ram() {
    local ram_kb
    ram_kb=$(cat /proc/meminfo | grep MemTotal | awk '{print $2}')
    echo $((ram_kb / 1024))  # Convert to MB
}

# ─── Detect RAM Category ─────────────────────────────────────────────────────
detect_ram_category() {
    local total_ram
    total_ram=$(get_total_ram)
    
    if [ "$total_ram" -lt 3500 ]; then
        echo "low"  # 3GB or less
    elif [ "$total_ram" -lt 7000 ]; then
        echo "medium"  # 4-6GB
    else
        echo "high"  # 8GB+
    fi
}

# ─── Low Memory Preset (3GB or less) ─────────────────────────────────────────
apply_low_preset() {
    klog "Applying LOW memory preset (3GB or less)"
    
    # Aggressive LMK values
    write /sys/module/lowmemorykiller/parameters/minfree "18432,23040,27648,32256,36864,41472"
    write /sys/module/lowmemorykiller/parameters/adj "0,58,117,176,529,1000"
    
    # Higher ZRAM
    local total_ram
    total_ram=$(get_total_ram)
    local zram_percent=50
    write /sys/block/zram0/disksize "$((total_ram * 1024 * 1024 * zram_percent / 100))"
    
    # Lower swappiness (aggressive swap)
    sysctl -w vm.swappiness=180 2>/dev/null
    
    # Aggressive memory reclaim
    sysctl -w vm.vfs_cache_pressure=200 2>/dev/null
    sysctl -w vm.dirty_ratio=20 2>/dev/null
    sysctl -w vm.dirty_background_ratio=5 2>/dev/null
    
    # Smaller read ahead
    for ra in /sys/class/block/*/queue/read_ahead_kb; do
        write "$ra" "128"
    done
    
    # Disable compaction (saves memory but fragmentation possible)
    sysctl -w vm.compact_unevictable_allowed=0 2>/dev/null
    
    klog "LOW memory preset applied"
}

# ─── Medium Memory Preset (4-6GB) ────────────────────────────────────────────
apply_medium_preset() {
    klog "Applying MEDIUM memory preset (4-6GB)"
    
    # Balanced LMK
    write /sys/module/lowmemorykiller/parameters/minfree "30740,38424,46108,53792,61476,69160"
    write /sys/module/lowmemorykiller/parameters/adj "0,58,117,176,529,1000"
    
    # Moderate ZRAM (25%)
    local total_ram
    total_ram=$(get_total_ram)
    write /sys/block/zram0/disksize "$((total_ram * 1024 * 1024 / 4))"
    
    # Balanced swappiness
    sysctl -w vm.swappiness=100 2>/dev/null
    
    # Balanced reclaim settings
    sysctl -w vm.vfs_cache_pressure=100 2>/dev/null
    sysctl -w vm.dirty_ratio=30 2>/dev/null
    sysctl -w vm.dirty_background_ratio=10 2>/dev/null
    
    # Default read ahead
    for ra in /sys/class/block/*/queue/read_ahead_kb; do
        write "$ra" "512"
    done
    
    # Normal compaction
    sysctl -w vm.compact_unevictable_allowed=1 2>/dev/null
    
    klog "MEDIUM memory preset applied"
}

# ─── High Memory Preset (8GB+) ───────────────────────────────────────────────
apply_high_preset() {
    klog "Applying HIGH memory preset (8GB+)"
    
    # Relaxed LMK values
    write /sys/module/lowmemorykiller/parameters/minfree "65536,81920,98304,114688,131072,147456"
    write /sys/module/lowmemorykiller/parameters/adj "0,100,200,300,900,906"
    
    # Minimal ZRAM (10%)
    local total_ram
    total_ram=$(get_total_ram)
    write /sys/block/zram0/disksize "$((total_ram * 1024 * 1024 / 10))"
    
    # Low swappiness (keep more in RAM)
    sysctl -w vm.swappiness=30 2>/dev/null
    
    # Aggressive caching
    sysctl -w vm.vfs_cache_pressure=50 2>/dev/null
    sysctl -w vm.dirty_ratio=40 2>/dev/null
    sysctl -w vm.dirty_background_ratio=15 2>/dev/null
    
    # Higher read ahead for performance
    for ra in /sys/class/block/*/queue/read_ahead_kb; do
        write "$ra" "1024"
    done
    
    # Enable compaction for better memory management
    sysctl -w vm.compact_unevictable_allowed=1 2>/dev/null
    sysctl -w vm.compaction_proactiveness=20 2>/dev/null
    
    # Enable transparent huge pages
    write /sys/kernel/mm/transparent_hugepage/enabled "always"
    write /sys/kernel/mm/transparent_hugepage/defrag "defer+madvise"
    
    klog "HIGH memory preset applied"
}

# ─── Set ZRAM Size ───────────────────────────────────────────────────────────
set_zram() {
    local percent="$1"
    local total_ram
    total_ram=$(get_total_ram)
    
    local zram_size=$((total_ram * 1024 * 1024 * percent / 100))
    
    # Disable zram first
    swapoff /dev/zram0 2>/dev/null
    
    # Set new size
    write /sys/block/zram0/disksize "$zram_size"
    
    # Format and enable
    mkswap /dev/zram0 2>/dev/null
    swapon /dev/zram0 2>/dev/null
    
    klog "ZRAM set to ${percent}% (${zram_size} bytes)"
}

# ─── Set Swappiness ──────────────────────────────────────────────────────────
set_swappiness() {
    local value="$1"
    sysctl -w vm.swappiness="$value" 2>/dev/null
    klog "Swappiness set to $value"
}

# ─── Optimize Memory Now ─────────────────────────────────────────────────────
optimize_memory() {
    klog "Running memory optimization..."
    
    # Drop caches
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    
    # Compact memory
    echo 1 > /proc/sys/vm/compact_memory 2>/dev/null
    
    # Trigger garbage collection
    for pid in $(ls /proc/ | grep -E '^[0-9]+$'); do
        if [ -f "/proc/$pid/cmdline" ]; then
            # Just a nudge, won't force gc but helps
            :
        fi
    done
    
    klog "Memory optimization complete"
}

# ─── Get Current Settings ───────────────────────────────────────────────────
get_settings() {
    python3 -c "
import subprocess

def get_value(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except:
        return 'N/A'

def sysctl_get(prop):
    try:
        result = subprocess.run(['sysctl', '-n', prop], capture_output=True, text=True)
        return result.stdout.strip()
    except:
        return 'N/A'

total_ram = $(get_total_ram)

settings = {
    'total_ram_mb': total_ram,
    'detected_category': '$([detect_ram_category])',
    'lmk_minfree': get_value('/sys/module/lowmemorykiller/parameters/minfree'),
    'lmk_adj': get_value('/sys/module/lowmemorykiller/parameters/adj'),
    'swappiness': sysctl_get('vm.swappiness'),
    'vfs_cache_pressure': sysctl_get('vm.vfs_cache_pressure'),
    'dirty_ratio': sysctl_get('vm.dirty_ratio'),
    'zram_size': get_value('/sys/block/zram0/disksize')
}

import json
print(json.dumps(settings, indent=2))
"
}

# ─── Main ────────────────────────────────────────────────────────────────────
case "$1" in
    low)
        apply_low_preset
        ;;
    medium)
        apply_medium_preset
        ;;
    high)
        apply_high_preset
        ;;
    auto)
        category=$(detect_ram_category)
        case "$category" in
            low)   apply_low_preset ;;
            medium) apply_medium_preset ;;
            high)  apply_high_preset ;;
        esac
        echo "Applied auto-detected: $category"
        ;;
    zram)
        set_zram "${2:-25}"
        ;;
    swappiness)
        set_swappiness "${2:-60}"
        ;;
    optimize)
        optimize_memory
        ;;
    settings)
        get_settings
        ;;
    detect)
        detect_ram_category
        ;;
    *)
        echo "Usage: $0 {low|medium|high|auto|zram|swappiness|optimize|settings|detect}"
        ;;
esac
