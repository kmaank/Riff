# config_ui/build_ui.sh
set -e  # Exit immediately if any command fails (e.g. swiftc compilation error)

# Change to script directory
cd "$(dirname "$0")"

APP_NAME="RiffControlCenter"
SRC_DIR="RiffControlCenter"
BUILD_DIR="build"
OUTPUT_APP="$BUILD_DIR/$APP_NAME.app"

echo "🔨 Building $APP_NAME..."

# Ensure clean build
rm -rf "$BUILD_DIR"
mkdir -p "$OUTPUT_APP/Contents/MacOS"
mkdir -p "$OUTPUT_APP/Contents/Resources"

# Compile Swift sources
# Note: We just glob all .swift files
swiftc "$SRC_DIR"/*.swift \
    -o "$OUTPUT_APP/Contents/MacOS/$APP_NAME" \
    -target arm64-apple-macosx12.0 \
    -sdk $(xcrun --show-sdk-path) \
    -framework AVFoundation \
    -O

# Create Info.plist
cat > "$OUTPUT_APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.riff.controlcenter</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Riff needs microphone access to transcribe your voice.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>riff</string>
            </array>
            <key>CFBundleURLName</key>
            <string>com.riff.app.oauth</string>
        </dict>
    </array>
</dict>
</plist>
EOF

# Copy Icon (reuse main app icon for now)
if [ -f "../assets/AppIcon.icns" ]; then
    cp "../assets/AppIcon.icns" "$OUTPUT_APP/Contents/Resources/AppIcon.icns"
fi

# Copy Settings Logo
if [ -f "../assets/settings_logo.png" ]; then
    cp "../assets/settings_logo.png" "$OUTPUT_APP/Contents/Resources/settings_logo.png"
fi

echo "✅ Built $OUTPUT_APP"
