# Riff Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [2026-01-28] - Session: claude/review-riff-app-ffwNp

### Fixed
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

### Changed
- **What Changed**
  - **Before**: Old behavior
  - **After**: New behavior
  - **Reason**: Why this change was made
  - **Files Changed**: List of files
  - **Commit**: Short hash

### Deprecated
- Features that are being phased out

### Removed
- Features that were removed

### Security
- Security-related fixes
```

### Categories Priority Order:
1. **Security** - Always list first if present
2. **Fixed** - Bug fixes
3. **Added** - New features
4. **Changed** - Changes to existing features
5. **Deprecated** - Soon-to-be-removed features
6. **Removed** - Removed features

### Writing Style:
- ✅ Start with user impact (what/why before how)
- ✅ Include "Problem → Solution → Impact" for fixes
- ✅ Be specific but concise
- ✅ Link commit hashes for traceability
- ✅ List all files changed
- ❌ Don't include implementation details unless critical
- ❌ Don't be too verbose (1-3 sentences per bullet)
