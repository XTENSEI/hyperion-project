#!/system/bin/sh
# =============================================================================
# Hyperion Project - Virtual Memory & Kernel Parameter Tuning
# Made by ShadowBytePrjkt
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/vm.log"

vmlog() {
    local level="$1"; local msg="$2"
    local ts; ts=$(date -u +%H:%M:%S)
    echo "[$ts][VM][$level] $msg" >> "$LOG_FILE"
    echo "[$ts][VM][$level] $msg"
}

write() {
    local path="$1"; local value="$2"
    [ -f "$path" ] && [ -w "$path" ] && echo "$value" > "$path" 2>/dev/null
}

sysctl_set() {
    local key="$1"; local value="$2"
    sysctl -w "${key}=${value}" 2>/dev/null || write "/proc/sys/$(echo $key | tr '.' '/')" "$value"
}

# ─── Kernel Scheduler Tuning ──────────────────────────────────────────────────
tune_scheduler() {
    local mode="$1"

    case "$mode" in
        performance)
            # Reduce scheduler latency for better responsiveness
            sysctl_set "kernel.sched_latency_ns" "1000000"
            sysctl_set "kernel.sched_min_granularity_ns" "100000"
            sysctl_set "kernel.sched_wakeup_granularity_ns" "500000"
            sysctl_set "kernel.sched_migration_cost_ns" "500000"
            sysctl_set "kernel.sched_nr_migrate" "64"
            sysctl_set "kernel.sched_child_runs_first" "1"
            # Disable scheduler statistics (reduce overhead)
            sysctl_set "kernel.sched_schedstats" "0"
            vmlog "INFO" "Scheduler: performance (low latency)"
            ;;
        balanced)
            sysctl_set "kernel.sched_latency_ns" "10000000"
            sysctl_set "kernel.sched_min_granularity_ns" "1000000"
            sysctl_set "kernel.sched_wakeup_granularity_ns" "2000000"
            sysctl_set "kernel.sched_migration_cost_ns" "500000"
            sysctl_set "kernel.sched_nr_migrate" "32"
            vmlog "INFO" "Scheduler: balanced"
            ;;
        powersave)
            sysctl_set "kernel.sched_latency_ns" "20000000"
            sysctl_set "kernel.sched_min_granularity_ns" "2000000"
            sysctl_set "kernel.sched_wakeup_granularity_ns" "4000000"
            sysctl_set "kernel.sched_migration_cost_ns" "1000000"
            sysctl_set "kernel.sched_nr_migrate" "8"
            vmlog "INFO" "Scheduler: powersave"
            ;;
    esac
}

# ─── Huge Pages ───────────────────────────────────────────────────────────────
tune_hugepages() {
    local mode="$1"

    if [ -d "/sys/kernel/mm/transparent_hugepage" ]; then
        case "$mode" in
            performance)
                write "/sys/kernel/mm/transparent_hugepage/enabled" "always"
                write "/sys/kernel/mm/transparent_hugepage/defrag" "defer+madvise"
                vmlog "INFO" "THP: always"
                ;;
            balanced)
                write "/sys/kernel/mm/transparent_hugepage/enabled" "madvise"
                write "/sys/kernel/mm/transparent_hugepage/defrag" "madvise"
                vmlog "INFO" "THP: madvise"
                ;;
            powersave)
                write "/sys/kernel/mm/transparent_hugepage/enabled" "never"
                vmlog "INFO" "THP: never"
                ;;
        esac
    fi
}

# ─── Memory Compaction ────────────────────────────────────────────────────────
tune_compaction() {
    local mode="$1"

    case "$mode" in
        performance)
            sysctl_set "vm.compaction_proactiveness" "0"
            sysctl_set "vm.compact_unevictable_allowed" "0"
            ;;
        balanced)
            sysctl_set "vm.compaction_proactiveness" "20"
            sysctl_set "vm.compact_unevictable_allowed" "1"
            ;;
        powersave)
            sysctl_set "vm.compaction_proactiveness" "40"
            sysctl_set "vm.compact_unevictable_allowed" "1"
            ;;
    esac
}

# ─── Kernel Panic & Watchdog ──────────────────────────────────────────────────
tune_stability() {
    # Disable kernel panic on oops (more stable)
    sysctl_set "kernel.panic_on_oops" "0"
    sysctl_set "kernel.panic" "0"

    # Disable hung task detection (reduces overhead)
    sysctl_set "kernel.hung_task_timeout_secs" "0"

    # Disable NMI watchdog
    sysctl_set "kernel.nmi_watchdog" "0"
    sysctl_set "kernel.watchdog" "0"

    vmlog "INFO" "Stability tuning applied"
}

# ─── Entropy Pool ─────────────────────────────────────────────────────────────
tune_entropy() {
    # Reduce entropy requirements (faster crypto operations)
    sysctl_set "kernel.random.read_wakeup_threshold" "64"
    sysctl_set "kernel.random.write_wakeup_threshold" "128"
    vmlog "INFO" "Entropy pool tuned"
}

# ─── Printk & Logging ─────────────────────────────────────────────────────────
tune_logging() {
    local mode="$1"

    case "$mode" in
        performance)
            # Reduce kernel logging overhead
            sysctl_set "kernel.printk" "3 3 1 3"
            sysctl_set "kernel.printk_ratelimit" "0"
            ;;
        *)
            sysctl_set "kernel.printk" "4 4 1 4"
            ;;
    esac
}

# ─── Apply Profile ────────────────────────────────────────────────────────────
apply_profile() {
    local profile="$1"
    vmlog "INFO" "Applying VM/kernel profile: $profile"

    case "$profile" in
        gaming|performance)
            tune_scheduler "performance"
            tune_hugepages "performance"
            tune_compaction "performance"
            tune_logging "performance"
            # Disable ASLR for slight performance gain (security tradeoff)
            # sysctl_set "kernel.randomize_va_space" "0"  # Commented: security risk
            # Perf events
            sysctl_set "kernel.perf_event_paranoid" "1"
            sysctl_set "kernel.perf_cpu_time_max_percent" "25"
            vmlog "INFO" "Gaming/Performance VM profile applied"
            ;;
        balanced)
            tune_scheduler "balanced"
            tune_hugepages "balanced"
            tune_compaction "balanced"
            tune_logging "balanced"
            vmlog "INFO" "Balanced VM profile applied"
            ;;
        battery|powersave)
            tune_scheduler "powersave"
            tune_hugepages "powersave"
            tune_compaction "powersave"
            tune_logging "balanced"
            vmlog "INFO" "Battery VM profile applied"
            ;;
    esac

    # Always apply these
    tune_stability
    tune_entropy

    # Disable core dumps (saves I/O)
    sysctl_set "kernel.core_pattern" "/dev/null"
    ulimit -c 0 2>/dev/null

    vmlog "INFO" "VM profile '$profile' applied"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
PROFILE="${1:-balanced}"
apply_profile "$PROFILE"
