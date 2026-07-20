#!/bin/bash
#
# Builds the "AI Headroom.app" bundle.
#
# Usage:
#   ./Scripts/make-app.sh                 build the bundle into ./build
#   ./Scripts/make-app.sh --install       build, then install into /Applications and (re)launch
#   ./Scripts/make-app.sh --run           build, then (re)launch from ./build
#
# --install is the recommended day-to-day flow: it quits any running copy,
# refreshes "/Applications/AI Headroom.app", and opens the new build so the menu
# bar item comes back with your latest changes.
#
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="build"
case "${1:-}" in
    --install) MODE="install" ;;
    --run)     MODE="run" ;;
    "")        MODE="build" ;;
    *) echo "Unknown option: $1"; echo "Use --install, --run, or no argument."; exit 1 ;;
esac

# The bundle name carries a space so the Finder and Login Items read
# "AI Headroom". The executable inside stays space-free (matches the SwiftPM
# product and CFBundleExecutable), which keeps pgrep/pkill simple.
APP_NAME="AI Headroom"
PRODUCT_NAME="AIHeadroom"
BUILD_APP="build/${APP_NAME}.app"
INSTALLED_APP="/Applications/${APP_NAME}.app"

echo "› Building (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/${PRODUCT_NAME}"

echo "› Assembling ${BUILD_APP}…"
rm -rf "$BUILD_APP"
mkdir -p "${BUILD_APP}/Contents/MacOS"
cp "$BIN" "${BUILD_APP}/Contents/MacOS/${PRODUCT_NAME}"
cp Packaging/Info.plist "${BUILD_APP}/Contents/Info.plist"

# Ad-hoc code signature so SMAppService / Keychain ACLs behave predictably.
codesign --force --sign - "$BUILD_APP" 2>/dev/null || true
echo "✓ Built ${BUILD_APP}"

quit_running() {
    if pgrep -f "${PRODUCT_NAME}" >/dev/null 2>&1; then
        echo "› Quitting running copy…"
        osascript -e "quit app \"${APP_NAME}\"" 2>/dev/null || pkill -f "${PRODUCT_NAME}" || true
        # Give the menu bar a moment to release the old instance.
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            pgrep -f "${PRODUCT_NAME}" >/dev/null 2>&1 || break
            sleep 0.3
        done
    fi
}

case "$MODE" in
    build)
        echo "Done. Run it with:  open \"${BUILD_APP}\""
        echo "Or install with:    ./Scripts/make-app.sh --install"
        ;;
    run)
        quit_running
        echo "› Launching from build…"
        open "$BUILD_APP"
        echo "✓ Running from ${BUILD_APP}"
        ;;
    install)
        quit_running
        echo "› Installing to ${INSTALLED_APP}…"
        rm -rf "$INSTALLED_APP"
        cp -R "$BUILD_APP" "$INSTALLED_APP"
        echo "› Launching…"
        open "$INSTALLED_APP"
        echo "✓ Installed and running from ${INSTALLED_APP}"
        ;;
esac
