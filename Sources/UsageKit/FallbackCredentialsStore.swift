import Foundation

/// Reads credentials from a primary source, falling back to a secondary when
/// the primary has nothing (or fails). On macOS the primary is the keychain and
/// the secondary is the on-disk file, so a dev who keeps Claude Code credentials
/// outside the keychain is still picked up.
///
/// Routing is stateless: `saveRefreshedTokens` writes to whichever source holds
/// the item. The primary's save reports `notLoggedIn` when it lacks the item, so
/// that signal alone tells us to write to the secondary instead. No memory of
/// where `load` last read is needed.
public struct FallbackCredentialsStore: CredentialsStoring {
    private let primary: CredentialsStoring
    private let secondary: CredentialsStoring

    public init(primary: CredentialsStoring, secondary: CredentialsStoring) {
        self.primary = primary
        self.secondary = secondary
    }

    public func load() throws -> Credentials? {
        // A primary read error (e.g. the user denied the keychain prompt) must
        // not hide a perfectly readable file, so swallow it and fall through.
        if let creds = try? primary.load() { return creds }
        return try secondary.load()
    }

    public func saveRefreshedTokens(_ t: RefreshedTokens) throws {
        do {
            try primary.saveRefreshedTokens(t)
        } catch TokenError.notLoggedIn {
            try secondary.saveRefreshedTokens(t)
        }
    }
}
