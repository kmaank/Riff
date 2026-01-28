# Riff Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.2.7] - 2026-01-28

### Added
- **Large File Handling with Auto-Chunking**
  - **Problem**: Audio files exceeding 25MB/13 minutes failed with Groq API limit error
  - **Solution**:
    - Automatically detect files > 25MB and split into 10-minute chunks
    - Transcribe each chunk independently using Whisper
    - Concatenate chunk transcriptions with intelligent spacing
    - Auto-cleanup temporary chunk files after processing
  - **Impact**: Supports unlimited recording length (tested with 57-minute/104MB files)
  - **Files Changed**: `core/transcriber.py`
  - **Commit**: `574957c`

- **Control Center UX Improvements (3 changes)**
  - **Changes**:
    1. **Streamlined Onboarding**: Merged microphone permission page into combined permissions step (6 steps → 5 steps). Added permissions section to Keys tab for post-onboarding access.
    2. **Merged Script & Style Tabs**: Combined into single "Script & Style" tab with Script Mode first, then Style options (5 tabs → 4 tabs). Cleaner sidebar navigation.
    3. **Enhanced History Timestamps**: Now shows full date + time (e.g., "Jan 28, 2026 at 3:45 PM") instead of time-only format.
  - **Impact**: Simpler onboarding flow, less cluttered interface, more informative history
  - **Files Changed**: `OnboardingView.swift`, `KeysView.swift`, `ContentView.swift`, `ScriptAndStyleView.swift` (new), `HistoryView.swift`
  - **Commit**: `d9a5cae`

### Fixed
- **Long Transcriptions Not Pasting Completely**
  - **Problem**: Transcriptions > 5000 chars (30+ minute recordings) were truncated when pasted, only partial text appeared
  - **Root Cause**: macOS clipboard and app limitations - single large paste (8603 chars) overwhelms clipboard/app buffer
  - **Solution**: Added chunked pasting - splits text into 4000-char chunks with sequential paste operations and delays between chunks
  - **Impact**: Long recordings now paste reliably without data loss
  - **Files Changed**: `core/text_injector.py`
  - **Commit**: `c296803`

- **Control Center Window Not Appearing from Tray**
  - **Problem**: Clicking "Settings" in tray launched Control Center (visible in dock) but window didn't come to front, requiring manual dock icon click
  - **Root Cause**: `subprocess.Popen()` launches process but doesn't activate/focus window on macOS
  - **Solution**: Added AppleScript activation after launch with 0.3s initialization delay
  - **Impact**: Settings window now appears immediately when clicked from tray
  - **Files Changed**: `main.py`
  - **Commit**: `72ec6b7`

- **Critical: Whisper Hallucinations**
  - **Problem**: Short phrases like "Gantt chart" generated complete hallucinated paragraphs
  - **Root Cause**: Vague prompts ("naturally", "keeping code-switching") gave Whisper too much freedom to elaborate
  - **Solution**:
    - Replaced vague prompts with constraining language: "Transcribe exactly what is spoken, word for word. Do not add explanations..."
    - Added `response_format: "verbose_json"` to get confidence scores from Whisper
    - Added explicit `temperature: 0.0` for deterministic output
    - Implemented confidence-based hallucination detection (rejects if avg no_speech_prob > 0.8)
    - Improved hallucination filtering to only block obvious patterns (removed overly aggressive number filtering)
  - **Impact**: Eliminates hallucinations while preserving legitimate short transcriptions
  - **Files Changed**: `core/transcriber.py`
  - **Commit**: `3e20eb0`

### Added
- **Unified Tray and Control Center Lifecycle**
  - **Problem**: Tray app and Control Center ran as independent processes, requiring separate quits and creating orphaned processes
  - **Solution**:
    - Main app now tracks Control Center subprocess when launched
    - Automatically terminates Control Center when main app quits (graceful shutdown with 2s timeout)
    - Prevents multiple Control Center instances by bringing existing window to front
    - Launches Control Center binary directly to maintain process handle
  - **Impact**: One quit closes all, prevents orphaned processes, matches modern desktop app UX (Slack, Discord, etc.)
  - **Files Changed**: `main.py`
  - **Commit**: `7a49816`

- **Script Mode Tracking in History**
  - Added `script_mode` field to history entries for better tracking
  - Files Changed: `main.py` (HistoryManager, ProcessingThread)

### Technical Details
- **Whisper API Parameters**: Now using `verbose_json`, `temperature: 0.0`
- **Confidence Scoring**: Tracks avg no_speech_prob across all segments
- **Process Management**: Using `subprocess.Popen()` instead of `open -a` for better control

### Fixed (Late Updates)
- **History Date/Time Display**
  - **Problem**: History timestamps shifted due to timezone conversion
  - **Solution**: Implemented Wall Clock strategy to display server time exactly as received
  - **Files Changed**: `config_ui/RiffControlCenter/HistoryView.swift`
  - **Commit**: `1b13afd`

- **Build Pipeline**
  - **Solution**: `build_app.sh` now explicitly rebuilds the UI component before packaging
  - **Files Changed**: `build_app.sh`
  - **Commit**: `1b13afd`

---

## [1.2.6] - 2026-01-22
**Status:** Critical Bug Fixes Release
**Commits:** `5401d54`, `12304ea`

### Fixed
- **Thread Safety Bug (Zombie State)**
  - **Problem**: App getting stuck in zombie state after stream timeout (>20s).
  - **Root Cause**: Thread safety violation in audio recorder cleanup where state changes were made without locks.
  - **Solution**: Added thread locks, enhanced logging, and emergency state reset mechanisms.
  - **Files Changed**: `core/audio_recorder.py`, `main.py`, `ui/tray.py`

- **LLM Answering Bug**
  - **Problem**: AI answering dictated questions instead of transcribing them.
  - **Root Cause**: Refiner prompts lacked specific anti-chatbot instructions for dictation context.
  - **Solution**: Implemented comprehensive anti-answer preambles and strict context rules.
  - **Files Changed**: `core/refiner.py`

### Added
- **Health Monitoring System**: Automatically detects and recovers from stuck states every 30s.
- **Force Reset**: Manual tray option to reset app state.
- **State Dump**: Debug utility for logging app state during errors.

---

## [1.2.0] - 2026-01-18
**Status:** Control Center Shipped

### Added
- **Riff Control Center**: A native macOS Dashboard (SwiftUI).
  - **Style Picker**: Visual selection for personalities.
  - **History**: View past transcriptions.
  - **Keys**: Configure inputs.
  - **Help**: Native guide.
- **Local History**: Transcriptions saved to `history.json`.

---

## [1.0.0] - 2026-01-18
**Status:** Stable Release

### Added
- **Global Smart Dictation**: F8 to Record.
- **Context-Aware**: Auto-detects context.
- **Native Onboarding**: AppleScript dialogs.

---

## Format Guide

When adding new changes, use this structure:

```markdown
## [YYYY-MM-DD] - Session: <branch-name>

### Added
- **Feature Name**
  - **Problem**: What issue this solves (if applicable)
  - **Solution**: How it was implemented
  - **Impact**: User-facing benefit
  - **Files Changed**: List of files
  - **Commit**: Short hash

### Fixed
- **Bug Name**
  - **Problem**: What was broken
  - **Root Cause**: Why it was happening
  - **Solution**: How it was fixed
  - **Impact**: What this improves
  - **Files Changed**: List of files
  - **Commit**: Short hash
```
