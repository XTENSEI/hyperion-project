#!/usr/bin/env python3
# =============================================================================
# Hyperion Project - Adaptive Learning Engine
# Made by ShadowBytePrjkt
# =============================================================================
# Records usage patterns and adapts AI scoring biases over time
# Uses SQLite for persistent storage - runs as a background task
# =============================================================================

import sqlite3
import json
import os
import time
import logging
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta
from pathlib import Path

HYPERION_DIR = "/data/adb/hyperion"
DB_PATH = f"{HYPERION_DIR}/data/usage.db"
AI_RULES_FILE = f"{HYPERION_DIR}/ai_rules.json"
LOG_FILE = f"{HYPERION_DIR}/logs/learning.log"

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [LEARN][%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
log = logging.getLogger("hyperion.learning")

PROFILES = ["gaming", "performance", "balanced", "battery", "powersave"]


# ─── Database Manager ─────────────────────────────────────────────────────────
class UsageDatabase:
    def __init__(self, db_path: str = DB_PATH):
        self.db_path = db_path
        os.makedirs(os.path.dirname(db_path), exist_ok=True)
        self._init_db()

    def _init_db(self):
        with self._conn() as conn:
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS profile_sessions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    profile TEXT NOT NULL,
                    start_time INTEGER NOT NULL,
                    end_time INTEGER,
                    duration_sec INTEGER,
                    reason TEXT,
                    foreground_app TEXT,
                    battery_start INTEGER,
                    battery_end INTEGER,
                    avg_cpu REAL,
                    avg_temp REAL,
                    was_manual INTEGER DEFAULT 0
                );

                CREATE TABLE IF NOT EXISTS app_usage (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    package TEXT NOT NULL,
                    profile_used TEXT NOT NULL,
                    session_start INTEGER NOT NULL,
                    session_end INTEGER,
                    duration_sec INTEGER,
                    user_overrode INTEGER DEFAULT 0
                );

                CREATE TABLE IF NOT EXISTS hourly_stats (
                    hour INTEGER NOT NULL,
                    profile TEXT NOT NULL,
                    count INTEGER DEFAULT 0,
                    total_duration INTEGER DEFAULT 0,
                    PRIMARY KEY (hour, profile)
                );

                CREATE TABLE IF NOT EXISTS thermal_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp INTEGER NOT NULL,
                    temp_c REAL NOT NULL,
                    profile_at_time TEXT,
                    action_taken TEXT
                );

                CREATE TABLE IF NOT EXISTS battery_drain_rates (
                    profile TEXT PRIMARY KEY,
                    avg_drain_pct_per_hour REAL DEFAULT 0,
                    sample_count INTEGER DEFAULT 0,
                    last_updated INTEGER
                );

                CREATE INDEX IF NOT EXISTS idx_sessions_time ON profile_sessions(start_time);
                CREATE INDEX IF NOT EXISTS idx_app_usage_pkg ON app_usage(package);
                CREATE INDEX IF NOT EXISTS idx_hourly_hour ON hourly_stats(hour);
            """)
        log.info("Database initialized")

    def _conn(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path, timeout=10)

    def record_profile_start(self, profile: str, reason: str = "",
                              app: str = "", battery: int = 100,
                              was_manual: bool = False) -> int:
        with self._conn() as conn:
            cursor = conn.execute(
                """INSERT INTO profile_sessions
                   (profile, start_time, reason, foreground_app, battery_start, was_manual)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (profile, int(time.time()), reason, app, battery, int(was_manual))
            )
            return cursor.lastrowid

    def record_profile_end(self, session_id: int, battery_end: int = 100,
                            avg_cpu: float = 0, avg_temp: float = 0):
        now = int(time.time())
        with self._conn() as conn:
            conn.execute(
                """UPDATE profile_sessions
                   SET end_time=?, duration_sec=end_time-start_time,
                       battery_end=?, avg_cpu=?, avg_temp=?
                   WHERE id=?""",
                (now, battery_end, avg_cpu, avg_temp, session_id)
            )

    def record_app_session(self, package: str, profile: str):
        with self._conn() as conn:
            conn.execute(
                """INSERT INTO app_usage (package, profile_used, session_start)
                   VALUES (?, ?, ?)""",
                (package, profile, int(time.time()))
            )

    def update_hourly_stats(self, hour: int, profile: str, duration_sec: int):
        with self._conn() as conn:
            conn.execute(
                """INSERT INTO hourly_stats (hour, profile, count, total_duration)
                   VALUES (?, ?, 1, ?)
                   ON CONFLICT(hour, profile) DO UPDATE SET
                   count=count+1, total_duration=total_duration+?""",
                (hour, profile, duration_sec, duration_sec)
            )

    def record_thermal_event(self, temp_c: float, profile: str, action: str):
        with self._conn() as conn:
            conn.execute(
                """INSERT INTO thermal_events (timestamp, temp_c, profile_at_time, action_taken)
                   VALUES (?, ?, ?, ?)""",
                (int(time.time()), temp_c, profile, action)
            )

    def update_battery_drain(self, profile: str, drain_pct_per_hour: float):
        with self._conn() as conn:
            conn.execute(
                """INSERT INTO battery_drain_rates
                   (profile, avg_drain_pct_per_hour, sample_count, last_updated)
                   VALUES (?, ?, 1, ?)
                   ON CONFLICT(profile) DO UPDATE SET
                   avg_drain_pct_per_hour=(avg_drain_pct_per_hour*sample_count+?)/(sample_count+1),
                   sample_count=sample_count+1,
                   last_updated=?""",
                (profile, drain_pct_per_hour, int(time.time()),
                 drain_pct_per_hour, int(time.time()))
            )

    def get_hourly_profile_distribution(self) -> Dict[int, Dict[str, float]]:
        """Returns {hour: {profile: probability}} for all 24 hours"""
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT hour, profile, count FROM hourly_stats"
            ).fetchall()

        distribution: Dict[int, Dict[str, int]] = {}
        for hour, profile, count in rows:
            if hour not in distribution:
                distribution[hour] = {}
            distribution[hour][profile] = count

        # Normalize to probabilities
        result = {}
        for hour, counts in distribution.items():
            total = sum(counts.values())
            result[hour] = {p: c / total for p, c in counts.items()}

        return result

    def get_app_profile_preferences(self) -> Dict[str, str]:
        """Returns {package: most_used_profile} for apps with enough data"""
        with self._conn() as conn:
            rows = conn.execute("""
                SELECT package, profile_used, COUNT(*) as cnt
                FROM app_usage
                GROUP BY package, profile_used
                HAVING cnt >= 3
                ORDER BY package, cnt DESC
            """).fetchall()

        preferences = {}
        seen_packages = set()
        for package, profile, count in rows:
            if package not in seen_packages:
                preferences[package] = profile
                seen_packages.add(package)

        return preferences

    def get_battery_drain_rates(self) -> Dict[str, float]:
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT profile, avg_drain_pct_per_hour FROM battery_drain_rates"
            ).fetchall()
        return {profile: rate for profile, rate in rows}

    def get_recent_thermal_frequency(self, hours: int = 24) -> float:
        """Returns thermal events per hour in the last N hours"""
        since = int(time.time()) - hours * 3600
        with self._conn() as conn:
            count = conn.execute(
                "SELECT COUNT(*) FROM thermal_events WHERE timestamp > ?",
                (since,)
            ).fetchone()[0]
        return count / hours

    def cleanup_old_data(self, days: int = 30):
        """Remove data older than N days"""
        cutoff = int(time.time()) - days * 86400
        with self._conn() as conn:
            conn.execute("DELETE FROM profile_sessions WHERE start_time < ?", (cutoff,))
            conn.execute("DELETE FROM app_usage WHERE session_start < ?", (cutoff,))
            conn.execute("DELETE FROM thermal_events WHERE timestamp < ?", (cutoff,))
        log.info(f"Cleaned up data older than {days} days")


# ─── Learning Analyzer ────────────────────────────────────────────────────────
class LearningAnalyzer:
    def __init__(self, db: UsageDatabase):
        self.db = db

    def compute_hourly_biases(self) -> Dict[str, Dict[str, float]]:
        """
        Compute per-hour scoring biases based on historical usage.
        Returns {hour_key: {profile: bias}} where bias is -3 to +3
        """
        distribution = self.db.get_hourly_profile_distribution()
        biases = {}

        for hour, probs in distribution.items():
            hour_key = f"hour_{hour}"
            hour_biases = {}

            for profile in PROFILES:
                prob = probs.get(profile, 0.0)
                # Convert probability to bias: 0.5 prob = 0 bias, 1.0 = +3, 0.0 = -3
                bias = (prob - 0.2) * 15  # Scale: 0.2 is "neutral" (1/5 profiles)
                bias = max(-3.0, min(3.0, bias))  # Clamp to [-3, +3]
                if abs(bias) > 0.5:  # Only include significant biases
                    hour_biases[profile] = round(bias, 2)

            if hour_biases:
                biases[hour_key] = hour_biases

        return biases

    def compute_thermal_adjustment(self) -> Dict[str, float]:
        """
        If device has frequent thermal events, lower gaming/performance thresholds
        """
        thermal_freq = self.db.get_recent_thermal_frequency(24)
        adjustments = {}

        if thermal_freq > 2:  # More than 2 thermal events per hour
            log.info(f"High thermal frequency ({thermal_freq:.1f}/hr) - adjusting scores")
            adjustments["gaming"] = -1.0
            adjustments["performance"] = -0.5

        return adjustments

    def suggest_app_overrides(self) -> Dict[str, str]:
        """
        Suggest new app-profile mappings based on learned preferences
        """
        return self.db.get_app_profile_preferences()

    def generate_report(self) -> Dict:
        """Generate a learning report for the WebUI"""
        distribution = self.db.get_hourly_profile_distribution()
        drain_rates = self.db.get_battery_drain_rates()
        thermal_freq = self.db.get_recent_thermal_frequency(24)
        app_prefs = self.db.get_app_profile_preferences()

        return {
            "hourly_distribution": distribution,
            "battery_drain_rates": drain_rates,
            "thermal_events_per_hour": round(thermal_freq, 2),
            "learned_app_preferences": len(app_prefs),
            "top_app_preferences": dict(list(app_prefs.items())[:10]),
            "generated_at": datetime.now().isoformat()
        }


# ─── AI Rules Updater ─────────────────────────────────────────────────────────
class AIRulesUpdater:
    def __init__(self, db: UsageDatabase, analyzer: LearningAnalyzer):
        self.db = db
        self.analyzer = analyzer

    def update_rules(self):
        """Update ai_rules.json with learned biases"""
        log.info("Updating AI rules from learned data...")

        # Load existing rules
        try:
            with open(AI_RULES_FILE) as f:
                rules = json.load(f)
        except Exception:
            rules = {}

        # Compute new biases
        hourly_biases = self.analyzer.compute_hourly_biases()
        thermal_adj = self.analyzer.compute_thermal_adjustment()
        app_suggestions = self.analyzer.suggest_app_overrides()

        # Update rules
        rules["learned_biases"] = hourly_biases
        rules["thermal_adjustments"] = thermal_adj
        rules["learned_app_suggestions"] = app_suggestions
        rules["last_learning_update"] = datetime.now().isoformat()
        rules["learning_stats"] = {
            "hourly_patterns": len(hourly_biases),
            "app_preferences": len(app_suggestions),
            "thermal_freq_24h": round(self.analyzer.compute_thermal_adjustment().get("gaming", 0), 2)
        }

        # Write updated rules
        with open(AI_RULES_FILE, 'w') as f:
            json.dump(rules, f, indent=2)

        log.info(f"AI rules updated: {len(hourly_biases)} hourly patterns, "
                 f"{len(app_suggestions)} app preferences")

    def update_app_profiles(self):
        """Update app_profiles.json with learned preferences"""
        app_prefs = self.analyzer.suggest_app_overrides()

        try:
            with open(f"{HYPERION_DIR}/app_profiles.json") as f:
                app_profiles = json.load(f)
        except Exception:
            app_profiles = {"overrides": {}, "learned": {}}

        # Add learned preferences to a separate section (don't override user settings)
        app_profiles["learned"] = app_prefs
        app_profiles["last_updated"] = datetime.now().isoformat()

        with open(f"{HYPERION_DIR}/app_profiles.json", 'w') as f:
            json.dump(app_profiles, f, indent=2)

        log.info(f"App profiles updated with {len(app_prefs)} learned preferences")


# ─── Main Learning Cycle ──────────────────────────────────────────────────────
def run_learning_cycle():
    """Run a full learning cycle - called daily"""
    log.info("Starting learning cycle...")

    db = UsageDatabase()
    analyzer = LearningAnalyzer(db)
    updater = AIRulesUpdater(db, analyzer)

    # Generate report
    report = analyzer.generate_report()
    report_path = f"{HYPERION_DIR}/data/learning_report.json"
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    log.info(f"Learning report saved to {report_path}")

    # Update AI rules
    updater.update_rules()
    updater.update_app_profiles()

    # Cleanup old data
    db.cleanup_old_data(30)

    log.info("Learning cycle complete")
    return report


# ─── Entry Point ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1:
        if sys.argv[1] == "cycle":
            run_learning_cycle()
        elif sys.argv[1] == "report":
            db = UsageDatabase()
            analyzer = LearningAnalyzer(db)
            report = analyzer.generate_report()
            print(json.dumps(report, indent=2))
        elif sys.argv[1] == "record":
            # Record a profile session: learning_engine.py record <profile> <reason>
            if len(sys.argv) >= 3:
                db = UsageDatabase()
                profile = sys.argv[2]
                reason = sys.argv[3] if len(sys.argv) > 3 else ""
                session_id = db.record_profile_start(profile, reason)
                print(f"Session {session_id} started for profile {profile}")
    else:
        # Default: run learning cycle
        run_learning_cycle()
