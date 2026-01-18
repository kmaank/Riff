# EchoFlow Desktop - Quick Start Guide

## 🎯 What You're Building

A desktop voice-to-text app that:
- Runs in system tray (Windows/macOS)
- Press hotkey → speak → polished text appears
- Removes "um", "uh", "like" automatically
- Works in ANY app (Slack, Email, Code, Browser)

**Timeline:** 1-2 weeks of vibe-coding

---

## 📁 Documents Included

| Document | Purpose | Use When |
|----------|---------|----------|
| `DOC_1_MASTER_ARCHITECTURE.md` | Big picture, system design | Starting out, need context |
| `DOC_2_TECHNICAL_SPECIFICATIONS.md` | Detailed module specs, code patterns | Writing specific modules |
| `DOC_3_BUILD_PROMPTS.md` | **Copy-paste prompts for AI** | **Actually building** |

---

## 🚀 Fastest Path to Working App

### Day 1: Setup + First Recording

1. **Get your tools:**
   - Install Python 3.11
   - Install Cursor (cursor.sh) or use Gemini
   - Get Groq API key (console.groq.com - free)

2. **Copy Prompt 0 from DOC_3** → paste into AI → run commands

3. **Copy Prompt 1.1 from DOC_3** → paste into AI → test recording

### Day 2: Connect the Pipeline

4. **Copy Prompts 1.2, 1.3, 1.4, 1.5 from DOC_3** (in order)

5. **Test:** Press F8 → speak → text appears in Notepad

### Day 3-4: Make It Pretty

6. **Copy Prompts 2.1 through 2.5 from DOC_3**

7. **Test:** App runs with tray icon, uses config file

### Day 5-6: Package It

8. **Copy Prompts 3.1 or 3.2** (depending on OS)

9. **Result:** Standalone .exe or .app file

---

## 💰 Cost Breakdown

| Item | Cost |
|------|------|
| Development | $0 |
| Groq API (testing) | $0 (free tier) |
| Groq API (per user/month) | ~$0.08 |
| Google Play | $25 one-time |
| Apple Developer | $99/year |

---

## 🔑 Key Decisions Made For You

| Decision | Choice | Why |
|----------|--------|-----|
| Language | Python | Your research doc has Python, AI generates it well |
| Cloud API | Groq | Fastest (300ms), cheapest (~$0.08/user) |
| Audio | sounddevice | Cross-platform, simple |
| Hotkey | pynput | Works globally on Win/Mac |
| Tray | pystray | Standard solution |

---

## ⚠️ Common Gotchas

1. **macOS needs permissions:** Accessibility + Microphone
2. **Windows antivirus:** May flag the .exe initially
3. **Groq rate limits:** 30 requests/minute on free tier
4. **First run:** Config file auto-creates, but API key is empty

---

## 📋 Pre-Flight Checklist

Before starting:
- [ ] Python 3.11 installed
- [ ] Cursor/Gemini ready
- [ ] Groq API key obtained
- [ ] DOC_3 open and ready

---

## 🏁 Definition of Done

Your app is complete when:
- [ ] Double-click to launch
- [ ] Appears in system tray
- [ ] Hotkey records voice
- [ ] Text appears in any app
- [ ] Filler words removed
- [ ] Can be quit from tray

---

## Need Help?

Paste errors directly into your AI assistant with:
```
I'm building EchoFlow (voice-to-text desktop app).
Error: [paste error]
File: [which file]
What I was trying: [what you did]
```

---

**Start with DOC_3_BUILD_PROMPTS.md, Prompt 1.1. Go.**
