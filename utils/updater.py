"""Check GitHub Releases and replace this app with the latest notarized DMG."""

import json
import logging
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

REPO = "kmaank/Riff"
API_URL = f"https://api.github.com/repos/{REPO}/releases/latest"
STATUS_NAME = "update_status.json"
REQUEST_NAME = "update_install.request"


def version_tuple(value):
    text = str(value or "").strip().lstrip("vV")
    parts = []
    for piece in text.split("."):
        digits = ""
        for ch in piece:
            if ch.isdigit():
                digits += ch
            else:
                break
        if digits == "":
            break
        parts.append(int(digits))
    return tuple(parts) or (0,)


def app_bundle_path():
    if not getattr(sys, "frozen", False):
        return None
    return os.path.abspath(os.path.join(os.path.dirname(sys.executable), "..", ".."))


def current_version():
    bundle = app_bundle_path()
    if not bundle and os.path.isdir("/Applications/Riff.app"):
        bundle = "/Applications/Riff.app"
    plist_path = os.path.join(bundle, "Contents", "Info.plist") if bundle else ""
    if plist_path and os.path.exists(plist_path):
        try:
            with open(plist_path, "rb") as handle:
                return str(plistlib.load(handle).get("CFBundleShortVersionString") or "0.0.0")
        except Exception:
            logging.debug("[Update] Could not read Info.plist", exc_info=True)
    return "0.0.0"


class AppUpdater:
    def __init__(self, support_dir):
        self.support_dir = support_dir
        self.status_path = os.path.join(support_dir, STATUS_NAME)
        self.request_path = os.path.join(support_dir, REQUEST_NAME)
        self._installing = False
        self.latest = None

    def check(self):
        current = current_version()
        payload = {
            "current": current,
            "latest": current,
            "available": False,
            "state": "idle",
            "message": "",
            "download_url": "",
            "checked_at": time.time(),
        }
        try:
            request = urllib.request.Request(
                API_URL,
                headers={
                    "User-Agent": f"Riff/{current}",
                    "Accept": "application/vnd.github+json",
                },
            )
            with urllib.request.urlopen(request, timeout=20) as response:
                data = json.loads(response.read().decode("utf-8"))
            if data.get("draft") or data.get("prerelease"):
                self._write(payload)
                return payload
            latest = str(data.get("tag_name") or "").lstrip("vV")
            asset = _dmg_asset(data.get("assets") or [])
            payload["latest"] = latest or current
            if asset and version_tuple(latest) > version_tuple(current):
                payload["available"] = True
                payload["state"] = "available"
                payload["download_url"] = asset
                payload["message"] = f"Riff {latest} is available."
                self.latest = payload
                logging.info("[Update] %s -> %s", current, latest)
            else:
                logging.info("[Update] Up to date (%s)", current)
        except Exception as exc:
            payload["state"] = "error"
            payload["message"] = "Could not check for updates."
            logging.warning("[Update] Check failed: %s", exc)
        self._write(payload)
        self.latest = payload
        return payload

    def consume_request(self):
        if self._installing or not os.path.exists(self.request_path):
            return False
        try:
            os.remove(self.request_path)
        except OSError:
            return False
        return True

    def install(self, quit_callback):
        if self._installing:
            return
        self._installing = True
        info = self.latest or self.check()
        url = info.get("download_url") or ""
        latest = info.get("latest") or ""
        if not info.get("available") or not url.startswith("https://"):
            self._write({**info, "state": "error", "message": "No update to install."})
            self._installing = False
            return
        bundle = app_bundle_path()
        if not bundle or not bundle.endswith(".app"):
            self._write({**info, "state": "error", "message": "Updates install only from the Riff.app build."})
            self._installing = False
            return
        try:
            self._write({**info, "state": "downloading", "message": f"Downloading Riff {latest}…"})
            staged = self._stage_app(url)
            self._write({**info, "state": "installing", "message": "Installing. Riff will reopen."})
            _launch_swap(staged, bundle)
            quit_callback()
        except Exception as exc:
            logging.error("[Update] Install failed: %s", exc, exc_info=True)
            self._write({**info, "state": "error", "message": f"Update failed: {exc}"})
            self._installing = False

    def _stage_app(self, url):
        work = tempfile.mkdtemp(prefix="riff-update-")
        dmg_path = os.path.join(work, "Riff.dmg")
        mount = os.path.join(work, "mnt")
        staged = os.path.join(work, "Riff.app")
        os.makedirs(mount, exist_ok=True)
        request = urllib.request.Request(url, headers={"User-Agent": f"Riff/{current_version()}"})
        with urllib.request.urlopen(request, timeout=120) as response, open(dmg_path, "wb") as out:
            shutil.copyfileobj(response, out)
        subprocess.run(
            ["hdiutil", "attach", dmg_path, "-nobrowse", "-readonly", "-mountpoint", mount],
            check=True,
            capture_output=True,
        )
        try:
            source = os.path.join(mount, "Riff.app")
            if not os.path.isdir(source):
                raise RuntimeError("The release DMG does not contain Riff.app")
            subprocess.run(["ditto", source, staged], check=True)
        finally:
            subprocess.run(["hdiutil", "detach", mount, "-force"], capture_output=True)
        verify = subprocess.run(["codesign", "--verify", "--deep", "--strict", staged], capture_output=True)
        if verify.returncode != 0:
            raise RuntimeError("Downloaded app failed signature check")
        return staged

    def _write(self, payload):
        try:
            os.makedirs(self.support_dir, exist_ok=True)
            tmp = self.status_path + ".tmp"
            with open(tmp, "w") as handle:
                json.dump(payload, handle)
            os.replace(tmp, self.status_path)
        except OSError:
            logging.debug("[Update] Could not write status", exc_info=True)


def _dmg_asset(assets):
    for asset in assets:
        name = str(asset.get("name") or "")
        url = str(asset.get("browser_download_url") or "")
        if name.endswith(".dmg") and name.startswith("Riff") and url.startswith("https://github.com/"):
            return url
    return ""


def _launch_swap(staged, destination):
    script = f"""#!/bin/bash
set -euo pipefail
for _ in $(seq 1 80); do
  if ! pgrep -x Riff >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
pkill -x RiffControlCenter >/dev/null 2>&1 || true
sleep 0.4
rm -rf "{destination}.new"
ditto "{staged}" "{destination}.new"
rm -rf "{destination}"
mv "{destination}.new" "{destination}"
open "{destination}"
"""
    path = os.path.join(tempfile.gettempdir(), "riff-apply-update.sh")
    with open(path, "w") as handle:
        handle.write(script)
    os.chmod(path, 0o755)
    subprocess.Popen(
        ["/bin/bash", path],
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
