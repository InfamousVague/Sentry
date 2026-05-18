import Foundation
import UserNotifications

/// Thin wrapper over UserNotifications for "new/changed persistence" alerts.
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func postNewItem(_ item: PersistenceItem) {
        let content = UNMutableNotificationContent()
        switch item.source {
        case .launchAgent:
            content.title = "Launch agent added: \(item.name)"
        case .launchDaemon:
            content.title = "Launch daemon added: \(item.name)"
        case .loginItem:
            content.title = "New login item: \(item.name)"
        case .cron:
            content.title = "New cron job"
        case .shellRC:
            content.title = "Shell rc changed: \(item.name)"
        }
        var body = item.detail
        if item.source != .shellRC && item.source != .cron {
            body += "  ·  \(item.signature.label)"
        }
        body += ". Click to inspect in Sentry."
        content.body = body
        content.userInfo = ["sentryKey": item.key]
        send(id: "sentry-\(item.key)", content: content)
    }

    static func postSummary(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(count) new persistence items"
        content.body = "Sentry detected \(count) new launch/login entries. Click to review."
        send(id: "sentry-burst-\(Int(Date().timeIntervalSince1970))", content: content)
    }

    private static func send(id: String, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
