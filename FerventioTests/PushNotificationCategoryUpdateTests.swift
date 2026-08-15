import FerventioDomain
import Testing
import UserNotifications
@testable import Ferventio

@MainActor
struct PushNotificationCategoryUpdateTests {
    @Test
    func rapidCategoryUpdatesPreserveEverySynchronousChange() {
        let suiteName = "PushNotificationCategoryUpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferencesStore = PushNotificationPreferencesStore(defaults: defaults)
        preferencesStore.save(
            PushNotificationPreferences(
                enabled: true,
                repliesAndMentions: false,
                moderation: false,
                channelActivity: false
            )
        )
        let coordinator = PushNotificationCoordinator(
            preferencesStore: preferencesStore,
            registrationService: NoopPushRegistrationService(),
            authorizationService: NoopPushNotificationAuthorizationService()
        )

        coordinator.updateCategory(
            .repliesAndMentions,
            enabled: true,
            grant: nil,
            channelLogins: []
        )
        coordinator.updateCategory(
            .moderation,
            enabled: true,
            grant: nil,
            channelLogins: []
        )
        coordinator.updateCategory(
            .channelActivity,
            enabled: true,
            grant: nil,
            channelLogins: []
        )

        #expect(coordinator.preferences.repliesAndMentions)
        #expect(coordinator.preferences.moderation)
        #expect(coordinator.preferences.channelActivity)

        let persisted = preferencesStore.load()
        #expect(persisted.repliesAndMentions)
        #expect(persisted.moderation)
        #expect(persisted.channelActivity)
    }
}

private actor NoopPushRegistrationService: PushRegistering {
    func register(
        deviceToken: Data,
        channelLogins: [String],
        preferences: PushNotificationPreferences,
        grant: AuthenticationGrant
    ) async throws {}

    func unregister() async throws {}

    func selfTest() async throws {}
}

@MainActor
private final class NoopPushNotificationAuthorizationService: PushNotificationAuthorizing {
    func requestAuthorization() async throws -> Bool {
        true
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        .authorized
    }

    func registerForRemoteNotifications() {}

    func unregisterForRemoteNotifications() {}
}
