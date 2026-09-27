
import pystray
from PIL import Image, ImageDraw
import threading
import time
import os
import sys
import logging
from pystray import Icon, Menu, MenuItem
from utils.permissions import PermissionManager

class SystemTray:
    def __init__(self, on_settings, on_quit, on_instructions=None, on_record=None, on_stop=None, on_force_reset=None, on_reveal_logs=None, permission_manager=None):
        self.on_settings = on_settings
        self.on_quit = on_quit
        self.on_instructions = on_instructions
        self.on_record = on_record
        self.on_stop = on_stop
        self.on_force_reset = on_force_reset
        self.on_reveal_logs = on_reveal_logs
        self.permission_manager = permission_manager or PermissionManager()
        self.icon = None
        self.icons = self._create_icons()
        self.current_state = "idle"

    def load_icon(self, icon_name):
        """Loads an icon from the assets folder."""
        try:
            if getattr(sys, 'frozen', False):
                base_path = sys._MEIPASS
            else:
                current_dir = os.path.dirname(os.path.abspath(__file__))
                base_path = os.path.dirname(current_dir)
            
            icon_path = os.path.join(base_path, "assets", icon_name)
            return Image.open(icon_path)
        except Exception as e:
            logging.error(f"Failed to load icon {icon_name}: {e}")
            return self.create_fallback_icon("red" if "recording" in icon_name else "green" if "processing" in icon_name else "white")

    def create_fallback_icon(self, color):
        width = 64
        height = 64
        image = Image.new('RGB', (width, height), color)
        dc = ImageDraw.Draw(image)
        dc.rectangle((0, 0, width, height), fill=color)
        return image

    def _create_icons(self):
        return {
            "idle": self.load_icon("tray_idle.png"),
            "recording": self.load_icon("tray_recording.png"),
            "processing": self.load_icon("tray_processing.png")
        }

    def _create_advanced_menu(self):
        return pystray.Menu(
            pystray.MenuItem("Reveal Logs", self._on_reveal_logs_click),
            pystray.MenuItem("Force Reset", self._on_force_reset_click),
        )

    def _create_menu(self):
        return pystray.Menu(
            pystray.MenuItem("Riff", None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Open Home", self._on_settings_click, default=True),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Start Recording", self._on_record_click, enabled=lambda item: self.current_state == "idle"),
            pystray.MenuItem("Stop Recording", self._on_stop_click, enabled=lambda item: self.current_state == "recording"),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Advanced", self._create_advanced_menu()),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Quit", self._quit)
        )

    def _on_instructions_click(self, icon, item):
        logging.info("Tray: How to clicked")
        if self.on_instructions:
            self.on_instructions()
    
    def update_menu(self):
        if self.icon:
            self.icon.menu = self._create_menu()

    def _on_record_click(self, icon, item):
        logging.info("Tray: Start Recording clicked")
        if self.on_record:
            self.on_record()

    def _on_stop_click(self, icon, item):
        logging.info("Tray: Stop Recording clicked")
        if self.on_stop:
            self.on_stop()

    def _on_force_reset_click(self, icon, item):
        logging.warning("Tray: Force Reset clicked")
        if self.on_force_reset:
            self.on_force_reset()

    def _on_reveal_logs_click(self, icon, item):
        logging.info("Tray: Reveal Logs clicked")
        if self.on_reveal_logs:
            threading.Thread(target=self.on_reveal_logs, daemon=True).start()

    def _on_settings_click(self, icon, item):
        logging.info("Tray: Settings clicked")
        if self.on_settings:
            threading.Thread(target=self.on_settings, daemon=True).start()

    def _quit(self):
        logging.info("Tray: Quit clicked")
        if self.icon:
            self.icon.stop()
        if self.on_quit:
            self.on_quit()

    def set_state(self, state: str):
        self.current_state = state
        if not self.icon or state not in self.icons:
            return
        try:
            self.icon.icon = self.icons[state]
        except Exception:
            logging.debug("[Tray] Icon update failed for %s", state, exc_info=True)

    def show_notification(self, title: str, message: str):
        if self.icon:
            self.icon.notify(message, title)

    def run(self):
        self.icon = pystray.Icon(
            "Riff",
            self.icons["idle"],
            "Riff",
            menu=self._create_menu()
        )
        self.icon.run()

    def run_detached(self):
        thread = threading.Thread(target=self.run, daemon=True)
        thread.start()

    def stop(self):
        if self.icon:
            self.icon.stop()

def main():
    def on_settings():
        print("Settings clicked")
    def on_quit():
        print("Quit clicked")
    def on_record():
        print("Record clicked")
    def on_stop():
        print("Stop clicked")
        
    tray = SystemTray(on_settings, on_quit, on_record, on_stop)
    print("Tray running in background...")
    tray.run_detached()
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        tray.stop()

if __name__ == "__main__":
    main()
