import Foundation
import FerventioDomain
import Testing
import UserNotifications
@testable import Ferventio

@MainActor
struct PushNotificationAsyncCompletionTests {
    @Test
    func restoreCompletionAfterSignOutDoesNotReenableRegistrationCallbacks() async {
        let fixture = makeFixture(blockAuthorizationStatus: true)
        let grant = makeGrant()

        let restoreTask = Task { @MainActor in
            await fixture.coordinator.restoreIfNeeded(
                grant: grant,
                channelLogins: ["channel"]
            )
        }
        await fixture.authorizationService.waitUntilStatusRequestStarts()

        await fixture.coordinator.signedOut()
        fixture.authorizationService.completeStatus(.authorized)
        await restoreTask.value

        await fixture.coordinator.receiveDeviceToken(
            Data([0x01]),
            grant: grant,
            channelLogins: ["channel"]
        )

        #expect(await fixture.registrationService.registrationCount() == 0)
        #expect(!fixture.coordinator.isTransportRegistered)
        fixture.cleanup()
    }

    @Test
    func selfTestCompletionAfterSignOutCannotRestoreOldSessionStatus() async {
        let fixture = makeFixture(blockAuthorizationStatus: false)
        let grant = makeGrant()

        await fixture.coordinator.restoreIfNeeded(
            grant: grant,
            channelLogins: ["channel"]
        )
        await fixture.coordinator.receiveDeviceToken(
            Data([0x01]),
            grant: grant,
            channelLogins: ["channel"]
        )
        #expect(fixture.coordinator.isTransportRegistered)

        let selfTestTask = Task { @MainActor in
            await fixture.coordinator.sendSelfTest()
        }
        await fixture.registrationService.waitUntilSelfTestStarts()

        await fixture.coordinator.signedOut()
        await fixture.registrationService.completeSelfTest()
        let result = await selfTestTask.value

        #expect(!result)
        #expect(fixture.coordinator.selfTestSucceeded == nil)
        #expect(fixture.coordinator.errorMessage == nil)
        #expect(!fixture.coordinator.isTransportRegistered)
        #expect(!fixture.coordinator.isWorking)
        fixture.cleanup()
    }

    private func makeFixture(
        blockAuthorizationStatus: Bool
    ) -> PushAsyncCompletionFixture {
        let suiteName = "PushNotificationAsyncCompletionTests.\(UUID().uuidString)"
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
        let registrationService = AsyncCompletionPushRegistrationService()
        let authorizationService = AsyncCompletionAuthorizationService(
            blockStatus: blockAuthorizationStatus
        )
        let coordinator = PushNotificationCoordinator(
            preferencesStore: preferencesStore,
            registrationService: registrationService,
            authorizationService: authorizationService
        )
        return PushAsyncCompletionFixture(
            coordinator: coordinator,
            registrationService: registrationService,
            authorizationService: authorizationService,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private func makeGrant() -> AuthenticationGrant {
        AuthenticationGrant(
            backendCredential: BackendSessionCredential(
                serverURL: "https://ferventio.godive.dev",
                token: "session",
                expiresAtEpochMilliseconds: 200_000
            ),
            accessLease: TwitchAccessLease(
                accessToken: "access",
                leaseExpiresAtEpochMilliseconds: 100_000,
                twitchExpiresAtEpochMilliseconds: 150_000,
                twitchValidatedAtEpochMilliseconds: 90_000,
                backendSessionExpiresAtEpochMilliseconds: 200_000,
                session: TwitchSession(
                    clientID: "client",
                    userID: "user",
                    login: "tester",
                    scopes: ["user:read:chat"],
                    expiresInSeconds: 150
                )
            )
        )
    }
}

@MainActor
private struct PushAsyncCompletionFixture {
    let coordinator: PushNotificationCoordinator
    let registrationService: AsyncCompletionPushRegistrationService
    let authorizationService: AsyncCompletionAuthorizationService
    let defaults: UserDefaults
    let suiteName: String

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private actor AsyncCompletionPushRegistrationService: PushRegistering {
    private var registrations = 0
    private var selfTestStarted = false
    private var selfTestWaiters: [CheckedContinuation<Void, Never>] = []
    private var selfTestContinuation: CheckedContinuation<Void, Never>?

    func register(
        deviceToken: Data,
        channelLogins: [String],
        preferences: PushNotificationPreferences,
        grant: AuthenticationGrant
    ) async throws {
        registrations += 1
    }

    func unregister() async throws {}

    func selfTest() async throws {
        await withCheckedContinuation { continuation in
            selfTestContinuation = continuation
            selfTestStarted = true
            let waiters = selfTestWaiters
            selfTestWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func registrationCount() -> Int {
        registrations
    }

    func waitUntilSelfTestStarts() async {
        guard !selfTestStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            selfTestWaiters.append(continuation)
        }
    }

    func completeSelfTest() {
        selfTestContinuation?.resume()
        selfTestContinuation = nil
    }
}

@MainActor
private final class AsyncCompletionAuthorizationService: PushNotificationAuthorizing {
    private let blockStatus: Bool
    private var statusRequestStarted = false
    private var statusRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private var statusContinuation: CheckedContinuation<UNAuthorizationStatus, Never>?

    init(blockStatus: Bool) {
        self.blockStatus = blockStatus
    }

    func requestAuthorization() async throws -> Bool {
        true
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        guard blockStatus else {
            return .authorized
        }
        return await withCheckedContinuation { continuation in
            statusContinuation = continuation
            statusRequestStarted = true
            let waiters = statusRequestWaiters
            statusRequestWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func registerForRemoteNotifications() {}

    func unregisterForRemoteNotifications() {}

    func waitUntilStatusRequestStarts() async {
        guard !statusRequestStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            statusRequestWaiters.append(continuation)
        }
    }

    func completeStatus(_ status: UNAuthorizationStatus) {
        statusContinuation?.resume(returning: status)
        statusContinuation = nil
    }
}
