import json
import logging
import os
import signal
import tempfile
import threading
import time
import subprocess
import queue
import sys
import stat
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import uuid

from pynput import keyboard
from groq import Groq

# Core components
from core.audio_recorder import AudioRecorder, AudioRecorderError
from core.transcriber import Transcriber, TranscriptionError
from core.refiner import Refiner, RefinementError
from core.text_injector import TextInjector
from core.context_detector import ContextDetector
from core.noise import assess_transcript
from core.provider_errors import classify_error, hud_message
from utils.config_manager import ConfigManager
from utils.stats_store import StatsStore, DEFAULT_TYPING_WPM
from utils.retry_queue import RetryQueue
from utils.provider_status import ProviderStatus
from ui.tray import SystemTray
from ui.hud import RecordingHUD
from utils.permissions import PermissionManager

# Phase 2: Authentication
try:
    from utils.auth_manager import AuthManager
    AUTH_AVAILABLE = True
except ImportError:
    AUTH_AVAILABLE = False
    logging.warning("Auth modules not available - running without subscription management")

# Setup Logging
from utils.logger import setup_logging, log_crash, log_activity, open_logs_folder, write_diagnostics, SESSION_ID

# Initialize logging
try:
    log_file = setup_logging()
    sys.excepthook = log_crash
    log_activity("Riff App Started")
except Exception as e:
    print(f"Failed to setup logging: {e}")

logging.info("----------------------------------------------------------------")
logging.info("Riff Logging Started")
logging.info(f"Python Version: {sys.version}")


class HistoryManager:
    def __init__(self):
        self.history_dir = os.path.expanduser("~/Library/Application Support/Riff")
        self.history_file = os.path.join(self.history_dir, "history.json")
        self.deleted_file = os.path.join(self.history_dir, "history_deleted.json")
        self._lock = threading.Lock()
        self._ensure_file()

    def _ensure_file(self):
        if not os.path.exists(self.history_dir):
            os.makedirs(self.history_dir, exist_ok=True)
        if not os.path.exists(self.history_file):
            with open(self.history_file, 'w') as f:
                json.dump([], f)

    def _deleted_timestamps(self):
        if not os.path.exists(self.deleted_file):
            return set()
        try:
            with open(self.deleted_file, "r") as f:
                return set(json.load(f) or [])
        except Exception:
            return set()

    def add_entry(self, original, refined, style, script_mode="unknown", extra=None):
        try:
            entry = {
                "timestamp": datetime.now().isoformat(),
                "original": original,
                "refined": refined,
                "style": style,
                "script_mode": script_mode
            }
            if extra:
                entry.update(extra)

            with self._lock:
                history = []
                if os.path.exists(self.history_file):
                    try:
                        with open(self.history_file, 'r') as f:
                            history = json.load(f)
                    except json.JSONDecodeError:
                        history = []
                deleted = self._deleted_timestamps()
                history = [row for row in history if isinstance(row, dict) and row.get("timestamp") not in deleted]
                if entry.get("timestamp") in deleted:
                    return entry
                history.insert(0, entry)
                history = history[:200]
                tmp_path = self.history_file + ".tmp"
                with open(tmp_path, 'w') as f:
                    json.dump(history, f, indent=2)
                    f.flush()
                    os.fsync(f.fileno())
                os.replace(tmp_path, self.history_file)

            logging.info(f"History entry added: {style}, script_mode: {script_mode}")
            return entry
        except Exception as e:
            logging.error(f"Failed to save history: {e}")
            return None


class ProcessingThread(threading.Thread):
    def __init__(self, audio_queue, config_manager, status_callback, notification_callback,
                 refiner=None, transcriber=None, injector=None, watchdog_callback=None,
                 processing_done_callback=None, auth_manager=None,
                 stats_store=None, retry_queue=None, provider_status=None):
        super().__init__(daemon=True)
        self.audio_queue = audio_queue
        self.config_manager = config_manager
        self.status_callback = status_callback
        self.notification_callback = notification_callback
        self.watchdog_callback = watchdog_callback
        self.processing_done_callback = processing_done_callback
        self.transcriber = transcriber
        self.refiner = refiner
        self.injector = injector
        self.history_manager = HistoryManager()
        self.auth_manager = auth_manager  # Phase 2: Auth integration
        self.stats_store = stats_store
        self.retry_queue = retry_queue
        self.provider_status = provider_status
        
        # Fallback initialization (may fail if API key not yet configured)
        if not self.transcriber:
            try:
                api_key = config_manager.get_api_key()
                if api_key:
                    script_mode = config_manager.get("script_mode.active_mode", "english_mixed")
                    self.transcriber = Transcriber(api_key, script_mode=script_mode)
            except Exception as e:
                logging.warning(f"Transcriber not initialized (API key missing?): {e}")
        if not self.refiner:
            try:
                api_key = config_manager.get_api_key()
                if api_key:
                    self.refiner = Refiner(api_key)
            except Exception as e:
                logging.warning(f"Refiner not initialized (API key missing?): {e}")
        if not self.injector:
            self.injector = TextInjector()

        # Local file writes are serialized; cloud uploads can overlap across riffs.
        self._persist_lock = threading.Lock()
        self._persist_shutdown = False
        self._persist_pool = ThreadPoolExecutor(max_workers=3, thread_name_prefix="riff-persist")

    def run(self):
        logging.info("Processing thread started")
        while True:
            job = self.audio_queue.get()
            if job is None:
                logging.info("Processing thread received stop signal")
                break

            if isinstance(job, dict):
                audio_path = job.get("path")
                queue_id = job.get("queue_id")
            else:
                audio_path = job
                queue_id = None

            keep_audio = False
            try:
                keep_audio = bool(self._process_audio_file(audio_path, queue_id=queue_id))
            except Exception as e:
                logging.error(f"Unhandled error in processing thread: {e}", exc_info=True)
                keep_audio = self._handle_provider_failure(e, audio_path, queue_id)
            finally:
                # ALWAYS signal that processing is done
                self.status_callback("idle")
                if self.processing_done_callback:
                    self.processing_done_callback()
                    
                # Cleanup audio file unless the retry queue still owns it
                try:
                    if audio_path and (not keep_audio) and os.path.exists(audio_path):
                        os.remove(audio_path)
                except OSError:
                    pass
                    
                self.audio_queue.task_done()

    def _ensure_clients(self, api_key: str):
        """Create or refresh Groq clients so paid leases work without a BYOK key."""
        script_mode = self.config_manager.get("script_mode.active_mode", "english_mixed")
        if self.transcriber:
            self.transcriber.update_api_key(api_key)
        else:
            self.transcriber = Transcriber(api_key, script_mode=script_mode)
        if self.refiner:
            self.refiner.update_api_key(api_key)
        else:
            self.refiner = Refiner(api_key, model=self.config_manager.get("api.llm_model"))

    def _process_audio_file(self, audio_path, queue_id=None):
        """Process a single audio file through the pipeline. Returns True if the wav must be kept."""
        riff_id = uuid.uuid4().hex[:8]
        pipeline_started = time.time()
        logging.info("[Riff %s] Pipeline start path=%s queue=%s", riff_id, audio_path, queue_id or "-")

        # Phase 2: BYOK gate — signed in + Groq key. Reloads config so onboarding paste is seen.
        if self.auth_manager:
            can_riff, reason = self.auth_manager.can_riff()
            logging.info("[Riff %s] can_riff=%s reason=%s", riff_id, can_riff, reason)
            if not can_riff:
                logging.warning("[Riff %s] Blocked: %s", riff_id, reason)
                self.notification_callback("Setup Required", reason)
                return False
            user_key = self.auth_manager.get_effective_api_key()
            if not user_key:
                user_key = self.auth_manager.sync_byok_key()
            if user_key:
                self._ensure_clients(user_key)
                logging.info("[Riff %s] Groq client ready (key prefix=%s)", riff_id, user_key[:7])
            else:
                logging.warning("[Riff %s] No Groq key after sync", riff_id)

        # Guard: API key may not be configured yet (first run)
        if not self.transcriber:
            logging.warning("[Riff %s] Transcriber not initialized — API key missing", riff_id)
            self.notification_callback("Setup Required", "Please set your Groq API key in Settings")
            return False

        # Duration + watchdog. Groq timeout is 300s per request; allow retries and chunks.
        try:
            f_size = os.path.getsize(audio_path)
            wav_header = 44
            audio_bytes = max(0, f_size - wav_header)
            duration_sec = audio_bytes / 32000.0
            num_chunks = max(1, int((duration_sec + 599) // 600))
            needed_timeout = 90.0 + 320.0 * num_chunks
            logging.info(
                "[Riff %s] Audio %.2fs (%.2f MB) chunks_est=%s watchdog=%.0fs",
                riff_id, duration_sec, f_size / (1024 * 1024), num_chunks, needed_timeout
            )

            if self.watchdog_callback:
                self.watchdog_callback(needed_timeout)
        except Exception as e:
            logging.warning("[Riff %s] Could not calculate duration: %s", riff_id, e)
            duration_sec = 10.0

        # Check minimum file size (0.5 sec = 16000 bytes + header)
        file_size = os.path.getsize(audio_path)
        if file_size < 8000:
            logging.info("[Riff %s] Audio too short (%s bytes), discarding as noise.", riff_id, file_size)
            return False

        self.status_callback("processing")
        
        # Reload config to get latest style changes from UI
        self.config_manager.load()
        new_script_mode = self.config_manager.get("script_mode.active_mode", "english_mixed")
        if self.transcriber.script_mode != new_script_mode:
            logging.info("[Riff %s] Script Mode changed from %s to %s", riff_id, self.transcriber.script_mode, new_script_mode)
            self.transcriber.script_mode = new_script_mode
        logging.info("[Riff %s] Using script_mode=%s style=%s", riff_id, new_script_mode, self.config_manager.get_style())

        # 1. Transcribe with Retry
        logging.info("[Riff %s] Transcribing...", riff_id)
        raw_text = None
        transcribe_started = time.time()
        try:
            for attempt in range(3):
                try:
                    raw_text = self.transcriber.transcribe_file(audio_path)
                    break
                except Exception as e:
                    logging.warning("[Riff %s] Transcription attempt %s failed: %s", riff_id, attempt + 1, e)
                    classified = classify_error(e)
                    if classified["kind"] != "other" or attempt >= 2:
                        raise
                    self.notification_callback("Processing...", f"Retrying transcription ({attempt + 2}/3)...")
                    time.sleep(1)
        except Exception as e:
            return self._handle_provider_failure(e, audio_path, queue_id)
        transcribe_ms = int((time.time() - transcribe_started) * 1000)

        meta = getattr(self.transcriber, "last_meta", {}) or {}
        noise = assess_transcript(
            raw_text or meta.get("discarded_text") or "",
            duration_sec,
            meta.get("no_speech_prob"),
        )
        if meta.get("likely_noise"):
            noise["likely_noise"] = True
            if not raw_text:
                noise["discard"] = True

        if not raw_text or not raw_text.strip():
            if noise.get("likely_noise"):
                discarded = (meta.get("discarded_text") or "").strip()
                extra = {
                    "likely_noise": True,
                    "transcribe_ms": transcribe_ms,
                    "rewrite_ms": 0,
                    "type_ms": 0,
                    "round_trip_ms": int((time.time() - pipeline_started) * 1000),
                    "word_count": 0,
                }
                if discarded:
                    self.history_manager.add_entry(discarded, discarded, "casual", new_script_mode, extra)
                self.notification_callback("Likely Noise", "I heard noise, not speech")
                logging.info("[Riff %s] Likely noise — no paste", riff_id)
                if queue_id and self.retry_queue:
                    self.retry_queue.complete(queue_id)
                return False
            logging.info("[Riff %s] Transcription empty - no speech detected (%.1fs)", riff_id, time.time() - pipeline_started)
            self.notification_callback("No Speech", "Nothing was detected")
            if queue_id and self.retry_queue:
                self.retry_queue.complete(queue_id)
            return False
            
        logging.info("[Riff %s] Raw transcription: %s chars", riff_id, len(raw_text))
        logging.debug("[Riff %s] Raw text: %s", riff_id, raw_text)

        # 2. Get Style
        style = (self.config_manager.get_style() or "casual").strip().lower()

        # 3. Refine with Fallback. Casual is verbatim — no Groq chat round-trip.
        refined_text = raw_text
        used_fallback = False
        rewrite_started = time.time()
        if style == "casual":
            logging.info("[Riff %s] Casual: skipping refine, pasting transcript as-is", riff_id)
        else:
            logging.info("[Riff %s] Refining with style '%s'...", riff_id, style)
            try:
                refined_text = self._refine_text(raw_text, style)
                logging.info("[Riff %s] Refined text: %s chars", riff_id, len(refined_text))
                logging.debug("[Riff %s] Refined: %s", riff_id, refined_text)
            except Exception as e:
                classified = classify_error(e)
                if classified["kind"] != "other":
                    return self._handle_provider_failure(e, audio_path, queue_id)
                logging.error("[Riff %s] Refinement failed, falling back to raw text: %s", riff_id, e)
                refined_text = raw_text
                used_fallback = True
            if used_fallback:
                self.notification_callback("Refinement Failed", "Using raw transcript")
        rewrite_ms = 0 if style == "casual" else int((time.time() - rewrite_started) * 1000)

        # Paste immediately so the next riff can start. Persist only after a successful paste.
        type_started = time.time()
        pasted = self.injector.inject(refined_text)
        type_ms = int((time.time() - type_started) * 1000)
        if not pasted:
            logging.error("[Riff %s] Paste failed last_error=%s — keeping history", riff_id, getattr(self.injector, "last_error", None))
            if getattr(self.injector, "last_error", None) == "no_focus":
                self.notification_callback("Paste Failed", "Click in a text field — the riff is in History")
            else:
                self.notification_callback("Paste Failed", "Text was not inserted — the riff is in History")

        if self.provider_status:
            snap = self.retry_queue.snapshot() if self.retry_queue else {"waiting": 0}
            self.provider_status.write("healthy", waiting=snap.get("waiting", 0))

        if queue_id and self.retry_queue:
            self.retry_queue.complete(queue_id)

        logging.info(
            "[Riff %s] Pipeline complete in %.1fs paste=%s fallback=%s transcribe=%sms rewrite=%sms type=%sms",
            riff_id, time.time() - pipeline_started, "ok" if pasted else "fail", used_fallback, transcribe_ms, rewrite_ms, type_ms
        )

        persist_job = {
            "raw_text": raw_text,
            "refined_text": refined_text,
            "style": style,
            "script_mode": self.transcriber.script_mode if self.transcriber else "unknown",
            "duration_sec": duration_sec,
            "word_count": len(refined_text.split()),
            "transcribe_ms": transcribe_ms,
            "rewrite_ms": rewrite_ms,
            "type_ms": type_ms,
            "round_trip_ms": transcribe_ms + rewrite_ms + type_ms,
            "likely_noise": bool(noise.get("likely_noise")),
        }
        self._queue_persist(persist_job)

        if used_fallback:
            self.notification_callback("Riff Complete", "Converted (Raw Fallback)")
            log_activity(f"Success: Transcribed & Pasted (Raw Fallback). Text length: {len(refined_text)}")
        else:
            self.notification_callback("Riff Complete", f"Converted ({style})")
            log_activity(f"Success: Transcribed & Pasted (Style: {style}). Text length: {len(refined_text)}")

    def _queue_persist(self, job: dict):
        """Run persist in the background unless we are already quitting."""
        with self._persist_lock:
            shutting_down = self._persist_shutdown
        if shutting_down:
            logging.info("[Persist] App quitting — saving synchronously")
            self._persist_after_paste(job)
            return
        try:
            self._persist_pool.submit(self._persist_after_paste, job)
            logging.info("[Persist] Queued history/metrics/usage sync in background")
        except RuntimeError:
            logging.info("[Persist] Pool closed — saving synchronously")
            self._persist_after_paste(job)

    def _persist_after_paste(self, job: dict):
        """Save local + cloud data after a successful paste. Safe to overlap with the next riff."""
        raw_text = job["raw_text"]
        refined_text = job["refined_text"]
        style = job["style"]
        script_mode = job["script_mode"]
        duration_sec = job["duration_sec"]
        word_count = job["word_count"]

        logging.info(f"[Persist] Starting background save ({word_count} words, {duration_sec:.1f}s)")
        try:
            extra = {
                "transcribe_ms": job.get("transcribe_ms", 0),
                "rewrite_ms": job.get("rewrite_ms", 0),
                "type_ms": job.get("type_ms", 0),
                "round_trip_ms": job.get("round_trip_ms", 0),
                "likely_noise": bool(job.get("likely_noise")),
                "word_count": word_count,
            }
            with self._persist_lock:
                entry = self.history_manager.add_entry(raw_text, refined_text, style, script_mode, extra)
                self.config_manager.update_metrics(word_count, duration_sec, style)
                if self.stats_store and not extra["likely_noise"]:
                    typing_wpm = self.config_manager.get("metrics.typing_wpm", DEFAULT_TYPING_WPM) or DEFAULT_TYPING_WPM
                    self.stats_store.record_riff(word_count, duration_sec, typing_wpm)
                hotkey = self.config_manager.get("hotkey.combination", "ctrl_l")
                onboarding_completed = bool(self.config_manager.get("onboarding_completed"))
                logging.info(f"[Metrics] Updated: +{word_count} words, +{duration_sec:.1f}s, style={style}")

            # Cloud writes stay outside the lock so the next riff can save locally
            # while this riff's HTTP is still in flight. log-usage is an INSERT, so
            # overlapping requests from back-to-back riffs do not clobber each other.
            if self.auth_manager:
                if entry:
                    try:
                        self.auth_manager.upload_history_entry(
                            entry["timestamp"], raw_text, refined_text, style, script_mode
                        )
                    except Exception as e:
                        logging.warning(f"[Auth] History upload error: {e}")
                try:
                    self.auth_manager.log_usage(word_count, duration_sec, style, script_mode)
                    self.auth_manager.sync_user_settings(
                        hotkey,
                        style,
                        script_mode,
                        onboarding_completed,
                    )
                    logging.info("[Auth] Usage logged to backend")
                except Exception as e:
                    logging.warning(f"[Auth] Usage logging error (non-fatal): {e}")
            logging.info("[Persist] Background save complete")
        except Exception as e:
            logging.error(f"[Persist] Background save failed: {e}", exc_info=True)

    def shutdown_persist(self, wait: bool = True):
        logging.info("[Persist] Shutting down background save pool")
        with self._persist_lock:
            self._persist_shutdown = True
        self._persist_pool.shutdown(wait=wait)

    def _handle_provider_failure(self, exc, audio_path, queue_id=None) -> bool:
        classified = classify_error(exc)
        kind = classified["kind"]
        logging.warning("[Provider] %s: %s", kind, exc)
        waiting = 0
        if self.retry_queue and classified["save_audio"] and audio_path and os.path.exists(audio_path):
            if queue_id:
                self.retry_queue.mark_attempt(queue_id, classified.get("retry_after"))
                waiting = self.retry_queue.snapshot().get("waiting", 0)
                keep = True
            else:
                snap = self.retry_queue.enqueue(audio_path, kind, classified.get("retry_after"))
                waiting = snap.get("waiting", 0)
                keep = False
        else:
            keep = bool(queue_id)
        if self.provider_status:
            self.provider_status.write(kind if kind != "other" else "unknown", waiting=waiting, retry_after=classified.get("retry_after"))
        if kind == "other":
            self.notification_callback("Error", "Processing failed")
        else:
            self.notification_callback("Provider", hud_message(kind, waiting, classified.get("retry_after")))
        return keep

    def _refine_text(self, text, style):
        """Refine text using Refiner style prompts. Config overrides are optional."""
        if (style or "").strip().lower() == "casual":
            logging.info("Casual style: returning transcript without LLM refine")
            return text
        override = self.config_manager.get(f"style.options.{style}")
        if not isinstance(override, str) or not override.strip():
            override = None
        logging.info("Refining with style: %s override=%s", style, bool(override))
        if self.refiner:
            return self.refiner.refine(text, style, prompt=override)
        logging.error("Refiner component not initialized")
        return text


class RiffApp:
    def __init__(self):
        logging.info("Initializing RiffApp")
        self.config = ConfigManager()
        status_dir = os.path.dirname(self.config.config_path)
        status_path = os.path.join(status_dir, "permissions_status.json")
        self.permission_manager = PermissionManager(status_path=status_path)
        self.permission_prompt_path = os.path.join(status_dir, "permission_prompt")
        self.settings_session_path = os.path.join(status_dir, "settings_session.json")
        self.tray_relaunch_path = os.path.join(status_dir, "tray_relaunch.json")
        self.reopen_settings_path = os.path.join(status_dir, "reopen_settings")
        self._user_requested_quit = False
        self._permission_relaunch_scheduled = False
        self.stats_store = StatsStore(status_dir)
        self.stats_store.refresh_snapshot()
        self.retry_queue = RetryQueue(status_dir)
        self.provider_status = ProviderStatus(status_dir)
        waiting = self.retry_queue.snapshot().get("waiting", 0)
        self.provider_status.write("unknown" if waiting else "healthy", waiting=waiting)

        # Phase 2: Initialize Auth Manager
        self.auth_manager = None
        if AUTH_AVAILABLE:
            try:
                self.auth_manager = AuthManager(self.config)
                logging.info(f"[Auth] AuthManager initialized. Authenticated: {self.auth_manager.is_authenticated}")
            except Exception as e:
                logging.warning(f"[Auth] Failed to initialize AuthManager: {e}")

        # Load API Key (account-synced BYOK)
        self._uses_byok = True
        if self.auth_manager:
            if self.auth_manager.is_authenticated:
                self.auth_manager.sync_byok_key()
            self.api_key = self.auth_manager.get_effective_api_key()
            logging.info("[Auth] Groq client %s", "ready (BYOK)" if self.api_key else "waiting for key")
        else:
            self.api_key = self.config.get("api.api_key")

        self.tray = SystemTray(
            on_settings=self.open_settings,
            on_quit=self.quit_from_tray,
            on_instructions=self.open_instructions,
            on_record=self.start_recording_manual,
            on_stop=self.stop_recording_manual,
            on_force_reset=self.force_reset_state,
            on_reveal_logs=open_logs_folder,
            permission_manager=self.permission_manager
        )
        self.hud = RecordingHUD(os.path.dirname(self.config.config_path))
        
        if not self.api_key:
            logging.warning("API Key missing — app will start but recording disabled until key is set")

        # Initialize Components
        script_mode = self.config.get("script_mode.active_mode", "english_mixed")
        self.transcriber = Transcriber(self.api_key, script_mode=script_mode) if self.api_key else None
        self.refiner = Refiner(self.api_key, model=self.config.get("api.llm_model")) if self.api_key else None
        
        self.recorder = AudioRecorder(
            sample_rate=self.config.get("audio.sample_rate", 16000),
            silence_threshold_ms=self.config.get("audio.silence_threshold_ms", 600)
        )
        self.injector = TextInjector()
        self.context_detector = ContextDetector()

        # Initialize Audio Queue and Processing Thread
        self.audio_queue = queue.Queue()
        self.processing_thread = ProcessingThread(
            self.audio_queue,
            self.config,
            self.update_tray_status,
            self.show_notification,
            refiner=self.refiner,
            transcriber=self.transcriber,
            injector=self.injector,
            watchdog_callback=self.update_watchdog,
            processing_done_callback=self._on_processing_done,
            auth_manager=self.auth_manager,
            stats_store=self.stats_store,
            retry_queue=self.retry_queue,
            provider_status=self.provider_status
        )
        self.processing_thread.start()
        
        # State management with lock
        self._state_lock = threading.Lock()
        self._is_processing = False
        self.running = True
        self.listener = None
        self.current_hotkey_str = self.config.get("hotkey.combination", "ctrl_l")
        
        # Determine initial hotkey string safely
        if isinstance(self.current_hotkey_str, list) and len(self.current_hotkey_str) > 0:
            self.current_hotkey_str = self.current_hotkey_str[0]
        elif not isinstance(self.current_hotkey_str, str):
            self.current_hotkey_str = "ctrl_l"
             
        self.is_latched = False
        self.processing_start_time = 0
        self.recording_started_at = 0
        self.watchdog_timeout = 45.0
        
        # Config Monitoring
        self.config_mtime = 0
        try:
            self.config_mtime = os.path.getmtime(self.config.config_path)
        except OSError:
            pass

        # Control Center is a separate Settings window. Closing it must not quit the tray.
        self.control_center_process = None

        logging.info("Initialization Complete")
        write_diagnostics({
            "session_id": SESSION_ID,
            "authenticated": bool(self.auth_manager and self.auth_manager.is_authenticated),
            "has_groq_key": bool(self.api_key and str(self.api_key).startswith("gsk_")),
            "onboarding_completed": bool(self.config.get("onboarding_completed", False)),
            "hotkey": self.config.get("hotkey.combination", ""),
            "script_mode": self.config.get("script_mode.active_mode", ""),
            "style": self.config.get("style.active_style", ""),
            "sample_rate": self.config.get("audio.sample_rate", 16000),
        })

    def handle_auth_url(self, url: str):
        if not self.auth_manager:
            return
        result = self.auth_manager.handle_auth_callback_url(url)
        if result.get("success"):
            self._notify_banner("Riff", "Signed in successfully.")
            self.open_settings()
        elif result.get("error"):
            self.show_notification("Riff sign-in", str(result["error"]))

    def _merge_cloud_history(self, remote):
        try:
            hm = HistoryManager()
            local = []
            if os.path.exists(hm.history_file):
                with open(hm.history_file, "r") as f:
                    local = json.load(f)
            deleted = set()
            deleted_path = os.path.join(hm.history_dir, "history_deleted.json")
            if os.path.exists(deleted_path):
                try:
                    with open(deleted_path, "r") as f:
                        deleted = set(json.load(f) or [])
                except Exception:
                    deleted = set()
            by_ts = {e.get("timestamp"): e for e in local if isinstance(e, dict)}
            for item in remote:
                ts = item.get("timestamp")
                if ts and ts not in by_ts and ts not in deleted:
                    by_ts[ts] = {
                        "timestamp": ts,
                        "original": item.get("original", ""),
                        "refined": item.get("refined", ""),
                        "style": item.get("style", ""),
                        "script_mode": item.get("script_mode", ""),
                    }
            merged = sorted(by_ts.values(), key=lambda e: e.get("timestamp", ""), reverse=True)[:200]
            tmp_path = hm.history_file + ".tmp"
            with open(tmp_path, "w") as f:
                json.dump(merged, f, indent=2)
            os.replace(tmp_path, hm.history_file)
            logging.info("[Auth] Merged cloud history (%s remote)", len(remote))
        except Exception as e:
            logging.warning("[Auth] History merge failed: %s", e)

    def install_auth_url_handler(self):
        try:
            from AppKit import NSAppleEventManager, NSApplication
            from Foundation import NSObject

            NSApplication.sharedApplication()
            owner = self

            class URLHandler(NSObject):
                def handleGetURLEvent_withReplyEvent_(self, event, replyEvent):
                    try:
                        key_direct_object = 0x2D2D2D2D
                        desc = event.descriptorForKeyword_(key_direct_object)
                        url = desc.stringValue() if desc else None
                        if url:
                            owner.handle_auth_url(url)
                    except Exception as exc:
                        logging.error("[Auth] URL event failed: %s", exc)

            handler = URLHandler.alloc().init()
            gurl = 0x4755524C
            NSAppleEventManager.sharedAppleEventManager().setEventHandler_andSelector_forEventClass_andEventID_(
                handler, b"handleGetURLEvent:withReplyEvent:", gurl, gurl
            )
            self._url_handler = handler
            logging.info("[Auth] Registered riff:// URL handler")
        except Exception as e:
            logging.warning("[Auth] Could not install URL handler: %s", e)

    @property
    def is_processing(self):
        with self._state_lock:
            return self._is_processing
    
    @is_processing.setter
    def is_processing(self, value):
        with self._state_lock:
            self._is_processing = value

    def _on_processing_done(self):
        """Called when processing thread finishes a job."""
        self.is_processing = False
        self.watchdog_timeout = 45.0

    def _release_to_idle(self, reason=""):
        """Clear processing lock without yanking a take that already started."""
        if reason:
            logging.info("[State] Release to idle (%s)", reason)
        self.is_processing = False
        self.watchdog_timeout = 45.0
        if self.recorder.recording:
            return
        if self.tray:
            self.tray.set_state("idle")
        self.hud.on_idle()

    def update_tray_status(self, status):
        if status == "idle":
            self._release_to_idle("pipeline")
            return
        if self.recorder.recording:
            # A follow-up take is already live — don't flash Working/idle over it.
            return
        if self.tray and status in ("recording", "processing"):
            self.tray.set_state(status)
        if status == "processing":
            self.hud.show_working()

    def _info_banners_enabled(self) -> bool:
        return bool(self.config.get("ui.show_notifications"))

    def _notify_banner(self, title, message, kind="info"):
        """macOS banners are opt-in. Dictation feedback stays on the HUD."""
        if kind == "info" and not self._info_banners_enabled():
            return
        if kind == "info" and self._is_control_center_running():
            return
        if self.tray:
            self.tray.show_notification(title, message)

    def show_notification(self, title, message):
        if title in ("Riff Complete",):
            self.hud.show_done()
            return
        if title in ("Processing...",):
            return
        if title in ("No Speech", "Paste Failed", "Cancelled", "Error", "Refinement Failed", "Setup Required", "Provider", "Likely Noise"):
            persist = title in ("Provider", "Setup Required")
            self.hud.show_error(self._human_hud_message(title, message), persist=persist)
            return
        self._notify_banner(title, message)

    def _human_hud_message(self, title, message):
        blob = f"{title} {message or ''}".lower()
        if title == "Likely Noise" or "heard noise" in blob:
            return "Likely noise"
        if title == "Provider":
            return message or "Audio saved"
        if title == "No Speech" or "nothing was detected" in blob:
            return "No speech"
        if title == "Paste Failed" or "click in a text field" in blob or "no_focus" in blob:
            return "Click in a text field"
        if "too short" in blob:
            return "Hold a bit longer"
        if title == "Setup Required":
            return "Finish setup in Settings"
        if title == "Refinement Failed":
            return "Using what I heard"
        return message or title

    def _show_recording_hud(self):
        style = "casual"
        try:
            style = self.config.get_style() or "casual"
        except Exception:
            pass
        self.hud.show_recording(style, self.recording_started_at or time.time(), self.recorder)

    def start(self):
        print("Riff Starting...")
        logging.info("App start() called")
        self.install_auth_url_handler()
        self._install_permission_relaunch_handlers()
        self.hud.attach()

        # Hotkeys must not wait on Supabase. Cloud work runs in the background.
        perm_status = self.permission_manager.check_accessibility()
        input_ok = self.permission_manager.check_input_monitoring()
        logging.info("Accessibility=%s InputMonitoring=%s", perm_status, input_ok)
        self.permission_manager.write_status()
        self._clear_stale_relaunch_marker()
        self._restore_settings_if_needed()

        if perm_status and input_ok:
            self.start_listener()
        else:
            logging.info("Deferring hotkey listener until Accessibility and Input Monitoring are granted")

        threading.Thread(target=self._warmup_audio, daemon=True).start()
        threading.Thread(target=self.monitor_config, daemon=True).start()
        threading.Thread(target=self.health_monitor, daemon=True).start()
        threading.Thread(target=self._drain_retry_queue, daemon=True, name="riff-retry").start()
        if self.auth_manager and self.auth_manager.is_authenticated:
            threading.Thread(target=self._startup_cloud_sync, daemon=True, name="riff-cloud-sync").start()

        if not self.api_key and getattr(self, "_uses_byok", True):
            def _notify_setup():
                time.sleep(1.5)
                self._notify_banner("Riff — Setup Required",
                                    "Please enter your Groq API key in the Settings window.")
            threading.Thread(target=_notify_setup, daemon=True).start()

        try:
            self.tray.run()
        except KeyboardInterrupt:
            self.quit()

    def _startup_cloud_sync(self):
        """History, device register, and settings — never block hotkeys."""
        try:
            if self.auth_manager.is_authenticated:
                subscription = self.auth_manager.validate_subscription()
                logging.info(
                    "[Auth] Subscription: tier=%s, status=%s",
                    subscription.get("tier", "free"), subscription.get("status", "unknown")
                )
            self.auth_manager.register_this_device()
            remote = self.auth_manager.download_history()
            if remote:
                self._merge_cloud_history(remote)
            pulled = self.auth_manager.pull_user_settings()
            local_style = self.config.get("style.active_style")
            local_script = self.config.get("script_mode.active_mode")
            if pulled and not self.config.get("onboarding_completed"):
                local_hotkey = self.config.get("hotkey.combination")
                if pulled.get("hotkey") and not local_hotkey:
                    self.config.set("hotkey.combination", pulled["hotkey"])
                if pulled.get("style") and not local_style:
                    self.config.set("style.active_style", pulled["style"])
                if pulled.get("script_mode") and not local_script:
                    self.config.set("script_mode.active_mode", pulled["script_mode"])
                logging.info(
                    "[Auth] Restored cloud settings on first-run: style=%s script=%s",
                    pulled.get("style"), pulled.get("script_mode")
                )
            elif pulled:
                logging.info(
                    "[Auth] Keeping local style=%s script=%s (not overwriting from cloud)",
                    local_style, local_script
                )
        except Exception as e:
            logging.warning("[Auth] Startup cloud sync failed: %s", e)

    def _handle_permission_prompt(self):
        path = getattr(self, "permission_prompt_path", "")
        if not path or not os.path.exists(path):
            return
        try:
            with open(path, "r") as f:
                kind = f.read().strip()
            os.remove(path)
        except OSError:
            return
        logging.info("[Permissions] Onboarding asked Riff to prompt: %s", kind)
        if kind == "accessibility":
            self.permission_manager.request_accessibility()
        elif kind == "input_monitoring":
            self.permission_manager.request_input_monitoring()
        elif kind == "microphone":
            self.permission_manager.request_microphone()
        self.permission_manager.write_status()
        if kind in ("accessibility", "input_monitoring"):
            self._schedule_tray_relaunch(kind)

    def _warmup_audio(self):
        """Import PortAudio at launch so the first recording is not delayed ~3s."""
        try:
            logging.info("[AudioRecorder] Warming up PortAudio...")
            t0 = time.time()
            self.recorder._sounddevice()
            logging.info("[AudioRecorder] PortAudio ready in %.1fs", time.time() - t0)
        except Exception as e:
            logging.warning("[AudioRecorder] Warmup failed: %s", e)

    def start_listener(self):
        # Stop existing if any
        if self.listener:
            try:
                self.listener.stop()
            except:
                pass
                
        # Reload config to get latest key
        self.config.load()
        key_name = self.config.get("hotkey.combination", "ctrl_l")
        if isinstance(key_name, list): 
            key_name = key_name[0]
        self.current_hotkey_str = key_name
        
        logging.info(f"Binding Hotkey: {key_name}")
        print(f"Press {key_name} to record.")
        
        try:
            self.listener = keyboard.Listener(
                on_press=self.on_press,
                on_release=self.on_release
            )
            self.listener.start()
            logging.info("Keyboard listener started/restarted successfully")
        except Exception as e:
            print(f"Error starting hotkey listener: {e}")
            logging.error(f"Error starting hotkey listener: {e}", exc_info=True)
            self.tray.show_notification("Error", f"Hotkey failed: {e}")

    def monitor_config(self):
        """Polls config file for changes to reload hotkeys and API key dynamically."""
        while self.running:
            try:
                self._handle_permission_prompt()
                self.permission_manager.write_status()

                if self.listener is None and self.permission_manager.check_accessibility() and self.permission_manager.check_input_monitoring():
                    logging.info("[ConfigMonitor] Accessibility and Input Monitoring granted — starting hotkey listener")
                    self.start_listener()

                if os.path.exists(self.config.config_path):
                    mtime = os.path.getmtime(self.config.config_path)
                    if mtime > self.config_mtime:
                        logging.info("Config file changed. Reloading...")
                        self.config_mtime = mtime

                        # Reload config
                        new_config = self.config.load()
                        logging.info(
                            "[ConfigMonitor] Reloaded style=%s script_mode=%s onboarding=%s",
                            (new_config.get("style") or {}).get("active_style"),
                            (new_config.get("script_mode") or {}).get("active_mode"),
                            new_config.get("onboarding_completed"),
                        )
                        new_script = (new_config.get("script_mode") or {}).get("active_mode")
                        if new_script and self.transcriber and self.transcriber.script_mode != new_script:
                            logging.info(
                                "[ConfigMonitor] Applying script_mode %s -> %s",
                                self.transcriber.script_mode, new_script
                            )
                            self.transcriber.script_mode = new_script

                        new_key = new_config.get("hotkey", {}).get("combination", "ctrl_l")
                        if isinstance(new_key, list):
                            new_key = new_key[0]

                        if new_key != self.current_hotkey_str:
                            logging.info(f"Hotkey changed from {self.current_hotkey_str} to {new_key}. Restarting listener.")
                            self.start_listener()
                            self._notify_banner("Riff", f"Hotkey updated to: {new_key}")

                        # Check if API key was just configured (first-run onboarding)
                        new_api_key = (new_config.get("api", {}) or {}).get("api_key", "") or ""
                        typing_wpm = ((new_config.get("metrics") or {}).get("typing_wpm"))
                        if typing_wpm and self.stats_store:
                            try:
                                self.stats_store.set_typing_wpm(int(typing_wpm))
                            except Exception:
                                pass

                        if new_api_key.startswith("gsk_") and len(new_api_key) >= 40 and new_api_key != self.api_key:
                            logging.info("[ConfigMonitor] Groq key changed — reinitializing clients (prefix=%s)", new_api_key[:7])
                            self.api_key = new_api_key
                            try:
                                script_mode = self.config.get("script_mode.active_mode", "english_mixed")
                                self.transcriber = Transcriber(new_api_key, script_mode=script_mode)
                                self.refiner = Refiner(new_api_key, model=self.config.get("api.llm_model"))
                                self.processing_thread.transcriber = self.transcriber
                                self.processing_thread.refiner = self.refiner
                                logging.info("[ConfigMonitor] Components initialized successfully")
                            except Exception as e:
                                logging.error("[ConfigMonitor] Failed to initialize components: %s", e)

            except Exception as e:
                logging.error(f"Error in config monitor: {e}")
            time.sleep(0.5)

    def _drain_retry_queue(self):
        while self.running:
            time.sleep(5)
            try:
                if self.is_processing or self.recorder.recording:
                    continue
                due = self.retry_queue.due_items()
                if not due:
                    continue
                item = due[0]
                if not os.path.exists(item.get("path", "")):
                    self.retry_queue.complete(item["id"])
                    continue
                self.retry_queue.claim(item["id"], hold_sec=180)
                logging.info("[Queue] Replaying saved audio %s (%s)", item["id"], item.get("kind"))
                self.audio_queue.put({"path": item["path"], "queue_id": item["id"]})
            except Exception as e:
                logging.warning("[Queue] Drain error: %s", e)

    def health_monitor(self):
        """Periodically checks recorder health and auto-recovers from stuck states."""
        logging.info("[HealthMonitor] Starting health monitoring system")

        while self.running:
            time.sleep(30.0)  # Check every 30 seconds
            try:
                # Run health check
                is_healthy, issues = self.recorder.health_check()

                if not is_healthy:
                    logging.error(f"[HealthMonitor] Unhealthy state detected: {issues}")
                    self.dump_state()  # Detailed state dump for debugging

                    # Attempt auto-recovery
                    logging.warning("[HealthMonitor] Attempting auto-recovery...")
                    recovered = self.recorder.auto_recover()

                    if recovered:
                        # Also reset app-level processing flag if stuck
                        if self.is_processing:
                            elapsed = time.time() - self.processing_start_time
                            if elapsed > self.watchdog_timeout:
                                logging.warning(f"[HealthMonitor] Processing stuck for {elapsed:.1f}s - resetting")
                                self.is_processing = False
                                self.tray.set_state("idle")

                        log_activity("Auto-recovered from stuck state")
                        self.tray.show_notification("Riff Recovered", "Auto-recovered from stuck state")

                # Additional check: processing timeout detection
                if self.is_processing:
                    elapsed = time.time() - self.processing_start_time
                    if elapsed > (self.watchdog_timeout + 30):  # Extra 30s grace period
                        logging.error(f"[HealthMonitor] Processing timeout detected ({elapsed:.1f}s > {self.watchdog_timeout + 30}s)")
                        logging.warning("[HealthMonitor] Force resetting processing state")
                        self.is_processing = False
                        self.tray.set_state("idle")
                        self.recorder._force_cleanup()
                        log_activity("Force reset due to processing timeout")
                        self.tray.show_notification("Riff Reset", "Recovered from timeout")

            except Exception as e:
                logging.error(f"[HealthMonitor] Error in health check: {e}", exc_info=True)

    def get_trigger_key(self):
        key_str = self.current_hotkey_str
        
        # Handle "f8" -> Key.f8, "cmd_r" -> Key.cmd_r
        if hasattr(keyboard.Key, key_str.lower()):
            return getattr(keyboard.Key, key_str.lower())
        return keyboard.KeyCode.from_char(key_str)

    def on_press(self, key):
        logging.debug(f"Key pressed: {key}")
        try:
            trigger = self.get_trigger_key()
        except Exception as e:
            logging.error(f"Error getting trigger key: {e}")
            return

        # 1. Check for Stop Trigger (if latched)
        if key == trigger and self.is_latched:
            if self.recorder.recording:
                logging.info("Latch Stop Triggered via Hotkey")
                self._stop_latch_and_process()
                return
            logging.warning("[Hotkey] Latch set but recorder is idle — clearing latch")
            self.is_latched = False

        # 2. Check for Latch Activation (Shift while recording)
        if (key == keyboard.Key.shift or key == keyboard.Key.shift_l or key == keyboard.Key.shift_r):
            if self.recorder.recording and not self.is_latched:
                logging.info("Latch Mode Enabled")
                self.is_latched = True
                self._notify_banner("Riff", "Latch Mode Enabled 🔒")

        # 3. Standard Trigger - Start Recording
        if key == trigger:
            logging.info("Hotkey Trigger Detected")

            # STATE VALIDATION: Run health check before starting
            is_healthy, issues = self.recorder.health_check()
            if not is_healthy:
                logging.warning(f"[Hotkey] Unhealthy state detected before start: {issues}")
                self.recorder.auto_recover()

            if self.is_processing and not self.recorder.recording:
                elapsed = time.time() - self.processing_start_time if self.processing_start_time else 0
                logging.info(
                    "[Hotkey] Previous riff still finishing (%.1fs) — starting next take",
                    elapsed,
                )

            # Start if the mic is free. A finishing paste must not block the next hold.
            if not self.recorder.recording:
                try:
                    self.tray.set_state("recording")
                    self.recording_started_at = time.time()
                    self.recorder.start_recording()  # No VAD callback - manual stop only
                    self._show_recording_hud()
                    logging.info("Recording started")
                    log_activity("Recording Started")
                except AudioRecorderError as e:
                    logging.error(f"Failed to start recording: {e}")
                    self.tray.show_notification("Error", f"Mic error: {e}")
                    self.tray.set_state("idle")
                    self.hud.hide()
                except Exception as e:
                    logging.error(f"Unexpected error starting recording: {e}", exc_info=True)
                    self.tray.show_notification("Error", "Could not access microphone.")
                    self.tray.set_state("idle")
                    self.hud.hide()

    def on_release(self, key):
        try:
            trigger = self.get_trigger_key()
        except:
            return
            
        if key == trigger:
            # If latched, ignore release (don't stop)
            if self.is_latched:
                return
                
            if self.recorder.recording:
                hold_s = time.time() - self.recording_started_at if self.recording_started_at else 0
                logging.info("Hotkey Release Detected - Stopping after %.1fs", hold_s)
                self._stop_and_process()

    def _stop_latch_and_process(self):
        """Stop latched recording and process."""
        self.is_latched = False
        self._stop_and_process()
    
    def _stop_and_process(self):
        """Stop recording and queue for processing."""
        # STATE VALIDATION: Verify recorder is actually recording
        if not self.recorder.recording:
            logging.warning("[Stop] Recorder not in recording state - ignoring stop request")
            logging.warning(f"[Stop] State check: recording={self.recorder.recording}, is_processing={self.is_processing}")
            return

        # A previous riff may still be pasting. Still stop this take and queue it.
        if self.is_processing:
            logging.info("[Stop] Previous riff still in flight — queueing this take")
        else:
            self.is_processing = True
            self.processing_start_time = time.time()
        self.tray.set_state("processing")
        self.hud.show_working()
        
        # Process in a thread to not block hotkey listener
        threading.Thread(target=self._do_stop_and_queue, daemon=True).start()
    
    def _do_stop_and_queue(self):
        """Actually stop recording and queue the file."""
        filename = os.path.join(tempfile.gettempdir(), f"riff_recording_{time.time()}.wav")

        logging.info(f"[StopAndQueue] Attempting to stop recording and save to: {filename}")
        hold_s = time.time() - self.recording_started_at if self.recording_started_at else 0
        logging.info(
            "[StopAndQueue] Pre-stop state: recording=%s stream=%s hold=%.1fs",
            self.recorder.recording, self.recorder.stream, hold_s
        )

        try:
            self.recorder.stop_recording(filename, timeout=1.0)
            self.permission_manager.note_recording_level(getattr(self.recorder, "peak_rms", 0.0))
            
            if os.path.exists(filename) and os.path.getsize(filename) > 0:
                self.audio_queue.put(filename)
                log_activity("Recording Finished. Transcribing...")
                logging.info(
                    "Audio queued for processing: %s (%.2f MB, hold=%.1fs)",
                    filename, os.path.getsize(filename) / (1024 * 1024), hold_s
                )
            else:
                logging.warning("No audio file created")
                if not self.audio_queue.qsize():
                    self._release_to_idle("empty_file")
                    self.hud.show_nudge("Hold a bit longer")
                
        except AudioRecorderError as e:
            if "too short" in str(e).lower() or "no audio" in str(e).lower():
                logging.info("[Stop] Ignored short tap: %s", e)
                if not self.audio_queue.qsize():
                    self._release_to_idle("short_tap")
                    self.hud.show_nudge("Hold a bit longer")
                return
            logging.warning(f"Recording error: {e}")
            log_activity(f"Recording cancelled: {e}")
            self.show_notification("Cancelled", str(e))
            if not self.audio_queue.qsize():
                self._release_to_idle("cancelled")
            
            # Cleanup partial file
            if os.path.exists(filename):
                try:
                    os.remove(filename)
                except:
                    pass
                    
        except Exception as e:
            logging.error(f"Error stopping recording: {e}", exc_info=True)
            self.dump_state()  # Dump state for debugging
            log_activity(f"Error: {e}")
            self.show_notification("Error", f"Recording failed: {e}")
            if not self.audio_queue.qsize():
                self._release_to_idle("stop_error")
            self.recorder._force_cleanup()

    def start_recording_manual(self):
        """Manually start recording from tray."""
        # Emergency health check and recovery before manual start
        logging.info("Manual Start Triggered")

        # Run health check to detect stuck states
        is_healthy, issues = self.recorder.health_check()
        if not is_healthy:
            logging.warning(f"[Manual Start] Unhealthy recorder state detected: {issues}")
            logging.warning("[Manual Start] Attempting auto-recovery...")
            self.recorder.auto_recover()
            time.sleep(0.1)  # Brief pause for cleanup

        # Additional safety: Force reset if flags are stuck
        if self.recorder.recording:
            logging.error("[Manual Start] Recording flag still set after health check - forcing cleanup")
            self.recorder._force_cleanup()
            time.sleep(0.1)

        if self.is_processing:
            logging.info("[Manual Start] Previous riff still finishing — starting next take")

        if not self.recorder.recording:
            log_activity("Recording Started (Manual)")
            try:
                self.tray.set_state("recording")
                self.recording_started_at = time.time()
                self.recorder.start_recording()
                self._show_recording_hud()
            except AudioRecorderError as e:
                logging.error(f"Manual start failed: {e}")
                self.tray.show_notification("Error", str(e))
                self.tray.set_state("idle")
                self.hud.hide()
        else:
            logging.error(f"[Manual Start] Cannot start - recording={self.recorder.recording}, is_processing={self.is_processing}")
            self.tray.show_notification("Error", "Cannot start - app may be stuck. Try restarting Riff.")

    def stop_recording_manual(self):
        """Manually stop recording from tray."""
        if self.recorder.recording:
            logging.info("Manual Stop Triggered")
            self._stop_and_process()

    def _control_center_app_path(self) -> str:
        if getattr(sys, 'frozen', False):
            candidates = []
            exe_dir = os.path.dirname(sys.executable)
            candidates.append(os.path.abspath(os.path.join(exe_dir, "..", "Resources", "RiffControlCenter.app")))
            if hasattr(sys, '_MEIPASS'):
                candidates.append(os.path.join(sys._MEIPASS, "RiffControlCenter.app"))
            candidates.append(os.path.abspath(os.path.join(exe_dir, "..", "Frameworks", "RiffControlCenter.app")))
            candidates.append(os.path.join(exe_dir, "RiffControlCenter.app"))
            for c in candidates:
                if os.path.exists(c) and os.path.exists(os.path.join(c, "Contents", "MacOS")):
                    return c
            return candidates[0]
        return os.path.join(os.getcwd(), "config_ui", "build", "RiffControlCenter.app")

    def _is_control_center_running(self) -> bool:
        try:
            result = subprocess.run(
                ["pgrep", "-x", "RiffControlCenter"],
                capture_output=True, text=True
            )
            return result.returncode == 0
        except Exception:
            return False

    def _settings_session_active(self) -> bool:
        path = getattr(self, "settings_session_path", "")
        if not path or not os.path.exists(path):
            return False
        try:
            with open(path, "r") as f:
                data = json.load(f)
            updated = float(data.get("updated_at") or data.get("interrupted_at") or 0)
            age = time.time() - updated
            if data.get("interrupted") and age < 90:
                return True
            if data.get("resume") and age < 90:
                return True
            if data.get("route") == "onboarding" and age < 90:
                return True
            return bool(data.get("open")) and age < 30
        except Exception:
            return False

    def _write_json(self, path, payload):
        if not path:
            return
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            tmp = path + ".tmp"
            with open(tmp, "w") as f:
                json.dump(payload, f)
            os.replace(tmp, path)
        except OSError as e:
            logging.debug("[Settings] Could not write %s: %s", path, e)

    def _mark_settings_restore(self):
        if self._is_control_center_running() or self._settings_session_active():
            try:
                os.makedirs(os.path.dirname(self.reopen_settings_path), exist_ok=True)
                with open(self.reopen_settings_path, "w") as f:
                    f.write("1")
            except OSError:
                pass

    def _clear_settings_restore(self):
        for path in (getattr(self, "reopen_settings_path", ""), getattr(self, "tray_relaunch_path", "")):
            if path and os.path.exists(path):
                try:
                    os.remove(path)
                except OSError:
                    pass

    def _clear_stale_relaunch_marker(self):
        path = getattr(self, "tray_relaunch_path", "")
        if not path or not os.path.exists(path):
            return
        try:
            with open(path, "r") as f:
                data = json.load(f)
            if time.time() - float(data.get("at") or 0) > 20:
                os.remove(path)
        except Exception:
            try:
                os.remove(path)
            except OSError:
                pass

    def _restore_settings_if_needed(self):
        flag = getattr(self, "reopen_settings_path", "")
        flag_fresh = False
        if flag and os.path.exists(flag):
            try:
                flag_fresh = (time.time() - os.path.getmtime(flag)) < 90
            except OSError:
                flag_fresh = True
        should_open = flag_fresh or self._settings_session_active()
        if not should_open:
            return
        if self._is_control_center_running():
            logging.info("[Settings] Control Center still open after tray restart — leaving it")
            if os.path.exists(self.reopen_settings_path):
                try:
                    os.remove(self.reopen_settings_path)
                except OSError:
                    pass
            return
        logging.info("[Settings] Restoring Control Center after permission restart")
        if os.path.exists(self.reopen_settings_path):
            try:
                os.remove(self.reopen_settings_path)
            except OSError:
                pass
        self.open_settings()

    def _riff_app_path(self):
        if getattr(sys, "frozen", False):
            return os.path.abspath(os.path.join(os.path.dirname(sys.executable), "..", ".."))
        return None

    def _install_permission_relaunch_handlers(self):
        def _leave_settings(signum, frame):
            logging.info("[Permissions] Signal %s — exiting without closing Settings", signum)
            self._mark_settings_restore()
            os._exit(0)

        try:
            signal.signal(signal.SIGTERM, _leave_settings)
        except Exception as e:
            logging.debug("[Permissions] Could not install SIGTERM handler: %s", e)

    def _schedule_tray_relaunch(self, reason: str):
        if self._permission_relaunch_scheduled:
            return
        path = getattr(self, "tray_relaunch_path", "")
        if path and os.path.exists(path):
            try:
                with open(path, "r") as f:
                    data = json.load(f)
                if time.time() - float(data.get("at") or 0) < 8:
                    logging.info("[Permissions] Skipping relaunch — one just happened")
                    return
            except Exception:
                pass
        self._permission_relaunch_scheduled = True
        self._write_json(self.tray_relaunch_path, {"at": time.time(), "reason": reason})
        logging.info("[Permissions] Scheduling tray-only relaunch after %s so Settings can stay open", reason)

        def _go():
            time.sleep(2.4)
            self._relaunch_tray_preserving_settings()

        threading.Thread(target=_go, daemon=True, name="riff-perm-relaunch").start()

    def _relaunch_tray_preserving_settings(self):
        """Restart only the menu-bar process. Control Center is left running."""
        self._mark_settings_restore()
        app_path = self._riff_app_path()
        try:
            if app_path and os.path.exists(app_path):
                subprocess.Popen(["/bin/sh", "-c", "sleep 0.8; open \"%s\"" % app_path.replace('"', '\\"')])
            else:
                subprocess.Popen([sys.executable] + sys.argv, cwd=os.getcwd())
        except Exception as e:
            logging.error("[Permissions] Could not relaunch tray: %s", e)
            return
        logging.info("[Permissions] Relaunching tray; leaving Control Center open")
        self.running = False
        try:
            if self.listener:
                self.listener.stop()
        except Exception:
            pass
        try:
            self.tray.stop()
        except Exception:
            pass
        os._exit(0)

    def _quit_control_center(self):
        try:
            subprocess.run(
                ["osascript", "-e", 'tell application "RiffControlCenter" to quit'],
                capture_output=True, timeout=3
            )
        except Exception:
            pass
        try:
            subprocess.run(["pkill", "-x", "RiffControlCenter"], capture_output=True)
        except Exception:
            pass

    def open_settings(self):
        """Open or bring forward Control Center. Closing that window does not quit Riff."""
        try:
            logging.info("[Settings] open_settings() called")
            app_path = self._control_center_app_path()
            logging.info(f"[Settings] Control Center path: {app_path}")
            if not os.path.exists(app_path):
                logging.error(f"[Settings] Settings app not found at {app_path}")
                subprocess.call(["open", self.config.config_path])
                return

            binary_path = os.path.join(app_path, "Contents", "MacOS", "RiffControlCenter")
            if os.path.exists(binary_path):
                try:
                    os.chmod(binary_path, os.stat(binary_path).st_mode | stat.S_IEXEC)
                except OSError as e:
                    logging.warning("[Settings] Could not chmod Control Center (continuing): %s", e)

            subprocess.Popen(["open", app_path])
            logging.info("[Settings] Control Center launched via open")
        except Exception as e:
            logging.error(f"[Settings] Could not open settings: {e}", exc_info=True)

    def open_instructions(self):
        self.open_settings()

    def update_watchdog(self, new_timeout):
        """Callback to extend watchdog timeout for long recordings."""
        logging.info(f"[Watchdog] Extending timeout to {new_timeout:.1f}s")
        self.watchdog_timeout = new_timeout

    def dump_state(self):
        """Dump all current state for debugging."""
        logging.info("="*60)
        logging.info("[STATE DUMP] Current Application State:")
        logging.info(f"  App.is_processing: {self.is_processing}")
        logging.info(f"  App.is_latched: {self.is_latched}")
        logging.info(f"  App.processing_start_time: {self.processing_start_time}")
        logging.info(f"  App.watchdog_timeout: {self.watchdog_timeout}")
        logging.info(f"  Recorder.recording: {self.recorder.recording}")
        logging.info(f"  Recorder.stream: {self.recorder.stream}")
        logging.info(f"  Recorder.stream.active: {self.recorder.stream.active if self.recorder.stream else 'N/A'}")
        logging.info(f"  Tray.current_state: {self.tray.current_state}")
        logging.info(f"  Audio queue size: {self.audio_queue.qsize()}")
        logging.info("="*60)

    def force_reset_state(self):
        """Emergency force reset of all app state. Use when app is stuck."""
        logging.warning("="*60)
        logging.warning("[FORCE RESET] Emergency state reset initiated")
        self.dump_state()
        logging.warning("="*60)

        try:
            # Reset recorder
            self.recorder._force_cleanup()

            # Reset app state
            self.is_processing = False
            self.is_latched = False
            self.processing_start_time = 0

            # Reset tray
            self.tray.set_state("idle")
            self.hud.hide()

            # Clear audio queue
            while not self.audio_queue.empty():
                try:
                    self.audio_queue.get_nowait()
                except:
                    break

            logging.warning("[FORCE RESET] State reset completed successfully")
            log_activity("Emergency state reset performed")
            self.tray.show_notification("Riff Reset", "All state has been reset. Ready to record.")

        except Exception as e:
            logging.error(f"[FORCE RESET] Error during reset: {e}", exc_info=True)
            self.tray.show_notification("Reset Failed", f"Error: {e}")

    def quit_from_tray(self):
        self._user_requested_quit = True
        self.quit()

    def quit(self):
        logging.info("Quitting App user=%s", self._user_requested_quit)
        log_activity("Riff App Quit")
        self.running = False
        try:
            self.hud.hide()
        except Exception:
            pass

        if self._user_requested_quit:
            self._clear_settings_restore()
            self._quit_control_center()
        else:
            self._mark_settings_restore()

        try:
            if self.listener:
                self.listener.stop()
        except:
            pass

        try:
            self.audio_queue.put(None)
            self.processing_thread.join(timeout=2)
        except Exception:
            pass

        try:
            if self.processing_thread:
                self.processing_thread.shutdown_persist(wait=True)
        except Exception as e:
            logging.warning(f"[Persist] Shutdown error: {e}")

        self.tray.stop()
        logging.info("Force exiting now.")
        os._exit(0)


def launch_settings_app(config, app_instance=None):
    """
    Launch Control Center. Used during onboarding and from the tray Settings menu.
    Closing Control Center does not quit the menu-bar app.
    """
    try:
        if app_instance:
            app_instance.open_settings()
            return

        if getattr(sys, 'frozen', False):
            candidates = []
            exe_dir = os.path.dirname(sys.executable)
            candidates.append(os.path.abspath(os.path.join(exe_dir, "..", "Resources", "RiffControlCenter.app")))
            if hasattr(sys, '_MEIPASS'):
                candidates.append(os.path.join(sys._MEIPASS, "RiffControlCenter.app"))
            candidates.append(os.path.abspath(os.path.join(exe_dir, "..", "Frameworks", "RiffControlCenter.app")))
            candidates.append(os.path.join(exe_dir, "RiffControlCenter.app"))
            app_path = candidates[0]
            for c in candidates:
                if os.path.exists(c) and os.path.exists(os.path.join(c, "Contents", "MacOS")):
                    app_path = c
                    break
        else:
            app_path = os.path.join(os.getcwd(), "config_ui", "build", "RiffControlCenter.app")

        logging.info(f"Launching settings app at: {app_path}")
        if os.path.exists(app_path):
            binary_path = os.path.join(app_path, "Contents", "MacOS", "RiffControlCenter")
            if os.path.exists(binary_path):
                os.chmod(binary_path, os.stat(binary_path).st_mode | stat.S_IEXEC)
            subprocess.call(["open", app_path])
        else:
            logging.error(f"Settings app not found at {app_path}")
            subprocess.call(["open", config.config_path])
    except Exception as e:
        logging.error(f"Could not open settings: {e}")


def main():
    config = ConfigManager()
    api_key = config.get("api.api_key")
    onboarded = config.get("onboarding_completed")
    if not onboarded or not api_key:
        print("Setup required. Launching Riff Control Center...")
        launch_settings_app(config)

    app = RiffApp()
    for arg in sys.argv[1:]:
        if isinstance(arg, str) and arg.startswith("riff://"):
            app.handle_auth_url(arg)
    app.start()


if __name__ == "__main__":
    main()