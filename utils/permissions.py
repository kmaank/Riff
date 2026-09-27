import json
import logging
import os
import sys
import subprocess
import time
from typing import Dict

try:
    from AVFoundation import (
        AVCaptureDevice,
        AVMediaTypeAudio,
        AVAuthorizationStatusAuthorized,
    )
    from ApplicationServices import AXIsProcessTrusted, AXIsProcessTrustedWithOptions
    _HAS_PYOBJC = True
except ImportError:
    _HAS_PYOBJC = False

try:
    from Quartz import CGPreflightListenEventAccess, CGRequestListenEventAccess
    _HAS_QUARTZ = True
except ImportError:
    _HAS_QUARTZ = False
    CGPreflightListenEventAccess = None
    CGRequestListenEventAccess = None

if not _HAS_PYOBJC:
    logging.warning("PyObjC frameworks not found/imported")
else:
    logging.info("PyObjC frameworks loaded successfully")


MIC_LIVE_RMS = 0.0005
MIC_DEAD_RMS = 0.00001


class PermissionManager:
    def __init__(self, status_path: str = None):
        self.platform = sys.platform
        self.status_path = status_path
        self._mic_proof_path = (
            os.path.join(os.path.dirname(status_path), "mic_verified.json") if status_path else None
        )
        self._mic_verified = self._load_mic_proof()
        self._logged_mic_status = None

    def _load_mic_proof(self) -> bool:
        if not self._mic_proof_path or not os.path.exists(self._mic_proof_path):
            return False
        try:
            with open(self._mic_proof_path, "r") as f:
                return bool(json.load(f).get("verified"))
        except Exception:
            return False

    def note_recording_level(self, peak_rms: float):
        """PortAudio can record while AVFoundation still reports not-determined.
        Real signal proves access; digital silence means macOS is feeding zeros."""
        if peak_rms >= MIC_LIVE_RMS:
            verified = True
        else:
            return
        if verified == self._mic_verified:
            return
        self._mic_verified = verified
        logging.info("[Permissions] Microphone verified from recording=%s (peak=%.5f)", verified, peak_rms)
        if self._mic_proof_path:
            try:
                with open(self._mic_proof_path, "w") as f:
                    json.dump({"verified": verified, "updated_at": time.time()}, f)
            except OSError:
                pass
        self.write_status()

    def check_microphone(self) -> bool:
        if self.platform != "darwin" or not _HAS_PYOBJC:
            return True
        status = AVCaptureDevice.authorizationStatusForMediaType_(AVMediaTypeAudio)
        if status != self._logged_mic_status:
            self._logged_mic_status = status
            logging.info("[Permissions] AVFoundation microphone status=%s verified=%s", status, self._mic_verified)
        return status == AVAuthorizationStatusAuthorized or self._mic_verified

    def prompt_microphone(self):
        if self.platform != "darwin" or not _HAS_PYOBJC:
            return
        logging.info("[Permissions] Requesting microphone from Riff process")
        AVCaptureDevice.requestAccessForMediaType_completionHandler_(
            AVMediaTypeAudio, lambda granted: logging.info("[Permissions] Microphone granted=%s", granted)
        )

    def open_microphone_settings(self):
        subprocess.run(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"])

    def open_accessibility_settings(self):
        subprocess.run(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"])

    def open_input_monitoring_settings(self):
        subprocess.run(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"])

    def request_microphone(self):
        self.prompt_microphone()
        self.open_microphone_settings()

    def request_accessibility(self):
        self.prompt_accessibility()
        self.open_accessibility_settings()

    def request_input_monitoring(self):
        self.prompt_input_monitoring()
        self.open_input_monitoring_settings()

    def check_accessibility(self) -> bool:
        if self.platform != "darwin" or not _HAS_PYOBJC:
            return True
        return bool(AXIsProcessTrusted())

    def prompt_accessibility(self):
        """Prompt as the Riff tray app (com.riff.app), not Control Center."""
        if self.platform != "darwin" or not _HAS_PYOBJC:
            return
        logging.info("[Permissions] Accessibility prompt from Riff process")
        try:
            AXIsProcessTrustedWithOptions({"AXTrustedCheckOptionPrompt": True})
        except Exception as e:
            logging.warning("[Permissions] Accessibility prompt failed: %s", e)

    def check_input_monitoring(self) -> bool:
        if self.platform != "darwin" or not _HAS_QUARTZ or CGPreflightListenEventAccess is None:
            return True
        try:
            return bool(CGPreflightListenEventAccess())
        except Exception as e:
            logging.warning("[Permissions] Input monitoring check failed: %s", e)
            return False

    def prompt_input_monitoring(self):
        if self.platform != "darwin" or not _HAS_QUARTZ or CGRequestListenEventAccess is None:
            return
        logging.info("[Permissions] Input Monitoring prompt from Riff process")
        try:
            CGRequestListenEventAccess()
        except Exception as e:
            logging.warning("[Permissions] Input monitoring prompt failed: %s", e)

    def get_all_status(self) -> Dict[str, bool]:
        if not self._mic_verified:
            self._mic_verified = self._load_mic_proof()
        return {
            "microphone": self.check_microphone(),
            "accessibility": self.check_accessibility(),
            "input_monitoring": self.check_input_monitoring(),
        }

    def write_status(self):
        if not self.status_path:
            return
        payload = self.get_all_status()
        payload["updated_at"] = time.time()
        payload["mic_verified"] = bool(self._mic_verified)
        payload["app"] = "Riff"
        payload["bundle_id"] = "com.riff.app"
        if self.platform == "darwin" and _HAS_PYOBJC:
            raw = AVCaptureDevice.authorizationStatusForMediaType_(AVMediaTypeAudio)
            payload["microphone_status"] = {
                0: "not_determined",
                1: "restricted",
                2: "denied",
                3: "authorized",
            }.get(int(raw) if raw is not None else -1, str(raw))
        tmp = self.status_path + ".tmp"
        try:
            os.makedirs(os.path.dirname(self.status_path), exist_ok=True)
            with open(tmp, "w") as f:
                json.dump(payload, f)
            os.replace(tmp, self.status_path)
        except Exception as e:
            logging.debug("[Permissions] Could not write status: %s", e)
