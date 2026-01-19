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
from core.audio_recorder import AudioRecorder
from core.transcriber import Transcriber, TranscriptionError
from core.refiner import Refiner, RefinementError
from core.text_injector import TextInjector
from core.context_detector import ContextDetector
from utils.config_manager import ConfigManager
from ui.tray import SystemTray
from ui.native_onboarding import run_onboarding_native
from utils.permissions import PermissionManager
from ui.instructions import show_instructions


# Setup Logging
try:
    log_file = os.path.expanduser("~/Documents/Riff/debug.log")
    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler(sys.stdout)
        ]
    )
except Exception as e:
    print(f"Failed to setup file logging: {e}")

# Silence noisy libraries
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)

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

    def add_entry(self, original, refined, style):
        try:
            entry = {
                "timestamp": datetime.now().isoformat(),
                "original": original,
                "refined": refined,
                "style": style
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
                
            logging.info(f"History entry added: {style}")
        except Exception as e:
            logging.error(f"Failed to save history: {e}")


class ProcessingThread(threading.Thread):
    def __init__(self, audio_queue, config_manager, status_callback, notification_callback, refiner=None, transcriber=None):
        super().__init__(daemon=True)
        self.audio_queue = audio_queue
        self.config_manager = config_manager
        self.status_callback = status_callback
        self.notification_callback = notification_callback
        self.transcriber = transcriber
        self.refiner = refiner
        self.history_manager = HistoryManager()
        # Fallback if component not passed (should not happen in correct init)
        if not self.transcriber:
             self.transcriber = Transcriber(config_manager.get_api_key())
        if not self.refiner:
             self.refiner = Refiner(config_manager.get_api_key())

    def run(self):
        logging.info("Processing thread started")
        while True:
            audio_path = self.audio_queue.get()
            if audio_path is None:
                break

            try:
                self.status_callback("processing")
                
                # Reload config to get latest style changes from UI
                self.config_manager.load()
                
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
                            time.sleep(1) # Short backoff
                        else:
                            raise e # Re-raise if all fail
                            
                logging.info(f"Raw transcription: {raw_text}")

                # 2. Get Context & Style
                context = "" # self.get_active_context()
                style = self.config_manager.get_style()
                
                # 3. Refine with Fallback
                logging.info(f"Refining with style '{style}'...")
                refined_text = raw_text
                used_fallback = False
                
                try:
                    refined_text = self.refine_text(raw_text, style, context)
                    logging.info(f"Refined text: {refined_text}")
                except Exception as e:
                    logging.error(f"Refinement failed, falling back to raw text: {e}")
                    refined_text = raw_text
                    used_fallback = True
                    self.notification_callback("Refinement Failed", "Using raw transcript")

                # 4. Save History
                self.history_manager.add_entry(raw_text, refined_text, style)

                # 5. Type
                self.type_text(refined_text)
                
                # 6. Notify
                if used_fallback:
                     self.notification_callback("Riff Complete", "Converted (Raw Fallback)")
                else:
                     self.notification_callback("Riff Complete", f"Converted ({style})")

            except Exception as e:
                logging.error(f"Processing failed: {e}")
                self.notification_callback("Error", str(e))
            finally:
                self.status_callback("idle")
                try:
                    os.remove(audio_path)
                except OSError:
                    pass
                self.audio_queue.task_done()

    def refine_text(self, text, style, context):
        try:
            # Get prompt from config (handles overrides and defaults)
            system_prompt = self.config_manager.get_prompt(style)
            
            logging.info(f"Refining with style: {style}")
            
            # Use the dedicated Refiner component
            if self.refiner:
                 return self.refiner.refine(text, style, prompt=system_prompt)
            else:
                 logging.error("Refiner component not initialized")
                 return text

        except Exception as e:
            logging.error(f"Refinement failed: {e}")
            return text 

    def type_text(self, text):
        script = f'''
        tell application "System Events"
            keystroke "{text}"
        end tell
        '''
        try:
            subprocess.run(["osascript", "-e", script], check=True)
        except subprocess.CalledProcessError as e:
            logging.error(f"Typing failed: {e}")


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
            permission_manager=self.permission_manager
        )
        
        if not self.api_key:
            self.tray.show_notification("Riff", "Please set your Groq API Key in config.json")
            logging.warning("API Key missing")

        self.transcriber = Transcriber(self.api_key) if self.api_key else None
        self.refiner = Refiner(self.api_key, model=self.config.get("api.llm_model")) if self.api_key else None
        
        # Initialize Audio Queue and Processing Thread
        self.audio_queue = queue.Queue()
        self.processing_thread = ProcessingThread(
            self.audio_queue, 
            self.config, 
            self.update_tray_status, 
            self.show_notification,
            refiner=self.refiner,
            transcriber=self.transcriber
        )
        self.processing_thread.start()

        # Initialize Components
        self.recorder = AudioRecorder(
            sample_rate=self.config.get("audio.sample_rate", 16000),
            silence_threshold_ms=self.config.get("audio.silence_threshold_ms", 600)
        )
        self.injector = TextInjector()
        self.context_detector = ContextDetector()
        
        self.is_processing = False
        self.running = True
        self.listener = None
        self.current_hotkey_str = self.config.get("hotkey.combination", "ctrl_l")
        
        # Determine initial hotkey string safely
        if isinstance(self.current_hotkey_str, list) and len(self.current_hotkey_str) > 0:
             self.current_hotkey_str = self.current_hotkey_str[0]
        elif not isinstance(self.current_hotkey_str, str):
             self.current_hotkey_str = "ctrl_l"
             
        self.is_latched = False
        
        # Config Monitoring
        self.config_mtime = 0
        try:
            self.config_mtime = os.path.getmtime(self.config.config_path)
        except OSError:
            pass
            
        logging.info("Initialization Complete")

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
        if isinstance(key_name, list): key_name = key_name[0]
        self.current_hotkey_str = key_name
        
        logging.info(f"Binder Hotkey: {key_name}")
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
                    # Handle legacy list
                    if isinstance(new_key, list): new_key = new_key[0]
                    
                    if new_key != self.current_hotkey_str:
                        logging.info(f"Hotkey changed from {self.current_hotkey_str} to {new_key}. Restarting listener.")
                        self.start_listener()
                        self.tray.show_notification("Riff", f"Hotkey updated to: {new_key}")
                        
            except Exception as e:
                logging.error(f"Error in config monitor: {e}")

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
            self.quit_latch_and_process()
            return

        # 2. Check for Latch Activation (Shift while triggering)
        if (key == keyboard.Key.shift or key == keyboard.Key.shift_l or key == keyboard.Key.shift_r) and self.recorder.recording:
            if not self.is_latched:
                 logging.info("Latch Mode Enabled")
                 self.is_latched = True
                 self.tray.show_notification("Riff", "Latch Mode Enabled 🔒")

        # 3. Standard Trigger
        if key == trigger:
            logging.info("Hotkey Trigger Detected")
            if not self.recorder.recording and not self.is_processing:
                self.tray.set_state("recording")
                # Disable VAD auto-stop to allow pauses
                self.recorder.start_recording()

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
                # Stop recording and process
                self.tray.set_state("processing")
                threading.Thread(target=self.process_audio).start()

    def quit_latch_and_process(self):
        self.tray.set_state("processing")
        self.is_latched = False
        threading.Thread(target=self.process_audio).start()
    
    def on_auto_stop(self):
        """Called by VAD when silence is detected."""
        print("[Auto-Stop] Silence detected.")
        self.tray.set_state("processing")
        threading.Thread(target=self.process_audio).start()

    def start_recording_manual(self):
        """Manually start recording from tray."""
        if not self.recorder.recording and not self.is_processing:
            logging.info("Manual Start Triggered")
            self.tray.set_state("recording")
            self.recorder.start_recording()

    def stop_recording_manual(self):
        """Manually stop recording from tray."""
        if self.recorder.recording:
            logging.info("Manual Stop Triggered")
            self.tray.set_state("processing")
            threading.Thread(target=self.process_audio).start()

    def process_audio(self):
        # Prevent double processing (e.g. key release + auto-stop race)
        if self.is_processing:
            return
            
        self.is_processing = True
        logging.info("Processing Audio...")
        
        filename = os.path.join(tempfile.gettempdir(), f"echoflow_recording_{time.time()}.wav")
        
        try:
            self.recorder.stop_recording(filename)
            if os.path.exists(filename) and os.path.getsize(filename) > 0:
                self.audio_queue.put(filename)
            else:
                logging.warning("No audio recorded or file is empty.")
                self.tray.set_state("idle")
                self.is_processing = False
                if os.path.exists(filename):
                    os.remove(filename)
        except Exception as e:
            logging.error(f"Error stopping recording or queuing audio: {e}", exc_info=True)
            self.tray.show_notification("Error", f"Recording failed: {e}")
            self.tray.set_state("idle")
            self.is_processing = False
            if os.path.exists(filename):
                os.remove(filename)

    def open_settings(self):
        try:
            # Determine Path
            if getattr(sys, 'frozen', False):
                # Robust Search for Frozen App
                candidates = []
                
                exe_dir = os.path.dirname(sys.executable)
                
                # 1. In Resources (Contents/Resources) - Preferred for macOS Bundle
                candidates.append(os.path.abspath(os.path.join(exe_dir, "..", "Resources", "RiffControlCenter.app")))

                # 2. sys._MEIPASS (OneFile / Internal)
                if hasattr(sys, '_MEIPASS'):
                   candidates.append(os.path.join(sys._MEIPASS, "RiffControlCenter.app"))
                
                # 3. In Frameworks (Contents/Frameworks) - PyInstaller often dumps here
                candidates.append(os.path.abspath(os.path.join(exe_dir, "..", "Frameworks", "RiffControlCenter.app")))
                
                # 4. Alongside executable (Contents/MacOS)
                candidates.append(os.path.join(exe_dir, "RiffControlCenter.app"))

                app_path = candidates[0] # Default relative to Resources if nothing found
                found = False
                for c in candidates:
                    if os.path.exists(c):
                        # Verify it has contents
                        if os.path.exists(os.path.join(c, "Contents", "MacOS")):
                            app_path = c
                            found = True
                            break
                
                if not found:
                    logging.warning("RiffControlCenter.app search failed, defaulting to Resources path")
            else:
                # Dev: config_ui/build/RiffControlCenter.app
                app_path = os.path.join(os.getcwd(), "config_ui", "build", "RiffControlCenter.app")
            
            logging.info(f"Launching settings app at: {app_path}")
            if os.path.exists(app_path):
                # Use open -a to force launch as application
                subprocess.call(["open", "-a", app_path])
            else:
                logging.error(f"Settings app not found at {app_path}")
                # Fallback to file open
                subprocess.call(["open", self.config.config_path])
                
        except Exception as e:
            logging.error(f"Could not open settings: {e}")

    def open_instructions(self):
        # Run instructions in a thread to avoid blocking tray
        threading.Thread(target=show_instructions, daemon=True).start()

    def quit(self):
        logging.info("Quitting App")
        self.running = False
        if self.listener:
            try:
                self.listener.stop()
            except: 
                pass
        self.audio_queue.put(None) # Signal processing thread to stop
        self.processing_thread.join(timeout=5) # Wait for thread to finish
        self.tray.stop()
        sys.exit(0)

def main():
    # 1. Load Config
    config = ConfigManager()
    
    # 2. Check for First Run / Missing Key
    api_key = config.get("api.api_key")
    if not api_key:
        print("First run detected. Launching Native Onboarding...")
        # Use Native AppleScript Onboarding (Safe for all macOS versions)
        run_onboarding_native(config)
        
        # Reload key after onboarding
        api_key = config.get("api.api_key")
        if not api_key:
            print("Setup cancelled. Exiting.")
            sys.exit(0)
            
    # 3. Start App
    app = RiffApp()
    app.start()

if __name__ == "__main__":
    main()
