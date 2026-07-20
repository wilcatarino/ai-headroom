import Foundation

/// Delay until the next usage fetch.
///
/// Steady state polls at `baseInterval`. After a failed fetch the app backs off
/// exponentially, starting at `retryBase` and doubling per consecutive failure,
/// capped at `maxBackoff`. This keeps the app from hammering a rate-limited
/// endpoint (the usage API returns HTTP 429 under load) while still recovering
/// quickly from a one-off blip. `consecutiveFailures` is reset to 0 on success
/// (and on "not logged in", which sends no request), so recovery returns to the
/// steady cadence immediately.
public func nextRefreshDelay(
    consecutiveFailures: Int,
    baseInterval: TimeInterval,
    retryBase: TimeInterval,
    maxBackoff: TimeInterval
) -> TimeInterval {
    guard consecutiveFailures > 0 else { return baseInterval }
    let delay = retryBase * pow(2.0, Double(consecutiveFailures - 1))
    return min(delay, maxBackoff)
}
