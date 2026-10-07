#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
DEST="../build/ScreenCompanion.app"
CACHE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/screencompanion-build.XXXXXX")"
trap 'rm -rf "$CACHE_DIR"' EXIT
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path "$CACHE_DIR" \
  -framework AppKit -framework SwiftUI -framework ScreenCaptureKit \
  -framework Security -framework Carbon \
  Core.swift App.swift Tests.swift main.swift \
  -o "$DEST/Contents/MacOS/ScreenCompanion"
cp Info.plist "$DEST/Contents/Info.plist"
codesign --force --sign - --identifier local.screencompanion.macos "$DEST"
"$DEST/Contents/MacOS/ScreenCompanion" --self-test
printf '\nBuilt: %s/build/ScreenCompanion.app\n' "$(cd .. && pwd)"
