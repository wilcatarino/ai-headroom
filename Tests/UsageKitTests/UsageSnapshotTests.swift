import Foundation
import UsageKit

func testUsageSnapshot() {
    let r = try! UsageResponse.decode(T.fixtureData("usage-response"))
    let snap = UsageSnapshot.from(r, plan: "Max (20x)", fetchedAt: Date(timeIntervalSince1970: 0))
    T.equal(snap.session.percent, 10)
    T.equal(snap.weekly.percent, 22)
    T.equal(snap.session.severity, Severity.normal)
    T.equal(snap.plan, "Max (20x)")
    T.expect(snap.session.resetsAt != nil, "session reset parsed")

    // Comparable severity
    T.expect(Severity.normal < Severity.warning, "normal < warning")
    T.expect(Severity.warning < Severity.critical, "warning < critical")
    T.equal(max(Severity.normal, Severity.critical), Severity.critical)

    // severity mapping
    T.equal(severity(from: "warning", percent: 10), Severity.warning)
    T.equal(severity(from: "critical", percent: 10), Severity.critical)
    T.equal(severity(from: "normal", percent: 95), Severity.critical)
    T.equal(severity(from: "normal", percent: 75), Severity.warning)
    T.equal(severity(from: "normal", percent: 10), Severity.normal)
}
