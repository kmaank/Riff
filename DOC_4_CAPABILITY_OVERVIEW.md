# Riff - Product Capability Log

> This document tracks the evolution of Riff's capabilities. Each entry represents a shipped state of the product.

---

## 📦 Release v1.0.0 (Stable)
**Date:** 2026-01-18
**Timestamp:** 13:50 IST
**Status:** Shipped 🚀

### 1. Executive Summary
**Riff** is a high-performance, AI-powered voice-to-text utility for macOS. It is context-aware and uses next-generation AI (Groq + Llama 3) to deliver nearly instant, human-quality transcription anywhere on the screen.

### 2. Capabilities List

#### 🎙️ Global Smart Dictation
*   **Works Anywhere:** Compatible with IDEs, Browsers, Slack, etc.
*   **Virtual Keyboard Injection:** Types text directly into active fields.

#### 🧠 Context-Aware Intelligence
*   **Active Context Retrieval:** Reads previous text to understand context.
*   **Style Matching:** Adapts to code (snake_case) or prose automatically.
*   **Smart Refinement:** Llama-3 removes fillers ("umms") and fixes grammar.

#### ⚡ Extreme Performance
*   **Engine:** Groq LPU + Whisper-Large-V3.
*   **Latency:** Near real-time processing.

####  UX & Onboarding
*   **Push-to-Talk:** `Left Control` (Hold).
*   **Latch Mode:** `Ctrl + Shift` (Toggle).
*   **Native Setup:** AppleScript popups for API Key & Permissions (No Terminal).
*   **Tray Icon:** Menu bar control and status indication.

#### Technical Specs
*   **OS:** macOS Big Sur+ (Apple Silicon Native + Intel Rosetta).
*   **Security:** Local config storage; no audio verified limits.
*   **Distribution:** Signed `.pkg` installer.
