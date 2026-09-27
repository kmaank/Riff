#!/bin/bash
# Sign and notarize an already-built Riff.app / pkg / dmg.
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/Riff.app"
ENT="entitlements/Riff.entitlements"
PROFILE="${RIFF_NOTARY_PROFILE:-riff-notary}"
VERSION="${RIFF_PKG_VERSION:-1.2.8}"
OUT="build_output"

APP_ID="${RIFF_SIGN_IDENTITY:-}"
if [ -z "$APP_ID" ]; then
  APP_ID="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
PKG_ID="${RIFF_PKG_IDENTITY:-}"
if [ -z "$PKG_ID" ]; then
  PKG_ID="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Installer/ {print $2; exit}')"
fi

if [ -z "$APP_ID" ]; then
  echo "ERROR: Developer ID Application certificate not found in the keychain."
  exit 1
fi
echo "Using application identity (team hidden)."

sign() { codesign --force --options runtime --timestamp --entitlements "$ENT" --sign "$APP_ID" "$1"; }

# PyInstaller splits the nested Settings app into symlink halves that
# codesign rejects. Replace it with a real bundle before signing.
SRC_CC="config_ui/build/RiffControlCenter.app"
if [ -d "$SRC_CC" ]; then
  rm -rf "$APP/Contents/Resources/RiffControlCenter.app"
  rm -rf "$APP/Contents/Frameworks/RiffControlCenter.app"
  rm -rf "$APP/Contents/Frameworks/RiffControlCenter__dot__app"
  ditto --norsrc --noextattr --noqtn "$SRC_CC" "$APP/Contents/Resources/RiffControlCenter.app"
  chmod +x "$APP/Contents/Resources/RiffControlCenter.app/Contents/MacOS/RiffControlCenter"
fi

xattr -cr "$APP" 2>/dev/null || true

find "$APP" \( -name "*.dylib" -o -name "*.so" \) -print0 | while IFS= read -r -d '' f; do
  [ -L "$f" ] && continue
  sign "$f"
done

while IFS= read -r bundle; do
  [ "$bundle" = "$APP" ] && continue
  [ -L "$bundle" ] && continue
  if [ -L "$bundle/Contents/MacOS" ] || [ -L "$bundle/Contents/Info.plist" ]; then
    echo "Skipping symlink bundle $bundle"
    continue
  fi
  sign "$bundle"
done < <(find "$APP" \( -name "*.app" -o -name "*.framework" \) | awk '{ print length, $0 }' | sort -nr | cut -d' ' -f2-)

sign "$APP/Contents/MacOS/Riff"
sign "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

SIGNED_PKG="$OUT/Riff-$VERSION.pkg"
if [ -n "$PKG_ID" ] && [ -f dist/Riff.pkg ]; then
  productsign --sign "$PKG_ID" --timestamp dist/Riff.pkg "$SIGNED_PKG"
else
  echo "No Developer ID Installer cert — skipping productsign"
  SIGNED_PKG=""
fi

if [ -f "$OUT/Riff-$VERSION.dmg" ]; then
  codesign --force --timestamp --sign "$APP_ID" "$OUT/Riff-$VERSION.dmg"
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "ERROR: notarytool profile '$PROFILE' is not stored."
  echo "Run: xcrun notarytool store-credentials \"$PROFILE\" --apple-id EMAIL --team-id TEAMID --password APP_SPECIFIC_PASSWORD"
  exit 1
fi

if [ -n "$SIGNED_PKG" ]; then
  xcrun notarytool submit "$SIGNED_PKG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$SIGNED_PKG"
  xcrun stapler validate "$SIGNED_PKG"
else
  xcrun notarytool submit "$OUT/Riff-$VERSION.dmg" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$OUT/Riff-$VERSION.dmg"
  xcrun stapler validate "$OUT/Riff-$VERSION.dmg"
fi
xcrun stapler staple "$APP" || true
echo "SIGNED_AND_NOTARIZED"
