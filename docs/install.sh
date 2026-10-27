#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Klipboard"
VERSION="${KLIPBOARD_VERSION:-0.1.0}"
INSTALL_DIR="/Applications"
APP_DEST="${INSTALL_DIR}/${APP_NAME}.app"
DMG_URL="${KLIPBOARD_DMG_URL:-https://klipboard-beryl.vercel.app/${APP_NAME}.dmg}"
FALLBACK_URL="https://github.com/akai-49/Klipboard/releases/download/v${VERSION}/${APP_NAME}-${VERSION}.dmg"

TMP_DIR="$(mktemp -d "/tmp/klipboard-install.XXXXXX")"
DMG_FILE="${TMP_DIR}/${APP_NAME}-${VERSION}.dmg"
MOUNT_POINT="${TMP_DIR}/mount"

cleanup() {
  if [ -d "${MOUNT_POINT}" ]; then
    hdiutil detach "${MOUNT_POINT}" -quiet 2>/dev/null || true
  fi
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "==> Downloading ${APP_NAME} v${VERSION}..."
if ! curl -fsSL "${DMG_URL}" -o "${DMG_FILE}" 2>/dev/null; then
  echo "==> Primary mirror unavailable, trying GitHub Releases..."
  curl -fsSL "${FALLBACK_URL}" -o "${DMG_FILE}"
fi

echo "==> Mounting disk image..."
mkdir -p "${MOUNT_POINT}"
hdiutil attach "${DMG_FILE}" -mountpoint "${MOUNT_POINT}" -nobrowse -quiet

echo "==> Stopping any running ${APP_NAME} instance..."
killall "${APP_NAME}" 2>/dev/null || true

echo "==> Installing ${APP_NAME}.app to ${INSTALL_DIR}..."
rm -rf "${APP_DEST}"
cp -R "${MOUNT_POINT}/${APP_NAME}.app" "${APP_DEST}"

echo "==> Removing macOS Gatekeeper quarantine attributes..."
xattr -cr "${APP_DEST}" 2>/dev/null || true

echo "==> Launching ${APP_NAME}..."
open "${APP_DEST}"

echo ""
echo "✓ ${APP_NAME} v${VERSION} installed to ${APP_DEST} and launched!"
echo "  Press Option+V (⌥V) or Command+Shift+V (⌘⇧V) anytime to open your clipboard history."
