import Foundation

/// Claude Code usage, read from the OAuth credentials the CLI stores in the
/// macOS Keychain and the same endpoint that backs the `/usage` command. This
/// is the first `UsageProvider`; new providers (Cursor, Copilot, ...) conform
/// to the same protocol and slot into the same UI.
public struct AnthropicProvider: UsageProvider {
    public var info: ProviderInfo { .anthropic }

    private let client: UsageClient

    public init(http: HTTPClient, tokenProvider: TokenProvider, plan: @escaping @Sendable () -> String) {
        self.client = UsageClient(http: http, tokenProvider: tokenProvider, plan: plan)
    }

    public func fetch(now: Date) async throws -> UsageSnapshot {
        try await client.fetch(now: now)
    }
}
