# EchoFlow Desktop: Master Architecture Document

## Document 1 of 3 | Version 1.0

---

## 1. Executive Summary

**Product Name:** EchoFlow  
**Tagline:** "Speak Messy. Type Perfect."  
**Platforms:** Windows 10/11, macOS 12+  
**Language:** Python 3.11+  
**Architecture:** Desktop system tray application with cloud AI backend

### What We're Building

A desktop application that:
1. Runs silently in the system tray
2. Activates via global hotkey (e.g., Ctrl+Shift+Space)
3. Records user's voice
4. Transcribes speech to text using Groq Whisper API
5. Refines text using Groq Llama-3 (removes filler words, fixes grammar, applies style)
6. Types the polished text directly into ANY active application

### Why This Beats Competitors

| Wispr Flow | EchoFlow |
|------------|----------|
| $8-10/month | Free / $5/month |
| macOS only | Windows + macOS |
| Cloud only | Local mode option (Phase 2) |
| Fixed behavior | Custom style prompts |
| Closed source | Open for customization |

---

## 2. Core User Experience

### The "Happy Path" (Primary Flow)

```
User is typing in Slack
        │
        ▼
User holds [Ctrl+Shift+Space]
        │
        ▼
┌─────────────────────────────┐
│  Visual: Tray icon turns 🔴  │
│  Audio: Optional beep       │
│  Haptic: None (desktop)     │
└─────────────────────────────┘
        │
        ▼
User speaks: "Hey can you uh send me that report 
             thing from yesterday I think it was 
             the Q3 one or something"
        │
        ▼
User releases key OR silence detected (600ms)
        │
        ▼
┌─────────────────────────────┐
│  Visual: Tray icon turns 🟡  │
│  (Processing)               │
└─────────────────────────────┘
        │
        ▼
Text typed into Slack: "Hey, can you send me 
the Q3 report from yesterday?"
        │
        ▼
┌─────────────────────────────┐
│  Visual: Tray icon turns ⚪  │
│  (Ready)                    │
└─────────────────────────────┘
```

### Latency Targets

| Stage | Target | Max Acceptable |
|-------|--------|----------------|
| Hotkey detection | <10ms | 50ms |
| Audio capture start | <50ms | 100ms |
| VAD silence detection | <100ms | 200ms |
| Transcription (Groq) | <300ms | 500ms |
| LLM refinement (Groq) | <200ms | 400ms |
| Text injection | <50ms | 100ms |
| **Total end-to-end** | **<700ms** | **1200ms** |

---

## 3. System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        ECHOFLOW DESKTOP                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   HOTKEY     │───▶│    AUDIO     │───▶│     VAD      │      │
│  │   LISTENER   │    │   RECORDER   │    │   (Silero)   │      │
│  │   (pynput)   │    │ (sounddevice)│    │              │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│                                                 │               │
│                                                 ▼               │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │    TEXT      │◀───│     LLM      │◀───│     ASR      │      │
│  │   INJECTOR   │    │   REFINER    │    │ TRANSCRIBER  │      │
│  │   (pynput)   │    │ (Groq Llama) │    │(Groq Whisper)│      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   ACTIVE     │    │   SYSTEM     │    │   CONFIG     │      │
│  │   WINDOW     │    │    TRAY      │    │   MANAGER    │      │
│  │  (any app)   │    │  (pystray)   │    │   (JSON)     │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS
                              ▼
                    ┌──────────────────┐
                    │    GROQ API      │
                    │  - Whisper       │
                    │  - Llama-3-8B    │
                    └──────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Library |
|-----------|---------------|---------|
| Hotkey Listener | Detect global key press/release | `pynput` |
| Audio Recorder | Capture microphone input at 16kHz | `sounddevice` |
| VAD | Detect speech end via silence | `silero-vad` |
| ASR Transcriber | Convert audio to raw text | Groq Whisper API |
| LLM Refiner | Clean and style the text | Groq Llama-3 API |
| Text Injector | Type text into active window | `pynput.keyboard` |
| Context Detector | Identify active application | `pygetwindow` / `AppKit` |
| System Tray | Background UI and settings | `pystray` |
| Config Manager | Persist user preferences | JSON file |

---

## 4. Technology Stack

### Core Dependencies

```
# requirements.txt

# Audio
sounddevice==0.4.6
numpy==1.26.4
scipy==1.12.0

# Voice Activity Detection
torch==2.2.0
torchaudio==2.2.0
silero-vad==4.0

# Hotkey & Typing
pynput==1.7.6

# AI APIs
groq==0.4.2

# System Tray
pystray==0.19.5
Pillow==10.2.0

# Window Detection (Windows)
pygetwindow==0.0.9  # Windows only

# Window Detection (macOS)
pyobjc-framework-Cocoa==10.1  # macOS only

# Notifications
plyer==2.1.0

# Packaging
pyinstaller==6.4.0
```

### API Dependencies

| Service | Purpose | Pricing |
|---------|---------|---------|
| Groq Whisper | Speech-to-text | ~$0.03/hour of audio |
| Groq Llama-3-8B | Text refinement | ~$0.05/1M tokens |

**Cost per user (heavy usage: 20 requests/day):** ~$0.08/month

---

## 5. Configuration Schema

### Default Configuration (config.json)

```json
{
  "version": "1.0.0",
  "hotkey": {
    "combination": ["ctrl", "shift", "space"],
    "mode": "hold"  // "hold" or "toggle"
  },
  "audio": {
    "sample_rate": 16000,
    "channels": 1,
    "silence_threshold_ms": 600,
    "max_recording_seconds": 60
  },
  "style": {
    "active": "clean",
    "options": {
      "clean": "Remove filler words (um, uh, like, you know). Fix grammar and punctuation. Keep original tone.",
      "professional": "Make formal and concise. Remove all filler words. Use professional language.",
      "casual": "Keep friendly and relaxed. Light grammar fixes only. Preserve personality.",
      "technical": "Preserve technical terms exactly. Fix only obvious errors. Maintain precision."
    }
  },
  "context_awareness": {
    "enabled": true,
    "app_specific_styles": {
      "Slack": "professional",
      "Discord": "casual",
      "Code": "technical",
      "Visual Studio Code": "technical",
      "Outlook": "professional",
      "Gmail": "professional"
    }
  },
  "api": {
    "provider": "groq",
    "whisper_model": "whisper-large-v3",
    "llm_model": "llama3-8b-8192"
  },
  "ui": {
    "start_on_boot": false,
    "show_notifications": true,
    "play_sounds": true,
    "sound_on_start": "assets/beep_start.wav",
    "sound_on_end": "assets/beep_end.wav"
  }
}
```

---

## 6. State Machine

The application follows a strict state machine:

```
                    ┌─────────┐
                    │  IDLE   │◀─────────────────────┐
                    └────┬────┘                      │
                         │                           │
                    [Hotkey Pressed]                 │
                         │                           │
                         ▼                           │
                    ┌─────────┐                      │
                    │RECORDING│                      │
                    └────┬────┘                      │
                         │                           │
         [Hotkey Released OR Silence Detected]       │
                         │                           │
                         ▼                           │
                    ┌─────────┐                      │
              ┌─────│PROCESSING│                     │
              │     └────┬────┘                      │
              │          │                           │
         [Error]    [Success]                        │
              │          │                           │
              ▼          ▼                           │
        ┌─────────┐ ┌─────────┐                      │
        │  ERROR  │ │ TYPING  │                      │
        └────┬────┘ └────┬────┘                      │
             │           │                           │
             └───────────┴───────────────────────────┘
```

### State Definitions

| State | Tray Icon | Description |
|-------|-----------|-------------|
| IDLE | ⚪ Gray | Waiting for hotkey |
| RECORDING | 🔴 Red | Capturing audio |
| PROCESSING | 🟡 Yellow | Transcribing + refining |
| TYPING | 🟢 Green | Injecting text |
| ERROR | 🔴 Red (flash) | Something went wrong |

---

## 7. Error Handling Strategy

### Error Categories

| Error | User Feedback | Recovery |
|-------|---------------|----------|
| No internet | Notification: "No connection. Check your internet." | Return to IDLE |
| API key invalid | Notification: "Invalid API key. Check settings." | Return to IDLE |
| No audio detected | Notification: "No speech detected." | Return to IDLE |
| API timeout | Notification: "Server slow. Try again." | Return to IDLE |
| Microphone in use | Notification: "Microphone unavailable." | Return to IDLE |
| Groq rate limit | Notification: "Too many requests. Wait 10 seconds." | Auto-retry after delay |

### Fallback Behavior

If LLM refinement fails but transcription succeeds:
- **Action:** Insert raw transcript (unrefined)
- **Notification:** "Inserted raw transcript (refinement failed)"

---

## 8. Security & Privacy

### Data Flow

```
Audio → [Your Device] → HTTPS → [Groq API] → [Your Device] → Discarded
```

### Privacy Guarantees

1. **No local storage of audio:** Audio is held in RAM only, never written to disk
2. **No local storage of transcripts:** Text is discarded after injection
3. **API provider policy:** Groq does not store or train on API inputs
4. **No telemetry:** App sends nothing to developer servers

### API Key Storage

- **Windows:** Stored in `%APPDATA%/EchoFlow/config.json` (user-only readable)
- **macOS:** Stored in `~/Library/Application Support/EchoFlow/config.json`
- **Future:** Consider OS keychain integration for enhanced security

---

## 9. Platform-Specific Considerations

### Windows

| Feature | Implementation |
|---------|---------------|
| Global hotkey | `pynput.keyboard.GlobalHotKeys` |
| Active window | `pygetwindow.getActiveWindow()` |
| System tray | `pystray` with `.ico` icon |
| Startup | Registry key in `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` |
| Audio device | Default input via `sounddevice` |

### macOS

| Feature | Implementation |
|---------|---------------|
| Global hotkey | `pynput` (requires Accessibility permission) |
| Active window | `NSWorkspace.sharedWorkspace().frontmostApplication()` |
| System tray | `pystray` with `.png` icon |
| Startup | LaunchAgent plist in `~/Library/LaunchAgents/` |
| Audio device | Default input via `sounddevice` |

### macOS Permissions Required

1. **Accessibility:** For global hotkey capture
2. **Microphone:** For audio recording
3. **Automation:** For text injection into other apps

---

## 10. File Structure

```
echoflow/
├── main.py                 # Entry point
├── requirements.txt        # Dependencies
├── config.json            # User configuration
│
├── core/
│   ├── __init__.py
│   ├── state_machine.py   # Application state management
│   ├── hotkey_listener.py # Global hotkey detection
│   ├── audio_recorder.py  # Microphone capture
│   ├── vad.py             # Voice activity detection
│   ├── transcriber.py     # Groq Whisper integration
│   ├── refiner.py         # Groq Llama integration
│   ├── text_injector.py   # Keyboard simulation
│   └── context_detector.py # Active window detection
│
├── ui/
│   ├── __init__.py
│   ├── tray.py            # System tray icon and menu
│   ├── settings_window.py # Settings GUI (optional)
│   └── notifications.py   # Toast notifications
│
├── utils/
│   ├── __init__.py
│   ├── config_manager.py  # Load/save configuration
│   ├── logger.py          # Logging setup
│   └── platform_utils.py  # OS-specific helpers
│
├── assets/
│   ├── icon_idle.png
│   ├── icon_recording.png
│   ├── icon_processing.png
│   ├── icon_error.png
│   ├── beep_start.wav
│   └── beep_end.wav
│
└── build/
    ├── windows/
    │   └── echoflow.spec  # PyInstaller spec for Windows
    └── macos/
        └── echoflow.spec  # PyInstaller spec for macOS
```

---

## 11. Development Phases

### Phase 1: Core MVP (Week 1-2)
- [x] Hotkey listener
- [x] Audio recording
- [x] Basic VAD (key release only)
- [x] Groq Whisper transcription
- [x] Groq Llama refinement
- [x] Text injection
- [x] System tray icon

### Phase 2: Polish (Week 3)
- [ ] Silero VAD (smart silence detection)
- [ ] Context awareness (detect active app)
- [ ] Settings window
- [ ] Notifications
- [ ] Sound feedback

### Phase 3: Distribution (Week 4)
- [ ] PyInstaller packaging (Windows .exe)
- [ ] PyInstaller packaging (macOS .app)
- [ ] Code signing (optional)
- [ ] Auto-updater (optional)

### Phase 4: Advanced Features (Future)
- [ ] Local mode (Faster-Whisper + Ollama)
- [ ] Custom user prompts
- [ ] Clipboard context ("Reply to copied text")
- [ ] Multiple language support

---

## 12. Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| End-to-end latency | <1 second | Timestamp logging |
| Transcription accuracy | >95% WER | Manual testing |
| Style accuracy | >90% | User feedback |
| Crash rate | <1% | Error logging |
| Daily active usage | N/A | Optional telemetry |

---

## 13. Dependencies on External Services

| Service | Criticality | Fallback |
|---------|-------------|----------|
| Groq API | HIGH | None (app non-functional without) |
| Internet | HIGH | Offline notification |

**Risk:** Groq API unavailability = complete service disruption

**Mitigation (Future):** Implement local mode with Faster-Whisper + Ollama

---

## Document Navigation

- **Document 1 (This):** Master Architecture & Overview
- **Document 2:** Technical Implementation Specifications
- **Document 3:** Build Prompts & Execution Sequence

---

*End of Document 1*
