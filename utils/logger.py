import logging
import logging.handlers
import os
import sys
import re
import datetime

# Sensitive patterns to redact
SENSITIVE_PATTERNS = [
    (r"gsk_[a-zA-Z0-9]+", "gsk_REDACTED"),  # Groq API keys
    (r"Bearer [a-zA-Z0-9\-\._]+", "Bearer REDACTED"),  # Bearer tokens
    (r"eyJ[a-zA-Z0-9_\-]+\.[a-zA-Z0-9_\-]+\.[a-zA-Z0-9_\-]+", "JWT_REDACTED"),  # JWT tokens
    (r'"access_token":\s*"[^"]+"', '"access_token": "REDACTED"'),  # Access tokens in JSON
    (r'"refresh_token":\s*"[^"]+"', '"refresh_token": "REDACTED"'),  # Refresh tokens in JSON
    (r'"apikey":\s*"[^"]+"', '"apikey": "REDACTED"'),  # Supabase API keys in JSON
    (r"X-Request-Signature:\s*\d+:[a-f0-9]+", "X-Request-Signature: REDACTED"),  # HMAC signatures
]

class RedactingFormatter(logging.Formatter):
    """Formatter that redacts sensitive information from log messages."""
    def format(self, record):
        original_msg = super().format(record)
        for pattern, replacement in SENSITIVE_PATTERNS:
            original_msg = re.sub(pattern, replacement, original_msg)
        return original_msg

def setup_logging(log_dir=None):
    """
    Sets up a robust logging configuration with rotation and redaction.
    Returns the path to the log file.
    """
    if not log_dir:
        # Application Support does not trigger a Documents-folder TCC prompt on launch.
        log_dir = os.path.expanduser("~/Library/Application Support/Riff/logs")
    
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, "debug.log")

    # prevent double configuration of OUR handlers
    root_logger = logging.getLogger()
    
    # Check if we already have our specific file handler attached
    for h in root_logger.handlers:
        if isinstance(h, logging.handlers.RotatingFileHandler) and h.baseFilename == log_file:
             return log_file
             
    # If we are here, we need to setup logging.
    # First, clear any pre-existing handlers (e.g. from libraries like pystray)
    if root_logger.handlers:
        root_logger.handlers.clear()

    root_logger.setLevel(logging.INFO)

    # 1. File Handler (Rotating)
    # 5MB max size, keep 3 backups.
    file_handler = logging.handlers.RotatingFileHandler(
        log_file, maxBytes=5*1024*1024, backupCount=3, encoding='utf-8'
    )
    file_handler.setFormatter(RedactingFormatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    ))
    root_logger.addHandler(file_handler)

    # 2. Console Handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(RedactingFormatter(
        '%(levelname)s: %(message)s'
    ))
    root_logger.addHandler(console_handler)

    # 3. Silence noisy libraries
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)

    logging.info("="*60)
    logging.info(f"Riff Logging System Initialized. Log file: {log_file}")
    logging.info(f"System: {sys.platform}, Python: {sys.version}")
    
    return log_file

def log_activity(message: str):
    """
    Logs a high-level, user-friendly message to 'activity.log'.
    This is for non-technical users to see what Riff is doing.
    """
    try:
        # We manually append to a separate file to keep it strictly clean.
        # No complex handlers to avoid mixing with debug logs.
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        # Determine log dir (same as debug)
        log_dir = os.path.expanduser("~/Library/Application Support/Riff/logs")
        os.makedirs(log_dir, exist_ok=True)
        activity_file = os.path.join(log_dir, "activity.log")
        
        with open(activity_file, "a", encoding="utf-8") as f:
            f.write(f"[{timestamp}] {message}\n")
            
    except Exception:
        # Never crash due to activity logging
        pass

def log_crash(exc_type, exc_value, exc_traceback):
    """Global crash handler to log unhandled exceptions."""
    if issubclass(exc_type, KeyboardInterrupt):
        sys.__excepthook__(exc_type, exc_value, exc_traceback)
        return

    logging.critical("Uncaught Exception", exc_info=(exc_type, exc_value, exc_traceback))

