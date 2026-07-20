import AppKit
import UsageKit

/// Per-provider live state: the latest snapshot plus the login/error/poll
/// bookkeeping that used to live directly on AppDelegate. One instance per
/// registered provider so each can be logged in, erroring, or loading
/// independently.
@MainActor
final class ProviderRuntime {
    let provider: any UsageProvider
    var lastSnapshot: UsageSnapshot?
    var loggedOut = false
    var hasError = false
    /// Consecutive failed fetches, used to grow the backoff. Reset to 0 on a
    /// successful fetch or a "not logged in" result (which sends no request).
    var consecutiveFailures = 0
    /// Bumped whenever a fetch starts or is scheduled, so a stale pending poll
    /// invalidates itself instead of stacking extra requests.
    var pollGeneration = 0

    init(_ provider: any UsageProvider) { self.provider = provider }

    var info: ProviderInfo { provider.info }

    var state: BarState {
        if let s = lastSnapshot { return .data(s) }
        if loggedOut { return .loggedOut }
        if hasError { return .error }
        return .loading
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private func log(_ msg: String) { NSLog("[AIHeadroom] \(msg)") }

    private var statusItem: NSStatusItem!
    private var runtimes: [ProviderRuntime] = []

    private static let defaultProviderKey = "defaultProviderID"

    // Poll cadence. The steady interval stays under the panel's 180s "stale"
    // threshold so normal operation never looks out of date. On failure the app
    // backs off exponentially from `retryBase` up to `maxBackoff`, so a
    // rate-limited endpoint (HTTP 429) is not hammered. See nextRefreshDelay.
    private static let pollInterval: TimeInterval = 120
    private static let retryBase: TimeInterval = 30
    private static let maxBackoff: TimeInterval = 1800

    /// The provider whose number is shown in the menu bar. The user picks it
    /// from the menu (when more than one is registered); the choice persists.
    /// Falls back to the first provider.
    private var barRuntime: ProviderRuntime? {
        let id = UserDefaults.standard.string(forKey: Self.defaultProviderKey)
        return runtimes.first(where: { $0.info.id == id }) ?? runtimes.first
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let http = URLSessionHTTPClient()
        let store = KeychainStore()
        let refresher = OAuthRefresher(http: http)
        let tokenProvider = TokenProvider(store: store, refresher: refresher)
        let planString = ((try? store.load()) ?? nil).map {
            planLabel(subscriptionType: $0.subscriptionType, rateLimitTier: $0.rateLimitTier)
        } ?? "Claude Code"

        // The provider list is the single place new providers slot in.
        runtimes = [
            ProviderRuntime(AnthropicProvider(http: http, tokenProvider: tokenProvider, plan: { planString })),
        ]

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Enable start-at-login by default on first run, but only from an
        // installed .app bundle so a dev binary never registers a login item.
        // The flag is left unset when unsupported, so a later proper install
        // still gets the default-on behavior.
        if LoginItem.isSupported, !UserDefaults.standard.bool(forKey: "didSetInitialLoginItem") {
            LoginItem.setEnabled(true)
            UserDefaults.standard.set(true, forKey: "didSetInitialLoginItem")
        }

        // Preview mode: force a severity state so colors can be reviewed live,
        // e.g. `AIHEADROOM_PREVIEW=warning` when running the binary directly.
        // Skips live fetching.
        if let preview = ProcessInfo.processInfo.environment["AIHEADROOM_PREVIEW"] {
            renderPreview(preview)
            return
        }

        render()
        refreshAll()
    }

    private func renderPreview(_ preview: String) {
        let now = Date()
        let sev: Severity = preview == "critical" ? .critical : .warning
        let snap = UsageSnapshot(
            plan: "Max (20x) · preview \(sev)",
            session: UsageWindow(percent: sev == .critical ? 95 : 82, severity: sev,
                                 resetsAt: now.addingTimeInterval(2 * 3600 + 10 * 60)),
            weekly: UsageWindow(percent: 60, severity: .warning,
                                resetsAt: now.addingTimeInterval(3 * 86400)),
            models: [],
            fetchedAt: now)
        runtimes.first?.lastSnapshot = snap
        render()
    }

    private func refreshAll() {
        for rt in runtimes { refresh(rt) }
    }

    private func refresh(_ rt: ProviderRuntime) {
        // Invalidate any pending scheduled poll for this runtime so a manual
        // refresh (or overlap) doesn't stack a second request on top.
        rt.pollGeneration += 1
        let gen = rt.pollGeneration
        Task { @MainActor in
            do {
                let snap = try await rt.provider.fetch(now: Date())
                rt.lastSnapshot = snap
                rt.loggedOut = false
                rt.hasError = false
                rt.consecutiveFailures = 0
                self.log("refresh ok [\(rt.info.id)]: session \(snap.session.percent)% weekly \(snap.weekly.percent)%")
            } catch TokenError.notLoggedIn {
                // No request was sent, so this is not a rate-limit concern: keep
                // the steady cadence so a later login is noticed promptly.
                self.log("refresh [\(rt.info.id)]: not logged in")
                rt.loggedOut = true
                rt.hasError = false
                rt.consecutiveFailures = 0
            } catch {
                // Back off so a failing or rate-limited endpoint is not hammered.
                // Prior data keeps showing (stale); otherwise the error glyph.
                rt.loggedOut = false
                rt.hasError = true
                rt.consecutiveFailures += 1
                self.log("refresh [\(rt.info.id)] failed (\(rt.consecutiveFailures)x): \(error)")
            }
            self.render()
            self.scheduleNextPoll(rt, gen: gen)
        }
    }

    /// Schedule this runtime's next fetch. The delay is the steady interval
    /// after a success, or a growing backoff after failures. The generation
    /// guard drops the scheduled fire if a newer refresh has since started.
    private func scheduleNextPoll(_ rt: ProviderRuntime, gen: Int) {
        guard rt.pollGeneration == gen else { return }
        let delay = nextRefreshDelay(
            consecutiveFailures: rt.consecutiveFailures,
            baseInterval: Self.pollInterval,
            retryBase: Self.retryBase,
            maxBackoff: Self.maxBackoff)
        rt.pollGeneration += 1
        let next = rt.pollGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak rt] in
            guard let self, let rt, rt.pollGeneration == next else { return }
            self.refresh(rt)
        }
    }

    private func render() {
        let now = Date()
        let barState = barRuntime?.state ?? .loading
        let title = renderMenuBarTitle(barState, now: now)
        statusItem.button?.attributedTitle = attributedTitle(title)
        statusItem.menu = buildMenu(now: now)
    }

    private func attributedTitle(_ title: MenuBarTitle) -> NSAttributedString {
        return NSAttributedString(string: title.text, attributes: [
            .foregroundColor: Palette.titleColor(for: title.severity),
            .font: NSFont.menuBarFont(ofSize: 0),
        ])
    }

    private func buildMenu(now: Date) -> NSMenu {
        let menu = NSMenu()
        // Manage item enablement ourselves so the login toggle can be disabled
        // when start-at-login is not manageable from this location.
        menu.autoenablesItems = false
        let header = NSMenuItem()
        header.view = UsagePanel.makeView(items: runtimes.map { ($0.info, $0.state) }, now: now)
        menu.addItem(header)
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "↻ Atualizar", action: #selector(manualRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        // Only worth showing once there is more than one provider to choose from.
        if runtimes.count > 1 {
            let submenu = NSMenu()
            let current = barRuntime?.info.id
            for rt in runtimes {
                let item = NSMenuItem(title: rt.info.displayName, action: #selector(selectBarProvider(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = rt.info.id
                item.state = rt.info.id == current ? .on : .off
                submenu.addItem(item)
            }
            let parent = NSMenuItem(title: "Mostrar na barra", action: nil, keyEquivalent: "")
            parent.submenu = submenu
            menu.addItem(parent)
        }

        let login = NSMenuItem(title: "Iniciar no login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        login.isEnabled = LoginItem.isSupported
        if !LoginItem.isSupported {
            login.toolTip = "Disponível quando o app está instalado em Aplicativos"
        }
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Sair", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func manualRefresh() { refreshAll() }

    @objc private func selectBarProvider(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        UserDefaults.standard.set(id, forKey: Self.defaultProviderKey)
        render()
    }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        render()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
