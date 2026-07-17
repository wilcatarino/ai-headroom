#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ClaudeUsageBar"

APP="build/ClaudeUsageBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudeUsageBar"
cp Packaging/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc code signature so SMAppService / Keychain ACLs behave predictably.
codesign --force --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
