#!/system/bin/sh
# =============================================================================
# Hyperion Project - Device Detection & Path Auto-discovery
# Made by ShadowBytePrjkt
# =============================================================================
# Auto-detect device capabilities and available sysfs paths

HYPERION_DIR="/data/adb/hyperion"
DETECT_FILE="$HYPERION_DIR/data/device_info.json"

klog() {
    echo "[$(date -u +%H:%M:%S)][DETECT] $1"
}

# ─── Detect CPU Info ──────────────────────────────────────────────────────────
detect_cpu() {
    local cpu_info="{"
    
    # CPU governor path
    local gov_path="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
    if [ -f "$gov_path" ]; then
        local gov
        gov=$(cat "$gov_path" 2>/dev/null)
        cpu_info="${cpu_info}\"governor_path\":\"$gov_path\",\"current_governor\":\"$gov\","
    fi
    
    # CPU frequencies
    local min_freq="/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq"
    local max_freq="/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"
    
    if [ -f "$min_freq" ]; then
        local min
        min=$(( $(cat "$min_freq") / 1000 ))
        cpu_info="${cpu_info}\"min_freq\":$min,"
    fi
    
    if [ -f "$max_freq" ]; then
        local max
        max=$(( $(cat "$max_freq") / 1000 ))
        cpu_info="${cpu_info}\"max_freq\":$max,"
    fi
    
    # CPU cores
    local cores
    cores=$(ls /sys/devices/system/cpu/ | grep -c "cpu[0-9]" 2>/dev/null || echo "8")
    cpu_info="${cpu_info}\"cores\":$cores,"
    
    # CPU boost
    if [ -f "/sys/devices/system/cpu/cpufreq/boost" ]; then
        cpu_info="${cpu_info}\"boost_supported\":true,"
    fi
    
    # Available governors
    local avail_gov=""
    if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors" ]; then
        avail_gov=$(cat "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors" 2>/dev/null)
        cpu_info="${cpu_info}\"available_governors\":\"$avav_gov\""
    fi
    
    cpu_info="${cpu_info}}"
    echo "$cpu_info"
}

# ─── Detect GPU Info ─────────────────────────────────────────────────────────
detect_gpu() {
    local gpu_info="{"
    
    # Check for Adreno (Qualcomm)
    if [ -d "/sys/class/kgsl/kgsl-3d0" ]; then
        gpu_info="${gpu_info}\"type\":\"adreno\","
        
        local gpu_path="/sys/class/kgsl/kgsl-3d0"
        
        if [ -f "$gpu_path/gpuclk" ]; then
            local max_gpu
            max_gpu=$(( $(cat "$gpu_path/gpuclk" 2>/dev/null || echo "0") / 1000000 ))
            gpu_info="${gpu_info}\"max_clk\":$max_gpu,"
        fi
        
        if [ -f "$gpu_path/devfreq/cur_freq" ]; then
            local cur_gpu
            cur_gpu=$(( $(cat "$gpu_path/devfreq/cur_freq" 2>/dev/null || echo "0") / 1000000 ))
            gpu_info="${gpu_info}\"cur_freq\":$cur_gpu,"
        fi
        
        # GPU available frequencies
        if [ -f "$gpu_path/gpu_available_frequencies" ]; then
            local freqs
            freqs=$(cat "$gpu_path/gpu_available_frequencies" 2>/dev/null | tr ' ' ',')
            gpu_info="${gpu_info}\"available_freqs\":[$freqs],"
        fi
        
        gpu_info="${gpu_info}\"path\":\"$gpu_path\""
    # Check for Mali
    elif [ -d "/sys/class/misc/mali0" ]; then
        gpu_info="${gpu_info}\"type\":\"mali\","
        gpu_info="${gpu_info}\"path\":\"/sys/class/misc/mali0\""
    else
        gpu_info="${gpu_info}\"type\":\"unknown\""
    fi
    
    gpu_info="${gpu_info}}"
    echo "$gpu_info"
}

# ─── Detect Memory Info ─────────────────────────────────────────────────────
detect_memory() {
    local mem_info="{"
    
    # Total RAM
    local total
    total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    total=$((total / 1024))
    mem_info="${mem_info}\"total_mb\":$total,"
    
    # Detect category
    local category="medium"
    if [ "$total" -lt 3500 ]; then
        category="low"
    elif [ "$total" -gt 7000 ]; then
        category="high"
    fi
    mem_info="${mem_info}\"category\":\"$category\","
    
    # LMK paths
    if [ -f "/sys/module/lowmemorykiller/parameters/minfree" ]; then
        mem_info="${mem_info}\"lmk_path\":\"/sys/module/lowmemorykiller/parameters\","
    fi
    
    # ZRAM
    if [ -f "/sys/block/zram0/disksize" ]; then
        mem_info="${mem_info}\"zram_available\":true,"
    fi
    
    # Swap
    if [ -f "/proc/swaps" ]; then
        local swap
        swap=$(grep -v Filename /proc/swaps | awk '{sum+=$3} END {print sum}')
        mem_info="${mem_info}\"swap_mb\":$swap"
    fi
    
    mem_info="${mem_info}}"
    echo "$mem_info"
}

# ─── Detect Thermal ───────────────────────────────────────────────────────────
detect_thermal() {
    local thermal_info="{"
    
    # Count thermal zones
    local zones
    zones=$(ls /sys/class/thermal/ | grep -c "thermal_zone" 2>/dev/null || echo "0")
    thermal_info="${thermal_info}\"zone_count\":$zones,"
    
    # Check for common thermal paths
    if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
        thermal_info="${thermal_info}\"available\":true,"
    fi
    
    # Check for msm_thermal
    if [ -d "/sys/module/msm_thermal" ]; then
        thermal_info="${thermal_info}\"msm_thermal\":true,"
    fi
    
    # Check for VDD restriction
    if [ -f "/sys/module/msm_thermal/vdd_restriction/enabled" ]; then
        thermal_info="${thermal_info}\"vdd_restriction\":true"
    else
        thermal_info="${thermal_info}\"vdd_restriction\":false"
    fi
    
    thermal_info="${thermal_info}}"
    echo "$thermal_info"
}

# ─── Detect Storage/IO ──────────────────────────────────────────────────────
detect_io() {
    local io_info="{"
    
    # Available schedulers
    local scheduler_path="/sys/block/sda/queue/scheduler"
    if [ -f "$scheduler_path" ]; then
        local schedulers
        schedulers=$(cat "$scheduler_path" 2>/dev/null)
        io_info="${io_info}\"available_schedulers\":\"$schedulers\","
        
        # Current scheduler
        local current
        current=$(echo "$schedulers" | grep -oE '\[.*\]' | tr -d '[]')
        io_info="${io_info}\"current_scheduler\":\"$current\","
    fi
    
    # Read ahead
    local ra_path="/sys/block/sda/queue/read_ahead_kb"
    if [ -f "$ra_path" ]; then
        local ra
        ra=$(cat "$ra_path" 2>/dev/null)
        io_info="${io_info}\"readahead_kb\":$ra,"
    fi
    
    # Check for UFS
    if [ -d "/sys/class/scsi_host/host0" ]; then
        io_info="${io_info}\"storage_type\":\"ufs\","
    elif [ -d "/sys/block/sda" ]; then
        io_info="${io_info}\"storage_type\":\"nvme\","
    fi
    
    # Check for ZRAM
    if [ -d "/sys/block/zram0" ]; then
        io_info="${io_info}\"zram_available\":true"
    else
        io_info="${io_info}\"zram_available\":false"
    fi
    
    io_info="${gpu_info}}"
    echo "$io_info"
}

# ─── Detect Battery ───────────────────────────────────────────────────────────
detect_battery() {
    local batt_info="{"
    
    if [ -d "/sys/class/power_supply/battery" ]; then
        batt_info="${batt_info}\"available\":true,"
        
        # Health
        if [ -f "/sys/class/power_supply/battery/health" ]; then
            local health
            health=$(cat "/sys/class/power_supply/battery/health" 2>/dev/null)
            batt_info="${batt_info}\"health\":\"$health\","
        fi
        
        # Capacity
        if [ -f "/sys/class/power_supply/battery/capacity" ]; then
            local cap
            cap=$(cat "/sys/class/power_supply/battery/capacity" 2>/dev/null)
            batt_info="${batt_info}\"capacity\":$cap,"
        fi
        
        # Bypass charging support
        if [ -f "/sys/class/power_supply/usb/pd_active" ]; then
            batt_info="${batt_info}\"bypass_supported\":true,\"bypass_type\":\"pd\","
        elif [ -f "/sys/class/power_supply/battery/pump_express" ]; then
            batt_info="${batt_info}\"bypass_supported\":true,\"bypass_type\":\"pe\","
        else
            batt_info="${batt_info}\"bypass_supported\":false,"
        fi
        
        batt_info="${batt_info}\"path\":\"/sys/class/power_supply/battery\""
    else
        batt_info="${batt_info}\"available\":false"
    fi
    
    batt_info="${batt_info}}"
    echo "$batt_info"
}

# ─── Detect Display ───────────────────────────────────────────────────────────
detect_display() {
    local disp_info="{"
    
    # Refresh rate
    if [ -f "/sys/class/graphics/fb0/modes" ]; then
        local modes
        modes=$(cat "/sys/class/graphics/fb0/modes" 2>/dev/null)
        disp_info="${disp_info}\"available_modes\":\"$modes\","
    fi
    
    # Brightness
    local brightness_path="/sys/class/leds/lcd-backlight/brightness"
    if [ -f "$brightness_path" ]; then
        disp_info="${disp_info}\"brightness_path\":\"$brightness_path\","
    fi
    
    # DSI display (color control)
    if [ -f "/sys/class/graphics/fb0/dsi_display" ]; then
        disp_info="${disp_info}\"color_control\":true,"
    fi
    
    disp_info="${disp_info}\"path\":\"/sys/class/graphics/fb0\""
    disp_info="${disp_info}}"
    echo "$disp_info"
}

# ─── Detect Device Info ─────────────────────────────────────────────────────
detect_device() {
    local device_info="{"
    
    # Model
    local model
    model=$(getprop ro.product.model 2>/dev/null)
    device_info="${device_info}\"model\":\"$model\","
    
    # Manufacturer
    local manufacturer
    manufacturer=$(getprop ro.product.manufacturer 2>/dev/null)
    device_info="${device_info}\"manufacturer\":\"$manufacturer\","
    
    # Android version
    local android
    android=$(getprop ro.build.version.release 2>/dev/null)
    device_info="${device_info}\"android_version\":\"$android\","
    
    # SDK
    local sdk
    sdk=$(getprop ro.build.version.sdk 2>/dev/null)
    device_info="${device_info}\"sdk\":$sdk,"
    
    # Architecture
    local arch
    arch=$(getprop ro.arch || getprop ro.product.cpu.abi | cut -d'-' -f1)
    device_info="${device_info}\"architecture\":\"$arch\","
    
    # Root solution (Magisk/KernelSU)
    local root="unknown"
    if [ -f "/sbin/magisk" ]; then
        root="magisk"
        local version
        version=$(magisk -V 2>/dev/null)
        root="${root} $version"
    elif [ -f "/data/adb/ksu/bin/ksu" ]; then
        root="ksu"
        local version
        version=$(ksu -V 2>/dev/null)
        root="${root} $version"
    fi
    device_info="${device_info}\"root_solution\":\"$root\""
    
    device_info="${device_info}}"
    echo "$device_info"
}

# ─── Full Detection ─────────────────────────────────────────────────────────
detect_all() {
    klog "Starting device detection..."
    
    python3 -c "
import json
import subprocess
import os

def read_file(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except:
        return None

def get_prop(prop):
    try:
        result = subprocess.run(['getprop', prop], capture_output=True, text=True)
        return result.stdout.strip()
    except:
        return 'unknown'

# Build device info
device = {
    'model': get_prop('ro.product.model'),
    'manufacturer': get_prop('ro.product.manufacturer'),
    'android': get_prop('ro.build.version.release'),
    'sdk': get_prop('ro.build.version.sdk'),
    'arch': get_prop('ro.product.cpu.abi'),
    'cpu': {
        'cores': len([f for f in os.listdir('/sys/devices/system/cpu') if f.startswith('cpu')]),
        'governor': read_file('/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor'),
        'available_governors': read_file('/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors'),
    },
    'gpu': {
        'type': 'unknown',
        'path': '/sys/class/kgsl/kgsl-3d0' if os.path.exists('/sys/class/kgsl/kgsl-3d0') else None,
    },
    'memory': {
        'total_mb': int(read_file('/proc/meminfo').split()[1]) // 1024 if read_file('/proc/meminfo') else 0,
    },
    'battery': {
        'health': read_file('/sys/class/power_supply/battery/health'),
        'bypass_supported': os.path.exists('/sys/class/power_supply/usb/pd_active') or os.path.exists('/sys/class/power_supply/battery/pump_express'),
    },
    'thermal': {
        'zones': len([f for f in os.listdir('/sys/class/thermal') if f.startswith('thermal_zone')]),
    }
}

print(json.dumps(device, indent=2))
" > "$DETECT_FILE"
    
    klog "Device detection complete"
    cat "$DETECT_FILE"
}

# ─── Check Available Features ────────────────────────────────────────────────
check_features() {
    local features="{"
    
    # CPU
    features="${features}\"cpu_tuning\":$( [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ] && echo true || echo false),"
    
    # GPU
    features="${features}\"gpu_tuning\":$( [ -d /sys/class/kgsl/kgsl-3d0 ] && echo true || echo false),"
    
    # Memory
    features="${features}\"memory_tuning\":$( [ -f /sys/module/lowmemorykiller/parameters/minfree ] && echo true || echo false),"
    
    # ZRAM
    features="${features}\"zram\":$( [ -d /sys/block/zram0 ] && echo true || echo false),"
    
    # Thermal
    features="${features}\"thermal_control\":$( [ -d /sys/module/msm_thermal ] && echo true || echo false),"
    
    # Battery
    features="${features}\"battery_control\":$( [ -d /sys/class/power_supply/battery ] && echo true || echo false),"
    
    # Display
    features="${features}\"display_tuning\":$( [ -f /sys/class/graphics/fb0/modes ] && echo true || echo false),"
    
    # IO
    features="${features}\"io_tuning\":$( [ -f /sys/block/sda/queue/scheduler ] && echo true || echo false)"
    
    features="${features}}"
    echo "$features"
}

# ─── Main ────────────────────────────────────────────────────────────────────
case "$1" in
    all)
        detect_all
        ;;
    cpu)
        detect_cpu
        ;;
    gpu)
        detect_gpu
        ;;
    memory)
        detect_memory
        ;;
    thermal)
        detect_thermal
        ;;
    io)
        detect_io
        ;;
    battery)
        detect_battery
        ;;
    display)
        detect_display
        ;;
    device)
        detect_device
        ;;
    features)
        check_features
        ;;
    *)
        detect_all
        ;;
esac
