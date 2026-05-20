#!/usr/bin/env bash
# 将 MacCleaner/Version.swift 中的版本号同步到 Info.plist
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="${ROOT}/MacCleaner/Info.plist"
VERSION_FILE="${ROOT}/MacCleaner/Version.swift"

MARKETING=$(grep 'static let marketing' "${VERSION_FILE}" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')

BUILD_LINE=$(grep 'static let build' "${VERSION_FILE}" | head -1)
if [[ "${BUILD_LINE}" == *"marketing"* ]]; then
  BUILD="${MARKETING}"
elif [[ "${BUILD_LINE}" =~ \"([^\"]+)\" ]]; then
  BUILD="${BASH_REMATCH[1]}"
else
  BUILD="${MARKETING}"
fi

if [[ -z "${MARKETING}" ]]; then
  echo "error: cannot read marketing version from ${VERSION_FILE}" >&2
  exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${MARKETING}" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD}" "${PLIST}"

echo "Synced Info.plist -> marketing=${MARKETING}, build=${BUILD}"
