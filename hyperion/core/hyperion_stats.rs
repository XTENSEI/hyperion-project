// =============================================================================
// Hyperion Project - Rust Stats Daemon
// Made by ShadowBytePrjkt
// =============================================================================
// High-performance system stats fetcher using Rust
// Compiled to native arm64 binary for maximum performance
// =============================================================================

use std::fs::{self, File};
use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use std::collections::HashMap;

// JSON output structure
#[derive(serde::Serialize)]
struct SystemStats {
    cpu: CpuStats,
    gpu: GpuStats,
    memory: MemoryStats,
    battery: BatteryStats,
    thermal: ThermalStats,
    io: IoStats,
    timestamp: u64,
}

#[derive(serde::Serialize)]
struct CpuStats {
    freq: u32,
    governor: String,
    cores: u32,
    usage: f32,
}

#[derive(serde::Serialize)]
struct GpuStats {
    freq: u32,
    available: bool,
}

#[derive(serde::Serialize)]
struct MemoryStats {
    total_mb: u32,
    available_mb: u32,
    used_percent: u32,
    swap_mb: u32,
}

#[derive(serde::Serialize)]
struct BatteryStats {
    percent: u32,
    temperature: f32,
    voltage: u32,
    charging: bool,
    health: String,
}

#[derive(serde::Serialize)]
struct ThermalStats {
    cpu_temp: f32,
    gpu_temp: f32,
    battery_temp: f32,
}

#[derive(serde::Serialize)]
struct IoStats {
    read_speed: u32,
    write_speed: u32,
}

// Read a file and return its contents as string
fn read_file_value(path: &str) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}

// Get CPU frequency in MHz
fn get_cpu_freq() -> u32 {
    if let Some(val) = read_file_value("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq") {
        return val.parse::<u32>().unwrap_or(0) / 1000;
    }
    0
}

// Get CPU governor
fn get_cpu_governor() -> String {
    read_file_value("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
        .unwrap_or_else(|| "unknown".to_string())
}

// Get number of CPU cores
fn get_cpu_cores() -> u32 {
    fs::read_dir("/sys/devices/system/cpu")
        .map(|entries| {
            entries
                .filter_map(|e| e.ok())
                .filter(|e| e.path().to_string_lossy().starts_with("/sys/devices/system/cpu/cpu"))
                .count() as u32
        })
        .unwrap_or(8)
}

// Calculate CPU usage from /proc/stat
fn get_cpu_usage() -> f32 {
    let file = match File::open("/proc/stat") {
        Ok(f) => f,
        Err(_) => return 0.0,
    };
    
    let reader = BufReader::new(file);
    let mut lines = reader.lines();
    
    if let Some(Ok(line)) = lines.next() {
        if line.starts_with("cpu ") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 5 {
                let user: u64 = parts[1].parse().unwrap_or(0);
                let nice: u64 = parts[2].parse().unwrap_or(0);
                let system: u64 = parts[3].parse().unwrap_or(0);
                let idle: u64 = parts[4].parse().unwrap_or(0);
                
                let total = user + nice + system + idle;
                if total > 0 {
                    return ((total - idle) as f32 / total as f32) * 100.0;
                }
            }
        }
    }
    0.0
}

// Get GPU stats
fn get_gpu_stats() -> GpuStats {
    let gpu_path = "/sys/class/kgsl/kgsl-3d0";
    let available = Path::new(gpu_path).exists();
    
    let freq = if available {
        read_file_value(format!("{}/gpuclk", gpu_path))
            .and_then(|s| s.parse::<u64>().ok())
            .map(|v| (v / 1_000_000) as u32)
            .unwrap_or(0)
    } else {
        0
    };
    
    GpuStats { freq, available }
}

// Get memory stats
fn get_memory_stats() -> MemoryStats {
    let file = match File::open("/proc/meminfo") {
        Ok(f) => f,
        Err(_) => return MemoryStats::default(),
    };
    
    let reader = BufReader::new(file);
    let mut mem_total: u32 = 0;
    let mut mem_available: u32 = 0;
    let mut swap_total: u32 = 0;
    
    for line in reader.lines().filter_map(|l| l.ok()) {
        if line.starts_with("MemTotal:") {
            mem_total = line.split_whitespace()
                .nth(1)
                .and_then(|s| s.parse().ok())
                .unwrap_or(0) / 1024;
        } else if line.starts_with("MemAvailable:") {
            mem_available = line.split_whitespace()
                .nth(1)
                .and_then(|s| s.parse().ok())
                .unwrap_or(0) / 1024;
        } else if line.starts_with("SwapTotal:") {
            swap_total = line.split_whitespace()
                .nth(1)
                .and_then(|s| s.parse().ok())
                .unwrap_or(0) / 1024;
        }
    }
    
    let used_percent = if mem_total > 0 {
        ((mem_total - mem_available) * 100 / mem_total) as u32
    } else {
        0
    };
    
    MemoryStats {
        total_mb: mem_total,
        available_mb: mem_available,
        used_percent,
        swap_mb: swap_total,
    }
}

impl Default for MemoryStats {
    fn default() -> Self {
        Self {
            total_mb: 0,
            available_mb: 0,
            used_percent: 0,
            swap_mb: 0,
        }
    }
}

// Get battery stats
fn get_battery_stats() -> BatteryStats {
    let battery_path = "/sys/class/power_supply/battery";
    
    let percent = read_file_value(format!("{}/capacity", battery_path))
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);
    
    let temperature = read_file_value(format!("{}/temp", battery_path))
        .and_then(|s| s.parse::<u32>().ok())
        .map(|t| t as f32 / 10.0)
        .unwrap_or(0.0);
    
    let voltage = read_file_value(format!("{}/voltage_now", battery_path))
        .and_then(|s| s.parse::<u32>().ok())
        .map(|v| v / 1000)
        .unwrap_or(0);
    
    let status = read_file_value(format!("{}/status", battery_path))
        .unwrap_or_else(|| "Unknown".to_string());
    
    let charging = status.to_lowercase().contains("charging");
    
    let health = read_file_value(format!("{}/health", battery_path))
        .unwrap_or_else(|| "Unknown".to_string());
    
    BatteryStats {
        percent,
        temperature,
        voltage,
        charging,
        health,
    }
}

// Get thermal stats
fn get_thermal_stats() -> ThermalStats {
    let cpu_temp = read_file_value("/sys/class/thermal/thermal_zone0/temp")
        .and_then(|s| s.parse::<u32>().ok())
        .map(|t| t as f32 / 1000.0)
        .unwrap_or(0.0);
    
    let battery_temp = read_file_value("/sys/class/thermal/thermal_zone1/temp")
        .and_then(|s| s.parse::<u32>().ok())
        .map(|t| t as f32 / 1000.0)
        .unwrap_or(0.0);
    
    // Try to find GPU temp
    let gpu_temp = read_file_value("/sys/class/thermal/thermal_zone2/temp")
        .and_then(|s| s.parse::<u32>().ok())
        .map(|t| t as f32 / 1000.0)
        .unwrap_or(cpu_temp);
    
    ThermalStats {
        cpu_temp,
        gpu_temp,
        battery_temp,
    }
}

// Get I/O stats
fn get_io_stats() -> IoStats {
    // Simple I/O stats - could be enhanced with /proc/diskstats
    IoStats {
        read_speed: 0,
        write_speed: 0,
    }
}

// Collect all stats
fn collect_stats() -> SystemStats {
    SystemStats {
        cpu: CpuStats {
            freq: get_cpu_freq(),
            governor: get_cpu_governor(),
            cores: get_cpu_cores(),
            usage: get_cpu_usage(),
        },
        gpu: get_gpu_stats(),
        memory: get_memory_stats(),
        battery: get_battery_stats(),
        thermal: get_thermal_stats(),
        io: get_io_stats(),
        timestamp: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0),
    }
}

// Write stats to file (IPC with Node.js server)
fn write_stats(stats: &SystemStats) {
    let output_path = "/data/adb/hyperion/data/stats.json";
    
    if let Ok(json) = serde_json::to_string(stats) {
        let _ = fs::write(output_path, json);
    }
}

fn main() {
    println!("[Hyperion] Rust stats daemon starting...");
    
    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();
    
    // Handle SIGTERM for clean shutdown
    ctrlc::set_handler(move || {
        r.store(false, Ordering::SeqCst);
    }).expect("Error setting Ctrl-C handler");
    
    // Main loop - collect and write stats
    while running.load(Ordering::SeqCst) {
        let stats = collect_stats();
        write_stats(&stats);
        
        // Sleep for 500ms - high frequency updates
        thread::sleep(Duration::from_millis(500));
    }
    
    println!("[Hyperion] Rust stats daemon stopped");
}
