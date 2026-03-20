#!/system/bin/sh
# =============================================================================
# Hyperion Project - Battery Health Monitor
# Made by ShadowBytePrjkt
# =============================================================================
# Advanced battery health tracking with cycle counting and SoH estimation
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
BATTERY_LOG="$HYPERION_DIR/data/battery_health.json"

get_battery_health() {
    # Try to get battery health from various sources
    local health="Unknown"
    local capacity="Unknown"
    local voltage="Unknown"
    local temp="Unknown"
    local current="Unknown"
    local power="Unknown"

    # Capacity (design vs current)
    capacity=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)
    capacity="${capacity}%"

    # Health
    health=$(cat /sys/class/power_supply/battery/health 2>/dev/null || echo "Unknown")

    # Voltage
    voltage=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null)
    if [ -n "$voltage" ] && [ "$voltage" -gt 0 ]; then
        voltage=$((voltage / 1000))
        voltage="${voltage}mV"
    fi

    # Temperature
    temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)
    if [ -n "$temp" ]; then
        temp=$((temp / 10))
        temp="${temp}°C"
    fi

    # Current
    current=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)
    if [ -n "$current" ]; then
        current=$((current / 1000))
        current="${current}mA"
    fi

    # Power
    power=$(cat /sys/class/power_supply/battery/power_now 2>/dev/null)
    if [ -n "$power" ]; then
        power=$((power / 1000))
        power="${power}mW"
    fi

    # Estimate SoH (State of Health) based on capacity ratio if available
    local design_capacity
    design_capacity=$(cat /sys/class/power_supply/battery/charge_full_design 2>/dev/null)
    local full_capacity
    full_capacity=$(cat /sys/class/power_supply/battery/charge_full 2>/dev/null)

    local soh="Unknown"
    if [ -n "$design_capacity" ] && [ -n "$full_capacity" ] && [ "$design_capacity" -gt 0 ]; then
        soh=$((full_capacity * 100 / design_capacity))
        soh="${soh}%"
    fi

    # Get cycle count if available
    local cycles
    cycles=$(cat /sys/class/power_supply/battery/cycle_count 2>/dev/null || echo "N/A")

    # Output JSON
    python3 -c "
import json
from datetime import datetime

data = {
    'timestamp': datetime.now().isoformat(),
    'capacity': '$capacity',
    'health': '$health',
    'soh': '$soh',
    'voltage': '$voltage',
    'temperature': '$temp',
    'current': '$current',
    'power': '$power',
    'cycles': '$cycles'
}
print(json.dumps(data, indent=2))
"
}

log_battery_stats() {
    local stats
    stats=$(get_battery_health)

    # Append to log file
    echo "$stats" >> "$HYPERION_DIR/logs/battery_health.log"

    # Keep last 1000 entries
    local count
    count=$(wc -l < "$HYPERION_DIR/logs/battery_health.log")
    if [ "$count" -gt 1000 ]; then
        tail -n 500 "$HYPERION_DIR/logs/battery_health.log" > "$HYPERION_DIR/logs/battery_health.tmp"
        mv "$HYPERION_DIR/logs/battery_health.tmp" "$HYPERION_DIR/logs/battery_health.log"
    fi

    echo "$stats"
}

get_summary() {
    if [ ! -f "$HYPERION_DIR/logs/battery_health.log" ]; then
        echo "No battery data logged yet"
        return
    fi

    python3 -c "
import json

# Read all entries
entries = []
with open('$HYPERION_DIR/logs/battery_health.log') as f:
    for line in f:
        try:
            entries.append(json.loads(line))
        except:
            pass

if not entries:
    print('No valid data found')
    exit()

# Get latest
latest = entries[-1]

# Calculate averages
temps = [e.get('temperature', '0°C').replace('°C', '') for e in entries if e.get('temperature')]
temps = [float(t) for t in temps if t.replace('.', '').isdigit()]

avg_temp = sum(temps) / len(temps) if temps else 0

# Get cycle count
cycles = latest.get('cycles', 'N/A')

print('=== Battery Health Summary ===')
print(f'Current Capacity: {latest.get(\"capacity\", \"N/A\")}')
print(f'State of Health: {latest.get(\"soh\", \"N/A\")}')
print(f'Health Status: {latest.get(\"health\", \"N/A\")}')
print(f'Cycle Count: {cycles}')
print(f'Average Temp: {avg_temp:.1f}°C')
print(f'Last Updated: {latest.get(\"timestamp\", \"N/A\")}')
"
}

case "$1" in
    health)   get_battery_health ;;
    log)     log_battery_stats ;;
    summary) get_summary ;;
    *)       get_battery_health ;;
esac
