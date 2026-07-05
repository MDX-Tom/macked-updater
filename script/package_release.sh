#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Macked Updater"
PRODUCT_NAME="macked-updater"
BUNDLE_ID="app.macked.updater"
MIN_SYSTEM_VERSION="12.0"
VERSION="0.1.11"
BUILD_NUMBER="12"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
DMG_VERSIONED="$DIST_DIR/MackedUpdater-$VERSION.dmg"
DMG_LATEST="$DIST_DIR/MackedUpdater.dmg"

if [[ -x "/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
  export SDKROOT="${SDKROOT:-/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"
  SWIFT_BIN="${SWIFT_BIN:-/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift}"
else
  SWIFT_BIN="${SWIFT_BIN:-swift}"
fi

cd "$ROOT_DIR"
mkdir -p "$DIST_DIR"
"$SWIFT_BIN" build -c release
BUILD_BIN_DIR="$("$SWIFT_BIN" build -c release --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
find "$BUILD_BIN_DIR" -maxdepth 1 -name '*.resources' -type d -exec cp -R {} "$APP_RESOURCES/" \;
if [[ -d "$ROOT_DIR/Resources" ]]; then
  cp -R "$ROOT_DIR/Resources/"* "$APP_RESOURCES/" 2>/dev/null || true
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

echo -n "APPL????" > "$APP_CONTENTS/PkgInfo"
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

STAGE_DIR="$(mktemp -d /tmp/macked-updater-dmg-stage.XXXXXX)"
trap 'rm -rf "$STAGE_DIR"' EXIT
cp -R "$APP_BUNDLE" "$STAGE_DIR/"
rm -f "$DMG_VERSIONED" "$DMG_LATEST"
hdiutil create -volname "$APP_NAME" -fs HFS+ -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_VERSIONED"
hdiutil verify "$DMG_VERSIONED"
cp "$DMG_VERSIONED" "$DMG_LATEST"

cat <<MSG
Packaged:
  $APP_BUNDLE
  $DMG_VERSIONED
  $DMG_LATEST
MSG
