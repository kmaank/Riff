"""Floating recording HUD: timer, waveform, working/done/error.

Lives in the Riff tray process (not Control Center) so it never creates a
second TCC identity. Click-through, non-activating, always on top.
"""

from __future__ import annotations

import json
import logging
import math
import os
import threading
import time

try:
    import objc
    from AppKit import (
        NSBezierPath,
        NSColor,
        NSFont,
        NSFontAttributeName,
        NSForegroundColorAttributeName,
        NSMutableParagraphStyle,
        NSPanel,
        NSParagraphStyleAttributeName,
        NSScreen,
        NSStatusWindowLevel,
        NSView,
        NSWindowCollectionBehaviorCanJoinAllSpaces,
        NSWindowCollectionBehaviorFullScreenAuxiliary,
        NSWindowCollectionBehaviorIgnoresCycle,
        NSWindowCollectionBehaviorStationary,
    )
    from Foundation import (
        NSMakeRect,
        NSObject,
        NSString,
        NSThread,
    )
    _HAS_APPKIT = True
except Exception as exc:  # pragma: no cover - missing PyObjC in some test envs
    logging.warning("[HUD] AppKit unavailable: %s", exc)
    _HAS_APPKIT = False
    objc = None
    NSView = object
    NSPanel = object
    NSObject = object
    NSString = str


HUD_WIDTH = 340.0
HUD_HEIGHT = 74.0
WAVE_BARS = 22
WAVE_LEFT = 86.0
WAVE_RIGHT = 228.0
BAR_WIDTH = 4.2
BAR_GAP = 2.4
CHIP_RIGHT_INSET = 14.0
NSWindowStyleMaskBorderless = 0
NSWindowStyleMaskNonactivatingPanel = 1 << 7
NSCenterTextAlignment = 1

_STATUS_NAME = "hud_status.json"


def _hotkey_style_label(style: str) -> str:
    name = (style or "casual").strip().lower()
    return {
        "casual": "Casual",
        "clean": "Clean",
        "formal": "Formal",
        "riff": "Riff",
    }.get(name, name.capitalize() or "Casual")


if _HAS_APPKIT:

    class _HudCanvas(NSView):
        def initWithOwner_(self, owner):
            self = objc.super(_HudCanvas, self).init()
            if self is None:
                return None
            self.owner = owner
            return self

        def isFlipped(self):
            return True

        def drawRect_(self, rect):
            owner = getattr(self, "owner", None)
            if owner is None:
                return
            owner._paint(self.bounds())

    class _MainInvoker(NSObject):
        def initWithCallback_(self, callback):
            self = objc.super(_MainInvoker, self).init()
            if self is None:
                return None
            self._callback = callback
            return self

        def invoke(self):
            cb = getattr(self, "_callback", None)
            if cb:
                try:
                    cb()
                except Exception:
                    logging.debug("[HUD] Main-thread callback failed", exc_info=True)


class RecordingHUD:
    def __init__(self, status_dir: str):
        self.status_path = os.path.join(status_dir, _STATUS_NAME)
        self._lock = threading.Lock()
        self._window = None
        self._canvas = None
        self._mode = "hidden"  # recording | working | done | error | nudge | hidden
        self._style = "casual"
        self._message = ""
        self._started_at = 0.0
        self._elapsed = 0.0
        self._levels = [0.08] * WAVE_BARS
        self._recorder = None
        self._pump_stop = threading.Event()
        self._pump_thread = None
        self._hide_timer = None
        self._last_status_write = 0.0
        self._attached = False
        self._invokers = []

    def attach(self):
        """Create the hidden panel on the AppKit main thread."""
        self._on_main(self._attach_unlocked)

    def show_recording(self, style: str, started_at: float, recorder=None):
        with self._lock:
            self._cancel_hide_unlocked()
            self._mode = "recording"
            self._style = style or "casual"
            self._message = ""
            self._started_at = started_at or time.time()
            self._elapsed = 0.0
            self._levels = [0.08] * WAVE_BARS
            self._recorder = recorder
            self._pump_stop.clear()
        self._start_pump()
        self._on_main(lambda: self._present())
        self._write_status(force=True)

    def show_working(self):
        with self._lock:
            self._cancel_hide_unlocked()
            self._mode = "working"
            self._message = "Working…"
            self._recorder = None
        self._stop_pump()
        self._on_main(lambda: self._present())
        self._write_status(force=True)

    def show_done(self):
        with self._lock:
            self._mode = "done"
            self._message = "Done"
            self._recorder = None
        self._stop_pump()
        self._on_main(lambda: self._present())
        self._write_status(force=True)
        self._hide_later(0.45)

    def show_error(self, message: str, persist: bool = False):
        with self._lock:
            self._mode = "error"
            self._message = message or "Something went wrong"
            self._recorder = None
        self._stop_pump()
        self._on_main(lambda: self._present())
        self._write_status(force=True)
        if not persist:
            self._hide_later(1.8)

    def show_nudge(self, message: str = "Hold a bit longer"):
        with self._lock:
            self._mode = "nudge"
            self._message = message
            self._recorder = None
        self._stop_pump()
        self._on_main(lambda: self._present())
        self._write_status(force=True)
        self._hide_later(1.35)

    def on_idle(self):
        with self._lock:
            mode = self._mode
        if mode in ("done", "error", "nudge"):
            return
        self.hide()

    def hide(self):
        with self._lock:
            self._cancel_hide_unlocked()
            self._mode = "hidden"
            self._message = ""
            self._recorder = None
        self._stop_pump()
        self._on_main(self._order_out)
        self._write_status(force=True)

    def snapshot(self) -> dict:
        with self._lock:
            return {
                "state": self._mode,
                "style": self._style,
                "message": self._message,
                "elapsed": round(self._elapsed, 2),
            }

    # --- internals ---

    def _on_main(self, fn):
        if not _HAS_APPKIT:
            return
        try:
            if NSThread.isMainThread():
                fn()
                return
        except Exception:
            pass
        try:
            inv = _MainInvoker.alloc().initWithCallback_(fn)
            self._invokers.append(inv)
            if len(self._invokers) > 24:
                self._invokers = self._invokers[-8:]
            inv.performSelectorOnMainThread_withObject_waitUntilDone_(b"invoke", None, False)
        except Exception:
            logging.debug("[HUD] Could not hop to main thread", exc_info=True)

    def _attach_unlocked(self):
        if not _HAS_APPKIT or self._window is not None:
            self._attached = True
            return
        try:
            screen = NSScreen.mainScreen()
            frame = screen.visibleFrame() if screen else NSMakeRect(0, 0, 800, 600)
            x = frame.origin.x + (frame.size.width - HUD_WIDTH) / 2.0
            y = frame.origin.y + frame.size.height - HUD_HEIGHT - 28.0
            panel = NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
                NSMakeRect(x, y, HUD_WIDTH, HUD_HEIGHT),
                NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel,
                2,  # NSBackingStoreBuffered
                False,
            )
            panel.setLevel_(NSStatusWindowLevel)
            panel.setOpaque_(False)
            panel.setBackgroundColor_(NSColor.clearColor())
            panel.setHasShadow_(True)
            panel.setIgnoresMouseEvents_(True)
            panel.setHidesOnDeactivate_(False)
            panel.setReleasedWhenClosed_(False)
            try:
                panel.setCollectionBehavior_(
                    NSWindowCollectionBehaviorCanJoinAllSpaces
                    | NSWindowCollectionBehaviorStationary
                    | NSWindowCollectionBehaviorIgnoresCycle
                    | NSWindowCollectionBehaviorFullScreenAuxiliary
                )
            except Exception:
                pass
            canvas = _HudCanvas.alloc().initWithOwner_(self)
            canvas.setFrame_(NSMakeRect(0, 0, HUD_WIDTH, HUD_HEIGHT))
            panel.setContentView_(canvas)
            self._window = panel
            self._canvas = canvas
            self._attached = True
            logging.info("[HUD] Panel ready")
        except Exception:
            logging.warning("[HUD] Failed to create panel", exc_info=True)

    def _present(self):
        self._attach_unlocked()
        if not self._window:
            return
        try:
            screen = NSScreen.mainScreen()
            if screen:
                frame = screen.visibleFrame()
                x = frame.origin.x + (frame.size.width - HUD_WIDTH) / 2.0
                y = frame.origin.y + frame.size.height - HUD_HEIGHT - 28.0
                self._window.setFrameOrigin_((x, y))
            self._window.orderFront_(None)
            if self._canvas:
                self._canvas.setNeedsDisplay_(True)
        except Exception:
            logging.debug("[HUD] Present failed", exc_info=True)

    def _order_out(self):
        if self._window:
            try:
                self._window.orderOut_(None)
            except Exception:
                pass

    def _redraw(self):
        if self._canvas is not None:
            try:
                self._canvas.setNeedsDisplay_(True)
            except Exception:
                pass

    def _start_pump(self):
        self._stop_pump()
        self._pump_stop.clear()

        def pump():
            while not self._pump_stop.is_set():
                recorder = None
                started = 0.0
                with self._lock:
                    if self._mode != "recording":
                        break
                    recorder = self._recorder
                    started = self._started_at
                target = []
                if recorder is not None and hasattr(recorder, "snapshot_levels"):
                    try:
                        raw, _rms = recorder.snapshot_levels()
                        peak = max(raw) if raw else 0.05
                        floor = max(peak, 0.02)
                        sampled = raw[-WAVE_BARS:] if raw else []
                        target = [min(1.0, (v / floor) ** 0.65) for v in sampled]
                    except Exception:
                        target = []
                while len(target) < WAVE_BARS:
                    target.insert(0, 0.06)
                target = target[-WAVE_BARS:]
                with self._lock:
                    prev = list(self._levels)
                    if len(prev) != len(target):
                        blended = target
                    else:
                        blended = []
                        for old, new in zip(prev, target):
                            alpha = 0.40 if new > old else 0.22
                            blended.append(old + (new - old) * alpha)
                    self._levels = blended
                    self._elapsed = max(0.0, time.time() - started)
                self._on_main(self._redraw)
                self._write_status()
                self._pump_stop.wait(0.08)

        self._pump_thread = threading.Thread(target=pump, daemon=True, name="riff-hud")
        self._pump_thread.start()

    def _stop_pump(self):
        self._pump_stop.set()

    def _hide_later(self, delay: float):
        with self._lock:
            self._cancel_hide_unlocked()

            def fire():
                with self._lock:
                    self._hide_timer = None
                self.hide()

            timer = threading.Timer(delay, fire)
            timer.daemon = True
            self._hide_timer = timer
            timer.start()

    def _cancel_hide_unlocked(self):
        timer = self._hide_timer
        self._hide_timer = None
        if timer:
            try:
                timer.cancel()
            except Exception:
                pass

    def _write_status(self, force: bool = False):
        now = time.time()
        if not force and (now - self._last_status_write) < 0.1:
            return
        self._last_status_write = now
        payload = self.snapshot()
        payload["updated_at"] = now
        tmp = self.status_path + ".tmp"
        try:
            os.makedirs(os.path.dirname(self.status_path), exist_ok=True)
            with open(tmp, "w") as fh:
                json.dump(payload, fh)
            os.replace(tmp, self.status_path)
        except Exception:
            logging.debug("[HUD] Status write failed", exc_info=True)

    def _paint(self, bounds):
        with self._lock:
            mode = self._mode
            style = self._style
            message = self._message
            elapsed = self._elapsed
            levels = list(self._levels)

        if mode == "hidden":
            return

        bg = NSColor.colorWithCalibratedRed_green_blue_alpha_(0.07, 0.08, 0.10, 0.92)
        path = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(bounds, 18, 18)
        bg.set()
        path.fill()

        if mode == "recording":
            self._draw_timer(elapsed)
            self._draw_wave(levels)
            self._draw_chip(_hotkey_style_label(style), riff=(style or "").lower() == "riff")
        elif mode == "working":
            self._draw_centered("Working…", subtitle=_hotkey_style_label(style))
        elif mode == "done":
            self._draw_centered("There you go", subtitle=None, check=True)
        else:
            self._draw_centered(message or "Hold a bit longer", subtitle=None)

    def _draw_timer(self, elapsed: float):
        minutes = int(elapsed) // 60
        seconds = int(elapsed) % 60
        text = "%d:%02d" % (minutes, seconds)
        attrs = {
            NSFontAttributeName: NSFont.monospacedDigitSystemFontOfSize_weight_(22.0, 0.5),
            NSForegroundColorAttributeName: NSColor.whiteColor(),
        }
        NSString.stringWithString_(text).drawAtPoint_withAttributes_((16, 24), attrs)

    def _draw_wave(self, levels):
        pitch = BAR_WIDTH + BAR_GAP
        fit = max(1, int((WAVE_RIGHT - WAVE_LEFT + BAR_GAP) / pitch))
        count = min(WAVE_BARS, fit, max(1, len(levels)))
        used = count * BAR_WIDTH + (count - 1) * BAR_GAP
        origin_x = WAVE_LEFT + max(0.0, (WAVE_RIGHT - WAVE_LEFT - used) / 2.0)
        base_y = 20.0
        max_h = 30.0
        idle = NSColor.colorWithCalibratedRed_green_blue_alpha_(1, 1, 1, 0.22)
        live = NSColor.colorWithCalibratedRed_green_blue_alpha_(1.0, 0.42, 0.38, 0.95)
        now = time.time()
        for i, raw in enumerate(levels[:count]):
            t = 0.08 + max(0.0, min(1.0, raw)) * 0.92
            t = max(t, 0.12 + 0.035 * math.sin(now * 3.2 + i * 0.4))
            h = 6.0 + t * max_h
            x = origin_x + i * pitch
            if x + BAR_WIDTH > WAVE_RIGHT + 0.5:
                break
            y = base_y + (max_h + 6.0 - h) / 2.0
            bar = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
                NSMakeRect(x, y, BAR_WIDTH, h), 1.6, 1.6
            )
            (live if t > 0.22 else idle).set()
            bar.fill()

    def _draw_chip(self, label: str, riff: bool = False):
        text = (label or "Casual")[:10]
        if riff:
            fill = NSColor.colorWithCalibratedRed_green_blue_alpha_(0.95, 0.35, 0.55, 0.95)
        else:
            fill = NSColor.colorWithCalibratedRed_green_blue_alpha_(1, 1, 1, 0.12)
        font = NSFont.systemFontOfSize_weight_(11.0, 0.5)
        attrs = {
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: NSColor.whiteColor(),
        }
        try:
            size = NSString.stringWithString_(text).sizeWithAttributes_(attrs)
            text_w = float(size.width)
            text_h = float(size.height)
        except Exception:
            text_w = 44.0
            text_h = 14.0
        pad_x = 12.0
        chip_w = max(58.0, min(88.0, text_w + pad_x * 2))
        chip_h = 24.0
        chip_x = HUD_WIDTH - CHIP_RIGHT_INSET - chip_w
        chip_y = 25.0
        chip = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
            NSMakeRect(chip_x, chip_y, chip_w, chip_h), 12, 12
        )
        fill.set()
        chip.fill()
        text_x = chip_x + (chip_w - text_w) / 2.0
        text_y = chip_y + (chip_h - text_h) / 2.0
        NSString.stringWithString_(text).drawAtPoint_withAttributes_((text_x, text_y), attrs)

    def _draw_centered(self, title: str, subtitle=None, check=False):
        para = NSMutableParagraphStyle.alloc().init()
        para.setAlignment_(NSCenterTextAlignment)
        color = NSColor.whiteColor()
        attrs = {
            NSFontAttributeName: NSFont.systemFontOfSize_weight_(17.0, 0.5),
            NSForegroundColorAttributeName: color,
            NSParagraphStyleAttributeName: para,
        }
        prefix = "✓  " if check else ""
        rect = NSMakeRect(0, 22 if subtitle else 24, HUD_WIDTH, 28)
        NSString.stringWithString_(prefix + title).drawInRect_withAttributes_(rect, attrs)
        if subtitle:
            sub_attrs = {
                NSFontAttributeName: NSFont.systemFontOfSize_weight_(11.0, 0.3),
                NSForegroundColorAttributeName: NSColor.colorWithCalibratedWhite_alpha_(1, 0.65),
                NSParagraphStyleAttributeName: para,
            }
            NSString.stringWithString_(subtitle).drawInRect_withAttributes_(
                NSMakeRect(0, 44, HUD_WIDTH, 16), sub_attrs
            )


