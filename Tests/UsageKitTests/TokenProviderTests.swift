import Foundation
import UsageKit

private final class FakeStore: CredentialsStoring, @unchecked Sendable {
    var creds: Credentials?
    var saved: RefreshedTokens?
    func load() throws -> Credentials? { creds }
    func saveRefreshedTokens(_ t: RefreshedTokens) throws { saved = t }
}

private final class FakeRefresher: TokenRefreshing, @unchecked Sendable {
    var calls = 0
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        calls += 1
        return RefreshedTokens(accessToken: "AT2", refreshToken: "RT2", expiresAtMillis: 9_000_000_000_000)
    }
}

func testTokenProvider() async {
    // expiry uses skew
    let now = Date(timeIntervalSince1970: 1000)
    T.equal(isExpired(expiresAtMillis: 1030_000, now: now, skewSeconds: 60), true)
    T.equal(isExpired(expiresAtMillis: 1120_000, now: now, skewSeconds: 60), false)

    // valid token returned unchanged
    let store = FakeStore()
    store.creds = Credentials(accessToken: "AT1", refreshToken: "RT1",
                              expiresAtMillis: 9_000_000_000_000, subscriptionType: "max", rateLimitTier: nil)
    let refresher = FakeRefresher()
    let provider = TokenProvider(store: store, refresher: refresher, skewSeconds: 60)
    let token = try! await provider.validAccessToken(now: now)
    T.equal(token, "AT1")
    T.equal(refresher.calls, 0)

    // expired -> refresh + persist
    let store2 = FakeStore()
    store2.creds = Credentials(accessToken: "AT1", refreshToken: "RT1",
                               expiresAtMillis: 500_000, subscriptionType: "max", rateLimitTier: nil)
    let refresher2 = FakeRefresher()
    let provider2 = TokenProvider(store: store2, refresher: refresher2, skewSeconds: 60)
    let token2 = try! await provider2.validAccessToken(now: now)
    T.equal(token2, "AT2")
    T.equal(refresher2.calls, 1)
    T.equal(store2.saved?.accessToken, "AT2")

    // not logged in throws
    var threw = false
    let provider3 = TokenProvider(store: FakeStore(), refresher: FakeRefresher(), skewSeconds: 60)
    do { _ = try await provider3.validAccessToken(now: now) } catch { threw = true }
    T.expect(threw, "notLoggedIn throws")
}
