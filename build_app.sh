#!/bin/bash

# Riff Build Script
# Creates a standalone macOS .app bundle using PyInstaller

# Ensure in virtualenv
source venv/bin/activate

# Clean previous builds
rm -rf build dist

# Run PyInstaller
# --clean: Clean cache
# --noconfirm: Overwrite existing
pyinstaller --clean --noconfirm Riff.spec

echo "Build complete. App is located in dist/Riff.app"
