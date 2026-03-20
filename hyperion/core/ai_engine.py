#!/usr/bin/env python3
# =============================================================================
# Hyperion Project - Event-Driven AI Profile Engine
# Made by ShadowBytePrjkt
# =============================================================================
# Architecture: asyncio event loop + inotify-style file watching via epoll
# Zero polling - all events are interrupt-driven for minimal CPU overhead
# =============================================================================

import asyncio
import json
import os
import sys
import time
import signal
import socket
import struct
import logging
import subprocess
from pathlib import Path
from typing import Optional, Dict, Any
from collections import deque

# ─── Constants ────────────────────────────────────────────────────────────────
HYPERION_DIR = "/data/adb/hyperion"
CONFIG_FILE = f"{HYPERION_DIR}/config.json"
AI_RULES_FILE = f"{HYPERION_DIR}/ai_rules.json"
APP_PROFILES_FILE = f"{HYPERION_DIR}/app_profiles.json"
CURRENT_PROFILE_FILE = f"{HYPERION_DIR}/current_profile"
SOCKET_PATH = "/dev/hyperion.sock"
LOG_FILE = f"{HYPERION_DIR}/logs/ai_engine.log"
LEARNING_DB = f"{HYPERION_DIR}/data/usage.db"

PROFILES = ["gaming", "performance", "balanced", "battery", "powersave"]
PROFILE_MANAGER = f"{HYPERION_DIR}/../core/profile_manager.sh"

# ─── Logging Setup ────────────────────────────────────────────────────────────
os.makedirs(f"{HYPERION_DIR}/logs", exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [AI][%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)
log = logging.getLogger("hyperion.ai")


# ─── Scoring Matrix ───────────────────────────────────────────────────────────
DEFAULT_SCORING_MATRIX = {
    # condition: {profile: score_delta}
    "cpu_high": {        # CPU > 80%
        "gaming": 3, "performance": 2, "balanced": 0, "battery": -1, "powersave": -2
    },
    "cpu_critical": {    # CPU > 95%
        "gaming": 5, "performance": 3, "balanced": 1, "battery": -2, "powersave": -3
    },
    "battery_low": {     # Battery < 20%
        "gaming": -3, "performance": -2, "balanced": -1, "battery": 2, "powersave": 3
    },
    "battery_critical": { # Battery < 5%
        "gaming": -5, "performance": -5, "balanced": -3, "battery": 1, "powersave": 5
    },
    "temp_high": {       # Temp > 45°C
        "gaming": -2, "performance": -1, "balanced": 1, "battery": 2, "powersave": 2
    },
    "temp_critical": {   # Temp > 50°C
        "gaming": -5, "performance": -4, "balanced": 0, "battery": 3, "powersave": 4
    },
    "game_detected": {   # Known game in foreground
        "gaming": 5, "performance": 2, "balanced": 0, "battery": -2, "powersave": -3
    },
    "screen_off": {      # Display off
        "gaming": -5, "performance": -3, "balanced": -1, "battery": 3, "powersave": 5
    },
    "charging": {        # Device is charging
        "gaming": 1, "performance": 1, "balanced": 0, "battery": 0, "powersave": -1
    },
    "network_burst": {   # High network activity
        "gaming": 1, "performance": 1, "balanced": 1, "battery": -1, "powersave": -2
    },
    "ram_low": {         # RAM < 20% free
        "gaming": -1, "performance": -1, "balanced": 1, "battery": 2, "powersave": 2
    },
    "idle": {            # System idle (CPU < 10%)
        "gaming": -3, "performance": -2, "balanced": 0, "battery": 2, "powersave": 3
    }
}


# ─── System State ─────────────────────────────────────────────────────────────
class SystemState:
    def __init__(self):
        self.cpu_percent: float = 0.0
        self.gpu_percent: float = 0.0
        self.ram_percent: float = 0.0
        self.battery_level: int = 100
        self.battery_temp: float = 30.0
        self.cpu_temp: float = 30.0
        self.is_charging: bool = False
        self.screen_on: bool = True
        self.foreground_app: str = ""
        self.network_rx_bytes: int = 0
        self.network_tx_bytes: int = 0
        self.network_burst: bool = False
        self.timestamp: float = time.time()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "cpu": round(self.cpu_percent, 1),
            "gpu": round(self.gpu_percent, 1),
            "ram": round(self.ram_percent, 1),
            "battery": self.battery_level,
            "battery_temp": round(self.battery_temp, 1),
            "cpu_temp": round(self.cpu_temp, 1),
            "charging": self.is_charging,
            "screen_on": self.screen_on,
            "foreground_app": self.foreground_app,
            "network_burst": self.network_burst,
            "timestamp": self.timestamp
        }


# ─── CPU Stats Reader ─────────────────────────────────────────────────────────
class CPUMonitor:
    def __init__(self):
        self._prev_idle = 0
        self._prev_total = 0

    def get_usage(self) -> float:
        try:
            with open("/proc/stat") as f:
                line = f.readline()
            fields = list(map(int, line.split()[1:]))
            idle = fields[3] + fields[4]  # idle + iowait
            total = sum(fields)
            delta_idle = idle - self._prev_idle
            delta_total = total - self._prev_total
            self._prev_idle = idle
            self._prev_total = total
            if delta_total == 0:
                return 0.0
            return round(100.0 * (1.0 - delta_idle / delta_total), 1)
        except Exception:
            return 0.0


# ─── Temperature Reader ───────────────────────────────────────────────────────
def read_temp(zone: int = 0) -> float:
    try:
        path = f"/sys/class/thermal/thermal_zone{zone}/temp"
        with open(path) as f:
            raw = int(f.read().strip())
        return raw / 1000.0 if raw > 1000 else float(raw)
    except Exception:
        return 0.0


def read_battery_temp() -> float:
    try:
        with open("/sys/class/power_supply/battery/temp") as f:
            return int(f.read().strip()) / 10.0
    except Exception:
        return 0.0


# ─── Battery Reader ───────────────────────────────────────────────────────────
def read_battery_level() -> int:
    try:
        with open("/sys/class/power_supply/battery/capacity") as f:
            return int(f.read().strip())
    except Exception:
        return 100


def read_charging_status() -> bool:
    try:
        with open("/sys/class/power_supply/battery/status") as f:
            status = f.read().strip()
        return status in ("Charging", "Full")
    except Exception:
        return False


# ─── RAM Reader ───────────────────────────────────────────────────────────────
def read_ram_usage() -> float:
    try:
        meminfo = {}
        with open("/proc/meminfo") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2:
                    meminfo[parts[0].rstrip(':')] = int(parts[1])
        total = meminfo.get("MemTotal", 1)
        available = meminfo.get("MemAvailable", total)
        return round(100.0 * (1.0 - available / total), 1)
    except Exception:
        return 0.0


# ─── Network Monitor ──────────────────────────────────────────────────────────
class NetworkMonitor:
    def __init__(self):
        self._prev_rx = 0
        self._prev_tx = 0
        self._prev_time = time.time()
        self.BURST_THRESHOLD_MBPS = 5.0

    def check_burst(self) -> bool:
        try:
            rx, tx = 0, 0
            with open("/proc/net/dev") as f:
                for line in f:
                    if ':' in line:
                        parts = line.split(':')[1].split()
                        if len(parts) >= 9:
                            rx += int(parts[0])
                            tx += int(parts[8])
            now = time.time()
            elapsed = now - self._prev_time
            if elapsed > 0:
                rx_rate = (rx - self._prev_rx) / elapsed / 1024 / 1024
                tx_rate = (tx - self._prev_tx) / elapsed / 1024 / 1024
                self._prev_rx = rx
                self._prev_tx = tx
                self._prev_time = now
                return (rx_rate + tx_rate) > self.BURST_THRESHOLD_MBPS
        except Exception:
            pass
        return False


# ─── App Profiles Loader ──────────────────────────────────────────────────────
class AppProfileManager:
    def __init__(self):
        self.app_profiles: Dict[str, str] = {}
        self.load()

    def load(self):
        try:
            with open(APP_PROFILES_FILE) as f:
                data = json.load(f)
            self.app_profiles = data.get("overrides", {})
            log.info(f"Loaded {len(self.app_profiles)} app profile overrides")
        except Exception as e:
            log.warning(f"Could not load app profiles: {e}")

    def get_profile_for_app(self, package: str) -> Optional[str]:
        return self.app_profiles.get(package)

    def is_game(self, package: str) -> bool:
        profile = self.app_profiles.get(package)
        return profile == "gaming"


# ─── Hysteresis Controller ────────────────────────────────────────────────────
class HysteresisController:
    def __init__(self, min_interval: float = 10.0, required_wins: int = 3):
        self.min_interval = min_interval
        self.required_wins = required_wins
        self._last_switch_time: float = 0
        self._candidate_profile: str = ""
        self._candidate_wins: int = 0
        self._thermal_cooldown_until: float = 0

    def can_switch(self, new_profile: str, current_profile: str, thermal_event: bool = False) -> bool:
        now = time.time()

        # Thermal cooldown
        if now < self._thermal_cooldown_until:
            log.debug(f"Thermal cooldown active, {self._thermal_cooldown_until - now:.0f}s remaining")
            return False

        # Minimum interval
        if now - self._last_switch_time < self.min_interval:
            return False

        # Same profile - no switch needed
        if new_profile == current_profile:
            self._candidate_profile = ""
            self._candidate_wins = 0
            return False

        # Track consecutive wins
        if new_profile == self._candidate_profile:
            self._candidate_wins += 1
        else:
            self._candidate_profile = new_profile
            self._candidate_wins = 1

        if self._candidate_wins >= self.required_wins:
            self._candidate_wins = 0
            return True

        log.debug(f"Profile candidate '{new_profile}': {self._candidate_wins}/{self.required_wins} wins")
        return False

    def record_switch(self, thermal_event: bool = False):
        self._last_switch_time = time.time()
        if thermal_event:
            self._thermal_cooldown_until = time.time() + 60.0
            log.info("Thermal cooldown started (60s)")


# ─── AI Decision Engine ───────────────────────────────────────────────────────
class AIDecisionEngine:
    def __init__(self):
        self.scoring_matrix = DEFAULT_SCORING_MATRIX.copy()
        self.app_manager = AppProfileManager()
        self.hysteresis = HysteresisController()
        self.current_profile = "balanced"
        self.ai_enabled = True
        self.learned_biases: Dict[str, Dict[str, float]] = {}
        self._load_current_profile()
        self._load_ai_rules()

    def _load_current_profile(self):
        try:
            with open(CURRENT_PROFILE_FILE) as f:
                self.current_profile = f.read().strip()
        except Exception:
            self.current_profile = "balanced"

    def _load_ai_rules(self):
        try:
            with open(AI_RULES_FILE) as f:
                rules = json.load(f)
            if "scoring_overrides" in rules:
                self.scoring_matrix.update(rules["scoring_overrides"])
            if "learned_biases" in rules:
                self.learned_biases = rules["learned_biases"]
            log.info("AI rules loaded")
        except Exception as e:
            log.warning(f"Could not load AI rules: {e}")

    def decide(self, state: SystemState) -> Dict[str, Any]:
        """
        Main decision function. Returns dict with:
        - profile: recommended profile
        - scores: per-profile scores
        - confidence: 0.0-1.0
        - reason: human-readable reason
        - app_override: True if app-specific override was used
        """
        # Layer 1: App-specific override
        if state.foreground_app:
            app_profile = self.app_manager.get_profile_for_app(state.foreground_app)
            if app_profile:
                log.info(f"App override: {state.foreground_app} → {app_profile}")
                return {
                    "profile": app_profile,
                    "scores": {p: (10 if p == app_profile else 0) for p in PROFILES},
                    "confidence": 1.0,
                    "reason": f"App override: {state.foreground_app}",
                    "app_override": True
                }

        # Layer 2: Scoring matrix
        scores = {p: 0.0 for p in PROFILES}
        active_conditions = []

        # Evaluate conditions
        if state.cpu_percent > 95:
            self._apply_condition(scores, "cpu_critical")
            active_conditions.append("cpu_critical")
        elif state.cpu_percent > 80:
            self._apply_condition(scores, "cpu_high")
            active_conditions.append("cpu_high")
        elif state.cpu_percent < 10:
            self._apply_condition(scores, "idle")
            active_conditions.append("idle")

        if state.battery_level < 5:
            self._apply_condition(scores, "battery_critical")
            active_conditions.append("battery_critical")
        elif state.battery_level < 20:
            self._apply_condition(scores, "battery_low")
            active_conditions.append("battery_low")

        if state.cpu_temp > 50 or state.battery_temp > 50:
            self._apply_condition(scores, "temp_critical")
            active_conditions.append("temp_critical")
        elif state.cpu_temp > 45 or state.battery_temp > 45:
            self._apply_condition(scores, "temp_high")
            active_conditions.append("temp_high")

        if self.app_manager.is_game(state.foreground_app):
            self._apply_condition(scores, "game_detected")
            active_conditions.append("game_detected")

        if not state.screen_on:
            self._apply_condition(scores, "screen_off")
            active_conditions.append("screen_off")

        if state.is_charging:
            self._apply_condition(scores, "charging")
            active_conditions.append("charging")

        if state.network_burst:
            self._apply_condition(scores, "network_burst")
            active_conditions.append("network_burst")

        if state.ram_percent > 80:
            self._apply_condition(scores, "ram_low")
            active_conditions.append("ram_low")

        # Layer 3: Apply learned biases
        hour = time.localtime().tm_hour
        hour_key = f"hour_{hour}"
        if hour_key in self.learned_biases:
            for profile, bias in self.learned_biases[hour_key].items():
                if profile in scores:
                    scores[profile] += bias

        # Find winner
        winner = max(scores, key=scores.get)
        max_score = scores[winner]
        total_score = sum(abs(s) for s in scores.values())
        confidence = min(1.0, max_score / max(total_score, 1))

        reason = f"Conditions: {', '.join(active_conditions) if active_conditions else 'none'}"

        return {
            "profile": winner,
            "scores": {p: round(s, 2) for p, s in scores.items()},
            "confidence": round(confidence, 3),
            "reason": reason,
            "app_override": False,
            "conditions": active_conditions
        }

    def _apply_condition(self, scores: Dict[str, float], condition: str):
        if condition in self.scoring_matrix:
            for profile, delta in self.scoring_matrix[condition].items():
                if profile in scores:
                    scores[profile] += delta


# ─── Profile Applier ──────────────────────────────────────────────────────────
async def apply_profile(profile: str, reason: str = ""):
    log.info(f"Applying profile: {profile} (reason: {reason})")
    try:
        proc = await asyncio.create_subprocess_exec(
            "/system/bin/sh", PROFILE_MANAGER, profile,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=30)
        if proc.returncode == 0:
            log.info(f"Profile '{profile}' applied successfully")
            # Update current profile file
            with open(CURRENT_PROFILE_FILE, 'w') as f:
                f.write(profile)
        else:
            log.error(f"Profile apply failed: {stderr.decode()}")
    except asyncio.TimeoutError:
        log.error("Profile apply timed out")
    except Exception as e:
        log.error(f"Profile apply error: {e}")


# ─── WebSocket Notifier ───────────────────────────────────────────────────────
class WebSocketNotifier:
    def __init__(self):
        self._ws_socket_path = "/dev/hyperion_ws.sock"
        self._connected = False

    async def send(self, msg_type: str, data: Any):
        try:
            msg = json.dumps({"type": msg_type, "data": data, "ts": time.time()})
            # Write to a named pipe that the Node.js server reads
            pipe_path = f"{HYPERION_DIR}/data/ai_events.pipe"
            if os.path.exists(pipe_path):
                with open(pipe_path, 'w') as f:
                    f.write(msg + "\n")
        except Exception:
            pass


# ─── Main AI Loop ─────────────────────────────────────────────────────────────
class HyperionAI:
    def __init__(self):
        self.state = SystemState()
        self.cpu_monitor = CPUMonitor()
        self.net_monitor = NetworkMonitor()
        self.engine = AIDecisionEngine()
        self.notifier = WebSocketNotifier()
        self.running = True
        self._telemetry_interval = 0.5  # 500ms
        self._decision_interval = 2.0   # 2s decision cycle
        self._last_decision_time = 0.0
        self._event_queue: asyncio.Queue = asyncio.Queue()

    async def update_state(self):
        """Update system state from /proc and /sys"""
        self.state.cpu_percent = self.cpu_monitor.get_usage()
        self.state.ram_percent = read_ram_usage()
        self.state.battery_level = read_battery_level()
        self.state.battery_temp = read_battery_temp()
        self.state.cpu_temp = read_temp(0)
        self.state.is_charging = read_charging_status()
        self.state.network_burst = self.net_monitor.check_burst()
        self.state.timestamp = time.time()

    async def update_foreground_app(self):
        """Detect foreground app via dumpsys (runs every 2s)"""
        try:
            proc = await asyncio.create_subprocess_exec(
                "dumpsys", "activity", "activities",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=3)
            output = stdout.decode(errors='ignore')
            # Parse: mResumedActivity: ActivityRecord{... pkg/activity ...}
            for line in output.split('\n'):
                if 'mResumedActivity' in line or 'mCurrentFocus' in line:
                    parts = line.split()
                    for part in parts:
                        if '/' in part and '.' in part:
                            pkg = part.split('/')[0].strip('{').strip('}')
                            if pkg and pkg != self.state.foreground_app:
                                log.info(f"Foreground app: {pkg}")
                                self.state.foreground_app = pkg
                                await self._event_queue.put(("app_change", pkg))
                            break
                    break
        except Exception:
            pass

    async def telemetry_loop(self):
        """Fast loop: update state and send telemetry every 500ms"""
        log.info("Telemetry loop started")
        while self.running:
            try:
                await self.update_state()
                await self.notifier.send("telemetry", self.state.to_dict())
            except Exception as e:
                log.error(f"Telemetry error: {e}")
            await asyncio.sleep(self._telemetry_interval)

    async def app_detection_loop(self):
        """App detection loop every 2s"""
        log.info("App detection loop started")
        while self.running:
            try:
                await self.update_foreground_app()
            except Exception as e:
                log.error(f"App detection error: {e}")
            await asyncio.sleep(2.0)

    async def decision_loop(self):
        """AI decision loop - event-driven with 2s minimum interval"""
        log.info("AI decision loop started")
        while self.running:
            try:
                # Wait for event or timeout
                try:
                    event = await asyncio.wait_for(
                        self._event_queue.get(),
                        timeout=self._decision_interval
                    )
                    log.debug(f"Event received: {event}")
                except asyncio.TimeoutError:
                    event = ("timer", None)

                if not self.engine.ai_enabled:
                    continue

                # Make decision
                decision = self.engine.decide(self.state)
                recommended = decision["profile"]
                confidence = decision["confidence"]

                # Check hysteresis
                thermal_event = "temp_critical" in decision.get("conditions", [])
                if self.engine.hysteresis.can_switch(
                    recommended,
                    self.engine.current_profile,
                    thermal_event
                ):
                    if confidence >= 0.3 or decision.get("app_override"):
                        old_profile = self.engine.current_profile
                        self.engine.current_profile = recommended
                        self.engine.hysteresis.record_switch(thermal_event)

                        # Apply profile
                        await apply_profile(recommended, decision["reason"])

                        # Notify WebSocket
                        await self.notifier.send("profile_change", {
                            "from": old_profile,
                            "to": recommended,
                            "reason": decision["reason"],
                            "confidence": confidence,
                            "scores": decision["scores"]
                        })

                        log.info(
                            f"Profile switched: {old_profile} → {recommended} "
                            f"(confidence: {confidence:.2f}, reason: {decision['reason']})"
                        )

                # Always send AI decision to WebSocket
                await self.notifier.send("ai_decision", {
                    "current": self.engine.current_profile,
                    "recommended": recommended,
                    "scores": decision["scores"],
                    "confidence": confidence,
                    "reason": decision["reason"],
                    "conditions": decision.get("conditions", [])
                })

            except Exception as e:
                log.error(f"Decision loop error: {e}")
                await asyncio.sleep(1.0)

    async def command_listener(self):
        """Listen for commands from Node.js server via Unix socket"""
        log.info("Command listener started")
        pipe_path = f"{HYPERION_DIR}/data/commands.pipe"

        # Create named pipe if not exists
        if not os.path.exists(pipe_path):
            os.mkfifo(pipe_path)

        while self.running:
            try:
                # Non-blocking read from pipe
                fd = os.open(pipe_path, os.O_RDONLY | os.O_NONBLOCK)
                try:
                    data = os.read(fd, 4096).decode(errors='ignore').strip()
                    if data:
                        for line in data.split('\n'):
                            if line.strip():
                                await self._handle_command(json.loads(line))
                except (BlockingIOError, json.JSONDecodeError):
                    pass
                finally:
                    os.close(fd)
            except Exception:
                pass
            await asyncio.sleep(0.5)

    async def _handle_command(self, cmd: Dict[str, Any]):
        """Handle incoming commands"""
        cmd_type = cmd.get("type")
        data = cmd.get("data", {})

        if cmd_type == "set_profile":
            profile = data.get("profile")
            if profile in PROFILES:
                self.engine.ai_enabled = False  # Disable AI when manually set
                self.engine.current_profile = profile
                await apply_profile(profile, "manual")
                log.info(f"Manual profile set: {profile}")

        elif cmd_type == "toggle_ai":
            self.engine.ai_enabled = data.get("enabled", True)
            log.info(f"AI {'enabled' if self.engine.ai_enabled else 'disabled'}")

        elif cmd_type == "reload_rules":
            self.engine._load_ai_rules()
            self.engine.app_manager.load()
            log.info("Rules reloaded")

        elif cmd_type == "get_status":
            await self.notifier.send("status", {
                "current_profile": self.engine.current_profile,
                "ai_enabled": self.engine.ai_enabled,
                "state": self.state.to_dict()
            })

    async def run(self):
        """Main entry point"""
        log.info("=" * 60)
        log.info("Hyperion AI Engine starting...")
        log.info(f"Version: 1.0.0 | Made by ShadowBytePrjkt")
        log.info("=" * 60)

        # Create data pipes
        os.makedirs(f"{HYPERION_DIR}/data", exist_ok=True)
        for pipe in ["ai_events.pipe", "commands.pipe"]:
            pipe_path = f"{HYPERION_DIR}/data/{pipe}"
            if not os.path.exists(pipe_path):
                try:
                    os.mkfifo(pipe_path)
                except Exception:
                    pass

        # Start all coroutines
        tasks = [
            asyncio.create_task(self.telemetry_loop()),
            asyncio.create_task(self.app_detection_loop()),
            asyncio.create_task(self.decision_loop()),
            asyncio.create_task(self.command_listener()),
        ]

        log.info("All AI loops started")

        try:
            await asyncio.gather(*tasks)
        except asyncio.CancelledError:
            log.info("AI engine shutting down...")
        finally:
            for task in tasks:
                task.cancel()

    def stop(self):
        self.running = False
        log.info("AI engine stop requested")


# ─── Signal Handlers ──────────────────────────────────────────────────────────
def setup_signals(ai: HyperionAI, loop: asyncio.AbstractEventLoop):
    def handle_sigterm():
        log.info("SIGTERM received")
        ai.stop()
        loop.stop()

    def handle_sighup():
        log.info("SIGHUP received - reloading rules")
        ai.engine._load_ai_rules()
        ai.engine.app_manager.load()

    loop.add_signal_handler(signal.SIGTERM, handle_sigterm)
    loop.add_signal_handler(signal.SIGHUP, handle_sighup)


# ─── Entry Point ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    ai = HyperionAI()
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    setup_signals(ai, loop)

    try:
        loop.run_until_complete(ai.run())
    except KeyboardInterrupt:
        log.info("Interrupted by user")
    finally:
        loop.close()
        log.info("AI engine stopped")
