
import tkinter as tk
from tkinter import ttk, messagebox
import webbrowser
import sys
import os

class OnboardingWindow:
    def __init__(self, config_manager):
        self.config = config_manager
        self.root = tk.Tk()
        self.root.title("Welcome to EchoFlow")
        self.root.geometry("600x550")
        self.root.resizable(False, False)
        
        # Center the window
        self.center_window()
        
        self.setup_ui()
        
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
        style.configure("TLabel", font=("Helvetica", 12))
        style.configure("Header.TLabel", font=("Helvetica", 20, "bold"))
        style.configure("SubHeader.TLabel", font=("Helvetica", 14, "bold"))
        
        # Main Container
        main_frame = ttk.Frame(self.root, padding="20")
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Header
        ttk.Label(main_frame, text="Welcome to EchoFlow! 🎙️", style="Header.TLabel").pack(pady=(0, 20))
        
        ttk.Label(main_frame, text="To get started, we need to set up a few things.", wraplength=550).pack(pady=(0, 20))
        
        # Step 1: API Key
        step1_frame = ttk.LabelFrame(main_frame, text="Step 1: AI Brain 🧠", padding="10")
        step1_frame.pack(fill=tk.X, pady=(0, 20))
        
        ttk.Label(step1_frame, text="EchoFlow uses Groq for super-fast transcription.").pack(anchor=tk.W)
        
        link_lbl = ttk.Label(step1_frame, text="Get your FREE API Key here", foreground="blue", cursor="hand2")
        link_lbl.pack(anchor=tk.W, pady=(5, 5))
        link_lbl.bind("<Button-1>", lambda e: webbrowser.open("https://console.groq.com/keys"))
        
        ttk.Label(step1_frame, text="Paste it below:").pack(anchor=tk.W)
        
        self.api_key_var = tk.StringVar()
        entry = ttk.Entry(step1_frame, textvariable=self.api_key_var, width=50)
        entry.pack(fill=tk.X, pady=(5, 0))
        
        # Step 2: Permissions
        step2_frame = ttk.LabelFrame(main_frame, text="Step 2: Permissions 🔐", padding="10")
        step2_frame.pack(fill=tk.X, pady=(0, 20))
        
        info_text = (
            "Because EchoFlow listens to global hotkeys and types text for you, it needs special permissions:\n\n"
            "1. Accessibility: To hear your hotkey.\n"
            "2. Automation: To try pasting text cleanly.\n"
            "\nMacOS will ask you for these. Please click 'Allow' or 'Open System Settings' when prompted."
        )
        ttk.Label(step2_frame, text=info_text, wraplength=520, justify=tk.LEFT).pack(anchor=tk.W)
        
        # Start Button
        btn_frame = ttk.Frame(main_frame)
        btn_frame.pack(fill=tk.X, pady=(20, 0))
        
        ttk.Button(btn_frame, text="Save & Start App", command=self.save_and_start).pack(fill=tk.X, ipady=10)

    def save_and_start(self):
        key = self.api_key_var.get().strip()
        if not key:
            messagebox.showerror("Error", "Please enter a valid API Key.")
            return
            
        if not key.startswith("gsk_"):
             if not messagebox.askyesno("Warning", "That doesn't look like a standard Groq key (usually starts with 'gsk_'). Continue anyway?"):
                 return

        # Save to config
        try:
            self.config.set("api.api_key", key)
            messagebox.showinfo("Success", "Setup complete! The app will now try to launch.\nCheck the System Tray (top right) for the icon.")
            self.root.destroy()
        except Exception as e:
            messagebox.showerror("Error", f"Failed to save config: {e}")

    def run(self):
        self.root.mainloop()

def run_onboarding(config_manager):
    window = OnboardingWindow(config_manager)
    window.run()

if __name__ == "__main__":
    # Test run
    from utils.config_manager import ConfigManager
    cm = ConfigManager()
    run_onboarding(cm)
