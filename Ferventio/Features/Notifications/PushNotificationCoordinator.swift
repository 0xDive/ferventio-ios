import Foundation
import FerventioDomain
import Observation
import UserNotifications

@MainActor
@Observable
final class PushNotificationCoordinator {
    var preferences: PushNotificationPreferences
    var isTransportRegistered = false
    var isWorking = false
    var errorMessage: String?
    var selfTestSucceeded: Bool?

    @ObservationIgnored private let preferencesStore: PushNotificationPreferencesStore
    @ObservationIgnored private let registrationService: any PushRegistering
    @ObservationIgnored private let authorizationService: any PushNotificationAuthorizing
    @ObservationIgnored private var lastDeviceToken: Data?

    init(
        preferencesStore: PushNotificationPreferencesStore? = nil,
        registrationService: (any PushRegistering)? = nil,
        authorizationService: (any PushNotificationAuthorizing)? = nil
    ) {
        let store = preferencesStore ?? PushNotificationPreferencesStore()
        self.preferencesStore = store
        preferences = store.load()
        self.registrationService = registrationService ?? PushRegistrationService.live()
        self.authorizationService = authorizationService ?? PushNotificationAuthorizationService()
    }

    func restoreIfNeeded(
        grant: AuthenticationGrant?,
        channelLogins: [String]
    ) async {
        guard preferences.enabled, grant != nil else {
            return
        }
        let status = await authorizationService.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            authorizationService.registerForRemoteNotifications()
        case .denied:
            preferences = preferencesStore.save(
                PushNotificationPreferences(
                    enabled: false,
                    repliesAndMentions: preferences.repliesAndMentions,
                    moderation: preferences.moderation,
                    channelActivity: preferences.channelActivity
                )
            )
            isTransportRegistered = false
            errorMessage = localized("permission_denied")
        case .notDetermined:
            // Never trigger the system permission prompt during passive app restore.
            break
        @unknown default:
            break
        }
    }

    @discardableResult
    func enable(
        grant: AuthenticationGrant?,
        channelLogins: [String]
    ) async -> Bool {
        guard grant != nil, !isWorking else {
            errorMessage = localized("error.not_authenticated")
            return false
        }
        isWorking = true
        errorMessage = nil
        selfTestSucceeded = nil
        defer { isWorking = false }

        do {
            let granted = try await authorizationService.requestAuthorization()
            guard granted else {
                preferences = preferencesStore.save(
                    PushNotificationPreferences(
                        enabled: false,
                        repliesAndMentions: preferences.repliesAndMentions,
                        moderation: preferences.moderation,
                        channelActivity: preferences.channelActivity
                    )
                )
                errorMessage = localized("permission_denied")
                return false
            }
            preferences = preferencesStore.save(
                PushNotificationPreferences(
                    enabled: true,
                    repliesAndMentions: preferences.repliesAndMentions,
                    moderation: preferences.moderation,
                    channelActivity: preferences.channelActivity
                )
            )
            authorizationService.registerForRemoteNotifications()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func disable() async {
        guard !isWorking else {
            return
        }
        isWorking = true
        errorMessage = nil
        selfTestSucceeded = nil
        defer { isWorking = false }

        preferences = preferencesStore.save(
            PushNotificationPreferences(
                enabled: false,
                repliesAndMentions: preferences.repliesAndMentions,
                moderation: preferences.moderation,
                channelActivity: preferences.channelActivity
            )
        )
        do {
            try await registrationService.unregister()
        } catch {
            // Disabling local delivery must not be blocked by a temporary backend error.
            errorMessage = error.localizedDescription
        }
        authorizationService.unregisterForRemoteNotifications()
        lastDeviceToken = nil
        isTransportRegistered = false
    }

    func updateCategories(
        repliesAndMentions: Bool,
        moderation: Bool,
        channelActivity: Bool,
        grant: AuthenticationGrant?,
        channelLogins: [String]
    ) async {
        preferences = preferencesStore.save(
            PushNotificationPreferences(
                enabled: preferences.enabled,
                repliesAndMentions: repliesAndMentions,
                moderation: moderation,
                channelActivity: channelActivity
            )
        )
        guard preferences.enabled else {
            return
        }
        await refreshRegistration(grant: grant, channelLogins: channelLogins)
    }

    func receiveDeviceToken(
        _ deviceToken: Data,
        grant: AuthenticationGrant?,
        channelLogins: [String]
    ) async {
        lastDeviceToken = deviceToken
        guard preferences.enabled else {
            return
        }
        await refreshRegistration(grant: grant, channelLogins: channelLogins)
    }

    func workspaceChannelsChanged(
        grant: AuthenticationGrant?,
        channelLogins: [String]
    ) async {
        guard preferences.enabled, lastDeviceToken != nil else {
            return
        }
        await refreshRegistration(grant: grant, channelLogins: channelLogins)
    }

    func registrationFailed(_ error: any Error) {
        isTransportRegistered = false
        errorMessage = error.localizedDescription
    }

    @discardableResult
    func sendSelfTest() async -> Bool {
        guard preferences.enabled, isTransportRegistered, !isWorking else {
            selfTestSucceeded = false
            return false
        }
        isWorking = true
        errorMessage = nil
        selfTestSucceeded = nil
        defer { isWorking = false }

        do {
            try await registrationService.selfTest()
            selfTestSucceeded = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            selfTestSucceeded = false
            return false
        }
    }

    func signedOut() async {
        if preferences.enabled {
            try? await registrationService.unregister()
        }
        authorizationService.unregisterForRemoteNotifications()
        lastDeviceToken = nil
        isTransportRegistered = false
        selfTestSucceeded = nil
    }

    private func refreshRegistration(
        grant: AuthenticationGrant?,
        channelLogins: [String]
    ) async {
        guard let grant, let lastDeviceToken, !isWorking else {
            if grant == nil {
                errorMessage = localized("error.not_authenticated")
            }
            return
        }
        isWorking = true
        errorMessage = nil
        selfTestSucceeded = nil
        defer { isWorking = false }

        do {
            try await registrationService.register(
                deviceToken: lastDeviceToken,
                channelLogins: channelLogins,
                preferences: preferences,
                grant: grant
            )
            isTransportRegistered = true
        } catch {
            isTransportRegistered = false
            errorMessage = error.localizedDescription
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "PushNotifications")
    }
}
