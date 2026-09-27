"""Write Groq status for the settings window. Never invent remaining-quota counts."""

from __future__ import annotations

import json
import os
import threading
import time


class ProviderStatus:
    def __init__(self, status_dir: str):
        self.path = os.path.join(status_dir, "provider_status.json")
        self._lock = threading.Lock()
        os.makedirs(status_dir, exist_ok=True)

    def write(self, state: str, waiting: int = 0, retry_after=None, label: str = ""):
        payload = {
            "state": state,
            "label": label or self._label(state, waiting, retry_after),
            "waiting": int(waiting or 0),
            "retry_after": int(retry_after) if retry_after else None,
            "updated_at": time.time(),
        }
        with self._lock:
            tmp = self.path + ".tmp"
            with open(tmp, "w") as handle:
                json.dump(payload, handle, indent=2)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(tmp, self.path)
        return payload

    def _label(self, state: str, waiting: int, retry_after) -> str:
        if state == "healthy":
            return "Your key · within limits"
        if state == "rate_limited":
            if retry_after:
                return f"Retry in {int(retry_after)}s · audio saved"
            return "Retry shortly · audio saved"
        if state == "offline":
            extra = f" · {waiting} waiting" if waiting else ""
            return f"Offline{extra}"
        if state == "key_rejected":
            return "Key rejected"
        if waiting:
            return f"{waiting} waiting"
        return "Unknown"
