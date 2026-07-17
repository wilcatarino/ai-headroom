import Foundation

public struct UsageResponse: Decodable {
    struct Window: Decodable { let utilization: Double?; let resets_at: String? }
    struct Model: Decodable { let id: String?; let display_name: String? }
    struct Scope: Decodable { let model: Model? }
    struct Limit: Decodable {
        let kind: String?
        let group: String?
        let percent: Int?
        let severity: String?
        let resets_at: String?
        let scope: Scope?
        let is_active: Bool?
    }
    let five_hour: Window?
    let seven_day: Window?
    let limits: [Limit]?

    public static func decode(_ data: Data) throws -> UsageResponse {
        try JSONDecoder().decode(UsageResponse.self, from: data)
    }
}

/// Parses the API's ISO8601-with-fractional-seconds timestamps.
func parseAPITimestamp(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
}
