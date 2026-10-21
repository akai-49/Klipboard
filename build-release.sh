#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Klipboard"
VERSION="0.1.0"
BUILD_NUM="1"
BUNDLE_ID="com.abhishek.Klipboard"
ROOT_DIR="$(cd .. && pwd)"
DIST_DIR="$(pwd)/dist"
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.zip"

SDK_PATH="$(xcrun --show-sdk-path)"
SOURCES=($(find Klipboard -name '*.swift'))

echo "==> Stopping any running ${APP_NAME} instances..."
killall "${APP_NAME}" 2>/dev/null || true

echo "==> Removing legacy dist/${APP_NAME}.app bundle so Spotlight only indexes one app..."
rm -rf "${DIST_DIR}/${APP_NAME}.app" "${DIST_DIR}/dmg-staging" "${DIST_DIR}/.metadata_never_index"
mkdir -p "${DIST_DIR}"

echo "==> Preparing ${APP_BUNDLE}..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

echo "==> Compiling ${APP_NAME}..."
TMP_BIN="${DIST_DIR}/.${APP_NAME}.tmp"
swiftc -O -whole-module-optimization \
  -sdk "${SDK_PATH}" \
  -target arm64-apple-macosx14.0 \
  "${SOURCES[@]}" \
  -o "${TMP_BIN}"

chmod +x "${TMP_BIN}"
mv -f "${TMP_BIN}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

if [ -f "Klipboard/Resources/AppIcon.icns" ]; then
  cp -f "Klipboard/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

echo "==> Writing Info.plist..."
cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_NUM}</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string></string>
</dict>
</plist>
EOF

echo "==> Code-signing ${APP_NAME}.app..."
codesign --force --deep --sign - --identifier "${BUNDLE_ID}" --entitlements Klipboard/Resources/Klipboard.entitlements "${APP_BUNDLE}"
touch "${APP_BUNDLE}"

echo "==> Creating drag-and-drop DMG installer (${DMG_PATH})..."
rm -f "${DMG_PATH}" "${ZIP_PATH}"

DMG_TMP="/tmp/klipboard-dmg-staging.$$.noindex"
rm -rf "${DMG_TMP}"
mkdir -p "${DMG_TMP}"
cp -R "${APP_BUNDLE}" "${DMG_TMP}/"
ln -s /Applications "${DMG_TMP}/Applications"

if hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_TMP}" -ov -format UDZO "${DMG_PATH}" >/dev/null 2>&1; then
  rm -rf "${DMG_TMP}"
else
  rm -rf "${DMG_TMP}"
  python3 scripts/build_dmg.py "${APP_BUNDLE}" "${DMG_PATH}"
fi

echo "==> Done!"
echo "    App: ${APP_BUNDLE}"
echo "    DMG: ${DMG_PATH}"
