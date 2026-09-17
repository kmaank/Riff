# Riff key management (BYOK)

This document is the source of truth for how Groq API keys work on the **`byok-version`** branch.

Riff is free. Every user brings their own Groq key. They sign in once, paste the key once, and that key follows the **account** — not one laptop. Devices still call Groq **directly**. Riff does not proxy transcription.

---

## What a user experiences

1. **Sign up or log in** with email on Mac.
2. **First time on this account:** paste a Groq key that starts with `gsk_`. Riff saves it on this Mac and on the account.
3. **Later on the same account** (new Mac, Android when it exists, or uninstall then reinstall): log in. The key comes back. No paste again.
4. **Replace the key** in Control Center → Account. The new key overwrites the account copy after a short pause.
5. **Sign out** on a Mac: the Groq key is removed from that Mac so the next person at that computer cannot use it. The account still has the wrapped copy. Logging in again restores it.

There is no paywall and no Riff-owned Groq key on this branch.

---

## The two copies of the key

| Place | What is stored | Who can use it |
|---|---|---|
| This Mac | Plain Groq key in `~/Library/Application Support/Riff/config.json` under `api.api_key` | This device, so it can call Groq with no extra hop |
| Riff account (Supabase) | Scrambled (wrapped) copy in table `user_groq_keys` | Nobody until our server unlocks it after a valid login |

The Mac copy is what makes riffs fast. The account copy is what makes “paste once, use everywhere” work.

Sign-in tokens live separately (`session.json` and UserDefaults). They are not the Groq key.

---

## The padlock (why we have Edge secrets)

If the database stored Groq keys as readable text, a database leak would give attackers every user’s Groq key and they could spend those users’ Groq credits.

So before save, the server **locks** the key:

1. The user is logged in (JWT).
2. Edge Function `save-groq-key` receives the `gsk_…` key.
3. It encrypts with AES-256-GCM using a lock-key that exists **only** on the server.
4. Postgres stores a blob that looks like `v1.{iv}.{ciphertext}`.
5. The Mac never sees that blob. The user cannot decrypt it from their account dump.

To unlock, Edge Function `get-api-key` checks the same login, reads the blob, decrypts with the same lock-key, and returns the plain Groq key to that device.

### The lock-key (already set)

On project **Riff-production** (`yrsviodciuepunofxoja`) these two Edge secrets hold the **same** random 32-byte hex value:

- `ENCRYPTION_SECRET`
- `API_KEY_WRAP_SECRET`

The code (`supabase/functions/_shared/crypto.ts`) tries `API_KEY_WRAP_SECRET` first, then `ENCRYPTION_SECRET`. Both names exist so either path works.

They were generated with `openssl rand -hex 32` and uploaded with the Supabase CLI. The value is **not** in git and must **not** be pasted into chat, README, or GitHub.

You do **not** need to create these again.

**Do not rotate (replace) them** unless you are ready to make every user paste their Groq key again. A new lock-key cannot open blobs written with the old one.

Dashboard (only if you ever need to look at names, not values):  
Supabase → Project **Riff-production** → Edge Functions → Secrets.

---

## What the server does

### Table `public.user_groq_keys`

| Column | Meaning |
|---|---|
| `user_id` | Primary key, one row per Riff user |
| `encrypted_key` | Wrapped Groq key (`v1.…`) |
| `updated_at` | Last save |

Row Level Security is on. `anon` and `authenticated` have **no** grants. Only the **service role** (Edge Functions) can read or write. The Mac app must not query this table through the REST API.

Migration: `supabase/migrations/013_user_groq_keys.sql` (already applied on production).

### `POST /functions/v1/save-groq-key`

- Requires a user JWT (`verify_jwt: true`).
- Body: `{ "api_key": "gsk_..." }`.
- Rejects keys that do not start with `gsk_`.
- Wraps and upserts the row for that user.
- Returns `{ "ok": true }`.
- Must never log the key.

### `POST /functions/v1/get-api-key`

- Requires a user JWT.
- If this user has no row: **404** `{ "error": "not_found" }` — onboarding should show the paste screen.
- If a row exists: unwrap and return `{ "api_key": "gsk_..." }`.
- If a leftover unwrapped value is found, it is re-wrapped on read.

On this branch, `get-api-key` is **not** a 24-hour lease of a Riff-owned Groq key. That behaviour lives only on `paid-branch`.

---

## What the Mac does

### Save (paste or Account field)

1. Write `api.api_key` into `config.json`.
2. Call `save-groq-key` with the access token.
   - Onboarding: immediately on Next.
   - Account: about 0.8s after typing stops, so we do not hit the server on every keystroke.

Code: `OnboardingView.saveKey`, `AccountView.scheduleCloudSave`, `SwiftAuthManager.saveCloudGroqKey`, Python `AuthManager._save_cloud_groq_key`.

### Restore (login, signup finished, app start)

1. Call `get-api-key`.
2. If the account has a key, write it into `config.json` (account wins over a different local key).
3. If the account has none, but this Mac already has a `gsk_` key, **upload** it (covers people who pasted locally before cloud save existed).
4. If neither has a key, show the paste step.

Code: `SwiftAuthManager.syncGroqKeyWithCloud`, `OnboardingView.advanceAfterAccount`, Python `AuthManager.sync_byok_key` on tray start and before a riff if the local key is missing.

### Sign out

Clear `api.api_key` in `config.json`, delete session tokens, mark `auth_state.json` signed out. **Do not** delete the `user_groq_keys` row.

Code: `SwiftAuthManager.signOut` / `clearLocalApiKey`, Python `AuthManager.logout`.

### Riffing

`AuthManager.get_effective_api_key()` reads the local config key. Whisper and Llama on Groq use that key from this laptop. Silence/noise is still skipped locally so empty clips are not billed.

---

## Security: what this does and does not do

**Does**

- Stop casual reading of Groq keys from Postgres or the Supabase table editor as a normal user.
- Stop Control Center from showing a key after sign-out on that Mac.
- Restore the key only to a device that has a valid login.

**Does not**

- Hide the key from someone who is logged in on that device (it must be in memory and in `config.json` so Groq can be called).
- Stop a determined person from copying the key off their own laptop while signed in.
- Bind the Groq key so it only works inside Riff. Groq keys are bearer tokens; if copied, they work in curl too. That is Groq’s model, not a Riff bug.

The product promise is **one-time setup and sync**, not “the user can never extract their own key.”

---

## Other devices (Android later)

Android should use the same two functions with the same JWT:

1. After login, `POST get-api-key`. If 200, store the key in app-private storage and skip paste.
2. If 404, show paste, then `POST save-groq-key`.
3. On logout, delete the local key only.

Do not read `user_groq_keys` from the Android client.

---

## Shared Supabase project (read this)

`paid-branch` and `byok-version` currently share **Riff-production**.

Live `get-api-key` is the **BYOK** version (user’s wrapped key, or 404). A Mac build from `paid-branch` will **not** receive a Riff-managed Groq lease from this project until the backends are split.

Do not point `paid-branch` at this `get-api-key` and expect the old paid lease.

---

## Checklist if something breaks

| Symptom | Likely cause |
|---|---|
| Paste succeeds locally but key is gone after reinstall + login | `save-groq-key` failed: missing wrap secret, 401, or network. Check Edge Function logs. |
| Login always asks to paste again | 404 from `get-api-key` — no row, or unwrap failed after a secret rotation. |
| 500 from save or get | `ENCRYPTION_SECRET` / `API_KEY_WRAP_SECRET` missing or changed. |
| Key still on the Mac after Sign out | Old Control Center binary without `clearLocalApiKey`. Rebuild from `byok-version`. |
| Paid Mac app cannot fetch a managed key | Expected on this shared project. Use `paid-branch` only with a separate backend. |

Rebuild Control Center from this branch before testing the UI. Python-only runs pick up `auth_manager.py` immediately; the Swift onboarding/Account screens need a new `RiffControlCenter.app`.

---

## Code map

| Piece | Path |
|---|---|
| Wrap / unwrap | `supabase/functions/_shared/crypto.ts` |
| Save | `supabase/functions/save-groq-key/index.ts` |
| Restore | `supabase/functions/get-api-key/index.ts` |
| Table | `supabase/migrations/013_user_groq_keys.sql` |
| Mac auth + cloud sync | `config_ui/RiffControlCenter/SwiftAuthManager.swift` |
| Onboarding paste / skip | `config_ui/RiffControlCenter/OnboardingView.swift` |
| Replace key | `config_ui/RiffControlCenter/AccountView.swift` |
| Tray restore + logout wipe | `utils/auth_manager.py` |
| Agent rules for this branch | `.cursor/rules/byok-version.mdc` |
