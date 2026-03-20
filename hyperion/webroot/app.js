// Hyperion - Complete Mobile-First WebUI App
// Uses hyperion C binary for fast system control

const MODPATH = '/data/adb/modules/hyperion_project';
const BIN_PATH = '/data/adb/modules/hyperion_project/system/bin';
const CONFIG_DIR = '/data/adb/.config/hyperion';

// Binary paths
const HYPERION = `${BIN_PATH}/hyperion`;
const HYPERION_CPU = `${BIN_PATH}/hyperion_cpu`;
const HYPERION_GAME = `${BIN_PATH}/hyperion_game`;
const HYPERION_THERMAL = `${BIN_PATH}/hyperion_thermal`;

// KSU API
const ksuApi = typeof ksu !== 'undefined' ? ksu : null;

// Execute command via KSU API
async function execCmd(cmd) {
    return new Promise((resolve) => {
        if (ksuApi && typeof ksuApi.exec === 'function') {
            const callbackName = 'cb_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
            window[callbackName] = function(errno, stdout, stderr) {
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
    return execCmd(`${HYPERION} ${args}`);
}

// Execute hyperion_cpu binary
async function hyperionCpu(args) {
    return execCmd(`${HYPERION_CPU} ${args}`);
}

// Execute hyperion_game binary  
async function hyperionGame(args) {
    return execCmd(`${HYPERION_GAME} ${args}`);
}

// Execute hyperion_thermal binary
async function hyperionThermal(args) {
    return execCmd(`${HYPERION_THERMAL} ${args}`);
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

// ============ PROFILE FUNCTIONS ============

async function applyProfile(profile) {
    // Apply via hyperion binary
    if (profile === 'gaming' || profile === 'performance') {
        await hyperion('boost');
    } else if (profile === 'battery' || profile === 'powersave') {
        await hyperion('unboost');
    }
    
    // Apply CPU governor based on profile
    let gov = 'schedutil';
    if (profile === 'gaming' || profile === 'performance') gov = 'performance';
    if (profile === 'battery' || profile === 'powersave') gov = 'powersave';
    
    await execCmd(`for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo ${gov} > $f 2>/dev/null; done`);
    
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

// ============ CPU FUNCTIONS ============

async function getCPUGovernors() {
    const result = await execCmd('cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null');
    return result.stdout.trim().split(' ');
}

async function setCPUGovernor(governor) {
    const result = await execCmd(`for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo ${governor} > $f 2>/dev/null; done`);
    toast(`CPU Governor: ${governor}`);
    
    const select = document.getElementById('cpuGovernor');
    if (select) select.value = governor;
    
    // Save preference
    await execCmd(`mkdir -p ${CONFIG_DIR}`);
    await execCmd(`echo ${governor} > ${CONFIG_DIR}/cpu_governor`);
}

async function setCPUMinFreq(mhz) {
    await execCmd(`for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq; do echo ${mhz}000 > $f 2>/dev/null; done`);
    toast(`CPU Min: ${mhz} MHz`);
}

async function setCPUMaxFreq(mhz) {
    await execCmd(`for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do echo ${mhz}000 > $f 2>/dev/null; done`);
    toast(`CPU Max: ${mhz} MHz`);
}

async function getCPUInfo() {
    let html = '';
    
    // Get CPU frequencies
    const minFreq = await execCmd('cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq 2>/dev/null');
    const maxFreq = await execCmd('cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null');
    const curFreq = await execCmd('cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null');
    const gov = await execCmd('cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null');
    
    const minMhz = minFreq.stdout ? Math.round(parseInt(minFreq.stdout) / 1000) : '--';
    const maxMhz = maxFreq.stdout ? Math.round(parseInt(maxFreq.stdout) / 1000) : '--';
    const curMhz = curFreq.stdout ? Math.round(parseInt(curFreq.stdout) / 1000) : '--';
    
    html += `<div class="info-row"><span>Current:</span><span>${curMhz} MHz</span></div>`;
    html += `<div class="info-row"><span>Min:</span><span>${minMhz} MHz</span></div>`;
    html += `<div class="info-row"><span>Max:</span><span>${maxMhz} MHz</span></div>`;
    html += `<div class="info-row"><span>Governor:</span><span>${gov.stdout.trim() || '--'}</span></div>`;
    
    // Get CPU cores
    const cores = await execCmd('nproc');
    html += `<div class="info-row"><span>Cores:</span><span>${cores.stdout.trim() || '--'}</span></div>`;
    
    const infoEl = document.getElementById('cpuInfo');
    if (infoEl) infoEl.innerHTML = html;
    
    // Populate governor dropdown
    const govSelect = document.getElementById('cpuGovernor');
    if (govSelect) {
        const availableGovs = await getCPUGovernors();
        govSelect.innerHTML = '';
        availableGovs.forEach(g => {
            const opt = document.createElement('option');
            opt.value = g;
            opt.textContent = g.charAt(0).toUpperCase() + g.slice(1);
            if (g === gov.stdout.trim()) opt.selected = true;
            govSelect.appendChild(opt);
        });
    }
}

// ============ GPU FUNCTIONS ============

async function getGPUGovernors() {
    const paths = [
        '/sys/class/kgsl/kgsl-3d0/devfreq/governor',
        '/sys/class/devfreq/gpu/governor',
        '/sys/devices/platform/gpufreq/gpu_governor'
    ];
    
    for (const p of paths) {
        const result = await execCmd(`cat ${p} 2>/dev/null`);
        if (result.stdout) return result.stdout.trim();
    }
    return 'msm-adreno-tz';
}

async function setGPUGovernor(governor) {
    const paths = [
        '/sys/class/kgsl/kgsl-3d0/devfreq/governor',
        '/sys/class/devfreq/gpu/governor'
    ];
    
    for (const p of paths) {
        await execCmd(`echo ${governor} > ${p} 2>/dev/null`);
    }
    toast(`GPU Governor: ${governor}`);
    
    const select = document.getElementById('gpuGovernor');
    if (select) select.value = governor;
}

async function getGPUInfo() {
    let html = '';
    
    // GPU frequency
    const gpuFreqPaths = [
        '/sys/class/kgsl/kgsl-3d0/gpuclk',
        '/sys/class/devfreq/0.gpu/max_freq',
        '/sys/devices/platform/gpufreq/gpu_max_freq'
    ];
    
    let gpuFreq = '--';
    for (const p of gpuFreqPaths) {
        const result = await execCmd(`cat ${p} 2>/dev/null`);
        if (result.stdout) {
            gpuFreq = Math.round(parseInt(result.stdout) / 1000000) + ' MHz';
            break;
        }
    }
    
    // GPU governor
    const gov = await getGPUGovernors();
    
    html += `<div class="info-row"><span>GPU Clock:</span><span>${gpuFreq}</span></div>`;
    html += `<div class="info-row"><span>Governor:</span><span>${gov}</span></div>`;
    
    // Try to get GPU available governors
    const govPath = '/sys/class/kgsl/kgsl-3d0/devfreq/available_governors';
    const availGovs = await execCmd(`cat ${govPath} 2>/dev/null`);
    if (availGovs.stdout) {
        html += `<div class="info-row"><span>Available:</span><span>${availGovs.stdout.trim().replace(/ /g, ', ')}</span></div>`;
    }
    
    const infoEl = document.getElementById('gpuInfo');
    if (infoEl) infoEl.innerHTML = html;
    
    // Populate governor dropdown
    const govSelect = document.getElementById('gpuGovernor');
    if (govSelect && availGovs.stdout) {
        const govs = availGovs.stdout.trim().split(' ');
        govSelect.innerHTML = '';
        govs.forEach(g => {
            const opt = document.createElement('option');
            opt.value = g;
            opt.textContent = g;
            if (g === gov) opt.selected = true;
            govSelect.appendChild(opt);
        });
    }
}

// ============ MEMORY FUNCTIONS ============

async function setMemoryPreset(preset) {
    let swappiness = 60;
    if (preset === 'light') swappiness = 80;
    else if (preset === 'balanced') swappiness = 60;
    else if (preset === 'aggressive') swappiness = 40;
    else if (preset === 'extreme') swappiness = 20;
    
    await execCmd(`echo ${swappiness} > /proc/sys/vm/swappiness 2>/dev/null`);
    toast(`Memory: ${preset} (swappiness: ${swappiness})`);
}

async function getMemoryInfo() {
    const result = await execCmd('cat /proc/meminfo');
    if (result.stdout) {
        const lines = result.stdout.split('\n');
        let total = 0, free = 0, available = 0;
        
        for (const line of lines) {
            if (line.startsWith('MemTotal:')) total = Math.round(parseInt(line.split()[1]) / 1024);
            if (line.startsWith('MemFree:')) free = Math.round(parseInt(line.split()[1]) / 1024);
            if (line.startsWith('MemAvailable:')) available = Math.round(parseInt(line.split()[1]) / 1024);
        }
        
        const used = total - available;
        const percent = Math.round((used / total) * 100);
        
        const html = `
            <div class="info-row"><span>Total:</span><span>${total} MB</span></div>
            <div class="info-row"><span>Used:</span><span>${used} MB</span></div>
            <div class="info-row"><span>Free:</span><span>${free} MB</span></div>
            <div class="info-row"><span>Usage:</span><span>${percent}%</span></div>
        `;
        
        const infoEl = document.getElementById('memoryInfo');
        if (infoEl) infoEl.innerHTML = html;
    }
}

// ============ IO FUNCTIONS ============

async function getIOSchedulers() {
    const devices = ['mmcblk0', 'sda', 'nvme0n1'];
    let available = [];
    
    for (const dev of devices) {
        const result = await execCmd(`cat /sys/block/${dev}/queue/available_schedulers 2>/dev/null`);
        if (result.stdout) {
            available = result.stdout.trim().split(' ');
            break;
        }
    }
    return available.length > 0 ? available : ['noop', 'deadline', 'cfq', 'bfq'];
}

async function setIOScheduler(scheduler) {
    const devices = ['mmcblk0', 'sda', 'nvme0n1', 'vda'];
    for (const dev of devices) {
        await execCmd(`echo ${scheduler} > /sys/block/${dev}/queue/scheduler 2>/dev/null`);
    }
    toast(`IO Scheduler: ${scheduler}`);
    
    const select = document.getElementById('ioScheduler');
    if (select) select.value = scheduler;
}

async function getIOInfo() {
    const devices = ['mmcblk0', 'sda', 'nvme0n1'];
    let html = '';
    
    for (const dev of devices) {
        const sched = await execCmd(`cat /sys/block/${dev}/queue/scheduler 2>/dev/null`);
        const readAhead = await execCmd(`cat /sys/block/${dev}/queue/read_ahead_kb 2>/dev/null`);
        
        if (sched.stdout) {
            html += `<div class="info-row"><span>${dev}:</span><span>${sched.stdout.trim()}</span></div>`;
            html += `<div class="info-row"><span>${dev} ReadAhead:</span><span>${readAhead.stdout.trim()} KB</span></div>`;
        }
    }
    
    const infoEl = document.getElementById('ioInfo');
    if (infoEl) infoEl.innerHTML = html || 'No IO devices found';
    
    // Populate scheduler dropdown
    const schedSelect = document.getElementById('ioScheduler');
    if (schedSelect) {
        const available = await getIOSchedulers();
        schedSelect.innerHTML = '';
        available.forEach(s => {
            const opt = document.createElement('option');
            opt.value = s;
            opt.textContent = s.toUpperCase();
            schedSelect.appendChild(opt);
        });
    }
}

// ============ DISPLAY FUNCTIONS ============

async function setRefreshRate(rate) {
    await execCmd(`settings put system peak_refresh_rate ${rate}`);
    await execCmd(`settings put system user_refresh_rate ${rate}`);
    toast(`Refresh Rate: ${rate} Hz`);
}

async function getDisplayInfo() {
    let html = '';
    
    // Refresh rate
    const rate = await execCmd('settings get system peak_refresh_rate');
    html += `<div class="info-row"><span>Refresh Rate:</span><span>${rate.stdout.trim() || '--'} Hz</span></div>`;
    
    // Resolution
    const res = await execCmd('wm size');
    html += `<div class="info-row"><span>Resolution:</span><span>${res.stdout.trim() || '--'}</span></div>`;
    
    // Density
    const density = await execCmd('wm density');
    html += `<div class="info-row"><span>Density:</span><span>${density.stdout.trim() || '--'}</span></div>`;
    
    const infoEl = document.getElementById('displayInfo');
    if (infoEl) infoEl.innerHTML = html;
}

async function toggleDCDimming(enabled) {
    const paths = [
        '/sys/class/backlight/panel/brightness_doe',
        '/sys/class/backlight/panel0/brightness_doe',
        '/sys/devices/platform/panel/panel/brightness_doe'
    ];
    
    for (const p of paths) {
        await execCmd(`echo ${enabled ? 1 : 0} > ${p} 2>/dev/null`);
    }
    toast(`DC Dimming: ${enabled ? 'ON' : 'OFF'}`);
}

async function toggleHBM(enabled) {
    const paths = [
        '/sys/class/leds/wled/boost',
        '/sys/class/backlight/panel/hbm',
        '/sys/devices/platform/panel/panel/hbm'
    ];
    
    for (const p of paths) {
        await execCmd(`echo ${enabled ? 1 : 0} > ${p} 2>/dev/null`);
    }
    toast(`High Brightness Mode: ${enabled ? 'ON' : 'OFF'}`);
}

async function toggleAutoBrightness(enabled) {
    await execCmd(`settings put system screen_brightness_mode ${enabled ? 1 : 0}`);
    toast(`Auto Brightness: ${enabled ? 'ON' : 'OFF'}`);
}

// ============ THERMAL FUNCTIONS ============

async function setThermalProfile(profile) {
    // Use hyperion thermal binary
    await hyperionThermal(`profile ${profile}`);
    toast(`Thermal Profile: ${profile}`);
}

async function getThermalInfo() {
    let html = '';
    
    // Get thermal zones
    const zones = await execCmd('ls /sys/class/thermal/thermal_zone* 2>/dev/null');
    
    if (zones.stdout) {
        const zoneList = zones.stdout.trim().split('\n');
        for (const zone of zoneList.slice(0, 4)) {
            const name = zone.split('/').pop();
            const temp = await execCmd(`cat ${zone}/temp 2>/dev/null`);
            const type = await execCmd(`cat ${zone}/type 2>/dev/null`);
            
            const tempC = temp.stdout ? Math.round(parseInt(temp.stdout) / 1000) : '--';
            html += `<div class="info-row"><span>${type.stdout.trim()}:</span><span>${tempC}°C</span></div>`;
        }
    }
    
    const infoEl = document.getElementById('thermalInfo');
    if (infoEl) infoEl.innerHTML = html || 'No thermal info';
}

// ============ BATTERY FUNCTIONS ============

async function getBatteryInfo() {
    let html = '';
    
    const cap = await execCmd('cat /sys/class/power_supply/battery/capacity 2>/dev/null');
    const status = await execCmd('cat /sys/class/power_supply/battery/status 2>/dev/null');
    const temp = await execCmd('cat /sys/class/power_supply/battery/temp 2>/dev/null');
    const volt = await execCmd('cat /sys/class/power_supply/battery/voltage_now 2>/dev/null');
    const current = await execCmd('cat /sys/class/power_supply/battery/current_now 2>/dev/null');
    
    html += `<div class="info-row"><span>Capacity:</span><span>${cap.stdout.trim() || '--'}%</span></div>`;
    html += `<div class="info-row"><span>Status:</span><span>${status.stdout.trim() || '--'}</span></div>`;
    html += `<div class="info-row"><span>Temp:</span><span>${temp.stdout ? (parseInt(temp.stdout) / 10) : '--'}°C</span></div>`;
    html += `<div class="info-row"><span>Voltage:</span><span>${volt.stdout ? (parseInt(volt.stdout) / 1000000).toFixed(2) : '--'} V</span></div>`;
    html += `<div class="info-row"><span>Current:</span><span>${current.stdout ? (parseInt(current.stdout) / 1000) : '--'} mA</span></div>`;
    
    const infoEl = document.getElementById('batteryInfo');
    if (infoEl) infoEl.innerHTML = html;
}

async function setBatteryProfile(profile) {
    toast(`Battery Profile: ${profile}`);
}

async function toggleBypass(enabled) {
    const paths = [
        '/sys/class/power_supply/battery/bypass_charging_enabled',
        '/sys/class/power_supply/battery/force_charge_type',
        '/sys/kernel/fast_charge/force_fast_charge'
    ];
    
    for (const p of paths) {
        await execCmd(`echo ${enabled ? 1 : 0} > ${p} 2>/dev/null`);
    }
    toast(`Bypass Charging: ${enabled ? 'ON' : 'OFF'}`);
}

// ============ GAME BOOSTER FUNCTIONS ============

async function toggleGameBooster(enabled) {
    if (enabled) {
        await hyperionGame('boost');
    } else {
        await hyperionGame('reset');
    }
    toast(`Game Booster: ${enabled ? 'ON' : 'OFF'}`);
}

async function toggleFPSBoost(enabled) {
    const paths = [
        '/sys/kernel/gpu/gpu_boost',
        '/sys/class/kgsl/kgsl-3d0/boost',
        '/sys/devices/platform/gpu/gpu_boost'
    ];
    
    for (const p of paths) {
        await execCmd(`echo ${enabled ? 1 : 0} > ${p} 2>/dev/null`);
    }
    toast(`FPS Boost: ${enabled ? 'ON' : 'OFF'}`);
}

async function toggleTouchBoost(enabled) {
    const paths = [
        '/sys/module/touchpanel/parameters/touch_boost',
        '/sys/class/input/input0/boost',
        '/sys/devices/platform/input/touch_boost'
    ];
    
    for (const p of paths) {
        await execCmd(`echo ${enabled ? 1 : 0} > ${p} 2>/dev/null`);
    }
    toast(`Touch Boost: ${enabled ? 'ON' : 'OFF'}`);
}

async function toggleCoreCtrl(enabled) {
    // CPU core control for gaming
    if (enabled) {
        // Enable all cores
        await execCmd('for f in /sys/devices/system/cpu/cpu*/online; do echo 1 > $f 2>/dev/null; done');
    }
    toast(`Core Control: ${enabled ? 'ALL CORES' : 'AUTO'}`);
}

// ============ NETWORK FUNCTIONS ============

async function getNetworkInfo() {
    let html = '';
    
    // WiFi status
    const wifi = await execCmd('settings get global wifi_on');
    html += `<div class="info-row"><span>WiFi:</span><span>${wifi.stdout.trim() === '1' ? 'ON' : 'OFF'}</span></div>`;
    
    // Mobile data
    const mobile = await execCmd('settings get global mobile_data 2>/dev/null');
    html += `<div class="info-row"><span>Mobile Data:</span><span>${mobile.stdout.trim() === '1' ? 'ON' : 'OFF'}</span></div>`;
    
    // Hotspot
    const hotspot = await execCmd('settings get global tether_on 2>/dev/null');
    html += `<div class="info-row"><span>Hotspot:</span><span>${hotspot.stdout.trim() === '1' ? 'ON' : 'OFF'}</span></div>`;
    
    const infoEl = document.getElementById('networkInfo');
    if (infoEl) infoEl.innerHTML = html;
}

async function toggleWiFi(enabled) {
    await execCmd(`svc wifi ${enabled ? 'enable' : 'disable'}`);
    toast(`WiFi: ${enabled ? 'ON' : 'OFF'}`);
}

async function toggleMobileData(enabled) {
    await execCmd(`svc data ${enabled ? 'enable' : 'disable'}`);
    toast(`Mobile Data: ${enabled ? 'ON' : 'OFF'}`);
}

// ============ DEVICE INFO FUNCTIONS ============

async function getDeviceInfo() {
    let html = '';
    
    // Model
    const model = await execCmd('getprop ro.product.model');
    const brand = await execCmd('getprop ro.product.brand');
    const device = await execCmd('getprop ro.product.device');
    html += `<div class="info-row"><span>Model:</span><span>${model.stdout.trim()}</span></div>`;
    html += `<div class="info-row"><span>Brand:</span><span>${brand.stdout.trim()}</span></div>`;
    html += `<div class="info-row"><span>Device:</span><span>${device.stdout.trim()}</span></div>`;
    
    // Android
    const android = await execCmd('getprop ro.build.version.release');
    const sdk = await execCmd('getprop ro.build.version.sdk');
    const security = await execCmd('getprop ro.build.version.security_patch');
    html += `<div class="info-row"><span>Android:</span><span>${android.stdout.trim()}</span></div>`;
    html += `<div class="info-row"><span>SDK:</span><span>${sdk.stdout.trim()}</span></div>`;
    html += `<div class="info-row"><span>Security Patch:</span><span>${security.stdout.trim()}</span></div>`;
    
    // Kernel
    const kernel = await execCmd('uname -r');
    html += `<div class="info-row"><span>Kernel:</span><span>${kernel.stdout.trim()}</span></div>`;
    
    // Build
    const build = await execCmd('getprop ro.build.display.id');
    html += `<div class="info-row"><span>Build:</span><span>${build.stdout.trim()}</span></div>`;
    
    const infoEl = document.getElementById('deviceInfo');
    if (infoEl) infoEl.innerHTML = html;
}

// ============ KERNEL TWEAKS ============

async function applyKernelTweaks(preset) {
    if (preset === 'performance') {
        await execCmd('echo 0 > /proc/sys/kernel/randomize_va_space 2>/dev/null');
        await execCmd('echo 0 > /proc/sys/kernel/syscalls_disabled 2>/dev/null');
    } else if (preset === 'battery') {
        await execCmd('echo 1 > /proc/sys/kernel/randomize_va_space 2>/dev/null');
    }
    toast(`Kernel Tweaks: ${preset}`);
}

async function toggleDebug(enabled) {
    await execCmd(`echo ${enabled ? 0 : 1} > /proc/sys/kernel/perf_event_max_sample_rate 2>/dev/null`);
    toast(`Debug: ${enabled ? 'OFF' : 'ON'}`);
}

// ============ AI FUNCTIONS ============

async function toggleAI(enabled) {
    await execCmd(`mkdir -p ${CONFIG_DIR}`);
    await execCmd(`echo ${enabled ? 1 : 0} > ${CONFIG_DIR}/ai_enabled`);
    toast(`AI Mode: ${enabled ? 'ON' : 'OFF'}`);
}

async function loadAIState() {
    const result = await execCmd(`cat ${CONFIG_DIR}/ai_enabled 2>/dev/null`);
    const enabled = result.stdout.trim() === '1';
    const toggle = document.getElementById('toggle-ai');
    if (toggle) toggle.checked = enabled;
}

// ============ SYSTEM STATS ============

async function updateStats() {
    try {
        // CPU frequency
        const cpuResult = await execCmd('cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null');
        const cpuMhz = cpuResult.stdout ? Math.round(parseInt(cpuResult.stdout) / 1000) : 0;
        
        // Memory
        const memResult = await execCmd('cat /proc/meminfo');
        if (memResult.stdout) {
            const lines = memResult.stdout.split('\n');
            let total = 0, available = 0;
            for (const line of lines) {
                if (line.startsWith('MemTotal:')) total = parseInt(line.split()[1]);
                if (line.startsWith('MemAvailable:')) available = parseInt(line.split()[1]);
            }
            const used = total - available;
            const percent = Math.round((used / total) * 100);
            
            const ramEl = document.getElementById('stat-ram');
            if (ramEl) ramEl.textContent = percent + '%';
        }
        
        // Temperature
        const tempResult = await execCmd('cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null');
        const tempVal = tempResult.stdout ? Math.round(parseInt(tempResult.stdout) / 1000) : 0;
        
        // Battery
        const battResult = await execCmd('cat /sys/class/power_supply/battery/capacity 2>/dev/null');
        const battVal = battResult.stdout ? battResult.stdout.trim() : '--';
        
        // Update elements
        const cpuEl = document.getElementById('stat-cpu');
        const tempEl = document.getElementById('stat-temp');
        const battEl = document.getElementById('stat-battery');
        
        if (cpuEl) cpuEl.textContent = cpuMhz + ' MHz';
        if (tempEl) tempEl.textContent = tempVal + '°';
        if (battEl) battEl.textContent = battVal + '%';
        
        // Header stats
        const cpuFreqEl = document.getElementById('cpuFreq');
        const battLevelEl = document.getElementById('batteryLevel');
        if (cpuFreqEl) cpuFreqEl.textContent = cpuMhz;
        if (battLevelEl) battLevelEl.textContent = battVal + '%';
        
    } catch (e) {
        console.error('Stats error:', e);
    }
}

// ============ NAVIGATION ============

function initNavigation() {
    const navBtns = document.querySelectorAll('.nav-btn');
    const pages = document.querySelectorAll('.page');
    
    navBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            const targetPage = btn.dataset.page;
            
            navBtns.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            
            pages.forEach(p => {
                if (p.id === targetPage) {
                    p.classList.add('active');
                    p.style.animation = 'fadeIn 0.3s ease';
                } else {
                    p.classList.remove('active');
                }
            });
            
            // Load page data
            loadPageData(targetPage);
        });
    });
}

async function loadPageData(page) {
    switch(page) {
        case 'page-cpu':
            await getCPUInfo();
            break;
        case 'page-gpu':
            await getGPUInfo();
            break;
        case 'page-memory':
            await getMemoryInfo();
            break;
        case 'page-io':
            await getIOInfo();
            break;
        case 'page-display':
            await getDisplayInfo();
            break;
        case 'page-thermal':
            await getThermalInfo();
            break;
        case 'page-battery':
            await getBatteryInfo();
            break;
        case 'page-device':
            await getDeviceInfo();
            break;
        case 'page-network':
            await getNetworkInfo();
            break;
    }
}

// ============ INITIALIZATION ============

async function loadSavedProfile() {
    try {
        const result = await execCmd(`cat ${CONFIG_DIR}/current_profile 2>/dev/null`);
        const profile = result.stdout.trim() || 'balanced';
        updateProfileButtons(profile);
    } catch (e) {
        console.log('Using default profile');
    }
}

function uninstallModule() {
    if (confirm('Uninstall Hyperion module?')) {
        toast('Please uninstall from KernelSU Manager');
    }
}

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    initNavigation();
    loadSavedProfile();
    loadAIState();
    
    // Start stats polling
    updateStats();
    setInterval(updateStats, 5000);
    
    console.log('Hyperion WebUI ready');
});

// Add animation CSS
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
    .info-row {
        display: flex;
        justify-content: space-between;
        padding: 8px 0;
        border-bottom: 1px solid var(--border);
    }
    .info-row:last-child {
        border-bottom: none;
    }
    .info-row span:first-child {
        color: var(--text-secondary);
    }
    .info-row span:last-child {
        color: var(--text-primary);
        font-weight: 500;
    }
`;
document.head.appendChild(style);
