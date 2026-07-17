import AppKit
import UsageKit

/// Per-provider live state: the latest snapshot plus the login/error/retry
/// bookkeeping that used to live directly on AppDelegate. One instance per
/// registered provider so each can be logged in, erroring, or loading
/// independently.
@MainActor
final class ProviderRuntime {
    let provider: any UsageProvider
    var lastSnapshot: UsageSnapshot?
    var loggedOut = false
    var hasError = false
    var didLoadOnce = false
    var initialRetryIndex = 0

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
    private func log(_ msg: String) { NSLog("[Headroom] \(msg)") }

    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var runtimes: [ProviderRuntime] = []

    private static let defaultProviderKey = "defaultProviderID"

    /// The provider whose number is shown in the menu bar. The user picks it
    /// from the menu (when more than one is registered); the choice persists.
    /// Falls back to the first provider.
    private var barRuntime: ProviderRuntime? {
        let id = UserDefaults.standard.string(forKey: Self.defaultProviderKey)
        return runtimes.first(where: { $0.info.id == id }) ?? runtimes.first
    }

    /// Fast retry schedule used until a provider's first successful load, so a
    /// transient cold-start failure (keychain re-auth, network not ready)
    /// self-heals in seconds instead of waiting for the 60s poll.
    private static let initialRetryDelays: [TimeInterval] = [2, 4, 8, 15]

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

        // Enable start-at-login by default on first run.
        if !UserDefaults.standard.bool(forKey: "didSetInitialLoginItem") {
            LoginItem.setEnabled(true)
            UserDefaults.standard.set(true, forKey: "didSetInitialLoginItem")
        }

        // Preview mode: force a severity state so colors can be reviewed live,
        // e.g. `HEADROOM_PREVIEW=warning` when running the binary directly.
        // Skips live fetching.
        if let preview = ProcessInfo.processInfo.environment["HEADROOM_PREVIEW"] {
            renderPreview(preview)
            return
        }

        render()
        refreshAll()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAll() }
        }
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
        Task { @MainActor in
            do {
                let snap = try await rt.provider.fetch(now: Date())
                rt.lastSnapshot = snap
                rt.loggedOut = false
                rt.hasError = false
                rt.didLoadOnce = true
                rt.initialRetryIndex = 0
                self.log("refresh ok [\(rt.info.id)]: session \(snap.session.percent)% weekly \(snap.weekly.percent)%")
            } catch TokenError.notLoggedIn {
                self.log("refresh [\(rt.info.id)]: not logged in")
                rt.loggedOut = true
                rt.hasError = false
                self.scheduleInitialRetryIfNeeded(rt)
            } catch {
                self.log("refresh [\(rt.info.id)] failed: \(error)")
                rt.loggedOut = false
                rt.hasError = true
                // If we already had data, keep showing it (stale). Otherwise the
                // computed state falls back to the error glyph.
                self.scheduleInitialRetryIfNeeded(rt)
            }
            self.render()
        }
    }

    /// Before a provider's first successful load, keep retrying on a short
    /// backoff so the UI doesn't sit on "Carregando…"/error until the next tick.
    private func scheduleInitialRetryIfNeeded(_ rt: ProviderRuntime) {
        guard !rt.didLoadOnce, rt.initialRetryIndex < Self.initialRetryDelays.count else { return }
        let delay = Self.initialRetryDelays[rt.initialRetryIndex]
        rt.initialRetryIndex += 1
        self.log("scheduling initial retry [\(rt.info.id)] in \(delay)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak rt] in
            guard let self, let rt, !rt.didLoadOnce else { return }
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
