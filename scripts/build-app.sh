#!/usr/bin/env bash
# Builds "Space Manager.app" into ./build using SwiftPM.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/Space Manager.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MacSpaceManager" "$APP/Contents/MacOS/MacSpaceManager"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature so macOS can remember the Full Disk Access grant.
codesign --force --deep --sign - "$APP"

ditto -c -k --keepParent "$APP" "build/Space-Manager.zip"

echo "Built $APP"
echo "Run: open \"$APP\""
