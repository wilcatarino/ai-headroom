import Foundation

public enum UsageClientError: Error { case http(Int) }

public struct UsageClient: Sendable {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let http: HTTPClient
    private let tokenProvider: TokenProvider
    private let plan: @Sendable () -> String

    public init(http: HTTPClient, tokenProvider: TokenProvider, plan: @escaping @Sendable () -> String) {
        self.http = http
        self.tokenProvider = tokenProvider
        self.plan = plan
    }

    public func fetch(now: Date) async throws -> UsageSnapshot {
        let token = try await tokenProvider.validAccessToken(now: now)
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw UsageClientError.http(response.statusCode)
        }
        let decoded = try UsageResponse.decode(data)
        return UsageSnapshot.from(decoded, provider: .anthropic, plan: plan(), fetchedAt: now)
    }
}
