#!/usr/bin/env bash
# 本地打包 DMG（与 GitHub Actions 流程一致）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MacCleaner"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" MacCleaner/Info.plist)
APP_BUNDLE="dist/${APP_NAME}.app"
DMG_PATH="dist/${APP_NAME}-${VERSION}.dmg"

echo "Building ${APP_NAME} ${VERSION}..."
swift build -c release

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cp ".build/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp "MacCleaner/Info.plist" "${APP_BUNDLE}/Contents/"
cp "MacCleaner/Resources/MacCleanerIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
cp "MacCleaner/Resources/SidebarIcon.png" "${APP_BUNDLE}/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APP_NAME}" "${APP_BUNDLE}/Contents/Info.plist"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# 本地 ad-hoc 签名，避免 Gatekeeper 提示「已损坏」（仍需用户在首次打开时允许）
codesign --force --deep --sign - "${APP_BUNDLE}"
codesign --verify --deep --strict "${APP_BUNDLE}"

DMG_ROOT="dist/dmg-root"
rm -f "${DMG_PATH}"
rm -rf "${DMG_ROOT}"
mkdir -p "${DMG_ROOT}"
cp -R "${APP_BUNDLE}" "${DMG_ROOT}/"
ln -s /Applications "${DMG_ROOT}/Applications"

hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_ROOT}" -ov -format UDZO "${DMG_PATH}"
rm -rf "${DMG_ROOT}"

echo "Done: ${DMG_PATH}"
ls -lh "${DMG_PATH}"
