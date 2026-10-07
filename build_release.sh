#!/bin/bash
# Build, sign, notarize, and staple Riff for public macOS distribution.
#
# Required on this Mac:
#   - Developer ID Application certificate in the login keychain
#   - Developer ID Installer certificate (for the .pkg)
#   - A notarytool keychain profile (default name: riff-notary)
#
# Store notary credentials once:
#   xcrun notarytool store-credentials "riff-notary" \
#     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
#
# Optional env:
#   RIFF_SIGN_IDENTITY   Developer ID Application identity string
#   RIFF_PKG_IDENTITY    Developer ID Installer identity string
#   RIFF_NOTARY_PROFILE  notarytool profile name (default: riff-notary)
#   RIFF_PKG_VERSION     version stamped on the pkg (default: 1.2.8)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VERSION="${RIFF_PKG_VERSION:-1.2.9}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_DIR="$SCRIPT_DIR/build_output"
ENTITLEMENTS="$SCRIPT_DIR/entitlements/Riff.entitlements"
APP_PATH="$SCRIPT_DIR/dist/Riff.app"
NOTARY_PROFILE="${RIFF_NOTARY_PROFILE:-riff-notary}"
LOG="$OUTPUT_DIR/release_$TIMESTAMP.log"

mkdir -p "$OUTPUT_DIR"
exec > >(tee -a "$LOG") 2>&1

echo "=============================================="
echo "Riff release $VERSION — $(date)"
echo "=============================================="

pick_identity() {
  local kind="$1"
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' -v kind="$kind" '$0 ~ kind { print $2; exit }'
}

APP_IDENTITY="${RIFF_SIGN_IDENTITY:-}"
if [ -z "$APP_IDENTITY" ]; then
  APP_IDENTITY="$(pick_identity "Developer ID Application")"
fi
PKG_IDENTITY="${RIFF_PKG_IDENTITY:-}"
if [ -z "$PKG_IDENTITY" ]; then
  PKG_IDENTITY="$(pick_identity "Developer ID Installer")"
fi

if [ -z "$APP_IDENTITY" ]; then
  echo "ERROR: No Developer ID Application certificate found."
  echo "Install it from Apple Developer → Certificates, then re-run."
  exit 1
fi

echo "App identity: ${APP_IDENTITY%%:*}"
if [ -n "$PKG_IDENTITY" ]; then
  echo "Pkg identity: ${PKG_IDENTITY%%:*}"
else
  echo "Pkg identity: none — will notarize a DMG instead of a signed pkg"
fi
echo "Notary profile: $NOTARY_PROFILE"
echo ""

echo "[1/6] Control Center"
chmod +x config_ui/build_ui.sh
bash config_ui/build_ui.sh
chmod +x config_ui/build/RiffControlCenter.app/Contents/MacOS/RiffControlCenter

echo "[2/6] Riff.app"
rm -rf build dist
export PYINSTALLER_CONFIG_DIR="$SCRIPT_DIR/.pyinstaller_cache"
mkdir -p "$PYINSTALLER_CONFIG_DIR"
./venv/bin/python -m PyInstaller --noconfirm Riff.spec
chmod +x "$APP_PATH/Contents/MacOS/Riff"
# PyInstaller splits nested .app datas into symlink halves. Restore a real bundle.
rm -rf "$APP_PATH/Contents/Resources/RiffControlCenter.app"
rm -rf "$APP_PATH/Contents/Frameworks/RiffControlCenter.app"
rm -rf "$APP_PATH/Contents/Frameworks/RiffControlCenter__dot__app"
ditto --norsrc --noextattr --noqtn \
  "$SCRIPT_DIR/config_ui/build/RiffControlCenter.app" \
  "$APP_PATH/Contents/Resources/RiffControlCenter.app"
chmod +x "$APP_PATH/Contents/Resources/RiffControlCenter.app/Contents/MacOS/RiffControlCenter"
xattr -cr "$APP_PATH" 2>/dev/null || true

sign_item() {
  local path="$1"
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$APP_IDENTITY" \
    "$path"
}

echo "[3/6] Codesign (hardened runtime)"
# Inside-out: libraries, then nested app, then the outer app.
while IFS= read -r -d '' file; do
  sign_item "$file"
done < <(find "$APP_PATH" \( -name "*.dylib" -o -name "*.so" -o -name "*.framework" \) -print0)

CC_APP="$APP_PATH/Contents/Resources/RiffControlCenter.app"
if [ ! -d "$CC_APP" ]; then
  CC_APP="$(find "$APP_PATH" -name "RiffControlCenter.app" -type d | head -1 || true)"
fi
if [ -n "${CC_APP:-}" ] && [ -d "$CC_APP" ]; then
  sign_item "$CC_APP"
fi

find "$APP_PATH/Contents/MacOS" -type f -perm +111 -print0 | while IFS= read -r -d '' bin; do
  sign_item "$bin"
done

sign_item "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "Codesign ok"

echo "[4/6] Installers"
chmod +x "$SCRIPT_DIR/build_pkg.sh"
RIFF_PKG_VERSION="$VERSION" bash "$SCRIPT_DIR/build_pkg.sh"
UNSIGNED_PKG="$SCRIPT_DIR/dist/Riff.pkg"
SIGNED_PKG="$OUTPUT_DIR/Riff-$VERSION.pkg"
DMG_PATH="$OUTPUT_DIR/Riff-$VERSION.dmg"

if [ -n "$PKG_IDENTITY" ]; then
  productsign --sign "$PKG_IDENTITY" --timestamp "$UNSIGNED_PKG" "$SIGNED_PKG"
  echo "Signed pkg: $SIGNED_PKG"
else
  cp "$UNSIGNED_PKG" "$SIGNED_PKG"
  echo "Unsigned pkg copied (no Developer ID Installer cert)"
fi

DMG_SRC="$(mktemp -d "${TMPDIR:-/tmp}/riff-dmg.XXXXXX")"
ditto --norsrc --noextattr --noqtn "$APP_PATH" "$DMG_SRC/Riff.app"
ln -s /Applications "$DMG_SRC/Applications"
xattr -cr "$DMG_SRC/Riff.app" 2>/dev/null || true
hdiutil create -volname "Riff" -srcfolder "$DMG_SRC" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_SRC"
codesign --force --timestamp --sign "$APP_IDENTITY" "$DMG_PATH"
echo "DMG: $DMG_PATH"

echo "[5/6] Notarize"
submit() {
  local file="$1"
  echo "Submitting $(basename "$file")..."
  xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait
}

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "ERROR: notarytool profile '$NOTARY_PROFILE' is missing."
  echo "Create it with:"
  echo "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id EMAIL --team-id TEAMID --password APP_SPECIFIC_PASSWORD"
  exit 1
fi

if [ -n "$PKG_IDENTITY" ] && [ -f "$SIGNED_PKG" ]; then
  submit "$SIGNED_PKG"
  echo "[6/6] Staple"
  xcrun stapler staple "$SIGNED_PKG"
  xcrun stapler validate "$SIGNED_PKG"
else
  submit "$DMG_PATH"
  echo "[6/6] Staple"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler staple "$APP_PATH" || true
  xcrun stapler validate "$DMG_PATH"
fi

# Always staple the app and refresh the DMG copy after a pkg notarization too
xcrun stapler staple "$APP_PATH" || true
ditto --norsrc --noextattr --noqtn "$APP_PATH" "$OUTPUT_DIR/Riff-$VERSION.app"

echo "=============================================="
echo "Release ready."
echo "PKG: $SIGNED_PKG"
echo "DMG: $DMG_PATH"
echo "APP: $OUTPUT_DIR/Riff-$VERSION.app"
echo "Log: $LOG"
echo "=============================================="
