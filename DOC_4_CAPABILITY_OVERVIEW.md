# Riff - Product Capability Overview
**Version:** 1.0.0 (Stable Release)
**Date:** 2026-01-18

## 1. Executive Summary
**Riff** is a high-performance, AI-powered voice-to-text utility for macOS. Unlike standard dictation tools, Riff is "context-aware"—it reads the surrounding text to understand style and intent—and utilizes next-generation AI (Groq + Llama 3) to deliver nearly instant, human-quality transcription anywhere on the screen.

---

## 2. Core Capabilities

### 🎙️ Global Smart Dictation
*   **Works Anywhere:** Riff is not limited to a specific app. It works in IDEs (VS Code), Messengers (Slack, Discord), Browsers, and Notes.
*   **Virtual Keyboard Injection:** Riff types the text out as if you typed it yourself, ensuring compatibility with 100% of application text fields.

### 🧠 Context-Aware Intelligence
*   **Active Context Retrieval:** Before you speak, Riff momentarily checks the text *before* your cursor (via smart clipboard handling).
*   **Style Matching:** If you are writing a formal email, Riff dictates formally. If you are writing Python code, it formats variables (e.g., `snake_case`) correctly.
*   **Smart Refinement:** Raw fast speech is "cleaned" by Llama-3 to remove "umms", "ahhs", and stutters while fixing grammar instantly.

### ⚡ Extreme Performance (Groq Powered)
*   **Latency:** Near real-time. By leveraging Groq's LPU (Language Processing Unit) inference engine, Riff converts audio to refined text faster than real-time speech.
*   **Models:**
    *   **Hearing:** Whisper-Large-V3 (State-of-the-art recognition).
    *   **Thinking:** Llama-3-70b (Nuanced text refinement).

## 3. User Experience (UX)

### 🖱️ Frictionless Control
*   **Push-to-Talk:** Hold `Left Control` to speak. Release to transcribe. Experience feels like a "Walkie-Talkie" for your computer.
*   **Latch Mode:** Press `Ctrl + Shift` to toggle recording on/off (perfect for long dictations without holding a key).
*   **Visual Feedback:**
    *   Mic icon appears/animates in the System Tray (Menu Bar).
    *   Audio cues (optional future feature) on start/stop.

### 📦 Seamless Onboarding
*   **Native Experience:** No command-line required for end-users.
*   **Guided Setup:**
    *   **API Key:** Native macOS popup asks for the Groq Key securely.
    *   **Permissions:** Prompts user to enable Accessibility and Microphone permissions via System Settings.
*   **System Tray:** Unobtrusive "Riff" icon in the menu bar for quick access to Settings, Instructions, or Quit.

## 4. Technical Specifications

### System Requirements
*   **OS:** macOS Big Sur (11.0) or later.
*   **Hardware:** Optimized for Apple Silicon (M1/M2/M3/M4), but compatible with Intel Macs via Rosetta.
*   **Internet:** Required (for API calls).

### Security & Privacy
*   **No Data Storage:** Audio is processed in RAM and sent to API; never saved to disk permanently (temp files are overwritten).
*   **Local Config:** API Keys are stored locally in the user's secure Application Support folder (`~/Library/Application Support/Riff/config.json`).
*   **Distribution:** Signed `.pkg` installer ensures file integrity and easier Gatekeeper acceptance.

## 5. Use Cases (For Marketing)

| Persona | Use Case | Capability Highlight |
| :--- | :--- | :--- |
| **Developer** | Dictating documentation, commit messages, or comments. | "Context Aware" (Matches code style). |
| **Writer/Marketer** | Drafting blog posts or rapid-fire email replies. | "Llama-3 Refinement" (Fixes grammar on the fly). |
| **Executive** | Slack updates and heavy email volume. | "Push-to-Talk" (Fastest input method). |
