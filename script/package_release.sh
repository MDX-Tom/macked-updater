#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Macked Updater"
PRODUCT_NAME="macked-updater"
BUNDLE_ID="app.macked.updater"
MIN_SYSTEM_VERSION="12.0"
VERSION="0.1.0"
BUILD_NUMBER="1"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_ROOT="${BUILD_ROOT:-/tmp/macked-updater-package-build}"
APP_UNIVERSAL="$DIST_DIR/$APP_NAME-universal.app"
APP_ARM64="$DIST_DIR/$APP_NAME-arm64.app"
APP_INTEL="$DIST_DIR/$APP_NAME-intel.app"
APP_DEFAULT="$DIST_DIR/$APP_NAME.app"
DMG_UNIVERSAL="$DIST_DIR/MackedUpdater_${VERSION}_universal.dmg"
DMG_ARM64="$DIST_DIR/MackedUpdater_${VERSION}_apple_silicon_aarch64.dmg"
DMG_INTEL="$DIST_DIR/MackedUpdater_${VERSION}_intel_x64.dmg"

if [[ -x "/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
  export SDKROOT="${SDKROOT:-/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"
  SWIFT_BIN="${SWIFT_BIN:-/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift}"
else
  SWIFT_BIN="${SWIFT_BIN:-swift}"
fi

cd "$ROOT_DIR"
mkdir -p "$DIST_DIR" "$BUILD_ROOT"

write_info_plist() {
  local info_plist="$1"
  cat >"$info_plist" <<PLIST
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
}

copy_resources() {
  local build_bin_dir="$1"
  local app_resources="$2"

  find "$build_bin_dir" -maxdepth 1 -name '*.resources' -type d -exec cp -R {} "$app_resources/" \;
  if [[ -d "$ROOT_DIR/Resources" ]]; then
    cp -R "$ROOT_DIR/Resources/"* "$app_resources/" 2>/dev/null || true
  fi
}

build_arch() {
  local arch="$1"
  local scratch="$BUILD_ROOT/$arch"
  rm -rf "$scratch"
  "$SWIFT_BIN" build -c release --arch "$arch" --scratch-path "$scratch" >&2
  "$SWIFT_BIN" build -c release --arch "$arch" --scratch-path "$scratch" --show-bin-path
}

create_app_bundle() {
  local app_bundle="$1"
  local binary_path="$2"
  local resources_bin_dir="$3"

  local app_contents="$app_bundle/Contents"
  local app_macos="$app_contents/MacOS"
  local app_resources="$app_contents/Resources"
  local app_binary="$app_macos/$APP_NAME"
  local info_plist="$app_contents/Info.plist"

  rm -rf "$app_bundle"
  mkdir -p "$app_macos" "$app_resources"
  cp "$binary_path" "$app_binary"
  chmod +x "$app_binary"
  copy_resources "$resources_bin_dir" "$app_resources"
  write_info_plist "$info_plist"
  echo -n "APPL????" > "$app_contents/PkgInfo"
  codesign --force --deep --sign - "$app_bundle" >/dev/null
  codesign --verify --deep --strict --verbose=2 "$app_bundle"
}

create_dmg() {
  local app_bundle="$1"
  local dmg_path="$2"

  local stage_dir
  stage_dir="$(mktemp -d /tmp/macked-updater-dmg-stage.XXXXXX)"
  cp -R "$app_bundle" "$stage_dir/$APP_NAME.app"
  ln -s /Applications "$stage_dir/Applications"
  rm -f "$dmg_path"
  hdiutil create -volname "$APP_NAME" -fs HFS+ -srcfolder "$stage_dir" -ov -format UDZO "$dmg_path"
  hdiutil verify "$dmg_path"
  rm -rf "$stage_dir"
}

echo "Building release binaries for arm64 and Intel..."
ARM64_BIN_DIR="$(build_arch arm64)"
INTEL_BIN_DIR="$(build_arch x86_64)"
ARM64_BINARY="$ARM64_BIN_DIR/$PRODUCT_NAME"
INTEL_BINARY="$INTEL_BIN_DIR/$PRODUCT_NAME"
UNIVERSAL_BINARY="$BUILD_ROOT/$PRODUCT_NAME-universal"

lipo -create -output "$UNIVERSAL_BINARY" "$ARM64_BINARY" "$INTEL_BINARY"
file "$ARM64_BINARY"
file "$INTEL_BINARY"
file "$UNIVERSAL_BINARY"

echo "Creating app bundles..."
create_app_bundle "$APP_ARM64" "$ARM64_BINARY" "$ARM64_BIN_DIR"
create_app_bundle "$APP_INTEL" "$INTEL_BINARY" "$ARM64_BIN_DIR"
create_app_bundle "$APP_UNIVERSAL" "$UNIVERSAL_BINARY" "$ARM64_BIN_DIR"
rm -rf "$APP_DEFAULT"
cp -R "$APP_UNIVERSAL" "$APP_DEFAULT"

echo "Creating DMGs with /Applications shortcuts..."
rm -f \
  "$DIST_DIR/MackedUpdater-$VERSION-universal.dmg" \
  "$DIST_DIR/MackedUpdater-$VERSION-arm64.dmg" \
  "$DIST_DIR/MackedUpdater-$VERSION-intel.dmg" \
  "$DIST_DIR/MackedUpdater-universal.dmg" \
  "$DIST_DIR/MackedUpdater-arm64.dmg" \
  "$DIST_DIR/MackedUpdater-intel.dmg" \
  "$DIST_DIR/MackedUpdater.dmg"
create_dmg "$APP_UNIVERSAL" "$DMG_UNIVERSAL"
create_dmg "$APP_ARM64" "$DMG_ARM64"
create_dmg "$APP_INTEL" "$DMG_INTEL"

cat <<MSG
Packaged version $VERSION ($BUILD_NUMBER):
  Universal app: $APP_UNIVERSAL
  Apple Silicon app: $APP_ARM64
  Intel app: $APP_INTEL
  Default app: $APP_DEFAULT
  Universal DMG: $DMG_UNIVERSAL
  Apple Silicon DMG: $DMG_ARM64
  Intel DMG: $DMG_INTEL
MSG
