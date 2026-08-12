import Foundation
import Testing
@testable import Ferventio

@MainActor
struct ChatPresentationPreferencesTests {
    @Test
    func repeatCollapseDefaultsEnabledLikeAndroid() {
        #expect(ChatPresentationPreferences.default.repeatCollapseEnabled)
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
}
