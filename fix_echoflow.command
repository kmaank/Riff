#!/bin/bash
# fix_echoflow.command
# This script fixes the "App cannot be opened" error for EchoFlow.

echo "🔧 Fixing EchoFlow permissions..."
echo "Please type your password if requested (it won't show on screen)."

# 1. Clear Quarantine (Gatekeeper)
sudo xattr -cr /Applications/EchoFlow.app
if [ $? -eq 0 ]; then
    echo "✅ Quarantine removed."
else
    echo "⚠️  Could not remove quarantine. Is the app in /Applications?"
fi

# 2. Re-sign Ad-Hoc (Force signature)
sudo codesign --force --deep --sign - /Applications/EchoFlow.app
if [ $? -eq 0 ]; then
    echo "✅ Application signed locally."
else
    echo "⚠️  Signing failed."
fi

echo "---------------------------------------------------"
echo "Done! Try opening EchoFlow from Applications now."
echo "You can close this window."
read -p "Press Enter to exit..."
