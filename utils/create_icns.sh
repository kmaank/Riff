#!/bin/bash
# utils/create_icns.sh
# Generates AppIcon.icns from a single 1024x1024 PNG

SOURCE="assets/app_icon.png"
ICONSET="assets/AppIcon.iconset"
DEST="assets/AppIcon.icns"

if [ ! -f "$SOURCE" ]; then
    echo "Error: Source image $SOURCE not found."
    exit 1
fi

mkdir -p "$ICONSET"

# Resize images
sips -z 16 16     "$SOURCE" --out "${ICONSET}/icon_16x16.png"
sips -z 32 32     "$SOURCE" --out "${ICONSET}/icon_16x16@2x.png"
sips -z 32 32     "$SOURCE" --out "${ICONSET}/icon_32x32.png"
sips -z 64 64     "$SOURCE" --out "${ICONSET}/icon_32x32@2x.png"
sips -z 128 128   "$SOURCE" --out "${ICONSET}/icon_128x128.png"
sips -z 256 256   "$SOURCE" --out "${ICONSET}/icon_128x128@2x.png"
sips -z 256 256   "$SOURCE" --out "${ICONSET}/icon_256x256.png"
sips -z 512 512   "$SOURCE" --out "${ICONSET}/icon_256x256@2x.png"
sips -z 512 512   "$SOURCE" --out "${ICONSET}/icon_512x512.png"
sips -z 1024 1024 "$SOURCE" --out "${ICONSET}/icon_512x512@2x.png"

# Create icns
iconutil -c icns "$ICONSET" -o "$DEST"

# Cleanup
rm -rf "$ICONSET"

echo "✅ AppIcon.icns created at $DEST"
