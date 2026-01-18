
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
    def __init__(self, on_settings, on_quit, on_instructions=None, on_record=None, on_stop=None, permission_manager=None):
        self.on_settings = on_settings
        self.on_quit = on_quit
        self.on_instructions = on_instructions
        self.on_record = on_record
        self.on_stop = on_stop
        self.permission_manager = permission_manager or PermissionManager()
        self.icon = None
        self.icons = self._create_icons()
        self.current_state = "idle"

    def load_icon(self, icon_name):
        """Loads an icon from the assets folder."""
        try:
            # Determine path (handle dev vs frozen app)
            if getattr(sys, 'frozen', False):
                base_path = sys._MEIPASS
            else:
                current_dir = os.path.dirname(os.path.abspath(__file__))
                # ui/tray.py -> ../assets
                base_path = os.path.dirname(current_dir)
            
            icon_path = os.path.join(base_path, "assets", icon_name)
            return Image.open(icon_path)
        except Exception as e:
            logging.error(f"Failed to load icon {icon_name}: {e}")
            # Fallback to creating a simple colored square if image fails
            return self.create_fallback_icon("red" if "recording" in icon_name else "green" if "processing" in icon_name else "white")

    def create_fallback_icon(self, color):
        """Fallback generator if assets are missing."""
        width = 64
        height = 64
        image = Image.new('RGB', (width, height), color)
        dc = ImageDraw.Draw(image)
        dc.rectangle((0, 0, width, height), fill=color)
        return image

    def _create_icons(self):
        # Preload icons
        return {
            "idle": self.load_icon("tray_idle.png"),
            "recording": self.load_icon("tray_recording.png"),
            "processing": self.load_icon("tray_processing.png")
        }

    def _create_permissions_menu(self):
        status = self.permission_manager.get_all_status()
        
        mic_mark = "✓" if status.get("microphone") else "✗"
        acc_mark = "✓" if status.get("accessibility") else "✗"
        auto_mark = "?" 
        
        return pystray.Menu(
            pystray.MenuItem(f"{mic_mark} Microphone (Open Settings)", self._req_mic),
            pystray.MenuItem(f"{acc_mark} Accessibility (Open Settings)", self._req_acc),
            pystray.MenuItem(f"Automation (Open Settings)", self._req_auto)
        )

    def _req_mic(self, icon, item):
        self.permission_manager.request_microphone()
        self.update_menu()

    def _req_acc(self, icon, item):
        self.permission_manager.request_accessibility()
        self.update_menu()

    def _req_auto(self, icon, item):
        self.permission_manager.request_automation()
        self.update_menu()

    def _create_menu(self):
        # Dynamic label based on state
        state_label = f"Status: {self.current_state.title()}"
        
        return pystray.Menu(
            pystray.MenuItem(state_label, None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Start Recording", self._on_record_click, enabled=lambda item: self.current_state == "idle"),
            pystray.MenuItem("Stop Recording", self._on_stop_click, enabled=lambda item: self.current_state == "recording"),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("How to Use (Instructions)", self._on_instructions_click),
            pystray.MenuItem("Permissions ▸", self._create_permissions_menu()),
            pystray.MenuItem("Settings", self.on_settings),
            pystray.MenuItem("Quit", self._quit)
        )

    def _on_instructions_click(self, icon, item):
        if self.on_instructions:
            self.on_instructions()
    
    def update_menu(self):
        if self.icon:
            self.icon.menu = self._create_menu()

    def _on_record_click(self, icon, item):
        if self.on_record:
            self.on_record()

    def _on_stop_click(self, icon, item):
        if self.on_stop:
            self.on_stop()

    def _quit(self):
        if self.icon:
            self.icon.stop()
        if self.on_quit:
            self.on_quit()

    def set_state(self, state: str):
        self.current_state = state
        if self.icon:
            if state in self.icons:
                self.icon.icon = self.icons[state]
            # Update menu to reflect state changes (e.g. enable/disable buttons)
            self.update_menu()

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
