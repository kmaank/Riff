#!/usr/bin/env python3
"""Push Riff auth email templates to the hosted Supabase project.

Requires SUPABASE_ACCESS_TOKEN from https://supabase.com/dashboard/account/tokens
"""
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

PROJECT_REF = "yrsviodciuepunofxoja"
TEMPLATES = Path(__file__).resolve().parent / "templates"


def read_html(name: str) -> str:
    return (TEMPLATES / name).read_text(encoding="utf-8").strip()


def main() -> int:
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if not token:
        print("Set SUPABASE_ACCESS_TOKEN and run again.", file=sys.stderr)
        return 1

    payload = {
        "smtp_sender_name": "Riff",
        "mailer_subjects_confirmation": "Confirm your Riff email",
        "mailer_templates_confirmation_content": read_html("confirmation.html"),
        "mailer_subjects_recovery": "Reset your Riff password",
        "mailer_templates_recovery_content": read_html("recovery.html"),
        "mailer_subjects_magic_link": "Your Riff sign-in link",
        "mailer_templates_magic_link_content": read_html("magic_link.html"),
        "mailer_subjects_email_change": "Confirm your new Riff email",
        "mailer_templates_email_change_content": read_html("email_change.html"),
    }

    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{PROJECT_REF}/config/auth",
        data=json.dumps(payload).encode("utf-8"),
        method="PATCH",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            print(f"Updated auth email templates ({resp.status})")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        print(f"Failed {exc.code}: {body[:400]}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
