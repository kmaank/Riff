#!/bin/bash

# Clean previous builds
rm -rf build dist

# Install PyInstaller if not present (handled by pip, but good to ensure)
# pip install pyinstaller

# Build the app
# --windowed: No terminal window
# --noconfirm: Overwrite output directory
# --name: App name
# --add-data: Include assets if any (none for now, but syntax is source:dest)
# --hidden-import: Ensure dynamic imports are caught (pystray backends likely needed)

# Set Minimum macOS Version to 11.0 (Big Sur) - Covers all Apple Silicon (M1/M2/M3/M4)
export MACOSX_DEPLOYMENT_TARGET=11.0

echo "📦 Building Riff.app..."

python3 -m PyInstaller --noconfirm Riff.spec

echo "✅ Build Complete!"
echo "🚀 App location: dist/Riff.app"
