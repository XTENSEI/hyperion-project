/*
 * =============================================================================
 * Hyperion Project - CPU Optimizer (C)
 * Made by ShadowBytePrjkt
 * =============================================================================
 * Fast CPU optimization using C for maximum performance
 * =============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>

#define MAX_PATH 256

/* Color output */
#define RED     "\033[31m"
#define GREEN   "\033[32m"
#define YELLOW  "\033[33m"
#define BLUE    "\033[34m"
#define RESET   "\033[0m"

static int write_int(const char *path, int val) {
    FILE *f = fopen(path, "w");
    if (!f) return -1;
    fprintf(f, "%d\n", val);
    fclose(f);
    return 0;
}

static int write_str(const char *path, const char *val) {
    FILE *f = fopen(path, "w");
    if (!f) return -1;
    fprintf(f, "%s\n", val);
    fclose(f);
    return 0;
}

static int read_int(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    int val;
    if (fscanf(f, "%d", &val) != 1) {
        fclose(f);
        return -1;
    }
    fclose(f);
    return val;
}

/* Set CPU governor for all cores */
static void set_governor(const char *gov) {
    char path[MAX_PATH];
    DIR *dir = opendir("/sys/devices/system/cpu");
    if (!dir) {
        printf(RED "Error: Cannot access CPU\n" RESET);
        return;
    }

    struct dirent *entry;
    int count = 0;
    while ((entry = readdir(dir))) {
        if (strncmp(entry->d_name, "cpu", 3) == 0 && atoi(entry->d_name + 3) >= 0) {
            snprintf(path, sizeof(path), "/sys/devices/system/cpu/%s/cpufreq/scaling_governor", entry->d_name);
            if (write_str(path, gov) == 0) count++;
        }
    }
    closedir(dir);
    printf(GREEN "Governor: %s (%d cores)\n" RESET, gov, count);
}

/* Set CPU frequency */
static void set_freq(int min_mhz, int max_mhz) {
    char path[MAX_PATH];
    DIR *dir = opendir("/sys/devices/system/cpu");
    if (!dir) return;

    struct dirent *entry;
    while ((entry = readdir(dir))) {
        if (strncmp(entry->d_name, "cpu", 3) == 0 && atoi(entry->d_name + 3) >= 0) {
            snprintf(path, sizeof(path), "/sys/devices/system/cpu/%s/cpufreq/scaling_min_freq", entry->d_name);
            write_int(path, min_mhz * 1000);
            snprintf(path, sizeof(path), "/sys/devices/system/cpu/%s/cpufreq/scaling_max_freq", entry->d_name);
            write_int(path, max_mhz * 1000);
        }
    }
    closedir(dir);
    printf(GREEN "Frequency: %d-%d MHz\n" RESET, min_mhz, max_mhz);
}

/* Enable/disable CPU boost */
static void set_boost(int enable) {
    write_int("/sys/devices/system/cpu/cpu0/cpufreq/boost", enable ? 1 : 0);
    printf(GREEN "CPU Boost: %s\n" RESET, enable ? "ON" : "OFF");
}

/* Show CPU info */
static void show_info(void) {
    char path[MAX_PATH];
    char buf[128];
    
    printf(BLUE "=== CPU Information ===\n" RESET);
    
    /* Available governors */
    snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors");
    FILE *f = fopen(path, "r");
    if (f) {
        if (fgets(buf, sizeof(buf), f)) printf(YELLOW "Available: %s" RESET, buf);
        fclose(f);
    }
    
    /* Current governor */
    snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor");
    f = fopen(path, "r");
    if (f) {
        if (fgets(buf, sizeof(buf), f)) printf(GREEN "Current: %s" RESET, buf);
        fclose(f);
    }
    
    /* Frequencies */
    snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq");
    int min = read_int(path) / 1000;
    snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq");
    int max = read_int(path) / 1000;
    printf(YELLOW "Range: %d - %d MHz\n" RESET, min, max);
    
    /* Boost status */
    snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpufreq/boost");
    int boost = read_int(path);
    printf(GREEN "Boost: %s\n" RESET, boost ? "enabled" : "disabled");
}

/* Performance mode */
static void mode_performance(void) {
    set_governor("performance");
    set_boost(1);
    printf(GREEN "=== PERFORMANCE MODE ===\n" RESET);
}

/* Powersave mode */
static void mode_powersave(void) {
    set_governor("powersave");
    set_boost(0);
    printf(BLUE "=== POWERSAVE MODE ===\n" RESET);
}

/* Game mode */
static void mode_game(void) {
    set_governor("performance");
    set_freq(1800, 3000);
    set_boost(1);
    printf(GREEN "=== GAME MODE ===\n" RESET);
}

static void usage(const char *prog) {
    printf("Hyperion CPU Optimizer v1.0\n");
    printf("Usage: %s <command>\n\n", prog);
    printf("Commands:\n");
    printf("  info            Show CPU information\n");
    printf("  gov <name>      Set governor (performance, powersave, schedutil, ondemand)\n");
    printf("  freq <min> <max>  Set frequency range in MHz\n");
    printf("  boost <0|1>    Enable/disable boost\n");
    printf("  performance     Performance mode\n");
    printf("  powersave      Powersave mode\n");
    printf("  game           Game mode\n");
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        usage(argv[0]);
        return 0;
    }

    const char *cmd = argv[1];

    if (strcmp(cmd, "info") == 0) {
        show_info();
    }
    else if (strcmp(cmd, "gov") == 0 && argc == 3) {
        set_governor(argv[2]);
    }
    else if (strcmp(cmd, "freq") == 0 && argc == 4) {
        set_freq(atoi(argv[2]), atoi(argv[3]));
    }
    else if (strcmp(cmd, "boost") == 0 && argc == 3) {
        set_boost(atoi(argv[2]));
    }
    else if (strcmp(cmd, "performance") == 0) {
        mode_performance();
    }
    else if (strcmp(cmd, "powersave") == 0) {
        mode_powersave();
    }
    else if (strcmp(cmd, "game") == 0) {
        mode_game();
    }
    else {
        usage(argv[0]);
    }

    return 0;
}
