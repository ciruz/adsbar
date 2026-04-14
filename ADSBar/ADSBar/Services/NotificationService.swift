import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private init() {
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                print("Notification auth error: \(error)")
            }
        }
    }

    func sendDeviceOffline(name: String) {
        send(
            id: "offline-\(name)",
            title: "Station Offline",
            body: "\(name) is no longer responding."
        )
    }

    private func send(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
