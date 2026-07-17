import Foundation

public struct OAuthRefresher: TokenRefreshing {
    static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    private let http: HTTPClient
    private let clock: @Sendable () -> Date

    public init(http: HTTPClient, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http
        self.clock = clock
    }

    private struct Response: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }

    public func refresh(refreshToken: String) async throws -> RefreshedTokens {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw UsageClientError.http(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let expiresAt = Int((clock().timeIntervalSince1970 + Double(decoded.expires_in)) * 1000)
        return RefreshedTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? refreshToken,
            expiresAtMillis: expiresAt)
    }
}
