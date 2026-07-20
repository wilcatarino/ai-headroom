import AppKit
import UsageKit

/// Central place for the severity colors, so the menu bar title and the panel
/// stay in sync and the tones are easy to tweak.
enum Palette {
    // systemOrange reads well on the menu bar in light and dark, and adapts to
    // accessibility settings. Chosen over plain yellow (too faded) and a custom
    // amber (a touch pale on light backgrounds).
    static let warning = NSColor.systemOrange
    static let critical = NSColor.systemRed

    /// Color for the menu bar title text (normal uses the default label color so
    /// it blends with the rest of the menu bar).
    static func titleColor(for severity: Severity) -> NSColor {
        switch severity {
        case .normal: return .labelColor
        case .warning: return warning
        case .critical: return critical
        }
    }

    /// Color for the panel bars and percentages (normal uses the accent color).
    static func panelColor(for severity: Severity) -> NSColor {
        switch severity {
        case .normal: return .controlAccentColor
        case .warning: return warning
        case .critical: return critical
        }
    }
}
