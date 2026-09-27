#!/bin/bash

# Riff Build Script
# Creates a standalone macOS .app bundle using PyInstaller

# Ensure in virtualenv
source venv/bin/activate

# Clean previous builds
rm -rf build dist

# Build UI (settings helper — same identity as Riff.app)
echo "🎨 Building settings helper..."
chmod +x config_ui/build_ui.sh
./config_ui/build_ui.sh

# Run PyInstaller
# --clean: Clean cache
# --noconfirm: Overwrite existing
pyinstaller --clean --noconfirm Riff.spec

# Settings helper shares com.riff.app. Lives in Helpers, not Resources,
# and is launched as a child binary (never `open -a`) so TCC shows one Riff.
HELPER_APP="config_ui/build/RiffSettings.app"
APP_PATH="dist/Riff.app"
if [ ! -d "$HELPER_APP" ]; then
  echo "ERROR: $HELPER_APP missing"
  exit 1
fi
mkdir -p "$APP_PATH/Contents/Helpers"
rm -rf "$APP_PATH/Contents/Helpers/RiffSettings.app"
ditto "$HELPER_APP" "$APP_PATH/Contents/Helpers/RiffSettings.app"
chmod +x "$APP_PATH/Contents/Helpers/RiffSettings.app/Contents/MacOS/RiffSettings"
rm -f "$APP_PATH/Contents/MacOS/RiffSettings"
rm -rf "$APP_PATH/Contents/Resources/RiffControlCenter.app" "$APP_PATH/Contents/Resources/RiffSettings.app"
codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || true

echo "Build complete. App is located in dist/Riff.app"
