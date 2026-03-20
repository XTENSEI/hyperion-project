/*
 * =============================================================================
 * Hyperion Project - Game Booster (C)
 * Made by ShadowBytePrjkt
 * =============================================================================
 * Fast game optimization using C
 * =============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>

#define MAX_PATH 256

/* Colors */
#define RED     "\033[31m"
#define GREEN   "\033[32m"
#define YELLOW  "\033[33m"
#define BLUE    "\033[34m"
#define RESET   "\033[0m"

static int write_str(const char *path, const char *val) {
    FILE *f = fopen(path, "w");
    if (!f) return -1;
    fprintf(f, "%s\n", val);
    fclose(f);
    return 0;
}

/* Apply game optimizations */
static void boost_enable(void) {
    char path[MAX_PATH];
    
    printf(BLUE "Applying game optimizations...\n" RESET);
    
    /* CPU performance */
    DIR *dir = opendir("/sys/devices/system/cpu");
    if (dir) {
        struct dirent *entry;
        while ((entry = readdir(dir))) {
            if (strncmp(entry->d_name, "cpu", 3) == 0 && atoi(entry->d_name + 3) >= 0) {
                snprintf(path, sizeof(path), "/sys/devices/system/cpu/%s/cpufreq/scaling_governor", entry->d_name);
                write_str(path, "performance");
            }
        }
        closedir(dir);
    }
    
    /* CPU boost */
    write_str("/sys/devices/system/cpu/cpu0/cpufreq/boost", "1");
    
    /* I/O scheduler - noop for games */
    dir = opendir("/sys/block");
    if (dir) {
        struct dirent *entry;
        while ((entry = readdir(dir))) {
            if (entry->d_name[0] == '.') continue;
            snprintf(path, sizeof(path), "/sys/block/%s/queue/scheduler", entry->d_name);
            write_str(path, "noop");
            snprintf(path, sizeof(path), "/sys/block/%s/queue/read_ahead_kb", entry->d_name);
            FILE *f = fopen(path, "w");
            if (f) { fprintf(f, "2048\n"); fclose(f); }
        }
        closedir(dir);
    }
    
    /* Memory */
    write_str("/proc/sys/vm/swappiness", "10");
    write_str("/proc/sys/vm/vfs_cache_pressure", "50");
    
    /* GPU */
    write_str("/sys/class/misc/mali0/device/freq", "0");
    write_str("/sys/class/kgsl/kgsl-3d0/max_gpuclk", "0");
    
    /* Thermal */
    write_str("/sys/class/thermal/thermal_zone0/priority", "10");
    
    /* Network */
    write_str("/proc/sys/net/ipv4/tcp_fastopen", "3");
    write_str("/proc/sys/net/ipv4/tcp_tw_reuse", "1");
    
    printf(GREEN "=== GAME BOOST ENABLED ===\n" RESET);
}

/* Remove game optimizations */
static void boost_disable(void) {
    char path[MAX_PATH];
    
    printf(BLUE "Removing game optimizations...\n" RESET);
    
    /* CPU schedutil */
    DIR *dir = opendir("/sys/devices/system/cpu");
    if (dir) {
        struct dirent *entry;
        while ((entry = readdir(dir))) {
            if (strncmp(entry->d_name, "cpu", 3) == 0 && atoi(entry->d_name + 3) >= 0) {
                snprintf(path, sizeof(path), "/sys/devices/system/cpu/%s/cpufreq/scaling_governor", entry->d_name);
                write_str(path, "schedutil");
            }
        }
        closedir(dir);
    }
    
    /* CPU boost off */
    write_str("/sys/devices/system/cpu/cpu0/cpufreq/boost", "0");
    
    /* I/O scheduler */
    dir = opendir("/sys/block");
    if (dir) {
        struct dirent *entry;
        while ((entry = readdir(dir))) {
            if (entry->d_name[0] == '.') continue;
            snprintf(path, sizeof(path), "/sys/block/%s/queue/scheduler", entry->d_name);
            write_str(path, "cfq");
            snprintf(path, sizeof(path), "/sys/block/%s/queue/read_ahead_kb", entry->d_name);
            FILE *f = fopen(path, "w");
            if (f) { fprintf(f, "128\n"); fclose(f); }
        }
        closedir(dir);
    }
    
    /* Memory */
    write_str("/proc/sys/vm/swappiness", "60");
    write_str("/proc/sys/vm/vfs_cache_pressure", "100");
    
    printf(GREEN "=== GAME BOOST DISABLED ===\n" RESET);
}

/* Show status */
static void show_status(void) {
    char buf[MAX_PATH];
    FILE *f;
    
    printf(BLUE "=== Game Booster Status ===\n" RESET);
    
    /* CPU Governor */
    f = fopen("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor", "r");
    if (f) {
        if (fgets(buf, sizeof(buf), f)) printf("CPU: %s", buf);
        fclose(f);
    }
    
    /* GPU */
    f = fopen("/sys/class/kgsl/kgsl-3d0/gpu_busy", "r");
    if (f) {
        if (fgets(buf, sizeof(buf), f)) printf("GPU: %s", buf);
        fclose(f);
    }
    
    /* Swappiness */
    f = fopen("/proc/sys/vm/swappiness", "r");
    if (f) {
        if (fgets(buf, sizeof(buf), f)) printf("Swappiness: %s", buf);
        fclose(f);
    }
}

static void usage(const char *prog) {
    printf("Hyperion Game Booster v1.0\n");
    printf("Usage: %s <command>\n\n", prog);
    printf("Commands:\n");
    printf("  enable   Enable game boost\n");
    printf("  disable  Disable game boost\n");
    printf("  status   Show status\n");
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        usage(argv[0]);
        return 0;
    }

    const char *cmd = argv[1];

    if (strcmp(cmd, "enable") == 0 || strcmp(cmd, "on") == 0) {
        boost_enable();
    }
    else if (strcmp(cmd, "disable") == 0 || strcmp(cmd, "off") == 0) {
        boost_disable();
    }
    else if (strcmp(cmd, "status") == 0) {
        show_status();
    }
    else {
        usage(argv[0]);
    }

    return 0;
}
