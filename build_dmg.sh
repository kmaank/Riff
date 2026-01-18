#!/bin/bash

APP_NAME="EchoFlow"
DIST_DIR="dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
SOURCE_FOLDER="dmg_source"

echo "💿 Preparing to build $DMG_NAME..."

# Check if App exists
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: $APP_PATH not found. Please run build_app.sh first."
    exit 1
fi

# Clean up previous build artifacts
rm -rf "$SOURCE_FOLDER"
rm -f "$DMG_PATH"

# Create source folder
mkdir "$SOURCE_FOLDER"

# Copy App to source folder
echo "📂 Copying app to source folder..."
cp -R "$APP_PATH" "$SOURCE_FOLDER/"
cp "fix_echoflow.command" "$SOURCE_FOLDER/"
chmod +x "$SOURCE_FOLDER/fix_echoflow.command"

# Create /Applications link
echo "🔗 Creating Applications symlink..."
ln -s /Applications "$SOURCE_FOLDER/Applications"

# Clean Attributes (Quarantine)
echo "🧹 Cleaning extended attributes (quarantine)..."
xattr -cr "$SOURCE_FOLDER/$APP_NAME.app"

# Create DMG
echo "📦 Creating DMG..."
hdiutil create -volname "$APP_NAME" -srcfolder "$SOURCE_FOLDER" -ov -format UDZO "$DMG_PATH"

# Clean up source folder
rm -rf "$SOURCE_FOLDER"

if [ -f "$DMG_PATH" ]; then
    echo "✅ DMG created successfully: $DMG_PATH"
else
    echo "❌ DMG creation failed."
    exit 1
fi
