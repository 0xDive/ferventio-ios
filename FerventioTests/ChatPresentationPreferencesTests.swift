import Foundation
import FerventioDomain
import Testing
@testable import Ferventio

@MainActor
struct ChatPresentationPreferencesTests {
    @Test
    func repeatCollapseDefaultsEnabledLikeAndroid() {
        #expect(ChatPresentationPreferences.default.repeatCollapseEnabled)
        #expect(ChatPresentationPreferences.default.rules.isEmpty)
    }

    @Test
    func usesAndroidCompatiblePreferenceKeyAndRoundTripsValue() throws {
        let suiteName = "ChatPresentationPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ChatPresentationPreferencesStore(defaults: defaults)

        #expect(ChatPresentationPreferencesStore.repeatCollapseStorageKey == "repeat_collapse_enabled")
        #expect(store.load().repeatCollapseEnabled)

        store.save(ChatPresentationPreferences(repeatCollapseEnabled: false))

        #expect(!store.load().repeatCollapseEnabled)
        #expect(defaults.object(forKey: "repeat_collapse_enabled") != nil)
        #expect(!defaults.bool(forKey: "repeat_collapse_enabled"))
    }

    @Test
    func rulesRoundTripInVersionedStorage() throws {
        let suiteName = "ChatPresentationPreferencesTests.rules.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ChatPresentationPreferencesStore(defaults: defaults)
        let rules = [
            ChatPresentationRule(
                action: .hide,
                target: .message,
                query: "spam"
            ),
            ChatPresentationRule(
                action: .highlight,
                target: .author,
                matchMode: .regex,
                query: "^trusted_",
                caseSensitive: true
            ),
        ]

        let saved = store.save(
            ChatPresentationPreferences(
                repeatCollapseEnabled: true,
                rules: rules
            )
        )
        let loaded = store.load()

        #expect(saved.rules == rules)
        #expect(loaded.rules == rules)
        #expect(defaults.data(forKey: ChatPresentationPreferencesStore.rulesStorageKey) != nil)
    }

    @Test
    func storageBoundsRuleCountWithoutChangingOrder() throws {
        let suiteName = "ChatPresentationPreferencesTests.bound.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ChatPresentationPreferencesStore(defaults: defaults)
        let rules = (0..<(ChatPresentationPreferencesStore.maximumRules + 5)).map { index in
            ChatPresentationRule(
                action: .highlight,
                target: .message,
                query: "rule-\(index)"
            )
        }

        let saved = store.save(
            ChatPresentationPreferences(
                repeatCollapseEnabled: true,
                rules: rules
            )
        )

        #expect(saved.rules.count == ChatPresentationPreferencesStore.maximumRules)
        #expect(saved.rules.map(\.id) == Array(rules.prefix(ChatPresentationPreferencesStore.maximumRules)).map(\.id))
        #expect(store.load().rules == saved.rules)
    }

    @Test
    func corruptOrFutureRuleSnapshotFallsBackToEmptyRules() throws {
        let suiteName = "ChatPresentationPreferencesTests.corrupt.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ChatPresentationPreferencesStore(defaults: defaults)

        defaults.set(Data("not-json".utf8), forKey: ChatPresentationPreferencesStore.rulesStorageKey)
        #expect(store.load().rules.isEmpty)

        let futureEnvelope = Data(#"{"version":999,"rules":[]}"#.utf8)
        defaults.set(futureEnvelope, forKey: ChatPresentationPreferencesStore.rulesStorageKey)
        #expect(store.load().rules.isEmpty)
    }
}
