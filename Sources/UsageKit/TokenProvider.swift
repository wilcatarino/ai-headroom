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

    public init(store: CredentialsStoring, refresher: TokenRefreshing, skewSeconds: Int = 60) {
        self.store = store
        self.refresher = refresher
        self.skewSeconds = skewSeconds
    }

    public func validAccessToken(now: Date) async throws -> String {
        guard let creds = try store.load() else { throw TokenError.notLoggedIn }
        guard isExpired(expiresAtMillis: creds.expiresAtMillis, now: now, skewSeconds: skewSeconds) else {
            return creds.accessToken
        }
        let refreshed = try await refresher.refresh(refreshToken: creds.refreshToken)
        try store.saveRefreshedTokens(refreshed)
        return refreshed.accessToken
    }
}
