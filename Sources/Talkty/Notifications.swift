import Foundation
import UserNotifications
import TalktyKit

/// Thin wrapper over UNUserNotificationCenter for the "Show notification" option
/// and permission hints. Replaces the Windows tray BalloonTip.
enum Notifications {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func show(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }
}
