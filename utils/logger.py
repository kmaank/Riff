import logging
import logging.handlers
import os
import sys
import re
import datetime
import uuid
import json
import subprocess
import platform
from typing import Optional

# Sensitive patterns to redact before anything hits disk
SENSITIVE_PATTERNS = [
    (r"gsk_[a-zA-Z0-9]+", "gsk_REDACTED"),
    (r"Bearer [a-zA-Z0-9\-\._]+", "Bearer REDACTED"),
    (r"eyJ[a-zA-Z0-9_\-]+\.[a-zA-Z0-9_\-]+\.[a-zA-Z0-9_\-]+", "JWT_REDACTED"),
    (r'"access_token":\s*"[^"]+"', '"access_token": "REDACTED"'),
    (r'"refresh_token":\s*"[^"]+"', '"refresh_token": "REDACTED"'),
    (r'"api_key":\s*"[^"]+"', '"api_key": "REDACTED"'),
    (r'"apikey":\s*"[^"]+"', '"apikey": "REDACTED"'),
    (r"X-Request-Signature:\s*\d+:[a-f0-9]+", "X-Request-Signature: REDACTED"),
]

LOG_DIR = os.path.expanduser("~/Library/Application Support/Riff/logs")
SESSION_ID = datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8]
SHARE_README = """Share this folder when reporting a Riff bug.

Attach the whole zip, or at least:
  riff.log          everything from the current session (Python + Control Center)
  debug.log         rolling Python history
  debug_auth.log    Control Center login / onboarding
  diagnostics.txt   machine snapshot (no secrets)

Zip from Terminal:
  zip -r ~/Desktop/riff-logs.zip ~/Library/Application\\ Support/Riff/logs

Do NOT share config.json — it can contain your Groq key.
Keys and tokens in these logs are redacted (gsk_REDACTED / JWT_REDACTED).
"""


class RedactingFormatter(logging.Formatter):
    """Formatter that redacts sensitive information from log messages."""

    def format(self, record):
        original_msg = super().format(record)
        return redact(original_msg)


def redact(text: str) -> str:
    if not text:
        return text
    for pattern, replacement in SENSITIVE_PATTERNS:
        text = re.sub(pattern, replacement, text)
    return text


def get_log_dir() -> str:
    os.makedirs(LOG_DIR, exist_ok=True)
    return LOG_DIR


def _archive_if_huge(path: str, max_bytes: int = 8 * 1024 * 1024) -> None:
    """Move an oversized log aside so the next session starts readable."""
    try:
        if os.path.exists(path) and os.path.getsize(path) > max_bytes:
            bak = path + ".old"
            if os.path.exists(bak):
                os.remove(bak)
            os.replace(path, bak)
    except OSError:
        pass


def write_share_readme() -> None:
    try:
        with open(os.path.join(get_log_dir(), "HOW_TO_SHARE.txt"), "w", encoding="utf-8") as f:
            f.write(SHARE_README)
    except OSError:
        pass


def write_diagnostics(extra: Optional[dict] = None) -> str:
    """Overwrite diagnostics.txt with a secret-free snapshot of this session."""
    path = os.path.join(get_log_dir(), "diagnostics.txt")
    payload = {
        "session_id": SESSION_ID,
        "written_at": datetime.datetime.now().isoformat(),
        "platform": sys.platform,
        "macos": platform.mac_ver()[0] if sys.platform == "darwin" else "",
        "python": sys.version.split()[0],
        "frozen": bool(getattr(sys, "frozen", False)),
        "executable": sys.executable,
        "cwd": os.getcwd(),
        "log_dir": LOG_DIR,
    }
    if extra:
        payload.update(extra)
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, default=str)
            f.write("\n")
    except OSError:
        pass
    return path


def open_logs_folder() -> None:
    """Reveal the logs folder in Finder so they can be zipped and shared."""
    path = get_log_dir()
    write_share_readme()
    try:
        subprocess.Popen(["open", path])
    except OSError as e:
        logging.error("Could not open logs folder: %s", e)


def setup_logging(log_dir=None):
    """
    Sets up rotating debug.log plus a single shareable riff.log for the session.
    Returns the path to debug.log.
    """
    log_dir = log_dir or get_log_dir()
    os.makedirs(log_dir, exist_ok=True)
    debug_file = os.path.join(log_dir, "debug.log")
    session_file = os.path.join(log_dir, "riff.log")
    auth_file = os.path.join(log_dir, "debug_auth.log")

    root_logger = logging.getLogger()
    for h in root_logger.handlers:
        if isinstance(h, logging.handlers.RotatingFileHandler) and h.baseFilename == debug_file:
            return debug_file

    if root_logger.handlers:
        root_logger.handlers.clear()

    _archive_if_huge(session_file, max_bytes=4 * 1024 * 1024)
    _archive_if_huge(auth_file, max_bytes=8 * 1024 * 1024)

    root_logger.setLevel(logging.DEBUG)

    file_formatter = RedactingFormatter(
        "%(asctime)s - %(levelname)s - [%(name)s] %(message)s"
    )

    debug_handler = logging.handlers.RotatingFileHandler(
        debug_file, maxBytes=10 * 1024 * 1024, backupCount=5, encoding="utf-8"
    )
    debug_handler.setLevel(logging.DEBUG)
    debug_handler.setFormatter(file_formatter)
    root_logger.addHandler(debug_handler)

    session_handler = logging.FileHandler(session_file, mode="a", encoding="utf-8")
    session_handler.setLevel(logging.INFO)
    session_handler.setFormatter(file_formatter)
    root_logger.addHandler(session_handler)

    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(RedactingFormatter("%(levelname)s: %(message)s"))
    root_logger.addHandler(console_handler)

    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("PIL").setLevel(logging.WARNING)

    write_share_readme()
    write_diagnostics()

    logging.info("=" * 60)
    logging.info("Riff session %s", SESSION_ID)
    logging.info("Share folder: %s", log_dir)
    logging.info("System: %s  Python: %s  frozen=%s", sys.platform, sys.version.split()[0], getattr(sys, "frozen", False))
    logging.info("=" * 60)

    return debug_file


def log_activity(message: str):
    """High-level, user-friendly line in activity.log."""
    try:
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        os.makedirs(LOG_DIR, exist_ok=True)
        with open(os.path.join(LOG_DIR, "activity.log"), "a", encoding="utf-8") as f:
            f.write(f"[{timestamp}] {message}\n")
    except Exception:
        pass


def log_crash(exc_type, exc_value, exc_traceback):
    """Global crash handler to log unhandled exceptions."""
    if issubclass(exc_type, KeyboardInterrupt):
        sys.__excepthook__(exc_type, exc_value, exc_traceback)
        return

    logging.critical("Uncaught Exception", exc_info=(exc_type, exc_value, exc_traceback))
