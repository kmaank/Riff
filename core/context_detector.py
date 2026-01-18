
import platform
import time

try:
    if platform.system() == "Windows":
        import pygetwindow as gw
        import win32gui
        import win32process
        import psutil
    elif platform.system() == "Darwin":
        from AppKit import NSWorkspace
except ImportError:
    pass

class ContextDetector:
    def __init__(self):
        self.system = platform.system()

    def get_active_app_name(self) -> str:
        if self.system == "Windows":
            return self._get_windows_app()
        elif self.system == "Darwin":
            return self._get_macos_app()
        else:
            return "Unknown"

    def _get_windows_app(self) -> str:
        try:
            hwnd = win32gui.GetForegroundWindow()
            _, pid = win32process.GetWindowThreadProcessId(hwnd)
            process = psutil.Process(pid)
            return process.name().replace('.exe', '')
        except Exception:
            return "Unknown"

    def _get_macos_app(self) -> str:
        try:
            active_app = NSWorkspace.sharedWorkspace().frontmostApplication()
            return active_app.localizedName()
        except Exception:
            return "Unknown"

    def suggest_style(self, app_name: str, config: dict) -> str:
        app_styles = config.get("context_awareness.app_specific_styles", {})
        
        # Check for exact match
        if app_name in app_styles:
            return app_styles[app_name]
        
        # Check for partial match (case-insensitive)
        app_lower = app_name.lower()
        for key, style in app_styles.items():
            if key.lower() in app_lower:
                return style
        
        return config.get("style.active", "clean")

def main():
    detector = ContextDetector()
    print("Monitoring active app... (Press Ctrl+C to stop)")
    try:
        while True:
            app_name = detector.get_active_app_name()
            print(f"Active App: {app_name}")
            time.sleep(2)
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
