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
        <title>Riff Documentation</title>
        <style>
            body { 
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; 
                padding: 40px; 
                line-height: 1.6; 
                max_width: 800px; 
                margin: 0 auto; 
                color: #333; 
                background-color: #fdfdfd;
            }
            h1 { color: #000; margin-bottom: 5px; }
            .subtitle { font-size: 1.2em; color: #666; font-weight: 300; margin-bottom: 30px; border-bottom: 2px solid #eee; padding-bottom: 20px;}
            
            h2 { margin-top: 40px; color: #111; border-bottom: 1px solid #eee; padding-bottom: 8px;}
            h3 { margin-top: 25px; color: #444; margin-bottom: 10px; }
            
            .key { 
                background: #f0f0f0; 
                padding: 2px 6px; 
                border-radius: 4px; 
                border: 1px solid #ccc; 
                font-family: monospace; 
                font-weight: bold; 
                font-size: 0.9em;
            }
            
            .icon-red { color: #e74c3c; font-weight: bold; }
            .icon-yellow { color: #f1c40f; font-weight: bold; }
            
            ul { padding-left: 20px; }
            li { margin-bottom: 6px; }
            
            .box {
                background: #f9f9f9;
                border: 1px solid #eee;
                padding: 15px;
                border-radius: 8px;
                margin-top: 10px;
                margin-bottom: 20px;
            }
            .box strong { color: #222; }
            
            .style-card {
                margin-bottom: 20px;
                padding: 15px;
                background: #fff;
                border: 1px solid #e0e0e0;
                border-radius: 8px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.02);
            }
            .style-title { font-weight: bold; font-size: 1.1em; color: #d35400; margin-bottom: 5px;}
            .style-formal .style-title { color: #2c3e50; }
            
            .troubleshoot-item { margin-bottom: 15px; }
            .question { font-weight: bold; color: #c0392b; }
            
            .pro-tip {  margin-bottom: 12px; }
            .pro-tip strong { color: #27ae60; }
            
            .footer { margin-top: 60px; font-size: 0.9em; color: #888; text-align: center; border-top: 1px solid #eee; padding-top: 20px; }
        </style>
    </head>
    <body>
        <h1>Riff Documentation 🎙️</h1>
        <div class="subtitle">Stop typing. Start riffing.</div>

        <h2>Quick Start (Think it. Riff it. Ship it.)</h2>
        
        <div class="box">
            <h3>Standard Riff</h3>
            <ul>
                <li>HOLD <span class="key">Left Control</span> to start riffing</li>
                <li>Icon turns <span class="icon-red">RED 🔴</span></li>
                <li>Release to stop</li>
                <li>Your riff auto-types into any window</li>
            </ul>
        </div>

        <div class="box">
            <h3>Latch Mode (Hands-Free Riffing)</h3>
            <ul>
                <li>Hold <span class="key">Left Shift</span> + <span class="key">Left Control</span> to lock recording</li>
                <li>Keep riffing without holding the key</li>
                <li>Press <span class="key">Left Control</span> again to stop</li>
            </ul>
        </div>

        <p><strong>Processing:</strong> Icon turns <span class="icon-yellow">YELLOW 🟡</span> while your riff gets cleaned up. Wait 2-5 seconds. Text appears automatically.</p>

        <h2>Riff Styles</h2>
        <p>Choose how your riff gets polished:</p>
        
        <div class="style-card">
            <div class="style-title">Casual</div>
            <p><strong>What it does:</strong> Raw. Unfiltered. Pure riff.</p>
            <ul>
                <li>Keeps your actual voice — slang, emotion, tone</li>
                <li>No censoring</li>
                <li>Filler words stay if they add feeling</li>
                <li>You said "fuck" → it types "fuck"</li>
            </ul>
            <p><em>Riff it for: Personal notes, creative writing, thinking out loud</em></p>
        </div>

        <div class="style-card style-formal">
            <div class="style-title">Formal</div>
            <p><strong>What it does:</strong> Business-ready riff. Clean and professional.</p>
            <ul>
                <li>Strips filler words (umm, uh, like)</li>
                <li>Removes repetition and stuttering</li>
                <li>Replaces aggressive language with professional equivalents</li>
                <li>Polished, concise, ready to send</li>
            </ul>
            <p><em>Riff it for: Emails, Slack messages, client communication, documentation</em></p>
        </div>

        <h2>Your Riff History</h2>
        <p>Every riff you've ever riffed, saved with:</p>
        <ul>
            <li>Full transcript</li>
            <li>Timestamp</li>
            <li>One-click copy</li>
        </ul>
        <p>Access via tray menu (Settings > History). Never lose a good riff.</p>

        <h2>Permissions Setup</h2>
        <p>If you can't riff, you're missing permissions. Open <strong>Tray > Permissions</strong>. Enable these 4:</p>
        <ul>
            <li><strong>Microphone:</strong> So Riff can hear you</li>
            <li><strong>Accessibility:</strong> Detects your riff hotkey</li>
            <li><strong>Input Monitoring:</strong> Listens for global keyboard events</li>
            <li><strong>Automation:</strong> Auto-types your riff into apps</li>
        </ul>
        <p><em>Click any item in the menu → opens System Settings → toggle it on.</em></p>

        <h2>Troubleshooting</h2>
        <div class="troubleshoot-item">
            <div class="question">Can't start riffing?</div>
            Check microphone permission.
        </div>
        <div class="troubleshoot-item">
            <div class="question">Hotkey not working?</div>
            Enable Accessibility + Input Monitoring.
        </div>
        <div class="troubleshoot-item">
            <div class="question">Riff not appearing in your app?</div>
            Enable Automation permission.
        </div>
        <div class="troubleshoot-item">
            <div class="question">Still broken?</div>
            Restart Riff after granting permissions.
        </div>

        <h2>Pro Tips</h2>
        <div class="pro-tip">
            <strong>Riff emails faster than you can type them.</strong><br>
            Stop staring at blank compose windows. Just riff what you want to say. Edit later if needed.
        </div>
        <div class="pro-tip">
            <strong>Riff documentation while you think.</strong><br>
            Context-switching kills flow. Stay in your IDE, hold Control, riff your docs, keep coding.
        </div>
        <div class="pro-tip">
            <strong>Riff meeting notes hands-free.</strong><br>
            Use Latch Mode. Riff everything important. Your notes type themselves.
        </div>
        <div class="pro-tip">
            <strong>Riff through writer's block.</strong><br>
            Can't find the right words? Stop trying. Just riff it. Your casual riff becomes your first draft.
        </div>
        
        <br>
        <p style="font-size: 1.1em; font-weight: bold; text-align: center;">
            You think at 150 words/min. You type at 40.<br>
            Stop typing. Start riffing.
        </p>

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
