#!/system/bin/sh
# =============================================================================
# Hyperion Control Center - Unified Shell Interface
# Consolidates all optimization scripts into one
# =============================================================================

MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
MODDIR=${MODDIR%/*}
BIN="$MODDIR/system/bin/hyperion"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# === CPU FUNCTIONS ===
cpu_info() {
    echo "=== CPU Information ==="
    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
        [ -f "$cpu/cpufreq/scaling_governor" ] || continue
        gov=$(cat $cpu/cpufreq/scaling_governor 2>/dev/null)
        freq=$(cat $cpu/cpufreq/scaling_cur_freq 2>/dev/null)
        [ -n "$freq" ] && freq=$((freq / 1000)) || freq=0
        echo "CPU${cpu##*/cpu}: $gov @ ${freq}MHz"
    done
}

cpu_set_governor() {
    [ -z "$1" ] && echo "Usage: cpu_set_governor <governor>" && return 1
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$cpu" ] && echo "$1" > "$cpu" 2>/dev/null
    done
    echo "CPU Governor set to: $1"
}

cpu_boost() {
    [ -f "/sys/devices/system/cpu/cpu0/cpufreq/boost" ] && echo 1 > /sys/devices/system/cpu/cpu0/cpufreq/boost
    echo "CPU Boost enabled"
}

cpu_unboost() {
    [ -f "/sys/devices/system/cpu/cpu0/cpufreq/boost" ] && echo 0 > /sys/devices/system/cpu/cpu0/cpufreq/boost
    echo "CPU Boost disabled"
}

# === MEMORY FUNCTIONS ===
mem_info() {
    echo "=== Memory Information ==="
    total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    avail=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    used=$((total - avail))
    pct=$((used * 100 / total))
    echo "Total: $((total / 1024)) MB"
    echo "Available: $((avail / 1024)) MB"
    echo "Used: $((used / 1024)) MB ($pct%)"
}

mem_set_swappiness() {
    [ -z "$1" ] && echo "Usage: mem_set_swappiness <0-100>" && return 1
    echo "$1" > /proc/sys/vm/swappiness 2>/dev/null
    echo "Swappiness set to: $1"
}

mem_drop_caches() {
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    echo "Caches dropped"
}

# === GPU FUNCTIONS ===
gpu_info() {
    echo "=== GPU Information ==="
    # Mali
    if [ -f "/sys/class/misc/mali0/device/utilization" ]; then
        mali=$(cat /sys/class/misc/mali0/device/utilization 2>/dev/null)
        echo "Mali GPU: ${mali}%"
    fi
    # Adreno
    if [ -f "/sys/class/kgsl/kgsl-3d0/gpu_busy" ]; then
        adreno=$(cat /sys/class/kgsl/kgsl-3d0/gpu_busy 2>/dev/null)
        echo "Adreno GPU: ${adreno}%"
    fi
}

gpu_set_max() {
    # Try Mali
    [ -f "/sys/class/misc/mali0/device/freq" ] && echo 0 > /sys/class/misc/mali0/device/freq
    # Try Adreno  
    [ -f "/sys/class/kgsl/kgsl-3d0/max_gpuclk" ] && echo 0 > /sys/class/kgsl/kgsl-3d0/max_gpuclk
    echo "GPU set to maximum"
}

# === I/O FUNCTIONS ===
io_info() {
    echo "=== I/O Schedulers ==="
    for dev in /sys/block/*/queue/scheduler; do
        [ -f "$dev" ] || continue
        name=$(echo $dev | cut -d'/' -f4)
        sched=$(cat $dev 2>/dev/null)
        echo "$name: $sched"
    done
}

io_set_scheduler() {
    [ -z "$1" ] && echo "Usage: io_set_scheduler <scheduler>" && return 1
    for dev in /sys/block/*/queue/scheduler; do
        [ -f "$dev" ] && echo "$1" > "$dev" 2>/dev/null
    done
    echo "I/O Scheduler set to: $1"
}

# === THERMAL FUNCTIONS ===
thermal_info() {
    echo "=== Thermal Zones ==="
    for zone in /sys/class/thermal/thermal_zone*; do
        [ -f "$zone/temp" ] || continue
        type=$(cat $zone/type 2>/dev/null)
        temp=$(cat $zone/temp 2>/dev/null)
        [ -n "$temp" ] && temp=$((temp / 1000)) || temp=0
        echo "Zone: $type - ${temp}°C"
    done
}

# === BATTERY FUNCTIONS ===
battery_info() {
    echo "=== Battery Information ==="
    level=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)
    status=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
    temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)
    [ -n "$temp" ] && temp=$((temp / 10)) || temp=0
    echo "Level: ${level}%"
    echo "Status: $status"
    echo "Temperature: ${temp}°C"
}

# === BOOST FUNCTIONS ===
boost_enable() {
    cpu_set_governor performance
    cpu_boost
    mem_set_swappiness 10
    io_set_scheduler noop
    echo "=== BOOST MODE ENABLED ==="
}

boost_disable() {
    cpu_set_governor schedutil
    cpu_unboost
    mem_set_swappiness 60
    io_set_scheduler cfq
    echo "=== BOOST MODE DISABLED ==="
}

# === MAIN ===
case "$1" in
    cpu)
        case "$2" in
            info) cpu_info ;;
            gov) cpu_set_governor "$3" ;;
            boost) cpu_boost ;;
            unboost) cpu_unboost ;;
            *) cpu_info ;;
        esac
        ;;
    mem)
        case "$2" in
            info) mem_info ;;
            swap) mem_set_swappiness "$3" ;;
            drop) mem_drop_caches ;;
            *) mem_info ;;
        esac
        ;;
    gpu)
        case "$2" in
            info) gpu_info ;;
            max) gpu_set_max ;;
            *) gpu_info ;;
        esac
        ;;
    io)
        case "$2" in
            info) io_info ;;
            set) io_set_scheduler "$3" ;;
            *) io_info ;;
        esac
        ;;
    thermal)
        thermal_info
        ;;
    battery)
        battery_info
        ;;
    boost)
        boost_enable
        ;;
    unboost)
        boost_disable
        ;;
    all)
        cpu_info
        mem_info
        gpu_info
        io_info
        thermal_info
        battery_info
        ;;
    *)
        echo "Hyperion Control Center"
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  cpu [info|gov <name>|boost|unboost]"
        echo "  mem [info|swap <0-100>|drop]"
        echo "  gpu [info|max]"
        echo "  io [info|set <scheduler>]"
        echo "  thermal"
        echo "  battery"
        echo "  boost"
        echo "  unboost"
        echo "  all"
        ;;
esac
