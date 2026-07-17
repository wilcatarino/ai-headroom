import Foundation
import UsageKit

func testTimeFormatting() {
    let ref = Date(timeIntervalSince1970: 1_700_000_000)

    T.equal(countdown(to: ref.addingTimeInterval(5*3600 + 12*60), now: ref), "5h12m")
    T.equal(countdown(to: ref.addingTimeInterval(47*60), now: ref), "47m")
    T.equal(countdown(to: ref.addingTimeInterval(3*60), now: ref), "3m")
    T.equal(countdown(to: ref.addingTimeInterval(30), now: ref), "<1m")
    T.equal(countdown(to: ref.addingTimeInterval(4*86400 + 19*3600), now: ref), "4d19h")
    T.equal(countdown(to: ref.addingTimeInterval(-10), now: ref), "—")
    T.equal(countdown(to: nil, now: ref), "—")

    T.equal(relativeTime(since: ref, now: ref.addingTimeInterval(20)), "agora")
    T.equal(relativeTime(since: ref, now: ref.addingTimeInterval(120)), "há 2min")
    T.equal(relativeTime(since: ref, now: ref.addingTimeInterval(3600)), "há 1h")

    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let sameDay = ref.addingTimeInterval(3600)
    T.equal(clockLabel(sameDay, now: ref, calendar: cal).count, 5)     // "HH:mm"
    let otherDay = ref.addingTimeInterval(3 * 86400)
    T.expect(clockLabel(otherDay, now: ref, calendar: cal).contains("/"), "cross-day shows date")
}
