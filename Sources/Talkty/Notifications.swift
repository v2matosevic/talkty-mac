import Foundation
import UserNotifications
import TalktyKit

/// Thin wrapper over UNUserNotificationCenter for the "Show notification" option
/// and the failure/permission notices. Replaces the Windows tray BalloonTip.
///
/// Authorization is requested lazily on the first notice, not only when the user
/// turns "Show notification" on: the failure notices ("Prompting failed", "Auto-paste
/// needs Accessibility") were silently dropped for everyone who never enabled the
/// success toast, because UNUserNotificationCenter ignores requests without a grant.
enum Notifications {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func show(title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { deliver(title, body) }
                    else { Log.debug("Notification declined, dropped: \(title)") }
                }
            case .denied:
                Log.debug("Notifications denied in System Settings, dropped: \(title)")
            default:
                deliver(title, body)
            }
        }
    }

    private static func deliver(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
