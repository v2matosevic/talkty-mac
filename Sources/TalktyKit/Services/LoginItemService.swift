import Foundation
import ServiceManagement

/// Registers Talkty as a macOS login item via SMAppService (macOS 13+). The main
/// app registers itself — no helper bundle needed. Requires the app to be signed
/// (we use a stable self-signed identity in dev) and launched from a real .app
/// bundle; when run as a bare SwiftPM binary the calls no-op with a logged warning.
public enum LoginItemService {

    /// Whether Talkty is currently registered to launch at login.
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Human-readable login-item status (for logs / the --login-item CLI hook).
    public static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .notRegistered: return "notRegistered"
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown"
        }
    }

    /// Register or unregister the login item. Returns false on failure (e.g. running
    /// unbundled, or the user must approve it in System Settings → Login Items).
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, .enabled), (false, .notRegistered):
                return true                                   // already in the desired state
            case (true, _):
                try SMAppService.mainApp.register()
            case (false, _):
                try SMAppService.mainApp.unregister()
            }
            Log.info("Login item \(enabled ? "enabled" : "disabled")")
            return true
        } catch {
            Log.warning("Login item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
            return false
        }
    }
}
