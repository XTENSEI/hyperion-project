/*
 * =============================================================================
 * Hyperion Project - C Utilities (SAC-like)
 * Made by ShadowBytePrjkt
 * =============================================================================
 * Fast C-based system optimization utilities
 * Subcommands: cpu, gpu, memory, io, thermal, boost
 * =============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <stdarg.h>

#define MAX_PATH 256
#define MAX_LINE 128

/* ─── Color Output ─────────────────────────────────────────────────────────*/
#define RED     "\033[31m"
#define GREEN   "\033[32m"
#define YELLOW  "\033[33m"
#define BLUE    "\033[34m"
#define RESET   "\033[0m"

static void print_color(const char *color, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    printf("%s", color);
    vprintf(fmt, args);
    printf("%s", RESET);
    va_end(args);
}

/* ─── File Helpers ─────────────────────────────────────────────────────────*/
static int read_str(const char *path, char *buf, size_t size) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    if (fgets(buf, size, f)) {
        buf[strcspn(buf, "\n")] = 0;
        fclose(f);
        return 0;
    }
    fclose(f);
    return -1;
}

static int write_str(const char *path, const char *val) {
    FILE *f = fopen(path, "w");
    if (!f) return -1;
    fprintf(f, "%s\n", val);
    fclose(f);
    return 0;
}

static int write_int(const char *path, int val) {
    FILE *f = fopen(path, "w");
    if (!f) return -1;
    fprintf(f, "%d\n", val);
    fclose(f);
    return 0;
}

/* ─── CPU Functions ─────────────────────────────────────────────────────────*/
static void cpu_list_governors(void) {
    char path[MAX_PATH];
    char buf[MAX_LINE];
    DIR *dir = opendir("/sys/devices/system/cpu");
    if (!dir) {
        print_color(RED, "Error: Cannot access CPU directory\n");
        return;
    }

    print_color(BLUE, "Available CPU Governors:\n");
    struct dirent *entry;
    while ((entry = readdir(dir))) {
        if (strncmp(entry->d_name, "cpu", 3) == 0 && atoi(entry->d_name + 3) > 0) {
            snprintf(path, sizeof(path), "/sys/devices/system/cpu/%s/cpufreq/scaling_governor", entry->d_name);
            if (read_str(path, buf, sizeof(buf)) == 0) {
                print_color(GREEN, "  CPU%s: %s\n", entry->d_name + 3, buf);
            }
        }
    }
    closedir(dir);
}

static void cpu_set_governor(const char *gov) {
    char path[MAX_PATH];
    DIR *dir = opendir("/sys/devices/system/cpu");
    if (!dir) {
        print_color(RED, "Error: Cannot access CPU directory\n");
        return;
    }

    struct dirent *entry;
    int count = 0;
    while ((entry = readdir(dir))) {
        if (strncmp(entry->d_name, "cpu", 3) == 0 && atoi(entry->d_name + 3) >= 0) {
            snprintf(path, sizeof(path), "/sys/devices/system/cpu/%s/cpufreq/scaling_governor", entry->d_name);
            if (write_str(path, gov) == 0) {
                count++;
            }
        }
    }
    closedir(dir);
    print_color(GREEN, "Set governor to %s on %d CPUs\n", gov, count);
}

static void cpu_set_boost(int enable) {
    write_int("/sys/devices/system/cpu/cpu0/cpufreq/boost", enable ? 1 : 0);
    print_color(GREEN, "CPU Boost %s\n", enable ? "enabled" : "disabled");
}

static void cpu_show_info(void) {
    char buf[MAX_LINE];
    char path[MAX_PATH];
    
    print_color(BLUE, "=== CPU Information ===\n");
    
    if (read_str("/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors", buf, sizeof(buf)) == 0) {
        print_color(YELLOW, "Available: %s\n", buf);
    }
    
    if (read_str("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor", buf, sizeof(buf)) == 0) {
        print_color(GREEN, "Current: %s\n", buf);
    }
    
    if (read_str("/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq", buf, sizeof(buf)) == 0) {
        print_color(YELLOW, "Min Freq: %s KHz\n", buf);
    }
    if (read_str("/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq", buf, sizeof(buf)) == 0) {
        print_color(YELLOW, "Max Freq: %s KHz\n", buf);
    }
    
    if (read_str("/sys/devices/system/cpu/cpufreq/boost", buf, sizeof(buf)) == 0) {
        print_color(GREEN, "Boost: %s\n", atoi(buf) ? "enabled" : "disabled");
    }
}

/* ─── GPU Functions ─────────────────────────────────────────────────────────*/
static void gpu_show_info(void) {
    char buf[MAX_LINE];
    
    print_color(BLUE, "=== GPU Information ===\n");
    
    if (read_str("/sys/class/misc/mali0/device/utilization", buf, sizeof(buf)) == 0) {
        print_color(GREEN, "Mali Utilization: %s%%\n", buf);
    }
    if (read_str("/sys/class/misc/mali0/device/freq", buf, sizeof(buf)) == 0) {
        print_color(YELLOW, "Mali Frequency: %s MHz\n", buf);
    }
    
    if (read_str("/sys/class/kgsl/kgsl-3d0/gpu_busy", buf, sizeof(buf)) == 0) {
        print_color(GREEN, "Adreno Busy: %s%%\n", buf);
    }
    if (read_str("/sys/class/kgsl/kgsl-3d0/max_gpuclk", buf, sizeof(buf)) == 0) {
        print_color(YELLOW, "Adreno Max: %s MHz\n", buf);
    }
}

static void gpu_set_freq(int freq_mhz) {
    if (write_str("/sys/class/misc/mali0/device/freq", "0") == 0) {
        print_color(GREEN, "Set Mali GPU to maximum\n");
        return;
    }
    if (write_str("/sys/class/kgsl/kgsl-3d0/max_gpuclk", "0") == 0) {
        print_color(GREEN, "Set Adreno GPU to maximum\n");
        return;
    }
    print_color(RED, "GPU frequency control not available\n");
}

/* ─── Memory Functions ─────────────────────────────────────────────────────*/
static void memory_show_info(void) {
    FILE *f;
    char line[MAX_LINE];
    long mem_total = 0, mem_free = 0, mem_available = 0, buffers = 0, cached = 0;
    
    print_color(BLUE, "=== Memory Information ===\n");
    
    f = fopen("/proc/meminfo", "r");
    if (!f) {
        print_color(RED, "Cannot read memory info\n");
        return;
    }
    
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "MemTotal: %ld kB", &mem_total) == 1);
        else if (sscanf(line, "MemFree: %ld kB", &mem_free) == 1);
        else if (sscanf(line, "MemAvailable: %ld kB", &mem_available) == 1);
        else if (sscanf(line, "Buffers: %ld kB", &buffers) == 1);
        else if (sscanf(line, "Cached: %ld kB", &cached) == 1);
    }
    fclose(f);
    
    long used = mem_total - mem_available;
    int percent = (int)((double)used / mem_total * 100);
    
    print_color(YELLOW, "Total:     %ld MB\n", mem_total / 1024);
    print_color(GREEN, "Available: %ld MB\n", mem_available / 1024);
    print_color(RED, "Used:      %ld MB (%d%%)\n", used / 1024, percent);
}

static void memory_set_swappiness(int val) {
    char path[MAX_PATH];
    snprintf(path, sizeof(path), "/proc/sys/vm/swappiness");
    if (write_int(path, val) == 0) {
        print_color(GREEN, "Set swappiness to %d\n", val);
    } else {
        print_color(RED, "Failed to set swappiness\n");
    }
}

static void memory_drop_caches(void) {
    sync();
    if (write_str("/proc/sys/vm/drop_caches", "3") == 0) {
        print_color(GREEN, "Dropped caches successfully\n");
    } else {
        print_color(RED, "Failed to drop caches\n");
    }
}

/* ─── I/O Functions ─────────────────────────────────────────────────────────*/
static void io_list_schedulers(void) {
    char buf[MAX_LINE];
    
    print_color(BLUE, "=== I/O Schedulers ===\n");
    
    DIR *dir = opendir("/sys/block");
    if (!dir) {
        print_color(RED, "Cannot access block devices\n");
        return;
    }
    
    struct dirent *entry;
    while ((entry = readdir(dir))) {
        if (entry->d_name[0] == '.') continue;
        char path[MAX_PATH];
        snprintf(path, sizeof(path), "/sys/block/%s/queue/scheduler", entry->d_name);
        if (read_str(path, buf, sizeof(buf)) == 0) {
            print_color(GREEN, "%s: %s\n", entry->d_name, buf);
        }
    }
    closedir(dir);
}

static void io_set_scheduler(const char *device, const char *scheduler) {
    char path[MAX_PATH];
    snprintf(path, sizeof(path), "/sys/block/%s/queue/scheduler", device);
    if (write_str(path, scheduler) == 0) {
        print_color(GREEN, "Set %s scheduler to %s\n", device, scheduler);
    } else {
        print_color(RED, "Failed to set scheduler\n");
    }
}

static void io_set_read_ahead(const char *device, int kb) {
    char path[MAX_PATH];
    snprintf(path, sizeof(path), "/sys/block/%s/queue/read_ahead_kb", device);
    if (write_int(path, kb) == 0) {
        print_color(GREEN, "Set %s read_ahead to %d KB\n", device, kb);
    } else {
        print_color(RED, "Failed to set read_ahead\n");
    }
}

/* ─── Thermal Functions ─────────────────────────────────────────────────────*/
static void thermal_show(void) {
    char path[MAX_PATH];
    char buf[MAX_LINE];
    int temp;
    
    print_color(BLUE, "=== Thermal Zones ===\n");
    
    for (int i = 0; i < 10; i++) {
        snprintf(path, sizeof(path), "/sys/class/thermal/thermal_zone%d/type", i);
        if (read_str(path, buf, sizeof(buf)) != 0) break;
        
        char type[MAX_LINE];
        strcpy(type, buf);
        
        snprintf(path, sizeof(path), "/sys/class/thermal/thermal_zone%d/temp", i);
        if (read_str(path, buf, sizeof(buf)) == 0) {
            temp = atoi(buf);
            if (temp > 1000) temp /= 1000;
            print_color(GREEN, "Zone %d (%s): %d C\n", i, type, temp);
        }
    }
}

static void thermal_set_limit(int temp) {
    char *paths[] = {
        "/sys/class/thermal/thermal_zone0/crit_temp",
        "/sys/devices/virtual/thermal/thermal_zone0/crit_temp",
        NULL
    };
    
    for (int i = 0; paths[i]; i++) {
        if (write_int(paths[i], temp) == 0) {
            print_color(GREEN, "Set thermal limit to %d C\n", temp);
            return;
        }
    }
    print_color(RED, "Thermal control not available\n");
}

/* ─── Boost Functions ─────────────────────────────────────────────────────*/
static void boost_enable(void) {
    cpu_set_governor("performance");
    cpu_set_boost(1);
    memory_set_swappiness(10);
    io_set_scheduler("mmcblk0", "noop");
    io_set_scheduler("sda", "noop");
    print_color(GREEN, "=== BOOST MODE ENABLED ===\n");
    print_color(GREEN, "CPU: Performance governor\n");
    print_color(GREEN, "Boost: Enabled\n");
    print_color(GREEN, "Swappiness: 10\n");
    print_color(GREEN, "I/O: Noop scheduler\n");
}

static void boost_disable(void) {
    cpu_set_governor("schedutil");
    cpu_set_boost(0);
    memory_set_swappiness(60);
    io_set_scheduler("mmcblk0", "cfq");
    io_set_scheduler("sda", "cfq");
    print_color(YELLOW, "=== BOOST MODE DISABLED ===\n");
    print_color(YELLOW, "CPU: Schedutil governor\n");
    print_color(YELLOW, "Boost: Disabled\n");
    print_color(YELLOW, "Swappiness: 60\n");
    print_color(YELLOW, "I/O: CFQ scheduler\n");
}

/* ─── Main ─────────────────────────────────────────────────────────────────*/
static void usage(const char *prog) {
    printf("Hyperion Utilities v1.0.0\n");
    printf("Made by ShadowBytePrjkt\n\n");
    printf("Usage: %s <command> [options]\n\n", prog);
    printf("Commands:\n");
    printf("  cpu                     Show CPU information\n");
    printf("  cpu gov <governor>     Set CPU governor (performance, powersave, schedutil, ondemand)\n");
    printf("  cpu boost <0|1>        Enable/disable CPU boost\n");
    printf("  gpu                    Show GPU information\n");
    printf("  gpu freq               Set GPU to maximum frequency\n");
    printf("  mem                    Show memory information\n");
    printf("  mem swap <value>       Set swappiness (0-100)\n");
    printf("  mem drop               Drop caches\n");
    printf("  io                     List I/O schedulers\n");
    printf("  io set <dev> <sched>   Set I/O scheduler\n");
    printf("  io ra <dev> <kb>       Set read-ahead KB\n");
    printf("  thermal                Show thermal information\n");
    printf("  thermal limit <temp>   Set thermal limit\n");
    printf("  boost                  Enable gaming boost\n");
    printf("  unboost                Disable gaming boost\n");
    printf("\nExamples:\n");
    printf("  %s cpu gov performance\n", prog);
    printf("  %s boost\n", prog);
    printf("  %s mem swap 10\n", prog);
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        usage(argv[0]);
        return 0;
    }

    const char *cmd = argv[1];

    if (strcmp(cmd, "cpu") == 0) {
        if (argc == 2) {
            cpu_show_info();
        } else if (strcmp(argv[2], "gov") == 0 && argc == 4) {
            cpu_set_governor(argv[3]);
        } else if (strcmp(argv[2], "boost") == 0 && argc == 4) {
            cpu_set_boost(atoi(argv[3]));
        } else {
            usage(argv[0]);
        }
    } 
    else if (strcmp(cmd, "gpu") == 0) {
        if (argc == 2) {
            gpu_show_info();
        } else if (strcmp(argv[2], "freq") == 0) {
            gpu_set_freq(0);
        } else {
            usage(argv[0]);
        }
    }
    else if (strcmp(cmd, "mem") == 0) {
        if (argc == 2) {
            memory_show_info();
        } else if (strcmp(argv[2], "swap") == 0 && argc == 4) {
            memory_set_swappiness(atoi(argv[3]));
        } else if (strcmp(argv[2], "drop") == 0) {
            memory_drop_caches();
        } else {
            usage(argv[0]);
        }
    }
    else if (strcmp(cmd, "io") == 0) {
        if (argc == 2) {
            io_list_schedulers();
        } else if (strcmp(argv[2], "set") == 0 && argc == 5) {
            io_set_scheduler(argv[3], argv[4]);
        } else if (strcmp(argv[2], "ra") == 0 && argc == 5) {
            io_set_read_ahead(argv[3], atoi(argv[4]));
        } else {
            usage(argv[0]);
        }
    }
    else if (strcmp(cmd, "thermal") == 0) {
        if (argc == 2) {
            thermal_show();
        } else if (strcmp(argv[2], "limit") == 0 && argc == 4) {
            thermal_set_limit(atoi(argv[3]));
        } else {
            usage(argv[0]);
        }
    }
    else if (strcmp(cmd, "boost") == 0) {
        boost_enable();
    }
    else if (strcmp(cmd, "unboost") == 0) {
        boost_disable();
    }
    else {
        usage(argv[0]);
    }

    return 0;
}
