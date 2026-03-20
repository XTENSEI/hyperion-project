#!/usr/bin/env node
// =============================================================================
// Hyperion Project - WebSocket + HTTP Server
// Made by ShadowBytePrjkt
// =============================================================================
// Handles WebSocket connections for real-time updates and HTTP for WebUI
// KSU WebUI Integration: Works inside KernelSU WebUI or KSU WebUI APK
// =============================================================================

const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const WebSocket = require('ws');

const PORT = process.env.PORT || 8080;
const HYPERION_DIR = '/data/adb/hyperion';
const LOG_DIR = `${HYPERION_DIR}/logs`;

// Ensure directories exist
[LOG_DIR, `${HYPERION_DIR}/data`].forEach(dir => {
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
    }
});

// Logger
function log(message) {
    const timestamp = new Date().toISOString();
    const logLine = `[${timestamp}] ${message}\n`;
    fs.appendFileSync(`${LOG_DIR}/server.log`, logLine);
    console.log(logLine.trim());
}

// Execute shell command
function execCommand(command, callback) {
    const shell = spawn('sh', ['-c', command], {
        cwd: HYPERION_DIR,
        env: { ...process.env, PATH: '/sbin:/vendor/bin:/system/bin:/system/xbin' }
    });
    
    let output = '';
    let error = '';
    
    shell.stdout.on('data', (data) => {
        output += data.toString();
    });
    
    shell.stderr.on('data', (data) => {
        error += data.toString();
    });
    
    shell.on('close', (code) => {
        callback(code, output, error);
    });
}

// Get system stats
function getStats() {
    return new Promise((resolve) => {
        execCommand(`
            CPU=\$(cat /proc/cpuinfo | grep "cpu MHz" | head -1 | awk '{print int(\$4)}')
            GPU=\$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null || echo 0)
            GPU=\$((GPU / 1000000))
            TEMP=\$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
            TEMP=\$((TEMP / 1000))
            MEM=\$(awk '/MemAvailable/{a=\$2} /MemTotal/{t=\$2} END{print int((t-a)*100/t)}' /proc/meminfo)
            BATTERY=\$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 0)
            CHARGING=\$(cat /sys/class/power_supply/battery/status 2>/dev/null | grep -c Charging)
            BATT_TEMP=\$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 0)
            BATT_TEMP=\$((BATT_TEMP / 10))
            VOLTAGE=\$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null || echo 0)
            VOLTAGE=\$((VOLTAGE / 1000))
            
            echo "cpu:\${CPU}|gpu:\${GPU}|temp:\${TEMP}|mem:\${MEM}|battery:\${BATTERY}|charging:\${CHARGING}|batt_temp:\${BATT_TEMP}|voltage:\${VOLTAGE}"
        `, (code, output) => {
            const data = {};
            output.trim().split('|').forEach(part => {
                const [key, value] = part.split(':');
                data[key] = value || '0';
            });
            resolve(data);
        });
    });
}

// Get foreground app
function getForegroundApp() {
    return new Promise((resolve) => {
        execCommand(`
            APP=\$(dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp" | head -1 | awk -F'/' '{print \$1}' | awk '{print \$NF}')
            echo "\${APP:-Unknown}"
        `, (code, output) => {
            resolve(output.trim() || 'Unknown');
        });
    });
}

// Get current profile
function getCurrentProfile() {
    return new Promise((resolve) => {
        const profileFile = `${HYPERION_DIR}/data/current_profile.txt`;
        if (fs.existsSync(profileFile)) {
            resolve(fs.readFileSync(profileFile, 'utf8').trim());
        } else {
            resolve('balanced');
        }
    });
}

// Handle WebSocket messages
function handleMessage(ws, message) {
    try {
        const data = JSON.parse(message);
        const { command, ...params } = data;
        
        log(`Command received: ${command}`);
        
        switch (command) {
            case 'get_stats':
                getStats().then(stats => {
                    ws.send(JSON.stringify({ type: 'stats', data: stats }));
                });
                break;
                
            case 'get_profile':
                getCurrentProfile().then(profile => {
                    ws.send(JSON.stringify({ type: 'profile_change', data: { profile } }));
                });
                break;
                
            case 'get_app':
                getForegroundApp().then(app => {
                    ws.send(JSON.stringify({ type: 'app_detect', data: { app } }));
                });
                break;
                
            case 'set_profile':
                const profile = params.profile || 'balanced';
                const scriptPath = `${HYPERION_DIR}/core/profile_manager.sh`;
                execCommand(`sh ${scriptPath} apply ${profile}`, (code, output) => {
                    fs.writeFileSync(`${HYPERION_DIR}/data/current_profile.txt`, profile);
                    ws.send(JSON.stringify({ type: 'profile_change', data: { profile } }));
                    log(`Profile changed to: ${profile}`);
                });
                break;
                
            case 'ai_toggle':
                const aiEnabled = params.enabled ? 'true' : 'false';
                execCommand(`echo ${aiEnabled} > ${HYPERION_DIR}/data/ai_enabled.txt`, () => {
                    ws.send(JSON.stringify({ type: 'ai_status', data: { enabled: params.enabled } }));
                });
                break;
                
            // CPU commands
            case 'set_cpu_governor':
                execCommand(`sh ${HYPERION_DIR}/scripts/cpu.sh governor ${params.governor}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'CPU governor set' } }));
                });
                break;
                
            case 'set_cpu_boost':
                execCommand(`sh ${HYPERION_DIR}/scripts/cpu.sh boost ${params.enabled}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'CPU boost toggled' } }));
                });
                break;
                
            // GPU commands
            case 'set_gpu_max_clock':
                execCommand(`sh ${HYPERION_DIR}/scripts/gpu.sh max ${params.freq}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'GPU max clock set' } }));
                });
                break;
                
            // Memory commands
            case 'set_memory_preset':
                execCommand(`sh ${HYPERION_DIR}/scripts/memory_presets.sh ${params.preset}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Memory preset applied' } }));
                });
                break;
                
            case 'set_zram_size':
                execCommand(`sh ${HYPERION_DIR}/scripts/memory_presets.sh zram ${params.percent}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'ZRAM size set' } }));
                });
                break;
                
            case 'set_swappiness':
                execCommand(`sh ${HYPERION_DIR}/scripts/memory_presets.sh swappiness ${params.value}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Swappiness set' } }));
                });
                break;
                
            case 'optimize_memory':
                execCommand(`sh ${HYPERION_DIR}/scripts/memory_presets.sh optimize`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Memory optimized' } }));
                });
                break;
                
            // IO commands
            case 'set_io_scheduler':
                execCommand(`sh ${HYPERION_DIR}/scripts/io_scheduler.sh scheduler ${params.scheduler}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'IO scheduler set' } }));
                });
                break;
                
            case 'set_readahead':
                execCommand(`sh ${HYPERION_DIR}/scripts/io_scheduler.sh readahead ${params.kb}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Read ahead set' } }));
                });
                break;
                
            // Display commands
            case 'set_refresh_rate':
                execCommand(`sh ${HYPERION_DIR}/scripts/display_control.sh refresh_rate ${params.rate}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Refresh rate set' } }));
                });
                break;
                
            case 'set_saturation':
                execCommand(`sh ${HYPERION_DIR}/scripts/display_control.sh saturation ${params.value}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Saturation set' } }));
                });
                break;
                
            case 'set_contrast':
                execCommand(`sh ${HYPERION_DIR}/scripts/display_control.sh contrast ${params.value}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Contrast set' } }));
                });
                break;
                
            case 'set_hue':
                execCommand(`sh ${HYPERION_DIR}/scripts/display_control.sh hue ${params.value}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Hue set' } }));
                });
                break;
                
            case 'set_brightness':
                execCommand(`sh ${HYPERION_DIR}/scripts/display_control.sh brightness ${params.value}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Brightness set' } }));
                });
                break;
                
            case 'apply_display_preset':
                execCommand(`sh ${HYPERION_DIR}/scripts/display_control.sh preset ${params.preset}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Display preset applied' } }));
                });
                break;
                
            // Battery commands
            case 'set_bypass_charging':
                execCommand(`sh ${HYPERION_DIR}/scripts/bypass_charging.sh ${params.enabled ? 'enable' : 'disable'}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Bypass charging toggled' } }));
                });
                break;
                
            case 'set_charge_limit':
                execCommand(`echo ${params.limit} > ${HYPERION_DIR}/data/charge_limit.txt`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Charge limit set' } }));
                });
                break;
                
            // HWUI commands
            case 'set_hwui_renderer':
                execCommand(`sh ${HYPERION_DIR}/scripts/hwui_tweaks.sh renderer ${params.renderer}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'HWUI renderer set' } }));
                });
                break;
                
            case 'set_hwui_vulkan':
                execCommand(`sh ${HYPERION_DIR}/scripts/hwui_tweaks.sh vulkan ${params.enabled}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Vulkan toggled' } }));
                });
                break;
                
            // Preload commands
            case 'set_preload':
                execCommand(`sh ${HYPERION_DIR}/scripts/app_preload.sh ${params.enabled ? 'enable' : 'disable'}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Preload toggled' } }));
                });
                break;
                
            case 'set_preload_count':
                execCommand(`sh ${HYPERION_DIR}/scripts/app_preload.sh start ai ${params.count}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Preload count set' } }));
                });
                break;
                
            // Thermal commands
            case 'set_thermal_limit':
                execCommand(`sh ${HYPERION_DIR}/scripts/thermal.sh limit ${params.temp}`, () => {
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: 'Thermal limit set' } }));
                });
                break;
                
            // Generic exec command
            case 'exec':
                execCommand(params.command, (code, output, error) => {
                    const result = error ? `Error: ${error}` : output;
                    ws.send(JSON.stringify({ type: 'command_output', data: { output: result } }));
                });
                break;
                
            default:
                log(`Unknown command: ${command}`);
        }
    } catch (e) {
        log(`Error handling message: ${e.message}`);
    }
}

// CORS headers for KSU WebUI integration
function setCORSHeaders(res) {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

// KSU API endpoint handler
function handleKSUApi(req, res) {
    setCORSHeaders(res);
    
    const url = req.url.split('?')[0];
    const method = req.method;
    
    // Parse query params
    const urlObj = new URL(req.url, `http://${HOST}:${PORT}`);
    const params = Object.fromEntries(urlObj.searchParams);
    
    // KSU API endpoints
    if (url === '/api/ksu/stats' && method === 'GET') {
        // Return stats in KSU-compatible format
        getStats().then(stats => {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ success: true, data: stats }));
        });
        return;
    }
    
    if (url === '/api/ksu/profile' && method === 'GET') {
        getCurrentProfile().then(profile => {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ success: true, data: { profile } }));
        });
        return;
    }
    
    if (url === '/api/ksu/profile' && method === 'POST') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            try {
                const data = JSON.parse(body);
                const profile = data.profile || 'balanced';
                const scriptPath = `${HYPERION_DIR}/core/profile_manager.sh`;
                execCommand(`sh ${scriptPath} apply ${profile}`, () => {
                    fs.writeFileSync(`${HYPERION_DIR}/data/current_profile.txt`, profile);
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ success: true, data: { profile } }));
                    log(`Profile changed to: ${profile} (KSU)`);
                });
            } catch (e) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, error: e.message }));
            }
        });
        return;
    }
    
    if (url === '/api/ksu/ai' && method === 'GET') {
        const aiEnabled = fs.existsSync(`${HYPERION_DIR}/data/ai_enabled.txt`) 
            ? fs.readFileSync(`${HYPERION_DIR}/data/ai_enabled.txt`, 'utf8').trim() 
            : 'true';
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, data: { enabled: aiEnabled === 'true' } }));
        return;
    }
    
    if (url === '/api/ksu/ai' && method === 'POST') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            try {
                const data = JSON.parse(body);
                const aiEnabled = data.enabled ? 'true' : 'false';
                fs.writeFileSync(`${HYPERION_DIR}/data/ai_enabled.txt`, aiEnabled);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: true, data: { enabled: data.enabled } }));
                log(`AI toggled: ${aiEnabled} (KSU)`);
            } catch (e) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, error: e.message }));
            }
        });
        return;
    }
    
    if (url === '/api/ksu/exec' && method === 'POST') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            try {
                const data = JSON.parse(body);
                const command = data.command;
                execCommand(command, (code, output, error) => {
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ 
                        success: code === 0, 
                        output: output, 
                        error: error || null 
                    }));
                });
            } catch (e) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, error: e.message }));
            }
        });
        return;
    }
    
    if (url === '/api/ksu/status' && method === 'GET') {
        // Return module status for KSU WebUI
        const status = {
            running: true,
            version: 'v1.0.0',
            ksu_integrated: true,
            webui_port: PORT
        };
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, data: status }));
        return;
    }
    
    // 404 for unknown KSU API endpoints
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: false, error: 'Unknown endpoint' }));
}

// HTTP server for WebUI with KSU support
const server = http.createServer((req, res) => {
    // Handle KSU API endpoints
    if (req.url.startsWith('/api/ksu/')) {
        handleKSUApi(req, res);
        return;
    }
    
    // Handle WebSocket upgrade for KSU
    if (req.url === '/ws') {
        // Let WebSocket server handle this
        return;
    }
    
    let filePath = req.url === '/' ? '/index.html' : req.url;
    filePath = path.join(HYPERION_DIR, 'webui', filePath);
    
    const ext = path.extname(filePath);
    const contentTypes = {
        '.html': 'text/html',
        '.css': 'text/css',
        '.js': 'application/javascript',
        '.json': 'application/json',
        '.png': 'image/png',
        '.jpg': 'image/jpeg',
        '.svg': 'image/svg+xml'
    };
    
    // Set CORS for webui files
    setCORSHeaders(res);
    
    fs.readFile(filePath, (err, content) => {
        if (err) {
            res.writeHead(404);
            res.end('Not Found');
            return;
        }
        
        res.writeHead(200, { 'Content-Type': contentTypes[ext] || 'text/plain' });
        res.end(content);
    });
});

// WebSocket server
const wss = new WebSocket.Server({ server });

wss.on('connection', (ws) => {
    log('Client connected');
    
    ws.on('message', (message) => {
        handleMessage(ws, message);
    });
    
    ws.on('close', () => {
        log('Client disconnected');
    });
});

// Broadcast stats periodically
setInterval(async () => {
    const stats = await getStats();
    const message = JSON.stringify({ type: 'stats', data: stats });
    
    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(message);
        }
    });
}, 2000);

// Start server
server.listen(PORT, '0.0.0.0', () => {
    log(`Hyperion server started on port ${PORT}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    log('Shutting down...');
    server.close(() => {
        process.exit(0);
    });
});
