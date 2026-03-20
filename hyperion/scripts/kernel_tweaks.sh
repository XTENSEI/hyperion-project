#!/system/bin/sh
# =============================================================================
# Hyperion Project - Advanced Kernel Tweaks
# Made by ShadowBytePrjkt
# =============================================================================
# Advanced kernel-level optimizations including eBPF, binder, and ion tweaks
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/kernel.log"

klog() {
    echo "[$(date -u +%H:%M:%S)][KERNEL] $1" | tee -a "$LOG_FILE"
}

write() {
    [ -f "$1" ] && [ -w "$1" ] && echo "$2" > "$1" 2>/dev/null
}

# ─── Binder Tuning ────────────────────────────────────────────────────────────
tune_binder() {
    local mode="$1"
    klog "Tuning binder: $mode"

    # Binder transactions
    for node in /sys/module/binder*/parameters/*; do
        [ -f "$node" ] && chmod 666 "$node" 2>/dev/null
    done

    # Binder memory
    write /sys/module/binder/parameters binder_size "1048576"
    write /sys/module/binder/parameters binder_async_size "1048576"

    # Binder transactions limits
    write /sys/module/binder/parameters max_pagesoftlimit "4096"
    write /sys/module/binder/parameters max_readpages "32"

    klog "Binder tuned for $mode"
}

# ─── ION Heap Tuning ──────────────────────────────────────────────────────────
tune_ion() {
    local mode="$1"
    klog "Tuning ION heap: $mode"

    # List available heaps
    for heap in /sys/class/ion/*; do
        [ -d "$heap" ] || continue
        local name
        name=$(basename "$heap")

        case "$mode" in
            performance)
                # Pre-allocate for gaming
                for pool in "$heap"/"$name"_pool; do
                    [ -d "$pool" ] && write "${pool}/min_size" "8192"
                done
                ;;
            powersave)
                # Reduce memory
                for pool in "$heap"/"$name"_pool; do
                    [ -d "$pool" ] && write "${pool}/min_size" "1024"
                done
                ;;
        esac
    done

    klog "ION heap tuned for $mode"
}

# ─── Scheduler Tuning ──────────────────────────────────────────────────────────
tune_scheduler() {
    local mode="$1"
    klog "Tuning scheduler: $mode"

    # CFS
    case "$mode" in
        performance)
            write /proc/sys/kernel/sched_latency_ns "1000000"
            write /proc/sys/kernel/sched_min_granularity_ns "100000"
            write /proc/sys/kernel/sched_wakeup_granularity_ns "500000"
            ;;
        powersave)
            write /proc/sys/kernel/sched_latency_ns "20000000"
            write /proc/sys/kernel/sched_min_granularity_ns "2000000"
            write /proc/sys/kernel/sched_wakeup_granularity_ns "4000000"
            ;;
    esac

    # Enable schedutil everywhere
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$cpu" ] && echo "schedutil" > "$cpu" 2>/dev/null
    done

    klog "Scheduler tuned for $mode"
}

# ─── TCP/Network Tuning ────────────────────────────────────────────────────────
tune_tcp_advanced() {
    local mode="$1"
    klog "Tuning TCP: $mode"

    # TCP fastopen
    sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null

    # TCP mem
    case "$mode" in
        performance)
            sysctl -w net.core.rmem_max=16777216
            sysctl -w net.core.wmem_max=16777216
            sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216"
            sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216"
            sysctl -w net.ipv4.tcp_low_latency=1
            sysctl -w net.ipv4.tcp_tw_reuse=1
            ;;
        powersave)
            sysctl -w net.core.rmem_max=2097152
            sysctl -w net.core.wmem_max=2097152
            sysctl -w net.ipv4.tcp_rmem="4096 16384 2097152"
            sysctl -w net.ipv4.tcp_wmem="4096 16384 2097152"
            sysctl -w net.ipv4.tcp_low_latency=0
            ;;
    esac

    # TCP congestion
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null

    klog "TCP tuned for $mode"
}

# ─── Virtual Memory Tuning ────────────────────────────────────────────────────
tune_vm_advanced() {
    local mode="$1"
    klog "Tuning VM: $mode"

    case "$mode" in
        performance)
            # Reduce watermark
            sysctl -w vm.min_free_kbytes=8192
            sysctl -w vm.extra_free_kbytes=24576
            # Faster compaction
            sysctl -w vm.compaction_proactiveness=0
            # Enable readahead
            sysctl -v vm.readahead=128 2>/dev/null
            ;;
        powersave)
            sysctl -w vm.min_free_kbytes=2048
            sysctl -w vm.compaction_proactiveness=40
            ;;
    esac

    # Always tune these
    sysctl -w vm.vfs_cache_pressure=100
    sysctl -w vm.dirty_ratio=30
    sysctl -w vm.dirty_background_ratio=10
    sysctl -w vm.dirty_expire_centisecs=3000

    klog "VM tuned for $mode"
}

# ─── Security Hardening ───────────────────────────────────────────────────────
harden_security() {
    klog "Applying security hardening..."

    # Disable core dumps
    sysctl -w kernel.core_pattern=/dev/null
    ulimit -c 0

    # Disable unused protocols
    sysctl -w net.ipv4.conf.all.accept_source_route=0
    sysctl -w net.ipv6.conf.all.accept_source_route=0
    sysctl -w net.ipv4.conf.all.accept_redirects=0
    sysctl -w net.ipv6.conf.all.accept_redirects=0
    sysctl -w net.ipv4.conf.all.send_redirects=0
    sysctl -w net.ipv4.conf.all.rp_filter=1

    # Randomize memory
    sysctl -w kernel.randomize_va_space=2

    klog "Security hardening applied"
}

# ─── Governor Specific Tweaks ─────────────────────────────────────────────────
tune_governor_specific() {
    local gov="$1"
    klog "Applying $gov governor specific tweaks"

    case "$gov" in
        performance)
            # Performance governor - disable energy efficiency
            for node in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
                [ -f "$node" ] && echo "performance" > "$node" 2>/dev/null
            done
            ;;
        powersave)
            for node in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
                [ -f "$node" ] && echo "power" > "$node" 2>/dev/null
            done
            ;;
        schedutil)
            for node in /sys/devices/system/cpu/cpu*/cpufreq/schedutil/; do
                [ -d "$node" ] || continue
                write "${node}rate_limit_us" "500"
                write "${node}hispeed_load" "85"
            done
            ;;
    esac

    klog "$gov specific tweaks applied"
}

# ─── Main ────────────────────────────────────────────────────────────────────
apply_advanced() {
    local profile="$1"
    klog "Applying advanced kernel tweaks for: $profile"

    case "$profile" in
        gaming|performance)
            tune_binder "performance"
            tune_ion "performance"
            tune_scheduler "performance"
            tune_tcp_advanced "performance"
            tune_vm_advanced "performance"
            tune_governor_specific "performance"
            ;;
        battery|powersave)
            tune_binder "powersave"
            tune_ion "powersave"
            tune_scheduler "powersave"
            tune_tcp_advanced "powersave"
            tune_vm_advanced "powersave"
            tune_governor_specific "powersave"
            ;;
        *)
            klog "Using balanced settings"
            tune_binder "balanced"
            tune_scheduler "balanced"
            tune_tcp_advanced "balanced"
            tune_vm_advanced "balanced"
            ;;
    esac

    # Always apply security
    harden_security

    klog "Advanced kernel tweaks applied for $profile"
}

case "$1" in
    binder)    tune_binder "${2:-balanced}" ;;
    ion)       tune_ion "${2:-balanced}" ;;
    scheduler) tune_scheduler "${2:-balanced}" ;;
    tcp)      tune_tcp_advanced "${2:-balanced}" ;;
    vm)       tune_vm_advanced "${2:-balanced}" ;;
    security) harden_security ;;
    all)      apply_advanced "${2:-balanced}" ;;
    *)        apply_advanced "${1:-balanced}" ;;
esac
