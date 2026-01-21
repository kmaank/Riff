
import json
import os
import platform
from typing import Any

class ConfigManager:
    DEFAULT_CONFIG = {
        "version": "1.0.0",
        "hotkey": {
            "combination": "ctrl_l",
            "mode": "hold"
        },
        "audio": {
            "sample_rate": 16000,
            "silence_threshold_ms": 600,
            "max_recording_seconds": 60
        },
        "style": {
            "active_style": "casual"
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
        
        # Migration: Check for deprecated models and update
        if self.config.get("api", {}).get("llm_model") == "llama3-8b-8192":
            print("[Config] Migrating deprecated model llama3-8b-8192 to llama-3.3-70b-versatile")
            self.set("api.llm_model", "llama-3.3-70b-versatile")
            
        return self.config

    def save(self, config: dict = None):
        if config:
            self.config = config
        
        # Atomic Write Strategy:
        # 1. Write to a temporary file (e.g., config.json.tmp)
        # 2. Flush and sync to disk
        # 3. Rename temporary file to actual file (atomic)
        tmp_path = self.config_path + ".tmp"
        try:
            with open(tmp_path, 'w') as f:
                json.dump(self.config, f, indent=2)
                f.flush()
                os.fsync(f.fileno()) # Ensure data hits the disk
            
            # Atomic swap
            os.replace(tmp_path, self.config_path)
            
        except Exception as e:
            print(f"Error saving config: {e}")
            # Try to clean up temp file if it exists
            if os.path.exists(tmp_path):
                try:
                    os.remove(tmp_path)
                except:
                    pass

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

        self.save()
        return self.config

    def get_api_key(self):
        return self.get("api.api_key")

    def get_style(self):
        val = self.get("style.active_style", "casual")
        print(f"[DEBUG] get_style called. Found: {val}")
        return val

    def get_prompt(self, style):
        # 1. Check for user override in config.json
        # The key is style.options.<style_name>
        config_override = self.get(f"style.options.{style}")
        if config_override:
            return config_override

        # 2. Hardcoded defaults
        prompts = {
            "casual": (
                "You are a transcriber who captures the raw authenticity of speech. "
                "Output the text exactly as spoken, preserving slang, emotions, and tone. "
                "Do NOT censor abusive or aggressive language. "
                "Do NOT remove filler words if they add to the emotion. "
                "Simply transcribe the 'feelings' and words of the person as is."
            ),
            "formal": (
                "You are a professional business editor. "
                "Your task is to transform the spoken input into clean, clear, and grammatically correct business-formal text. "
                "Remove all filler words (umm, uh, like), repetitions, and stuttering. "
                "Remove any abusive, aggressive, or slang language, replacing it with polite professional equivalents if necessary, or omitting it if irrelevant. "
                "Ensure the tone is respectful, concise, and ready for a professional email or Slack message."
            ),
            # Aliases
            "professional": (
                "You are a professional business editor. "
                "Your task is to transform the spoken input into clean, clear, and grammatically correct business-formal text. "
                "Remove all filler words (umm, uh, like), repetitions, and stuttering. "
                "Remove any abusive, aggressive, or slang language, replacing it with polite professional equivalents if necessary, or omitting it if irrelevant. "
                "Ensure the tone is respectful, concise, and ready for a professional email or Slack message."
            ),
            "clean": (
                 "You are a dictation editor. Clean the following transcript. "
                 "REMOVE: filler words (um, uh, like, you know, basicially), repetitions, and hesitations. "
                 "FIX: grammar, punctuation, and capitalization. "
                 "KEEP: the original tone, meaning, and non-filler words. "
                 "Do NOT act as a chatbot. Do NOT add intros/outros. Output ONLY the refined text."
            ),
            # Extras
            "code": "You are a coding assistant. Format the text as code comments or proper variable names (snake_case) depending on context.",
            "pirate": "You are a pirate. Arrr! Speak like one."
        }
        prompt = prompts.get(style, prompts["casual"])
        
        # Universal strict boundary to prevent "Here is the transcript" chatter
        strict_instruction = (
            "\n\nCRITICAL: Output ONLY the refined text. "
            "Do NOT include quotes, 'Here is the transcript:', or any explanations. "
            "Just the text."
        )
        
        return prompt + strict_instruction

def main():
    config = ConfigManager()
    print(f"Config path: {config.config_path}")
    print(f"API Key: {config.get('api.api_key')}")
    
    # Test setting
    # config.set("ui.show_notifications", False)
    # print(f"Notifications: {config.get('ui.show_notifications')}")

if __name__ == "__main__":
    main()
