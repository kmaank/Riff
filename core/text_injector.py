import logging
from pynput.keyboard import Controller, Key
import pyperclip
import time
import platform
import threading

class TextInjector:
    def __init__(self, use_clipboard=True):
        self.keyboard = Controller()
        self.use_clipboard = use_clipboard
        self.is_mac = platform.system() == "Darwin"
        self.last_error = None
        logging.info(f"[Injector] Init: Clipboard={use_clipboard}, OS={platform.system()}")

    def inject(self, text: str) -> bool:
        if not text:
            return False

        self.last_error = None
        logging.info(f"[Injector] Inserting {len(text)} chars...")

        if not self.has_keyboard_focus():
            logging.warning("[Injector] No focused text field — skipping paste")
            self.last_error = "no_focus"
            return False

        try:
            if len(text) > 5000:
                logging.info("[Injector] Strategy: Chunked Clipboard Paste (text > 5000 chars)")
                ok = self.inject_via_chunked_clipboard(text)
            elif self.use_clipboard or len(text) > 300:
                logging.info("[Injector] Strategy: Clipboard Paste")
                ok = self.inject_via_clipboard(text)
            else:
                logging.info("[Injector] Strategy: Direct Typing")
                self.type_text(text)
                ok = True
        except Exception as e:
            logging.error(f"[Injector] Failed: {e}", exc_info=True)
            self.last_error = "paste_failed"
            return False

        if not ok:
            self.last_error = self.last_error or "paste_failed"
        logging.info(f"[Injector] Done success={ok} last_error={self.last_error}")
        return ok

    def type_text(self, text: str):
        # Type character by character
        for char in text:
            self.keyboard.type(char)
            # Adaptive Typing: Slower speed (0.01s) for reliability
            time.sleep(0.01)

    def inject_via_chunked_clipboard(self, text: str, chunk_size: int = 4000):
        """
        Inject very long text by splitting into chunks and pasting sequentially.
        This prevents clipboard/app limitations for texts > 5000 chars.
        """
        # Save current clipboard
        try:
            old_clipboard = pyperclip.paste()
        except:
            old_clipboard = ""

        # Split text into chunks
        chunks = [text[i:i + chunk_size] for i in range(0, len(text), chunk_size)]
        total_chunks = len(chunks)
        logging.info(f"[Injector] Splitting into {total_chunks} chunks of ~{chunk_size} chars")

        for i, chunk in enumerate(chunks):
            logging.info(f"[Injector] Pasting chunk {i+1}/{total_chunks} ({len(chunk)} chars)...")

            pyperclip.copy(chunk)
            time.sleep(0.15)

            if not self._do_paste():
                logging.error(f"[Injector] Chunk {i+1}/{total_chunks} paste failed")
                return False

            if i < total_chunks - 1:
                time.sleep(0.3)

        self._restore_clipboard(old_clipboard, delay=0.2)
        logging.info(f"[Injector] Chunked paste complete: {total_chunks} chunks pasted")
        return True

    def has_keyboard_focus(self) -> bool:
        """True if some UI element is focused, or if we cannot tell (don't block paste)."""
        if not self.is_mac:
            return True
        try:
            from ApplicationServices import AXUIElementCreateSystemWide, AXUIElementCopyAttributeValue
            system = AXUIElementCreateSystemWide()
            result = AXUIElementCopyAttributeValue(system, "AXFocusedUIElement")
            focused = None
            err = 0
            if isinstance(result, tuple):
                if len(result) >= 2:
                    err, focused = result[0], result[1]
                elif result:
                    focused = result[0]
            else:
                focused = result
            if err not in (0, None) and focused is None:
                logging.debug("[Injector] AX focus check err=%s — assuming focused", err)
                return True
            if focused is None:
                logging.warning("[Injector] No focused UI element (err=%s) — pasting anyway", err)
                return True
            return True
        except Exception as e:
            logging.debug("[Injector] Focus check unavailable: %s", e)
            return True

    def _restore_clipboard(self, old_clipboard, delay=0.2):
        def restore():
            time.sleep(delay)
            try:
                pyperclip.copy(old_clipboard)
            except Exception:
                pass

        threading.Thread(target=restore, daemon=True, name="riff-clipboard-restore").start()

    def _do_paste(self) -> bool:
        """Paste via the same Accessibility key events as the hotkey. Skip AppleScript."""
        try:
            modifier = Key.cmd if self.is_mac else Key.ctrl
            with self.keyboard.pressed(modifier):
                self.keyboard.press('v')
                self.keyboard.release('v')
            return True
        except Exception as e:
            logging.error("[Injector] Paste failed: %s", e)
            return False

    def inject_via_clipboard(self, text: str) -> bool:
        try:
            old_clipboard = pyperclip.paste()
        except Exception:
            old_clipboard = ""

        pyperclip.copy(text)
        time.sleep(0.1)

        pasted = self._do_paste()
        self._restore_clipboard(old_clipboard, delay=0.2)
        return pasted

def main():
    injector = TextInjector()
    print("Will type in 3 seconds... switch to a text editor!")
    time.sleep(3)
    injector.inject("Hello from EchoFlow! This text was injected automatically.")

if __name__ == "__main__":
    main()
