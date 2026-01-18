# EchoFlow Desktop: Build Prompts & Execution Sequence

## Document 3 of 3 | Version 1.0

---

## How To Use This Document

This document contains ready-to-use prompts for AI coding assistants (Gemini, Claude, GPT, Cursor). 

**Instructions:**
1. Work through prompts IN ORDER (they build on each other)
2. Copy entire prompt block (including context)
3. Paste into your AI assistant
4. Test the generated code before moving to next prompt
5. If errors occur, paste the error back to the AI for fixing

---

## Pre-Build Setup

### Step 0: Environment Setup

Before starting, set up your development environment.

**Prompt for AI:**

```
I need to set up a Python development environment for a desktop application. 

Help me with step-by-step commands for:
1. Install Python 3.11 (check if already installed)
2. Create a new project folder called "echoflow"
3. Create a virtual environment
4. Create a requirements.txt file with these dependencies:

sounddevice==0.4.6
numpy==1.26.4
scipy==1.12.0
pynput==1.7.6
groq==0.4.2
pystray==0.19.5
Pillow==10.2.0
pyperclip==1.8.2
plyer==2.1.0

For Windows also add:
pygetwindow==0.0.9

For macOS also add:
pyobjc-framework-Cocoa==10.1

5. Install all dependencies
6. Create the folder structure:
   echoflow/
   ├── main.py
   ├── requirements.txt
   ├── config.json
   ├── core/
   │   └── __init__.py
   ├── ui/
   │   └── __init__.py
   ├── utils/
   │   └── __init__.py
   └── assets/

Give me the exact terminal commands for [Windows/macOS - specify your OS].
```

---

## Phase 1: Core MVP

### Prompt 1.1: Basic Audio Recording

**Goal:** Record audio when F8 is pressed, save to file.

```
Create a Python script that records audio from the microphone.

REQUIREMENTS:
1. Use sounddevice library for audio capture
2. Record at 16kHz sample rate, mono channel
3. When user presses F8 key, start recording
4. When user releases F8 key, stop recording
5. Save the audio to a file called "temp_recording.wav"
6. Print "[Recording started]" and "[Recording stopped: X.X seconds]"

TECHNICAL SPECS:
- Use pynput for keyboard detection
- Audio format: 16kHz, mono, float32 (convert to int16 for WAV)
- Use scipy.io.wavfile to save the WAV file
- Handle the case where no audio is captured

Create a single file: core/audio_recorder.py

Include a main() function that demonstrates the recording when run directly.
```

**Test:** Run the script, press F8, speak, release F8. Check that temp_recording.wav is created and playable.

---

### Prompt 1.2: Groq Whisper Transcription

**Goal:** Send audio to Groq Whisper API and get text back.

```
Create a Python module that transcribes audio using Groq's Whisper API.

REQUIREMENTS:
1. Use the groq library
2. Accept a WAV file path as input
3. Send to Groq Whisper API (model: whisper-large-v3)
4. Return the transcribed text
5. Handle errors gracefully (no internet, invalid API key, etc.)

TECHNICAL SPECS:
- API key should be passed as parameter (we'll load from config later)
- Create custom exception class TranscriptionError
- Print status messages: "[Transcribing...]" and "[Transcription complete]"

Create file: core/transcriber.py

Include these components:
1. TranscriptionError exception class
2. Transcriber class with:
   - __init__(self, api_key: str)
   - transcribe_file(self, filepath: str) -> str
3. main() function that:
   - Asks user to input API key
   - Transcribes "temp_recording.wav" 
   - Prints the result

Example usage:
```python
transcriber = Transcriber(api_key="gsk_xxx")
text = transcriber.transcribe_file("temp_recording.wav")
print(text)
```
```

**Test:** Get a Groq API key from console.groq.com. Run the script with a recorded WAV file.

---

### Prompt 1.3: Groq Llama Text Refinement

**Goal:** Clean up transcribed text using Llama-3.

```
Create a Python module that refines text using Groq's Llama-3 API.

REQUIREMENTS:
1. Accept raw transcribed text as input
2. Send to Groq Llama-3 API (model: llama3-8b-8192)
3. Remove filler words (um, uh, like, you know)
4. Fix grammar and punctuation
5. Return only the cleaned text (no explanations)

TECHNICAL SPECS:
- Support multiple styles: "clean", "professional", "casual"
- Use low temperature (0.3) for consistency
- Create custom exception class RefinementError

STYLE DEFINITIONS:
- clean: Remove filler words, fix grammar, keep original tone
- professional: Make formal and concise
- casual: Keep friendly, light grammar fixes only

Create file: core/refiner.py

Include:
1. RefinementError exception class
2. Refiner class with:
   - __init__(self, api_key: str)
   - refine(self, text: str, style: str = "clean") -> str
3. STYLES dictionary with system prompts for each style
4. main() function demonstrating usage

The system prompt template:
"You are a dictation editor. Clean the following transcript.
[STYLE INSTRUCTIONS]
Output ONLY the refined text. No explanations or quotation marks."
```

**Test:** Run with sample text like "I was uh thinking that maybe we should like go to the store or something"

---

### Prompt 1.4: Text Injection

**Goal:** Type text into the active window.

```
Create a Python module that types text into the currently active window.

REQUIREMENTS:
1. Use pynput.keyboard to simulate keystrokes
2. Support two modes:
   - Direct typing (character by character)
   - Clipboard paste (for long text, faster)
3. Automatically use clipboard for text longer than 100 characters
4. Work on both Windows and macOS

TECHNICAL SPECS:
- Use pyperclip for clipboard operations
- On macOS, use Cmd+V for paste
- On Windows, use Ctrl+V for paste
- Add small delay after clipboard copy before paste (50ms)

Create file: core/text_injector.py

Include:
1. TextInjector class with:
   - __init__(self, use_clipboard: bool = True)
   - inject(self, text: str) -> None
   - inject_via_clipboard(self, text: str) -> None
2. main() function that:
   - Waits 3 seconds (so user can click into a text field)
   - Types "Hello from EchoFlow!"

Print "[Injecting text...]" when starting and "[Done]" when complete.
```

**Test:** Run the script, quickly click into a text editor, watch it type.

---

### Prompt 1.5: Integrate Core Pipeline

**Goal:** Connect all modules into a working pipeline.

```
Create the main pipeline that connects audio recording, transcription, refinement, and text injection.

REQUIREMENTS:
1. Import and use the modules we created:
   - core/audio_recorder.py
   - core/transcriber.py
   - core/refiner.py
   - core/text_injector.py
2. Create a single pipeline:
   - F8 pressed → Start recording
   - F8 released → Stop recording → Transcribe → Refine → Inject text
3. Print status at each step
4. Handle errors gracefully (show message, don't crash)

Create file: main.py

The flow:
```
[IDLE] 
   → F8 pressed 
[RECORDING] 
   → F8 released
[PROCESSING]
   → Transcribe audio
   → Refine text  
   → Inject into active window
[IDLE]
```

Configuration (hardcoded for now, we'll add config file later):
- API_KEY = "your_groq_api_key_here"  # User replaces this
- STYLE = "clean"
- HOTKEY = "f8"

Include proper imports and a clear main() entry point.
The script should run continuously until Ctrl+C is pressed.
Print "EchoFlow Ready - Press F8 to dictate" on startup.
```

**Test:** Run main.py, press F8, speak, release F8, watch text appear in active window.

---

## Phase 2: Polish & UX

### Prompt 2.1: Configuration Manager

**Goal:** Load/save settings from config.json.

```
Create a configuration manager for EchoFlow.

REQUIREMENTS:
1. Load configuration from JSON file
2. Save configuration to JSON file
3. Use OS-appropriate config location:
   - Windows: %APPDATA%/EchoFlow/config.json
   - macOS: ~/Library/Application Support/EchoFlow/config.json
4. Create default config if file doesn't exist
5. Support dot-notation access (e.g., config.get("api.api_key"))

DEFAULT CONFIGURATION:
```json
{
  "version": "1.0.0",
  "hotkey": {
    "combination": ["ctrl", "shift", "space"],
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
    "llm_model": "llama3-8b-8192"
  },
  "ui": {
    "show_notifications": true,
    "play_sounds": false
  }
}
```

Create file: utils/config_manager.py

Include:
1. ConfigManager class with:
   - __init__(self, config_path: str = None)
   - load(self) -> dict
   - save(self, config: dict = None) -> None
   - get(self, key: str, default = None) -> Any
   - set(self, key: str, value: Any) -> None
2. main() function that loads config and prints API key location
```

---

### Prompt 2.2: System Tray Icon

**Goal:** Add system tray icon with status and menu.

```
Create a system tray module for EchoFlow.

REQUIREMENTS:
1. Use pystray library
2. Show icon in system tray (Windows taskbar / macOS menu bar)
3. Change icon based on state: idle (gray), recording (red), processing (yellow)
4. Right-click menu with: "Settings", "Quit"
5. Support notifications

ICON HANDLING:
Since we don't have icon files yet, create simple colored circles programmatically:
- Use PIL to create 64x64 colored circle images
- idle: gray (#808080)
- recording: red (#FF0000)  
- processing: yellow (#FFFF00)

Create file: ui/tray.py

Include:
1. SystemTray class with:
   - __init__(self, on_settings: Callable, on_quit: Callable)
   - set_state(self, state: str) -> None  # "idle", "recording", "processing"
   - show_notification(self, title: str, message: str) -> None
   - run(self) -> None  # Blocking, runs the tray
   - run_detached(self) -> None  # Non-blocking, runs in thread
   - stop(self) -> None
2. Helper function to create colored circle images
3. main() function demonstrating the tray with state changes

The tray should show "EchoFlow" as the tooltip.
Menu items: "Settings" (prints "Settings clicked"), "Quit" (stops tray).
```

---

### Prompt 2.3: Integrate Tray with Main

**Goal:** Update main.py to use system tray and config.

```
Update main.py to integrate the system tray and configuration manager.

REQUIREMENTS:
1. Load API key from config file (not hardcoded)
2. Show system tray icon
3. Update tray state based on pipeline state:
   - IDLE → gray icon
   - RECORDING → red icon
   - PROCESSING → yellow icon
4. Show notification on errors
5. Use hotkey from config (not hardcoded F8)
6. Add first-run check: if API key is empty, show notification asking user to set it

FLOW UPDATE:
```
[App starts]
   → Load config
   → If no API key: show notification "Please set API key in config file at {path}"
   → Start system tray
   → Register hotkey from config
   → Print "EchoFlow Ready"

[Hotkey pressed]
   → Set tray state to "recording"
   → Start audio capture

[Hotkey released]
   → Set tray state to "processing"
   → Run pipeline
   → If error: show notification, set tray to "idle"
   → If success: inject text, set tray to "idle"
```

Update file: main.py

The app should now:
1. Run with system tray visible
2. Read hotkey and API key from config
3. Update tray icon in real-time
4. Handle errors with notifications
```

---

### Prompt 2.4: Context-Aware Styling

**Goal:** Detect active application and adjust style.

```
Create a context detector that identifies the active application.

REQUIREMENTS:
1. Detect currently focused application name
2. Work on both Windows and macOS
3. Suggest appropriate style based on app

PLATFORM IMPLEMENTATIONS:
- Windows: Use pygetwindow to get active window, extract app name
- macOS: Use AppKit NSWorkspace to get frontmost application

APP-TO-STYLE MAPPING (default):
- Slack, Teams, Outlook, Gmail: "professional"
- Discord, WhatsApp, Messages: "casual"
- VS Code, Sublime, Terminal: "technical"
- Everything else: use default from config

Create file: core/context_detector.py

Include:
1. ContextDetector class with:
   - __init__(self)
   - get_active_app_name(self) -> str
   - suggest_style(self, app_name: str, app_style_map: dict) -> str
2. Cross-platform implementation (detect OS and use appropriate method)
3. main() function that prints current active app every 2 seconds

Then update main.py to:
1. Before refining, get active app name
2. If context_awareness.enabled in config, use suggested style
3. Pass app_name to refiner for potential prompt customization
```

---

### Prompt 2.5: Voice Activity Detection

**Goal:** Auto-stop recording when user stops speaking.

```
Add Voice Activity Detection (VAD) to automatically stop recording when silence is detected.

REQUIREMENTS:
1. Use simple energy-based VAD (no external model for simplicity)
2. Calculate audio energy (RMS) for each chunk
3. Track silence duration
4. If silence exceeds threshold (600ms default), trigger stop
5. This should work even if the hotkey is still held

IMPLEMENTATION:
```python
def calculate_energy(audio_chunk):
    """Calculate RMS energy of audio chunk."""
    return np.sqrt(np.mean(audio_chunk ** 2))

def is_speech(energy, threshold=0.01):
    """Returns True if energy indicates speech."""
    return energy > threshold
```

Update file: core/audio_recorder.py

Add to AudioRecorder class:
1. New parameter: silence_threshold_ms (default 600)
2. New parameter: energy_threshold (default 0.01)
3. Track silence duration during recording
4. New method: should_stop() -> bool
5. New callback: on_auto_stop (called when silence threshold exceeded)

Update main.py to:
1. Check should_stop() during recording
2. If True, trigger the same pipeline as hotkey release
3. Print "[Auto-stopped after silence]" when this happens
```

---

## Phase 3: Distribution

### Prompt 3.1: PyInstaller Packaging (Windows)

**Goal:** Create standalone .exe for Windows.

```
Create PyInstaller configuration to build EchoFlow as a Windows executable.

REQUIREMENTS:
1. Single .exe file (--onefile)
2. No console window (--windowed)
3. Include all dependencies
4. Include assets folder
5. Set application icon

Create file: build/windows/build.py

This script should:
1. Check if PyInstaller is installed
2. Create a .spec file with proper configuration
3. Run PyInstaller
4. Output to build/windows/dist/EchoFlow.exe

SPEC FILE REQUIREMENTS:
- name: "EchoFlow"
- console: False
- onefile: True
- Add hidden imports for: pynput, sounddevice, scipy
- Include data files: assets/*

Also create: build/windows/build.bat
A simple batch file that runs the build script.

Provide instructions for:
1. How to run the build
2. Where to find the output
3. How to test the built .exe
```

---

### Prompt 3.2: PyInstaller Packaging (macOS)

**Goal:** Create standalone .app for macOS.

```
Create PyInstaller configuration to build EchoFlow as a macOS application.

REQUIREMENTS:
1. Create .app bundle
2. No terminal window
3. Include all dependencies
4. Set application icon
5. Include Info.plist for permissions

Create file: build/macos/build.py

This script should:
1. Check if PyInstaller is installed
2. Create a .spec file with macOS-specific configuration
3. Run PyInstaller
4. Output to build/macos/dist/EchoFlow.app

MACOS-SPECIFIC:
- Bundle identifier: com.echoflow.app
- Request permissions in Info.plist:
  - NSMicrophoneUsageDescription: "EchoFlow needs microphone access for voice dictation"
  - NSAppleEventsUsageDescription: "EchoFlow needs automation access to type text"

Also create: build/macos/build.sh
A shell script that runs the build.

Provide instructions for:
1. How to run the build
2. How to code sign (optional)
3. How to grant permissions on first run
```

---

### Prompt 3.3: First-Run Setup Experience

**Goal:** Create a smooth onboarding for new users.

```
Create a first-run setup experience for EchoFlow.

REQUIREMENTS:
1. Detect if this is first run (no config file exists)
2. Show a simple terminal-based setup wizard
3. Ask for Groq API key
4. Test the API key is valid
5. Save to config
6. Explain the hotkey and how to use

SETUP FLOW:
```
=================================
Welcome to EchoFlow!
=================================

EchoFlow turns your voice into polished text.

Step 1: API Key Setup
---------------------
You need a Groq API key (free at console.groq.com)

Enter your Groq API key: gsk_xxxxx

[Testing API key...]
✓ API key is valid!

Step 2: Hotkey
--------------
Default hotkey: Ctrl+Shift+Space
Hold to record, release to process.

Would you like to change this? (y/n): n

Setup complete!
---------------
Press Ctrl+Shift+Space to start dictating.
EchoFlow will run in your system tray.

Starting EchoFlow...
```

Create file: ui/setup_wizard.py

Include:
1. SetupWizard class
2. Methods: run(), test_api_key(), save_config()
3. Clear terminal output formatting
4. Error handling for invalid API keys

Update main.py:
1. On startup, check if config exists
2. If not, run SetupWizard before starting main app
3. If API key is empty, run SetupWizard
```

---

## Phase 4: Advanced Features (Optional)

### Prompt 4.1: Custom Keyboard Shortcut Selector

```
Create a keyboard shortcut selector that lets users set their preferred hotkey.

REQUIREMENTS:
1. Listen for key combination when in "capture mode"
2. Support modifier keys: Ctrl, Shift, Alt, Cmd (Mac)
3. Support regular keys: letters, numbers, F1-F12
4. Validate the combination is usable
5. Save to config

Create a function capture_hotkey() that:
1. Prints "Press your desired hotkey combination..."
2. Waits for user to press keys
3. Captures the combination
4. Returns list like ["ctrl", "shift", "space"]

Add to setup wizard as optional step.
```

---

### Prompt 4.2: Clipboard Context (Reply Mode)

```
Add a "Reply Mode" feature that uses clipboard context.

REQUIREMENTS:
1. User can copy some text (e.g., a question they received)
2. Special hotkey (Ctrl+Shift+R) activates "Reply Mode"
3. User speaks their response
4. LLM uses copied text as context to craft appropriate reply

FLOW:
1. User copies "When can you send the report?"
2. User presses Ctrl+Shift+R
3. App reads clipboard
4. User speaks: "Tell them by end of day tomorrow"
5. Output: "I'll have the report to you by end of day tomorrow."

Update refiner.py to accept optional 'context' parameter.
Update the prompt template to include context when provided.
Add new hotkey registration for reply mode.
```

---

### Prompt 4.3: Local Mode (Offline)

```
Add offline mode using local models.

REQUIREMENTS:
1. Use faster-whisper for local transcription
2. Use Ollama with Llama-3.2-3B for local refinement
3. User can toggle between cloud and local mode
4. Local mode is slower but completely private

IMPLEMENTATION:
1. Add faster-whisper to requirements
2. Create LocalTranscriber class (same interface as cloud Transcriber)
3. Create LocalRefiner class using Ollama API (localhost:11434)
4. Add "mode": "cloud" | "local" to config
5. In main.py, instantiate appropriate transcriber/refiner based on mode

Note: This requires user to install Ollama and download models separately.
Provide instructions for this in a SETUP_LOCAL.md file.
```

---

## Troubleshooting Prompts

### If Audio Recording Fails

```
I'm getting this error when trying to record audio:
[PASTE ERROR HERE]

My setup:
- OS: [Windows/macOS]
- Python version: [version]
- sounddevice version: [version]

Help me debug and fix this audio recording issue.
Common causes to check:
1. No microphone connected
2. Microphone in use by another app
3. Permission not granted
4. Wrong audio device selected
```

### If Hotkey Doesn't Work

```
The global hotkey is not being detected.

My setup:
- OS: [Windows/macOS]
- Hotkey configured: [combination]
- pynput version: [version]

On macOS: Have you granted Accessibility permission to Terminal/Python?
On Windows: Is another app using this hotkey?

Help me debug the hotkey detection issue.
```

### If API Calls Fail

```
I'm getting API errors from Groq:
[PASTE ERROR HERE]

Check:
1. Is API key correct?
2. Is there internet connection?
3. Is the model name correct?
4. Has rate limit been exceeded?

Help me fix this API integration issue.
```

### If Text Injection Doesn't Work

```
The text is not being typed into the active window.

My setup:
- OS: [Windows/macOS]
- Target application: [app name]
- Using clipboard mode: [yes/no]

On macOS: Have you granted Accessibility permission?
On Windows: Is the target app running with admin privileges?

Help me debug text injection.
```

---

## Quick Reference: File Checklist

After completing all prompts, you should have:

```
echoflow/
├── main.py                      ✓ Prompt 1.5, 2.3
├── requirements.txt             ✓ Setup
├── config.json                  ✓ Prompt 2.1
│
├── core/
│   ├── __init__.py             ✓ Setup
│   ├── audio_recorder.py       ✓ Prompt 1.1, 2.5
│   ├── transcriber.py          ✓ Prompt 1.2
│   ├── refiner.py              ✓ Prompt 1.3
│   ├── text_injector.py        ✓ Prompt 1.4
│   └── context_detector.py     ✓ Prompt 2.4
│
├── ui/
│   ├── __init__.py             ✓ Setup
│   ├── tray.py                 ✓ Prompt 2.2
│   └── setup_wizard.py         ✓ Prompt 3.3
│
├── utils/
│   ├── __init__.py             ✓ Setup
│   └── config_manager.py       ✓ Prompt 2.1
│
├── assets/
│   └── (icons generated)       ✓ Prompt 2.2
│
└── build/
    ├── windows/
    │   ├── build.py            ✓ Prompt 3.1
    │   └── build.bat           ✓ Prompt 3.1
    └── macos/
        ├── build.py            ✓ Prompt 3.2
        └── build.sh            ✓ Prompt 3.2
```

---

## Recommended Build Order

| Day | Focus | Prompts | Milestone |
|-----|-------|---------|-----------|
| 1 | Environment + Audio | Setup, 1.1 | Can record audio |
| 2 | Transcription | 1.2, 1.3 | Can transcribe and refine |
| 3 | Integration | 1.4, 1.5 | Working pipeline! |
| 4 | Config + Tray | 2.1, 2.2 | Looks like real app |
| 5 | Polish | 2.3, 2.4, 2.5 | Professional quality |
| 6 | Distribution | 3.1, 3.2, 3.3 | Ready to share |

---

## Final Testing Checklist

Before considering the build complete:

- [ ] App starts without errors
- [ ] System tray icon appears
- [ ] Hotkey triggers recording
- [ ] Audio is captured correctly
- [ ] Transcription returns text
- [ ] Refinement cleans the text
- [ ] Text is injected into active window
- [ ] Config file is created and loaded
- [ ] First-run setup works
- [ ] Errors show notifications (don't crash)
- [ ] App can be quit from tray menu
- [ ] Packaged .exe/.app runs standalone

---

## Document Navigation

- **Document 1:** Master Architecture & Overview
- **Document 2:** Technical Implementation Specifications  
- **Document 3 (This):** Build Prompts & Execution Sequence

---

*End of Document 3*
