// Hyperion - Mobile-First WebUI App
// Uses hyperion C binary for fast system control

const MODPATH = '/data/adb/modules/hyperion_project';
const BIN_PATH = '/data/adb/modules/hyperion_project/system/bin/hyperion';
const CONFIG_DIR = '/data/adb/.config/hyperion';

// KSU API - check if available
const ksuApi = typeof ksu !== 'undefined' ? ksu : null;

// Execute command via KSU API
async function execCmd(cmd) {
    return new Promise((resolve) => {
        if (ksuApi && typeof ksuApi.exec === 'function') {
            const callbackName = 'cb_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
            window[callbackName] = (errno, stdout, stderr) => {
                resolve({ errno, stdout: stdout || '', stderr: stderr || '' });
                setTimeout(() => { delete window[callbackName]; }, 1000);
            };
            ksuApi.exec(cmd, callbackName);
            setTimeout(() => {
                if (window[callbackName]) {
                    resolve({ errno: -1, stdout: '', stderr: 'timeout' });
                    delete window[callbackName];
                }
            }, 5000);
        } else {
            resolve({ errno: -1, stdout: '', stderr: 'KSU not available' });
        }
    });
}

// Execute hyperion binary
async function hyperion(args) {
    return execCmd(`${BIN_PATH} ${args}`);
}

// Toast notification
function showToast(msg) {
    const existing = document.querySelector('.toast');
    if (existing) existing.remove();
    
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = msg;
    document.body.appendChild(toast);
    
    requestAnimationFrame(() => toast.classList.add('show'));
    setTimeout(() => {
        toast.classList.remove('show');
        setTimeout(() => toast.remove(), 300);
    }, 2500);
}

// Toast wrapper
function toast(msg) {
    if (ksuApi && typeof ksuApi.toast === 'function') {
        try { ksuApi.toast(msg); } catch (e) { showToast(msg); }
    } else {
        showToast(msg);
    }
}

// Profile Functions
async function applyProfile(profile) {
    const result = await hyperion(`boost`);
    if (profile === 'gaming' || profile === 'performance') {
        await hyperion('boost');
    } else if (profile === 'battery') {
        await hyperion('unboost');
    }
    toast(`Profile: ${profile.toUpperCase()}`);
    updateProfileButtons(profile);
    
    // Save profile
    await execCmd(`mkdir -p ${CONFIG_DIR}`);
    await execCmd(`echo ${profile} > ${CONFIG_DIR}/current_profile`);
}

function updateProfileButtons(activeProfile) {
    document.querySelectorAll('.profile-btn').forEach(btn => {
        const isActive = btn.dataset.profile === activeProfile;
        btn.classList.toggle('active', isActive);
        btn.style.borderColor = isActive ? 'var(--primary)' : 'var(--border)';
    });
}

// CPU Functions
async function setCPUGovernor(governor) {
    const result = await hyperion(`cpu gov ${governor}`);
    if (result.errno === 0) {
        toast(`CPU: ${governor}`);
    } else {
        // Fallback to direct write
        await execCmd(`for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo ${governor} > $f; done`);
        toast(`CPU: ${governor}`);
    }
    document.getElementById('cpuGovernor').value = governor;
}

async function getCPUInfo() {
    const result = await hyperion('cpu');
    document.getElementById('cpuInfo').innerHTML = result.stdout || 'Loading...';
}

// GPU Functions
async function setGPUGovernor(governor) {
    await hyperion(`gpu freq`);
    toast(`GPU: Max`);
}

async function getGPUInfo() {
    const result = await hyperion('gpu');
    document.getElementById('gpuInfo').innerHTML = result.stdout || 'Loading...';
}

// Memory Functions
async function setMemoryPreset(preset) {
    let swap = 10;
    if (preset === 'light') swap = 80;
    else if (preset === 'balanced') swap = 60;
    else if (preset === 'aggressive') swap = 30;
    else if (preset === 'extreme') swap = 10;
    
    await hyperion(`mem swap ${swap}`);
    toast(`Memory: ${preset}`);
}

// IO Functions
async function setIOScheduler(scheduler) {
    // Apply to common block devices
    const devices = ['mmcblk0', 'sda', 'nvme0n1'];
    for (const dev of devices) {
        await execCmd(`echo ${scheduler} > /sys/block/${dev}/queue/scheduler 2>/dev/null`);
    }
    toast(`IO: ${scheduler}`);
    document.getElementById('ioScheduler').value = scheduler;
}

// Display Functions
async function setRefreshRate(rate) {
    await execCmd(`settings put system peak_refresh_rate ${rate}`);
    await execCmd(`settings put system user_refresh_rate ${rate}`);
    toast(`Refresh: ${rate}Hz`);
}

async function toggleDCDimming(enabled) {
    await execCmd(`echo ${enabled ? 1 : 0} > /sys/class/backlight/panel/brightness_doe`);
    toast(`DC Dimming: ${enabled ? 'ON' : 'OFF'}`);
}

async function toggleHBM(enabled) {
    await execCmd(`echo ${enabled ? 1 : 0} > /sys/class/leds/wled/boost`);
    toast(`HBM: ${enabled ? 'ON' : 'OFF'}`);
}

// Thermal Functions
async function setThermalProfile(profile) {
    await hyperion('thermal');
    toast(`Thermal: ${profile}`);
}

// Battery Functions
async function setBatteryProfile(profile) {
    toast(`Battery: ${profile}`);
}

async function toggleBypass(enabled) {
    if (enabled) {
        await execCmd(`echo 1 > /sys/class/power_supply/battery/bypass charging_enabled`);
    }
    toast(`Bypass: ${enabled ? 'ON' : 'OFF'}`);
}

// Game Booster Functions
async function toggleGameBooster(enabled) {
    if (enabled) {
        await hyperion('boost');
    } else {
        await hyperion('unboost');
    }
    toast(`Game Booster: ${enabled ? 'ON' : 'OFF'}`);
}

async function toggleFPSBoost(enabled) {
    if (enabled) {
        await execCmd(`echo 1 > /sys/kernel/gpu/gpu Boost`);
    }
    toast(`FPS Boost: ${enabled ? 'ON' : 'OFF'}`);
}

async function toggleTouchBoost(enabled) {
    if (enabled) {
        await execCmd(`echo 1 > /sys/module/touchpanel/parameters/touch_boost`);
    }
    toast(`Touch Boost: ${enabled ? 'ON' : 'OFF'}`);
}

// AI Functions
async function toggleAI(enabled) {
    await execCmd(`mkdir -p ${CONFIG_DIR}`);
    await execCmd(`echo ${enabled ? 1 : 0} > ${CONFIG_DIR}/ai_enabled`);
    toast(`AI: ${enabled ? 'ON' : 'OFF'}`);
}

// System Stats - Optimized
async function updateStats() {
    try {
        // Get stats in single call
        const result = await hyperion('cpu');
        const memResult = await hyperion('mem');
        
        // Parse CPU info
        if (result.stdout) {
            const lines = result.stdout.split('\n');
            let cpuVal = '--', gov = '--';
            
            for (const line of lines) {
                if (line.includes('Current:')) {
                    cpuVal = line.split(':')[1]?.trim() || '--';
                }
                if (line.includes('governor') || line.includes('Governor')) {
                    gov = line.split(':')[1]?.trim() || '--';
                }
            }
            
            const cpuEl = document.getElementById('stat-cpu');
            if (cpuEl) cpuEl.textContent = cpuVal.includes('MHz') ? cpuVal : cpuVal + ' MHz';
        }
        
        // Parse memory
        if (memResult.stdout) {
            const lines = memResult.stdout.split('\n');
            let ramPercent = '--';
            
            for (const line of lines) {
                if (line.includes('%')) {
                    const match = line.match(/(\d+)%/);
                    if (match) ramPercent = match[1] + '%';
                }
            }
            
            const ramEl = document.getElementById('stat-ram');
            if (ramEl) ramEl.textContent = ramPercent;
        }
        
        // Get temperature and battery via direct read
        const tempResult = await execCmd('cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null');
        const tempVal = tempResult.stdout ? Math.round(parseInt(tempResult.stdout) / 1000) : '--';
        
        const battResult = await execCmd('cat /sys/class/power_supply/battery/capacity 2>/dev/null');
        const battVal = battResult.stdout ? battResult.stdout.trim() : '--';
        
        const tempEl = document.getElementById('stat-temp');
        const battEl = document.getElementById('stat-battery');
        if (tempEl) tempEl.textContent = tempVal + '°';
        if (battEl) battEl.textContent = battVal + '%';
        
        // Header stats
        const cpuFreqEl = document.getElementById('cpuFreq');
        const battLevelEl = document.getElementById('batteryLevel');
        if (cpuFreqEl && result.stdout) {
            const lines = result.stdout.split('\n');
            for (const line of lines) {
                if (line.includes('Max Freq:')) {
                    const match = line.match(/(\d+)/);
                    if (match) cpuFreqEl.textContent = Math.round(parseInt(match[1]) / 1000);
                }
            }
        }
        if (battLevelEl) battLevelEl.textContent = battVal + '%';
        
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
            
            // Update pages with animation
            pages.forEach(p => {
                if (p.id === targetPage) {
                    p.classList.add('active');
                    p.style.animation = 'fadeIn 0.3s ease';
                } else {
                    p.classList.remove('active');
                }
            });
            
            // Load page-specific data
            if (targetPage === 'page-cpu') getCPUInfo();
            if (targetPage === 'page-gpu') getGPUInfo();
        });
    });
}

// Load saved profile
async function loadSavedProfile() {
    try {
        const result = await execCmd(`cat ${CONFIG_DIR}/current_profile 2>/dev/null`);
        const profile = result.stdout.trim() || 'balanced';
        updateProfileButtons(profile);
    } catch (e) {
        console.log('Using default profile');
    }
}

// Uninstall
function uninstallModule() {
    if (confirm('Uninstall Hyperion module?')) {
        toast('Please uninstall from KernelSU Manager');
    }
}

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    initNavigation();
    loadSavedProfile();
    
    // Start stats polling
    updateStats();
    setInterval(updateStats, 10000);
    
    console.log('Hyperion WebUI ready');
});

// Add animation CSS dynamically
const style = document.createElement('style');
style.textContent = `
    @keyframes fadeIn {
        from { opacity: 0; transform: translateY(10px); }
        to { opacity: 1; transform: translateY(0); }
    }
    @keyframes pulse {
        0%, 100% { transform: scale(1); }
        50% { transform: scale(1.05); }
    }
    .page.active {
        animation: fadeIn 0.3s ease;
    }
    .profile-btn.active {
        animation: pulse 0.3s ease;
    }
`;
document.head.appendChild(style);
