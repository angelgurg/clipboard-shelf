#!/bin/bash
# Builds build/ClipboardShelf.app. Installing is scripts/install.sh.
# Signed with the "Local Self-Signed" certificate when it exists, so the Accessibility
# permission survives rebuilds (an ad hoc signature changes on every build and loses it).
# Usage: ./build.sh [--universal]   (--universal: arm64 + x86_64)
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(cat VERSION)
APP=build/ClipboardShelf.app

# SwiftUI on the macOS 27 SDK needs full Xcode's macro plugins; use Xcode when it's installed.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

ARCH_FLAGS=()
[ "${1:-}" = "--universal" ] && ARCH_FLAGS=(--arch arm64 --arch x86_64)

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN=$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ClipboardShelf" "$APP/Contents/MacOS/ClipboardShelf"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.stanimir93.clipboardshelf</string>
  <key>CFBundleName</key><string>Clipboard Shelf</string>
  <key>CFBundleDisplayName</key><string>Clipboard Shelf</string>
  <key>CFBundleExecutable</key><string>ClipboardShelf</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

IDENTITY=-
security find-identity -v -p codesigning | grep -q '"Local Self-Signed"' && IDENTITY="Local Self-Signed"
codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP ($VERSION, signed: $IDENTITY)"
