# Claude Code Usage Menu Bar App - Implementation Plan

> **Status: Implemented (2026-07-17).** All 11 tasks were delivered. This document is preserved as the plan of record; the task bodies below reflect what was planned. See "Implementation status and deviations" immediately below for the differences between this plan and what actually shipped, which is the source of truth for the current state.

> **Rename:** the app and executable `ClaudeUsageBar` were later renamed to **Headroom** (repo `ai-headroom`, bundle id `com.wilcatarino.headroom`), reframed as a multi-provider usage meter starting with Claude Code. The `UsageKit` library name is unchanged. References to `ClaudeUsageBar` below are historical.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Implementation status and deviations

Delivered and committed locally. The library layer (`UsageKit`) is fully covered by tests (61 checks passing via `swift run UsageKitTests`); the AppKit UI was verified by running the app. Differences from the plan below, all forced by the "no Xcode" constraint or found during testing:

- **Test framework.** XCTest and swift-testing ship only with full Xcode, so they are unavailable with Command Line Tools. The `UsageKitTests` target is therefore an executable with a small custom assertion harness (`Tests/UsageKitTests/Harness.swift` plus a `main.swift` registry), run with `swift run UsageKitTests` (not `swift test`). It exits non-zero on failure, so CI still works. This replaces the `testTarget` and every `@Test`/`XCTest` example in the tasks below; the assertions themselves are unchanged.
- **Public visibility.** Because the test target imports `UsageKit` without `@testable`, symbols exercised by tests (`UsageResponse.decode`, `UsageSnapshot.from`, `severity(from:percent:)`, the model initializers) are `public`.
- **Sendable.** `Keychain` and `UsageClient` were marked `Sendable` to satisfy Swift 6 strict concurrency across the `TokenProvider` actor and the app's `@MainActor` boundary.
- **Placeholder glyph.** The not-logged-in and empty-countdown placeholder is a hyphen (`◐ -`, `-`) rather than an em dash, matching the docs style.
- **Error state and retry.** A `BarState.error` case (`◐ ⚠`) was added, plus a fast retry with backoff (2, 4, 8, 15 seconds) until the first successful load, and `NSLog` diagnostics. This fixes a transient first-fetch failure (Keychain first-access prompt or cold-start network) that otherwise left the bar on "Carregando…" until a manual refresh.
- **Packaging.** `Info.plist` lives in `Packaging/Info.plist`, not under `Sources/` (SwiftPM would flag it as an unhandled resource). `Scripts/make-app.sh` gained `--run` and `--install` modes for the rebuild-and-relaunch flow.
- **Fixtures.** Test percentages reflect the captured response at implementation time and are frozen on disk for determinism.
- **Repo hygiene.** Added GitHub Actions CI (`.github/workflows/ci.yml`), `LICENSE` (MIT), `CONTRIBUTING.md`, `.editorconfig`, and a README with an unofficial-project disclaimer.

**Goal:** A macOS menu bar app that shows how much of the authenticated Claude Code plan is used (5h session + 7d weekly windows) with reset countdowns, backed by a reusable `UsageKit` library.

**Architecture:** SwiftPM package with two products - a pure, unit-tested `UsageKit` library (Keychain credentials, OAuth token refresh, usage API client, view models, pure title/format rendering) and a thin AppKit executable `ClaudeUsageBar` (NSStatusItem + poller + panel). All network, Keychain, and clock dependencies sit behind protocols so logic is tested with fakes; AppKit UI is verified manually.

**Tech Stack:** Swift 6.3 (Command Line Tools, no Xcode), Swift Package Manager, AppKit, Foundation, Security (Keychain), ServiceManagement (`SMAppService`). Tests use a custom executable harness (see "Implementation status and deviations"), not XCTest/swift-testing, which require full Xcode.

## Global Constraints

- Platform floor: **macOS 13** (`platforms: [.macOS(.v13)]`). Required for `MenuBarExtra`/`SMAppService`; we use AppKit `NSStatusItem` but keep the floor.
- No Xcode: everything builds via `swift build` with Command Line Tools. Tests run via `swift run UsageKitTests` (a custom executable harness), because `swift test` needs XCTest/swift-testing from full Xcode.
- Usage endpoint: `GET https://api.anthropic.com/api/oauth/usage`, headers `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`.
- OAuth refresh endpoint (best-effort, behind protocol, NOT live-tested during dev): `POST https://console.anthropic.com/v1/oauth/token`, JSON body `{"grant_type":"refresh_token","refresh_token":"<rt>","client_id":"9d1c250a-e61b-44d9-88ed-5944d1962f5e"}`, response `{access_token, refresh_token, expires_in}`.
- Keychain item: generic password, service `Claude Code-credentials`, value is JSON. **When writing back after refresh, preserve all other keys (e.g. `mcpOAuth`) - only mutate `claudeAiOauth.accessToken/refreshToken/expiresAt`.** Clobbering the blob would wipe the user's MCP tokens.
- Poll interval: 60s. Menu bar shows the session (5h) window as the primary figure.
- All Portuguese-facing copy uses the strings shown in tasks verbatim.

---

## File Structure

```
Package.swift
Sources/
  UsageKit/
    Credentials.swift          # Credentials struct + plan label helper
    CredentialsBlob.swift       # pure JSON parse/mutate of the keychain blob (Data->Data)
    Keychain.swift              # thin SecItem read/write of Data for a service
    KeychainStore.swift         # composes Blob + Keychain: load()/saveRefreshedTokens()
    UsageResponse.swift         # raw Decodable DTOs matching the API JSON
    UsageSnapshot.swift         # normalized view model + mapping from UsageResponse
    TimeFormatting.swift        # countdown / relativeTime / clockLabel (pure, now-injected)
    TokenProvider.swift         # expiry decision + TokenRefreshing protocol + TokenProvider
    OAuthRefresher.swift        # real refresh endpoint impl of TokenRefreshing
    HTTPClient.swift            # HTTPClient protocol + URLSession impl
    UsageClient.swift           # fetch() -> UsageSnapshot
    MenuBarTitle.swift          # BarState + renderMenuBarTitle (pure)
  ClaudeUsageBar/
    main.swift                  # NSApplication bootstrap
    AppDelegate.swift           # status item, poller, wiring, error/stale state
    UsagePanelView.swift        # custom NSView rendered inside the dropdown
    LoginItem.swift             # SMAppService start-at-login wrapper
Tests/
  UsageKitTests/
    Fixtures/usage-response.json
    Fixtures/credentials-blob.json
    CredentialsTests.swift
    CredentialsBlobTests.swift
    UsageSnapshotTests.swift
    TimeFormattingTests.swift
    TokenProviderTests.swift
    UsageClientTests.swift
    MenuBarTitleTests.swift
Scripts/
  make-app.sh                   # assembles ClaudeUsageBar.app bundle
```

---

### Task 1: Package skeleton + green test harness

**Files:**
- Create: `Package.swift`
- Create: `Sources/UsageKit/Credentials.swift` (temporary placeholder type)
- Create: `Sources/ClaudeUsageBar/main.swift` (temporary stub)
- Test: `Tests/UsageKitTests/CredentialsTests.swift` (temporary smoke test)

**Interfaces:**
- Produces: a buildable package with `UsageKit` library target, `ClaudeUsageBar` executable target, `UsageKitTests` test target using swift-testing.

- [ ] **Step 1: Write the failing smoke test**

`Tests/UsageKitTests/CredentialsTests.swift`:
```swift
import Testing
@testable import UsageKit

@Test func packageBuilds() {
    #expect(UsageKit.marker == "usagekit")
}
```

- [ ] **Step 2: Create `Package.swift`**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "UsageKit"),
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: ["UsageKit"]
        ),
        .testTarget(
            name: "UsageKitTests",
            dependencies: ["UsageKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 3: Create placeholder sources**

`Sources/UsageKit/Credentials.swift`:
```swift
public enum UsageKit {
    public static let marker = "usagekit"
}
```

`Sources/ClaudeUsageBar/main.swift`:
```swift
import UsageKit
print(UsageKit.marker)
```

- [ ] **Step 4: Create the fixtures directory**

Copy the captured fixture into the test bundle:
```bash
mkdir -p Tests/UsageKitTests/Fixtures
cp .context/fixtures/usage-response.json Tests/UsageKitTests/Fixtures/usage-response.json
```

- [ ] **Step 5: Run the test**

Run: `swift test 2>&1 | tail -20`
Expected: PASS (`packageBuilds`).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "chore: SwiftPM package skeleton with green test harness"
```

---

### Task 2: Credentials model + plan label

**Files:**
- Modify: `Sources/UsageKit/Credentials.swift`
- Test: `Tests/UsageKitTests/CredentialsTests.swift`

**Interfaces:**
- Produces:
  - `public struct Credentials: Equatable { public let accessToken: String; public let refreshToken: String; public let expiresAtMillis: Int; public let subscriptionType: String?; public let rateLimitTier: String? }`
  - `public func planLabel(subscriptionType: String?, rateLimitTier: String?) -> String`

- [ ] **Step 1: Write the failing tests**

Replace `Tests/UsageKitTests/CredentialsTests.swift`:
```swift
import Testing
@testable import UsageKit

@Test func planLabelFormatsMaxTier() {
    #expect(planLabel(subscriptionType: "max", rateLimitTier: "default_claude_max_20x") == "Max (20x)")
}

@Test func planLabelFallsBackWhenTierMissing() {
    #expect(planLabel(subscriptionType: "pro", rateLimitTier: nil) == "Pro")
}

@Test func planLabelUnknownIsClaudeCode() {
    #expect(planLabel(subscriptionType: nil, rateLimitTier: nil) == "Claude Code")
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter CredentialsTests 2>&1 | tail -20`
Expected: FAIL (`planLabel` not found).

- [ ] **Step 3: Implement**

Replace `Sources/UsageKit/Credentials.swift`:
```swift
import Foundation

public struct Credentials: Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAtMillis: Int
    public let subscriptionType: String?
    public let rateLimitTier: String?

    public init(accessToken: String, refreshToken: String, expiresAtMillis: Int,
                subscriptionType: String?, rateLimitTier: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAtMillis = expiresAtMillis
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }
}

/// Builds the human label, e.g. "Max (20x)". `rateLimitTier` looks like
/// "default_claude_max_20x"; we extract a trailing "<n>x" multiplier if present.
public func planLabel(subscriptionType: String?, rateLimitTier: String?) -> String {
    guard let sub = subscriptionType, !sub.isEmpty else { return "Claude Code" }
    let name = sub.prefix(1).uppercased() + sub.dropFirst()
    if let tier = rateLimitTier,
       let match = tier.split(separator: "_").last(where: { $0.hasSuffix("x") && $0.dropLast().allSatisfy(\.isNumber) }) {
        return "\(name) (\(match))"
    }
    return name
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter CredentialsTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageKit/Credentials.swift Tests/UsageKitTests/CredentialsTests.swift
git commit -m "feat: Credentials model and plan label helper"
```

---

### Task 3: Credentials blob - parse & non-destructive mutate

**Files:**
- Create: `Sources/UsageKit/CredentialsBlob.swift`
- Create: `Tests/UsageKitTests/Fixtures/credentials-blob.json`
- Test: `Tests/UsageKitTests/CredentialsBlobTests.swift`

**Interfaces:**
- Consumes: `Credentials` (Task 2).
- Produces:
  - `public enum CredentialsBlob { static func parse(_ data: Data) throws -> Credentials; static func writingRefreshedTokens(into data: Data, accessToken: String, refreshToken: String, expiresAtMillis: Int) throws -> Data }`
  - `public enum CredentialsBlobError: Error { case malformed }`

- [ ] **Step 1: Create the fixture**

`Tests/UsageKitTests/Fixtures/credentials-blob.json` (note: keeps a sibling `mcpOAuth` key that MUST survive a write):
```json
{"claudeAiOauth":{"accessToken":"sk-ant-oat01-OLD","refreshToken":"sk-ant-ort01-OLD","expiresAt":1000,"scopes":["user:inference"],"subscriptionType":"max","rateLimitTier":"default_claude_max_20x"},"mcpOAuth":{"linear-mcp|abc":{"accessToken":"keep-me"}}}
```

- [ ] **Step 2: Write the failing tests**

`Tests/UsageKitTests/CredentialsBlobTests.swift`:
```swift
import Testing
import Foundation
@testable import UsageKit

private func fixtureData(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")!
    return try Data(contentsOf: url)
}

@Test func parsesClaudeAiOauth() throws {
    let creds = try CredentialsBlob.parse(fixtureData("credentials-blob"))
    #expect(creds.accessToken == "sk-ant-oat01-OLD")
    #expect(creds.refreshToken == "sk-ant-ort01-OLD")
    #expect(creds.expiresAtMillis == 1000)
    #expect(creds.subscriptionType == "max")
    #expect(creds.rateLimitTier == "default_claude_max_20x")
}

@Test func writeUpdatesTokensAndPreservesOtherKeys() throws {
    let original = try fixtureData("credentials-blob")
    let updated = try CredentialsBlob.writingRefreshedTokens(
        into: original, accessToken: "NEW-AT", refreshToken: "NEW-RT", expiresAtMillis: 2000)

    let obj = try JSONSerialization.jsonObject(with: updated) as! [String: Any]
    let oauth = obj["claudeAiOauth"] as! [String: Any]
    #expect(oauth["accessToken"] as? String == "NEW-AT")
    #expect(oauth["refreshToken"] as? String == "NEW-RT")
    #expect(oauth["expiresAt"] as? Int == 2000)
    // untouched keys survive:
    #expect(oauth["subscriptionType"] as? String == "max")
    let mcp = obj["mcpOAuth"] as! [String: Any]
    #expect(mcp["linear-mcp|abc"] != nil)
}

@Test func malformedThrows() {
    #expect(throws: CredentialsBlobError.self) {
        _ = try CredentialsBlob.parse(Data("not json".utf8))
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter CredentialsBlobTests 2>&1 | tail -20`
Expected: FAIL (`CredentialsBlob` not found).

- [ ] **Step 4: Implement**

`Sources/UsageKit/CredentialsBlob.swift`:
```swift
import Foundation

public enum CredentialsBlobError: Error { case malformed }

public enum CredentialsBlob {
    public static func parse(_ data: Data) throws -> Credentials {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let access = oauth["accessToken"] as? String,
              let refresh = oauth["refreshToken"] as? String,
              let expires = oauth["expiresAt"] as? Int
        else { throw CredentialsBlobError.malformed }
        return Credentials(
            accessToken: access,
            refreshToken: refresh,
            expiresAtMillis: expires,
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String
        )
    }

    /// Returns a new blob with only the three token fields inside `claudeAiOauth`
    /// replaced. Every other key (including sibling `mcpOAuth`) is preserved.
    public static func writingRefreshedTokens(
        into data: Data, accessToken: String, refreshToken: String, expiresAtMillis: Int
    ) throws -> Data {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any]
        else { throw CredentialsBlobError.malformed }
        oauth["accessToken"] = accessToken
        oauth["refreshToken"] = refreshToken
        oauth["expiresAt"] = expiresAtMillis
        root["claudeAiOauth"] = oauth
        return try JSONSerialization.data(withJSONObject: root)
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `swift test --filter CredentialsBlobTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageKit/CredentialsBlob.swift Tests/UsageKitTests/CredentialsBlobTests.swift Tests/UsageKitTests/Fixtures/credentials-blob.json
git commit -m "feat: non-destructive keychain blob parse and token rewrite"
```

---

### Task 4: Usage response DTOs + UsageSnapshot mapping

**Files:**
- Create: `Sources/UsageKit/UsageResponse.swift`
- Create: `Sources/UsageKit/UsageSnapshot.swift`
- Test: `Tests/UsageKitTests/UsageSnapshotTests.swift`

**Interfaces:**
- Produces:
  - `public enum Severity: String, Comparable { case normal, warning, critical }` (ordered normal < warning < critical)
  - `public struct UsageWindow: Equatable { public let percent: Int; public let severity: Severity; public let resetsAt: Date? }`
  - `public struct ModelUsage: Equatable { public let name: String; public let percent: Int; public let severity: Severity; public let resetsAt: Date? }`
  - `public struct UsageSnapshot: Equatable { public let plan: String; public let session: UsageWindow; public let weekly: UsageWindow; public let models: [ModelUsage]; public let fetchedAt: Date }`
  - `struct UsageResponse: Decodable` (internal) with `static func decode(_ data: Data) throws -> UsageResponse`
  - `extension UsageSnapshot { static func from(_ r: UsageResponse, plan: String, fetchedAt: Date) -> UsageSnapshot }`

- [ ] **Step 1: Write the failing tests**

`Tests/UsageKitTests/UsageSnapshotTests.swift`:
```swift
import Testing
import Foundation
@testable import UsageKit

private func usageData() throws -> Data {
    let url = Bundle.module.url(forResource: "Fixtures/usage-response", withExtension: "json")!
    return try Data(contentsOf: url)
}

@Test func decodesSessionAndWeeklyFromLimits() throws {
    let r = try UsageResponse.decode(usageData())
    let snap = UsageSnapshot.from(r, plan: "Max (20x)", fetchedAt: Date(timeIntervalSince1970: 0))
    #expect(snap.session.percent == 9)
    #expect(snap.weekly.percent == 21)
    #expect(snap.session.severity == .normal)
    #expect(snap.plan == "Max (20x)")
    #expect(snap.session.resetsAt != nil)
}

@Test func severityIsComparable() {
    #expect(Severity.normal < Severity.warning)
    #expect(Severity.warning < Severity.critical)
    #expect(max(Severity.normal, Severity.critical) == .critical)
}

@Test func mapsSeverityStrings() {
    #expect(severity(from: "warning", percent: 10) == .warning)
    #expect(severity(from: "critical", percent: 10) == .critical)
    // unknown string falls back to percent thresholds:
    #expect(severity(from: "normal", percent: 95) == .critical)
    #expect(severity(from: "normal", percent: 75) == .warning)
    #expect(severity(from: "normal", percent: 10) == .normal)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter UsageSnapshotTests 2>&1 | tail -20`
Expected: FAIL (types not found).

- [ ] **Step 3: Implement DTOs**

`Sources/UsageKit/UsageResponse.swift`:
```swift
import Foundation

struct UsageResponse: Decodable {
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

    static func decode(_ data: Data) throws -> UsageResponse {
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
```

- [ ] **Step 4: Implement Snapshot + mapping**

`Sources/UsageKit/UsageSnapshot.swift`:
```swift
import Foundation

public enum Severity: String, Comparable {
    case normal, warning, critical
    private var rank: Int { switch self { case .normal: 0; case .warning: 1; case .critical: 2 } }
    public static func < (a: Severity, b: Severity) -> Bool { a.rank < b.rank }
}

/// Server severity string wins when it maps to a known bucket; otherwise fall
/// back to percent thresholds (>=90 critical, >=70 warning).
func severity(from serverValue: String?, percent: Int) -> Severity {
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
}

public struct ModelUsage: Equatable {
    public let name: String
    public let percent: Int
    public let severity: Severity
    public let resetsAt: Date?
}

public struct UsageSnapshot: Equatable {
    public let plan: String
    public let session: UsageWindow
    public let weekly: UsageWindow
    public let models: [ModelUsage]
    public let fetchedAt: Date
}

extension UsageSnapshot {
    static func from(_ r: UsageResponse, plan: String, fetchedAt: Date) -> UsageSnapshot {
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
```

- [ ] **Step 5: Run to verify pass**

Run: `swift test --filter UsageSnapshotTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageKit/UsageResponse.swift Sources/UsageKit/UsageSnapshot.swift Tests/UsageKitTests/UsageSnapshotTests.swift
git commit -m "feat: usage response decoding and UsageSnapshot mapping"
```

---

### Task 5: Time formatting helpers

**Files:**
- Create: `Sources/UsageKit/TimeFormatting.swift`
- Test: `Tests/UsageKitTests/TimeFormattingTests.swift`

**Interfaces:**
- Produces:
  - `public func countdown(to date: Date?, now: Date) -> String` - `"5h12m"`, `"47m"`, `"3m"`, `"<1m"`, `"4d19h"`, `"-"` when nil/past.
  - `public func relativeTime(since date: Date, now: Date) -> String` - `"agora"`, `"há 2min"`, `"há 1h"`.
  - `public func clockLabel(_ date: Date?, now: Date, calendar: Calendar) -> String` - `"07:20"` if same day, else `"22/07 03:00"`; `"-"` when nil.

- [ ] **Step 1: Write the failing tests**

`Tests/UsageKitTests/TimeFormattingTests.swift`:
```swift
import Testing
import Foundation
@testable import UsageKit

private let ref = Date(timeIntervalSince1970: 1_700_000_000) // fixed "now"

@Test func countdownFormats() {
    #expect(countdown(to: ref.addingTimeInterval(5*3600 + 12*60), now: ref) == "5h12m")
    #expect(countdown(to: ref.addingTimeInterval(47*60), now: ref) == "47m")
    #expect(countdown(to: ref.addingTimeInterval(3*60), now: ref) == "3m")
    #expect(countdown(to: ref.addingTimeInterval(30), now: ref) == "<1m")
    #expect(countdown(to: ref.addingTimeInterval(4*86400 + 19*3600), now: ref) == "4d19h")
    #expect(countdown(to: ref.addingTimeInterval(-10), now: ref) == "-")
    #expect(countdown(to: nil, now: ref) == "-")
}

@Test func relativeTimeFormats() {
    #expect(relativeTime(since: ref, now: ref.addingTimeInterval(20)) == "agora")
    #expect(relativeTime(since: ref, now: ref.addingTimeInterval(120)) == "há 2min")
    #expect(relativeTime(since: ref, now: ref.addingTimeInterval(3600)) == "há 1h")
}

@Test func clockLabelSameDayVsOther() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let sameDay = ref.addingTimeInterval(3600)
    #expect(clockLabel(sameDay, now: ref, calendar: cal).count == 5)   // "HH:mm"
    let otherDay = ref.addingTimeInterval(3 * 86400)
    #expect(clockLabel(otherDay, now: ref, calendar: cal).contains("/")) // "dd/MM HH:mm"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter TimeFormattingTests 2>&1 | tail -20`
Expected: FAIL (functions not found).

- [ ] **Step 3: Implement**

`Sources/UsageKit/TimeFormatting.swift`:
```swift
import Foundation

public func countdown(to date: Date?, now: Date) -> String {
    guard let date else { return "-" }
    let secs = Int(date.timeIntervalSince(now))
    if secs <= 0 { return "-" }
    let days = secs / 86400
    let hours = (secs % 86400) / 3600
    let mins = (secs % 3600) / 60
    if days > 0 { return "\(days)d\(hours)h" }
    if hours > 0 { return "\(hours)h\(String(format: "%02d", mins))m" }
    if mins > 0 { return "\(mins)m" }
    return "<1m"
}

public func relativeTime(since date: Date, now: Date) -> String {
    let secs = Int(now.timeIntervalSince(date))
    if secs < 60 { return "agora" }
    let mins = secs / 60
    if mins < 60 { return "há \(mins)min" }
    let hours = mins / 60
    if hours < 24 { return "há \(hours)h" }
    return "há \(hours / 24)d"
}

public func clockLabel(_ date: Date?, now: Date, calendar: Calendar = .current) -> String {
    guard let date else { return "-" }
    let f = DateFormatter()
    f.calendar = calendar
    f.timeZone = calendar.timeZone
    f.locale = Locale(identifier: "pt_BR")
    if calendar.isDate(date, inSameDayAs: now) {
        f.dateFormat = "HH:mm"
    } else {
        f.dateFormat = "dd/MM HH:mm"
    }
    return f.string(from: date)
}
```

Note the `countdown` `5h12m` case: minutes are zero-padded to two digits so `5h12m` and `5h02m` align; the test uses `12`. The `47m`/`3m` (hours == 0) branch is not padded.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter TimeFormattingTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageKit/TimeFormatting.swift Tests/UsageKitTests/TimeFormattingTests.swift
git commit -m "feat: time formatting helpers (countdown, relative, clock)"
```

---

### Task 6: Token expiry decision + TokenProvider

**Files:**
- Create: `Sources/UsageKit/TokenProvider.swift`
- Test: `Tests/UsageKitTests/TokenProviderTests.swift`

**Interfaces:**
- Consumes: `Credentials` (Task 2).
- Produces:
  - `public func isExpired(expiresAtMillis: Int, now: Date, skewSeconds: Int) -> Bool`
  - `public struct RefreshedTokens: Equatable { public let accessToken: String; public let refreshToken: String; public let expiresAtMillis: Int }`
  - `public protocol TokenRefreshing: Sendable { func refresh(refreshToken: String) async throws -> RefreshedTokens }`
  - `public protocol CredentialsStoring: Sendable { func load() throws -> Credentials?; func saveRefreshedTokens(_ t: RefreshedTokens) throws }`
  - `public actor TokenProvider { init(store: CredentialsStoring, refresher: TokenRefreshing, skewSeconds: Int); func validAccessToken(now: Date) async throws -> String }`
  - `public enum TokenError: Error { case notLoggedIn }`

- [ ] **Step 1: Write the failing tests**

`Tests/UsageKitTests/TokenProviderTests.swift`:
```swift
import Testing
import Foundation
@testable import UsageKit

@Test func expiryUsesSkew() {
    let now = Date(timeIntervalSince1970: 1000)
    // expires at 1000s + 30s, skew 60s -> considered expired
    #expect(isExpired(expiresAtMillis: 1030_000, now: now, skewSeconds: 60) == true)
    // expires at 1000s + 120s, skew 60s -> still valid
    #expect(isExpired(expiresAtMillis: 1120_000, now: now, skewSeconds: 60) == false)
}

private final class FakeStore: CredentialsStoring, @unchecked Sendable {
    var creds: Credentials?
    var saved: RefreshedTokens?
    func load() throws -> Credentials? { creds }
    func saveRefreshedTokens(_ t: RefreshedTokens) throws { saved = t }
}
private final class FakeRefresher: TokenRefreshing, @unchecked Sendable {
    var calls = 0
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        calls += 1
        return RefreshedTokens(accessToken: "AT2", refreshToken: "RT2", expiresAtMillis: 9_000_000_000_000)
    }
}

@Test func returnsCurrentTokenWhenValid() async throws {
    let store = FakeStore()
    store.creds = Credentials(accessToken: "AT1", refreshToken: "RT1",
                              expiresAtMillis: 9_000_000_000_000, subscriptionType: "max", rateLimitTier: nil)
    let refresher = FakeRefresher()
    let provider = TokenProvider(store: store, refresher: refresher, skewSeconds: 60)
    let token = try await provider.validAccessToken(now: Date(timeIntervalSince1970: 1000))
    #expect(token == "AT1")
    #expect(refresher.calls == 0)
}

@Test func refreshesAndPersistsWhenExpired() async throws {
    let store = FakeStore()
    store.creds = Credentials(accessToken: "AT1", refreshToken: "RT1",
                              expiresAtMillis: 500_000, subscriptionType: "max", rateLimitTier: nil)
    let refresher = FakeRefresher()
    let provider = TokenProvider(store: store, refresher: refresher, skewSeconds: 60)
    let token = try await provider.validAccessToken(now: Date(timeIntervalSince1970: 1000))
    #expect(token == "AT2")
    #expect(refresher.calls == 1)
    #expect(store.saved?.accessToken == "AT2")
}

@Test func notLoggedInThrows() async {
    let provider = TokenProvider(store: FakeStore(), refresher: FakeRefresher(), skewSeconds: 60)
    await #expect(throws: TokenError.self) {
        _ = try await provider.validAccessToken(now: Date())
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter TokenProviderTests 2>&1 | tail -20`
Expected: FAIL (types not found).

- [ ] **Step 3: Implement**

`Sources/UsageKit/TokenProvider.swift`:
```swift
import Foundation

public func isExpired(expiresAtMillis: Int, now: Date, skewSeconds: Int) -> Bool {
    let expiry = Double(expiresAtMillis) / 1000.0
    return expiry - Double(skewSeconds) <= now.timeIntervalSince1970
}

public struct RefreshedTokens: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAtMillis: Int
    public init(accessToken: String, refreshToken: String, expiresAtMillis: Int) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAtMillis = expiresAtMillis
    }
}

public protocol TokenRefreshing: Sendable {
    func refresh(refreshToken: String) async throws -> RefreshedTokens
}

public protocol CredentialsStoring: Sendable {
    func load() throws -> Credentials?
    func saveRefreshedTokens(_ t: RefreshedTokens) throws
}

public enum TokenError: Error { case notLoggedIn }

public actor TokenProvider {
    private let store: CredentialsStoring
    private let refresher: TokenRefreshing
    private let skewSeconds: Int

    public init(store: CredentialsStoring, refresher: TokenRefreshing, skewSeconds: Int = 60) {
        self.store = store
        self.refresher = refresher
        self.skewSeconds = skewSeconds
    }

    public func validAccessToken(now: Date) async throws -> String {
        guard let creds = try store.load() else { throw TokenError.notLoggedIn }
        guard isExpired(expiresAtMillis: creds.expiresAtMillis, now: now, skewSeconds: skewSeconds) else {
            return creds.accessToken
        }
        let refreshed = try await refresher.refresh(refreshToken: creds.refreshToken)
        try store.saveRefreshedTokens(refreshed)
        return refreshed.accessToken
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter TokenProviderTests 2>&1 | tail -20`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageKit/TokenProvider.swift Tests/UsageKitTests/TokenProviderTests.swift
git commit -m "feat: token expiry decision and refreshing TokenProvider"
```

---

### Task 7: HTTP client protocol + UsageClient

**Files:**
- Create: `Sources/UsageKit/HTTPClient.swift`
- Create: `Sources/UsageKit/UsageClient.swift`
- Test: `Tests/UsageKitTests/UsageClientTests.swift`

**Interfaces:**
- Consumes: `UsageResponse`/`UsageSnapshot` (Task 4), `TokenProvider` protocols (Task 6).
- Produces:
  - `public protocol HTTPClient: Sendable { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }`
  - `public struct URLSessionHTTPClient: HTTPClient` (real impl)
  - `public struct UsageClient { init(http: HTTPClient, tokenProvider: TokenProvider, plan: @escaping @Sendable () -> String); func fetch(now: Date) async throws -> UsageSnapshot }`
  - `public enum UsageClientError: Error { case http(Int) }`

- [ ] **Step 1: Write the failing tests**

`Tests/UsageKitTests/UsageClientTests.swift`:
```swift
import Testing
import Foundation
@testable import UsageKit

private func usageData() throws -> Data {
    let url = Bundle.module.url(forResource: "Fixtures/usage-response", withExtension: "json")!
    return try Data(contentsOf: url)
}

private struct FakeHTTP: HTTPClient {
    let data: Data
    let status: Int
    var lastAuth: String? { authBox.value }
    let authBox = Box()
    final class Box: @unchecked Sendable { var value: String? }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        authBox.value = request.value(forHTTPHeaderField: "Authorization")
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, resp)
    }
}

private final class StubStore: CredentialsStoring, @unchecked Sendable {
    func load() throws -> Credentials? {
        Credentials(accessToken: "AT-TEST", refreshToken: "RT", expiresAtMillis: 9_000_000_000_000,
                    subscriptionType: "max", rateLimitTier: "default_claude_max_20x")
    }
    func saveRefreshedTokens(_ t: RefreshedTokens) throws {}
}
private struct StubRefresher: TokenRefreshing {
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        RefreshedTokens(accessToken: "x", refreshToken: "y", expiresAtMillis: 0)
    }
}

@Test func fetchDecodesAndSendsBearer() async throws {
    let http = FakeHTTP(data: try usageData(), status: 200)
    let provider = TokenProvider(store: StubStore(), refresher: StubRefresher(), skewSeconds: 60)
    let client = UsageClient(http: http, tokenProvider: provider, plan: { "Max (20x)" })
    let snap = try await client.fetch(now: Date(timeIntervalSince1970: 0))
    #expect(snap.session.percent == 9)
    #expect(snap.weekly.percent == 21)
    #expect(http.lastAuth == "Bearer AT-TEST")
}

@Test func fetchThrowsOnHTTPError() async {
    let http = FakeHTTP(data: Data("{}".utf8), status: 401)
    let provider = TokenProvider(store: StubStore(), refresher: StubRefresher(), skewSeconds: 60)
    let client = UsageClient(http: http, tokenProvider: provider, plan: { "Max" })
    await #expect(throws: UsageClientError.self) {
        _ = try await client.fetch(now: Date())
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter UsageClientTests 2>&1 | tail -20`
Expected: FAIL (types not found).

- [ ] **Step 3: Implement HTTPClient**

`Sources/UsageKit/HTTPClient.swift`:
```swift
import Foundation

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
```

- [ ] **Step 4: Implement UsageClient**

`Sources/UsageKit/UsageClient.swift`:
```swift
import Foundation

public enum UsageClientError: Error { case http(Int) }

public struct UsageClient {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let http: HTTPClient
    private let tokenProvider: TokenProvider
    private let plan: @Sendable () -> String

    public init(http: HTTPClient, tokenProvider: TokenProvider, plan: @escaping @Sendable () -> String) {
        self.http = http
        self.tokenProvider = tokenProvider
        self.plan = plan
    }

    public func fetch(now: Date) async throws -> UsageSnapshot {
        let token = try await tokenProvider.validAccessToken(now: now)
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw UsageClientError.http(response.statusCode)
        }
        let decoded = try UsageResponse.decode(data)
        return UsageSnapshot.from(decoded, plan: plan(), fetchedAt: now)
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `swift test --filter UsageClientTests 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageKit/HTTPClient.swift Sources/UsageKit/UsageClient.swift Tests/UsageKitTests/UsageClientTests.swift
git commit -m "feat: HTTP client protocol and UsageClient fetch"
```

---

### Task 8: Menu bar title rendering (pure)

**Files:**
- Create: `Sources/UsageKit/MenuBarTitle.swift`
- Test: `Tests/UsageKitTests/MenuBarTitleTests.swift`

**Interfaces:**
- Consumes: `UsageSnapshot`, `Severity`, `countdown` (Tasks 4-5).
- Produces:
  - `public enum BarState: Equatable { case loading; case loggedOut; case data(UsageSnapshot) }`
  - `public struct MenuBarTitle: Equatable { public let text: String; public let severity: Severity }`
  - `public func renderMenuBarTitle(_ state: BarState, now: Date) -> MenuBarTitle`

- [ ] **Step 1: Write the failing tests**

`Tests/UsageKitTests/MenuBarTitleTests.swift`:
```swift
import Testing
import Foundation
@testable import UsageKit

private let now = Date(timeIntervalSince1970: 1_700_000_000)

private func snapshot(sessionPct: Int, sessionSev: Severity, weeklySev: Severity = .normal) -> UsageSnapshot {
    UsageSnapshot(
        plan: "Max (20x)",
        session: UsageWindow(percent: sessionPct, severity: sessionSev, resetsAt: now.addingTimeInterval(5*3600 + 12*60)),
        weekly: UsageWindow(percent: 21, severity: weeklySev, resetsAt: now.addingTimeInterval(4*86400)),
        models: [],
        fetchedAt: now
    )
}

@Test func loadingTitle() {
    #expect(renderMenuBarTitle(.loading, now: now) == MenuBarTitle(text: "◐ …", severity: .normal))
}

@Test func loggedOutTitle() {
    #expect(renderMenuBarTitle(.loggedOut, now: now) == MenuBarTitle(text: "◐ -", severity: .normal))
}

@Test func normalShowsPercentAndCountdown() {
    let t = renderMenuBarTitle(.data(snapshot(sessionPct: 8, sessionSev: .normal)), now: now)
    #expect(t.text == "◐ 8% · zera em 5h12m")
    #expect(t.severity == .normal)
}

@Test func warningSeverityFromWeekly() {
    let t = renderMenuBarTitle(.data(snapshot(sessionPct: 8, sessionSev: .normal, weeklySev: .warning)), now: now)
    #expect(t.severity == .warning)
    #expect(t.text.hasPrefix("◑"))
}

@Test func criticalSessionEmphasizesReset() {
    let t = renderMenuBarTitle(.data(snapshot(sessionPct: 95, sessionSev: .critical)), now: now)
    #expect(t.text == "● no teto · zera 5h12m")
    #expect(t.severity == .critical)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter MenuBarTitleTests 2>&1 | tail -20`
Expected: FAIL (types not found).

- [ ] **Step 3: Implement**

`Sources/UsageKit/MenuBarTitle.swift`:
```swift
import Foundation

public enum BarState: Equatable {
    case loading
    case loggedOut
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
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter MenuBarTitleTests 2>&1 | tail -20`
Expected: PASS (5 tests).

- [ ] **Step 5: Run the full suite**

Run: `swift test 2>&1 | tail -20`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageKit/MenuBarTitle.swift Tests/UsageKitTests/MenuBarTitleTests.swift
git commit -m "feat: pure menu bar title rendering"
```

---

### Task 9: Real Keychain + OAuth refresher wiring

**Files:**
- Create: `Sources/UsageKit/Keychain.swift`
- Create: `Sources/UsageKit/KeychainStore.swift`
- Create: `Sources/UsageKit/OAuthRefresher.swift`

**Interfaces:**
- Consumes: `CredentialsBlob` (Task 3), `CredentialsStoring`/`TokenRefreshing`/`RefreshedTokens` (Task 6), `HTTPClient` (Task 7).
- Produces:
  - `public struct Keychain { init(service: String); func readData() throws -> Data?; func writeData(_ data: Data) throws }`
  - `public struct KeychainStore: CredentialsStoring { init(keychain: Keychain) }`
  - `public struct OAuthRefresher: TokenRefreshing { init(http: HTTPClient, clock: @escaping @Sendable () -> Date) }`

These are integration-only (real `SecItem` + network). No unit test; verified via the app in Task 11. Keep them thin.

- [ ] **Step 1: Implement Keychain**

`Sources/UsageKit/Keychain.swift`:
```swift
import Foundation
import Security

public struct Keychain {
    public let service: String
    public init(service: String) { self.service = service }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service]
    }

    public func readData() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        return result as? Data
    }

    public func writeData(_ data: Data) throws {
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }
}

public enum KeychainError: Error { case status(OSStatus) }
```

- [ ] **Step 2: Implement KeychainStore**

`Sources/UsageKit/KeychainStore.swift`:
```swift
import Foundation

public struct KeychainStore: CredentialsStoring {
    private let keychain: Keychain
    public init(keychain: Keychain = Keychain(service: "Claude Code-credentials")) {
        self.keychain = keychain
    }

    public func load() throws -> Credentials? {
        guard let data = try keychain.readData() else { return nil }
        return try CredentialsBlob.parse(data)
    }

    public func saveRefreshedTokens(_ t: RefreshedTokens) throws {
        guard let data = try keychain.readData() else { throw TokenError.notLoggedIn }
        let updated = try CredentialsBlob.writingRefreshedTokens(
            into: data, accessToken: t.accessToken, refreshToken: t.refreshToken,
            expiresAtMillis: t.expiresAtMillis)
        try keychain.writeData(updated)
    }
}
```

- [ ] **Step 3: Implement OAuthRefresher**

`Sources/UsageKit/OAuthRefresher.swift`:
```swift
import Foundation

public struct OAuthRefresher: TokenRefreshing {
    static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    private let http: HTTPClient
    private let clock: @Sendable () -> Date

    public init(http: HTTPClient, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http
        self.clock = clock
    }

    private struct Response: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }

    public func refresh(refreshToken: String) async throws -> RefreshedTokens {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw UsageClientError.http(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let expiresAt = Int((clock().timeIntervalSince1970 + Double(decoded.expires_in)) * 1000)
        return RefreshedTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? refreshToken,
            expiresAtMillis: expiresAt)
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageKit/Keychain.swift Sources/UsageKit/KeychainStore.swift Sources/UsageKit/OAuthRefresher.swift
git commit -m "feat: real Keychain store and OAuth refresher"
```

---

### Task 10: Menu bar app - status item, poller, panel, login item

**Files:**
- Create: `Sources/ClaudeUsageBar/LoginItem.swift`
- Create: `Sources/ClaudeUsageBar/UsagePanelView.swift`
- Create: `Sources/ClaudeUsageBar/AppDelegate.swift`
- Modify: `Sources/ClaudeUsageBar/main.swift`

**Interfaces:**
- Consumes: everything public in `UsageKit` - `UsageClient`, `TokenProvider`, `KeychainStore`, `Keychain`, `OAuthRefresher`, `URLSessionHTTPClient`, `renderMenuBarTitle`, `BarState`, `UsageSnapshot`, `planLabel`, `countdown`, `clockLabel`, `relativeTime`.

This is AppKit UI; verified manually in Task 11 (no unit tests).

- [ ] **Step 1: Implement LoginItem**

`Sources/ClaudeUsageBar/LoginItem.swift`:
```swift
import Foundation
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            NSLog("LoginItem toggle failed: \(error)")
            return false
        }
    }
}
```

- [ ] **Step 2: Implement UsagePanelView**

`Sources/ClaudeUsageBar/UsagePanelView.swift`:
```swift
import AppKit
import UsageKit

/// Builds the rich content view shown at the top of the status menu.
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
            stack.addArrangedSubview(label(stamp, stale ? .systemYellow : .secondaryLabelColor))
        }

        let width: CGFloat = 320
        stack.frame = NSRect(x: 0, y: 0, width: width,
                             height: stack.fittingSize.height)
        let container = NSView(frame: stack.frame)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.frame = NSRect(x: 0, y: 0, width: width, height: stack.fittingSize.height + 24)
        return container
    }

    private static func color(for s: Severity) -> NSColor {
        switch s { case .normal: .controlAccentColor; case .warning: .systemYellow; case .critical: .systemRed }
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
```

- [ ] **Step 3: Implement AppDelegate**

`Sources/ClaudeUsageBar/AppDelegate.swift`:
```swift
import AppKit
import UsageKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var client: UsageClient!
    private var lastSnapshot: UsageSnapshot?
    private var loggedOut = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let http = URLSessionHTTPClient()
        let store = KeychainStore()
        let refresher = OAuthRefresher(http: http)
        let provider = TokenProvider(store: store, refresher: refresher)
        let planString = (try? store.load()).flatMap { $0 }.map {
            planLabel(subscriptionType: $0.subscriptionType, rateLimitTier: $0.rateLimitTier)
        } ?? "Claude Code"
        client = UsageClient(http: http, tokenProvider: provider, plan: { planString })

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "◐ …"

        // Enable start-at-login by default on first run.
        if !UserDefaults.standard.bool(forKey: "didSetInitialLoginItem") {
            LoginItem.setEnabled(true)
            UserDefaults.standard.set(true, forKey: "didSetInitialLoginItem")
        }

        render(state: .loading)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        Task { @MainActor in
            do {
                let snap = try await client.fetch(now: Date())
                lastSnapshot = snap
                loggedOut = false
                render(state: .data(snap))
            } catch TokenError.notLoggedIn {
                loggedOut = true
                render(state: .loggedOut)
            } catch {
                // keep last snapshot; panel will show the stale marker
                if let last = lastSnapshot {
                    render(state: .data(last))
                } else if !loggedOut {
                    render(state: .loading)
                }
            }
        }
    }

    private func currentState() -> BarState {
        if loggedOut { return .loggedOut }
        if let s = lastSnapshot { return .data(s) }
        return .loading
    }

    private func render(state: BarState) {
        let now = Date()
        let title = renderMenuBarTitle(state, now: now)
        statusItem.button?.title = title.text
        statusItem.menu = buildMenu(state: state, now: now)
    }

    private func buildMenu(state: BarState, now: Date) -> NSMenu {
        let menu = NSMenu()
        let header = NSMenuItem()
        header.view = UsagePanel.makeView(state: state, now: now)
        menu.addItem(header)
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "↻ Atualizar", action: #selector(manualRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let login = NSMenuItem(title: "Iniciar no login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Sair", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func manualRefresh() { refresh() }
    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        render(state: currentState())
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
```

- [ ] **Step 4: Wire main.swift**

Replace `Sources/ClaudeUsageBar/main.swift`:
```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 5: Build**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeUsageBar
git commit -m "feat: menu bar app UI, poller, panel, login item"
```

---

### Task 11: App bundle packaging + manual acceptance

**Files:**
- Create: `Scripts/make-app.sh`
- Create: `Sources/ClaudeUsageBar/Info.plist` (bundle template)

**Interfaces:**
- Consumes: the built `ClaudeUsageBar` executable.
- Produces: `build/ClaudeUsageBar.app` runnable bundle.

- [ ] **Step 1: Create Info.plist template**

`Sources/ClaudeUsageBar/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClaudeUsageBar</string>
    <key>CFBundleDisplayName</key><string>Claude Usage</string>
    <key>CFBundleIdentifier</key><string>com.wilson.claudeusagebar</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>ClaudeUsageBar</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
```

- [ ] **Step 2: Create the packaging script**

`Scripts/make-app.sh`:
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=$(swift build -c release --show-bin-path)/ClaudeUsageBar

APP="build/ClaudeUsageBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudeUsageBar"
cp Sources/ClaudeUsageBar/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc code signature so SMAppService / Keychain ACLs behave predictably.
codesign --force --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
```

- [ ] **Step 3: Make it executable and run it**

```bash
chmod +x Scripts/make-app.sh
./Scripts/make-app.sh
open build/ClaudeUsageBar.app
```
Expected: `Built build/ClaudeUsageBar.app`, then a new item appears in the menu bar.

- [ ] **Step 4: Manual acceptance checklist**

Verify each, against the live `/usage` command in Claude Code:
- Menu bar shows `◐ N% · zera em …` and the `N%` matches the session line in `/usage`.
- Clicking opens the panel: Session (5h) and Semana (7d) bars with matching percentages and reset times.
- Click **↻ Atualizar** → timestamp resets to "Atualizado agora".
- Toggle **Iniciar no login** → run `SMAppService` check: the checkmark flips; after enabling, `sfltool dumpbtm 2>/dev/null | grep -i claudeusagebar` (or System Settings → General → Login Items) lists the app.
- Turn Wi-Fi off, wait ~60s, open panel → shows `⚠ desatualizado …`, does not crash, keeps last numbers. Turn Wi-Fi back on → recovers on next poll.
- **Sair** removes the menu bar item.

If the Keychain read triggers a macOS permission prompt on first launch, that is expected - approve it (the app reads the same `Claude Code-credentials` item).

- [ ] **Step 5: Commit**

```bash
git add Scripts/make-app.sh Sources/ClaudeUsageBar/Info.plist
git commit -m "feat: app bundle packaging and acceptance checklist"
```

---

## Self-Review Notes

- **Spec coverage:** Keychain read (T3/T9), silent token refresh preserving other keys (T3/T6/T9), usage fetch+decode with `limits` primary (T4/T7), `UsageSnapshot` model reused by UI (T4), menu bar compact title with severity color + reset countdown incl. critical emphasis (T8/T10), panel with bars/reset/per-model (T10), error/offline stale + not-logged-in states (T4 severity, T10 handling), start-at-login default-on + toggle (T10), `.app` packaging (T11), reusable `UsageKit` boundary for future WidgetKit (whole library has no AppKit import). All covered.
- **Placeholder scan:** none - every code step is complete.
- **Type consistency:** `CredentialsStoring`/`TokenRefreshing`/`RefreshedTokens` defined in T6 and implemented in T9; `HTTPClient` defined in T7 and reused by `OAuthRefresher` in T9; `BarState`/`UsageSnapshot`/`UsageWindow`/`Severity` names consistent across T4/T8/T10; `countdown`/`clockLabel`/`relativeTime` signatures match between T5 and T10 usage.
