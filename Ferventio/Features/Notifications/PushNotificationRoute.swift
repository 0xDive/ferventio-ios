import Foundation
import FerventioDomain

struct PushNotificationRoute: Equatable, Sendable {
    let channelLogin: String
    let messageID: String?
    let destination: String?

    init?(userInfo: [AnyHashable: Any]) {
        guard let payload = Self.dictionary(userInfo["ferventio"]),
              let rawChannelLogin = payload["channelLogin"] as? String,
              let channelLogin = ChatWorkspaceRegistryStore.normalizedLogin(rawChannelLogin) else {
            return nil
        }

        self.channelLogin = channelLogin
        messageID = Self.nonEmptyString(payload["messageId"])
        destination = Self.nonEmptyString(payload["destination"])
    }

    var notificationUserInfo: [AnyHashable: Any] {
        var payload: [String: Any] = ["channelLogin": channelLogin]
        if let messageID {
            payload["messageId"] = messageID
        }
        if let destination {
            payload["destination"] = destination
        }
        return ["ferventio": payload]
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        guard let dictionary = value as? [AnyHashable: Any] else {
            return nil
        }

        var result: [String: Any] = [:]
        result.reserveCapacity(dictionary.count)
        for (key, value) in dictionary {
            guard let key = key as? String else {
                continue
            }
            result[key] = value
        }
        return result
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct PushNotificationRouteSessionPolicy {
    static func acceptsOpenedRoute(in state: AppState) -> Bool {
        state != .signedOut
    }

    static func shouldClearPendingRoute(
        previousUserID: String?,
        currentUserID: String?
    ) -> Bool {
        previousUserID != nil && currentUserID == nil
    }
}

final class PushNotificationRouteBuffer: @unchecked Sendable {
    static let shared = PushNotificationRouteBuffer()

    private let lock = NSLock()
    private var pendingRoute: PushNotificationRoute?

    func store(_ route: PushNotificationRoute) {
        lock.withLock {
            pendingRoute = route
        }
    }

    func takeLatest() -> PushNotificationRoute? {
        lock.withLock {
            defer { pendingRoute = nil }
            return pendingRoute
        }
    }

    func clear() {
        lock.withLock {
            pendingRoute = nil
        }
    }
}
