import Foundation
import UsageKit

func testLoginItemPolicy() {
    // Installed in Applications: manageable.
    T.expect(canManageLoginItem(bundlePath: "/Applications/AI Headroom.app"),
             "system Applications is manageable")
    T.expect(canManageLoginItem(bundlePath: "/Users/wilson/Applications/AI Headroom.app"),
             "user Applications is manageable")

    // The dev binary that caused a Terminal to open at login: not a .app.
    T.expect(!canManageLoginItem(bundlePath:
        "/Users/wilson/proj/.build/arm64-apple-macosx/debug/AIHeadroom"),
             "bare debug executable is not manageable")

    // A .app run from a throwaway location would orphan its login item.
    T.expect(!canManageLoginItem(bundlePath: "/Users/wilson/Downloads/AI Headroom.app"),
             "Downloads .app is not manageable")

    // The executable path inside the bundle is not the bundle path.
    T.expect(!canManageLoginItem(bundlePath: "/Applications/AI Headroom.app/Contents/MacOS/AIHeadroom"),
             "executable path inside the bundle is not manageable")
}
