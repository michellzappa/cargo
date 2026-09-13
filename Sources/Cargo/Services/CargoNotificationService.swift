import HouseKit
import UserNotifications

@MainActor
final class CargoNotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() {
        Notifications.request()
    }

    func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "cargo-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
