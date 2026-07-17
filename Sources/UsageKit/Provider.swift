import Foundation

/// Identity of a usage provider as shown in the UI. Kept separate from the live
/// data so the provider can still be named while logged out or in an error
/// state, when there is no snapshot to read a name from.
public struct ProviderInfo: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

extension ProviderInfo {
    public static let anthropic = ProviderInfo(id: "anthropic", displayName: "Claude Code")
}

/// A source of usage data. Each provider reads its own credentials and maps its
/// API onto a `UsageSnapshot`. `fetch` throws `TokenError.notLoggedIn` when the
/// provider has no stored credentials, so the UI can show a per-provider login
/// prompt.
public protocol UsageProvider: Sendable {
    var info: ProviderInfo { get }
    func fetch(now: Date) async throws -> UsageSnapshot
}
