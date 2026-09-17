import json
import logging
import os
import tempfile
import threading
import time
import subprocess
import queue
import sys
import stat
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

from pynput import keyboard
from groq import Groq

# Core components
from core.audio_recorder import AudioRecorder, AudioRecorderError
from core.transcriber import Transcriber, TranscriptionError
from core.refiner import Refiner, RefinementError
from core.text_injector import TextInjector
from core.context_detector import ContextDetector
from utils.config_manager import ConfigManager
from ui.tray import SystemTray
from utils.permissions import PermissionManager

# Phase 2: Authentication
try:
    from utils.auth_manager import AuthManager
    from utils.subscription_config import get_tier_features
    AUTH_AVAILABLE = True
except ImportError:
    AUTH_AVAILABLE = False
    logging.warning("Auth modules not available - running without subscription management")

# Setup Logging
from utils.logger import setup_logging, log_crash, log_activity

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
        self._ensure_file()

    def _ensure_file(self):
        if not os.path.exists(self.history_dir):
            os.makedirs(self.history_dir, exist_ok=True)
        if not os.path.exists(self.history_file):
            with open(self.history_file, 'w') as f:
                json.dump([], f)

    def add_entry(self, original, refined, style, script_mode="unknown"):
        try:
            entry = {
                "timestamp": datetime.now().isoformat(),
                "original": original,
                "refined": refined,
                "style": style,
                "script_mode": script_mode
            }
            
            history = []
            if os.path.exists(self.history_file):
                try:
                    with open(self.history_file, 'r') as f:
                        history = json.load(f)
                except json.JSONDecodeError:
                    history = []
            
            history.insert(0, entry)
            history = history[:50]

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
                 processing_done_callback=None, auth_manager=None):
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
            audio_path = self.audio_queue.get()
            if audio_path is None:
                logging.info("Processing thread received stop signal")
                break
            
            try:
                self._process_audio_file(audio_path)
            except Exception as e:
                logging.error(f"Unhandled error in processing thread: {e}", exc_info=True)
                self.notification_callback("Error", f"Processing failed: {e}")
            finally:
                # ALWAYS signal that processing is done
                self.status_callback("idle")
                if self.processing_done_callback:
                    self.processing_done_callback()
                    
                # Cleanup audio file
                try:
                    if os.path.exists(audio_path):
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

    def _process_audio_file(self, audio_path):
        """Process a single audio file through the pipeline."""

        # Phase 2: Quota enforcement gate
        if self.auth_manager:
            can_riff, reason = self.auth_manager.can_riff()
            if not can_riff:
                logging.warning(f"Riff blocked by quota: {reason}")
                self.notification_callback("Limit Reached", reason)
                return
            paid_key = self.auth_manager.get_effective_api_key()
            if paid_key:
                self._ensure_clients(paid_key)

        # Guard: API key may not be configured yet (first run)
        if not self.transcriber:
            logging.warning("Transcriber not initialized — API key missing")
            paid = False
            if AUTH_AVAILABLE and self.auth_manager:
                try:
                    paid = not get_tier_features(self.auth_manager.get_tier()).byok
                except Exception:
                    paid = False
            self.notification_callback(
                "Setup Required",
                "Could not load your Riff key. Check your connection and try again."
                if paid
                else "Please set your Groq API key in Settings",
            )
            return

        # Calculate duration for watchdog
        try:
            f_size = os.path.getsize(audio_path)
            wav_header = 44
            audio_bytes = max(0, f_size - wav_header)
            duration_sec = audio_bytes / 32000.0
            logging.info(f"Audio Duration: {duration_sec:.2f}s")
            
            if self.watchdog_callback:
                needed_timeout = 30.0 + duration_sec
                self.watchdog_callback(needed_timeout)
        except Exception as e:
            logging.warning(f"Could not calculate duration: {e}")
            duration_sec = 10.0

        # Check minimum file size (0.5 sec = 16000 bytes + header)
        file_size = os.path.getsize(audio_path)
        if file_size < 16000:
            logging.info(f"Audio too short ({file_size} bytes), discarding as noise.")
            return

        self.status_callback("processing")
        
        # Reload config to get latest style changes from UI
        self.config_manager.load()
        
        # Reload Script Mode
        new_script_mode = self.config_manager.get("script_mode.active_mode", "english_mixed")
        if self.transcriber.script_mode != new_script_mode:
            logging.info(f"Script Mode changed from {self.transcriber.script_mode} to {new_script_mode}")
            self.transcriber.script_mode = new_script_mode

        # 1. Transcribe with Retry
        logging.info(f"Transcribing {audio_path}...")
        raw_text = None
        for attempt in range(3):
            try:
                raw_text = self.transcriber.transcribe_file(audio_path)
                break
            except Exception as e:
                logging.warning(f"Transcription attempt {attempt + 1} failed: {e}")
                if attempt < 2:
                    self.notification_callback("Processing...", f"Retrying transcription ({attempt + 2}/3)...")
                    time.sleep(1)
                else:
                    raise
        
        if not raw_text or not raw_text.strip():
            logging.info("Transcription returned empty - no speech detected")
            self.notification_callback("No Speech", "Nothing was detected")
            return
            
        logging.info(f"Raw transcription: {raw_text}")

        # 2. Get Style
        style = self.config_manager.get_style()
        
        # 3. Refine with Fallback
        logging.info(f"Refining with style '{style}'...")
        refined_text = raw_text
        used_fallback = False
        
        try:
            refined_text = self._refine_text(raw_text, style)
            logging.info(f"Refined text: {refined_text}")
        except Exception as e:
            logging.error(f"Refinement failed, falling back to raw text: {e}")
            refined_text = raw_text
            used_fallback = True
        if used_fallback:
            self.notification_callback("Refinement Failed", "Using raw transcript")

        # Paste immediately so the next riff can start. Persist only after a successful paste.
        pasted = self.injector.inject(refined_text)
        if not pasted:
            logging.error("Paste failed — skipping history, metrics, and cloud sync")
            self.notification_callback("Paste Failed", "Text was not inserted")
            return

        persist_job = {
            "raw_text": raw_text,
            "refined_text": refined_text,
            "style": style,
            "script_mode": self.transcriber.script_mode if self.transcriber else "unknown",
            "duration_sec": duration_sec,
            "word_count": len(refined_text.split()),
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
            with self._persist_lock:
                entry = self.history_manager.add_entry(raw_text, refined_text, style, script_mode)
                self.config_manager.update_metrics(word_count, duration_sec, style)
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

    def _refine_text(self, text, style):
        """Refine text using the configured style."""
        system_prompt = self.config_manager.get_prompt(style)
        logging.info(f"Refining with style: {style}")
        
        if self.refiner:
            return self.refiner.refine(text, style, prompt=system_prompt)
        else:
            logging.error("Refiner component not initialized")
            return text


class RiffApp:
    def __init__(self):
        logging.info("Initializing RiffApp")
        self.config = ConfigManager()
        self.permission_manager = PermissionManager()

        # Phase 2: Initialize Auth Manager
        self.auth_manager = None
        if AUTH_AVAILABLE:
            try:
                self.auth_manager = AuthManager(self.config)
                logging.info(f"[Auth] AuthManager initialized. Authenticated: {self.auth_manager.is_authenticated}")

                # Validate subscription on startup
                if self.auth_manager.is_authenticated:
                    subscription = self.auth_manager.validate_subscription()
                    tier = subscription.get("tier", "free")
                    status = subscription.get("status", "unknown")
                    logging.info(f"[Auth] Subscription: tier={tier}, status={status}")
            except Exception as e:
                logging.warning(f"[Auth] Failed to initialize AuthManager: {e}")

        # Load API Key (BYOK for free tier, 24h RAM lease for paid)
        self._uses_byok = True
        if self.auth_manager:
            self._uses_byok = get_tier_features(self.auth_manager.get_tier()).byok
            self.api_key = self.auth_manager.get_effective_api_key()
            if self.api_key:
                logging.info("[Auth] Groq client ready (%s)", "BYOK" if self._uses_byok else "paid 24h RAM lease")
            else:
                logging.info(
                    "[Auth] Groq key not ready yet (%s)",
                    "enter key in Settings" if self._uses_byok else "will lease on first riff",
                )
        else:
            self.api_key = self.config.get("api.api_key")

        self.tray = SystemTray(
            on_settings=self.open_settings,
            on_quit=self.quit,
            on_instructions=self.open_instructions,
            on_record=self.start_recording_manual,
            on_stop=self.stop_recording_manual,
            on_force_reset=self.force_reset_state,
            permission_manager=self.permission_manager
        )
        
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
            auth_manager=self.auth_manager  # Phase 2: Pass auth_manager
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
        self.watchdog_timeout = 60.0
        
        # Config Monitoring
        self.config_mtime = 0
        try:
            self.config_mtime = os.path.getmtime(self.config.config_path)
        except OSError:
            pass

        # Control Center is a separate Settings window. Closing it must not quit the tray.
        self.control_center_process = None

        logging.info("Initialization Complete")

    def handle_auth_url(self, url: str):
        if not self.auth_manager:
            return
        result = self.auth_manager.handle_auth_callback_url(url)
        if result.get("success"):
            self.show_notification("Riff", "Signed in successfully.")
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
            by_ts = {e.get("timestamp"): e for e in local if isinstance(e, dict)}
            for item in remote:
                ts = item.get("timestamp")
                if ts and ts not in by_ts:
                    by_ts[ts] = {
                        "timestamp": ts,
                        "original": item.get("original", ""),
                        "refined": item.get("refined", ""),
                        "style": item.get("style", ""),
                        "script_mode": item.get("script_mode", ""),
                    }
            merged = sorted(by_ts.values(), key=lambda e: e.get("timestamp", ""), reverse=True)[:50]
            with open(hm.history_file, "w") as f:
                json.dump(merged, f, indent=2)
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

    def update_tray_status(self, status):
        if status == "idle":
            self.is_processing = False
        if self.tray:
            self.tray.set_state(status)

    def show_notification(self, title, message):
        if self.tray:
            self.tray.show_notification(title, message)

    def start(self):
        print("Riff Starting...")
        logging.info("App start() called")
        self.install_auth_url_handler()
        if self.auth_manager and self.auth_manager.is_authenticated:
            try:
                self.auth_manager.register_this_device()
                remote = self.auth_manager.download_history()
                if remote:
                    self._merge_cloud_history(remote)
                pulled = self.auth_manager.pull_user_settings()
                if pulled:
                    if pulled.get("hotkey"):
                        self.config.set("hotkey.combination", pulled["hotkey"])
                    if pulled.get("style"):
                        self.config.set("style.active_style", pulled["style"])
                    if pulled.get("script_mode"):
                        self.config.set("script_mode.active_mode", pulled["script_mode"])
            except Exception as e:
                logging.warning("[Auth] Startup cloud sync failed: %s", e)
        
        # Check Accessibility without prompting. Hotkeys start once it is granted.
        perm_status = self.permission_manager.check_accessibility()
        logging.info(f"Accessibility Permission Status: {perm_status}")

        if perm_status:
            self.start_listener()
        else:
            logging.info("Deferring hotkey listener until Accessibility is granted in Settings")

        # Start Config Monitor (also detects API key changes from onboarding)
        threading.Thread(target=self.monitor_config, daemon=True).start()

        # Notify user if API key is missing (free-tier BYOK only)
        if not self.api_key and getattr(self, "_uses_byok", True):
            # Delay slightly so tray icon is visible before notification
            def _notify_setup():
                time.sleep(1.5)
                self.tray.show_notification("Riff — Setup Required",
                                            "Please enter your Groq API key in the Settings window.")
            threading.Thread(target=_notify_setup, daemon=True).start()

        # Start Health Monitor
        threading.Thread(target=self.health_monitor, daemon=True).start()

        # Start Tray on Main Thread (Blocking)
        try:
            self.tray.run()
        except KeyboardInterrupt:
            self.quit()

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
            time.sleep(2.0)
            try:
                if self.listener is None and self.permission_manager.check_accessibility():
                    logging.info("[ConfigMonitor] Accessibility granted — starting hotkey listener")
                    self.start_listener()

                if not os.path.exists(self.config.config_path):
                    continue

                mtime = os.path.getmtime(self.config.config_path)
                if mtime > self.config_mtime:
                    logging.info("Config file changed. Reloading...")
                    self.config_mtime = mtime

                    # Reload config
                    new_config = self.config.load()
                    new_key = new_config.get("hotkey", {}).get("combination", "ctrl_l")
                    if isinstance(new_key, list):
                        new_key = new_key[0]

                    if new_key != self.current_hotkey_str:
                        logging.info(f"Hotkey changed from {self.current_hotkey_str} to {new_key}. Restarting listener.")
                        self.start_listener()
                        self.tray.show_notification("Riff", f"Hotkey updated to: {new_key}")

                    # Check if API key was just configured (first-run onboarding)
                    new_api_key = new_config.get("api", {}).get("api_key", "")
                    if new_api_key and not self.api_key:
                        logging.info("[ConfigMonitor] API key detected — initializing transcriber and refiner")
                        self.api_key = new_api_key
                        try:
                            script_mode = self.config.get("script_mode.active_mode", "english_mixed")
                            self.transcriber = Transcriber(new_api_key, script_mode=script_mode)
                            self.refiner = Refiner(new_api_key, model=self.config.get("api.llm_model"))
                            # Update the processing thread's references
                            self.processing_thread.transcriber = self.transcriber
                            self.processing_thread.refiner = self.refiner
                            self.tray.show_notification("Riff", "API key configured! Ready to record.")
                            logging.info("[ConfigMonitor] Components initialized successfully")
                        except Exception as e:
                            logging.error(f"[ConfigMonitor] Failed to initialize components: {e}")
                            self.tray.show_notification("Error", f"Invalid API key: {e}")

            except Exception as e:
                logging.error(f"Error in config monitor: {e}")

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
            logging.info("Latch Stop Triggered via Hotkey")
            self._stop_latch_and_process()
            return

        # 2. Check for Latch Activation (Shift while recording)
        if (key == keyboard.Key.shift or key == keyboard.Key.shift_l or key == keyboard.Key.shift_r):
            if self.recorder.recording and not self.is_latched:
                logging.info("Latch Mode Enabled")
                self.is_latched = True
                self.tray.show_notification("Riff", "Latch Mode Enabled 🔒")

        # 3. Standard Trigger - Start Recording
        if key == trigger:
            logging.info("Hotkey Trigger Detected")

            # STATE VALIDATION: Run health check before starting
            is_healthy, issues = self.recorder.health_check()
            if not is_healthy:
                logging.warning(f"[Hotkey] Unhealthy state detected before start: {issues}")
                self.recorder.auto_recover()

            # Watchdog: Force Reset if stuck
            if self.is_processing:
                elapsed = time.time() - self.processing_start_time
                if elapsed > self.watchdog_timeout:
                    logging.warning(f"[Watchdog] Force resetting stuck state (stuck for {elapsed:.1f}s > {self.watchdog_timeout}s)")
                    self.is_processing = False
                    self.tray.set_state("idle")
                    self.recorder._force_cleanup()
                else:
                    logging.info(f"[Watchdog] Still processing ({elapsed:.1f}s elapsed), ignoring trigger")
                    return

            # Start recording if not already
            if not self.recorder.recording and not self.is_processing:
                try:
                    self.tray.set_state("recording")
                    self.recorder.start_recording()  # No VAD callback - manual stop only
                    logging.info("Recording started")
                    log_activity("Recording Started")
                except AudioRecorderError as e:
                    logging.error(f"Failed to start recording: {e}")
                    self.tray.show_notification("Error", f"Mic error: {e}")
                    self.tray.set_state("idle")
                except Exception as e:
                    logging.error(f"Unexpected error starting recording: {e}", exc_info=True)
                    self.tray.show_notification("Error", "Could not access microphone.")
                    self.tray.set_state("idle")

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
                logging.info("Hotkey Release Detected - Stopping")
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

        # Prevent double processing
        if self.is_processing:
            logging.warning("Already processing, ignoring stop request")
            return
        
        self.is_processing = True
        self.processing_start_time = time.time()
        self.tray.set_state("processing")
        
        # Process in a thread to not block hotkey listener
        threading.Thread(target=self._do_stop_and_queue, daemon=True).start()
    
    def _do_stop_and_queue(self):
        """Actually stop recording and queue the file."""
        filename = os.path.join(tempfile.gettempdir(), f"riff_recording_{time.time()}.wav")

        logging.info(f"[StopAndQueue] Attempting to stop recording and save to: {filename}")
        logging.info(f"[StopAndQueue] Pre-stop state: recording={self.recorder.recording}, stream={self.recorder.stream}")

        try:
            self.recorder.stop_recording(filename)
            
            if os.path.exists(filename) and os.path.getsize(filename) > 0:
                self.audio_queue.put(filename)
                log_activity("Recording Finished. Transcribing...")
                logging.info(f"Audio queued for processing: {filename}")
            else:
                logging.warning("No audio file created")
                self.tray.set_state("idle")
                self.is_processing = False
                
        except AudioRecorderError as e:
            logging.warning(f"Recording error: {e}")
            log_activity(f"Recording cancelled: {e}")
            self.tray.show_notification("Cancelled", str(e))
            self.tray.set_state("idle")
            self.is_processing = False
            
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
            self.tray.show_notification("Error", f"Recording failed: {e}")
            self.tray.set_state("idle")
            self.is_processing = False
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
            logging.error("[Manual Start] Processing flag stuck - forcing reset")
            self.is_processing = False
            self.tray.set_state("idle")

        # Now attempt to start
        if not self.recorder.recording and not self.is_processing:
            log_activity("Recording Started (Manual)")
            try:
                self.tray.set_state("recording")
                self.recorder.start_recording()
            except AudioRecorderError as e:
                logging.error(f"Manual start failed: {e}")
                self.tray.show_notification("Error", str(e))
                self.tray.set_state("idle")
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
                os.chmod(binary_path, os.stat(binary_path).st_mode | stat.S_IEXEC)

            # `open` uses Launch Services so the Dock app can be quit and reopened.
            subprocess.Popen(["open", app_path])
            logging.info("[Settings] Control Center launched via open")
        except Exception as e:
            logging.error(f"[Settings] Could not open settings: {e}", exc_info=True)

    def open_instructions(self):
        try:
            from ui.instructions import show_instructions
            threading.Thread(target=show_instructions, daemon=True).start()
        except Exception as e:
            logging.error(f"Could not open instructions: {e}")

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

    def quit(self):
        logging.info("Quitting App")
        log_activity("Riff App Quit")
        self.running = False

        self._quit_control_center()

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