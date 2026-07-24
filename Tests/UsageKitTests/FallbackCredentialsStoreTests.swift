import Foundation
import UsageKit

private final class StubStore: CredentialsStoring, @unchecked Sendable {
    var creds: Credentials?
    var loadError: Error?
    var saveError: Error?
    var saved: RefreshedTokens?
    func load() throws -> Credentials? {
        if let loadError { throw loadError }
        return creds
    }
    func saveRefreshedTokens(_ t: RefreshedTokens) throws {
        if let saveError { throw saveError }
        saved = t
    }
}

private func creds(_ at: String) -> Credentials {
    Credentials(accessToken: at, refreshToken: "RT", expiresAtMillis: 1,
                subscriptionType: nil, rateLimitTier: nil)
}

func testFallbackCredentialsStore() {
    let tokens = RefreshedTokens(accessToken: "AT", refreshToken: "RT", expiresAtMillis: 1)

    // Primary has creds: load returns them, secondary untouched.
    let p1 = StubStore(); p1.creds = creds("PRIMARY")
    let s1 = StubStore(); s1.creds = creds("SECONDARY")
    let f1 = FallbackCredentialsStore(primary: p1, secondary: s1)
    T.equal((try! f1.load())?.accessToken, "PRIMARY")

    // Primary empty: load falls through to secondary.
    let p2 = StubStore()
    let s2 = StubStore(); s2.creds = creds("SECONDARY")
    let f2 = FallbackCredentialsStore(primary: p2, secondary: s2)
    T.equal((try! f2.load())?.accessToken, "SECONDARY")

    // Primary errors on read: still falls through to secondary.
    let p3 = StubStore(); p3.loadError = KeychainError.status(-25300)
    let s3 = StubStore(); s3.creds = creds("SECONDARY")
    let f3 = FallbackCredentialsStore(primary: p3, secondary: s3)
    T.equal((try! f3.load())?.accessToken, "SECONDARY")

    // Both empty: load is nil.
    let f4 = FallbackCredentialsStore(primary: StubStore(), secondary: StubStore())
    T.expect((try! f4.load()) == nil, "both empty -> nil")

    // Save goes to the primary when it holds the item.
    let p5 = StubStore(); let s5 = StubStore()
    try! FallbackCredentialsStore(primary: p5, secondary: s5).saveRefreshedTokens(tokens)
    T.equal(p5.saved?.accessToken, "AT")
    T.expect(s5.saved == nil, "primary write does not touch secondary")

    // Save routes to secondary when the primary reports notLoggedIn.
    let p6 = StubStore(); p6.saveError = TokenError.notLoggedIn
    let s6 = StubStore()
    try! FallbackCredentialsStore(primary: p6, secondary: s6).saveRefreshedTokens(tokens)
    T.equal(s6.saved?.accessToken, "AT")
}
