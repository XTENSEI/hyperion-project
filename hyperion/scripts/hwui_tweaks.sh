#!/system/bin/sh
# =============================================================================
# Hyperion Project - HWUI Rendering Tweaks
# Made by ShadowBytePrjkt
# =============================================================================
# Control Skia, Vulkan, and HWUI rendering options
# =============================================================================

HYPERION_DIR="/data/adb/hyperion"
LOG_FILE="$HYPERION_DIR/logs/hwui.log"

klog() {
    echo "[$(date -u +%H:%M:%S)][HWUI] $1" | tee -a "$LOG_FILE"
}

write() {
    [ -f "$1" ] && [ -w "$1" ] && echo "$2" > "$1" 2>/dev/null
}

# ─── Property Settings ────────────────────────────────────────────────────────
set_property() {
    local prop="$1"
    local value="$2"
    
    # Set property via setprop
    setprop "$prop" "$value" 2>/dev/null
    
    # Also try persist property
    setprop "persist.$prop" "$value" 2>/dev/null
    
    klog "Set $prop = $value"
}

# ─── Set Renderer ────────────────────────────────────────────────────────────
set_renderer() {
    local renderer="$1"
    klog "Setting renderer to: $renderer"
    
    case "$renderer" in
        opengl)
            set_property "debug.hwui.renderer" "opengl"
            set_property "debug.renderengine.mode" "opengl"
            ;;
        skiavk)
            set_property "debug.hwui.renderer" "skiagl"
            set_property "debug.renderengine.mode" "vk"
            # Enable Skia Vulkan
            set_property "debug.skia.vulkan" "true"
            set_property "debug.skia.enable_vulkan" "true"
            ;;
        skiavkthreaded)
            set_property "debug.hwui.renderer" "skiagl"
            set_property "debug.renderengine.mode" "vk"
            set_property "debug.skia.vulkan" "true"
            set_property "debug.skia.enable_vulkan" "true"
            set_property "debug.hwui.threaded" "true"
            set_property "debug.hwui.use_threads" "true"
            ;;
        filament)
            set_property "debug.hwui.renderer" "filament"
            set_property "debug.renderengine.mode" "filament"
            ;;
        *)
            klog "Unknown renderer: $renderer"
            ;;
    esac
}

# ─── Enable Debug Overdraw ───────────────────────────────────────────────────
toggle_overdraw() {
    local enabled="$1"
    
    if [ "$enabled" = "true" ]; then
        set_property "debug.hwui.show_overdraw" "true"
        set_property "debug.hwui.overdraw" "true"
        klog "Overdraw visualization enabled"
    else
        set_property "debug.hwui.show_overdraw" "false"
        set_property "debug.hwui.overdraw" "false"
        klog "Overdraw visualization disabled"
    fi
}

# ─── Enable HWUI Profiling ───────────────────────────────────────────────────
toggle_profile() {
    local enabled="$1"
    
    if [ "$enabled" = "true" ]; then
        set_property "debug.hwui.profile" "true"
        set_property "debug.hwui.profile_verbose" "true"
        set_property "debug.hwui.show_fps" "true"
        klog "HWUI profiling enabled"
    else
        set_property "debug.hwui.profile" "false"
        set_property "debug.hwui.profile_verbose" "false"
        set_property "debug.hwui.show_fps" "false"
        klog "HWUI profiling disabled"
    fi
}

# ─── Enable Render Thread ────────────────────────────────────────────────────
toggle_render_thread() {
    local enabled="$1"
    
    if [ "$enabled" = "true" ]; then
        set_property "debug.hwui.render_thread" "true"
        set_property "debug.hwui.use_threads" "true"
        klog "Render thread enabled"
    else
        set_property "debug.hwui.render_thread" "false"
        set_property "debug.hwui.use_threads" "false"
        klog "Render thread disabled"
    fi
}

# ─── Enable Vulkan ────────────────────────────────────────────────────────────
toggle_vulkan() {
    local enabled="$1"
    
    if [ "$enabled" = "true" ]; then
        set_property "debug.vulkan" "true"
        set_property "debug.vulkan.force" "true"
        set_property "debug.hwui.use_vulkan" "true"
        # Also enable Skia Vulkan
        set_property "debug.skia.vulkan" "true"
        set_property "debug.skia.enable_vulkan" "true"
        klog "Vulkan enabled"
    else
        set_property "debug.vulkan" "false"
        set_property "debug.vulkan.force" "false"
        set_property "debug.hwui.use_vulkan" "false"
        set_property "debug.skia.vulkan" "false"
        set_property "debug.skia.enable_vulkan" "false"
        klog "Vulkan disabled"
    fi
}

# ─── Force 16-bit ────────────────────────────────────────────────────────────
toggle_16bit() {
    local enabled="$1"
    
    if [ "$enabled" = "true" ]; then
        set_property "debug.hwui.force_16bit" "true"
        set_property "debug.hwui.force_16bpp" "true"
        klog "16-bit forced"
    else
        set_property "debug.hwui.force_16bit" "false"
        set_property "debug.hwui.force_16bpp" "false"
        klog "16-bit disabled"
    fi
}

# ─── Triple Buffer ────────────────────────────────────────────────────────────
toggle_triple_buffer() {
    local enabled="$1"
    
    if [ "$enabled" = "true" ]; then
        set_property "debug.hwui.triple_buffer" "true"
        set_property "debug.egl.triple_buffer" "true"
        klog "Triple buffer enabled"
    else
        set_property "debug.hwui.triple_buffer" "false"
        set_property "debug.egl.triple_buffer" "false"
        klog "Triple buffer disabled"
    fi
}

# ─── Blur Optimization ───────────────────────────────────────────────────────
toggle_blur() {
    local enabled="$1"
    
    if [ "$enabled" = "true" ]; then
        set_property "debug.hwui.enable_blur" "true"
        set_property "debug.hwui.blur_optimization" "true"
        set_property "debug.skia.enable_blur" "true"
        klog "Blur optimization enabled"
    else
        set_property "debug.hwui.enable_blur" "false"
        set_property "debug.hwui.blur_optimization" "false"
        set_property "debug.skia.enable_blur" "false"
        klog "Blur optimization disabled"
    fi
}

# ─── Get Current Settings ───────────────────────────────────────────────────
get_settings() {
    python3 -c "
import subprocess

def get_prop(prop):
    try:
        result = subprocess.run(['getprop', prop], capture_output=True, text=True)
        return result.stdout.strip()
    except:
        return ''

settings = {
    'renderer': get_prop('debug.hwui.renderer') or 'default',
    'debug_overdraw': get_prop('debug.hwui.show_overdraw') == 'true',
    'profile_hwui': get_prop('debug.hwui.profile') == 'true',
    'render_thread': get_prop('debug.hwui.render_thread') == 'true',
    'enable_vulkan': get_prop('debug.vulkan') == 'true',
    'force_16bit': get_prop('debug.hwui.force_16bit') == 'true',
    'triple_buffer': get_prop('debug.hwui.triple_buffer') == 'true',
    'blur_optimization': get_prop('debug.hwui.enable_blur') == 'true'
}

import json
print(json.dumps(settings, indent=2))
"
}

# ─── Apply Gaming Preset ──────────────────────────────────────────────────────
apply_gaming_preset() {
    klog "Applying gaming HWUI preset"
    
    set_renderer "skiavkthreaded"
    toggle_vulkan "true"
    toggle_render_thread "true"
    toggle_triple_buffer "true"
    toggle_blur "true"
    
    klog "Gaming preset applied"
}

# ─── Apply Battery Saver Preset ──────────────────────────────────────────────
apply_battery_preset() {
    klog "Applying battery saver HWUI preset"
    
    set_renderer "opengl"
    toggle_vulkan "false"
    toggle_render_thread "false"
    toggle_triple_buffer "false"
    toggle_blur "false"
    toggle_16bit "true"
    
    klog "Battery saver preset applied"
}

# ─── Main ────────────────────────────────────────────────────────────────────
case "$1" in
    renderer)
        set_renderer "${2:-skiavk}"
        ;;
    overdraw)
        toggle_overdraw "${2:-false}"
        ;;
    profile)
        toggle_profile "${2:-false}"
        ;;
    render_thread)
        toggle_render_thread "${2:-true}"
        ;;
    vulkan)
        toggle_vulkan "${2:-true}"
        ;;
    16bit)
        toggle_16bit "${2:-false}"
        ;;
    triple_buffer)
        toggle_triple_buffer "${2:-true}"
        ;;
    blur)
        toggle_blur "${2:-true}"
        ;;
    gaming)
        apply_gaming_preset
        ;;
    battery)
        apply_battery_preset
        ;;
    settings)
        get_settings
        ;;
    *)
        echo "Usage: $0 {renderer|overdraw|profile|render_thread|vulkan|16bit|triple_buffer|blur|gaming|battery|settings} [value]"
        ;;
esac
