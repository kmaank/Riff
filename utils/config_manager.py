
import json
import os
import platform
from typing import Any

class ConfigManager:
    DEFAULT_CONFIG = {
        "version": "1.0.0",
        "hotkey": {
            "combination": ["ctrl_l"],
            "mode": "hold"
        },
        "audio": {
            "sample_rate": 16000,
            "silence_threshold_ms": 600,
            "max_recording_seconds": 60
        },
        "style": {
            "active": "clean"
        },
        "api": {
            "api_key": "",
            "whisper_model": "whisper-large-v3",
            "llm_model": "llama-3.3-70b-versatile"
        },
        "ui": {
            "show_notifications": True,
            "play_sounds": False
        }
    }

    def __init__(self, config_path: str = None):
        self.config_path = config_path or self._get_default_path()
        self.config = {}
        self._ensure_config_dir()
        self.load()

    def _get_default_path(self) -> str:
        system = platform.system()
        user_home = os.path.expanduser("~")
        
        if system == "Windows":
            base = os.environ.get("APPDATA", user_home)
        elif system == "Darwin":
            base = os.path.join(user_home, "Library", "Application Support")
        else:
            base = os.path.join(user_home, ".config")
            
        return os.path.join(base, "Riff", "config.json")

    def _ensure_config_dir(self):
        os.makedirs(os.path.dirname(self.config_path), exist_ok=True)

    def load(self) -> dict:
        if os.path.exists(self.config_path):
            try:
                with open(self.config_path, 'r') as f:
                    self.config = json.load(f)
                    
                # Basic merge with defaults (shallow)
                # For a robust app, a deep merge is better
                for key, value in self.DEFAULT_CONFIG.items():
                    if key not in self.config:
                        self.config[key] = value
            except Exception as e:
                print(f"Error loading config: {e}")
                self.config = self.DEFAULT_CONFIG.copy()
        else:
            self.config = self.DEFAULT_CONFIG.copy()
            self.save()
        return self.config

    def save(self, config: dict = None):
        if config:
            self.config = config
        
        try:
            with open(self.config_path, 'w') as f:
                json.dump(self.config, f, indent=2)
        except Exception as e:
            print(f"Error saving config: {e}")

    def get(self, key: str, default: Any = None) -> Any:
        keys = key.split('.')
        value = self.config
        
        for k in keys:
            if isinstance(value, dict) and k in value:
                value = value[k]
            else:
                return default
        return value

    def set(self, key: str, value: Any) -> None:
        keys = key.split('.')
        target = self.config
        
        for k in keys[:-1]:
            if k not in target:
                target[k] = {}
            target = target[k]
            if not isinstance(target, dict):
                 # Smashed a non-dict value? recreate
                 target = {}
        
        target[keys[-1]] = value
        self.save()

def main():
    config = ConfigManager()
    print(f"Config path: {config.config_path}")
    print(f"API Key: {config.get('api.api_key')}")
    
    # Test setting
    # config.set("ui.show_notifications", False)
    # print(f"Notifications: {config.get('ui.show_notifications')}")

if __name__ == "__main__":
    main()
