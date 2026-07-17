# Claude Code Usage — Menu Bar App (macOS)

**Date:** 2026-07-17
**Status:** Approved design → implementation planning

## Goal

A fully functional macOS menu bar app that shows, at a glance, how much of the
authenticated Claude Code subscription plan the user has consumed — the same data
surfaced by the `/usage` command: the 5-hour session window and the 7-day weekly
window, with reset times and countdowns. Primary question it answers: **"am I
about to hit my limit, and when does it reset?"**

The data layer is deliberately isolated so a future WidgetKit widget (Notification
Center / desktop) can reuse it without change. WidgetKit itself is out of scope for
this iteration (it requires full Xcode; the user currently has only Command Line
Tools).

## Non-goals (this iteration)

- Native WidgetKit widget (future; needs Xcode). Architecture must not block it.
- Token/cost accounting from local `.jsonl` logs (that was option B, not chosen).
- Activity stats (messages/sessions/tool calls).
- Multi-account switching.

## Data source (verified)

`GET https://api.anthropic.com/api/oauth/usage`

Headers:
- `Authorization: Bearer <accessToken>`
- `anthropic-beta: oauth-2025-04-20`

Verified 200 response contains:

- `five_hour`: `{ utilization: Double, resets_at: ISO8601, limit_dollars, used_dollars, remaining_dollars }`
- `seven_day`: same shape.
- `limits: [ { kind, group, percent: Int, severity: "normal"|"warning"|..., resets_at: ISO8601?, scope: { model: { id, display_name } }?, is_active: Bool } ]`
  - `kind`: `session` | `weekly_all` | `weekly_scoped`.
  - This array is the **primary** decode target: it carries server-computed
    `severity` (used for color) and per-model scope. The top-level `five_hour` /
    `seven_day` are kept as convenience fallbacks.
- Other fields (`spend`, `extra_usage`, per-model top-level keys) are ignored this
  iteration but tolerated (unknown-key-tolerant decoding).

### Credentials

Stored in macOS Keychain, generic password, service `Claude Code-credentials`.
The password value is JSON:

```json
{ "claudeAiOauth": {
    "accessToken": "sk-ant-oat01-…",
    "refreshToken": "sk-ant-ort01-…",
    "expiresAt": 1784267326248,   // epoch millis
    "subscriptionType": "max",
    "rateLimitTier": "default_claude_max_20x"
} }
```

`subscriptionType` + `rateLimitTier` drive the "Plano Max (20x)" label in the panel.

## Architecture

Three units. Unit 1 is the reusable core.

### 1. `UsageKit` — reusable library (SwiftPM library target)

Pure logic, no AppKit. This is what a future widget target imports.

- **`KeychainCredentials`** — reads/writes the `Claude Code-credentials` item.
  - `load() -> Credentials?` decodes the JSON blob.
  - `save(Credentials)` writes back after a refresh (same item Claude Code uses).
- **`OAuthRefresher`** — when `expiresAt` is in the past (or within a 60s skew),
  exchanges `refreshToken` at the Anthropic OAuth token endpoint, gets a fresh
  `accessToken` + `expiresAt` + rotated `refreshToken`, and persists via
  `KeychainCredentials.save`. Keeps the app working even if Claude Code hasn't run.
  - Refresh is best-effort: on failure, fall back to the existing (possibly
    expired) token for the request; surface the resulting error to the UI state.
- **`UsageClient`** — `fetch() async throws -> UsageSnapshot`.
  - Ensures a valid token (refresh if needed), calls the usage endpoint, decodes.
- **`UsageSnapshot`** (model) — normalized view the UI renders:
  - `plan: String` (e.g. "Max (20x)")
  - `session: Window` — `{ percent: Int, severity: Severity, resetsAt: Date? }`
  - `weekly: Window`
  - `models: [ModelUsage]` — `{ name: String, percent: Int, severity, resetsAt: Date? }`
    (from `limits` where `scope.model` is present and `percent > 0`)
  - `fetchedAt: Date`
  - `Severity`: `.normal | .warning | .critical`, derived from server `severity`
    when present, else percent thresholds (`>=90` critical, `>=70` warning).

### 2. `ClaudeUsageBar` — menu bar app (SwiftPM executable, AppKit)

- `LSUIElement = true` (no Dock icon, menu-bar-only agent app).
- `NSStatusItem` in the system status bar.
- **Poller**: `Timer` every **60s** calls `UsageClient.fetch()`; also fetch on
  launch and on manual "Atualizar".
- **Status bar title** (compact):
  - Normal: `◐ 8% · zera em 5h12m` — session percent + session reset countdown.
  - When session severity is `.critical` (>=90%): emphasize reset, e.g.
    `● no teto · zera 12m`.
  - Color/symbol reflects the max severity of session/weekly:
    normal = template (adapts to light/dark), warning = yellow, critical = red.
  - Countdown formats coarsely: `5h12m`, `47m`, `3m`, `<1m`.
- **Dropdown panel** (`NSMenu` with a custom `NSView`, or `MenuBarExtra`-style
  content): progress bars for Session (5h) and Weekly (7d), each showing
  `percent`, exact reset clock (`07:20`, `22/07 03:00`) and countdown (`em 5h12m`,
  `em 4d19h`); per-model rows when available; footer:
  `Atualizado <relativo> · ↻ Atualizar · [ ] Iniciar no login · Sair`.

### 3. Packaging & login item

- `swift build -c release` produces the executable; a small build script assembles
  a proper `ClaudeUsageBar.app` bundle (Info.plist with `LSUIElement`, bundle id,
  icon) so it can live in `/Applications` and be launched normally.
- **Start at login**: `SMAppService.mainApp.register()` (macOS 13+), toggled by the
  panel checkbox; reflects current registration state.

## UI states & error handling

- **Loading (first launch)**: `◐ …` until first fetch resolves.
- **Not logged in** (no Keychain item): bar shows `◐ —`; panel shows
  "Faça login no Claude Code" with no bars.
- **Offline / API error**: keep last good snapshot; bar unchanged; panel shows
  `⚠ desatualizado há Xmin` next to the timestamp. Never crash, never blank.
- **Token expired**: silent refresh; only if refresh also fails do we degrade to
  the offline/error state above.

## Testing strategy

- `UsageKit` is pure and unit-testable (SwiftPM `swift test`):
  - JSON decoding of the real captured response fixture → `UsageSnapshot`
    (percents, reset dates, per-model rows, severity mapping).
  - Credentials blob decode/encode round-trip.
  - Countdown/relative-time formatting (fixed "now" injected).
  - Severity derivation (server value vs percent fallback).
  - Token-expiry decision (`expiresAt` vs injected now, with skew).
- Network (`UsageClient` HTTP, `OAuthRefresher` exchange, Keychain I/O) is behind
  small protocols so tests inject fakes; real network is exercised manually.
- Manual acceptance: launch app, confirm bar matches `/usage`, force-refresh,
  simulate offline (turn off Wi-Fi) → stale indicator, toggle login item.

## Open decisions locked in

- Menu bar shows the **session (5h)** window as the primary number + its reset
  countdown; weekly lives in the panel. Rationale: 5h is the fast-moving one.
- Poll interval **60s**.
- Start-at-login **enabled by default** on first run (user asked for it), toggle
  in panel.

## Future: WidgetKit expansion (option B)

When Xcode is available: create an Xcode project, add the `UsageKit` sources as a
shared framework target, add a Widget Extension whose `TimelineProvider` calls
`UsageClient.fetch()` and renders the same `UsageSnapshot`. No changes to `UsageKit`
expected. App Group entitlement lets the widget share the last snapshot cache.
