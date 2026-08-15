import Foundation

struct PushNotificationPreferences: Codable, Equatable, Sendable {
    static let `default` = PushNotificationPreferences(
        enabled: false,
        repliesAndMentions: true,
        moderation: false,
        channelActivity: false
    )

    let enabled: Bool
    let repliesAndMentions: Bool
    let moderation: Bool
    let channelActivity: Bool

    init(
        enabled: Bool,
        repliesAndMentions: Bool,
        moderation: Bool,
        channelActivity: Bool
    ) {
        self.enabled = enabled
        self.repliesAndMentions = repliesAndMentions
        self.moderation = moderation
        self.channelActivity = channelActivity
    }

    var backendRules: [String] {
        var rules: [String] = []
        if repliesAndMentions {
            rules += ["reply", "mention"]
        }
        if moderation {
            rules += ["automod_hold", "ban", "timeout", "moderation_action"]
        }
        if channelActivity {
            rules += [
                "stream_online",
                "title_change",
                "game_change",
                "raid",
                "reward",
                "subscription",
            ]
        }
        // The backend treats an empty rule array as legacy "all rules". Use a
        // deliberately unmatched marker when every optional category is disabled.
        return rules.isEmpty ? ["none"] : rules
    }
}

@MainActor
final class PushNotificationPreferencesStore {
    private struct Envelope: Codable {
        let version: Int
        let preferences: PushNotificationPreferences
    }

    static let currentVersion = 1
    static let storageKey = "push_notification_preferences_v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PushNotificationPreferences {
        guard let data = defaults.data(forKey: Self.storageKey),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == Self.currentVersion else {
            return .default
        }
        return envelope.preferences
    }

    @discardableResult
    func save(_ preferences: PushNotificationPreferences) -> PushNotificationPreferences {
        let envelope = Envelope(
            version: Self.currentVersion,
            preferences: preferences
        )
        if let data = try? JSONEncoder().encode(envelope) {
            defaults.set(data, forKey: Self.storageKey)
        }
        return preferences
    }
}
