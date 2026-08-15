import UIKit
import UserNotifications

@MainActor
protocol PushNotificationAuthorizing: AnyObject {
    func requestAuthorization() async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func registerForRemoteNotifications()
    func unregisterForRemoteNotifications()
}

@MainActor
final class PushNotificationAuthorizationService: PushNotificationAuthorizing {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func unregisterForRemoteNotifications() {
        UIApplication.shared.unregisterForRemoteNotifications()
    }
}
