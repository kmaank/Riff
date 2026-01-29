# RIFF - Complete Technical Documentation

**Version:** 1.2.7
**Last Updated:** 2026-01-29
**Platform:** macOS (Primary), Windows/Linux (Architecture Ready)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Overview](#architecture-overview)
3. [Core Components](#core-components)
4. [Complete Workflow](#complete-workflow)
5. [Configuration System](#configuration-system)
6. [API Integration](#api-integration)
7. [Threading & Concurrency](#threading--concurrency)
8. [Error Handling & Recovery](#error-handling--recovery)
9. [Build & Deployment](#build--deployment)
10. [Performance Characteristics](#performance-characteristics)
11. [Advanced Features](#advanced-features)

---

## Executive Summary

**Riff** is a macOS voice-to-text application that enables hands-free dictation with intelligent transcription refinement. Users hold a hotkey to record, and Riff automatically transcribes, refines with AI, and injects the text into any active application.

### Key Capabilities

- **Global Hotkey Recording**: Press and hold Control (or custom key) to record audio
- **Multi-Language Support**: 3 script modes for handling English, multilingual, and original-script content
- **AI-Powered Refinement**: 6 transcription styles (clean, formal, casual, code, professional, riff)
- **Smart Text Injection**: Automatically chooses typing, pasting, or chunked pasting based on text length
- **Unlimited Recording Length**: Auto-chunks files >25MB for seamless long-form dictation
- **System Tray Integration**: Menu bar app with visual status indicators
- **Native macOS UI**: Swift-based Control Center for configuration

### Technology Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| Backend | Python 3.12 | Audio processing, API orchestration |
| Frontend | Swift/SwiftUI | Native macOS settings UI |
| Speech-to-Text | Groq Whisper Large v3 | Audio transcription (~300ms latency) |
| Text Refinement | Groq Llama 3.3 70B | Style-based text polishing |
| Audio Capture | sounddevice + numpy | 16kHz mono recording |
| Input Simulation | pynput + AppleScript | Text injection via typing/pasting |
| IPC | JSON file-based | Python ↔ Swift configuration sync |

---

## Architecture Overview

### Project Structure

```
Riff/
├── main.py                          # Application entry point (878 lines)
│   └── RiffApp class: Orchestrates all components
│
├── core/                            # Business logic modules (1,191 lines)
│   ├── audio_recorder.py            # Microphone capture + VAD (320 lines)
│   ├── transcriber.py               # Whisper API + chunking (386 lines)
│   ├── refiner.py                   # LLM-based styling (284 lines)
│   ├── text_injector.py             # Keyboard/clipboard output (130 lines)
│   └── context_detector.py          # Active app detection (71 lines)
│
├── utils/                           # Support utilities (397 lines)
│   ├── config_manager.py            # Config I/O with atomic writes (210 lines)
│   ├── logger.py                    # Redacted logging system (106 lines)
│   └── permissions.py               # macOS permission checks (81 lines)
│
├── ui/                              # Python UI components (646 lines)
│   ├── tray.py                      # System tray menu (183 lines)
│   ├── instructions.py              # Help browser (227 lines)
│   ├── onboarding.py                # Python onboarding UI (108 lines)
│   └── native_onboarding.py         # Native macOS onboarding (128 lines)
│
├── config_ui/RiffControlCenter/     # Swift UI app (1,258 lines)
│   ├── RiffControlCenterApp.swift   # App entry point
│   ├── ContentView.swift            # Main navigation layout
│   ├── SettingsManager.swift        # Config file manager
│   ├── OnboardingView.swift         # First-run wizard (5 steps)
│   ├── ScriptAndStyleView.swift     # Mode + style selection
│   ├── KeysView.swift               # Hotkey configuration
│   ├── HistoryView.swift            # Transcription history viewer
│   └── HelpView.swift               # User documentation
│
├── assets/                          # Application resources
│   ├── AppIcon.icns                 # macOS app icon
│   ├── settings_logo.png            # UI branding
│   └── tray_*.png                   # Status indicator icons
│
├── build_scripts/                   # Build automation
│   ├── build_app.sh                 # PyInstaller compilation
│   ├── build_pkg.sh                 # macOS installer
│   ├── build_dmg.sh                 # DMG creator
│   └── config_ui/build_ui.sh        # Swift UI compiler
│
├── requirements.txt                 # Python dependencies
├── Riff.spec                        # PyInstaller configuration
└── CHANGELOG.md                     # Version history
```

### Architectural Patterns

**Component Separation:**
- **Python Backend**: Handles real-time audio processing, API calls, system integration
- **Swift Frontend**: Provides native macOS UI for configuration and history
- **IPC via Files**: Shared JSON files enable loose coupling between processes

**Concurrency Model:**
- Main thread: System tray event loop (blocking)
- Hotkey thread: Global keyboard listener (pynput)
- Processing thread: Audio queue worker (daemon)
- Monitor threads: Config watcher, health checker (daemon)

**Data Flow:**
```
User Input (Hotkey)
  ↓
AudioRecorder (Microphone → WAV file)
  ↓
ProcessingThread (Background worker)
  ↓
Transcriber (Audio → Raw Text via Whisper)
  ↓
Refiner (Raw Text → Styled Text via Llama)
  ↓
TextInjector (Styled Text → Active App)
  ↓
HistoryManager (Log to history.json)
```

---

## Core Components

### 1. AudioRecorder (`core/audio_recorder.py`)

**Responsibility:** Capture microphone audio and detect speech end via Voice Activity Detection (VAD)

#### Key Features

- **Real-time capture** at 16kHz, mono (configurable)
- **Voice Activity Detection** using energy-based silence detection
- **Thread-safe state management** with locks
- **Auto-recovery system** for stuck states
- **Health monitoring** for inconsistent states

#### Configuration

```python
{
  "audio": {
    "sample_rate": 16000,        # 16kHz recommended for speech
    "channels": 1,               # Mono audio
    "silence_threshold_ms": 600, # 600ms silence = speech end
    "max_recording_seconds": 60  # Safety timeout (ignored if disabled)
  }
}
```

#### State Machine

```
IDLE (recording=False, stream=None)
  ↓ start_recording()
RECORDING (recording=True, stream=active)
  ↓ stop_recording() OR VAD silence detection
STOPPING (recording=False, stream=closing)
  ↓ save_to_file()
IDLE
```

#### Key Methods

```python
def start_recording(on_auto_stop=None) -> bool
    """
    Begin audio capture with optional VAD callback.

    Args:
        on_auto_stop: Callback invoked when silence detected

    Returns:
        True if started successfully, False if already recording
    """

def stop_recording(filename: str) -> bool
    """
    Stop capture and save to WAV file.

    Args:
        filename: Path to save audio file

    Returns:
        True if saved successfully, False on error

    Notes:
        - Concatenates audio frames from queue
        - Uses scipy.io.wavfile.write() for WAV format
        - Times out after 5 seconds if stream doesn't close
    """

def health_check() -> (bool, list)
    """
    Detect inconsistent states (zombie flags, orphaned streams).

    Returns:
        (is_healthy, list_of_issues)

    Issues detected:
        - recording=True but stream=None (stream died)
        - recording=True but stream.active=False (stuck flag)
        - recording=False but stream exists (orphaned stream)
    """

def auto_recover()
    """
    Force cleanup from stuck states.
    Closes streams, resets flags, clears buffers.
    """
```

#### VAD Implementation

Uses energy-based silence detection:

```python
def _is_silence(audio_chunk):
    energy = np.sqrt(np.mean(audio_chunk**2))
    return energy < SILENCE_THRESHOLD

# In audio callback:
if _is_silence(current_chunk):
    consecutive_silence_frames += 1
    if consecutive_silence_frames >= SILENCE_FRAME_THRESHOLD:
        trigger_auto_stop()
```

---

### 2. Transcriber (`core/transcriber.py`)

**Responsibility:** Convert audio files to text using Groq Whisper API with multi-language support

#### Key Features

- **Groq Whisper Large v3** API integration
- **Automatic chunking** for files >25MB (10-minute chunks)
- **3 Script Modes** for language handling
- **Hallucination prevention** via constrained prompts + confidence scoring
- **Average latency:** 300ms for typical recordings

#### Script Modes

| Mode | Description | Use Case | Example |
|------|-------------|----------|---------|
| `english_mixed` | Romanize non-English, keep English | Multilingual with English preference | "I need a café" → "I need a café" |
| `english_translated` | Translate all to English | English-only output | "मुझे कॉफी चाहिए" → "I need coffee" |
| `original_mixed` | Keep original scripts | Preserve native languages | "मुझे कॉफी चाहिए" → "मुझे कॉफी चाहिए" |

#### Anti-Hallucination Strategy

**Problem:** Whisper sometimes generates full paragraphs from short phrases (e.g., "Gantt chart" → 3 paragraphs about project management)

**Solution:**
1. **Constrained prompts:**
   ```python
   "Transcribe exactly what is spoken, word for word.
    Do not add explanations, context, or extra words.
    Output only the verbatim speech."
   ```

2. **Confidence scoring:**
   ```python
   response_format: "verbose_json"  # Get segment-level scores
   temperature: 0.0                  # Deterministic output

   # Reject if avg no_speech_prob > 0.8
   if avg_no_speech_prob > 0.8:
       return ""  # Likely hallucination
   ```

3. **Regex filtering** (conservative, only removes obvious patterns):
   - Repetitive segments (>3 identical sentences)
   - Common hallucination phrases ("Thank you for watching")

#### Large File Handling

For files >25MB (Groq limit):

```python
def _transcribe_chunked(filepath):
    """
    Split audio into 10-minute chunks, transcribe each, concatenate.

    Process:
        1. Read WAV file with scipy.io.wavfile
        2. Split audio_data into chunk_size_samples segments
        3. Write each chunk to temp file
        4. Transcribe each chunk via _transcribe_single_file()
        5. Concatenate results with space separator
        6. Clean up temp files
    """
    chunks = _split_audio_file(filepath)  # Returns list of temp paths
    transcripts = [_transcribe_single_file(chunk) for chunk in chunks]
    return " ".join(transcripts)
```

#### Key Methods

```python
def transcribe_file(filepath: str) -> str
    """
    Main entry point. Auto-detects chunking need.

    Returns:
        Transcribed text (post-processed by script mode)
    """

def _transcribe_single_file(filepath: str) -> str
    """
    Single API call to Groq Whisper.

    API Parameters:
        - model: whisper-large-v3
        - response_format: verbose_json
        - prompt: Script mode-specific constraint
        - temperature: 0.0
    """

def _romanize_text(text: str) -> str
    """
    Convert non-Latin scripts to romanized form.
    Used in english_mixed mode.
    """

def _translate_to_english(text: str) -> str
    """
    Full translation to English via Groq LLM.
    Used in english_translated mode.
    """
```

---

### 3. Refiner (`core/refiner.py`)

**Responsibility:** Polish raw transcripts using style-specific LLM prompts

#### Supported Styles

| Style | Description | Transformations | Use Case |
|-------|-------------|-----------------|----------|
| `clean` | Remove fillers, fix grammar, preserve tone | um/uh → removed, capitalization, punctuation | General dictation |
| `formal` | Professional business style | All fillers removed, formal tone, proper structure | Emails, reports |
| `professional` | Alias for formal | Same as formal | Business communication |
| `casual` | Light cleaning | Keep personality, minimal changes | Chats, notes |
| `code` | Format as code comments/variables | snake_case, code-friendly | Developer documentation |
| `riff` | Conversational AI mode | Treat as conversation with AI | Assistant interactions |

#### Critical Anti-Answer Preamble

**Problem:** If user dictates "What is the capital of France?", LLM might answer "Paris" instead of outputting the question.

**Solution:**
```python
DICTATION_PREAMBLE = """You are a DICTATION TRANSCRIPTION editor, NOT a chatbot.
The user is DICTATING text they want to type. They are NOT talking to you.

NEVER answer questions in the transcription - just clean them up and output them.
NEVER respond as if they're talking to you.
NEVER add explanations, context, or interpretations.

Your ONLY job: Fix grammar, remove filler words, and format the text cleanly.
Output ONLY the cleaned dictation text."""
```

**Exception:** `riff` style DOES NOT use this preamble (user IS talking to AI)

#### Style Prompt Examples

**Clean Style:**
```
Remove filler words (um, uh, like), fix grammar, add punctuation.
Preserve the speaker's tone and meaning exactly.
Output only the cleaned text, nothing else.
```

**Code Style:**
```
Format as code comments or variable names.
Use snake_case for variables, proper comment syntax.
Remove conversational elements, keep technical precision.
```

#### Key Methods

```python
def refine(text: str, style: str, prompt: str = None) -> str
    """
    Apply style-specific refinement via Groq Llama API.

    Args:
        text: Raw transcript
        style: One of (clean, formal, casual, code, riff)
        prompt: Optional custom system prompt override

    Returns:
        Refined text (or original if API fails)

    Fallback behavior:
        - If API error: Return original text
        - If empty response: Return original text
        - Logs warning but never crashes
    """

def _clean_llm_artifacts(text: str, style: str) -> str
    """
    Remove common LLM preambles/artifacts.

    Removes patterns like:
        - "Here is the cleaned text:"
        - "Refined version:"
        - Markdown code blocks (unless style=code)
    """
```

---

### 4. TextInjector (`core/text_injector.py`)

**Responsibility:** Type or paste text into the active application

#### Injection Strategies

Automatically selects best method based on text length:

| Length | Strategy | Method | Latency | Reliability |
|--------|----------|--------|---------|-------------|
| <300 chars | **Direct Typing** | pynput character-by-character | ~50ms | High |
| 300-5000 chars | **Clipboard Paste** | pyperclip + Cmd+V | ~50ms | High |
| >5000 chars | **Chunked Paste** | 4000-char chunks + sequential paste | ~300ms | High |

#### Why Chunked Pasting?

**Problem:** Large texts (>5000 chars) truncate when pasted due to macOS clipboard buffer limits.

**Solution:**
```python
def inject_via_chunked_clipboard(text, chunk_size=4000):
    """
    Split text into chunks, paste sequentially.

    Process:
        1. Split text into 4000-char chunks
        2. For each chunk:
            a. Copy to clipboard
            b. Wait 0.15s (clipboard update delay)
            c. Paste with Cmd+V (AppleScript or pynput)
            d. Wait 0.3s (app processing delay)
        3. Restore original clipboard
    """
```

#### Platform-Specific Implementation

**macOS:**
```python
# Primary: AppleScript (most reliable)
subprocess.run(["osascript", "-e",
    'tell application "System Events" to keystroke "v" using command down'])

# Fallback: pynput (if AppleScript fails)
with keyboard.pressed(Key.cmd):
    keyboard.press('v')
    keyboard.release('v')
```

**Windows:**
```python
with keyboard.pressed(Key.ctrl):
    keyboard.press('v')
    keyboard.release('v')
```

#### Key Methods

```python
def inject(text: str)
    """
    Smart routing to optimal injection strategy.

    Decision tree:
        - len(text) > 5000: chunked paste
        - use_clipboard OR len(text) > 300: single paste
        - else: direct typing
    """

def type_text(text: str)
    """
    Character-by-character typing via pynput.
    Preserves capitalization, special characters.
    """

def inject_via_clipboard(text: str)
    """
    Single clipboard paste operation.
    Saves/restores original clipboard.
    """

def _do_paste()
    """
    Platform-specific paste implementation.
    Tries AppleScript first (macOS), falls back to pynput.
    """
```

---

### 5. ContextDetector (`core/context_detector.py`)

**Responsibility:** Detect active application for context-aware features (future use)

#### Implementation

**macOS:**
```python
from AppKit import NSWorkspace

def get_active_app_name():
    workspace = NSWorkspace.sharedWorkspace()
    app = workspace.frontmostApplication()
    return app.localizedName()  # e.g., "Slack", "Visual Studio Code"
```

**Windows:**
```python
import win32gui
import psutil

def get_active_app_name():
    hwnd = win32gui.GetForegroundWindow()
    _, pid = win32process.GetWindowThreadProcessId(hwnd)
    return psutil.Process(pid).name()
```

#### Potential Use Cases (Not Yet Implemented)

- Auto-select style based on active app
- App-specific hotkey configurations
- Context-aware refinement prompts

---

## Complete Workflow

### Application Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. APP LAUNCH (main.py)                                         │
└─────────────────────────────────────────────────────────────────┘
    ↓
main()
    ├── ConfigManager().load() → Load config.json
    ├── Check API key
    │   └── If missing: Launch RiffControlCenter for onboarding
    │       └── Wait for API key entry
    ├── RiffApp.__init__()
    │   ├── Initialize AudioRecorder (16kHz mono)
    │   ├── Initialize Transcriber (Groq Whisper)
    │   ├── Initialize Refiner (Groq Llama)
    │   ├── Initialize TextInjector
    │   ├── Initialize ProcessingThread (daemon)
    │   └── Initialize SystemTray
    ├── Start threads:
    │   ├── Hotkey listener (pynput.Listener)
    │   ├── Config monitor (30s polling)
    │   ├── Health monitor (30s checks)
    │   └── Processing thread (audio queue worker)
    └── app.start() → tray.run() [BLOCKING]

┌─────────────────────────────────────────────────────────────────┐
│ 2. USER PRESSES HOTKEY (e.g., Left Control)                     │
└─────────────────────────────────────────────────────────────────┘
    ↓
on_press(key)
    ├── Validate: Is recorder healthy?
    ├── Validate: Not already processing?
    ├── Check: Shift key held? (latch mode)
    ├── recorder.start_recording()
    │   └── Open sounddevice InputStream
    │   └── Begin queueing audio frames
    ├── Update tray icon: WHITE → RED (recording)
    └── Log: [Hotkey] Started recording

┌─────────────────────────────────────────────────────────────────┐
│ 3. USER RELEASES HOTKEY (or VAD detects silence)                │
└─────────────────────────────────────────────────────────────────┘
    ↓
on_release(key) OR vad_callback()
    └── RiffApp._stop_and_process()
        ├── Update tray icon: RED → YELLOW (processing)
        ├── Spawn background thread: _do_stop_and_queue()
        │   ├── filename = generate_temp_filename()
        │   ├── recorder.stop_recording(filename)
        │   │   ├── Close audio stream (5s timeout)
        │   │   ├── Concatenate frames from queue
        │   │   ├── Save to WAV file (scipy.io.wavfile)
        │   │   └── Return success status
        │   └── audio_queue.put(filename)
        └── Log: [Hotkey] Queued audio for processing

┌─────────────────────────────────────────────────────────────────┐
│ 4. BACKGROUND PROCESSING (ProcessingThread)                     │
└─────────────────────────────────────────────────────────────────┘
    ↓
ProcessingThread.run() [Infinite loop]
    └── audio_path = audio_queue.get() [BLOCKS until available]
        ↓
        _process_audio_file(audio_path)
            │
            ├── [VALIDATION]
            │   ├── File exists?
            │   ├── File size >= 8KB (0.5 sec audio)?
            │   └── If fails: Notify "Recording too short", return
            │
            ├── [TRANSCRIPTION]
            │   └── raw_text = transcriber.transcribe_file(audio_path)
            │       ├── Check file size: >25MB?
            │       │   ├── YES: _transcribe_chunked() (10-min chunks)
            │       │   └── NO: _transcribe_single_file()
            │       ├── Send to Groq Whisper API
            │       │   └── API params: {
            │       │       model: "whisper-large-v3",
            │       │       response_format: "verbose_json",
            │       │       temperature: 0.0,
            │       │       prompt: script_mode_prompt
            │       │     }
            │       ├── Get response with confidence scores
            │       ├── Check hallucination: avg_no_speech_prob > 0.8?
            │       │   └── If YES: Return "" (reject)
            │       ├── Apply regex filters (conservative)
            │       └── Post-process by script_mode:
            │           ├── english_mixed: _romanize_text()
            │           ├── english_translated: _translate_to_english()
            │           └── original_mixed: Return as-is
            │
            ├── [REFINEMENT]
            │   └── refined_text = refiner.refine(raw_text, active_style)
            │       ├── Load style-specific prompt
            │       ├── Add DICTATION_PREAMBLE (unless style=riff)
            │       ├── Send to Groq Llama API
            │       │   └── API params: {
            │       │       model: "llama-3.3-70b-versatile",
            │       │       temperature: 0.3,
            │       │       messages: [system_prompt, user_message]
            │       │     }
            │       ├── Clean LLM artifacts ("Here is the text:")
            │       └── Fallback to raw_text if API fails
            │
            ├── [HISTORY LOGGING]
            │   └── HistoryManager.add_entry({
            │       timestamp: ISO8601,
            │       original: raw_text,
            │       refined: refined_text,
            │       style: active_style,
            │       script_mode: active_script_mode
            │     })
            │     └── Write to ~/Library/Application Support/Riff/history.json
            │
            └── [TEXT INJECTION]
                └── injector.inject(refined_text)
                    ├── Select strategy by length:
                    │   ├── >5000: inject_via_chunked_clipboard()
                    │   ├── >300: inject_via_clipboard()
                    │   └── <300: type_text()
                    ├── Execute injection
                    └── Restore original clipboard

            ↓
            Show notification: "Riff Complete (clean)"
            Update tray icon: YELLOW → GREEN (done, 2s)
            Update tray icon: GREEN → WHITE (idle)
            Log: [ProcessingThread] Completed successfully

┌─────────────────────────────────────────────────────────────────┐
│ 5. RETURN TO IDLE STATE                                          │
└─────────────────────────────────────────────────────────────────┘
    ↓
    Ready for next hotkey press
    Background threads continue monitoring
```

---

## Configuration System

### Configuration File (`config.json`)

**Location:**
- **macOS:** `~/Library/Application Support/Riff/config.json`
- **Windows:** `%APPDATA%/Riff/config.json`
- **Linux:** `~/.config/Riff/config.json`

**Structure:**
```json
{
  "version": "1.0.0",

  "hotkey": {
    "combination": "ctrl_l",
    "latch_modifier": "shift"
  },

  "audio": {
    "sample_rate": 16000,
    "channels": 1,
    "silence_threshold_ms": 600,
    "max_recording_seconds": 60,
    "device_index": null
  },

  "style": {
    "active_style": "clean"
  },

  "script_mode": {
    "active_mode": "english_mixed"
  },

  "api": {
    "api_key": "gsk_...",
    "whisper_model": "whisper-large-v3",
    "llm_model": "llama-3.3-70b-versatile",
    "base_url": "https://api.groq.com/openai/v1"
  },

  "ui": {
    "show_notifications": true,
    "play_sounds": false,
    "theme": "system"
  },

  "onboarding_completed": true
}
```

### Atomic Configuration Updates

**Problem:** Config file corruption if app crashes during write

**Solution:** Write-then-replace pattern
```python
def save():
    tmp_path = config_path + ".tmp"
    try:
        with open(tmp_path, 'w') as f:
            json.dump(config, f, indent=2)
            f.flush()
            os.fsync(f.fileno())  # Force OS write to disk

        os.replace(tmp_path, config_path)  # Atomic rename
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
```

### Configuration Monitoring

Python backend polls config file every 2 seconds:

```python
def monitor_config():
    """
    Daemon thread that watches config.json for changes.

    Actions on change detection:
        - Reload configuration
        - Restart hotkey listener (if hotkey changed)
        - Update audio settings (if audio config changed)
        - Log configuration update
    """
    while True:
        current_mtime = os.path.getmtime(config_path)
        if current_mtime > last_mtime:
            config_manager.reload()
            apply_config_changes()
            last_mtime = current_mtime
        time.sleep(2)
```

### Nested Configuration Access

ConfigManager supports dot notation for nested keys:

```python
api_key = config.get("api.api_key")  # Instead of config["api"]["api_key"]
config.set("style.active_style", "professional")
hotkey = config.get("hotkey.combination", default="ctrl_l")
```

---

## API Integration

### Groq API

**Provider:** Groq Inc. (https://groq.com)
**Endpoint:** `https://api.groq.com/openai/v1/`
**Authentication:** Bearer token (API key in config)

#### 1. Speech-to-Text (Whisper)

**Model:** `whisper-large-v3`
**Endpoint:** `/audio/transcriptions`
**Method:** POST (multipart/form-data)

**Request:**
```python
files = {"file": ("audio.wav", open(filepath, "rb"))}
data = {
    "model": "whisper-large-v3",
    "response_format": "verbose_json",  # Get confidence scores
    "temperature": 0.0,                  # Deterministic
    "prompt": script_mode_prompt         # Constraint prompt
}
response = groq_client.audio.transcriptions.create(**data)
```

**Response (verbose_json):**
```json
{
  "text": "This is the transcribed text.",
  "segments": [
    {
      "start": 0.0,
      "end": 2.5,
      "text": "This is the",
      "no_speech_prob": 0.01
    },
    {
      "start": 2.5,
      "end": 4.0,
      "text": " transcribed text.",
      "no_speech_prob": 0.02
    }
  ]
}
```

**Performance:**
- **Latency:** ~300ms for 5-second audio
- **File size limit:** 25MB
- **Rate limit:** 30 requests/minute (free tier)

#### 2. Text Refinement (Llama)

**Model:** `llama-3.3-70b-versatile`
**Endpoint:** `/chat/completions`
**Method:** POST (application/json)

**Request:**
```python
response = groq_client.chat.completions.create(
    model="llama-3.3-70b-versatile",
    messages=[
        {"role": "system", "content": style_prompt + DICTATION_PREAMBLE},
        {"role": "user", "content": raw_text}
    ],
    temperature=0.3,
    max_tokens=2000
)
refined_text = response.choices[0].message.content
```

**Performance:**
- **Latency:** ~200ms for typical transcript
- **Rate limit:** 30 requests/minute (free tier)
- **Cost:** ~$0.05/1M tokens

#### Error Handling

**Retry Logic:**
```python
MAX_RETRIES = 3
RETRY_DELAY = 2  # seconds

for attempt in range(MAX_RETRIES):
    try:
        response = api_call()
        return response
    except Exception as e:
        if attempt < MAX_RETRIES - 1:
            time.sleep(RETRY_DELAY * (attempt + 1))
            continue
        else:
            logging.error(f"API failed after {MAX_RETRIES} retries: {e}")
            return fallback_value
```

**Fallback Behavior:**
- **Transcription fails:** Return empty string, notify user
- **Refinement fails:** Return raw transcript, notify "Refinement Failed"
- **Never crash** - Always degrade gracefully

---

## Threading & Concurrency

### Thread Architecture

```
Main Thread (Blocking)
    └── pystray.run() - System tray event loop

Hotkey Listener Thread (pynput)
    ├── Global keyboard monitoring
    └── Triggers: on_press() / on_release()

Processing Thread (Daemon)
    ├── Infinite loop: audio_queue.get()
    ├── Transcription (I/O-bound, Groq API)
    ├── Refinement (I/O-bound, Groq API)
    └── Text injection (CPU-bound, fast)

Config Monitor Thread (Daemon)
    ├── Poll config.json every 2 seconds
    └── Trigger: reload_config()

Health Monitor Thread (Daemon)
    ├── Check recorder.health_check() every 30 seconds
    ├── Detect: Stuck states, zombie flags
    └── Trigger: auto_recover()

Watchdog Thread (Daemon)
    ├── Timeout detection for long-running operations
    └── Trigger: force_reset() if processing exceeds threshold
```

### Thread-Safe Patterns

#### 1. State Locks

```python
class RiffApp:
    def __init__(self):
        self._state_lock = threading.Lock()
        self._is_processing = False

    def set_processing(self, value):
        with self._state_lock:
            self._is_processing = value  # Atomic update

class AudioRecorder:
    def __init__(self):
        self._lock = threading.Lock()
        self.recording = False

    def start_recording(self):
        with self._lock:
            if self.recording:
                return False  # Already recording
            self.recording = True
```

#### 2. Queue-Based Communication

```python
# Thread-safe queue for audio files
audio_queue = queue.Queue()

# Producer (hotkey thread)
def on_release():
    filename = recorder.stop_recording()
    audio_queue.put(filename)  # Thread-safe

# Consumer (processing thread)
def run():
    while True:
        audio_path = audio_queue.get()  # Blocks until item available
        process_audio_file(audio_path)
```

#### 3. Daemon Threads

All background threads are marked as daemon to ensure clean shutdown:

```python
processing_thread = threading.Thread(target=process_audio, daemon=True)
config_monitor = threading.Thread(target=monitor_config, daemon=True)
health_monitor = threading.Thread(target=health_check, daemon=True)
```

**Benefit:** On `sys.exit()` or `quit()`, daemon threads terminate automatically

---

## Error Handling & Recovery

### 1. Recorder Health Monitoring

**Problem:** AudioRecorder can enter inconsistent states (zombie flags, orphaned streams)

**Detection:**
```python
def health_check():
    issues = []

    # Case 1: Flag says recording, but no stream
    if self.recording and self.stream is None:
        issues.append("recording=True but stream=None")

    # Case 2: Flag says recording, but stream inactive
    if self.recording and self.stream and not self.stream.active:
        issues.append("recording=True but stream.active=False")

    # Case 3: Flag says idle, but stream exists
    if not self.recording and self.stream and self.stream.active:
        issues.append("recording=False but stream exists")

    return (len(issues) == 0, issues)
```

**Recovery:**
```python
def auto_recover():
    logging.warning("Attempting auto-recovery")

    # Force close any streams
    if self.stream:
        try:
            self.stream.close()
        except:
            pass

    # Reset all flags
    self.recording = False
    self.stream = None
    self.audio_frames.clear()

    logging.info("Auto-recovery complete")
```

### 2. Watchdog Timeout

**Problem:** Processing thread might hang on API calls or file I/O

**Implementation:**
```python
WATCHDOG_TIMEOUT = 120  # seconds

def watchdog_monitor():
    while True:
        with state_lock:
            if is_processing:
                elapsed = time.time() - processing_start_time
                if elapsed > WATCHDOG_TIMEOUT:
                    logging.error("Watchdog timeout exceeded!")
                    force_reset_state()
        time.sleep(10)
```

### 3. API Failure Handling

**Transcription Failure:**
```python
try:
    transcript = transcriber.transcribe_file(audio_path)
except Exception as e:
    logging.error(f"Transcription failed: {e}")
    notify_user("Transcription Failed")
    return  # Skip this recording
```

**Refinement Failure:**
```python
try:
    refined = refiner.refine(transcript, style)
except Exception as e:
    logging.warning(f"Refinement failed: {e}")
    refined = transcript  # Fallback to raw transcript
    notify_user("Refinement Failed - Using Raw Transcript")
```

### 4. File Size Validation

**Problem:** Very short recordings (<0.5 sec) are usually accidental

**Validation:**
```python
MIN_FILE_SIZE = 8000  # bytes (~0.5 sec at 16kHz)

def _process_audio_file(audio_path):
    file_size = os.path.getsize(audio_path)
    if file_size < MIN_FILE_SIZE:
        logging.info("Recording too short, discarding")
        notify_user("Recording Too Short")
        return
```

### 5. State Reset on Error

On any critical error, force reset to idle state:

```python
def force_reset_state():
    recorder.auto_recover()
    set_processing(False)
    tray.set_state("idle")
    audio_queue.queue.clear()
    logging.info("State force reset complete")
```

---

## Build & Deployment

### macOS Build Process

#### Step 1: Build Swift UI

```bash
#!/bin/bash
# build_scripts/config_ui/build_ui.sh

cd config_ui
swiftc -o RiffControlCenter \
    RiffControlCenterApp.swift \
    ContentView.swift \
    SettingsManager.swift \
    OnboardingView.swift \
    ScriptAndStyleView.swift \
    KeysView.swift \
    HistoryView.swift \
    HelpView.swift \
    -framework SwiftUI \
    -framework AppKit

# Create app bundle
mkdir -p build/RiffControlCenter.app/Contents/{MacOS,Resources}
mv RiffControlCenter build/RiffControlCenter.app/Contents/MacOS/
cp Info.plist build/RiffControlCenter.app/Contents/
cp ../assets/AppIcon.icns build/RiffControlCenter.app/Contents/Resources/
```

#### Step 2: Build Python App

```bash
#!/bin/bash
# build_scripts/build_app.sh

pyinstaller --noconfirm Riff.spec
```

**Riff.spec Configuration:**
```python
# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('assets/*', 'assets'),
        ('config_ui/build/RiffControlCenter.app', 'config_ui/RiffControlCenter.app')
    ],
    hiddenimports=[
        'pystray',
        'PIL',
        'pynput',
        'groq',
        'sounddevice',
        'numpy',
        'scipy'
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='Riff',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch='arm64',
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='Riff',
)

app = BUNDLE(
    coll,
    name='Riff.app',
    icon='assets/AppIcon.icns',
    bundle_identifier='com.riff.app',
    info_plist={
        'NSMicrophoneUsageDescription': 'Riff needs microphone access for voice recording.',
        'NSAppleEventsUsageDescription': 'Riff needs to send keystrokes to inject transcribed text.',
        'NSAccessibilityUsageDescription': 'Riff needs accessibility access to type text in other apps.',
        'LSUIElement': True,  # Menu bar app (no Dock icon)
        'CFBundleShortVersionString': '1.2.7',
        'CFBundleVersion': '1.2.7',
    },
)
```

#### Step 3: Create DMG

```bash
#!/bin/bash
# build_scripts/build_dmg.sh

# Create DMG template
hdiutil create -volname "Riff" -srcfolder dist/Riff.app -ov -format UDZO Riff.dmg

# Output: Riff.dmg (drag-to-install)
```

### Distribution Methods

**1. Direct App Bundle**
- File: `Riff.app`
- User action: Drag to `/Applications`
- Size: ~80MB (includes Python runtime, dependencies)

**2. DMG Installer**
- File: `Riff.dmg`
- User action: Mount, drag to Applications
- Size: ~40MB (compressed)

**3. PKG Installer**
- File: `Riff.pkg`
- User action: Run installer
- Installs to: `/Applications/Riff.app`

---

## Performance Characteristics

### Latency Breakdown

**End-to-End Flow (5-second recording):**

| Stage | Duration | Notes |
|-------|----------|-------|
| Hotkey detection | <10ms | pynput global listener |
| Audio stream start | <50ms | sounddevice initialization |
| Recording (variable) | 5000ms | User speech duration |
| VAD silence detection | <100ms | Energy-based threshold |
| Audio stream stop | <50ms | Stream closure + WAV write |
| File validation | <10ms | Size check |
| Transcription API | ~300ms | Groq Whisper Large v3 |
| Script mode processing | ~50ms | Romanization/translation |
| Refinement API | ~200ms | Groq Llama 3.3 70B |
| Text injection | <50ms | Clipboard paste or typing |
| **Total (excluding speech)** | **~800ms** | API latency dominates |
| **User-perceived time** | **5-7 seconds** | Speech + processing |

### Resource Usage

**Memory:**
- Base: ~150MB (Python runtime + dependencies)
- During recording: +10MB (audio buffer)
- During processing: +20MB (API response buffers)
- **Peak:** ~180MB

**CPU:**
- Idle: <1% (monitoring threads)
- Recording: ~5% (audio capture + VAD)
- Processing: ~15% (transcription chunking, text processing)

**Network:**
- Transcription: ~1MB upload (5-sec audio as WAV)
- Refinement: ~5KB upload/download (text payloads)

### API Performance

**Groq Whisper:**
- **Latency:** 200-400ms (avg 300ms)
- **Throughput:** ~20 requests/min (rate limit)
- **File size limit:** 25MB

**Groq Llama:**
- **Latency:** 150-300ms (avg 200ms)
- **Throughput:** ~30 requests/min (rate limit)
- **Token limit:** 8K context, 2K generation

---

## Advanced Features

### 1. Latch Mode

**Purpose:** Continuous recording without holding hotkey

**Activation:** Hold Shift while pressing hotkey

**Behavior:**
```python
def on_press(key):
    if key == configured_hotkey:
        is_latched = keyboard.is_pressed(Key.shift)
        if is_latched:
            start_recording()
            # Continue until hotkey pressed again
```

**Deactivation:** Press hotkey again (without Shift)

### 2. Auto-Stop on Silence

**Purpose:** Hands-free recording end

**Implementation:**
```python
def start_recording(on_auto_stop=None):
    self.on_auto_stop = on_auto_stop
    # Enable VAD in audio callback

def audio_callback(indata):
    if _is_silence(indata):
        consecutive_silence_frames += 1
        if consecutive_silence_frames >= threshold:
            threading.Thread(target=on_auto_stop).start()
```

**Configuration:**
```json
{
  "audio": {
    "silence_threshold_ms": 600  // 600ms silence triggers stop
  }
}
```

### 3. History Tracking

**Purpose:** Review past transcriptions

**Storage:** `~/Library/Application Support/Riff/history.json`

**Format:**
```json
[
  {
    "timestamp": "2026-01-29T14:22:00.123456",
    "original": "um can you help me with this like now",
    "refined": "Can you help me with this now?",
    "style": "clean",
    "script_mode": "english_mixed",
    "audio_duration": 3.5,
    "file_size": 56000
  }
]
```

**Retention:** Last 50 entries (auto-pruned)

**UI:** Accessible via RiffControlCenter → History tab

### 4. Script Mode System

**Purpose:** Handle multilingual dictation

**Modes:**

1. **english_mixed:**
   - Keep English words as-is
   - Romanize non-Latin scripts (हिंदी → Hindi)
   - Use case: English-dominant with foreign words

2. **english_translated:**
   - Translate all to English
   - Use case: English-only workflows

3. **original_mixed:**
   - Preserve all original scripts
   - Use case: Native language documentation

**Implementation:**
```python
def transcribe_file(filepath):
    raw = _call_whisper_api(filepath)

    if script_mode == "english_mixed":
        return _romanize_text(raw)
    elif script_mode == "english_translated":
        return _translate_to_english(raw)
    else:
        return raw
```

### 5. Custom Styles

**Purpose:** User-defined refinement prompts

**Configuration:**
```json
{
  "style": {
    "active_style": "custom",
    "custom_prompt": "Format as bullet points with technical terminology"
  }
}
```

**Implementation:**
```python
def refine(text, style, custom_prompt=None):
    if style == "custom" and custom_prompt:
        system_prompt = custom_prompt
    else:
        system_prompt = STYLE_PROMPTS[style]
```

---

## Troubleshooting

### Common Issues

#### 1. "Recording Too Short"

**Cause:** Audio file <0.5 seconds

**Solutions:**
- Hold hotkey longer
- Check microphone input level
- Reduce `silence_threshold_ms` in config

#### 2. Transcription Empty

**Possible Causes:**
- No speech detected (background noise only)
- Hallucination rejected (high no_speech_prob)
- API key invalid

**Debug Steps:**
```bash
# Check logs
tail -f ~/Documents/Riff/debug.log

# Look for:
[Transcriber] High no_speech probability (0.85), likely hallucination
[Transcriber] API error: Invalid API key
```

#### 3. Text Not Injecting

**Possible Causes:**
- Missing Accessibility permission
- Target app doesn't accept paste
- Clipboard interference

**Solutions:**
```bash
# Check permissions
System Settings → Privacy & Security → Accessibility → Riff (✓)

# Try direct typing instead
config["injector"]["use_clipboard"] = False
```

#### 4. Recorder Stuck

**Symptoms:** Red tray icon persists after release

**Auto-Recovery:**
- Health monitor detects in ~30 seconds
- Auto-recovery attempts cleanup

**Manual Recovery:**
```bash
# Force quit and restart
pkill -9 Riff
open /Applications/Riff.app
```

---

## Security & Privacy

### Data Handling

**Audio Files:**
- Stored temporarily in: `/tmp/riff_XXXXXX.wav`
- Deleted after processing
- Never uploaded permanently

**Transcripts:**
- Sent to Groq API for processing
- Not stored by Groq (per API terms)
- Logged locally in `history.json` (last 50 entries)

**API Keys:**
- Stored in: `~/Library/Application Support/Riff/config.json`
- File permissions: 600 (user-only read/write)
- Redacted in logs: `gsk_REDACTED`

### Permissions Required

**macOS Permissions:**
1. **Microphone:** Audio capture
2. **Accessibility:** Keyboard simulation
3. **Input Monitoring:** Global hotkey detection

**How to Grant:**
```
System Settings → Privacy & Security → [Permission Type] → Add Riff
```

---

## Future Enhancements

### Planned Features

1. **Local Whisper Option**: Offline transcription via whisper.cpp
2. **Custom Hotkeys**: Per-app hotkey configurations
3. **Voice Commands**: "Stop recording", "Delete that", "Undo"
4. **Multi-Hotkey Support**: Different hotkeys for different styles
5. **Transcription Editing**: In-app editor before injection
6. **Cloud Sync**: Sync config across devices
7. **Windows/Linux Support**: Full cross-platform release

---

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed release notes.

---

## Support

**Issues:** https://github.com/anthropics/claude-code/issues
**Documentation:** This file (DOCUMENTATION.md)

---

**End of Documentation**
