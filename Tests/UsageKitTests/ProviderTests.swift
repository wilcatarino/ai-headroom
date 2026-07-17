import Foundation
import UsageKit

private struct OKHTTP: HTTPClient {
    let data: Data
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, resp)
    }
}

private struct LoggedOutStore: CredentialsStoring, @unchecked Sendable {
    func load() throws -> Credentials? { nil }
    func saveRefreshedTokens(_ t: RefreshedTokens) throws {}
}

private struct StubStore2: CredentialsStoring, @unchecked Sendable {
    func load() throws -> Credentials? {
        Credentials(accessToken: "AT", refreshToken: "RT", expiresAtMillis: 9_000_000_000_000,
                    subscriptionType: "max", rateLimitTier: "default_claude_max_20x")
    }
    func saveRefreshedTokens(_ t: RefreshedTokens) throws {}
}

private struct StubRefresher2: TokenRefreshing {
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        RefreshedTokens(accessToken: "x", refreshToken: "y", expiresAtMillis: 0)
    }
}

func testProvider() async {
    // Snapshots carry the provider identity that produced them.
    let http = OKHTTP(data: T.fixtureData("usage-response"))
    let tokens = TokenProvider(store: StubStore2(), refresher: StubRefresher2(), skewSeconds: 60)
    let provider = AnthropicProvider(http: http, tokenProvider: tokens, plan: { "Max (20x)" })

    T.equal(provider.info, ProviderInfo.anthropic)
    T.equal(provider.info.displayName, "Claude Code")

    let snap = try! await provider.fetch(now: Date(timeIntervalSince1970: 0))
    T.equal(snap.provider, ProviderInfo.anthropic)
    T.equal(snap.session.percent, 10)

    // A provider with no stored credentials surfaces notLoggedIn so the UI can
    // show a per-provider login prompt.
    let out = AnthropicProvider(
        http: http,
        tokenProvider: TokenProvider(store: LoggedOutStore(), refresher: StubRefresher2(), skewSeconds: 60),
        plan: { "" })
    var loggedOut = false
    do { _ = try await out.fetch(now: Date()) }
    catch TokenError.notLoggedIn { loggedOut = true }
    catch { }
    T.expect(loggedOut, "missing credentials throws notLoggedIn")
}
