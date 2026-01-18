
import tkinter as tk
from tkinter import ttk

class InstructionsWindow:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("EchoFlow Instructions")
        self.root.geometry("500x600")
        self.root.resizable(False, False)
        self.center_window()
        self.setup_ui()
        
        # Bring to front
        self.root.lift()
        self.root.attributes('-topmost', True)
        self.root.after_idle(self.root.attributes, '-topmost', False)

    def center_window(self):
        self.root.update_idletasks()
        width = self.root.winfo_width()
        height = self.root.winfo_height()
        x = (self.root.winfo_screenwidth() // 2) - (width // 2)
        y = (self.root.winfo_screenheight() // 2) - (height // 2)
        self.root.geometry(f'{width}x{height}+{x}+{y}')

    def setup_ui(self):
        # Styles
        style = ttk.Style()
        style.configure("Header.TLabel", font=("Helvetica", 18, "bold"))
        style.configure("SubHeader.TLabel", font=("Helvetica", 14, "bold"))
        style.configure("Bold.TLabel", font=("Helvetica", 12, "bold"))
        
        main_frame = ttk.Frame(self.root, padding="20")
        main_frame.pack(fill=tk.BOTH, expand=True)

        # Title
        ttk.Label(main_frame, text="How to use EchoFlow 🎙️", style="Header.TLabel").pack(pady=(0, 20))
        
        # Section 1: Recording
        ttk.Label(main_frame, text="1. Recording", style="SubHeader.TLabel").pack(anchor=tk.W, pady=(10, 5))
        ttk.Label(main_frame, text="• Option A: HOLD 'Left Control' to talk.").pack(anchor=tk.W, padx=10)
        ttk.Label(main_frame, text="• Option B: Click 'Start Recording' in the Tray menu.").pack(anchor=tk.W, padx=10)
        ttk.Label(main_frame, text="• Latch Mode: Hold 'Left Shift' + 'Left Control' to lock.").pack(anchor=tk.W, padx=10)
        ttk.Label(main_frame, text="• The icon will turn RED 🔴 while recording.").pack(anchor=tk.W, padx=10)
        
        # Section 2: Stopping & Processing
        ttk.Label(main_frame, text="2. Finishing", style="SubHeader.TLabel").pack(anchor=tk.W, pady=(15, 5))
        ttk.Label(main_frame, text="• Release the hotkey OR click 'Stop Recording' in Tray.").pack(anchor=tk.W, padx=10)
        ttk.Label(main_frame, text="• The icon turns YELLOW 🟡 while processing.").pack(anchor=tk.W, padx=10)
        ttk.Label(main_frame, text="• Text will be typed into your active window.").pack(anchor=tk.W, padx=10)
        
        # Section 3: Permissions
        ttk.Label(main_frame, text="3. Permissions", style="SubHeader.TLabel").pack(anchor=tk.W, pady=(15, 5))
        ttk.Label(main_frame, text="If it's not working, check the Tray > Permissions menu.").pack(anchor=tk.W, padx=10)
        ttk.Label(main_frame, text="• Microphone: Needed to hear you.").pack(anchor=tk.W, padx=10)
        ttk.Label(main_frame, text="• Accessibility: Needed for the hotkey.").pack(anchor=tk.W, padx=10)
        ttk.Label(main_frame, text="• Automation: Needed to paste text cleanly.").pack(anchor=tk.W, padx=10)
        ttk.Label(main_frame, text="Click any item in the menu to open System Settings.").pack(anchor=tk.W, padx=10)

        # Close Button
        ttk.Button(main_frame, text="Got it!", command=self.root.destroy).pack(side=tk.BOTTOM, fill=tk.X, pady=20)

    def run(self):
        self.root.mainloop()

def show_instructions():
    # Run in a separate process or ensure it doesn't block if mainloop is tricky
    # Since specific tkinter usage within existing loops can be complex,
    # for this helper window, we'll just instantiate and run.
    # Note: If main thread is blocked by tray, this might need care.
    # But usually creating a new Tk instance for a transient window is okay-ish if careful,
    # or better, use multiprocessing if the main app is weird.
    # Let's try standard instantiation first.
    window = InstructionsWindow()
    window.run()

if __name__ == "__main__":
    show_instructions()
