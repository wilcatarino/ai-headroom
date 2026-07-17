import AppKit
import UsageKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private func log(_ msg: String) { NSLog("[ClaudeUsageBar] \(msg)") }

    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var client: UsageClient!
    private var lastSnapshot: UsageSnapshot?
    private var loggedOut = false
    private var hasError = false

    /// Fast retry schedule used until the first successful load, so a transient
    /// cold-start failure (keychain re-auth, network not ready) self-heals in
    /// seconds instead of waiting for the 60s poll.
    private static let initialRetryDelays: [TimeInterval] = [2, 4, 8, 15]
    private var initialRetryIndex = 0
    private var didLoadOnce = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let http = URLSessionHTTPClient()
        let store = KeychainStore()
        let refresher = OAuthRefresher(http: http)
        let provider = TokenProvider(store: store, refresher: refresher)
        let planString = ((try? store.load()) ?? nil).map {
            planLabel(subscriptionType: $0.subscriptionType, rateLimitTier: $0.rateLimitTier)
        } ?? "Claude Code"
        client = UsageClient(http: http, tokenProvider: provider, plan: { planString })

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Enable start-at-login by default on first run.
        if !UserDefaults.standard.bool(forKey: "didSetInitialLoginItem") {
            LoginItem.setEnabled(true)
            UserDefaults.standard.set(true, forKey: "didSetInitialLoginItem")
        }

        render(state: .loading)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        Task { @MainActor in
            do {
                let snap = try await self.client.fetch(now: Date())
                self.lastSnapshot = snap
                self.loggedOut = false
                self.hasError = false
                self.didLoadOnce = true
                self.initialRetryIndex = 0
                self.log("refresh ok: session \(snap.session.percent)% weekly \(snap.weekly.percent)%")
                self.render(state: .data(snap))
            } catch TokenError.notLoggedIn {
                self.log("refresh: not logged in")
                self.loggedOut = true
                self.hasError = false
                self.render(state: .loggedOut)
                self.scheduleInitialRetryIfNeeded()
            } catch {
                self.log("refresh failed: \(error)")
                self.loggedOut = false
                self.hasError = true
                // If we already had data, keep showing it (stale). Otherwise
                // surface the error state and retry quickly.
                self.render(state: self.currentState())
                self.scheduleInitialRetryIfNeeded()
            }
        }
    }

    /// Before the first successful load, keep retrying on a short backoff so the
    /// UI doesn't sit on "Carregando…"/error until the next 60s tick.
    private func scheduleInitialRetryIfNeeded() {
        guard !didLoadOnce, initialRetryIndex < Self.initialRetryDelays.count else { return }
        let delay = Self.initialRetryDelays[initialRetryIndex]
        initialRetryIndex += 1
        self.log("scheduling initial retry in \(delay)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.didLoadOnce else { return }
            self.refresh()
        }
    }

    private func currentState() -> BarState {
        if let s = lastSnapshot { return .data(s) }
        if loggedOut { return .loggedOut }
        if hasError { return .error }
        return .loading
    }

    private func render(state: BarState) {
        let now = Date()
        let title = renderMenuBarTitle(state, now: now)
        statusItem.button?.attributedTitle = attributedTitle(title)
        statusItem.menu = buildMenu(state: state, now: now)
    }

    private func attributedTitle(_ title: MenuBarTitle) -> NSAttributedString {
        let color: NSColor
        switch title.severity {
        case .normal: color = .labelColor
        case .warning: color = .systemYellow
        case .critical: color = .systemRed
        }
        return NSAttributedString(string: title.text, attributes: [
            .foregroundColor: color,
            .font: NSFont.menuBarFont(ofSize: 0),
        ])
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
