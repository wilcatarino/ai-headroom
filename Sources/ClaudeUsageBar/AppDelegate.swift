import AppKit
import UsageKit

@MainActor
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
                self.render(state: .data(snap))
            } catch TokenError.notLoggedIn {
                self.loggedOut = true
                self.render(state: .loggedOut)
            } catch {
                // keep last snapshot; panel shows the stale marker
                self.render(state: self.currentState())
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
