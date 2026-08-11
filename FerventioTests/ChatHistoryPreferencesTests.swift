import Foundation
import Testing
@testable import Ferventio

@MainActor
struct ChatHistoryPreferencesTests {
    @Test
    func defaultsMatchAndroidHistoryBehavior() {
        let preferences = ChatHistoryPreferences.default

        #expect(preferences.recentMessagesEnabled)
        #expect(preferences.localHistoryEnabled)
        #expect(preferences.localHistoryLimit == 500)
        #expect(preferences.retentionDays == 7)
        #expect(preferences.maxDatabaseSizeMB == 0)
        #expect(preferences.initialRestoreLimit == 500)
    }

    @Test
    func clampsPortableSettingsRanges() {
        let low = ChatHistoryPreferences(
            recentMessagesEnabled: false,
            localHistoryEnabled: false,
            localHistoryLimit: -1,
            retentionDays: -5,
            maxDatabaseSizeMB: -10
        )
        let high = ChatHistoryPreferences(
            recentMessagesEnabled: true,
            localHistoryEnabled: true,
            localHistoryLimit: 99_999,
            retentionDays: 99_999,
            maxDatabaseSizeMB: 99_999
        )

        #expect(low.localHistoryLimit == 100)
        #expect(low.retentionDays == 0)
        #expect(low.maxDatabaseSizeMB == 0)
        #expect(high.localHistoryLimit == 5_000)
        #expect(high.retentionDays == 365)
        #expect(high.maxDatabaseSizeMB == 1_024)
        #expect(high.initialRestoreLimit == 500)
    }

    @Test
    func zeroRetentionMeansUnlimitedAge() {
        let preferences = ChatHistoryPreferences(
            recentMessagesEnabled: true,
            localHistoryEnabled: true,
            localHistoryLimit: 500,
            retentionDays: 0,
            maxDatabaseSizeMB: 0
        )

        #expect(preferences.retentionBoundaryMilliseconds(nowMilliseconds: 1_000_000) == nil)
    }

    @Test
    func computesPositiveRetentionBoundary() {
        let preferences = ChatHistoryPreferences(
            recentMessagesEnabled: true,
            localHistoryEnabled: true,
            localHistoryLimit: 500,
            retentionDays: 1,
            maxDatabaseSizeMB: 0
        )
        let oneDay: Int64 = 24 * 60 * 60 * 1_000

        #expect(
            preferences.retentionBoundaryMilliseconds(nowMilliseconds: oneDay + 123)
                == 123
        )
    }

    @Test
    func roundTripsVersionedUserDefaultsPayload() throws {
        let suiteName = "ChatHistoryPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ChatHistoryPreferencesStore(defaults: defaults)
        let expected = ChatHistoryPreferences(
            recentMessagesEnabled: false,
            localHistoryEnabled: true,
            localHistoryLimit: 1_234,
            retentionDays: 30,
            maxDatabaseSizeMB: 256
        )

        store.save(expected)

        #expect(store.load() == expected)
    }
}
