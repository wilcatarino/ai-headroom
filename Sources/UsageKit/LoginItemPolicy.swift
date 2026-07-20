import Foundation

/// Whether the app should manage its start-at-login registration.
///
/// `SMAppService` only behaves for a real `.app` bundle installed under an
/// Applications folder. Registering from anywhere else leaves stray login items
/// behind:
/// - Running a bare executable (`swift run` or the `.build` debug binary during
///   development) would register that binary, which macOS then opens inside a
///   Terminal at every login.
/// - Running the `.app` from a temporary spot (e.g. `~/Downloads`) would create
///   a login item that orphans as soon as the app is moved or deleted.
///
/// Guarding on this keeps both developer and end-user machines clean; the app
/// only auto-enables (and only lets the menu toggle) start-at-login once it
/// lives in Applications.
public func canManageLoginItem(bundlePath: String) -> Bool {
    guard bundlePath.hasSuffix(".app") else { return false }
    return bundlePath.contains("/Applications/")
}
