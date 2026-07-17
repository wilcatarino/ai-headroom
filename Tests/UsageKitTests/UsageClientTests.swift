import Foundation
import UsageKit

private final class AuthBox: @unchecked Sendable { var value: String? }

private struct FakeHTTP: HTTPClient {
    let data: Data
    let status: Int
    let authBox = AuthBox()
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        authBox.value = request.value(forHTTPHeaderField: "Authorization")
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, resp)
    }
}

private final class StubStore: CredentialsStoring, @unchecked Sendable {
    func load() throws -> Credentials? {
        Credentials(accessToken: "AT-TEST", refreshToken: "RT", expiresAtMillis: 9_000_000_000_000,
                    subscriptionType: "max", rateLimitTier: "default_claude_max_20x")
    }
    func saveRefreshedTokens(_ t: RefreshedTokens) throws {}
}

private struct StubRefresher: TokenRefreshing {
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        RefreshedTokens(accessToken: "x", refreshToken: "y", expiresAtMillis: 0)
    }
}

func testUsageClient() async {
    let http = FakeHTTP(data: T.fixtureData("usage-response"), status: 200)
    let provider = TokenProvider(store: StubStore(), refresher: StubRefresher(), skewSeconds: 60)
    let client = UsageClient(http: http, tokenProvider: provider, plan: { "Max (20x)" })
    let snap = try! await client.fetch(now: Date(timeIntervalSince1970: 0))
    T.equal(snap.session.percent, 10)
    T.equal(snap.weekly.percent, 22)
    T.equal(http.authBox.value, "Bearer AT-TEST")

    // HTTP error throws
    let http2 = FakeHTTP(data: Data("{}".utf8), status: 401)
    let provider2 = TokenProvider(store: StubStore(), refresher: StubRefresher(), skewSeconds: 60)
    let client2 = UsageClient(http: http2, tokenProvider: provider2, plan: { "Max" })
    var threw = false
    do { _ = try await client2.fetch(now: Date()) } catch { threw = true }
    T.expect(threw, "HTTP 401 throws")
}
