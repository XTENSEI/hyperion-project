#!/system/bin/sh
# =============================================================================
# Hyperion Project - Network Optimization Script
# Made by ShadowBytePrjkt
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/network.log"

nlog() {
    local level="$1"; local msg="$2"
    local ts; ts=$(date -u +%H:%M:%S)
    echo "[$ts][NET][$level] $msg" >> "$LOG_FILE"
    echo "[$ts][NET][$level] $msg"
}

write() {
    local path="$1"; local value="$2"
    [ -f "$path" ] && [ -w "$path" ] && echo "$value" > "$path" 2>/dev/null
}

sysctl_set() {
    local key="$1"; local value="$2"
    sysctl -w "${key}=${value}" 2>/dev/null || write "/proc/sys/$(echo $key | tr '.' '/')" "$value"
}

# ─── TCP Congestion Control ───────────────────────────────────────────────────
set_tcp_congestion() {
    local algo="$1"
    local avail
    avail=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)

    if echo "$avail" | grep -qw "$algo"; then
        sysctl_set "net.ipv4.tcp_congestion_control" "$algo"
        nlog "INFO" "TCP congestion: $algo"
    else
        # Fallback chain
        for fallback in bbr cubic westwood reno; do
            if echo "$avail" | grep -qw "$fallback"; then
                sysctl_set "net.ipv4.tcp_congestion_control" "$fallback"
                nlog "INFO" "TCP congestion fallback: $fallback"
                break
            fi
        done
    fi
}

# ─── TCP Buffer Sizes ─────────────────────────────────────────────────────────
set_tcp_buffers() {
    local mode="$1"

    case "$mode" in
        performance)
            # Large buffers for high throughput
            sysctl_set "net.core.rmem_max" "16777216"
            sysctl_set "net.core.wmem_max" "16777216"
            sysctl_set "net.core.rmem_default" "262144"
            sysctl_set "net.core.wmem_default" "262144"
            sysctl_set "net.ipv4.tcp_rmem" "4096 87380 16777216"
            sysctl_set "net.ipv4.tcp_wmem" "4096 65536 16777216"
            sysctl_set "net.core.netdev_max_backlog" "5000"
            sysctl_set "net.ipv4.tcp_max_syn_backlog" "8192"
            nlog "INFO" "TCP buffers: performance (16MB)"
            ;;
        balanced)
            sysctl_set "net.core.rmem_max" "4194304"
            sysctl_set "net.core.wmem_max" "4194304"
            sysctl_set "net.core.rmem_default" "131072"
            sysctl_set "net.core.wmem_default" "131072"
            sysctl_set "net.ipv4.tcp_rmem" "4096 87380 4194304"
            sysctl_set "net.ipv4.tcp_wmem" "4096 65536 4194304"
            nlog "INFO" "TCP buffers: balanced (4MB)"
            ;;
        powersave)
            sysctl_set "net.core.rmem_max" "1048576"
            sysctl_set "net.core.wmem_max" "1048576"
            sysctl_set "net.core.rmem_default" "65536"
            sysctl_set "net.core.wmem_default" "65536"
            nlog "INFO" "TCP buffers: powersave (1MB)"
            ;;
    esac
}

# ─── TCP Optimizations ────────────────────────────────────────────────────────
optimize_tcp() {
    local mode="$1"

    # Common optimizations
    sysctl_set "net.ipv4.tcp_fastopen" "3"
    sysctl_set "net.ipv4.tcp_timestamps" "1"
    sysctl_set "net.ipv4.tcp_sack" "1"
    sysctl_set "net.ipv4.tcp_fack" "1"
    sysctl_set "net.ipv4.tcp_window_scaling" "1"
    sysctl_set "net.ipv4.tcp_moderate_rcvbuf" "1"

    case "$mode" in
        performance)
            sysctl_set "net.ipv4.tcp_low_latency" "1"
            sysctl_set "net.ipv4.tcp_no_delay_ack" "1"
            sysctl_set "net.ipv4.tcp_fin_timeout" "15"
            sysctl_set "net.ipv4.tcp_keepalive_time" "300"
            sysctl_set "net.ipv4.tcp_keepalive_intvl" "30"
            sysctl_set "net.ipv4.tcp_keepalive_probes" "5"
            sysctl_set "net.ipv4.tcp_tw_reuse" "1"
            nlog "INFO" "TCP: low latency mode"
            ;;
        balanced)
            sysctl_set "net.ipv4.tcp_low_latency" "0"
            sysctl_set "net.ipv4.tcp_fin_timeout" "30"
            sysctl_set "net.ipv4.tcp_keepalive_time" "600"
            nlog "INFO" "TCP: balanced mode"
            ;;
        powersave)
            sysctl_set "net.ipv4.tcp_low_latency" "0"
            sysctl_set "net.ipv4.tcp_fin_timeout" "60"
            sysctl_set "net.ipv4.tcp_keepalive_time" "1200"
            nlog "INFO" "TCP: powersave mode"
            ;;
    esac
}

# ─── WiFi Power Save ──────────────────────────────────────────────────────────
set_wifi_power_save() {
    local enabled="$1"

    # Find WiFi interface
    local wifi_iface
    for iface in wlan0 wlan1 wifi0; do
        if [ -d "/sys/class/net/$iface" ]; then
            wifi_iface="$iface"
            break
        fi
    done

    if [ -z "$wifi_iface" ]; then
        nlog "WARN" "WiFi interface not found"
        return
    fi

    if [ "$enabled" = "1" ]; then
        iw dev "$wifi_iface" set power_save on 2>/dev/null
        nlog "INFO" "WiFi power save: ON ($wifi_iface)"
    else
        iw dev "$wifi_iface" set power_save off 2>/dev/null
        nlog "INFO" "WiFi power save: OFF ($wifi_iface)"
    fi

    # Qualcomm WiFi power save
    write "/sys/module/wlan/parameters/con_mode" "$enabled"
}

# ─── DNS Cache ────────────────────────────────────────────────────────────────
optimize_dns() {
    # Set DNS cache TTL via system properties
    setprop net.dns1 "8.8.8.8" 2>/dev/null
    setprop net.dns2 "8.8.4.4" 2>/dev/null
    setprop net.dns3 "1.1.1.1" 2>/dev/null

    # Increase DNS cache size
    setprop ro.net.dns_cache_size "512" 2>/dev/null
    setprop ro.net.dns_cache_ttl "300" 2>/dev/null

    nlog "INFO" "DNS cache optimized"
}

# ─── Network Scheduler ────────────────────────────────────────────────────────
set_net_scheduler() {
    local mode="$1"

    # Set network queue discipline
    for iface in $(ls /sys/class/net/ | grep -v "lo\|dummy"); do
        case "$mode" in
            performance)
                tc qdisc replace dev "$iface" root fq 2>/dev/null || \
                tc qdisc replace dev "$iface" root pfifo_fast 2>/dev/null
                ;;
            balanced)
                tc qdisc replace dev "$iface" root fq_codel 2>/dev/null || \
                tc qdisc replace dev "$iface" root pfifo_fast 2>/dev/null
                ;;
        esac
    done
}

# ─── Apply Profile ────────────────────────────────────────────────────────────
apply_profile() {
    local profile="$1"
    nlog "INFO" "Applying network profile: $profile"

    case "$profile" in
        gaming)
            set_tcp_congestion "bbr"
            set_tcp_buffers "performance"
            optimize_tcp "performance"
            set_wifi_power_save "0"
            set_net_scheduler "performance"
            optimize_dns
            # Disable background data throttling
            sysctl_set "net.ipv4.tcp_slow_start_after_idle" "0"
            nlog "INFO" "Gaming network profile applied"
            ;;
        performance)
            set_tcp_congestion "bbr"
            set_tcp_buffers "performance"
            optimize_tcp "performance"
            set_wifi_power_save "0"
            set_net_scheduler "performance"
            optimize_dns
            nlog "INFO" "Performance network profile applied"
            ;;
        balanced)
            set_tcp_congestion "cubic"
            set_tcp_buffers "balanced"
            optimize_tcp "balanced"
            set_wifi_power_save "1"
            set_net_scheduler "balanced"
            nlog "INFO" "Balanced network profile applied"
            ;;
        battery|powersave)
            set_tcp_congestion "westwood"
            set_tcp_buffers "powersave"
            optimize_tcp "powersave"
            set_wifi_power_save "1"
            # Reduce background network activity
            sysctl_set "net.ipv4.tcp_slow_start_after_idle" "1"
            nlog "INFO" "Battery network profile applied"
            ;;
    esac
}

# ─── Main ─────────────────────────────────────────────────────────────────────
PROFILE="${1:-balanced}"
apply_profile "$PROFILE"
