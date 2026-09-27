#!/bin/bash
# Build a component pkg that ALWAYS installs to /Applications/Riff.app.
#
# pkgbuild --component marks the app relocatable by default. Installer then
# "upgrades" whichever Riff.app Launch Services already knows — often a
# timestamped copy in build_output — so nothing appears in Applications.

set -euo pipefail

APP_NAME="Riff"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DIST_DIR="dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
PKG_PATH="$DIST_DIR/$APP_NAME.pkg"
VERSION="${RIFF_PKG_VERSION:-1.2.8}"
PKG_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/riff-pkgroot.XXXXXX")"
COMPONENT_PLIST="$(mktemp "${TMPDIR:-/tmp}/riff-components.XXXXXX.plist")"

cleanup() {
  rm -rf "$PKG_ROOT" "$COMPONENT_PLIST"
}
trap cleanup EXIT

if [ ! -d "$APP_PATH" ]; then
  echo "Error: $APP_PATH not found. Build the app first."
  exit 1
fi

echo "Preparing payload at $PKG_ROOT"
# ditto without resource forks / AppleDouble so the pkg is not full of ._ files
ditto --norsrc --noextattr --noqtn "$APP_PATH" "$PKG_ROOT/$APP_NAME.app"
xattr -cr "$PKG_ROOT/$APP_NAME.app" 2>/dev/null || true

echo "Analyzing bundles..."
pkgbuild --analyze --root "$PKG_ROOT" "$COMPONENT_PLIST"

python3 - "$COMPONENT_PLIST" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as fh:
    items = plistlib.load(fh)
for item in items:
    item["BundleIsRelocatable"] = False
    item["BundleHasStrictIdentifier"] = True
    item["BundleIsVersionChecked"] = False
    item["BundleOverwriteAction"] = "upgrade"
with open(path, "wb") as fh:
    plistlib.dump(items, fh)
print("Pinned %s bundle(s) to /Applications (not relocatable)" % len(items))
PY

rm -f "$PKG_PATH"
echo "Building $PKG_PATH (version $VERSION)..."
pkgbuild --root "$PKG_ROOT" \
         --component-plist "$COMPONENT_PLIST" \
         --install-location "/Applications" \
         --identifier "com.riff.app" \
         --version "$VERSION" \
         "$PKG_PATH"

# Sanity-check: relocate-by-bundle-id must not be present
INFO_DIR="$(mktemp -d "${TMPDIR:-/tmp}/riff-pkginfo.XXXXXX")"
pkgutil --expand "$PKG_PATH" "$INFO_DIR/pkg"
if grep -q "<relocate>" "$INFO_DIR/pkg/PackageInfo"; then
  echo "WARNING: PackageInfo still contains <relocate>. Installer may skip Applications."
  cat "$INFO_DIR/pkg/PackageInfo"
else
  echo "PackageInfo has no <relocate> block — install path is /Applications/Riff.app"
fi
rm -rf "$INFO_DIR"

echo "Package created: $PKG_PATH"
echo "If Gatekeeper blocks it: right-click the pkg → Open."
