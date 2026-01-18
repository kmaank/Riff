# EchoFlow Desktop: Technical Implementation Specifications

## Document 2 of 3 | Version 1.0

---

## 1. Module Specifications

This document provides detailed specifications for each module. Use these specs when prompting AI to generate code.

---

## 2. Module: Hotkey Listener

### Purpose
Detect global keyboard shortcuts across all applications, even when EchoFlow is not in focus.

### Interface

```python
class HotkeyListener:
    """
    Listens for global hotkey combinations.
    
    Events:
        on_activate: Called when hotkey is pressed
        on_deactivate: Called when hotkey is released
    """
    
    def __init__(self, 
                 combination: List[str],  # e.g., ['ctrl', 'shift', 'space']
                 mode: str = 'hold'):     # 'hold' or 'toggle'
        pass
    
    def start(self) -> None:
        """Start listening for hotkeys in background thread."""
        pass
    
    def stop(self) -> None:
        """Stop listening and clean up resources."""
        pass
    
    def set_callback(self, 
                     on_activate: Callable, 
                     on_deactivate: Callable) -> None:
        """Register callback functions for hotkey events."""
        pass
    
    def update_combination(self, combination: List[str]) -> None:
        """Change the hotkey combination at runtime."""
        pass
```

### Implementation Notes

```python
# Key mapping for pynput
KEY_MAP = {
    'ctrl': Key.ctrl,
    'shift': Key.shift,
    'alt': Key.alt,
    'cmd': Key.cmd,      # macOS only
    'space': Key.space,
    'f1': Key.f1,
    'f2': Key.f2,
    # ... etc
}

# For 'hold' mode:
# - on_activate fires on key DOWN
# - on_deactivate fires on key UP

# For 'toggle' mode:
# - First press: on_activate
# - Second press: on_deactivate
```

### Platform Differences

| Platform | Consideration |
|----------|---------------|
| Windows | Works out of the box |
| macOS | Requires Accessibility permission in System Preferences |

### Error Handling

| Error | Handling |
|-------|----------|
| Permission denied (macOS) | Show dialog with instructions to enable Accessibility |
| Hotkey conflict | Notify user, suggest alternative |

---

## 3. Module: Audio Recorder

### Purpose
Capture microphone input at 16kHz sample rate, mono channel, and provide audio data as numpy arrays.

### Interface

```python
class AudioRecorder:
    """
    Records audio from the default microphone.
    
    Audio format: 16kHz, mono, 16-bit PCM
    """
    
    def __init__(self,
                 sample_rate: int = 16000,
                 channels: int = 1,
                 chunk_size: int = 1024):
        pass
    
    def start_recording(self) -> None:
        """Begin capturing audio to internal buffer."""
        pass
    
    def stop_recording(self) -> np.ndarray:
        """
        Stop recording and return audio data.
        
        Returns:
            numpy array of shape (samples,) with dtype float32
            Values normalized to range [-1.0, 1.0]
        """
        pass
    
    def get_audio_level(self) -> float:
        """
        Get current audio amplitude (0.0 to 1.0).
        Useful for visual feedback.
        """
        pass
    
    def save_to_file(self, audio: np.ndarray, filepath: str) -> None:
        """Save audio array to WAV file."""
        pass
    
    def is_recording(self) -> bool:
        """Check if currently recording."""
        pass
```

### Implementation Pattern

```python
import sounddevice as sd
import numpy as np
from scipy.io import wavfile
import threading
import queue

class AudioRecorder:
    def __init__(self, sample_rate=16000, channels=1, chunk_size=1024):
        self.sample_rate = sample_rate
        self.channels = channels
        self.chunk_size = chunk_size
        self._audio_queue = queue.Queue()
        self._recording = False
        self._stream = None
    
    def _audio_callback(self, indata, frames, time, status):
        """Called by sounddevice for each audio chunk."""
        if status:
            print(f"Audio status: {status}")
        if self._recording:
            self._audio_queue.put(indata.copy())
    
    def start_recording(self):
        self._recording = True
        self._audio_queue = queue.Queue()  # Clear queue
        self._stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=self.channels,
            dtype='float32',
            blocksize=self.chunk_size,
            callback=self._audio_callback
        )
        self._stream.start()
    
    def stop_recording(self):
        self._recording = False
        if self._stream:
            self._stream.stop()
            self._stream.close()
        
        # Combine all chunks
        chunks = []
        while not self._audio_queue.empty():
            chunks.append(self._audio_queue.get())
        
        if chunks:
            return np.concatenate(chunks, axis=0).flatten()
        return np.array([], dtype='float32')
```

### Audio Format Requirements

| Parameter | Value | Reason |
|-----------|-------|--------|
| Sample rate | 16000 Hz | Optimal for speech recognition models |
| Channels | 1 (mono) | Speech models expect mono |
| Bit depth | 32-bit float | sounddevice default, convert for API |
| Format for API | 16-bit PCM WAV | Groq Whisper requirement |

### Conversion for API

```python
def convert_to_wav_bytes(audio: np.ndarray, sample_rate: int = 16000) -> bytes:
    """Convert float32 audio to WAV bytes for API upload."""
    import io
    from scipy.io import wavfile
    
    # Convert float32 [-1, 1] to int16
    audio_int16 = (audio * 32767).astype(np.int16)
    
    # Write to bytes buffer
    buffer = io.BytesIO()
    wavfile.write(buffer, sample_rate, audio_int16)
    buffer.seek(0)
    return buffer.read()
```

---

## 4. Module: Voice Activity Detection (VAD)

### Purpose
Detect when the user has stopped speaking to automatically trigger processing, even if hotkey is still held.

### Interface

```python
class VoiceActivityDetector:
    """
    Detects voice activity and silence in audio stream.
    Uses Silero VAD model for high accuracy.
    """
    
    def __init__(self,
                 silence_threshold_ms: int = 600,
                 sample_rate: int = 16000):
        pass
    
    def load_model(self) -> None:
        """Load Silero VAD model (do this once at startup)."""
        pass
    
    def process_chunk(self, audio_chunk: np.ndarray) -> bool:
        """
        Process audio chunk and return speech status.
        
        Args:
            audio_chunk: Audio data (float32, 16kHz)
            
        Returns:
            True if speech detected, False if silence
        """
        pass
    
    def get_silence_duration_ms(self) -> int:
        """Get duration of current silence streak in milliseconds."""
        pass
    
    def should_stop_recording(self) -> bool:
        """
        Returns True if silence has exceeded threshold.
        Call this after each process_chunk().
        """
        pass
    
    def reset(self) -> None:
        """Reset silence tracking for new recording session."""
        pass
```

### Implementation Pattern

```python
import torch

class VoiceActivityDetector:
    def __init__(self, silence_threshold_ms=600, sample_rate=16000):
        self.silence_threshold_ms = silence_threshold_ms
        self.sample_rate = sample_rate
        self.model = None
        self._silence_start = None
        self._last_speech_time = None
    
    def load_model(self):
        """Load Silero VAD model."""
        self.model, utils = torch.hub.load(
            repo_or_dir='snakers4/silero-vad',
            model='silero_vad',
            force_reload=False
        )
        self.model.eval()
    
    def process_chunk(self, audio_chunk: np.ndarray) -> bool:
        """Process chunk and return True if speech detected."""
        if self.model is None:
            raise RuntimeError("Model not loaded. Call load_model() first.")
        
        # Convert to torch tensor
        audio_tensor = torch.from_numpy(audio_chunk).float()
        
        # Get speech probability
        speech_prob = self.model(audio_tensor, self.sample_rate).item()
        
        is_speech = speech_prob > 0.5
        
        if is_speech:
            self._last_speech_time = time.time()
            self._silence_start = None
        else:
            if self._silence_start is None:
                self._silence_start = time.time()
        
        return is_speech
    
    def get_silence_duration_ms(self) -> int:
        if self._silence_start is None:
            return 0
        return int((time.time() - self._silence_start) * 1000)
    
    def should_stop_recording(self) -> bool:
        return self.get_silence_duration_ms() >= self.silence_threshold_ms
    
    def reset(self):
        self._silence_start = None
        self._last_speech_time = None
```

### Alternative: Simple Energy-Based VAD

For faster startup (no model loading), use simple energy-based detection:

```python
def simple_vad(audio_chunk: np.ndarray, threshold: float = 0.01) -> bool:
    """Simple energy-based voice activity detection."""
    energy = np.sqrt(np.mean(audio_chunk ** 2))
    return energy > threshold
```

---

## 5. Module: Transcriber (Groq Whisper)

### Purpose
Convert audio to text using Groq's Whisper API.

### Interface

```python
class Transcriber:
    """
    Transcribes audio to text using Groq Whisper API.
    """
    
    def __init__(self, api_key: str, model: str = "whisper-large-v3"):
        pass
    
    def transcribe(self, audio: np.ndarray, sample_rate: int = 16000) -> str:
        """
        Transcribe audio to text.
        
        Args:
            audio: Audio data as float32 numpy array
            sample_rate: Sample rate of audio
            
        Returns:
            Transcribed text string
            
        Raises:
            TranscriptionError: If API call fails
        """
        pass
    
    def transcribe_file(self, filepath: str) -> str:
        """Transcribe audio from a WAV file."""
        pass
```

### Implementation

```python
from groq import Groq
import io
import tempfile
from scipy.io import wavfile

class TranscriptionError(Exception):
    pass

class Transcriber:
    def __init__(self, api_key: str, model: str = "whisper-large-v3"):
        self.client = Groq(api_key=api_key)
        self.model = model
    
    def transcribe(self, audio: np.ndarray, sample_rate: int = 16000) -> str:
        """Transcribe audio array to text."""
        
        # Convert to 16-bit PCM WAV
        audio_int16 = (audio * 32767).astype(np.int16)
        
        # Save to temporary file (Groq requires file upload)
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
            wavfile.write(f.name, sample_rate, audio_int16)
            temp_path = f.name
        
        try:
            with open(temp_path, 'rb') as audio_file:
                transcription = self.client.audio.transcriptions.create(
                    file=audio_file,
                    model=self.model,
                    response_format="text"
                )
            return transcription.strip()
        
        except Exception as e:
            raise TranscriptionError(f"Transcription failed: {e}")
        
        finally:
            # Clean up temp file
            import os
            os.unlink(temp_path)
    
    def transcribe_file(self, filepath: str) -> str:
        """Transcribe from file path."""
        with open(filepath, 'rb') as audio_file:
            transcription = self.client.audio.transcriptions.create(
                file=audio_file,
                model=self.model,
                response_format="text"
            )
        return transcription.strip()
```

### API Details

| Parameter | Value |
|-----------|-------|
| Endpoint | `https://api.groq.com/openai/v1/audio/transcriptions` |
| Model | `whisper-large-v3` |
| Max file size | 25 MB |
| Supported formats | wav, mp3, m4a, webm |
| Latency | 200-400ms typical |

---

## 6. Module: Refiner (Groq Llama)

### Purpose
Clean, format, and style the raw transcript using Groq's Llama-3 model.

### Interface

```python
class Refiner:
    """
    Refines transcribed text using Groq Llama-3.
    Removes filler words, fixes grammar, applies style.
    """
    
    def __init__(self, api_key: str, model: str = "llama3-8b-8192"):
        pass
    
    def refine(self, 
               text: str, 
               style: str = "clean",
               context: Optional[str] = None,
               app_name: Optional[str] = None) -> str:
        """
        Refine text with specified style.
        
        Args:
            text: Raw transcript
            style: Style name ("clean", "professional", "casual", "technical")
            context: Optional clipboard context for replies
            app_name: Optional active application name for context
            
        Returns:
            Refined text string
        """
        pass
    
    def set_custom_style(self, name: str, instructions: str) -> None:
        """Add a custom style with user-defined instructions."""
        pass
```

### Implementation

```python
from groq import Groq

class RefinementError(Exception):
    pass

class Refiner:
    
    STYLES = {
        "clean": """Remove filler words (um, uh, like, you know, basically, actually).
Fix grammar and punctuation.
Keep the original tone and meaning.
Do not add or remove information.""",
        
        "professional": """Make the text formal and professional.
Remove all filler words and hesitations.
Use complete sentences.
Be concise but thorough.""",
        
        "casual": """Keep the text friendly and conversational.
Light grammar fixes only.
Preserve personality and informal expressions.
Remove only excessive filler words.""",
        
        "technical": """Preserve all technical terms exactly as spoken.
Fix obvious grammatical errors only.
Maintain precision and specificity.
Do not simplify technical language."""
    }
    
    def __init__(self, api_key: str, model: str = "llama3-8b-8192"):
        self.client = Groq(api_key=api_key)
        self.model = model
        self.custom_styles = {}
    
    def _build_prompt(self, text: str, style: str, 
                      context: str = None, app_name: str = None) -> str:
        """Build the system and user prompts."""
        
        style_instructions = self.STYLES.get(style) or \
                           self.custom_styles.get(style) or \
                           self.STYLES["clean"]
        
        system_prompt = f"""You are a dictation editor. Your job is to clean up spoken text.

STYLE INSTRUCTIONS:
{style_instructions}

RULES:
- Output ONLY the refined text
- Do not add any commentary, explanations, or prefixes
- Do not add quotation marks around the output
- If the input is empty or just noise, output nothing"""

        user_prompt = f"Transcript: {text}"
        
        if app_name:
            user_prompt = f"[User is typing in: {app_name}]\n\n{user_prompt}"
        
        if context:
            user_prompt = f"[Replying to: {context}]\n\n{user_prompt}"
        
        return system_prompt, user_prompt
    
    def refine(self, text: str, style: str = "clean",
               context: str = None, app_name: str = None) -> str:
        """Refine the transcript."""
        
        if not text or not text.strip():
            return ""
        
        system_prompt, user_prompt = self._build_prompt(
            text, style, context, app_name
        )
        
        try:
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                temperature=0.3,  # Low temperature for consistency
                max_tokens=2048
            )
            
            return response.choices[0].message.content.strip()
        
        except Exception as e:
            raise RefinementError(f"Refinement failed: {e}")
    
    def set_custom_style(self, name: str, instructions: str):
        """Add custom style."""
        self.custom_styles[name] = instructions
```

### API Details

| Parameter | Value |
|-----------|-------|
| Endpoint | `https://api.groq.com/openai/v1/chat/completions` |
| Model | `llama3-8b-8192` (fast) or `llama3-70b-8192` (smart) |
| Temperature | 0.3 (for consistency) |
| Max tokens | 2048 |
| Latency | 100-300ms typical |

---

## 7. Module: Text Injector

### Purpose
Type text into the currently active text field, simulating keyboard input.

### Interface

```python
class TextInjector:
    """
    Types text into the active window using keyboard simulation.
    """
    
    def __init__(self, 
                 typing_speed: str = "instant",  # "instant", "fast", "natural"
                 use_clipboard: bool = False):
        pass
    
    def inject(self, text: str) -> None:
        """
        Type text into active window.
        
        Args:
            text: Text to type
        """
        pass
    
    def inject_via_clipboard(self, text: str) -> None:
        """
        Paste text using clipboard (faster for long text).
        Copies to clipboard, then simulates Ctrl+V / Cmd+V.
        """
        pass
```

### Implementation

```python
from pynput.keyboard import Controller, Key
import time
import platform

class TextInjector:
    def __init__(self, typing_speed: str = "instant", use_clipboard: bool = False):
        self.keyboard = Controller()
        self.typing_speed = typing_speed
        self.use_clipboard = use_clipboard
        self.is_mac = platform.system() == "Darwin"
    
    def inject(self, text: str):
        """Type text character by character."""
        if self.use_clipboard or len(text) > 100:
            # Use clipboard for long text
            self.inject_via_clipboard(text)
            return
        
        delay = self._get_delay()
        
        for char in text:
            self.keyboard.type(char)
            if delay > 0:
                time.sleep(delay)
    
    def inject_via_clipboard(self, text: str):
        """Paste via clipboard (faster)."""
        import pyperclip
        
        # Save current clipboard
        try:
            old_clipboard = pyperclip.paste()
        except:
            old_clipboard = ""
        
        # Copy text to clipboard
        pyperclip.copy(text)
        
        # Small delay to ensure clipboard is ready
        time.sleep(0.05)
        
        # Simulate paste
        modifier = Key.cmd if self.is_mac else Key.ctrl
        with self.keyboard.pressed(modifier):
            self.keyboard.press('v')
            self.keyboard.release('v')
        
        # Restore old clipboard after delay
        time.sleep(0.1)
        try:
            pyperclip.copy(old_clipboard)
        except:
            pass
    
    def _get_delay(self) -> float:
        """Get delay between keystrokes based on speed setting."""
        speeds = {
            "instant": 0,
            "fast": 0.01,
            "natural": 0.03
        }
        return speeds.get(self.typing_speed, 0)
```

### Platform Notes

| Platform | Paste Shortcut | Notes |
|----------|---------------|-------|
| Windows | Ctrl+V | Works universally |
| macOS | Cmd+V | Requires Accessibility permission |

### Clipboard Library

Add to requirements:
```
pyperclip==1.8.2
```

---

## 8. Module: Context Detector

### Purpose
Detect the currently active application to enable context-aware styling.

### Interface

```python
class ContextDetector:
    """
    Detects the currently active application.
    """
    
    def get_active_window_title(self) -> str:
        """Get the title of the active window."""
        pass
    
    def get_active_app_name(self) -> str:
        """Get the name of the active application."""
        pass
    
    def suggest_style(self, app_name: str, config: dict) -> str:
        """Suggest a style based on active app and config."""
        pass
```

### Implementation (Cross-Platform)

```python
import platform

class ContextDetector:
    def __init__(self):
        self.system = platform.system()
    
    def get_active_window_title(self) -> str:
        """Get active window title."""
        if self.system == "Windows":
            return self._get_windows_title()
        elif self.system == "Darwin":
            return self._get_macos_title()
        else:
            return "Unknown"
    
    def get_active_app_name(self) -> str:
        """Get active application name."""
        if self.system == "Windows":
            return self._get_windows_app()
        elif self.system == "Darwin":
            return self._get_macos_app()
        else:
            return "Unknown"
    
    # Windows implementation
    def _get_windows_title(self) -> str:
        try:
            import pygetwindow as gw
            active = gw.getActiveWindow()
            return active.title if active else ""
        except:
            return ""
    
    def _get_windows_app(self) -> str:
        try:
            import win32gui
            import win32process
            import psutil
            
            hwnd = win32gui.GetForegroundWindow()
            _, pid = win32process.GetWindowThreadProcessId(hwnd)
            process = psutil.Process(pid)
            return process.name().replace('.exe', '')
        except:
            # Fallback: extract from window title
            title = self._get_windows_title()
            return title.split(' - ')[-1] if ' - ' in title else title
    
    # macOS implementation
    def _get_macos_title(self) -> str:
        try:
            from AppKit import NSWorkspace
            active_app = NSWorkspace.sharedWorkspace().frontmostApplication()
            return active_app.localizedName()
        except:
            return ""
    
    def _get_macos_app(self) -> str:
        return self._get_macos_title()
    
    def suggest_style(self, app_name: str, config: dict) -> str:
        """Suggest style based on app."""
        app_styles = config.get("context_awareness", {}).get("app_specific_styles", {})
        
        # Check for exact match
        if app_name in app_styles:
            return app_styles[app_name]
        
        # Check for partial match
        app_lower = app_name.lower()
        for key, style in app_styles.items():
            if key.lower() in app_lower:
                return style
        
        return config.get("style", {}).get("active", "clean")
```

### Windows Additional Dependencies

```
pygetwindow==0.0.9
pywin32==306
psutil==5.9.8
```

### macOS Additional Dependencies

```
pyobjc-framework-Cocoa==10.1
```

---

## 9. Module: System Tray

### Purpose
Provide a system tray icon with status indication and settings menu.

### Interface

```python
class SystemTray:
    """
    System tray icon with menu.
    """
    
    def __init__(self, 
                 on_settings: Callable,
                 on_quit: Callable):
        pass
    
    def set_state(self, state: str) -> None:
        """
        Set tray icon state.
        States: "idle", "recording", "processing", "error"
        """
        pass
    
    def show_notification(self, title: str, message: str) -> None:
        """Show a system notification."""
        pass
    
    def run(self) -> None:
        """Start the tray icon (blocks main thread)."""
        pass
    
    def stop(self) -> None:
        """Stop and remove tray icon."""
        pass
```

### Implementation

```python
import pystray
from PIL import Image
import threading

class SystemTray:
    def __init__(self, on_settings, on_quit):
        self.on_settings = on_settings
        self.on_quit = on_quit
        self.icon = None
        self._load_icons()
    
    def _load_icons(self):
        """Load icon images for each state."""
        self.icons = {
            "idle": Image.open("assets/icon_idle.png"),
            "recording": Image.open("assets/icon_recording.png"),
            "processing": Image.open("assets/icon_processing.png"),
            "error": Image.open("assets/icon_error.png")
        }
    
    def _create_menu(self):
        """Create right-click menu."""
        return pystray.Menu(
            pystray.MenuItem("EchoFlow", None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Settings", self.on_settings),
            pystray.MenuItem("Quit", self._quit)
        )
    
    def _quit(self):
        """Handle quit menu item."""
        self.icon.stop()
        self.on_quit()
    
    def set_state(self, state: str):
        """Update tray icon based on state."""
        if self.icon and state in self.icons:
            self.icon.icon = self.icons[state]
    
    def show_notification(self, title: str, message: str):
        """Show system notification."""
        if self.icon:
            self.icon.notify(message, title)
    
    def run(self):
        """Start tray icon (call from main thread)."""
        self.icon = pystray.Icon(
            "EchoFlow",
            self.icons["idle"],
            "EchoFlow - Ready",
            menu=self._create_menu()
        )
        self.icon.run()
    
    def run_detached(self):
        """Start tray in background thread."""
        thread = threading.Thread(target=self.run, daemon=True)
        thread.start()
    
    def stop(self):
        """Stop tray icon."""
        if self.icon:
            self.icon.stop()
```

---

## 10. Module: Configuration Manager

### Purpose
Load, save, and validate user configuration.

### Interface

```python
class ConfigManager:
    """
    Manages user configuration.
    """
    
    def __init__(self, config_path: str = None):
        pass
    
    def load(self) -> dict:
        """Load configuration from file."""
        pass
    
    def save(self, config: dict) -> None:
        """Save configuration to file."""
        pass
    
    def get(self, key: str, default: Any = None) -> Any:
        """Get a configuration value by dot-notation key."""
        pass
    
    def set(self, key: str, value: Any) -> None:
        """Set a configuration value."""
        pass
    
    def get_config_path(self) -> str:
        """Get the configuration file path."""
        pass
```

### Implementation

```python
import json
import os
import platform

class ConfigManager:
    DEFAULT_CONFIG = {
        "version": "1.0.0",
        "hotkey": {
            "combination": ["ctrl", "shift", "space"],
            "mode": "hold"
        },
        "audio": {
            "sample_rate": 16000,
            "channels": 1,
            "silence_threshold_ms": 600,
            "max_recording_seconds": 60
        },
        "style": {
            "active": "clean"
        },
        "context_awareness": {
            "enabled": True,
            "app_specific_styles": {}
        },
        "api": {
            "provider": "groq",
            "whisper_model": "whisper-large-v3",
            "llm_model": "llama3-8b-8192",
            "api_key": ""
        },
        "ui": {
            "start_on_boot": False,
            "show_notifications": True,
            "play_sounds": True
        }
    }
    
    def __init__(self, config_path: str = None):
        self.config_path = config_path or self._get_default_path()
        self.config = {}
        self._ensure_config_dir()
    
    def _get_default_path(self) -> str:
        """Get OS-appropriate config path."""
        system = platform.system()
        
        if system == "Windows":
            base = os.environ.get("APPDATA", os.path.expanduser("~"))
        elif system == "Darwin":
            base = os.path.expanduser("~/Library/Application Support")
        else:
            base = os.path.expanduser("~/.config")
        
        return os.path.join(base, "EchoFlow", "config.json")
    
    def _ensure_config_dir(self):
        """Create config directory if it doesn't exist."""
        os.makedirs(os.path.dirname(self.config_path), exist_ok=True)
    
    def load(self) -> dict:
        """Load config, creating default if needed."""
        if os.path.exists(self.config_path):
            with open(self.config_path, 'r') as f:
                self.config = json.load(f)
        else:
            self.config = self.DEFAULT_CONFIG.copy()
            self.save(self.config)
        
        return self.config
    
    def save(self, config: dict = None):
        """Save configuration."""
        if config:
            self.config = config
        
        with open(self.config_path, 'w') as f:
            json.dump(self.config, f, indent=2)
    
    def get(self, key: str, default=None):
        """Get value using dot notation (e.g., 'api.api_key')."""
        keys = key.split('.')
        value = self.config
        
        for k in keys:
            if isinstance(value, dict) and k in value:
                value = value[k]
            else:
                return default
        
        return value
    
    def set(self, key: str, value):
        """Set value using dot notation."""
        keys = key.split('.')
        config = self.config
        
        for k in keys[:-1]:
            if k not in config:
                config[k] = {}
            config = config[k]
        
        config[keys[-1]] = value
        self.save()
```

---

## 11. Error Classes

```python
# errors.py

class EchoFlowError(Exception):
    """Base exception for EchoFlow."""
    pass

class TranscriptionError(EchoFlowError):
    """Raised when transcription fails."""
    pass

class RefinementError(EchoFlowError):
    """Raised when LLM refinement fails."""
    pass

class AudioError(EchoFlowError):
    """Raised when audio recording fails."""
    pass

class ConfigError(EchoFlowError):
    """Raised when configuration is invalid."""
    pass

class HotkeyError(EchoFlowError):
    """Raised when hotkey registration fails."""
    pass
```

---

## 12. Logging Setup

```python
# logger.py

import logging
import os
from datetime import datetime

def setup_logger(log_dir: str = None) -> logging.Logger:
    """Setup application logger."""
    
    logger = logging.getLogger("echoflow")
    logger.setLevel(logging.DEBUG)
    
    # Console handler
    console = logging.StreamHandler()
    console.setLevel(logging.INFO)
    console.setFormatter(logging.Formatter(
        '%(asctime)s - %(levelname)s - %(message)s'
    ))
    logger.addHandler(console)
    
    # File handler (optional)
    if log_dir:
        os.makedirs(log_dir, exist_ok=True)
        log_file = os.path.join(
            log_dir, 
            f"echoflow_{datetime.now():%Y%m%d}.log"
        )
        file_handler = logging.FileHandler(log_file)
        file_handler.setLevel(logging.DEBUG)
        file_handler.setFormatter(logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        ))
        logger.addHandler(file_handler)
    
    return logger
```

---

## Document Navigation

- **Document 1:** Master Architecture & Overview
- **Document 2 (This):** Technical Implementation Specifications
- **Document 3:** Build Prompts & Execution Sequence

---

*End of Document 2*
