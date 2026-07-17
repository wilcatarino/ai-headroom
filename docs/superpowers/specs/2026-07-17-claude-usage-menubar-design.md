# Claude Code Usage, Menu Bar App (macOS)

**Date:** 2026-07-17
**Status:** Implemented (see "Implementation notes" at the end for deviations from this design)

> **Rename:** the product was later named **Headroom** (repo `ai-headroom`), reframed as a multi-provider usage meter that starts with Claude Code. Where this document says `ClaudeUsageBar`, the shipped app and executable are `Headroom`. The `UsageKit` library name is unchanged.

## Goal

A fully functional macOS menu bar app that shows, at a glance, how much of the authenticated Claude Code subscription plan the user has consumed. This is the same data surfaced by the `/usage` command: the 5-hour session window and the 7-day weekly window, with reset times and countdowns. The primary question it answers is "am I about to hit my limit, and when does it reset?".

The data layer is deliberately isolated so a future WidgetKit widget (Notification Center or desktop) can reuse it without change. WidgetKit itself is out of scope for this iteration, because it requires full Xcode and the user currently has only the Command Line Tools.

## Non-goals (this iteration)

- Native WidgetKit widget (future work, needs Xcode). The architecture must not block it.
- Token or cost accounting from local `.jsonl` logs (that was option B, not chosen).
- Activity stats (messages, sessions, tool calls).
- Multi-account switching.

## Data source (verified)

`GET https://api.anthropic.com/api/oauth/usage`

Headers:

- `Authorization: Bearer <accessToken>`
- `anthropic-beta: oauth-2025-04-20`

The verified 200 response contains:

- `five_hour`: `{ utilization: Double, resets_at: ISO8601, limit_dollars, used_dollars, remaining_dollars }`
- `seven_day`: same shape.
- `limits: [ { kind, group, percent: Int, severity: "normal"|"warning"|..., resets_at: ISO8601?, scope: { model: { id, display_name } }?, is_active: Bool } ]`
  - `kind`: `session` | `weekly_all` | `weekly_scoped`.
  - This array is the primary decode target. It carries the server-computed `severity` (used for color) and the per-model scope. The top-level `five_hour` and `seven_day` are kept as convenience fallbacks.
- Other fields (`spend`, `extra_usage`, per-model top-level keys) are ignored this iteration but tolerated (unknown-key-tolerant decoding).

### Credentials

Stored in the macOS Keychain as a generic password with service `Claude Code-credentials`. The password value is JSON:

```json
{ "claudeAiOauth": {
    "accessToken": "sk-ant-oat01-…",
    "refreshToken": "sk-ant-ort01-…",
    "expiresAt": 1784267326248,   // epoch millis
    "subscriptionType": "max",
    "rateLimitTier": "default_claude_max_20x"
} }
```

`subscriptionType` and `rateLimitTier` drive the "Plano Max (20x)" label in the panel.

## Architecture

Three units. Unit 1 is the reusable core.

### 1. `UsageKit`, reusable library (SwiftPM library target)

Pure logic, no AppKit. This is what a future widget target imports.

- `KeychainCredentials` reads and writes the `Claude Code-credentials` item. `load() -> Credentials?` decodes the JSON blob. `save(Credentials)` writes back after a refresh (the same item Claude Code uses).
- `OAuthRefresher`: when `expiresAt` is in the past (or within a 60s skew), it exchanges `refreshToken` at the Anthropic OAuth token endpoint, gets a fresh `accessToken`, `expiresAt` and rotated `refreshToken`, and persists via `KeychainCredentials.save`. This keeps the app working even if Claude Code has not run recently. Refresh is best-effort: on failure, fall back to the existing (possibly expired) token for the request and surface the resulting error to the UI state.
- `UsageClient` exposes `fetch() async throws -> UsageSnapshot`. It ensures a valid token (refreshing if needed), calls the usage endpoint and decodes.
- `UsageSnapshot` is the normalized view model the UI renders: `plan: String` (e.g. "Max (20x)"), `session: Window` as `{ percent: Int, severity: Severity, resetsAt: Date? }`, `weekly: Window`, `models: [ModelUsage]` as `{ name: String, percent: Int, severity, resetsAt: Date? }` (from `limits` where `scope.model` is present and `percent > 0`), and `fetchedAt: Date`. `Severity` is `.normal | .warning | .critical`, derived from the server `severity` when present, else from percent thresholds (`>=90` critical, `>=70` warning).

### 2. `ClaudeUsageBar`, menu bar app (SwiftPM executable, AppKit)

- `LSUIElement = true` (no Dock icon, menu-bar-only agent app).
- `NSStatusItem` in the system status bar.
- Poller: a `Timer` every 60s calls `UsageClient.fetch()`, plus a fetch on launch and on manual "Atualizar".
- Status bar title (compact): normal shows `◐ 8% · zera em 5h12m` (session percent plus session reset countdown). When session severity is `.critical` (>=90%) it emphasizes the reset, e.g. `● no teto · zera 12m`. The color and symbol reflect the max severity of session and weekly: normal is a template color that adapts to light and dark, warning is yellow, critical is red. Countdown formats coarsely: `5h12m`, `47m`, `3m`, `<1m`.
- Dropdown panel (`NSMenu` with a custom `NSView`): progress bars for Session (5h) and Weekly (7d), each showing `percent`, the exact reset clock (`07:20`, `22/07 03:00`) and countdown (`em 5h12m`, `em 4d19h`); per-model rows when available; and a footer with `Atualizado <relativo>`, Atualizar, Iniciar no login and Sair.

### 3. Packaging and login item

- `swift build -c release` produces the executable, and a small build script assembles a proper `ClaudeUsageBar.app` bundle (Info.plist with `LSUIElement` and bundle id) so it can live in `/Applications` and be launched normally.
- Start at login uses `SMAppService.mainApp.register()` (macOS 13+), toggled by the panel item and reflecting the current registration state.

## UI states and error handling

- Loading (first launch): `◐ …` until the first fetch resolves.
- Not logged in (no Keychain item): the bar shows `◐ -` and the panel shows "Faça login no Claude Code" with no bars.
- Offline or API error: keep the last good snapshot, leave the bar unchanged, and show "desatualizado há X min" next to the timestamp in the panel. Never crash, never blank.
- Token expired: silent refresh. Only if the refresh also fails do we degrade to the offline or error state above.

## Testing strategy

- `UsageKit` is pure and unit-testable: JSON decoding of the real captured response fixture into `UsageSnapshot` (percents, reset dates, per-model rows, severity mapping); credentials blob decode and non-destructive rewrite; countdown and relative-time formatting with a fixed injected "now"; severity derivation (server value vs percent fallback); and the token-expiry decision (`expiresAt` vs injected now, with skew).
- Network (`UsageClient` HTTP, `OAuthRefresher` exchange) and Keychain I/O sit behind small protocols so tests inject fakes. Real network is exercised manually.
- Manual acceptance: launch the app, confirm the bar matches `/usage`, force a refresh, simulate offline (turn off Wi-Fi) to see the stale indicator, and toggle the login item.

## Open decisions locked in

- The menu bar shows the session (5h) window as the primary number plus its reset countdown; weekly lives in the panel. Rationale: the 5h window is the fast-moving one.
- Poll interval is 60s.
- Start-at-login is enabled by default on first run (the user asked for it), with a toggle in the panel.

## Future: WidgetKit expansion (option B)

When Xcode is available: create an Xcode project, add the `UsageKit` sources as a shared framework target, and add a Widget Extension whose `TimelineProvider` calls `UsageClient.fetch()` and renders the same `UsageSnapshot`. No changes to `UsageKit` are expected. An App Group entitlement lets the widget share the last snapshot cache.

## Implementation notes (what shipped, and deviations from the design above)

The implementation follows this design. The differences, all forced by the "no Xcode" constraint or discovered during testing, are:

- Tests do not use `swift test`. XCTest and swift-testing ship only with full Xcode, so the test suite is a small executable target (`UsageKitTests`) with a custom assertion harness, run via `swift run UsageKitTests`. It exits non-zero on failure, so it works in CI.
- The not-logged-in and empty-countdown placeholder is a hyphen (`◐ -`, `-`) rather than an em dash, for consistency with the docs style.
- An explicit `error` UI state was added (`◐ ⚠`) plus a fast retry with backoff (2, 4, 8, 15 seconds) until the first successful load. This fixes a case where a transient first fetch (Keychain first-access prompt or cold-start network) left the bar on "Carregando…" until a manual refresh.
- Refresh events are logged via `NSLog` (visible in Console.app or via stderr when run directly) for diagnosis.
- The bundle `Info.plist` lives in `Packaging/Info.plist` (not under `Sources/`, where SwiftPM would flag it as an unhandled resource). The build script `Scripts/make-app.sh` grew `--run` and `--install` modes for the day-to-day rebuild-and-relaunch flow.
- Concrete fixture numbers in tests reflect the captured response at implementation time (session and weekly percentages) and are frozen on disk for determinism.
