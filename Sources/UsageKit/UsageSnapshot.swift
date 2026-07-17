import Foundation

public enum Severity: String, Comparable {
    case normal, warning, critical
    private var rank: Int { switch self { case .normal: 0; case .warning: 1; case .critical: 2 } }
    public static func < (a: Severity, b: Severity) -> Bool { a.rank < b.rank }
}

/// Server severity string wins when it maps to a known bucket; otherwise fall
/// back to percent thresholds (>=90 critical, >=70 warning).
public func severity(from serverValue: String?, percent: Int) -> Severity {
    switch serverValue?.lowercased() {
    case "critical", "blocked", "exceeded": return .critical
    case "warning", "approaching": return .warning
    default:
        if percent >= 90 { return .critical }
        if percent >= 70 { return .warning }
        return .normal
    }
}

public struct UsageWindow: Equatable {
    public let percent: Int
    public let severity: Severity
    public let resetsAt: Date?
    public init(percent: Int, severity: Severity, resetsAt: Date?) {
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
    }
}

public struct ModelUsage: Equatable {
    public let name: String
    public let percent: Int
    public let severity: Severity
    public let resetsAt: Date?
    public init(name: String, percent: Int, severity: Severity, resetsAt: Date?) {
        self.name = name
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Equatable {
    public let plan: String
    public let session: UsageWindow
    public let weekly: UsageWindow
    public let models: [ModelUsage]
    public let fetchedAt: Date
    public init(plan: String, session: UsageWindow, weekly: UsageWindow, models: [ModelUsage], fetchedAt: Date) {
        self.plan = plan
        self.session = session
        self.weekly = weekly
        self.models = models
        self.fetchedAt = fetchedAt
    }
}

extension UsageSnapshot {
    public static func from(_ r: UsageResponse, plan: String, fetchedAt: Date) -> UsageSnapshot {
        let limits = r.limits ?? []

        func window(kind: String, fallback: UsageResponse.Window?) -> UsageWindow {
            if let l = limits.first(where: { $0.kind == kind }) {
                let pct = l.percent ?? Int((fallback?.utilization ?? 0).rounded())
                return UsageWindow(percent: pct,
                                   severity: severity(from: l.severity, percent: pct),
                                   resetsAt: parseAPITimestamp(l.resets_at) ?? parseAPITimestamp(fallback?.resets_at))
            }
            let pct = Int((fallback?.utilization ?? 0).rounded())
            return UsageWindow(percent: pct,
                               severity: severity(from: nil, percent: pct),
                               resetsAt: parseAPITimestamp(fallback?.resets_at))
        }

        let session = window(kind: "session", fallback: r.five_hour)
        let weekly = window(kind: "weekly_all", fallback: r.seven_day)

        let models: [ModelUsage] = limits.compactMap { l in
            guard let name = l.scope?.model?.display_name, let pct = l.percent, pct > 0 else { return nil }
            return ModelUsage(name: name, percent: pct,
                              severity: severity(from: l.severity, percent: pct),
                              resetsAt: parseAPITimestamp(l.resets_at))
        }

        return UsageSnapshot(plan: plan, session: session, weekly: weekly, models: models, fetchedAt: fetchedAt)
    }
}
