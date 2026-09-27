"""Flag Whisper silence hallucinations without inventing extra product states."""

from __future__ import annotations

import re

HALLUCINATIONS_EXACT = {
    "you", "you.", ".", "..", "...",
    "mbc news", "amara.org", "thank you", "thanks",
    "thank you for watching", "thank you for watching.",
    "thanks for watching", "thanks for watching.",
    "no audio", "no audio.",
    "subtitles by", "subtitle by", "aaa aaaa",
}

HALLUCINATION_PATTERNS = [
    r"^\[.*\]$",
    r"^\(.*\)$",
    r"^subtitle.*",
    r"^translated by.*",
    r"^thanks?(\s+you)?(\s+for\s+watching)?\.?$",
    r"^please subscribe",
    r"^(no\s+)?audio(\s+(not\s+)?(detected|found|available))?\.?$",
]


def assess_transcript(text: str, duration_sec: float = 0, no_speech_prob=None) -> dict:
    cleaned = (text or "").strip()
    if not cleaned:
        return {"likely_noise": True, "discard": True, "reason": "empty"}

    lowered = cleaned.lower()
    if lowered in HALLUCINATIONS_EXACT:
        return {"likely_noise": True, "discard": True, "reason": "hallucination"}
    for pattern in HALLUCINATION_PATTERNS:
        if re.search(pattern, cleaned, re.IGNORECASE):
            return {"likely_noise": True, "discard": True, "reason": "hallucination"}

    words = cleaned.split()
    if no_speech_prob is not None and no_speech_prob > 0.8:
        return {"likely_noise": True, "discard": len(words) <= 3, "reason": "no_speech"}

    if duration_sec >= 4.0 and len(words) <= 2:
        return {"likely_noise": True, "discard": False, "reason": "short_for_duration"}

    return {"likely_noise": False, "discard": False, "reason": ""}
