import os
import tempfile
import webbrowser
import logging
from threading import Timer

def get_instructions_html():
    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>How to use Riff</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; padding: 40px; line-height: 1.6; max_width: 700px; margin: 0 auto; color: #333; }
            h1 { color: #000; border-bottom: 2px solid #eee; padding-bottom: 10px; }
            h2 { margin-top: 30px; color: #444; }
            .key { background: #f0f0f0; padding: 2px 6px; border-radius: 4px; border: 1px solid #ccc; font-family: monospace; font-weight: bold; }
            .icon-red { color: #e74c3c; }
            .icon-yellow { color: #f1c40f; }
            ul { padding-left: 20px; }
            li { margin-bottom: 8px; }
            .footer { margin-top: 50px; font-size: 0.9em; color: #888; text-align: center; border-top: 1px solid #eee; padding-top: 20px; }
        </style>
    </head>
    <body>
        <h1>How to use Riff 🎙️</h1>

        <h2>1. Recording</h2>
        <ul>
            <li><strong>Option A:</strong> HOLD <span class="key">Left Control</span> to talk. (Release to stop)</li>
            <li><strong>Option B:</strong> Click "Start Recording" in the Tray menu.</li>
            <li><strong>Latch Mode:</strong> Hold <span class="key">Left Shift</span> + <span class="key">Left Control</span> to lock recording on. (Press key again to stop)</li>
            <li>The tray icon turns <strong class="icon-red">RED 🔴</strong> while recording.</li>
        </ul>

        <h2>2. Finishing</h2>
        <ul>
            <li>Release the hotkey OR click "Stop Recording" in the Tray.</li>
            <li>The icon turns <strong class="icon-yellow">YELLOW 🟡</strong> while processing.</li>
            <li>The text will be typed automatically into your active window.</li>
        </ul>

        <h2>3. Permissions</h2>
        <p>If it's not working, check the <strong>Tray > Permissions</strong> menu:</p>
        <ul>
            <li><strong>Microphone:</strong> Needed to hear your voice.</li>
            <li><strong>Accessibility:</strong> Needed to detect the hotkey press.</li>
            <li><strong>Input Monitoring:</strong> Needed to listen for global keyboard events.</li>
            <li><strong>Automation:</strong> Needed to paste text cleanly.</li>
        </ul>
        <p><em>Click any item in the menu to open the corresponding System Settings panel.</em></p>

        <div class="footer">
            Riff - Simplicity in Voice
        </div>
    </body>
    </html>
    """

def show_instructions():
    """Generates a transient HTML file and opens it in the default browser."""
    try:
        # Create a temp file
        fd, path = tempfile.mkstemp(suffix=".html", prefix="echoflow_help_")
        
        with os.fdopen(fd, 'w') as f:
            f.write(get_instructions_html())
            
        logging.info(f"Opening instructions at {path}")
        
        # Open in default browser
        webbrowser.open(f"file://{path}")
        
        # Optional: Clean up file after a delay (e.g. 5 seconds)
        # Browser needs time to read it, so we can't delete immediately.
        # A simple Timer works well here without blocking.
        def cleanup():
            try:
                if os.path.exists(path):
                    os.remove(path)
                    logging.info("Cleaned up instructions file")
            except:
                pass
                
        Timer(10.0, cleanup).start()
            
    except Exception as e:
        logging.error(f"Failed to show instructions: {e}")
