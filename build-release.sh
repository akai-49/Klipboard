#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="${APP_NAME:-Klipboard}"
# project.yml's MARKETING_VERSION is the single source of the version.
VERSION="${VERSION:-$(sed -n 's/.*MARKETING_VERSION: *"\{0,1\}\([0-9.]*\)"\{0,1\}.*/\1/p' project.yml | head -1)}"
BUILD_NUM="${BUILD_NUM:-$(sed -n 's/.*CURRENT_PROJECT_VERSION: *"\{0,1\}\([0-9]*\)"\{0,1\}.*/\1/p' project.yml | head -1)}"
BUNDLE_ID="${BUNDLE_ID:-com.abhishek.Klipboard}"
MIN_MACOS="${MIN_MACOS:-14.0}"
# Universal (Apple Silicon + Intel) by default; e.g. ARCHS=arm64 for a faster local build.
ARCHS="${ARCHS:-arm64 x86_64}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
FEED_URL="${FEED_URL:-https://github.com/akai-49/Klipboard/releases/latest/download/appcast.xml}"

if [ -n "${SPARKLE_PUBLIC_KEY:-}" ]; then
  PUBLIC_ED_KEY="${SPARKLE_PUBLIC_KEY}"
elif [ -f "sparkle-public-key.txt" ]; then
  PUBLIC_ED_KEY="$(cat sparkle-public-key.txt | tr -d '[:space:]')"
else
  PUBLIC_ED_KEY=""
fi

if [ -z "${PUBLIC_ED_KEY}" ]; then
  echo "ERROR: Sparkle public key (SUPublicEDKey) is empty. Set SPARKLE_PUBLIC_KEY or provide non-empty sparkle-public-key.txt" >&2
  exit 1
fi

ROOT_DIR="$(cd .. && pwd)"
DIST_DIR="${DIST_DIR:-$(pwd)/dist}"
APP_BUNDLE="${APP_BUNDLE:-${ROOT_DIR}/${APP_NAME}.app}"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.zip"

SPARKLE_VERSION="2.10.1"
SPARKLE_SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
SPARKLE_DIR="$(pwd)/.build/sparkle-${SPARKLE_VERSION}"
SPARKLE_TAR="${SPARKLE_DIR}/Sparkle-${SPARKLE_VERSION}.tar.xz"

if [ ! -d "${SPARKLE_DIR}/Sparkle.framework" ]; then
  echo "==> Downloading Sparkle ${SPARKLE_VERSION}..."
  mkdir -p "${SPARKLE_DIR}"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" -o "${SPARKLE_TAR}"
  ACTUAL_SHA="$(shasum -a 256 "${SPARKLE_TAR}" | awk '{print $1}')"
  if [ "${ACTUAL_SHA}" != "${SPARKLE_SHA256}" ]; then
    echo "ERROR: Checksum mismatch for Sparkle tarball! Expected ${SPARKLE_SHA256}, got ${ACTUAL_SHA}" >&2
    rm -rf "${SPARKLE_DIR}"
    exit 1
  fi
  tar -xf "${SPARKLE_TAR}" -C "${SPARKLE_DIR}"
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || xcrun --show-sdk-path)"
SOURCES=($(find Klipboard -name '*.swift'))

if [ "${APP_BUNDLE}" = "${ROOT_DIR}/${APP_NAME}.app" ]; then
  echo "==> Stopping any running ${APP_NAME} instances..."
  killall "${APP_NAME}" 2>/dev/null || true
fi

echo "==> Cleaning legacy staging files in ${DIST_DIR}..."
rm -rf "${DIST_DIR}/${APP_NAME}.app" "${DIST_DIR}/dmg-staging" "${DIST_DIR}/.metadata_never_index"
mkdir -p "${DIST_DIR}"

echo "==> Preparing ${APP_BUNDLE}..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
mkdir -p "${APP_BUNDLE}/Contents/Frameworks"

TMP_BIN="${DIST_DIR}/.${APP_NAME}.tmp"
SLICES=()
for ARCH in ${ARCHS}; do
  echo "==> Compiling ${APP_NAME} v${VERSION} (${ARCH}-apple-macosx${MIN_MACOS})..."
  xcrun swiftc -O -whole-module-optimization \
    -sdk "${SDK_PATH}" \
    -target "${ARCH}-apple-macosx${MIN_MACOS}" \
    -F "${SPARKLE_DIR}" -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "${SOURCES[@]}" \
    -o "${TMP_BIN}.${ARCH}"
  SLICES+=("${TMP_BIN}.${ARCH}")
done
lipo -create "${SLICES[@]}" -output "${TMP_BIN}"
rm -f "${SLICES[@]}"

chmod +x "${TMP_BIN}"
mv -f "${TMP_BIN}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

echo "==> Copying Sparkle.framework..."
rm -rf "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
cp -R "${SPARKLE_DIR}/Sparkle.framework" "${APP_BUNDLE}/Contents/Frameworks/"

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
	<string>${MIN_MACOS}</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string></string>
	<key>SUFeedURL</key>
	<string>${FEED_URL}</string>
	<key>SUPublicEDKey</key>
	<string>${PUBLIC_ED_KEY}</string>
</dict>
</plist>
EOF

KEYCHAIN_ARGS=()
if [ -n "${KEYCHAIN:-}" ]; then
  KEYCHAIN_ARGS=(--keychain "${KEYCHAIN}")
fi

REQ_ARGS=()
SPARKLE_REQ_ARGS=()
if [ "${SIGN_IDENTITY}" != "-" ]; then
    # Pin the designated requirement to the signing cert. codesign's auto-generated one
    # can come out unsatisfiable, which makes TCC ignore the Accessibility grant.
    # ponytail: re-grant Accessibility once when the cert is renewed (hash changes).
    FIND_ARGS=(-p codesigning)
    if [ -n "${KEYCHAIN:-}" ]; then
      FIND_ARGS+=("${KEYCHAIN}")
    fi
    CERT_HASH=$(security find-identity "${FIND_ARGS[@]}" 2>/dev/null | grep -F "${SIGN_IDENTITY}" | head -1 | awk '{print $2}')
    if [ -z "${CERT_HASH}" ]; then
      CERT_ARGS=(-c "${SIGN_IDENTITY}" -Z)
      if [ -n "${KEYCHAIN:-}" ]; then
        CERT_ARGS+=("${KEYCHAIN}")
      fi
      CERT_HASH=$(security find-certificate "${CERT_ARGS[@]}" 2>/dev/null | awk '/SHA-1 hash:/ {print $3}' | head -1)
    fi
    if [ -z "${CERT_HASH}" ]; then
      echo "ERROR: Could not find certificate SHA-1 hash for identity '${SIGN_IDENTITY}'" >&2
      exit 1
    fi
    REQ_ARGS=(-r="designated => identifier \"${BUNDLE_ID}\" and certificate leaf = H\"${CERT_HASH}\"")
    SPARKLE_REQ_ARGS=(-r="designated => certificate leaf = H\"${CERT_HASH}\"")
fi

echo "==> Code-signing Sparkle nested components..."
SPARKLE_FW="${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "${SIGN_IDENTITY}" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} ${SPARKLE_REQ_ARGS[@]+"${SPARKLE_REQ_ARGS[@]}"} "${SPARKLE_FW}/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign "${SIGN_IDENTITY}" --preserve-metadata=entitlements ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} ${SPARKLE_REQ_ARGS[@]+"${SPARKLE_REQ_ARGS[@]}"} "${SPARKLE_FW}/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign "${SIGN_IDENTITY}" --preserve-metadata=entitlements ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} ${SPARKLE_REQ_ARGS[@]+"${SPARKLE_REQ_ARGS[@]}"} "${SPARKLE_FW}/Versions/B/Autoupdate"
codesign --force --sign "${SIGN_IDENTITY}" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} ${SPARKLE_REQ_ARGS[@]+"${SPARKLE_REQ_ARGS[@]}"} "${SPARKLE_FW}/Versions/B/Updater.app"
codesign --force --sign "${SIGN_IDENTITY}" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} ${SPARKLE_REQ_ARGS[@]+"${SPARKLE_REQ_ARGS[@]}"} "${SPARKLE_FW}"

echo "==> Code-signing ${APP_NAME}.app..."
codesign --force --sign "${SIGN_IDENTITY}" --identifier "${BUNDLE_ID}" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} ${REQ_ARGS[@]+"${REQ_ARGS[@]}"} --entitlements Klipboard/Resources/Klipboard.entitlements "${APP_BUNDLE}"
codesign --verify --strict "${APP_BUNDLE}"
touch "${APP_BUNDLE}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${APP_BUNDLE}" 2>/dev/null || true

echo "==> Creating drag-and-drop DMG installer (${DMG_PATH})..."
rm -f "${DMG_PATH}" "${ZIP_PATH}"

DMG_TMP="/tmp/${APP_NAME}-dmg-staging.$$.noindex"
rm -rf "${DMG_TMP}"
mkdir -p "${DMG_TMP}"
cp -R "${APP_BUNDLE}" "${DMG_TMP}/"
ln -s /Applications "${DMG_TMP}/Applications"

if hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_TMP}" -ov -format UDZO "${DMG_PATH}" >/dev/null 2>&1; then
  rm -rf "${DMG_TMP}"
else
  rm -rf "${DMG_TMP}"
  python3 scripts/build_dmg.py "${APP_BUNDLE}" "${DMG_PATH}" "${APP_NAME}"
fi

if [ -d "docs" ]; then
  cp -f "${DMG_PATH}" "docs/${APP_NAME}.dmg"
fi

echo "==> Done!"
echo "    App: ${APP_BUNDLE}"
echo "    DMG: ${DMG_PATH}"
