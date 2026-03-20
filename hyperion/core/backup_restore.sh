#!/system/bin/sh
# =============================================================================
# Hyperion Project - Backup & Restore System
# Made by ShadowBytePrjkt
# =============================================================================
# Complete backup/restore for all settings, profiles, and learning data
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
BACKUP_DIR="/data/adb/hyperion/backup"

backup() {
    local backup_name="${1:-$(date +%Y%m%d_%H%M%S)}"
    local backup_path="$BACKUP_DIR/${backup_name}.tar.gz"

    mkdir -p "$BACKUP_DIR"

    echo "Creating backup: $backup_name"

    # Backup config files
    tar -czf "$backup_path" \
        -C "$HYPERION_DIR" \
        config/ \
        profiles/ \
        data/ \
        current_profile \
        2>/dev/null

    # Keep only last 10 backups
    ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | tail -n +11 | xargs -r rm

    echo "Backup created: $backup_path"
    echo "$backup_path"
}

restore() {
    local backup_file="$1"

    if [ -z "$backup_file" ]; then
        echo "Available backups:"
        ls -la "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No backups found"
        return 1
    fi

    if [ ! -f "$backup_file" ]; then
        echo "Backup not found: $backup_file"
        return 1
    fi

    echo "Restoring from: $backup_file"

    # Extract to temp location first
    local temp_dir="$BACKUP_DIR/restore_temp"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"

    tar -xzf "$backup_file" -C "$temp_dir"

    # Restore config
    cp -r "$temp_dir/config/"* "$HYPERION_DIR/config/" 2>/dev/null
    cp -r "$temp_dir/profiles/"* "$HYPERION_DIR/profiles/" 2>/dev/null
    cp -r "$temp_dir/data/"* "$HYPERION_DIR/data/" 2>/dev/null
    [ -f "$temp_dir/current_profile" ] && cp "$temp_dir/current_profile" "$HYPERION_DIR/current_profile"

    rm -rf "$temp_dir"

    echo "Restore complete!"
}

list_backups() {
    echo "Available backups:"
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No backups found"
}

export_settings() {
    local export_file="${1:-/sdcard/hyperion_settings.json}"

    python3 -c "
import json
import os

data = {
    'version': '1.0.0',
    'export_date': '$(date -u +%Y-%m-%dT%H:%SZ)',
    'profiles': {},
    'app_profiles': {},
    'ai_rules': {},
    'config': {}
}

# Read profiles
for f in os.listdir('/data/adb/hyperion/profiles'):
    if f.endswith('.json'):
        with open(f'/data/adb/hyperion/profiles/{f}') as fp:
            data['profiles'][f] = json.load(fp)

# Read app profiles
with open('/data/adb/hyperion/app_profiles.json') as fp:
    data['app_profiles'] = json.load(fp)

# Read AI rules
with open('/data/adb/hyperion/ai_rules.json') as fp:
    data['ai_rules'] = json.load(fp)

# Read config
with open('/data/adb/hyperion/config.json') as fp:
    data['config'] = json.load(fp)

with open('$export_file', 'w') as fp:
    json.dump(data, fp, indent=2)

print(f'Exported to: $export_file')
"
}

import_settings() {
    local import_file="$1"

    if [ ! -f "$import_file" ]; then
        echo "File not found: $import_file"
        return 1
    fi

    python3 -c "
import json
import shutil

with open('$import_file') as f:
    data = json.load(f)

# Import profiles
if 'profiles' in data:
    for name, content in data['profiles'].items():
        with open(f'/data/adb/hyperion/profiles/{name}', 'w') as fp:
            json.dump(content, fp, indent=2)

# Import app profiles
if 'app_profiles' in data:
    with open('/data/adb/hyperion/app_profiles.json', 'w') as fp:
        json.dump(data['app_profiles'], fp, indent=2)

# Import AI rules
if 'ai_rules' in data:
    with open('/data/adb/hyperion/ai_rules.json', 'w') as fp:
        json.dump(data['ai_rules'], fp, indent=2)

# Import config
if 'config' in data:
    with open('/data/adb/hyperion/config.json', 'w') as fp:
        json.dump(data['config'], fp, indent=2)

print('Settings imported successfully!')
"
}

case "$1" in
    backup)    backup "${2:-}" ;;
    restore)   restore "$2" ;;
    list)      list_backups ;;
    export)    export_settings "${2:-}" ;;
    import)    import_settings "$2" ;;
    *)         echo "Usage: $0 [backup|restore|list|export|import] [args...]"
esac
