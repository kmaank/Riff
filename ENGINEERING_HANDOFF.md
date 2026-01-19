# Engineering Handoff & Context Log
**Project:** Riff (formerly EchoFlow)
**Date:** January 2026
**Status:** Production Ready (macOS .pkg)

## 1. Project Overview
Riff is a native macOS voice-to-text utility that allows users to dictate text into any application.
- **Microphone**: Captures audio via `sounddevice`.
- **Logic**: Python (`main.py`) handles orchestration, API calls, and refined text injection.
- **UI**: Hybrid approach.
    - **Tray**: `pystray` (Python) for menu bar interactions.
    - **Settings**: SwiftUI (`RiffControlCenter.app`) for a native macOS preference window.
- **AI**: Uses Groq (Llama 3.3) for fast transcription and refinement.

## 2. Critical Architecture & Decisions ("The Why")

### 2.1 Hybrid UI (Python + Swift)
**Why?**
Tkinter looks foreign on macOS. We wanted a native "Settings" window but wanted to keep the core logic in Python for easy AI integration.
**Implementation:**
- `main.py` launches `RiffControlCenter.app` (Swift) as a subprocess.
- **IPC**: They communicate via a shared `config.json` file.
- **Watcher**: `main.py` spawns a thread (`monitor_config`) to watch this file for changes (file modification time) and reloads settings (like hotkeys) instantly.

### 2.2 Removing Tkinter
**Issue:** The "How to Use" window was originally Tkinter. This caused immediate crashes on macOS when running alongside `pystray` because both try to manage the main `NSApplication` event loop.
**Solution:**
We replaced the Tkinter Help window with a **generated HTML file** opened in the default browser.
**Benefit:** Zero crash risk, better styling capabilities (CSS), native feel.

### 2.3 Packaging & Path Resolution
**Issue:** When packaged with PyInstaller, the app couldn't find assets or the Settings app.
**Solution:**
We implemented a robust `get_resource_path` function that checks:
1.  `sys._MEIPASS` (PyInstaller temp dir).
2.  `Contents/MacOS/` (Executable dir).
3.  `Contents/Resources/` (Standard macOS bundle dir).
**Best Practice**: Always check `sys._MEIPASS` first for single-file builds, but check `Resources/` for `.app` bundles to allow easier asset updates.

### 2.4 Hotkey Logic Mismatch
**Issue:** The Swift UI (`KeysView.swift`) expected the hotkey combination to be a **String** (e.g., `"ctrl_l"`), but Python's `pynput` often defaults to a **List** (`["ctrl_l"]`). This caused the UI to break and revert to defaults.
**Fix:**
We enforced **String** format in `config_manager.py` and updated `main.py` deserialization to handle both (backward compatibility), but primarily save as String.

### 2.5 Input Monitoring
**Issue:** The app could "run" but not detect key presses globally.
**Why?** macOS requires specific "Input Monitoring" permission for global listeners, distinct from "Accessibility".
**Fix:** We added an explicit check and deep-link to the Input Monitoring settings pane in `native_onboarding.py`.

## 3. Best Practices Implemented

### 3.1 Live Configuration Reloading
Instead of requiring a restart for every setting change, the `monitor_config` function allows the user to change Hotkeys, Styles, or Models in the Settings UI, and the Python backend adapts immediately (restarting the `GlobalHotKeys` listener dynamically).

### 3.2 Strict Prompt Engineering
To prevent the LLM from chatting ("Here is your text: ..."), we append a **Strict Instruction** to every prompt in `ConfigManager`:
> "CRITICAL: Output ONLY the refined text. Do NOT include quotes... Just the text."

### 3.3 Build Pipeline Dependency
The build order is critical:
1.  **`build_ui.sh`**: Compiles Swift -> `RiffControlCenter.app`.
2.  **`build_app.sh`**: Uses PyInstaller to bundle Python + `RiffControlCenter.app` + `assets` -> `Riff.app`.
3.  **`build_pkg.sh`**: Wraps `Riff.app` into `Riff.pkg` for distribution.

## 4. Branding & Assests
- **Icons**: Generated via `tools/generate_icons.py`.
- **States**:
    - **Idle**: `tray_idle.png` (Standard Logo)
    - **Recording**: `tray_recording.png` (Red Tint)
    - **Processing**: `tray_processing.png` (Yellow Tint)
- **Settings Logo**: `settings_logo.png` (bundled in `config_ui/build_ui.sh`) replaces the text header in Swift UI.

## 5. Future Agent Instructions
If you work on this codebase:
1.  **Do NOT introduce Tkinter**. It conflicts with `pystray`. Use Web or Swift for UI.
2.  **Respect the Build Path**: Assets must be copied into `Contents/Resources` during build. Python checks there.
3.  **Config**: Always read/write to `config.json` for persistent state. Python is the source of truth for *logic*, Swift is the source of truth for *user intent*.
