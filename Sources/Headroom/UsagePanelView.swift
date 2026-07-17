import AppKit
import UsageKit

/// Builds the rich content view shown at the top of the status menu.
@MainActor
enum UsagePanel {
    static func makeView(state: BarState, now: Date) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        switch state {
        case .loading:
            stack.addArrangedSubview(label("Carregando…", .secondaryLabelColor))
        case .loggedOut:
            stack.addArrangedSubview(label("Claude Code", .labelColor, bold: true))
            stack.addArrangedSubview(label("Faça login no Claude Code", .secondaryLabelColor))
        case .error:
            stack.addArrangedSubview(label("Claude Code", .labelColor, bold: true))
            stack.addArrangedSubview(label("Não foi possível atualizar.", Palette.warning))
            stack.addArrangedSubview(label("Tentando de novo…", .secondaryLabelColor))
        case .data(let s):
            stack.addArrangedSubview(label("Claude Code · Plano \(s.plan)", .labelColor, bold: true))
            stack.addArrangedSubview(windowRow(title: "Sessão (5h)", w: s.session, now: now))
            stack.addArrangedSubview(windowRow(title: "Semana (7d)", w: s.weekly, now: now))
            for m in s.models {
                stack.addArrangedSubview(windowRow(
                    title: "  \(m.name) (7d)",
                    w: UsageWindow(percent: m.percent, severity: m.severity, resetsAt: m.resetsAt),
                    now: now))
            }
            let stale = now.timeIntervalSince(s.fetchedAt) > 180
            let stamp = stale
                ? "⚠ desatualizado \(relativeTime(since: s.fetchedAt, now: now))"
                : "Atualizado \(relativeTime(since: s.fetchedAt, now: now))"
            stack.addArrangedSubview(label(stamp, stale ? Palette.warning : .secondaryLabelColor))
        }

        let width: CGFloat = 320
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.frame = NSRect(x: 0, y: 0, width: width, height: stack.fittingSize.height)
        return container
    }

    private static func color(for s: Severity) -> NSColor {
        Palette.panelColor(for: s)
    }

    private static func windowRow(title: String, w: UsageWindow, now: Date) -> NSView {
        let row = NSStackView()
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 2

        let top = NSStackView()
        top.orientation = .horizontal
        top.spacing = 8
        let name = label(title, .labelColor)
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        top.addArrangedSubview(name)
        top.addArrangedSubview(label("\(w.percent)%", color(for: w.severity), bold: true))
        row.addArrangedSubview(top)

        let bar = ProgressBar(percent: w.percent, color: color(for: w.severity))
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 6).isActive = true
        bar.widthAnchor.constraint(equalToConstant: 292).isActive = true
        row.addArrangedSubview(bar)

        let resetText = "zera \(clockLabel(w.resetsAt, now: now)) · em \(countdown(to: w.resetsAt, now: now))"
        row.addArrangedSubview(label(resetText, .secondaryLabelColor, size: 10))
        return row
    }

    private static func label(_ text: String, _ c: NSColor, bold: Bool = false, size: CGFloat = 12) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.textColor = c
        l.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        return l
    }
}

/// Minimal rounded progress bar.
final class ProgressBar: NSView {
    private let percent: Int
    private let barColor: NSColor
    init(percent: Int, color: NSColor) {
        self.percent = max(0, min(100, percent))
        self.barColor = color
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let w = bounds.width * CGFloat(percent) / 100.0
        guard w > 0 else { return }
        barColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: max(w, bounds.height), height: bounds.height),
                     xRadius: radius, yRadius: radius).fill()
    }
}
