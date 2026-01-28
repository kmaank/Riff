import json
import logging
import os
import tempfile
import threading
import time
import subprocess
import queue
import sys
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
            
            with open(self.history_file, 'w') as f:
                json.dump(history, f, indent=2)
                
            logging.info(f"History entry added: {style}, script_mode: {script_mode}")
        except Exception as e:
            logging.error(f"Failed to save history: {e}")


class ProcessingThread(threading.Thread):
    def __init__(self, audio_queue, config_manager, status_callback, notification_callback, 
                 refiner=None, transcriber=None, injector=None, watchdog_callback=None,
                 processing_done_callback=None):
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
        
        # Fallback initialization
        if not self.transcriber:
            script_mode = config_manager.get("script_mode.active_mode", "english_mixed")
            self.transcriber = Transcriber(config_manager.get_api_key(), script_mode=script_mode)
        if not self.refiner:
            self.refiner = Refiner(config_manager.get_api_key())
        if not self.injector:
            self.injector = TextInjector()

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

    def _process_audio_file(self, audio_path):
        """Process a single audio file through the pipeline."""
        
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
            self.notification_callback("Refinement Failed", "Using raw transcript")

        # 4. Save History
        script_mode = self.transcriber.script_mode if self.transcriber else "unknown"
        self.history_manager.add_entry(raw_text, refined_text, style, script_mode)

        # 5. Type/Inject
        self.injector.inject(refined_text)
        
        # 6. Notify
        if used_fallback:
            self.notification_callback("Riff Complete", "Converted (Raw Fallback)")
            log_activity(f"Success: Transcribed & Pasted (Raw Fallback). Text length: {len(refined_text)}")
        else:
            self.notification_callback("Riff Complete", f"Converted ({style})")
            log_activity(f"Success: Transcribed & Pasted (Style: {style}). Text length: {len(refined_text)}")

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
        
        # Load API Key
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
            self.tray.show_notification("Riff", "Please set your Groq API Key in config.json")
            logging.warning("API Key missing")

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
            processing_done_callback=self._on_processing_done
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

        # Control Center Process Tracking
        self.control_center_process = None

        logging.info("Initialization Complete")

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
        
        # Check Accessibility Permission
        perm_status = self.permission_manager.check_accessibility()
        logging.info(f"Accessibility Permission Status: {perm_status}")
        
        if not perm_status:
            print("WARNING: Accessibility permission missing.")
            logging.warning("Accessibility permission missing!")
            self.tray.show_notification("Permission Needed", "Accessibility access needed for hotkeys.")
        
        # Start Hotkey Listener
        self.start_listener()

        # Start Config Monitor
        threading.Thread(target=self.monitor_config, daemon=True).start()

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
        """Polls config file for changes to reload hotkeys dynamically."""
        while self.running:
            time.sleep(2.0)
            try:
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

    def open_settings(self):
        try:
            # Check if Control Center is already running
            if self.control_center_process is not None:
                poll_result = self.control_center_process.poll()
                if poll_result is None:  # Still running
                    logging.info("Control Center already running, bringing to front")
                    # Use AppleScript to activate the running app
                    try:
                        subprocess.call(["osascript", "-e", 'tell application "RiffControlCenter" to activate'])
                    except:
                        pass  # If activation fails, continue to relaunch
                    return

            # Find Control Center app path
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
                # Launch the app binary directly to get a process handle
                binary_path = os.path.join(app_path, "Contents", "MacOS", "RiffControlCenter")
                if os.path.exists(binary_path):
                    self.control_center_process = subprocess.Popen([binary_path])
                    logging.info(f"Control Center launched with PID: {self.control_center_process.pid}")

                    # Activate the app window (bring to front)
                    time.sleep(0.3)  # Brief delay to let app initialize
                    try:
                        subprocess.call(["osascript", "-e", 'tell application "RiffControlCenter" to activate'])
                    except Exception as e:
                        logging.warning(f"Failed to activate Control Center window: {e}")
                else:
                    # Fallback to open -a if binary not found
                    subprocess.call(["open", "-a", app_path])
            else:
                logging.error(f"Settings app not found at {app_path}")
                subprocess.call(["open", self.config.config_path])

        except Exception as e:
            logging.error(f"Could not open settings: {e}")

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

        # Terminate Control Center if running
        if self.control_center_process is not None:
            try:
                poll_result = self.control_center_process.poll()
                if poll_result is None:  # Still running
                    logging.info("Terminating Control Center process")
                    self.control_center_process.terminate()
                    # Give it 2 seconds to close gracefully
                    try:
                        self.control_center_process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        # Force kill if it doesn't close gracefully
                        logging.warning("Control Center didn't close gracefully, force killing")
                        self.control_center_process.kill()
            except Exception as e:
                logging.error(f"Error terminating Control Center: {e}")

        try:
            if self.listener:
                self.listener.stop()
        except:
            pass

        try:
            self.audio_queue.put(None)
            self.processing_thread.join(timeout=2)
        except:
            pass

        self.tray.stop()
        logging.info("Force exiting now.")
        os._exit(0)


def launch_settings_app(config):
    try:
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
            # Use 'open' directly on the path without '-a' to force opening this specific bundle
            # '-a' often resolves to registered applications (which might be old versions in /Applications)
            subprocess.call(["open", app_path])
        else:
            logging.error(f"Settings app not found at {app_path}")
            subprocess.call(["open", config.config_path])
            
    except Exception as e:
        logging.error(f"Could not open settings: {e}")


def main():
    # 1. Load Config
    config = ConfigManager()
    
    # 2. Check for First Run / Missing Key
    api_key = config.get("api.api_key")
    if not api_key:
        print("First run detected. Launching Riff Control Center for Onboarding...")
        
        launch_settings_app(config)
        
        # Wait for key loop
        print("Waiting for API key configuration...")
        while not api_key:
            time.sleep(1)
            config.load()
            api_key = config.get("api.api_key")
            
        print("API Key found! Starting Riff...")

    # 3. Start App
    app = RiffApp()
    app.start()


if __name__ == "__main__":
    main()