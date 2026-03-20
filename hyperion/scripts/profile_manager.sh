#!/system/bin/sh
# =============================================================================
# Hyperion Project - Profile Manager with Export/Import
# Made by ShadowBytePrjkt
# =============================================================================
# Save, load, export, and import custom profiles

HYPERION_DIR="/data/adb/hyperion"
PROFILES_DIR="$HYPERION_DIR/profiles"
BACKUP_DIR="$HYPERION_DIR/backups"
CONFIG_DIR="$HYPERION_DIR/config"

klog() {
    echo "[$(date -u +%H:%M:%S)][PROFILE] $1"
}

# ─── Export Current Profile ──────────────────────────────────────────────────
export_profile() {
    local profile="${1:-custom}"
    local output_file="${2:-}"
    
    klog "Exporting profile: $profile"
    
    # Create export data
    local export_data="{"
    export_data="${export_data}\"name\":\"$profile\","
    export_data="${export_data}\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    export_data="${export_data}\"version\":\"1.0.0\","
    export_data="${export_data}\"hyperion_version\":\"v1.0.0\","
    
    # CPU settings
    local cpu_gov
    cpu_gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "schedutil")
    export_data="${export_data}\"cpu\":{\"governor\":\"$cpu_gov\"},"
    
    # GPU settings
    export_data="${export_data}\"gpu\":{"
    if [ -f "/sys/class/kgsl/kgsl-3d0/max_gpuclk" ]; then
        export_data="${export_data}\"max_clk\":\"$(cat /sys/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null)\","
        export_data="${export_data}\"force_clk\":\"$(cat /sys/class/kgsl/kgsl-3d0/force_clk_on 2>/dev/null)\""
    fi
    export_data="${export_data}},"
    
    # Memory settings
    export_data="${export_data}\"memory\":{"
    export_data="${export_data}\"swappiness\":\"$(sysctl -n vm.swappiness 2>/dev/null || echo 60)\""
    export_data="${export_data},"
    if [ -f "/sys/block/zram0/disksize" ]; then
        export_data="${export_data}\"zram_size\":\"$(cat /sys/block/zram0/disksize 2>/dev/null)\""
    fi
    export_data="${export_data}},"
    
    # IO settings
    export_data="${export_data}\"io\":{"
    if [ -f "/sys/block/sda/queue/scheduler" ]; then
        local scheduler
        scheduler=$(cat /sys/block/sda/queue/scheduler 2>/dev/null | grep -oE '\[.*\]' | tr -d '[]')
        export_data="${export_data}\"scheduler\":\"$scheduler\","
        export_data="${export_data}\"readahead\":\"$(cat /sys/block/sda/queue/read_ahead_kb 2>/dev/null)\""
    fi
    export_data="${export_data}},"
    
    # Display settings
    export_data="${export_data}\"display\":{"
    if [ -f "$HYPERION_DIR/data/display_preset.txt" ]; then
        export_data="${export_data}\"preset\":\"$(cat $HYPERION_DIR/data/display_preset.txt)\""
    fi
    export_data="${export_data}},"
    
    # AI settings
    export_data="${export_data}\"ai\":{"
    if [ -f "$HYPERION_DIR/data/ai_enabled.txt" ]; then
        export_data="${export_data}\"enabled\":\"$(cat $HYPERION_DIR/data/ai_enabled.txt)\""
    fi
    export_data="${export_data}},"
    
    # Custom overrides (if any)
    export_data="${export_data}\"custom\":{}"
    
    export_data="${export_data}}"
    
    if [ -n "$output_file" ]; then
        echo "$export_data" > "$output_file"
        klog "Profile exported to: $output_file"
    else
        echo "$export_data"
    fi
}

# ─── Import Profile ────────────────────────────────────────────────────────────
import_profile() {
    local input_file="$1"
    local apply="${2:-true}"
    
    klog "Importing profile from: $input_file"
    
    if [ ! -f "$input_file" ]; then
        echo "Error: File not found: $input_file"
        return 1
    fi
    
    # Read JSON and apply settings
    local profile_name
    profile_name=$(python3 -c "import json; print(json.load(open('$input_file')).get('name', 'imported'))" 2>/dev/null)
    
    # Apply CPU settings
    local cpu_gov
    cpu_gov=$(python3 -c "import json; print(json.load(open('$input_file')).get('cpu', {}).get('governor', 'schedutil'))" 2>/dev/null)
    if [ -n "$cpu_gov" ]; then
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            [ -f "$cpu" ] && echo "$cpu_gov" > "$cpu" 2>/dev/null
        done
        klog "CPU governor set to: $cpu_gov"
    fi
    
    # Apply GPU settings
    local gpu_max
    gpu_max=$(python3 -c "import json; print(json.load(open('$input_file')).get('gpu', {}).get('max_clk', ''))" 2>/dev/null)
    if [ -n "$gpu_max" ] && [ -f "/sys/class/kgsl/kgsl-3d0/max_gpuclk" ]; then
        echo "$gpu_max" > /sys/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null
        klog "GPU max clock set to: $gpu_max"
    fi
    
    # Apply Memory settings
    local swappiness
    swappiness=$(python3 -c "import json; print(json.load(open('$input_file')).get('memory', {}).get('swappiness', 60))" 2>/dev/null)
    if [ -n "$swappiness" ]; then
        sysctl -w vm.swappiness="$swappiness" 2>/dev/null
        klog "Swappiness set to: $swappiness"
    fi
    
    # Apply IO settings
    local scheduler
    scheduler=$(python3 -c "import json; print(json.load(open('$input_file')).get('io', {}).get('scheduler', ''))" 2>/dev/null)
    if [ -n "$scheduler" ]; then
        for queue in /sys/block/*/queue/scheduler; do
            [ -f "$queue" ] && echo "$scheduler" > "$queue" 2>/dev/null
        done
        klog "IO scheduler set to: $scheduler"
    fi
    
    # Save as custom profile
    echo "$profile_name" > "$HYPERION_DIR/data/current_profile.txt"
    
    klog "Profile imported successfully: $profile_name"
    echo "Profile '$profile_name' imported and applied!"
}

# ─── Backup All Settings ───────────────────────────────────────────────────────
backup_all() {
    local backup_name="${1:-hyperion_backup_$(date +%Y%m%d_%H%M%S)}"
    
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/${backup_name}.zip"
    
    klog "Creating backup: $backup_name"
    
    # Create backup archive
    (
        cd "$HYPERION_DIR"
        
        # Include config files
        zip -r "$backup_file" \
            config/ \
            profiles/ \
            data/ \
            -x "*.log" "*.pyc" 2>/dev/null
    )
    
    if [ -f "$backup_file" ]; then
        klog "Backup created: $backup_file"
        echo "$backup_file"
    else
        echo "Error: Backup failed"
        return 1
    fi
}

# ─── Restore Backup ───────────────────────────────────────────────────────────
restore_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        # Try to find in backup dir
        backup_file="$BACKUP_DIR/${backup_file}.zip"
        if [ ! -f "$backup_file" ]; then
            echo "Error: Backup not found: $backup_file"
            return 1
        fi
    fi
    
    klog "Restoring backup: $backup_file"
    
    # Stop services first
    sh "$HYPERION_DIR/service.sh" stop 2>/dev/null
    
    # Restore files
    unzip -o "$backup_file" -d "$HYPERION_DIR" 2>/dev/null
    
    # Restart services
    sh "$HYPERION_DIR/service.sh" start 2>/dev/null
    
    klog "Backup restored successfully"
    echo "Backup restored!"
}

# ─── List Backups ────────────────────────────────────────────────────────────
list_backups() {
    mkdir -p "$BACKUP_DIR"
    
    echo "Available backups:"
    ls -lh "$BACKUP_DIR"/*.zip 2>/dev/null || echo "No backups found"
}

# ─── Share Profile ───────────────────────────────────────────────────────────
share_profile() {
    local profile="${1:-custom}"
    local share_file="/sdcard/Download/hyperion_${profile}_$(date +%Y%m%d).json"
    
    export_profile "$profile" "$share_file"
    
    echo "Profile saved to: $share_file"
    echo "You can now share this file!"
}

# ─── Quick Save ──────────────────────────────────────────────────────────────
quick_save() {
    local slot="${1:-1}"
    local save_file="$HYPERION_DIR/data/quick_save_${slot}.json"
    
    export_profile "quick_save_$slot" "$save_file"
    
    echo "Quick save $slot created!"
}

# ─── Quick Load ──────────────────────────────────────────────────────────────
quick_load() {
    local slot="${1:-1}"
    local save_file="$HYPERION_DIR/data/quick_save_${slot}.json"
    
    if [ -f "$save_file" ]; then
        import_profile "$save_file"
    else
        echo "Quick save $slot not found!"
        return 1
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────
case "$1" in
    export)
        export_profile "${2:-custom}" "${3:-}"
        ;;
    import)
        import_profile "${2}" "${3:-true}"
        ;;
    backup)
        backup_all "${2}"
        ;;
    restore)
        restore_backup "${2}"
        ;;
    list)
        list_backups
        ;;
    share)
        share_profile "${2:-custom}"
        ;;
    save)
        quick_save "${2:-1}"
        ;;
    load)
        quick_load "${2:-1}"
        ;;
    *)
        echo "Usage: $0 {export|import|backup|restore|list|share|save|load}"
        echo ""
        echo "Examples:"
        echo "  $0 export custom /sdcard/my_profile.json"
        echo "  $0 import /sdcard/my_profile.json"
        echo "  $0 backup my_backup"
        echo "  $0 restore my_backup"
        echo "  $0 share gaming"
        echo "  $0 save 1"
        echo "  $0 load 1"
        ;;
esac
