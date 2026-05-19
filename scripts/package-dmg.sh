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

rm -f "${DMG_PATH}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_BUNDLE}" -ov -format UDZO "${DMG_PATH}"

echo "Done: ${DMG_PATH}"
ls -lh "${DMG_PATH}"
