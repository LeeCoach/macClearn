#!/usr/bin/env bash
# 本地打包 DMG（与 GitHub Actions 流程一致）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"${ROOT}/scripts/sync-version.sh"

APP_NAME="MacCleaner"
VERSION=$(grep 'static let marketing' MacCleaner/Version.swift | sed -E 's/.*"([^"]+)".*/\1/')
APP_BUNDLE="dist/${APP_NAME}.app"
DMG_PATH="dist/${APP_NAME}-${VERSION}.dmg"
DMG_ROOT="dist/dmg-root"
RW_DMG_PATH="/private/tmp/${APP_NAME}-${VERSION}-rw.dmg"
ICON_SOURCE_DIR="MacCleaner/Resources/Assets.xcassets/AppIcon.appiconset"
ICON_TIFF="build/MacCleanerIcon.tiff"

echo "Building ${APP_NAME} ${VERSION}..."
mkdir -p build/swiftpm-cache build/clang-module-cache
SWIFTPM_CACHE_PATH="${ROOT}/build/swiftpm-cache" \
CLANG_MODULE_CACHE_PATH="${ROOT}/build/clang-module-cache" \
swift build -c release --disable-sandbox --scratch-path "${ROOT}/.build"

echo "Generating Finder icon..."
tiffutil -cathidpicheck \
  "${ICON_SOURCE_DIR}/maccleaner-icon-16.png" \
  "${ICON_SOURCE_DIR}/maccleaner-icon-32.png" \
  "${ICON_SOURCE_DIR}/maccleaner-icon-128.png" \
  "${ICON_SOURCE_DIR}/maccleaner-icon-256.png" \
  "${ICON_SOURCE_DIR}/maccleaner-icon-512.png" \
  -out "${ICON_TIFF}" >/dev/null
tiff2icns "${ICON_TIFF}" "MacCleaner/Resources/MacCleanerIcon.icns"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cp ".build/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp "MacCleaner/Info.plist" "${APP_BUNDLE}/Contents/"
cp "MacCleaner/Resources/MacCleanerIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
cp "MacCleaner/Resources/SidebarIcon.png" "${APP_BUNDLE}/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APP_NAME}" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.maccleaner.app" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName MacCleaner" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName MacCleaner" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${APP_BUNDLE}/Contents/Info.plist"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

echo "Verifying app icon..."
ICON_TMP="$(mktemp -d)"
iconutil -c iconset "${APP_BUNDLE}/Contents/Resources/MacCleanerIcon.icns" -o "${ICON_TMP}/MacCleanerIcon.iconset"
if [[ ! -f "${ICON_TMP}/MacCleanerIcon.iconset/icon_512x512.png" && ! -f "${ICON_TMP}/MacCleanerIcon.iconset/icon_512x512@2x.png" ]]; then
  echo "error: MacCleanerIcon.icns does not contain a large Finder icon. Regenerate MacCleaner/Resources/MacCleanerIcon.icns from a valid .iconset." >&2
  exit 1
fi

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "${DEVELOPER_ID_APPLICATION}" "${APP_BUNDLE}"
else
  echo "warning: DEVELOPER_ID_APPLICATION is not set; using ad-hoc signing. macOS Full Disk Access may need to be granted again after each rebuild." >&2
  codesign --force --deep --sign - "${APP_BUNDLE}"
fi
codesign --verify --deep --strict "${APP_BUNDLE}"

rm -f "${DMG_PATH}" "${RW_DMG_PATH}"
rm -rf "${DMG_ROOT}"
mkdir -p "${DMG_ROOT}"
cp -R "${APP_BUNDLE}" "${DMG_ROOT}/"
ln -s /Applications "${DMG_ROOT}/Applications"

sync
for attempt in 1 2 3; do
  if hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_ROOT}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"; then
    break
  fi

  if [[ "${attempt}" == "3" ]]; then
    exit 1
  fi

  sleep 3
  rm -f "${DMG_PATH}"
done
rm -rf "${DMG_ROOT}"

echo "Done: ${DMG_PATH}"
ls -lh "${DMG_PATH}"
