import sys
import subprocess
import threading
from typing import Dict

# Try imports for macOS permissions
try:
    from AVFoundation import AVCaptureDevice, AVMediaTypeAudio, AVAuthorizationStatusAuthorized, AVAuthorizationStatusNotDetermined, AVAuthorizationStatusDenied, AVAuthorizationStatusRestricted
    from ApplicationServices import AXIsProcessTrusted, AXIsProcessTrustedWithOptions
    _HAS_PYOBJC = True
except ImportError as e:
    _HAS_PYOBJC = False
    
import logging
if not _HAS_PYOBJC:
    logging.warning("PyObjC frameworks not found/imported")
else:
    logging.info("PyObjC frameworks loaded successfully")

class PermissionManager:
    def __init__(self):
        self.platform = sys.platform
        
    def check_microphone(self) -> bool:
        if self.platform != "darwin" or not _HAS_PYOBJC:
            return True # Assume true on non-mac or if dependencies missing
            
        status = AVCaptureDevice.authorizationStatusForMediaType_(AVMediaTypeAudio)
        return status == AVAuthorizationStatusAuthorized

    def open_microphone_settings(self):
        # Opens System Settings -> Privacy & Security -> Microphone
        subprocess.run(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"])

    def open_accessibility_settings(self):
        # Opens System Settings -> Privacy & Security -> Accessibility
        subprocess.run(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"])

    def open_automation_settings(self):
        # Opens System Settings -> Privacy & Security -> Automation
        subprocess.run(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"])

    def open_input_monitoring_settings(self):
        # Opens System Settings -> Privacy & Security -> Input Monitoring
        subprocess.run(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"])
        
    # Maintain legacy request methods for compatibility but redirect to settings
    def request_microphone(self):
        self.open_microphone_settings()

    def request_accessibility(self):
        self.open_accessibility_settings()

    def request_automation(self):
        self.open_automation_settings()

    def check_accessibility(self) -> bool:
        if self.platform != "darwin" or not _HAS_PYOBJC:
            return True
            
        return AXIsProcessTrusted()

    def check_automation(self) -> bool:
        # Automation is hard to check without triggering. 
        # We'll assume if we can't control System Events, we don't have it.
        # But for 'checklist' purposes, we might just have to skip or use a heuristic.
        # A simple heuristic: try to verify if we can send a benign event?
        # For now, let's return False if not sure, or maybe just omit checking it strictly 
        # because checking it might trigger a prompt. 
        # User wants a checklist.
        return False # Placeholder
            
    def get_all_status(self) -> Dict[str, bool]:
        return {
            "microphone": self.check_microphone(),
            "accessibility": self.check_accessibility(),
            # Automation is tricky, maybe exclude from auto-check or always show valid?
            # Or just check accessibility as a proxy for "power user" perms?
            # Let's keep automation but default to False until we find a good check.
            "automation": self.check_automation() 
        }
