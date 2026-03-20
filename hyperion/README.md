# Hyperion Project - Installation & Usage Guide

## Made by: ShadowBytePrjkt

---

## 📥 Installation

### Step 1: Package the Module
```bash
cd hyperion
zip -r hyperion-v1.0.0.zip . -x "*.pyc" "*.log" "*.md" "*.zip"
```

### Step 2: Install via Magisk/KernelSU
1. Open **Magisk Manager** or **KernelSU Manager**
2. Go to **Modules**
3. Click **Install from storage**
4. Select `hyperion-v1.0.0.zip`
5. Wait for installation to complete
6. **REBOOT** your device

---

## 🚀 How to Use

### Method 1: Action Button (Recommended)
After installation, click the **action button** in the module section of Magisk/KernelSU - this opens the WebUI directly inside the manager (like Encore module).

### Method 2: Browser
Simply open any browser and go to:
```
http://localhost:8080
```

### Method 3: Terminal
```bash
# Start Hyperion
sh /data/adb/hyperion/action.sh start

# Open WebUI
sh /data/adb/hyperion/action.sh webui

# Toggle AI
sh /data/adb/hyperion/action.sh toggle

# Gaming mode
sh /data/adb/hyperion/action.sh gaming
```

---

## ✨ Features

### Quick Actions
- 🎮 **Game Booster** - Auto-detect games, boost GPU
- 🧠 **AI Control** - Smart profile switching based on app usage
- 🔥 **Live Stats** - Real-time CPU/GPU/Temp/Memory monitoring

### Profiles
| Profile | Description |
|---------|-------------|
| 🔋 Battery | Power saver mode |
| ⚖️ Balanced | Default everyday use |
| 🚀 Performance | Maximum performance |
| 🎮 Gaming | Best for games |
| 💤 Powersave | Ultra battery saver |
| ⚙️ Custom | Your custom settings |

### Tuning Options
- CPU Governor & Frequency
- GPU Clock & Boost
- Memory (ZRAM, LMK, Swappiness)
- IO Scheduler
- Display (Color calibration, Refresh Rate)
- Thermal Control

---

## 🔧 Troubleshooting

### WebUI Not Opening?
1. Make sure you **REBOOTED** after installation
2. Try: `http://localhost:8080` in browser
3. Check if server is running:
   ```bash
   curl http://localhost:8080
   ```

### Module Not Working?
1. Check Magisk/KernelSU logs
2. Try reinstalling
3. Make sure you have **ROOT** access

### Bootloop Protection
The module has **bootloop prevention** - it will auto-enter safe mode after 3 failed boots.

To recover:
```bash
echo "0" > /data/adb/hyperion/data/safe_mode
echo "0" > /data/adb/hyperion/data/boot_count
```

---

## 🗑️ Uninstall
1. Open Magisk/KernelSU Manager
2. Go to **Modules**
3. Find **Hyperion Project**
4. Click **Remove**
5. **REBOOT**

---

## Credits
- Made by: **ShadowBytePrjkt**
- Inspired by: **Rem01Gaming/encore**, **Project-Raco**
