import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let ferventioDidRegisterAPNsDeviceToken = Notification.Name(
        "io.ferventio.ios.did-register-apns-device-token"
    )
    static let ferventioDidFailAPNsRegistration = Notification.Name(
        "io.ferventio.ios.did-fail-apns-registration"
    )
    static let ferventioDidOpenRemoteNotification = Notification.Name(
        "io.ferventio.ios.did-open-remote-notification"
    )
}

final class FerventioAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationCenter.default.post(
            name: .ferventioDidRegisterAPNsDeviceToken,
            object: deviceToken
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        NotificationCenter.default.post(
            name: .ferventioDidFailAPNsRegistration,
            object: error
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        NotificationCenter.default.post(
            name: .ferventioDidOpenRemoteNotification,
            object: nil,
            userInfo: response.notification.request.content.userInfo
        )
    }
}
