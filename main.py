
import threading
import time
import os
import sys
import logging
from pynput import keyboard

# Setup Logging
try:
    log_file = os.path.expanduser("~/Documents/Riff/debug.log")
    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    logging.basicConfig(
        filename=log_file,
        level=logging.DEBUG,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
except Exception as e:
    # Fallback to console if file logging fails
    logging.basicConfig(level=logging.DEBUG)
    print(f"Failed to setup file logging: {e}")

logging.info("----------------------------------------------------------------")
logging.info("Riff Logging Started")
logging.info(f"Python Version: {sys.version}")

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

class RiffApp:
    def __init__(self):
        logging.info("Initializing RiffApp")
        self.config = ConfigManager()
        self.permission_manager = PermissionManager()
        self.tray = SystemTray(
            on_settings=self.open_settings, 
            on_quit=self.quit,
            on_instructions=self.open_instructions,
            on_record=self.start_recording_manual,
            on_stop=self.stop_recording_manual,
            permission_manager=self.permission_manager
        )
        
        # Load API Key
        self.api_key = self.config.get("api.api_key")
        if not self.api_key:
            self.tray.show_notification("EchoFlow", "Please set your Groq API Key in config.json")
            logging.warning("API Key missing")

        # Initialize Components
        self.recorder = AudioRecorder(
            sample_rate=self.config.get("audio.sample_rate", 16000),
            silence_threshold_ms=self.config.get("audio.silence_threshold_ms", 600)
        )
        self.transcriber = Transcriber(self.api_key) if self.api_key else None
        self.refiner = Refiner(self.api_key, model=self.config.get("api.llm_model")) if self.api_key else None
        self.injector = TextInjector()
        self.context_detector = ContextDetector()
        
        self.is_processing = False
        self.running = True
        self.listener = None
        self.is_latched = False
        logging.info("Initialization Complete")

    def start(self):
        print("EchoFlow Starting...")
        logging.info("App start() called")
        
        # Check Accessibility Permission
        perm_status = self.permission_manager.check_accessibility()
        logging.info(f"Accessibility Permission Status: {perm_status}")
        
        if not perm_status:
            print("WARNING: Accessibility permission missing.")
            logging.warning("Accessibility permission missing!")
            self.tray.show_notification("Permission Needed", "Accessibility access needed for hotkeys.")
        
        # Start Hotkey Listener
        key_name = self.config.get("hotkey.combination", "f8")
        if isinstance(key_name, list): key_name = key_name[0]
        logging.info(f"Configured Hotkey: {key_name}")
        print(f"Press {key_name} to record.")
        
        try:
            logging.info("Starting keyboard listener...")
            self.listener = keyboard.Listener(
                on_press=self.on_press,
                on_release=self.on_release
            )
            self.listener.start()
            logging.info("Keyboard listener started successfully")
        except Exception as e:
            print(f"Error starting hotkey listener: {e}")
            logging.error(f"Error starting hotkey listener: {e}", exc_info=True)
            self.tray.show_notification("Error", f"Hotkey failed: {e}")
        
        # Start Tray on Main Thread (Blocking)
        try:
            self.tray.run()
        except KeyboardInterrupt:
            self.quit()

    def get_trigger_key(self):
        key_str = self.config.get("hotkey.combination", ["f8"])[0] if isinstance(self.config.get("hotkey.combination"), list) else self.config.get("hotkey.combination", "f8")
        
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
                 self.tray.show_notification("EchoFlow", "Latch Mode Enabled 🔒")

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
        import tempfile
        filename = os.path.join(tempfile.gettempdir(), "echoflow_recording.wav")
        
        try:
            # 1. Stop Recording (safe to call multiple times)
            self.recorder.stop_recording(filename)
            
            if not os.path.exists(filename):
                self.tray.set_state("idle")
                self.is_processing = False
                return

            if not self.transcriber or not self.refiner:
                 self.tray.show_notification("Error", "API Key missing. Check config.")
                 self.tray.set_state("error")
                 time.sleep(2)
                 self.tray.set_state("idle")
                 self.is_processing = False
                 return

            # Determine Context
            app_name = self.context_detector.get_active_app_name()
            print(f"Active App: {app_name}")
            logging.info(f"Active App: {app_name}")
            
            suggested_style = self.context_detector.suggest_style(app_name, self.config.config)
            print(f"Suggested Style: {suggested_style}")

            # 2. Transcribe
            print("--> Transcribing...")
            raw_text = self.transcriber.transcribe_file(filename)
            print(f"Raw: {raw_text}")
            logging.info(f"Transcription: {raw_text}")
            
            if not raw_text:
                self.tray.set_state("idle")
                self.is_processing = False
                return

            # 3. Refine
            print("--> Refining...")
            refined_text = self.refiner.refine(raw_text, style=suggested_style)
            print(f"Refined: {refined_text}")
            
            # 4. Inject
            print("--> Injecting...")
            self.injector.inject(refined_text)
            logging.info("Injection complete")
            
            self.tray.set_state("idle")
            
        except Exception as e:
            print(f"Error: {e}")
            logging.error(f"Processing Error: {e}", exc_info=True)
            self.tray.set_state("error")
            self.tray.show_notification("Error", str(e))
            time.sleep(2)
            self.tray.set_state("idle")
        finally:
            self.is_processing = False

    def open_settings(self):
        # Placeholder for settings (opens config file)
        import subprocess
        try:
            if sys.platform == "darwin":
                subprocess.call(["open", self.config.config_path])
            elif sys.platform == "win32":
                os.startfile(self.config.config_path)
            else:
                subprocess.call(["xdg-open", self.config.config_path])
        except Exception as e:
              print(f"Could not open config: {e}")

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
