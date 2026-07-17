import Foundation

public enum BarState: Equatable {
    case loading
    case loggedOut
    /// A fetch failed and no prior snapshot exists; the app is retrying.
    case error
    case data(UsageSnapshot)
}

public struct MenuBarTitle: Equatable {
    public let text: String
    public let severity: Severity
    public init(text: String, severity: Severity) {
        self.text = text
        self.severity = severity
    }
}

private func glyph(for severity: Severity) -> String {
    switch severity {
    case .normal: return "◐"
    case .warning: return "◑"
    case .critical: return "●"
    }
}

public func renderMenuBarTitle(_ state: BarState, now: Date) -> MenuBarTitle {
    switch state {
    case .loading:
        return MenuBarTitle(text: "◐ …", severity: .normal)
    case .loggedOut:
        return MenuBarTitle(text: "◐ -", severity: .normal)
    case .error:
        return MenuBarTitle(text: "◐ ⚠", severity: .warning)
    case .data(let s):
        let combined = max(s.session.severity, s.weekly.severity)
        if s.session.severity == .critical {
            return MenuBarTitle(text: "● no teto · zera \(countdown(to: s.session.resetsAt, now: now))",
                                severity: .critical)
        }
        let text = "\(glyph(for: combined)) \(s.session.percent)% · zera em \(countdown(to: s.session.resetsAt, now: now))"
        return MenuBarTitle(text: text, severity: combined)
    }
}
