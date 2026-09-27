"""Daily riff stats for time-saved and the 12-week streak."""

from __future__ import annotations

import json
import logging
import os
import threading
from datetime import date, datetime, timedelta


DEFAULT_TYPING_WPM = 40
KEEP_DAYS = 90


class StatsStore:
    def __init__(self, status_dir: str):
        self.path = os.path.join(status_dir, "stats.json")
        self.snapshot_path = os.path.join(status_dir, "stats_snapshot.json")
        self._lock = threading.RLock()
        os.makedirs(status_dir, exist_ok=True)

    def set_typing_wpm(self, typing_wpm: int):
        with self._lock:
            data = self._load()
            data["typing_wpm"] = max(10, min(int(typing_wpm or DEFAULT_TYPING_WPM), 200))
            self._save(data)
            snap = self.snapshot(data)
            self._save_snapshot(snap)
            return snap

    def refresh_snapshot(self) -> dict:
        with self._lock:
            snap = self.snapshot()
            self._save_snapshot(snap)
            return snap

    def record_riff(self, word_count: int, recording_seconds: float, typing_wpm: int = DEFAULT_TYPING_WPM):
        with self._lock:
            data = self._load()
            data["typing_wpm"] = int(data.get("typing_wpm") or typing_wpm or DEFAULT_TYPING_WPM)
            today = date.today().isoformat()
            daily = data.setdefault("daily", {})
            row = daily.get(today) or {"words": 0, "recording_seconds": 0.0, "riffs": 0}
            row["words"] = int(row.get("words", 0)) + int(word_count)
            row["recording_seconds"] = float(row.get("recording_seconds", 0)) + float(recording_seconds)
            row["riffs"] = int(row.get("riffs", 0)) + 1
            daily[today] = row
            data["daily"] = self._trim(daily)
            self._save(data)
            snap = self.snapshot(data)
            self._save_snapshot(snap)
            return snap

    def snapshot(self, data=None) -> dict:
        with self._lock:
            data = data or self._load()
        typing_wpm = int(data.get("typing_wpm") or DEFAULT_TYPING_WPM)
        daily = data.get("daily") or {}
        current = self._window(daily, 30, 0, typing_wpm)
        prior = self._window(daily, 30, 30, typing_wpm)
        series = current["series"]
        streak = self._streak(daily)
        return {
            "typing_wpm": typing_wpm,
            "minutes": current["minutes_saved"],
            "minutes_prior": prior["minutes_saved"],
            "words_30": current["words"],
            "spoken_minutes_30": current["spoken_minutes"],
            "series": series,
            "streak_days": streak["days"],
            "streak_cells": streak["cells"],
            "formula": f"words ÷ {typing_wpm} WPM − minutes spoken",
        }

    def _window(self, daily: dict, days: int, offset: int, typing_wpm: int) -> dict:
        today = date.today()
        series = []
        words = 0
        spoken = 0.0
        for i in range(days - 1, -1, -1):
            day = today - timedelta(days=offset + i)
            row = daily.get(day.isoformat()) or {}
            day_words = int(row.get("words", 0))
            day_spoken = float(row.get("recording_seconds", 0)) / 60.0
            saved = max(0.0, (day_words / max(typing_wpm, 1)) - day_spoken)
            words += day_words
            spoken += day_spoken
            series.append({
                "date": day.isoformat(),
                "minutes": round(saved, 2),
                "riffs": int(row.get("riffs", 0)),
            })
        return {
            "words": words,
            "spoken_minutes": round(spoken, 2),
            "minutes_saved": round(max(0.0, (words / max(typing_wpm, 1)) - spoken), 2),
            "series": series,
        }

    def _streak(self, daily: dict) -> dict:
        today = date.today()
        cells = []
        for i in range(83, -1, -1):
            day = today - timedelta(days=i)
            row = daily.get(day.isoformat()) or {}
            minutes = max(0.0, float(row.get("words", 0)) / DEFAULT_TYPING_WPM - float(row.get("recording_seconds", 0)) / 60.0)
            riffs = int(row.get("riffs", 0))
            level = 0
            if riffs > 0:
                if minutes >= 20:
                    level = 4
                elif minutes >= 8:
                    level = 3
                elif minutes >= 3:
                    level = 2
                else:
                    level = 1
            cells.append({
                "date": day.isoformat(),
                "level": level,
                "minutes": round(minutes, 2),
                "riffs": riffs,
            })

        days = 0
        cursor = today
        if int((daily.get(cursor.isoformat()) or {}).get("riffs", 0)) == 0:
            cursor = today - timedelta(days=1)
        while int((daily.get(cursor.isoformat()) or {}).get("riffs", 0)) > 0:
            days += 1
            cursor -= timedelta(days=1)
        return {"days": days, "cells": cells}

    def _trim(self, daily: dict) -> dict:
        cutoff = (date.today() - timedelta(days=KEEP_DAYS)).isoformat()
        return {k: v for k, v in daily.items() if k >= cutoff}

    def _load(self) -> dict:
        if not os.path.exists(self.path):
            return {"typing_wpm": DEFAULT_TYPING_WPM, "daily": {}}
        try:
            with open(self.path, "r") as handle:
                data = json.load(handle)
            if not isinstance(data, dict):
                return {"typing_wpm": DEFAULT_TYPING_WPM, "daily": {}}
            data.setdefault("typing_wpm", DEFAULT_TYPING_WPM)
            data.setdefault("daily", {})
            return data
        except Exception as exc:
            logging.warning("[Stats] Failed to read stats.json: %s", exc)
            return {"typing_wpm": DEFAULT_TYPING_WPM, "daily": {}}

    def _save(self, data: dict):
        tmp = self.path + ".tmp"
        with open(tmp, "w") as handle:
            json.dump(data, handle, indent=2)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, self.path)

    def _save_snapshot(self, snap: dict):
        tmp = self.snapshot_path + ".tmp"
        with open(tmp, "w") as handle:
            json.dump(snap, handle, indent=2)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, self.snapshot_path)
