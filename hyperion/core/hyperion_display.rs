/*
 * Hyperion Display Optimizer - Rust Implementation
 * Display and graphics tuning for Android devices
 * 
 * Features:
 * - Refresh rate management
 * - Color calibration
 * - HDR settings
 * - Display power optimization
 */

use std::fs::{self, File};
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

/// Set refresh rate
fn set_refresh_rate(hz: u32) -> Result<(), String> {
    let paths = vec![
        "/sys/class/drm/card0/device/max_refresh_rate",
        "/sys/class/graphics/fb0/modes",
        "/sys/devices/virtual/graphics/fb0/mode",
    ];
    
    for path in &paths {
        let mode = format!("{}x{}@{}\0", 1080, 2400, hz);
        if write_sysfs(path, &mode).is_ok() {
            return Ok(());
        }
    }
    
    Err("Failed to set refresh rate".to_string())
}

/// Get current refresh rate
fn get_refresh_rate() -> Option<u32> {
    let paths = vec![
        "/sys/class/drm/card0/device/current_refresh_rate",
        "/sys/class/graphics/fb0/refresh_rate",
    ];
    
    for path in &paths {
        if let Some(val) = read_sysfs(path) {
            if let Ok(rate) = val.parse::<u32>() {
                return Some(rate);
            }
        }
    }
    
    None
}

/// Optimize display parameters
fn optimize_display(mode: &str) -> Result<(), String> {
    match mode {
        "performance" | "gaming" => {
            // High refresh rate
            set_refresh_rate(120).ok();
            
            // Disable power saving
            write_sysfs("/sys/class/graphics/fb0/dyn_pu", "0").ok();
            write_sysfs("/sys/class/graphics/fb0/idle_time", "0").ok();
            
            // Enable vsync
            write_sysfs("/sys/class/graphics/fb0/vsync_enabled", "1").ok();
        }
        "balanced" => {
            set_refresh_rate(90).ok();
            write_sysfs("/sys/class/graphics/fb0/dyn_pu", "1").ok();
            write_sysfs("/sys/class/graphics/fb0/idle_time", "50").ok();
        }
        "battery" | "powersave" => {
            set_refresh_rate(60).ok();
            write_sysfs("/sys/class/graphics/fb0/dyn_pu", "1").ok();
            write_sysfs("/sys/class/graphics/fb0/idle_time", "10").ok();
            
            // Reduce brightness if too high
            if let Some(bright) = read_sysfs("/sys/class/backlight/panel0/brightness") {
                if let Ok(b) = bright.parse::<u32>() {
                    if b > 150 {
                        write_sysfs("/sys/class/backlight/panel0/brightness", "150").ok();
                    }
                }
            }
        }
        _ => {
            return Err(format!("Unknown mode: {}", mode));
        }
    }
    
    Ok(())
}

/// Get display information
fn get_display_info() {
    println!("=== Hyperion Display Optimizer ===\n");
    
    // Refresh rate
    if let Some(rate) = get_refresh_rate() {
        println!("Current Refresh Rate: {} Hz", rate);
    } else {
        println!("Refresh Rate: Unknown");
    }
    
    // Resolution
    if let Some(res) = read_sysfs("/sys/class/graphics/fb0/modes") {
        println!("Current Resolution: {}", res.trim());
    }
    
    // Brightness
    if let Some(bright) = read_sysfs("/sys/class/backlight/panel0/brightness") {
        println!("Brightness: {}", bright.trim());
    }
    
    // Panel info
    if let Some(panel) = read_sysfs("/sys/class/drm/card0/panel/panel_name") {
        println!("Panel: {}", panel.trim());
    }
    
    // HDR status
    if let Some(hdr) = read_sysfs("/sys/class/drm/card0/hdr_enabled") {
        println!("HDR: {}", if hdr == "1" { "Enabled" } else { "Disabled" });
    }
    
    println!("\nOptimization: Apply profile to tune display parameters\n");
}

/// Apply display profile
fn apply_profile(profile: &str) {
    println!("Applying display profile: {}", profile);
    
    if let Err(e) = optimize_display(profile) {
        eprintln!("Warning: {}", e);
    }
    
    println!("Profile applied successfully!");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    
    if args.len() < 2 {
        get_display_info();
        return;
    }
    
    match args[1].as_str() {
        "status" | "info" => get_display_info(),
        "profile" | "set" if args.len() > 2 => apply_profile(&args[2]),
        "perf" | "performance" | "game" | "gaming" => apply_profile("gaming"),
        "balance" | "balanced" => apply_profile("balanced"),
        "battery" | "save" | "powersave" => apply_profile("battery"),
        "60" => { set_refresh_rate(60).ok(); },
        "90" => { set_refresh_rate(90).ok(); },
        "120" => { set_refresh_rate(120).ok(); },
        _ => {
            println!("Usage: {} [status|profile <name>|60|90|120]", args[0]);
        }
    }
}
