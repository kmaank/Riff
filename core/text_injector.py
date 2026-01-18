
from pynput.keyboard import Controller, Key
import pyperclip
import time
import platform

class TextInjector:
    def __init__(self, use_clipboard=True):
        self.keyboard = Controller()
        self.use_clipboard = use_clipboard
        self.is_mac = platform.system() == "Darwin"

    def inject(self, text: str):
        if not text:
            return

        print("[Injecting text...]")
        
        # Use clipboard for long text or if forced
        if self.use_clipboard or len(text) > 100:
            self.inject_via_clipboard(text)
        else:
            self.type_text(text)
            
        print("[Done]")

    def type_text(self, text: str):
        # Type character by character
        for char in text:
            self.keyboard.type(char)
            time.sleep(0.005) # Tiny delay for realism/reliability

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
            import subprocess
            try:
                subprocess.run(["osascript", "-e", 'tell application "System Events" to keystroke "v" using command down'], check=True)
            except Exception as e:
                print(f"AppleScript paste failed: {e}")
                # Fallback to pynput
                try:
                    with self.keyboard.pressed(Key.cmd):
                        self.keyboard.press('v')
                        self.keyboard.release('v')
                except Exception as ex:
                    print(f"Pynput paste failed: {ex}")
                    print("Falling back to typing...")
                    self.type_text(text)
        else:
            modifier = Key.ctrl
            with self.keyboard.pressed(modifier):
                self.keyboard.press('v')
                self.keyboard.release('v')
            
        # Restore clipboard after a moment
        time.sleep(0.5)
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
