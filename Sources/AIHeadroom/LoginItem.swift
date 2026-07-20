import Foundation
import ServiceManagement
import UsageKit

enum LoginItem {
    /// Whether start-at-login can be managed from where the app is running.
    /// False for the dev binary or an .app outside Applications, so neither
    /// registers a stray login item. See `canManageLoginItem`.
    static var isSupported: Bool { canManageLoginItem(bundlePath: Bundle.main.bundlePath) }

    static var isEnabled: Bool { isSupported && SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isSupported else {
            NSLog("LoginItem: skipping registration, not an installed .app bundle (\(Bundle.main.bundlePath))")
            return false
        }
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
