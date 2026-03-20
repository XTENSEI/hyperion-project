#!/system/bin/sh
# =============================================================================
# Hyperion Project - Quick Settings Tile Provider
# Made by ShadowBytePrjkt
# =============================================================================
# Provides a Quick Settings tile for quick profile switching
# Run: settings put secure qs_tile_packages "com.hyperion.project"
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"

case "$1" in
    click)
        # Cycle through profiles on tile click
        current=$(cat "$HYPERION_DIR/current_profile" 2>/dev/null || echo "balanced")
        case "$current" in
            gaming) new="balanced" ;;
            balanced) new="battery" ;;
            battery) new="powersave" ;;
            powersave) new="performance" ;;
            performance) new="gaming" ;;
            *) new="balanced" ;;
        esac
        "$HYPERION_DIR/core/profile_manager.sh" "$new"
        am broadcast -a com.hyperion.TILE_CLICKED --es profile "$new" 2>/dev/null
        ;;
    state)
        # Return current state
        cat "$HYPERION_DIR/current_profile" 2>/dev/null || echo "balanced"
        ;;
    *)
        echo "Tile provider: use 'click' or 'state'"
        ;;
esac
