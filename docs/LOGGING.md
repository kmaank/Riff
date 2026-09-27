# Sharing Riff logs

When something fails (onboarding, a long recording, paste, login), send the log folder — not `config.json`.

## Where they live

`~/Library/Application Support/Riff/logs`

From the menu bar: **Riff → Reveal Logs**.

From Terminal:

```bash
open ~/Library/Application\ Support/Riff/logs
zip -r ~/Desktop/riff-logs.zip ~/Library/Application\ Support/Riff/logs
```

## What to attach

| File | What it is |
|------|------------|
| `riff.log` | **Start here.** Current session: Python pipeline + Control Center auth/onboarding. |
| `debug.log` | Rolling Python history (rotated at 10 MB). |
| `debug_auth.log` | Control Center login, key restore, onboarding steps. |
| `diagnostics.txt` | Session id, Python version, signed-in?, has Groq key? (no secrets). |
| `activity.log` | Short human-readable timeline. |
| `HOW_TO_SHARE.txt` | This reminder, written next to the logs. |

Keys, JWTs, and Bearer tokens are redacted (`gsk_REDACTED`, `JWT_REDACTED`). Still do **not** send `config.json`.

## How to reproduce a useful log

1. Quit Riff fully (menu bar → Quit).
2. Launch Riff again (a new session banner is written).
3. Reproduce the bug once.
4. Reveal Logs and zip the folder, or attach `riff.log` + `debug_auth.log` + `diagnostics.txt`.

## What to look for

- Onboarding: `[Onboarding] step ->`, `saveCloudGroqKey status=`, `fetchCloudGroqKey status=`, `can_riff=`
- Long recordings: `LONG RECORDING`, `hold=`, `chunks_est=`, `watchdog=`, `[Transcriber] Splitting`, `Chunk N/M ... in Xs`
- Stuck processing: `[Watchdog]`, `[HealthMonitor]`, `[STATE DUMP]`
