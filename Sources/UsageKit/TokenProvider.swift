import Foundation

public func isExpired(expiresAtMillis: Int, now: Date, skewSeconds: Int) -> Bool {
    let expiry = Double(expiresAtMillis) / 1000.0
    return expiry - Double(skewSeconds) <= now.timeIntervalSince1970
}

public struct RefreshedTokens: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAtMillis: Int
    public init(accessToken: String, refreshToken: String, expiresAtMillis: Int) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAtMillis = expiresAtMillis
    }
}

public protocol TokenRefreshing: Sendable {
    func refresh(refreshToken: String) async throws -> RefreshedTokens
}

public protocol CredentialsStoring: Sendable {
    func load() throws -> Credentials?
    func saveRefreshedTokens(_ t: RefreshedTokens) throws
}

public enum TokenError: Error { case notLoggedIn }

public actor TokenProvider {
    private let store: CredentialsStoring
    private let refresher: TokenRefreshing
    private let skewSeconds: Int

    /// Credentials loaded once at startup and handed to the first token check,
    /// so the actor does not read the store a second time during launch. The
    /// keychain prompts on each distinct read, so collapsing the startup reads
    /// to one keeps launch at a single prompt. Consumed after the first use;
    /// later calls read the store normally (no prompt within the session).
    private var seed: Credentials?

    public init(store: CredentialsStoring, refresher: TokenRefreshing, skewSeconds: Int = 60,
                initialCredentials: Credentials? = nil) {
        self.store = store
        self.refresher = refresher
        self.skewSeconds = skewSeconds
        self.seed = initialCredentials
    }

    public func validAccessToken(now: Date) async throws -> String {
        let creds: Credentials
        if let seeded = seed {
            seed = nil
            creds = seeded
        } else {
            guard let loaded = try store.load() else { throw TokenError.notLoggedIn }
            creds = loaded
        }
        guard isExpired(expiresAtMillis: creds.expiresAtMillis, now: now, skewSeconds: skewSeconds) else {
            return creds.accessToken
        }
        let refreshed = try await refresher.refresh(refreshToken: creds.refreshToken)
        try store.saveRefreshedTokens(refreshed)
        return refreshed.accessToken
    }
}
