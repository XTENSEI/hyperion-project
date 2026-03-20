// Hyperion - Mobile-First WebUI App
// Works with KSU APIs

const MODPATH = '/data/adb/modules/hyperion_project';
const CONFIG_DIR = '/data/adb/.config/hyperion';

// KSU API - check if available
const ksuApi = typeof ksu !== 'undefined' ? ksu : null;

// Execute shell command via KSU API
async function run(cmd) {
    return new Promise((resolve) => {
        if (ksuApi && typeof ksuApi.exec === 'function') {
            try {
                const callbackName = 'cb_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
                window[callbackName] = (errno, stdout, stderr) => {
                    resolve({ errno, stdout: stdout || '', stderr: stderr || '' });
                    setTimeout(() => { delete window[callbackName]; }, 1000);
                };
                // Call KSU exec properly
                ksuApi.exec(cmd, callbackName);
                // Timeout fallback
                setTimeout(() => {
                    if (window[callbackName]) {
                        resolve({ errno: -1, stdout: '', stderr: 'timeout' });
                        delete window[callbackName];
                    }
                }, 5000);
            } catch (e) {
                resolve({ errno: -1, stdout: '', stderr: String(e) });
            }
        } else {
            // Fallback for non-KSU environment
            resolve({ errno: -1, stdout: '', stderr: 'KSU not available' });
        }
    });
}

// Toast notification
function showToast(message) {
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;
    document.body.appendChild(toast);
    
    setTimeout(() => toast.classList.add('show'), 10);
    setTimeout(() => {
        toast.classList.remove('show');
        setTimeout(() => toast.remove(), 300);
    }, 2000);
}

// KSU toast wrapper
function toast(msg) {
    if (ksuApi && typeof ksuApi.toast === 'function') {
        try { ksuApi.toast(msg); } catch (e) { showToast(msg); }
    } else {
        showToast(msg);
    }
}

// Show toast notification
function showToast(message) {
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;
    document.body.appendChild(toast);
    
    setTimeout(() => toast.classList.add('show'), 10);
    setTimeout(() => {
        toast.classList.remove('show');
        setTimeout(() => toast.remove(), 300);
    }, 2000);
}

// Profile Functions
async function applyProfile(profile) {
    const result = await run(`sh ${MODPATH}/scripts/profile_manager.sh apply ${profile}`);
    toast(`Profile: ${profile}`);
    updateProfileButtons(profile);
}

function updateProfileButtons(activeProfile) {
    document.querySelectorAll('.profile-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.profile === activeProfile);
        if (btn.dataset.profile === activeProfile) {
            btn.style.borderColor = 'var(--primary)';
        } else {
            btn.style.borderColor = 'var(--border)';
        }
    });
}

// CPU Functions
async function setCPUGovernor(governor) {
    await run(`echo ${governor} > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`);
    toast(`CPU: ${governor}`);
}

async function getCPUInfo() {
    const freq = await run('cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq');
    const maxFreq = await run('cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq');
    const gov = await run('cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor');
    
    const currentMHz = Math.round((parseInt(freq.stdout) || 0) / 1000);
    const maxMHz = Math.round((parseInt(maxFreq.stdout) || 0) / 1000);
    
    document.getElementById('cpuInfo').innerHTML = `
        Governor: ${gov.stdout.trim() || 'N/A'}<br>
        Current: ${currentMHz} MHz<br>
        Max: ${maxMHz} MHz
    `;
}

// GPU Functions
async function setGPUGovernor(governor) {
    await run(`echo ${governor} > /sys/class/kgsl/kgsl-3d0/pwrscale/trustzone/governor`);
    ksu.toast(`GPU: ${governor}`);
}

async function getGPUInfo() {
    const freq = await run('cat /sys/class/kgsl/kgsl-3d0/gpu_busy');
    document.getElementById('gpuInfo').innerHTML = `
        GPU Load: ${freq.stdout.trim() || 'N/A'}%
    `;
}

// Memory Functions
async function setMemoryPreset(preset) {
    await run(`sh ${MODPATH}/scripts/memory_presets.sh ${preset}`);
    ksu.toast(`Memory: ${preset}`);
}

// IO Functions
async function setIOScheduler(scheduler) {
    await run(`echo ${scheduler} > /sys/block/*/queue/scheduler`);
    ksu.toast(`IO: ${scheduler}`);
}

// Display Functions
async function setRefreshRate(rate) {
    await run(`settings put system peak_refresh_rate ${rate}`);
    ksu.toast(`Refresh: ${rate}Hz`);
}

async function toggleDCDimming(enabled) {
    // Implementation depends on device
    ksu.toast(`DC Dimming: ${enabled ? 'ON' : 'OFF'}`);
}

async function toggleHBM(enabled) {
    await run(`echo ${enabled ? '1' : '0'} > /sys/class/leds/wled/boost`);
    ksu.toast(`HBM: ${enabled ? 'ON' : 'OFF'}`);
}

// Thermal Functions
async function setThermalProfile(profile) {
    await run(`sh ${MODPATH}/scripts/thermal.sh ${profile}`);
    ksu.toast(`Thermal: ${profile}`);
}

// Battery Functions
async function setBatteryProfile(profile) {
    await run(`sh ${MODPATH}/scripts/battery.sh ${profile}`);
    ksu.toast(`Battery: ${profile}`);
}

async function toggleBypass(enabled) {
    await run(`sh ${MODPATH}/scripts/bypass_charging.sh ${enabled ? 'enable' : 'disable'}`);
    ksu.toast(`Bypass: ${enabled ? 'ON' : 'OFF'}`);
}

// Game Booster Functions
async function toggleGameBooster(enabled) {
    await run(`sh ${MODPATH}/scripts/game_booster.sh ${enabled ? 'enable' : 'disable'}`);
    ksu.toast(`Game Booster: ${enabled ? 'ON' : 'OFF'}`);
}

async function toggleFPSBoost(enabled) {
    ksu.toast(`FPS Boost: ${enabled ? 'ON' : 'OFF'}`);
}

async function toggleTouchBoost(enabled) {
    ksu.toast(`Touch Boost: ${enabled ? 'ON' : 'OFF'}`);
}

// AI Functions
async function toggleAI(enabled) {
    await run(`echo ${enabled} > ${CONFIG_DIR}/ai_enabled`);
    toast(`AI: ${enabled ? 'ON' : 'OFF'}`);
}

// System Stats - Simplified to prevent freezing
async function updateStats() {
    try {
        // Single combined command for efficiency
        const stats = await run('echo $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq) $(cat /proc/meminfo | grep MemAvailable) $(cat /sys/class/thermal/thermal_zone0/temp) $(cat /sys/class/power_supply/battery/capacity)');
        
        const parts = (stats.stdout || '').trim().split(/\s+/);
        if (parts.length >= 4) {
            const cpuMHz = Math.round((parseInt(parts[0]) || 0) / 1000);
            const memAvailKB = parseInt(parts[1].split(':')[1]) || 0;
            const tempC = Math.round((parseInt(parts[2]) || 0) / 1000);
            const battLevel = parseInt(parts[3]) || 0;
            
            // Get total RAM separately (needed for percentage)
            const memTotal = await run('grep MemTotal /proc/meminfo');
            const totalKB = parseInt((memTotal.stdout || '').split(':')[1]) || 1;
            const ramPercent = Math.round(((totalKB - memAvailKB) / totalKB) * 100);
            
            // Update UI
            const cpuEl = document.getElementById('stat-cpu');
            const ramEl = document.getElementById('stat-ram');
            const tempEl = document.getElementById('stat-temp');
            const battEl = document.getElementById('stat-battery');
            
            if (cpuEl) cpuEl.textContent = cpuMHz;
            if (ramEl) ramEl.textContent = ramPercent + '%';
            if (tempEl) tempEl.textContent = tempC + '°';
            if (battEl) battEl.textContent = battLevel + '%';
            
            // Also update alternative elements
            const cpuFreqEl = document.getElementById('cpuFreq');
            const battLevelEl = document.getElementById('batteryLevel');
            if (cpuFreqEl) cpuFreqEl.textContent = cpuMHz;
            if (battLevelEl) battLevelEl.textContent = battLevel + '%';
        }
    } catch (e) {
        console.error('Stats error:', e);
    }
}

// Navigation
function initNavigation() {
    const navBtns = document.querySelectorAll('.nav-btn');
    const pages = document.querySelectorAll('.page');
    
    navBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            const targetPage = btn.dataset.page;
            
            // Update nav
            navBtns.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            
            // Update pages
            pages.forEach(p => p.classList.remove('active'));
            document.getElementById(targetPage).classList.add('active');
            
            // Load page-specific data
            if (targetPage === 'page-cpu') getCPUInfo();
            if (targetPage === 'page-gpu') getGPUInfo();
        });
    });
}

// Load saved profile
async function loadSavedProfile() {
    try {
        const result = await run(`cat ${CONFIG_DIR}/current_profile`);
        const profile = result.stdout.trim() || 'balanced';
        updateProfileButtons(profile);
    } catch (e) {
        console.log('Using default profile');
    }
}

// Uninstall
function uninstallModule() {
    if (confirm('Uninstall Hyperion module?')) {
        ksu.toast('Please uninstall from KernelSU');
    }
}

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    initNavigation();
    loadSavedProfile();
    
    // Start stats polling (slower to prevent freezing)
    updateStats();
    setInterval(updateStats, 10000);
    
    console.log('Hyperion WebUI ready');
});
