import Foundation
import FerventioDomain
import Testing
import UserNotifications
@testable import Ferventio

@MainActor
struct PushNotificationCoordinatorTests {
    @Test
    func signedOutRemovesRegistrationThatCompletesAfterLogout() async {
        let fixture = makeFixture()
        let grant = makeGrant(userID: "old-user", token: "old-session")

        let registrationTask = Task { @MainActor in
            await fixture.coordinator.receiveDeviceToken(
                Data([0x01]),
                grant: grant,
                channelLogins: ["old-channel"]
            )
        }
        await fixture.registrationService.waitUntilFirstRegisterStarts()

        await fixture.coordinator.signedOut()
        #expect(await fixture.registrationService.unregisterCallCount() == 1)

        await fixture.registrationService.completeFirstRegister()
        await registrationTask.value

        #expect(await fixture.registrationService.unregisterCallCount() == 2)
        #expect(!fixture.coordinator.isTransportRegistered)
        #expect(!fixture.coordinator.isWorking)
        fixture.cleanup()
    }

    @Test
    func newSessionRegistrationRunsAfterStaleLogoutRegistrationIsRemoved() async {
        let fixture = makeFixture()
        let oldGrant = makeGrant(userID: "old-user", token: "old-session")
        let newGrant = makeGrant(userID: "new-user", token: "new-session")

        let oldRegistrationTask = Task { @MainActor in
            await fixture.coordinator.receiveDeviceToken(
                Data([0x01]),
                grant: oldGrant,
                channelLogins: ["old-channel"]
            )
        }
        await fixture.registrationService.waitUntilFirstRegisterStarts()
        await fixture.coordinator.signedOut()

        await fixture.coordinator.receiveDeviceToken(
            Data([0x02]),
            grant: newGrant,
            channelLogins: ["new-channel"]
        )
        await fixture.registrationService.completeFirstRegister()
        await oldRegistrationTask.value

        let registrations = await fixture.registrationService.registrationCalls()
        #expect(registrations.count == 2)
        #expect(registrations[0].userID == "old-user")
        #expect(registrations[0].deviceToken == Data([0x01]))
        #expect(registrations[1].userID == "new-user")
        #expect(registrations[1].deviceToken == Data([0x02]))
        #expect(registrations[1].channelLogins == ["new-channel"])
        #expect(await fixture.registrationService.unregisterCallCount() == 2)
        #expect(fixture.coordinator.isTransportRegistered)
        #expect(!fixture.coordinator.isWorking)
        fixture.cleanup()
    }

    @Test
    func newerDeviceTokenIsReplayedAfterInFlightRegistration() async {
        let fixture = makeFixture()
        let grant = makeGrant(userID: "user", token: "session")

        let firstRegistrationTask = Task { @MainActor in
            await fixture.coordinator.receiveDeviceToken(
                Data([0x01]),
                grant: grant,
                channelLogins: ["channel"]
            )
        }
        await fixture.registrationService.waitUntilFirstRegisterStarts()

        await fixture.coordinator.receiveDeviceToken(
            Data([0x02]),
            grant: grant,
            channelLogins: ["channel"]
        )
        await fixture.registrationService.completeFirstRegister()
        await firstRegistrationTask.value

        let registrations = await fixture.registrationService.registrationCalls()
        #expect(registrations.map(\.deviceToken) == [Data([0x01]), Data([0x02])])
        #expect(await fixture.registrationService.unregisterCallCount() == 0)
        #expect(fixture.coordinator.isTransportRegistered)
        #expect(!fixture.coordinator.isWorking)
        fixture.cleanup()
    }

    private func makeFixture() -> PushCoordinatorFixture {
        let suiteName = "PushNotificationCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let preferencesStore = PushNotificationPreferencesStore(defaults: defaults)
        preferencesStore.save(
            PushNotificationPreferences(
                enabled: true,
                repliesAndMentions: true,
                moderation: false,
                channelActivity: false
            )
        )
        let registrationService = BlockingPushRegistrationService()
        let authorizationService = StubPushNotificationAuthorizationService()
        let coordinator = PushNotificationCoordinator(
            preferencesStore: preferencesStore,
            registrationService: registrationService,
            authorizationService: authorizationService
        )
        return PushCoordinatorFixture(
            coordinator: coordinator,
            registrationService: registrationService,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private func makeGrant(userID: String, token: String) -> AuthenticationGrant {
        AuthenticationGrant(
            backendCredential: BackendSessionCredential(
                serverURL: "https://ferventio.godive.dev",
                token: token,
                expiresAtEpochMilliseconds: 200_000
            ),
            accessLease: TwitchAccessLease(
                accessToken: "access-\(userID)",
                leaseExpiresAtEpochMilliseconds: 100_000,
                twitchExpiresAtEpochMilliseconds: 150_000,
                twitchValidatedAtEpochMilliseconds: 90_000,
                backendSessionExpiresAtEpochMilliseconds: 200_000,
                session: TwitchSession(
                    clientID: "client",
                    userID: userID,
                    login: userID,
                    scopes: ["user:read:chat"],
                    expiresInSeconds: 150
                )
            )
        )
    }
}

@MainActor
private struct PushCoordinatorFixture {
    let coordinator: PushNotificationCoordinator
    let registrationService: BlockingPushRegistrationService
    let defaults: UserDefaults
    let suiteName: String

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct RecordedPushRegistration: Equatable, Sendable {
    let deviceToken: Data
    let channelLogins: [String]
    let userID: String
}

private actor BlockingPushRegistrationService: PushRegistering {
    private var registrations: [RecordedPushRegistration] = []
    private var unregisterCalls = 0
    private var firstRegisterStarted = false
    private var firstRegisterWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstRegisterContinuation: CheckedContinuation<Void, Never>?

    func register(
        deviceToken: Data,
        channelLogins: [String],
        preferences: PushNotificationPreferences,
        grant: AuthenticationGrant
    ) async throws {
        registrations.append(
            RecordedPushRegistration(
                deviceToken: deviceToken,
                channelLogins: channelLogins,
                userID: grant.accessLease.session.userID
            )
        )
        guard registrations.count == 1 else {
            return
        }

        firstRegisterStarted = true
        let waiters = firstRegisterWaiters
        firstRegisterWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            firstRegisterContinuation = continuation
        }
    }

    func unregister() async throws {
        unregisterCalls += 1
    }

    func selfTest() async throws {}

    func waitUntilFirstRegisterStarts() async {
        guard !firstRegisterStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            firstRegisterWaiters.append(continuation)
        }
    }

    func completeFirstRegister() {
        firstRegisterContinuation?.resume()
        firstRegisterContinuation = nil
    }

    func registrationCalls() -> [RecordedPushRegistration] {
        registrations
    }

    func unregisterCallCount() -> Int {
        unregisterCalls
    }
}

@MainActor
private final class StubPushNotificationAuthorizationService: PushNotificationAuthorizing {
    func requestAuthorization() async throws -> Bool {
        true
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        .authorized
    }

    func registerForRemoteNotifications() {}

    func unregisterForRemoteNotifications() {}
}
