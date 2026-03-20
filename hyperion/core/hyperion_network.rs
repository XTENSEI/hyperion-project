/*
 * Hyperion Network Optimizer - Rust Implementation
 * High-performance network tuning for Android devices
 * 
 * Features:
 * - TCP/IP stack optimization
 * - Buffer size tuning
 * - Connection management
 * - Network latency reduction
 */

use std::fs::{self, File, OpenOptions};
use std::io::{self, Write, Read};
use std::path::Path;

/// Read a value from a sysfs file
fn read_sysfs(path: &str) -> Option<String> {
    let mut file = File::open(path).ok()?;
    let mut contents = String::new();
    file.read_to_string(&mut contents).ok()?;
    Some(contents.trim().to_string())
}

/// Write a value to a sysfs file
fn write_sysfs(path: &str, value: &str) -> Result<(), io::Error> {
    let mut file = OpenOptions::new()
        .write(true)
        .open(path)?;
    file.write_all(value.as_bytes())?;
    Ok(())
}

/// Apply TCP buffer optimization
fn optimize_tcp_buffers() -> Result<(), String> {
    let tcp_params = vec![
        ("/proc/sys/net/core/rmem_default", "262144"),
        ("/proc/sys/net/core/rmem_max", "16777216"),
        ("/proc/sys/net/core/wmem_default", "262144"),
        ("/proc/sys/net/core/wmem_max", "16777216"),
        ("/proc/sys/net/ipv4/tcp_rmem", "4096 87380 16777216"),
        ("/proc/sys/net/ipv4/tcp_wmem", "4096 65536 16777216"),
        ("/proc/sys/net/ipv4/tcp_mem", "94500000 915000000 927000000"),
        ("/proc/sys/net/ipv4/tcp_slow_start_after_idle", "0"),
        ("/proc/sys/net/ipv4/tcp_tw_reuse", "1"),
        ("/proc/sys/net/ipv4/tcp_fack", "1"),
        ("/proc/sys/net/ipv4/tcp_window_scaling", "1"),
    ];
    
    for (path, value) in tcp_params {
        if let Err(e) = write_sysfs(path, value) {
            eprintln!("Warning: Failed to set {}: {}", path, e);
        }
    }
    
    Ok(())
}

/// Apply network connection tuning
fn optimize_connections() -> Result<(), String> {
    let conn_params = vec![
        ("/proc/sys/net/netfilter/nf_conntrack_max", "1048576"),
        ("/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established", "7200"),
        ("/proc/sys/net/ipv4/ipfrag_high_thresh", "8388608"),
        ("/proc/sys/net/ipv4/ipfrag_low_thresh", "7340032"),
        ("/proc/sys/net/ipv4/ipfrag_time", "60"),
    ];
    
    for (path, value) in conn_params {
        if let Err(e) = write_sysfs(path, value) {
            eprintln!("Warning: Failed to set {}: {}", path, e);
        }
    }
    
    Ok(())
}

/// Optimize WiFi settings
fn optimize_wifi() -> Result<(), String> {
    let wifi_params = vec![
        ("/sys/module/wlan/parameters/fwlogmask", "0"),
        ("/sys/module/wlan/parameters/ant_div", "0"),
        ("/sys/kernel/debug/wlan/assoc_reject", "0"),
    ];
    
    for (path, value) in wifi_params {
        if let Err(e) = write_sysfs(path, value) {
            eprintln!("Debug: {} not available: {}", path, e);
        }
    }
    
    Ok(())
}

/// Display network status
fn show_status() {
    println!("=== Hyperion Network Optimizer ===\n");
    
    // TCP parameters
    let tcp_params = vec![
        "/proc/sys/net/core/rmem_max",
        "/proc/sys/net/core/wmem_max",
        "/proc/sys/net/ipv4/tcp_rmem",
        "/proc/sys/net/ipv4/tcp_wmem",
    ];
    
    println!("TCP Buffer Settings:");
    for param in &tcp_params {
        if let Some(value) = read_sysfs(param) {
            let name = param.split('/').last().unwrap_or(param);
            println!("  {}: {}", name, value);
        }
    }
    
    // Connection tracking
    if let Some(ct_max) = read_sysfs("/proc/sys/net/netfilter/nf_conntrack_max") {
        println!("\nConnection Tracking: {}", ct_max);
    }
    
    // Network statistics
    println!("\nNetwork Statistics:");
    if let Some(established) = read_sysfs("/proc/net/nf_conntrack") {
        let count = established.lines().count();
        println!("  Active Connections: {}", count);
    }
    
    println!("\nOptimization: Apply profile to tune network parameters\n");
}

/// Apply network profile
fn apply_profile(profile: &str) {
    println!("Applying network profile: {}", profile);
    
    match profile {
        "performance" | "gaming" => {
            optimize_tcp_buffers().ok();
            optimize_connections().ok();
            optimize_wifi().ok();
            write_sysfs("/proc/sys/net/ipv4/tcp_congestion_control", "bbr").ok();
        }
        "balanced" => {
            optimize_tcp_buffers().ok();
            optimize_connections().ok();
            write_sysfs("/proc/sys/net/ipv4/tcp_congestion_control", "cubic").ok();
        }
        "battery" | "powersave" => {
            write_sysfs("/proc/sys/net/ipv4/tcp_congestion_control", "cubic").ok();
            write_sysfs("/proc/sys/net/ipv4/tcp_slow_start_after_idle", "1").ok();
        }
        _ => {
            println!("Unknown profile: {}", profile);
            return;
        }
    }
    
    println!("Profile applied successfully!");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    
    if args.len() < 2 {
        show_status();
        return;
    }
    
    match args[1].as_str() {
        "status" => show_status(),
        "profile" if args.len() > 2 => apply_profile(&args[2]),
        "perf" | "performance" => apply_profile("performance"),
        "game" | "gaming" => apply_profile("gaming"),
        "balance" | "balanced" => apply_profile("balanced"),
        "battery" => apply_profile("battery"),
        "save" | "powersave" => apply_profile("powersave"),
        _ => {
            println!("Usage: {} [status|profile <name>|perf|game|balance|battery|save]", 
                    args[0]);
        }
    }
}
