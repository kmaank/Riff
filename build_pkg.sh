#!/bin/bash

APP_NAME="Riff"
DIST_DIR="dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
PKG_NAME="$APP_NAME.pkg"
PKG_PATH="$DIST_DIR/$PKG_NAME"

echo "📦 Preparing to build $PKG_NAME..."

# Check if App exists
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: $APP_PATH not found. Please run build_app.sh first."
    exit 1
fi

# Remove old pkg
rm -f "$PKG_PATH"

# Build PKG
# --component: The bundle to install
# --install-location: Where to put it
echo "🔨 Building package..."
pkgbuild --component "$APP_PATH" \
         --install-location "/Applications" \
         --identifier "com.riff.app" \
         --version "1.2.6" \
         "$PKG_PATH"

if [ -f "$PKG_PATH" ]; then
    echo "✅ Package created successfully: $PKG_PATH"
    echo "ℹ️  Note: When opening, tell users to Right-Click -> Open if Gatekeeper blocks it."
else
    echo "❌ Package creation failed."
    exit 1
fi
