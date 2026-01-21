import logging
from pynput.keyboard import Controller, Key
import pyperclip
import time
import platform
import subprocess

class TextInjector:
    def __init__(self, use_clipboard=True):
        self.keyboard = Controller()
        self.use_clipboard = use_clipboard
        self.is_mac = platform.system() == "Darwin"
        logging.info(f"[Injector] Init: Clipboard={use_clipboard}, OS={platform.system()}")

    def inject(self, text: str):
        if not text:
            return

        logging.info(f"[Injector] Inserting {len(text)} chars...")
        
        # Use clipboard for long text or if forced
        # "Race to the Paste" Fix: Raised threshold to 300 to prefer typing
        if self.use_clipboard or len(text) > 300:
            logging.info("[Injector] Strategy: Clipboard Paste")
            self.inject_via_clipboard(text)
        else:
            logging.info("[Injector] Strategy: Direct Typing")
            self.type_text(text)
            
        logging.info("[Injector] Done")

    def type_text(self, text: str):
        # Type character by character
        for char in text:
            self.keyboard.type(char)
            # Adaptive Typing: Slower speed (0.01s) for reliability
            time.sleep(0.01)

    def inject_via_clipboard(self, text: str):
        # Save current clipboard
        try:
            old_clipboard = pyperclip.paste()
        except:
            old_clipboard = ""
            
        # Copy to clipboard
        pyperclip.copy(text)
        time.sleep(0.1) # Wait for clipboard to update
        
        # Simulate paste (Cmd+V or Ctrl+V)
        if self.is_mac:
            try:
                subprocess.run(["osascript", "-e", 'tell application "System Events" to keystroke "v" using command down'], check=True)
            except Exception as e:
                logging.warning(f"[Injector] AppleScript paste failed: {e}")
                # Fallback to pynput
                try:
                    with self.keyboard.pressed(Key.cmd):
                        self.keyboard.press('v')
                        self.keyboard.release('v')
                except Exception as ex:
                    logging.error(f"[Injector] Pynput paste failed: {ex}")
                    logging.info("[Injector] Falling back to typing...")
                    self.type_text(text)
        else:
            modifier = Key.ctrl
            with self.keyboard.pressed(modifier):
                self.keyboard.press('v')
                self.keyboard.release('v')
            
        # Restore clipboard after a moment
        # "Race to the Paste" Fix: Increased buffer to 0.8s
        time.sleep(0.8)
        try:
            pyperclip.copy(old_clipboard)
        except:
            pass

def main():
    injector = TextInjector()
    print("Will type in 3 seconds... switch to a text editor!")
    time.sleep(3)
    injector.inject("Hello from EchoFlow! This text was injected automatically.")

if __name__ == "__main__":
    main()
