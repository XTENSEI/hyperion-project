/*
 * =============================================================================
 * Hyperion Project - System Monitor Daemon
 * Made by ShadowBytePrjkt
 * =============================================================================
 * Ultra-lightweight epoll-based system monitor daemon
 * Reads /proc/stat, /proc/meminfo, /proc/net/dev, thermal zones
 * Exposes Unix domain socket for IPC with Node.js server
 * Compiled with: gcc -O2 -s -o hyperion hyperion_daemon.c
 * =============================================================================
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <time.h>
#include <math.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/timerfd.h>
#include <sys/signalfd.h>
#include <pthread.h>

/* ─── Constants ─────────────────────────────────────────────────────────────*/
#define HYPERION_DIR        "/data/adb/hyperion"
#define SOCKET_PATH         "/dev/hyperion.sock"
#define LOG_FILE            HYPERION_DIR "/logs/daemon.log"
#define PID_FILE            HYPERION_DIR "/data/daemon.pid"
#define MAX_CLIENTS         16
#define MAX_EVENTS          32
#define TELEMETRY_INTERVAL_MS 500   /* 500ms telemetry */
#define THERMAL_INTERVAL_MS   1000  /* 1s thermal check */
#define JSON_BUF_SIZE       2048
#define MAX_THERMAL_ZONES   16
#define MAX_CPU_CORES       16

/* ─── Data Structures ────────────────────────────────────────────────────────*/
typedef struct {
    unsigned long long user, nice, system, idle, iowait, irq, softirq, steal;
} cpu_stat_t;

typedef struct {
    double cpu_percent;
    double ram_percent;
    long ram_total_mb;
    long ram_free_mb;
    int battery_level;
    double battery_temp;
    double cpu_temp;
    int is_charging;
    long net_rx_bytes;
    long net_tx_bytes;
    double net_rx_mbps;
    double net_tx_mbps;
    long long timestamp_ms;
} telemetry_t;

typedef struct {
    int fd;
    int active;
    char buf[256];
} client_t;

/* ─── Globals ────────────────────────────────────────────────────────────────*/
static volatile int g_running = 1;
static int g_epoll_fd = -1;
static int g_server_fd = -1;
static int g_timer_fd = -1;
static int g_signal_fd = -1;
static client_t g_clients[MAX_CLIENTS];
static telemetry_t g_telemetry = {0};
static cpu_stat_t g_prev_cpu = {0};
static long g_prev_net_rx = 0;
static long g_prev_net_tx = 0;
static long long g_prev_net_time = 0;
static FILE *g_log_fp = NULL;
static pthread_mutex_t g_telemetry_mutex = PTHREAD_MUTEX_INITIALIZER;

/* ─── Logging ────────────────────────────────────────────────────────────────*/
static void hlog(const char *level, const char *fmt, ...) {
    char buf[512];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);

    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    char ts[32];
    strftime(ts, sizeof(ts), "%H:%M:%S", tm_info);

    if (g_log_fp) {
        fprintf(g_log_fp, "[%s][DAEMON][%s] %s\n", ts, level, buf);
        fflush(g_log_fp);
    }
    fprintf(stdout, "[%s][DAEMON][%s] %s\n", ts, level, buf);
}

/* ─── Time Helper ────────────────────────────────────────────────────────────*/
static long long get_time_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* ─── CPU Stats ──────────────────────────────────────────────────────────────*/
static int read_cpu_stat(cpu_stat_t *stat) {
    FILE *f = fopen("/proc/stat", "r");
    if (!f) return -1;

    int ret = fscanf(f, "cpu %llu %llu %llu %llu %llu %llu %llu %llu",
        &stat->user, &stat->nice, &stat->system, &stat->idle,
        &stat->iowait, &stat->irq, &stat->softirq, &stat->steal);
    fclose(f);
    return (ret == 8) ? 0 : -1;
}

static double calc_cpu_percent(const cpu_stat_t *prev, const cpu_stat_t *curr) {
    unsigned long long prev_idle = prev->idle + prev->iowait;
    unsigned long long curr_idle = curr->idle + curr->iowait;

    unsigned long long prev_total = prev->user + prev->nice + prev->system +
        prev->idle + prev->iowait + prev->irq + prev->softirq + prev->steal;
    unsigned long long curr_total = curr->user + curr->nice + curr->system +
        curr->idle + curr->iowait + curr->irq + curr->softirq + curr->steal;

    unsigned long long delta_idle = curr_idle - prev_idle;
    unsigned long long delta_total = curr_total - prev_total;

    if (delta_total == 0) return 0.0;
    return 100.0 * (1.0 - (double)delta_idle / (double)delta_total);
}

/* ─── Memory Stats ───────────────────────────────────────────────────────────*/
static int read_mem_stats(long *total_mb, long *free_mb, double *percent) {
    FILE *f = fopen("/proc/meminfo", "r");
    if (!f) return -1;

    long mem_total = 0, mem_available = 0;
    char line[128];

    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "MemTotal:", 9) == 0)
            sscanf(line + 9, "%ld", &mem_total);
        else if (strncmp(line, "MemAvailable:", 13) == 0)
            sscanf(line + 13, "%ld", &mem_available);
        if (mem_total && mem_available) break;
    }
    fclose(f);

    if (mem_total == 0) return -1;

    *total_mb = mem_total / 1024;
    *free_mb = mem_available / 1024;
    *percent = 100.0 * (1.0 - (double)mem_available / (double)mem_total);
    return 0;
}

/* ─── Battery Stats ──────────────────────────────────────────────────────────*/
static int read_battery_level(void) {
    FILE *f = fopen("/sys/class/power_supply/battery/capacity", "r");
    if (!f) return 100;
    int level = 100;
    fscanf(f, "%d", &level);
    fclose(f);
    return level;
}

static double read_battery_temp(void) {
    FILE *f = fopen("/sys/class/power_supply/battery/temp", "r");
    if (!f) return 30.0;
    int raw = 300;
    fscanf(f, "%d", &raw);
    fclose(f);
    return raw / 10.0;
}

static int read_charging_status(void) {
    FILE *f = fopen("/sys/class/power_supply/battery/status", "r");
    if (!f) return 0;
    char status[32] = {0};
    fscanf(f, "%31s", status);
    fclose(f);
    return (strcmp(status, "Charging") == 0 || strcmp(status, "Full") == 0) ? 1 : 0;
}

/* ─── Thermal Stats ──────────────────────────────────────────────────────────*/
static double read_thermal_zone(int zone) {
    char path[64];
    snprintf(path, sizeof(path), "/sys/class/thermal/thermal_zone%d/temp", zone);
    FILE *f = fopen(path, "r");
    if (!f) return 0.0;
    int raw = 0;
    fscanf(f, "%d", &raw);
    fclose(f);
    return (raw > 1000) ? raw / 1000.0 : (double)raw;
}

/* ─── Network Stats ──────────────────────────────────────────────────────────*/
static int read_net_stats(long *rx_bytes, long *tx_bytes) {
    FILE *f = fopen("/proc/net/dev", "r");
    if (!f) return -1;

    char line[256];
    long total_rx = 0, total_tx = 0;

    // Skip header lines
    fgets(line, sizeof(line), f);
    fgets(line, sizeof(line), f);

    while (fgets(line, sizeof(line), f)) {
        char *colon = strchr(line, ':');
        if (!colon) continue;

        // Skip loopback
        char iface[32] = {0};
        sscanf(line, " %31[^:]", iface);
        if (strcmp(iface, "lo") == 0) continue;

        long rx = 0, tx = 0;
        // Fields: rx_bytes, rx_packets, rx_errs, rx_drop, rx_fifo, rx_frame, rx_compressed, rx_multicast
        //         tx_bytes, tx_packets, ...
        sscanf(colon + 1, "%ld %*d %*d %*d %*d %*d %*d %*d %ld", &rx, &tx);
        total_rx += rx;
        total_tx += tx;
    }
    fclose(f);

    *rx_bytes = total_rx;
    *tx_bytes = total_tx;
    return 0;
}

/* ─── Update Telemetry ───────────────────────────────────────────────────────*/
static void update_telemetry(void) {
    pthread_mutex_lock(&g_telemetry_mutex);

    // CPU
    cpu_stat_t curr_cpu;
    if (read_cpu_stat(&curr_cpu) == 0) {
        g_telemetry.cpu_percent = calc_cpu_percent(&g_prev_cpu, &curr_cpu);
        g_prev_cpu = curr_cpu;
    }

    // Memory
    read_mem_stats(&g_telemetry.ram_total_mb, &g_telemetry.ram_free_mb,
                   &g_telemetry.ram_percent);

    // Battery
    g_telemetry.battery_level = read_battery_level();
    g_telemetry.battery_temp = read_battery_temp();
    g_telemetry.is_charging = read_charging_status();

    // Thermal
    g_telemetry.cpu_temp = read_thermal_zone(0);

    // Network
    long rx, tx;
    if (read_net_stats(&rx, &tx) == 0) {
        long long now = get_time_ms();
        double elapsed = (now - g_prev_net_time) / 1000.0;
        if (elapsed > 0 && g_prev_net_time > 0) {
            g_telemetry.net_rx_mbps = (rx - g_prev_net_rx) / elapsed / 1024.0 / 1024.0;
            g_telemetry.net_tx_mbps = (tx - g_prev_net_tx) / elapsed / 1024.0 / 1024.0;
        }
        g_prev_net_rx = rx;
        g_prev_net_tx = tx;
        g_prev_net_time = now;
        g_telemetry.net_rx_bytes = rx;
        g_telemetry.net_tx_bytes = tx;
    }

    g_telemetry.timestamp_ms = get_time_ms();

    pthread_mutex_unlock(&g_telemetry_mutex);
}

/* ─── Build JSON Telemetry ───────────────────────────────────────────────────*/
static int build_telemetry_json(char *buf, size_t size) {
    pthread_mutex_lock(&g_telemetry_mutex);
    int len = snprintf(buf, size,
        "{\"type\":\"telemetry\",\"data\":{"
        "\"cpu\":%.1f,"
        "\"ram\":%.1f,"
        "\"ram_total_mb\":%ld,"
        "\"ram_free_mb\":%ld,"
        "\"battery\":%d,"
        "\"battery_temp\":%.1f,"
        "\"cpu_temp\":%.1f,"
        "\"charging\":%s,"
        "\"net_rx_mbps\":%.2f,"
        "\"net_tx_mbps\":%.2f,"
        "\"ts\":%lld"
        "}}\n",
        g_telemetry.cpu_percent,
        g_telemetry.ram_percent,
        g_telemetry.ram_total_mb,
        g_telemetry.ram_free_mb,
        g_telemetry.battery_level,
        g_telemetry.battery_temp,
        g_telemetry.cpu_temp,
        g_telemetry.is_charging ? "true" : "false",
        g_telemetry.net_rx_mbps,
        g_telemetry.net_tx_mbps,
        g_telemetry.timestamp_ms
    );
    pthread_mutex_unlock(&g_telemetry_mutex);
    return len;
}

/* ─── Broadcast to Clients ───────────────────────────────────────────────────*/
static void broadcast_to_clients(const char *msg, int len) {
    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (g_clients[i].active && g_clients[i].fd >= 0) {
            ssize_t sent = send(g_clients[i].fd, msg, len, MSG_NOSIGNAL);
            if (sent < 0) {
                hlog("DEBUG", "Client %d disconnected", i);
                close(g_clients[i].fd);
                g_clients[i].active = 0;
                g_clients[i].fd = -1;
            }
        }
    }
}

/* ─── Accept New Client ──────────────────────────────────────────────────────*/
static void accept_client(void) {
    int client_fd = accept(g_server_fd, NULL, NULL);
    if (client_fd < 0) return;

    // Set non-blocking
    int flags = fcntl(client_fd, F_GETFL, 0);
    fcntl(client_fd, F_SETFL, flags | O_NONBLOCK);

    // Find free slot
    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (!g_clients[i].active) {
            g_clients[i].fd = client_fd;
            g_clients[i].active = 1;

            // Add to epoll
            struct epoll_event ev = {
                .events = EPOLLIN | EPOLLET,
                .data.fd = client_fd
            };
            epoll_ctl(g_epoll_fd, EPOLL_CTL_ADD, client_fd, &ev);

            hlog("INFO", "Client %d connected (fd=%d)", i, client_fd);

            // Send current telemetry immediately
            char json[JSON_BUF_SIZE];
            int len = build_telemetry_json(json, sizeof(json));
            send(client_fd, json, len, MSG_NOSIGNAL);
            return;
        }
    }

    // No free slots
    hlog("WARN", "Max clients reached, rejecting connection");
    close(client_fd);
}

/* ─── Handle Client Data ─────────────────────────────────────────────────────*/
static void handle_client_data(int fd) {
    char buf[512];
    ssize_t n = recv(fd, buf, sizeof(buf) - 1, 0);
    if (n <= 0) {
        // Client disconnected
        for (int i = 0; i < MAX_CLIENTS; i++) {
            if (g_clients[i].fd == fd) {
                close(fd);
                g_clients[i].active = 0;
                g_clients[i].fd = -1;
                hlog("INFO", "Client %d disconnected", i);
                break;
            }
        }
        return;
    }
    buf[n] = '\0';
    hlog("DEBUG", "Client data: %s", buf);
    // Commands are handled by Node.js server, daemon just monitors
}

/* ─── Signal Handler ─────────────────────────────────────────────────────────*/
static void handle_signal(int sigfd) {
    struct signalfd_siginfo si;
    ssize_t n = read(sigfd, &si, sizeof(si));
    if (n != sizeof(si)) return;

    switch (si.ssi_signo) {
        case SIGTERM:
        case SIGINT:
            hlog("INFO", "Signal %d received, shutting down", si.ssi_signo);
            g_running = 0;
            break;
        case SIGHUP:
            hlog("INFO", "SIGHUP received - reloading");
            break;
    }
}

/* ─── Setup Unix Socket ──────────────────────────────────────────────────────*/
static int setup_server_socket(void) {
    // Remove old socket
    unlink(SOCKET_PATH);

    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK, 0);
    if (fd < 0) {
        hlog("ERROR", "socket() failed: %s", strerror(errno));
        return -1;
    }

    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        hlog("ERROR", "bind() failed: %s", strerror(errno));
        close(fd);
        return -1;
    }

    chmod(SOCKET_PATH, 0666);

    if (listen(fd, 8) < 0) {
        hlog("ERROR", "listen() failed: %s", strerror(errno));
        close(fd);
        return -1;
    }

    hlog("INFO", "Unix socket listening at %s", SOCKET_PATH);
    return fd;
}

/* ─── Setup Timer ────────────────────────────────────────────────────────────*/
static int setup_timer(int interval_ms) {
    int fd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK);
    if (fd < 0) return -1;

    struct itimerspec ts = {
        .it_interval = {
            .tv_sec = interval_ms / 1000,
            .tv_nsec = (interval_ms % 1000) * 1000000
        },
        .it_value = {
            .tv_sec = 0,
            .tv_nsec = 100000000  // 100ms initial delay
        }
    };

    timerfd_settime(fd, 0, &ts, NULL);
    return fd;
}

/* ─── Write PID File ─────────────────────────────────────────────────────────*/
static void write_pid_file(void) {
    FILE *f = fopen(PID_FILE, "w");
    if (f) {
        fprintf(f, "%d\n", getpid());
        fclose(f);
    }
}

/* ─── Cleanup ────────────────────────────────────────────────────────────────*/
static void cleanup(void) {
    hlog("INFO", "Cleaning up...");

    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (g_clients[i].active && g_clients[i].fd >= 0) {
            close(g_clients[i].fd);
        }
    }

    if (g_server_fd >= 0) close(g_server_fd);
    if (g_timer_fd >= 0) close(g_timer_fd);
    if (g_signal_fd >= 0) close(g_signal_fd);
    if (g_epoll_fd >= 0) close(g_epoll_fd);

    unlink(SOCKET_PATH);
    unlink(PID_FILE);

    if (g_log_fp) fclose(g_log_fp);
}

/* ─── Main ───────────────────────────────────────────────────────────────────*/
int main(int argc, char *argv[]) {
    // Open log file
    g_log_fp = fopen(LOG_FILE, "a");

    hlog("INFO", "==============================================");
    hlog("INFO", "Hyperion Daemon v1.0.0 starting (PID: %d)", getpid());
    hlog("INFO", "Made by ShadowBytePrjkt");
    hlog("INFO", "==============================================");

    // Write PID
    write_pid_file();

    // Initialize clients
    memset(g_clients, 0, sizeof(g_clients));
    for (int i = 0; i < MAX_CLIENTS; i++) {
        g_clients[i].fd = -1;
    }

    // Setup signal handling via signalfd
    sigset_t mask;
    sigemptyset(&mask);
    sigaddset(&mask, SIGTERM);
    sigaddset(&mask, SIGINT);
    sigaddset(&mask, SIGHUP);
    sigprocmask(SIG_BLOCK, &mask, NULL);

    g_signal_fd = signalfd(-1, &mask, SFD_NONBLOCK);
    if (g_signal_fd < 0) {
        hlog("ERROR", "signalfd() failed: %s", strerror(errno));
        return 1;
    }

    // Setup epoll
    g_epoll_fd = epoll_create1(EPOLL_CLOEXEC);
    if (g_epoll_fd < 0) {
        hlog("ERROR", "epoll_create1() failed: %s", strerror(errno));
        return 1;
    }

    // Setup server socket
    g_server_fd = setup_server_socket();
    if (g_server_fd < 0) return 1;

    // Setup telemetry timer
    g_timer_fd = setup_timer(TELEMETRY_INTERVAL_MS);
    if (g_timer_fd < 0) {
        hlog("ERROR", "timerfd_create() failed: %s", strerror(errno));
        return 1;
    }

    // Add fds to epoll
    struct epoll_event ev;

    ev.events = EPOLLIN;
    ev.data.fd = g_signal_fd;
    epoll_ctl(g_epoll_fd, EPOLL_CTL_ADD, g_signal_fd, &ev);

    ev.events = EPOLLIN;
    ev.data.fd = g_server_fd;
    epoll_ctl(g_epoll_fd, EPOLL_CTL_ADD, g_server_fd, &ev);

    ev.events = EPOLLIN;
    ev.data.fd = g_timer_fd;
    epoll_ctl(g_epoll_fd, EPOLL_CTL_ADD, g_timer_fd, &ev);

    // Initial CPU stat read
    read_cpu_stat(&g_prev_cpu);
    read_net_stats(&g_prev_net_rx, &g_prev_net_tx);
    g_prev_net_time = get_time_ms();

    hlog("INFO", "Event loop started (epoll)");

    // ─── Main Event Loop ──────────────────────────────────────────────────
    struct epoll_event events[MAX_EVENTS];

    while (g_running) {
        int nfds = epoll_wait(g_epoll_fd, events, MAX_EVENTS, -1);

        if (nfds < 0) {
            if (errno == EINTR) continue;
            hlog("ERROR", "epoll_wait() failed: %s", strerror(errno));
            break;
        }

        for (int i = 0; i < nfds; i++) {
            int fd = events[i].data.fd;

            if (fd == g_signal_fd) {
                handle_signal(fd);

            } else if (fd == g_server_fd) {
                accept_client();

            } else if (fd == g_timer_fd) {
                // Drain timer
                uint64_t exp;
                read(g_timer_fd, &exp, sizeof(exp));

                // Update telemetry
                update_telemetry();

                // Broadcast to all clients
                char json[JSON_BUF_SIZE];
                int len = build_telemetry_json(json, sizeof(json));
                broadcast_to_clients(json, len);

            } else {
                // Client data
                if (events[i].events & (EPOLLERR | EPOLLHUP)) {
                    handle_client_data(fd);
                } else if (events[i].events & EPOLLIN) {
                    handle_client_data(fd);
                }
            }
        }
    }

    cleanup();
    hlog("INFO", "Hyperion daemon stopped");
    return 0;
}
