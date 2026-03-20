// =============================================================================
// Hyperion Project - Memory Optimizer (Rust)
// Made by ShadowBytePrjkt
// =============================================================================
// High-performance memory management using Rust
// =============================================================================

use std::fs;
use std::process::Command;

/// Write to a file
fn write_file(path: &str, value: &str) -> bool {
    fs::write(path, value).is_ok()
}

/// Read from a file
fn read_file(path: &str) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}

/// Set swappiness
fn set_swappiness(value: u32) {
    if write_file("/proc/sys/vm/swappiness", &value.to_string()) {
        println!("Swappiness set to: {}", value);
    } else {
        eprintln!("Failed to set swappiness");
    }
}

/// Drop caches
fn drop_caches() {
    // Sync first
    let _ = Command::new("sync").output();
    
    if write_file("/proc/sys/vm/drop_caches", "3") {
        println!("Caches dropped successfully");
    } else {
        eprintln!("Failed to drop caches");
    }
}

/// Set memory pressure
fn set_memory_pressure(level: &str) {
    let value = match level {
        "light" => 200,
        "moderate" => 150,
        "aggressive" => 100,
        "extreme" => 50,
        _ => 100,
    };
    
    if write_file("/proc/sys/vm/vfs_cache_pressure", &value.to_string()) {
        println!("Memory pressure set to: {} ({})", value, level);
    }
}

/// Enable/disable KSM
fn set_ksm(enable: bool) {
    let value = if enable { "1" } else { "0" };
    
    if write_file("/sys/kernel/mm/ksm/run", value) {
        println!("KSM {}", if enable { "enabled" } else { "disabled" });
    } else {
        eprintln!("Failed to set KSM");
    }
}

/// Show memory info
fn show_info() {
    println!("=== Memory Information ===");
    
    // Read meminfo
    if let Ok(content) = fs::read_to_string("/proc/meminfo") {
        for line in content.lines() {
            if line.starts_with("MemTotal:") ||
               line.starts_with("MemFree:") ||
               line.starts_with("MemAvailable:") ||
               line.starts_with("Buffers:") ||
               line.starts_with("Cached:") ||
               line.starts_with("SwapTotal:") ||
               line.starts_with("SwapFree:") {
                println!("{}", line);
            }
        }
    }
    
    // KSM status
    if let Some(status) = read_file("/sys/kernel/mm/ksm/run") {
        println!("KSM: {}", if status == "1" { "enabled" } else { "disabled" });
    }
    
    // Swappiness
    if let Some(swap) = read_file("/proc/sys/vm/swappiness") {
        println!("Swappiness: {}", swap);
    }
}

/// Memory modes
fn mode_light() {
    set_swappiness(80);
    set_memory_pressure("light");
    set_ksm(false);
    println!("=== LIGHT MODE ===");
}

fn mode_balanced() {
    set_swappiness(60);
    set_memory_pressure("moderate");
    set_ksm(true);
    println!("=== BALANCED MODE ===");
}

fn mode_aggressive() {
    set_swappiness(30);
    set_memory_pressure("aggressive");
    set_ksm(true);
    drop_caches();
    println!("=== AGGRESSIVE MODE ===");
}

fn mode_extreme() {
    set_swappiness(10);
    set_memory_pressure("extreme");
    set_ksm(true);
    drop_caches();
    println!("=== EXTREME MODE ===");
}

fn usage(program: &str) {
    println!("Hyperion Memory Optimizer v1.0");
    println!("Usage: {} <command>", program);
    println!();
    println!("Commands:");
    println!("  info         Show memory information");
    println!("  swap <0-100> Set swappiness");
    println!("  drop         Drop caches");
    println!("  ksm <0|1>    Enable/disable KSM");
    println!("  light        Light mode");
    println!("  balanced     Balanced mode");
    println!("  aggressive   Aggressive mode");
    println!("  extreme      Extreme mode");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    
    if args.len() < 2 {
        usage(&args[0]);
        return;
    }
    
    match args[1].as_str() {
        "info" => show_info(),
        "swap" => {
            if args.len() >= 3 {
                if let Ok(val) = args[2].parse::<u32>() {
                    set_swappiness(val);
                } else {
                    eprintln!("Invalid value: {}", args[2]);
                }
            } else {
                eprintln!("Usage: swap <0-100>");
            }
        }
        "drop" => drop_caches(),
        "ksm" => {
            if args.len() >= 3 {
                set_ksm(args[2] == "1");
            } else {
                eprintln!("Usage: ksm <0|1>");
            }
        }
        "light" => mode_light(),
        "balanced" => mode_balanced(),
        "aggressive" => mode_aggressive(),
        "extreme" => mode_extreme(),
        _ => usage(&args[0]),
    }
}
