import Foundation

public enum CredentialsBlobError: Error { case malformed }

public enum CredentialsBlob {
    public static func parse(_ data: Data) throws -> Credentials {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let access = oauth["accessToken"] as? String,
              let refresh = oauth["refreshToken"] as? String,
              let expires = oauth["expiresAt"] as? Int
        else { throw CredentialsBlobError.malformed }
        return Credentials(
            accessToken: access,
            refreshToken: refresh,
            expiresAtMillis: expires,
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String
        )
    }

    /// Returns a new blob with only the three token fields inside `claudeAiOauth`
    /// replaced. Every other key (including sibling `mcpOAuth`) is preserved.
    public static func writingRefreshedTokens(
        into data: Data, accessToken: String, refreshToken: String, expiresAtMillis: Int
    ) throws -> Data {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any]
        else { throw CredentialsBlobError.malformed }
        oauth["accessToken"] = accessToken
        oauth["refreshToken"] = refreshToken
        oauth["expiresAt"] = expiresAtMillis
        root["claudeAiOauth"] = oauth
        return try JSONSerialization.data(withJSONObject: root)
    }
}
