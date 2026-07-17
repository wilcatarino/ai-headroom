import Foundation

public enum UsageKit {
    public static let marker = "usagekit"
}

public struct Credentials: Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAtMillis: Int
    public let subscriptionType: String?
    public let rateLimitTier: String?

    public init(accessToken: String, refreshToken: String, expiresAtMillis: Int,
                subscriptionType: String?, rateLimitTier: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAtMillis = expiresAtMillis
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }
}

/// Builds the human label, e.g. "Max (20x)". `rateLimitTier` looks like
/// "default_claude_max_20x"; we extract a trailing "<n>x" multiplier if present.
public func planLabel(subscriptionType: String?, rateLimitTier: String?) -> String {
    guard let sub = subscriptionType, !sub.isEmpty else { return "Claude Code" }
    let name = sub.prefix(1).uppercased() + sub.dropFirst()
    if let tier = rateLimitTier,
       let match = tier.split(separator: "_").last(where: { $0.hasSuffix("x") && $0.dropLast().allSatisfy(\.isNumber) }) {
        return "\(name) (\(match))"
    }
    return name
}
