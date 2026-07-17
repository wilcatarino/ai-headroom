import Foundation
import UsageKit

private func snap(sessionPct: Int, sessionSev: Severity, weeklySev: Severity = .normal, now: Date) -> UsageSnapshot {
    UsageSnapshot(
        plan: "Max (20x)",
        session: UsageWindow(percent: sessionPct, severity: sessionSev, resetsAt: now.addingTimeInterval(5*3600 + 12*60)),
        weekly: UsageWindow(percent: 21, severity: weeklySev, resetsAt: now.addingTimeInterval(4*86400)),
        models: [],
        fetchedAt: now
    )
}

func testMenuBarTitle() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    T.equal(renderMenuBarTitle(.loading, now: now), MenuBarTitle(text: "◐ …", severity: .normal))
    T.equal(renderMenuBarTitle(.loggedOut, now: now), MenuBarTitle(text: "◐ —", severity: .normal))
    T.equal(renderMenuBarTitle(.error, now: now), MenuBarTitle(text: "◐ ⚠", severity: .warning))

    let normal = renderMenuBarTitle(.data(snap(sessionPct: 8, sessionSev: .normal, now: now)), now: now)
    T.equal(normal.text, "◐ 8% · zera em 5h12m")
    T.equal(normal.severity, Severity.normal)

    let warn = renderMenuBarTitle(.data(snap(sessionPct: 8, sessionSev: .normal, weeklySev: .warning, now: now)), now: now)
    T.equal(warn.severity, Severity.warning)
    T.expect(warn.text.hasPrefix("◑"), "warning glyph")

    let crit = renderMenuBarTitle(.data(snap(sessionPct: 95, sessionSev: .critical, now: now)), now: now)
    T.equal(crit.text, "● no teto · zera 5h12m")
    T.equal(crit.severity, Severity.critical)
}
