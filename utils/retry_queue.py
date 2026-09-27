"""Keep failed audio on disk and replay it when Groq is reachable again."""

from __future__ import annotations

import json
import logging
import os
import shutil
import threading
import time
import uuid


MAX_ITEMS = 20
MAX_ATTEMPTS = 5


class RetryQueue:
    def __init__(self, status_dir: str):
        self.dir = os.path.join(status_dir, "queue")
        self.path = os.path.join(status_dir, "queue.json")
        self._lock = threading.RLock()
        os.makedirs(self.dir, exist_ok=True)

    def enqueue(self, audio_path: str, kind: str, retry_after=None) -> dict:
        with self._lock:
            items = self._load()
            if any(item.get("source") == audio_path for item in items):
                return self.snapshot(items)
            dest = os.path.join(self.dir, f"{int(time.time())}_{uuid.uuid4().hex[:6]}.wav")
            try:
                shutil.copy2(audio_path, dest)
            except Exception as exc:
                logging.error("[Queue] Could not save audio: %s", exc)
                return self.snapshot(items)
            wait = max(1, int(retry_after or 12))
            items.insert(0, {
                "id": uuid.uuid4().hex[:10],
                "path": dest,
                "source": audio_path,
                "kind": kind,
                "created_at": time.time(),
                "retry_at": time.time() + wait,
                "attempts": 0,
            })
            items = items[:MAX_ITEMS]
            self._save(items)
            logging.info("[Queue] Saved %s audio (%s waiting)", kind, len(items))
            return self.snapshot(items)

    def due_items(self):
        now = time.time()
        with self._lock:
            return [item for item in self._load() if item.get("retry_at", 0) <= now and item.get("attempts", 0) < MAX_ATTEMPTS]

    def claim(self, item_id: str, hold_sec: int = 120):
        with self._lock:
            items = self._load()
            claimed = None
            for item in items:
                if item.get("id") == item_id:
                    item["retry_at"] = time.time() + max(10, int(hold_sec))
                    claimed = item
            self._save(items)
            return claimed

    def mark_attempt(self, item_id: str, retry_after=None):
        with self._lock:
            items = self._load()
            for item in items:
                if item.get("id") == item_id:
                    item["attempts"] = int(item.get("attempts", 0)) + 1
                    wait = max(1, int(retry_after or 20))
                    item["retry_at"] = time.time() + wait
            self._save(items)

    def complete(self, item_id: str):
        with self._lock:
            items = self._load()
            kept = []
            for item in items:
                if item.get("id") == item_id:
                    try:
                        if os.path.exists(item.get("path", "")):
                            os.remove(item["path"])
                    except OSError:
                        pass
                else:
                    kept.append(item)
            self._save(kept)
            return self.snapshot(kept)

    def snapshot(self, items=None) -> dict:
        with self._lock:
            items = items if items is not None else self._load()
        waiting = len(items)
        next_at = min((item.get("retry_at", 0) for item in items), default=0)
        kind = items[0]["kind"] if items else ""
        retry_after = max(0, int(next_at - time.time())) if waiting else 0
        return {
            "waiting": waiting,
            "kind": kind,
            "retry_after": retry_after,
            "items": items,
        }

    def _load(self) -> list:
        if not os.path.exists(self.path):
            return []
        try:
            with open(self.path, "r") as handle:
                data = json.load(handle)
            return data if isinstance(data, list) else []
        except Exception:
            return []

    def _save(self, items: list):
        tmp = self.path + ".tmp"
        with open(tmp, "w") as handle:
            json.dump(items, handle, indent=2)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, self.path)
