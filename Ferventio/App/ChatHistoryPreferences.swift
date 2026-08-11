import Foundation

struct ChatHistoryPreferences: Codable, Equatable, Sendable {
    static let minimumLocalHistoryLimit = 100
    static let maximumLocalHistoryLimit = 5_000
    static let maximumRetentionDays = 365
    static let maximumDatabaseSizeMB = 1_024

    static let `default` = ChatHistoryPreferences(
        recentMessagesEnabled: true,
        localHistoryEnabled: true,
        localHistoryLimit: 500,
        retentionDays: 7,
        maxDatabaseSizeMB: 0
    )

    let recentMessagesEnabled: Bool
    let localHistoryEnabled: Bool
    let localHistoryLimit: Int
    let retentionDays: Int
    let maxDatabaseSizeMB: Int

    init(
        recentMessagesEnabled: Bool,
        localHistoryEnabled: Bool,
        localHistoryLimit: Int,
        retentionDays: Int,
        maxDatabaseSizeMB: Int
    ) {
        self.recentMessagesEnabled = recentMessagesEnabled
        self.localHistoryEnabled = localHistoryEnabled
        self.localHistoryLimit = localHistoryLimit.clamped(
            to: Self.minimumLocalHistoryLimit...Self.maximumLocalHistoryLimit
        )
        self.retentionDays = retentionDays.clamped(to: 0...Self.maximumRetentionDays)
        self.maxDatabaseSizeMB = maxDatabaseSizeMB.clamped(
            to: 0...Self.maximumDatabaseSizeMB
        )
    }

    var initialRestoreLimit: Int {
        min(localHistoryLimit, 500)
    }

    func retentionBoundaryMilliseconds(nowMilliseconds: Int64) -> Int64? {
        guard retentionDays > 0 else {
            return nil
        }
        let retentionMilliseconds = Int64(retentionDays) * 24 * 60 * 60 * 1_000
        return max(0, nowMilliseconds - retentionMilliseconds)
    }
}

@MainActor
final class ChatHistoryPreferencesStore {
    private struct Envelope: Codable {
        let version: Int
        let preferences: ChatHistoryPreferences
    }

    static let currentVersion = 1
    static let storageKey = "chat_history_preferences_v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ChatHistoryPreferences {
        guard let data = defaults.data(forKey: Self.storageKey),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == Self.currentVersion else {
            return .default
        }
        return ChatHistoryPreferences(
            recentMessagesEnabled: envelope.preferences.recentMessagesEnabled,
            localHistoryEnabled: envelope.preferences.localHistoryEnabled,
            localHistoryLimit: envelope.preferences.localHistoryLimit,
            retentionDays: envelope.preferences.retentionDays,
            maxDatabaseSizeMB: envelope.preferences.maxDatabaseSizeMB
        )
    }

    @discardableResult
    func save(_ preferences: ChatHistoryPreferences) -> ChatHistoryPreferences {
        let normalized = ChatHistoryPreferences(
            recentMessagesEnabled: preferences.recentMessagesEnabled,
            localHistoryEnabled: preferences.localHistoryEnabled,
            localHistoryLimit: preferences.localHistoryLimit,
            retentionDays: preferences.retentionDays,
            maxDatabaseSizeMB: preferences.maxDatabaseSizeMB
        )
        let envelope = Envelope(
            version: Self.currentVersion,
            preferences: normalized
        )
        if let data = try? JSONEncoder().encode(envelope) {
            defaults.set(data, forKey: Self.storageKey)
        }
        return normalized
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
