#!/bin/bash
# Build a release LucidWallpaper.app and a distributable .dmg.
#
# Ad-hoc (local) build:   ./scripts/package.sh
# Notarized distribution: DEVELOPER_ID_APP="Developer ID Application: NAME (TEAMID)" \
#                         NOTARY_PROFILE="lucidwallpaper-notary" ./scripts/package.sh
#   (create the keychain profile once with:
#    xcrun notarytool store-credentials lucidwallpaper-notary --apple-id you@apple.com \
#          --team-id TEAMID --password APP_SPECIFIC_PASSWORD)
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:$PATH"

APP_NAME="LucidWallpaper"
CONFIG="Release"
# Build outside iCloud-synced Documents (see scripts/build.sh for why).
DERIVED="$HOME/Library/Caches/LucidWallpaperBuild-release"
PRODUCT="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
DIST="dist"
DEVELOPER_ID_APP="${DEVELOPER_ID_APP:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

echo "==> Generating project"
xcodegen generate

echo "==> Building $CONFIG (unsigned; we sign explicitly below)"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> Stripping extended attributes"
xattr -cr "$PRODUCT"

if [ -n "$DEVELOPER_ID_APP" ]; then
  echo "==> Signing with Developer ID + Hardened Runtime"
  codesign --force --options runtime --timestamp \
    --entitlements Resources/LucidWallpaper.entitlements \
    --sign "$DEVELOPER_ID_APP" "$PRODUCT"
else
  echo "==> No DEVELOPER_ID_APP set - ad-hoc signing."
  echo "    (Runs locally; other Macs will show a Gatekeeper warning until notarized.)"
  codesign --force --sign - "$PRODUCT"
fi
codesign --verify --verbose "$PRODUCT"

mkdir -p "$DIST"

# Notarize the app first (Apple's recommended order), then staple it.
if [ -n "$DEVELOPER_ID_APP" ] && [ -n "$NOTARY_PROFILE" ]; then
  echo "==> Notarizing app"
  ditto -c -k --keepParent "$PRODUCT" "$DIST/$APP_NAME.zip"
  xcrun notarytool submit "$DIST/$APP_NAME.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$PRODUCT"
  rm -f "$DIST/$APP_NAME.zip"
fi

echo "==> Building DMG"
STAGE="$(mktemp -d)"
cp -R "$PRODUCT" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/$APP_NAME.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# Notarize + staple the DMG too, so the download itself passes Gatekeeper.
if [ -n "$DEVELOPER_ID_APP" ] && [ -n "$NOTARY_PROFILE" ]; then
  echo "==> Notarizing DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
else
  echo "==> Skipping notarization (set DEVELOPER_ID_APP and NOTARY_PROFILE to enable)."
fi

echo "==> Done: $DMG"
ls -lh "$DMG"
