# Riff 🎙️

A desktop voice-to-text app that runs in the system tray. Press a hotkey → speak → polished text appears in any app.

- Removes filler words ("um", "uh", "like") automatically
- Multiple refinement styles: casual, formal, clean, code
- Works in ANY app (Slack, Email, Code editor, Browser)
- Powered by Groq API (Whisper + LLaMA)

---

## 🏗️ Building

### macOS (.app / .dmg) — via GitHub Actions

Riff uses **GitHub Actions** to build the macOS `.app` and `.dmg` on a cloud Apple Silicon runner. **No local Mac is needed for building.**

#### How it works:

1. Push code to the `claude/` branch or `main`
2. GitHub Actions automatically builds:
   - The **Swift Control Center UI** (compiled with `swiftc`)
   - The **Python app** (bundled with PyInstaller)
   - A `.dmg` installer
3. Download the built artifacts from the **Actions** tab

#### To trigger a build:

```bash
git add .
git commit -m "your changes"
git push origin claude/review-riff-app-ffwNp
```

Then go to **[Actions](../../actions)** → click the latest run → scroll to **Artifacts** → download `Riff-macOS-dmg`.

#### Manual trigger:

You can also trigger a build manually from the GitHub Actions tab → **"Build macOS App"** → **"Run workflow"**.

> **For AI assistants (Claude Code, Cursor, etc.):** After making code changes, commit and push to the `claude/` branch. The macOS build will be created automatically by GitHub Actions. Do NOT attempt to build `.app` locally — it requires a macOS environment which is handled by the CI pipeline.

---

## 🚀 Quick Start (Testing)

### Prerequisites
- Python 3.11
- Groq API key ([console.groq.com](https://console.groq.com) — free)

### Running from source (any OS):
```bash
python -m venv venv
source venv/bin/activate        # macOS/Linux
# .\venv\Scripts\activate       # Windows

pip install -r requirements.txt
python main.py
```

### Installing the built app (macOS):
1. Download `Riff-macOS-dmg` from the latest [Actions run](../../actions)
2. Open the `.dmg`
3. Drag Riff to Applications
4. Launch Riff — it appears in your system tray
5. Set your Groq API key when prompted

---

## 🎯 Usage

| Action | What happens |
|--------|-------------|
| **Hold hotkey** (default: Left Ctrl) | Records your voice |
| **Release hotkey** | Stops recording, transcribes, refines, and pastes |
| **Hold hotkey + press Shift** | Latch mode — keeps recording until you press the hotkey again |

### Refinement Styles
- **Casual** — Raw, authentic transcription preserving tone and emotion
- **Formal** — Clean, professional business text
- **Clean** — Removes fillers, fixes grammar, keeps original meaning
- **Code** — Formats as code comments or variable names

---

## 📁 Project Structure

```
Riff/
├── main.py                    # App entry point
├── core/
│   ├── audio_recorder.py      # Microphone recording with sounddevice
│   ├── transcriber.py         # Groq Whisper transcription  
│   ├── refiner.py             # LLM text refinement
│   ├── text_injector.py       # Clipboard paste / keystroke injection
│   └── context_detector.py    # App context detection
├── ui/
│   ├── tray.py                # System tray (pystray)
│   ├── instructions.py        # Help window
│   └── native_onboarding.py   # First-run setup
├── utils/
│   ├── config_manager.py      # JSON config management
│   ├── permissions.py         # OS permission checks
│   └── logger.py              # Logging setup
├── config_ui/
│   └── RiffControlCenter/     # Swift macOS settings UI
├── assets/                    # Icons and images
├── Riff.spec                  # PyInstaller spec (macOS)
├── requirements.txt           # Python dependencies
└── .github/workflows/
    └── build-macos.yml        # CI: auto-build macOS .app
```

---

## 📄 Documentation

| Document | Purpose |
|----------|---------|
| `DOC_1_MASTER_ARCHITECTURE.md` | System design and architecture |
| `DOC_2_TECHNICAL_SPECIFICATIONS.md` | Detailed module specs |
| `DOC_3_BUILD_PROMPTS.md` | AI-assisted build prompts |
| `QUICKSTART.md` | Getting started guide |
| `CHANGELOG.md` | Version history |
