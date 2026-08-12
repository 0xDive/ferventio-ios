import Foundation

struct ChatPresentationPreferences: Equatable, Sendable {
    static let `default` = ChatPresentationPreferences(
        repeatCollapseEnabled: true
    )

    let repeatCollapseEnabled: Bool
}

@MainActor
final class ChatPresentationPreferencesStore {
    static let repeatCollapseStorageKey = "repeat_collapse_enabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ChatPresentationPreferences {
        guard defaults.object(forKey: Self.repeatCollapseStorageKey) != nil else {
            return .default
        }
        return ChatPresentationPreferences(
            repeatCollapseEnabled: defaults.bool(forKey: Self.repeatCollapseStorageKey)
        )
    }

    @discardableResult
    func save(_ preferences: ChatPresentationPreferences) -> ChatPresentationPreferences {
        defaults.set(
            preferences.repeatCollapseEnabled,
            forKey: Self.repeatCollapseStorageKey
        )
        return preferences
    }
}
