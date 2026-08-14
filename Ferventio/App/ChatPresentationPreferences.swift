import Foundation
import FerventioDomain

struct ChatPresentationPreferences: Equatable, Sendable {
    static let `default` = ChatPresentationPreferences(
        repeatCollapseEnabled: true,
        rules: []
    )

    let repeatCollapseEnabled: Bool
    let rules: [ChatPresentationRule]

    init(
        repeatCollapseEnabled: Bool,
        rules: [ChatPresentationRule] = []
    ) {
        self.repeatCollapseEnabled = repeatCollapseEnabled
        self.rules = rules
    }
}

@MainActor
final class ChatPresentationPreferencesStore {
    private struct RulesEnvelope: Codable {
        let version: Int
        let rules: [ChatPresentationRule]
    }

    static let repeatCollapseStorageKey = "repeat_collapse_enabled"
    static let rulesStorageKey = "chat_presentation_rules_v1"
    static let currentRulesVersion = 1
    static let maximumRules = 100

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ChatPresentationPreferences {
        let repeatCollapseEnabled: Bool
        if defaults.object(forKey: Self.repeatCollapseStorageKey) == nil {
            repeatCollapseEnabled = ChatPresentationPreferences.default.repeatCollapseEnabled
        } else {
            repeatCollapseEnabled = defaults.bool(forKey: Self.repeatCollapseStorageKey)
        }

        return ChatPresentationPreferences(
            repeatCollapseEnabled: repeatCollapseEnabled,
            rules: loadRules()
        )
    }

    @discardableResult
    func save(_ preferences: ChatPresentationPreferences) -> ChatPresentationPreferences {
        let normalized = ChatPresentationPreferences(
            repeatCollapseEnabled: preferences.repeatCollapseEnabled,
            rules: Array(preferences.rules.prefix(Self.maximumRules))
        )

        defaults.set(
            normalized.repeatCollapseEnabled,
            forKey: Self.repeatCollapseStorageKey
        )
        let envelope = RulesEnvelope(
            version: Self.currentRulesVersion,
            rules: normalized.rules
        )
        if let data = try? JSONEncoder().encode(envelope) {
            defaults.set(data, forKey: Self.rulesStorageKey)
        }
        return normalized
    }

    private func loadRules() -> [ChatPresentationRule] {
        guard let data = defaults.data(forKey: Self.rulesStorageKey),
              let envelope = try? JSONDecoder().decode(RulesEnvelope.self, from: data),
              envelope.version == Self.currentRulesVersion else {
            return []
        }
        return Array(envelope.rules.prefix(Self.maximumRules))
    }
}
