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
    @ObservationIgnored private var registrationGeneration: UInt64 = 0
    @ObservationIgnored private var pendingRegistration: PendingRegistration?
    @ObservationIgnored private var registrationLoopRunning = false
    @ObservationIgnored private var registrationCleanupRunning = false
    @ObservationIgnored private var acceptsRegistrationCallbacks = false

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
            acceptsRegistrationCallbacks = false
            return
        }
        let requestGeneration = registrationGeneration
        let status = await authorizationService.authorizationStatus()
        guard registrationGeneration == requestGeneration else {
            return
        }
        switch status {
        case .authorized, .provisional, .ephemeral:
            acceptsRegistrationCallbacks = true
            authorizationService.registerForRemoteNotifications()
        case .denied:
            acceptsRegistrationCallbacks = false
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
            acceptsRegistrationCallbacks = false
            // Never trigger the system permission prompt during passive app restore.
            break
        @unknown default:
            acceptsRegistrationCallbacks = false
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
        let requestGeneration = registrationGeneration
        isWorking = true
        errorMessage = nil
        selfTestSucceeded = nil
        defer { isWorking = false }

        do {
            let granted = try await authorizationService.requestAuthorization()
            guard registrationGeneration == requestGeneration else {
                return false
            }
            guard granted else {
                acceptsRegistrationCallbacks = false
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
            acceptsRegistrationCallbacks = true
            authorizationService.registerForRemoteNotifications()
            return true
        } catch {
            guard registrationGeneration == requestGeneration else {
                return false
            }
            acceptsRegistrationCallbacks = false
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

        acceptsRegistrationCallbacks = false
        registrationGeneration &+= 1
        pendingRegistration = nil
        registrationCleanupRunning = true
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
        pendingRegistration = nil
        registrationCleanupRunning = false
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
        guard preferences.enabled, acceptsRegistrationCallbacks else {
            return
        }
        await refreshRegistration(grant: grant, channelLogins: channelLogins)
    }

    func receiveDeviceToken(
        _ deviceToken: Data,
        grant: AuthenticationGrant?,
        channelLogins: [String]
    ) async {
        guard preferences.enabled, acceptsRegistrationCallbacks else {
            return
        }
        lastDeviceToken = deviceToken
        await refreshRegistration(grant: grant, channelLogins: channelLogins)
    }

    func workspaceChannelsChanged(
        grant: AuthenticationGrant?,
        channelLogins: [String]
    ) async {
        guard preferences.enabled,
              acceptsRegistrationCallbacks,
              lastDeviceToken != nil else {
            return
        }
        await refreshRegistration(grant: grant, channelLogins: channelLogins)
    }

    func registrationFailed(_ error: any Error) {
        guard acceptsRegistrationCallbacks else {
            return
        }
        isTransportRegistered = false
        errorMessage = error.localizedDescription
    }

    @discardableResult
    func sendSelfTest() async -> Bool {
        guard preferences.enabled, isTransportRegistered, !isWorking else {
            selfTestSucceeded = false
            return false
        }
        let requestGeneration = registrationGeneration
        isWorking = true
        errorMessage = nil
        selfTestSucceeded = nil
        defer { isWorking = false }

        do {
            try await registrationService.selfTest()
            guard registrationGeneration == requestGeneration else {
                return false
            }
            selfTestSucceeded = true
            return true
        } catch {
            guard registrationGeneration == requestGeneration else {
                return false
            }
            errorMessage = error.localizedDescription
            selfTestSucceeded = false
            return false
        }
    }

    func signedOut() async {
        acceptsRegistrationCallbacks = false
        registrationGeneration &+= 1
        pendingRegistration = nil
        registrationCleanupRunning = true
        if preferences.enabled {
            try? await registrationService.unregister()
        }
        pendingRegistration = nil
        registrationCleanupRunning = false
        authorizationService.unregisterForRemoteNotifications()
        lastDeviceToken = nil
        isTransportRegistered = false
        errorMessage = nil
        selfTestSucceeded = nil
        PushNotificationRouteBuffer.shared.clear()
    }

    private func refreshRegistration(
        grant: AuthenticationGrant?,
        channelLogins: [String]
    ) async {
        guard acceptsRegistrationCallbacks,
              let grant,
              let lastDeviceToken else {
            if grant == nil && acceptsRegistrationCallbacks {
                errorMessage = localized("error.not_authenticated")
            }
            return
        }

        pendingRegistration = PendingRegistration(
            generation: registrationGeneration,
            deviceToken: lastDeviceToken,
            channelLogins: channelLogins,
            preferences: preferences,
            grant: grant
        )
        guard !registrationLoopRunning, !registrationCleanupRunning else {
            return
        }

        registrationLoopRunning = true
        isWorking = true
        errorMessage = nil
        selfTestSucceeded = nil
        defer {
            registrationLoopRunning = false
            isWorking = false
        }

        while acceptsRegistrationCallbacks && !registrationCleanupRunning {
            guard let request = pendingRegistration else {
                break
            }
            pendingRegistration = nil
            guard request.generation == registrationGeneration else {
                continue
            }
            errorMessage = nil

            do {
                try await registrationService.register(
                    deviceToken: request.deviceToken,
                    channelLogins: request.channelLogins,
                    preferences: request.preferences,
                    grant: request.grant
                )
                guard acceptsRegistrationCallbacks,
                      request.generation == registrationGeneration else {
                    // A logout or disable can race with an in-flight backend register.
                    // Remove the stale registration before allowing a newer request to run.
                    try? await registrationService.unregister()
                    continue
                }
                isTransportRegistered = true
            } catch {
                guard acceptsRegistrationCallbacks,
                      request.generation == registrationGeneration else {
                    continue
                }
                isTransportRegistered = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "PushNotifications")
    }
}

private struct PendingRegistration: Sendable {
    let generation: UInt64
    let deviceToken: Data
    let channelLogins: [String]
    let preferences: PushNotificationPreferences
    let grant: AuthenticationGrant
}
