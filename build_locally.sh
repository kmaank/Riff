#!/bin/bash
#
# Local Riff macOS build script
# Builds Control Center (Swift), Riff.app (PyInstaller), and creates DMG.
# All output is logged to build_output/ for debugging.
#
# Usage: ./build_locally.sh
#        or: bash build_locally.sh
#
# Output: build_output/Riff-YYYYMMDD-HHMMSS.dmg
#         build_output/build_YYYYMMDD-HHMMSS.log
#

set -e
set -o pipefail

# Timestamp for this build
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/build_output"
LOG_FILE="$OUTPUT_DIR/build_$TIMESTAMP.log"
DMG_OUTPUT="$OUTPUT_DIR/Riff-$TIMESTAMP.dmg"

mkdir -p "$OUTPUT_DIR"

# Log and print all output
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=============================================="
echo "Riff Local Build — $(date)"
echo "=============================================="
echo "Log file: $LOG_FILE"
echo "DMG output: $DMG_OUTPUT"
echo ""

cd "$SCRIPT_DIR"

# --- Step 1: Python setup ---
echo "[1/5] Setting up Python..."
python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt
python3 -m pip install pyinstaller
echo "Python setup done."
echo ""

# --- Step 2: Build Control Center (Swift) ---
echo "[2/5] Building Control Center (Swift UI)..."
chmod +x config_ui/build_ui.sh
bash config_ui/build_ui.sh
echo "--- Control Center build output ---"
ls -la config_ui/build/ 2>/dev/null || echo "No build dir"
ls -la config_ui/build/RiffControlCenter.app/Contents/MacOS/ 2>/dev/null || echo "No binary"
echo ""

# --- Step 3: Build Riff.app with PyInstaller ---
echo "[3/5] Building Riff.app with PyInstaller..."
rm -rf build dist

# Fix executable permissions (PyInstaller strips +x from data files)
RIFFCC_BIN="config_ui/build/RiffControlCenter.app/Contents/MacOS/RiffControlCenter"
if [ -f "$RIFFCC_BIN" ]; then
  chmod +x "$RIFFCC_BIN"
  echo "Restored +x on $RIFFCC_BIN"
fi

python3 -m PyInstaller --clean --noconfirm Riff.spec

echo "--- Build output ---"
ls -la dist/
ls -la dist/Riff.app/ 2>/dev/null || echo "No Riff.app found"

# Restore +x inside the packaged .app bundle
BUNDLED_BIN="dist/Riff.app/Contents/Resources/RiffControlCenter.app/Contents/MacOS/RiffControlCenter"
if [ -f "$BUNDLED_BIN" ]; then
  chmod +x "$BUNDLED_BIN"
  echo "Restored +x on bundled binary"
fi
echo ""

# --- Step 4: Create DMG ---
echo "[4/5] Creating DMG..."
APP_NAME="Riff"
DIST_DIR="dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
SOURCE_FOLDER="dmg_source"

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: $APP_PATH not found. Build failed."
  exit 1
fi

rm -rf "$SOURCE_FOLDER"
mkdir "$SOURCE_FOLDER"
cp -R "$APP_PATH" "$SOURCE_FOLDER/"

if [ -f "fix_echoflow.command" ]; then
  cp "fix_echoflow.command" "$SOURCE_FOLDER/"
  chmod +x "$SOURCE_FOLDER/fix_echoflow.command"
fi

ln -s /Applications "$SOURCE_FOLDER/Applications"
xattr -cr "$SOURCE_FOLDER/$APP_NAME.app" 2>/dev/null || true

sleep 2

for attempt in 1 2 3; do
  echo "DMG creation attempt $attempt..."
  if hdiutil create -volname "$APP_NAME" -srcfolder "$SOURCE_FOLDER" -ov -format UDZO "$DMG_PATH"; then
    echo "DMG created successfully"
    break
  else
    if [ "$attempt" -eq 3 ]; then
      echo "ERROR: All DMG creation attempts failed"
      exit 1
    fi
    echo "Attempt $attempt failed, retrying in 10s..."
    sleep 10
  fi
done

rm -rf "$SOURCE_FOLDER"
echo "DMG at: $DMG_PATH"
ls -lh "$DMG_PATH"
echo ""

# --- Step 5: Copy to output dir ---
echo "[5/5] Copying to build_output..."
cp "$DMG_PATH" "$DMG_OUTPUT"
cp -R "$APP_PATH" "$OUTPUT_DIR/Riff-$TIMESTAMP.app"
echo ""

echo "=============================================="
echo "Build complete."
echo "DMG: $DMG_OUTPUT"
echo "App: $OUTPUT_DIR/Riff-$TIMESTAMP.app"
echo "Log: $LOG_FILE"
echo "=============================================="
