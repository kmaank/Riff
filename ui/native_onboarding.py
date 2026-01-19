import subprocess
import logging
import sys

def run_applescript(script):
    """Runs a single line of AppleScript and returns the output."""
    try:
        result = subprocess.run(
            ['osascript', '-e', script],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        logging.error(f"AppleScript error: {e.stderr}")
        return None

def show_dialog(message, title="Riff", default_answer=None, buttons=["OK"], default_button="OK", icon="note"):
    """
    Shows a native macOS dialog.
    If default_answer is provided, it shows an input field.
    Returns the text entered (if any) or the button clicked.
    """
    buttons_str = ", ".join([f'"{b}"' for b in buttons])
    # Force dialog to front using System Events
    # Note: 'with title' is standard, but 'activate' ensures visibility for LSUIElement apps
    full_script = f'''
    tell application "System Events"
        activate
        display dialog "{message}" with title "{title}" buttons {{{buttons_str}}} default button "{default_button}" with icon {icon}
        {f'default answer "{default_answer}"' if default_answer is not None else ''}
    end tell
    '''
    
    # Clean up newlines for single-line execution if needed, 
    # but run_applescript takes a script string.
    # We'll pass the multiline script directly to osascript -e is tricky.
    # Better to pipe it or use multiple -e. 
    # Let's simplify and use the one-liner approach compatible with our helper.
    
    cmd = f'tell application "System Events" to display dialog "{message}" with title "{title}" buttons {{{buttons_str}}} default button "{default_button}" with icon {icon}'
    if default_answer is not None:
        cmd += f' default answer "{default_answer}"'
    
    # Prefix with 'activate' to force focus (System Events activate brings the dialog front)
    # Actually 'tell application "System Events" to activate' works best.
    
    final_script = f'tell application "System Events" to activate\n{cmd}'
    
    output = run_applescript(final_script)
    
    if output:
        # Parse output "button returned:OK, text returned:foo"
        parts = output.split(', ')
        result = {}
        for part in parts:
            if ':' in part:
                key, val = part.split(':', 1)
                result[key] = val
        return result
    return None

def run_onboarding_native(config_manager):
    logging.info("Starting Native Onboarding...")
    
    # Step 1: Welcome & API Key
    welcome_msg = (
        "Welcome to Riff! 🎙️\\n\\n"
        "To get started, we need your Groq API Key.\\n"
        "This is the 'Brain' that powers the voice-to-text.\\n\\n"
        "Get a free key at console.groq.com."
    )
    
    # Loop until valid key or cancel
    while True:
        response = show_dialog(
            message=welcome_msg, 
            default_answer="", 
            buttons=["Cancel", "Save Key"], 
            default_button="Save Key"
        )
        
        if not response or response.get("button returned") == "Cancel":
            logging.info("Onboarding cancelled by user.")
            return False
            
        api_key = response.get("text returned", "").strip()
        
        if not api_key:
             show_dialog("Please enter a valid API Key.", icon="stop")
             continue
             
        if not api_key.startswith("gsk_"):
            # Warning dialog
            warn_resp = show_dialog(
                "That doesn't look like a standard Groq key (usually starts with 'gsk_').\\n\\nUse it anyway?",
                buttons=["No, let me fix it", "Yes, use it"],
                default_button="No, let me fix it",
                icon="caution"
            )
            if warn_resp and warn_resp.get("button returned") == "No, let me fix it":
                continue
        
        # Save Config
        try:
            config_manager.set("api.api_key", api_key)
            logging.info("API Key saved successfully.")
            
            # Step 2: Permissions Info
            perm_msg = (
                "Setup Complete! ✅\\n\\n"
                "Riff will now launch in your System Tray (top right).\\n\\n"
                "IMPORTANT: You will see popups asking for 'Accessibility' permissions.\\n"
                "Please click 'Open System Settings' and grant access to Riff."
            )
            show_dialog(perm_msg, buttons=["Launch App"])
            return True
            
        except Exception as e:
            show_dialog(f"Failed to save config: {e}", icon="stop")
            return False

if __name__ == "__main__":
    # Test run
    from utils.config_manager import ConfigManager
    cm = ConfigManager()
    run_onboarding_native(cm)
