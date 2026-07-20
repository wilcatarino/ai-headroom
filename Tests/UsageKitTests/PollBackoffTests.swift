import Foundation
import UsageKit

func testPollBackoff() {
    let base: TimeInterval = 120
    let retry: TimeInterval = 30
    let cap: TimeInterval = 1800

    func delay(_ failures: Int) -> TimeInterval {
        nextRefreshDelay(consecutiveFailures: failures, baseInterval: base, retryBase: retry, maxBackoff: cap)
    }

    // No failures: steady interval.
    T.equal(delay(0), 120)

    // Exponential backoff from retryBase, doubling per failure.
    T.equal(delay(1), 30)
    T.equal(delay(2), 60)
    T.equal(delay(3), 120)
    T.equal(delay(4), 240)
    T.equal(delay(5), 480)

    // Capped at maxBackoff.
    T.equal(delay(6), 960)
    T.equal(delay(7), 1800)
    T.equal(delay(20), 1800)

    // Backoff never drops below the steady interval once it exceeds it, and is
    // monotonic non-decreasing across increasing failures.
    var prev = delay(1)
    for f in 2...30 {
        let d = delay(f)
        T.expect(d >= prev, "backoff monotonic at \(f): \(d) >= \(prev)")
        prev = d
    }
}
