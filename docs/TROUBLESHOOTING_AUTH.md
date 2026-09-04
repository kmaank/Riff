# Authentication Troubleshooting Guide

## Where is the config file?

- **Path**: `~/Library/Application Support/Riff/config.json`
- **Open in Finder**: Press **Cmd+Shift+G**, paste `~/Library/Application Support/Riff`, press Enter
- **Open in Terminal**: `open ~/Library/Application\ Support/Riff/config.json`
- **If it doesn't exist**: Run Riff once (e.g. `python main.py` or launch the app) so it creates the config. Or create the folder: `mkdir -p ~/Library/Application\ Support/Riff` and add a minimal `config.json` with your Supabase credentials.

---

## 1. "Signup failed" / "Invalid API key" (HTTP 401)

**Symptom**: Email signup or sign-in fails with a generic error. `debug_auth.log` shows:
```
Signup failed HTTP 401: {"message":"Invalid API key","hint":"Double check your Supabase `anon` or `service_role` API key."}
```

**Cause**: The Supabase anon key in your config is invalid, expired, or from a different/rotated project.

**Fix**:
1. Open [Supabase Dashboard](https://supabase.com/dashboard) → select your project
2. Go to **Project Settings** (gear icon) → **API**
3. Copy the **anon public** key (starts with `eyJ...`)
4. Edit the config file. It’s at:
   - **Path**: `~/Library/Application Support/Riff/config.json`
   - **Full path**: `/Users/YOUR_USERNAME/Library/Application Support/Riff/config.json`
   - **Open in Finder**: Cmd+Shift+G, paste the path, press Enter
   - **Open in Terminal**: `open ~/Library/Application\ Support/Riff/config.json`
   - If the file doesn’t exist yet, run Riff once so it creates the config, or create the folder and file manually
5. Update the `auth.supabase_anon_key` value with your new key
6. Restart Riff and try again

**Also check**: If your Supabase project was paused (free tier inactivity), restore it from the Dashboard first.

---

## 2. Email confirmation: "Site cannot be reached" / redirects to localhost

**Symptom**: After signing up, you get "Check your email!" and click "Confirm your mail" in the email. The link opens but shows "Site cannot be reached" or goes to `localhost:3000` instead of opening Riff.

**Cause**: Supabase uses its default Site URL (often `localhost:3000`) when no custom redirect is used. The app sends `emailRedirectTo: riff://auth/callback` on signup; if the redirect still goes to localhost, the Supabase project needs configuration changes.

**Fix** (do all of these):

1. **Redirect URLs**  
   In [Supabase Dashboard](https://supabase.com/dashboard) → **Authentication** → **URL Configuration**, add `riff://auth/callback` to **Redirect URLs**.

2. **Site URL**  
   Change **Site URL** from `http://localhost:3000` to `riff://` so the default fallback opens the app. (Required when `emailRedirectTo` isn’t applied, e.g. old templates.)

3. **Email template**  
   Go to **Authentication** → **Email Templates** → **Confirm signup**. Ensure the link uses `{{ .ConfirmationURL }}` (not `{{ .SiteURL }}`). Example:
   ```html
   <a href="{{ .ConfirmationURL }}">Confirm your mail</a>
   ```
   The `ConfirmationURL` variable includes the redirect; `SiteURL` does not.

4. **Rebuild and retry**  
   Rebuild the app (`cd config_ui && bash build_ui.sh`), then sign up again with a new email.

**Note**: Confirmation links expire (typically 24 hours). If you see "Email link is invalid or has expired", sign up again to get a fresh link.

---

## 3. "Unsupported provider: provider is not enabled" (GitHub / Apple OAuth)

**Symptom**: Clicking "Continue with GitHub" or "Continue with Apple" returns:
```json
{"code":400,"error_code":"validation_failed","msg":"Unsupported provider: provider is not enabled"}
```

**Cause**: GitHub and Apple OAuth are not enabled in your Supabase project.

**Fix**:
1. Open [Supabase Dashboard](https://supabase.com/dashboard) → your project
2. Go to **Authentication** → **Providers**
3. Enable **GitHub**: Add GitHub OAuth App credentials (Client ID + Secret)
4. Enable **Apple**: Add Apple Service ID and key
5. Add redirect URL: `riff://oauth/callback` in each provider's settings
6. In Supabase **Authentication** → **URL Configuration**, add `riff://oauth/callback` to **Redirect URLs**

---

## 4. "Email rate limit exceeded"

**Symptom**: Signup fails with "email rate limit exceeded". You may also not receive confirmation emails for recent signup attempts.

**Cause**: Supabase's built-in email service has a strict rate limit (about 2 emails per hour per project on free tier). Multiple signup attempts in a short time—or previous failed attempts—quickly hit this limit. Once hit, no more emails are sent until the window resets.

**Fix**:

1. **Wait 1–2 hours**  
   The limit usually resets after about an hour. Avoid further signup attempts until then.

2. **Use a different signup method**  
   If Google, GitHub, or Apple OAuth are enabled, use "Continue with Google" (or another provider) instead. OAuth does not use the email rate limit.

3. **Set up custom SMTP** (best for ongoing use)  
   Supabase → **Project Settings** → **Authentication** → **SMTP Settings**  
   Configure your own SMTP (e.g. Resend, SendGrid, Mailgun) to remove the default rate limit and improve deliverability.

4. **Confirm previous attempts**  
   If you signed up earlier and got a confirmation email:
   - Check spam/junk
   - Use the link within 24 hours (it expires)
   - If expired or missing, wait for the rate limit to reset, then sign up again with the same or a new email

---

## 5. Google OAuth: "525 SSL handshake failed"

**Symptom**: Clicking "Continue with Google" shows a Cloudflare error page:
```
525: SSL handshake failed
Cloudflare is unable to establish an SSL connection to the origin server.
```

**Cause**: Infrastructure issue between Cloudflare and Supabase's origin. Can be:
- Temporary Supabase/Cloudflare outage
- Project paused or unhealthy
- Regional connectivity (e.g. from India) – sometimes intermittent

**Fix**:
1. **Wait and retry** – often resolves on its own
2. **Check project status**: Supabase Dashboard → ensure project is not paused
3. **Try a VPN** – if you're in a region with known connectivity issues
4. **Use email/password** – works once the API key is fixed (see #1)

---

## Quick Reference

| Issue | Where to fix |
|-------|--------------|
| Invalid API key | Edit `~/Library/Application Support/Riff/config.json` → `auth.supabase_anon_key` (open via Finder Cmd+Shift+G or `open ~/Library/Application\ Support/Riff/config.json`) |
| Email rate limit exceeded | Wait 1–2 hours, use OAuth instead, or configure custom SMTP in Supabase |
| OAuth providers disabled | Supabase Dashboard → Authentication → Providers |
| OAuth redirect | Supabase → Auth → URL Configuration → Redirect URLs: `riff://oauth/callback`, `riff://auth/callback` |
| Project paused | Supabase Dashboard → Restore project |

---

**Logs**: Check `~/Documents/Riff/debug_auth.log` for detailed auth debugging.
