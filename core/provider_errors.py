"""Classify Groq / network failures without leaking raw status codes to the HUD."""

from __future__ import annotations

import re


def classify_error(exc: BaseException) -> dict:
    status = _status_code(exc)
    text = str(exc or "").lower()
    retry_after = _retry_after(exc, text)

    if status in (401, 403) or "invalid api key" in text or "invalid_api_key" in text or "unauthorized" in text:
        return {"kind": "key_rejected", "retry_after": None, "save_audio": True, "auto_retry": False}
    if status == 429 or "rate limit" in text or "rate_limit" in text or "too many requests" in text:
        return {"kind": "rate_limited", "retry_after": retry_after or 12, "save_audio": True, "auto_retry": True}
    if _is_offline(exc, text):
        return {"kind": "offline", "retry_after": retry_after or 15, "save_audio": True, "auto_retry": True}
    return {"kind": "other", "retry_after": None, "save_audio": False, "auto_retry": False}


def hud_message(kind: str, waiting: int = 0, retry_after=None) -> str:
    extra = f" · {waiting} waiting" if waiting > 1 else (" · 1 waiting" if waiting == 1 else "")
    if kind == "rate_limited":
        if retry_after:
            return f"Rate limited. Audio saved. Retry in {int(retry_after)}s{extra}"
        return f"Rate limited. Audio saved. Retry shortly{extra}"
    if kind == "offline":
        return f"Offline. Audio saved{extra}"
    if kind == "key_rejected":
        return "Key rejected. Finish setup in Settings"
    return "Something went wrong"


def _status_code(exc: BaseException):
    for attr in ("status_code", "status"):
        value = getattr(exc, attr, None)
        if isinstance(value, int):
            return value
    response = getattr(exc, "response", None)
    if response is not None:
        value = getattr(response, "status_code", None)
        if isinstance(value, int):
            return value
    match = re.search(r"\b(401|403|429)\b", str(exc))
    return int(match.group(1)) if match else None


def _retry_after(exc: BaseException, text: str):
    for source in (exc, getattr(exc, "response", None)):
        headers = getattr(source, "headers", None)
        if not headers:
            continue
        raw = None
        try:
            raw = headers.get("retry-after") or headers.get("Retry-After")
        except Exception:
            raw = None
        if raw:
            try:
                return max(1, int(float(raw)))
            except (TypeError, ValueError):
                pass
    match = re.search(r"try again in (\d+(?:\.\d+)?)\s*s", text)
    if match:
        return max(1, int(float(match.group(1))))
    return None


def _is_offline(exc: BaseException, text: str) -> bool:
    name = type(exc).__name__.lower()
    if "connection" in name or "timeout" in name:
        return True
    needles = (
        "connection error",
        "connecterror",
        "timed out",
        "timeout",
        "temporarily unavailable",
        "failed to resolve",
        "nodename nor servname",
        "network is unreachable",
        "offline",
    )
    return any(n in text for n in needles)
