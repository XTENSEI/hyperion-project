/*
 * Hyperion Thermal Manager - C Implementation
 * Optimized thermal management for Android devices
 * 
 * Features:
 * - Real-time temperature monitoring
 * - Thermal zone management
 * - CPU throttling control
 * - Performance optimization
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <sys/types.h>
#include <sys/stat.h>

#define MAX_PATH 256
#define MAX_TEMP 10

typedef struct {
    char name[64];
    char path[MAX_PATH];
    int temp;
} thermal_zone_t;

static thermal_zone_t thermal_zones[MAX_TEMP];
static int zone_count = 0;

// Read integer from file
static int read_int(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    
    char buf[32] = {0};
    read(fd, buf, sizeof(buf) - 1);
    close(fd);
    
    return atoi(buf);
}

// Write integer to file
static int write_int(const char *path, int value) {
    int fd = open(path, O_WRONLY);
    if (fd < 0) return -1;
    
    char buf[32];
    snprintf(buf, sizeof(buf), "%d", value);
    write(fd, buf, strlen(buf));
    close(fd);
    
    return 0;
}

// Scan thermal zones
static void scan_thermal_zones(void) {
    DIR *dir = opendir("/sys/class/thermal");
    if (!dir) return;
    
    struct dirent *entry;
    zone_count = 0;
    
    while ((entry = readdir(dir)) && zone_count < MAX_TEMP) {
        if (strncmp(entry->d_name, "thermal_zone", 12) == 0) {
            char path[MAX_PATH];
            snprintf(path, sizeof(path), "/sys/class/thermal/%s/type", entry->d_name);
            
            int fd = open(path, O_RDONLY);
            if (fd >= 0) {
                char type[64] = {0};
                read(fd, type, sizeof(type) - 1);
                close(fd);
                
                // Skip virtual and xiaomi thermal zones
                if (strstr(type, "virtual") || strstr(type, "xiaomi")) continue;
                
                strncpy(thermal_zones[zone_count].name, type, 63);
                snprintf(thermal_zones[zone_count].path, MAX_PATH, 
                        "/sys/class/thermal/%s/temp", entry->d_name);
                zone_count++;
            }
        }
    }
    closedir(dir);
}

// Get current temperature
static int get_temp(const char *path) {
    return read_int(path);
}

// Get CPU temperature
static int get_cpu_temp(void) {
    // Try common thermal zones
    const char *zones[] = {
        "/sys/class/thermal/thermal_zone0/temp",
        "/sys/devices/virtual/thermal/thermal_zone0/temp",
        "/sys/class/hwmon/hwmon0/temp1_input",
        "/sys/class/hwmon/hwmon1/temp1_input",
        NULL
    };
    
    for (int i = 0; zones[i]; i++) {
        int temp = read_int(zones[i]);
        if (temp > 0) return temp / 1000; // Convert to Celsius
    }
    
    return -1;
}

// Set thermal throttling
static int set_thermal_throttle(int level) {
    const char *paths[] = {
        "/sys/devices/virtual/thermal/thermal_message/tz_throttle",
        "/sys/module/msm_thermal/core_control/enabled",
        "/sys/class/thermal/thermal_message/sconfig",
        NULL
    };
    
    for (int i = 0; paths[i]; i++) {
        if (write_int(paths[i], level) == 0) {
            return 0;
        }
    }
    
    return -1;
}

// Display thermal status
static void show_thermal_status(void) {
    scan_thermal_zones();
    
    printf("=== Hyperion Thermal Manager ===\n\n");
    
    int cpu_temp = get_cpu_temp();
    if (cpu_temp > 0) {
        printf("CPU Temperature: %d°C\n", cpu_temp);
    } else {
        printf("CPU Temperature: N/A\n");
    }
    
    printf("\nThermal Zones:\n");
    for (int i = 0; i < zone_count; i++) {
        int temp = get_temp(thermal_zones[i].path);
        printf("  %s: %d°C\n", thermal_zones[i].name, temp / 1000);
    }
    
    // Check throttling status
    int throttle = read_int("/sys/kernel/msm_thermal/enabled");
    if (throttle >= 0) {
        printf("\nThermal Throttling: %s\n", throttle ? "ENABLED" : "DISABLED");
    }
    
    printf("\n");
}

// Apply thermal profile
static void apply_profile(const char *profile) {
    printf("Applying thermal profile: %s\n", profile);
    
    if (strcmp(profile, "performance") == 0) {
        set_thermal_throttle(0);
        write_int("/sys/module/msm_thermal/core_control/enabled", 0);
    } else if (strcmp(profile, "balanced") == 0) {
        set_thermal_throttle(1);
        write_int("/sys/module/msm_thermal/core_control/enabled", 1);
    } else if (strcmp(profile, "battery") == 0 || strcmp(profile, "powersave") == 0) {
        set_thermal_throttle(2);
        write_int("/sys/module/msm_thermal/core_control/enabled", 1);
    }
    
    printf("Profile applied successfully!\n");
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        show_thermal_status();
        return 0;
    }
    
    if (strcmp(argv[1], "status") == 0) {
        show_thermal_status();
    } else if (strcmp(argv[1], "profile") == 0 && argc > 2) {
        apply_profile(argv[2]);
    } else if (strcmp(argv[1], "cool") == 0) {
        apply_profile("performance");
    } else if (strcmp(argv[1], "normal") == 0) {
        apply_profile("balanced");
    } else if (strcmp(argv[1], "hot") == 0) {
        apply_profile("battery");
    } else {
        printf("Usage: %s [status|profile <name>|cool|normal|hot]\n", argv[0]);
    }
    
    return 0;
}
