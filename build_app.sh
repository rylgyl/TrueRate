#!/bin/zsh
# Builds TrueRate.app into dist/ and ad-hoc signs it.
set -e
cd "$(dirname "$0")"

swift build -c release

APP=dist/TrueRate.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TrueRate "$APP/Contents/MacOS/TrueRate"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
