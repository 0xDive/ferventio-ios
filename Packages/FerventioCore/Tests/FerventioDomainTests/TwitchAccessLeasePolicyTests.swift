import Testing
@testable import FerventioDomain

struct TwitchAccessLeasePolicyTests {
    @Test
    func shortLeaseCanBeReusedOutsideSafetyWindow() {
        let now: Int64 = 1_000_000
        let lease = makeLease(
            leaseExpiresAt: now + 10_000,
            twitchExpiresAt: now + 120_000,
            validatedAt: now
        )

        #expect(TwitchAccessLeasePolicy.canReuseWithoutBackendCall(lease, nowEpochMilliseconds: now))
    }

    @Test
    func shortLeaseIsNotReusedInsideSafetyWindow() {
        let now: Int64 = 1_000_000
        let lease = makeLease(
            leaseExpiresAt: now + 5_000,
            twitchExpiresAt: now + 120_000,
            validatedAt: now
        )

        #expect(!TwitchAccessLeasePolicy.canReuseWithoutBackendCall(lease, nowEpochMilliseconds: now))
    }

    @Test
    func startupRequiresRecentTwitchValidation() {
        let now: Int64 = 10_000_000
        let lease = makeLease(
            leaseExpiresAt: now + 60_000,
            twitchExpiresAt: now + 120_000,
            validatedAt: now - 5_001
        )

        #expect(TwitchAccessLeasePolicy.needsDirectValidationAtStartup(lease, nowEpochMilliseconds: now))
    }

    private func makeLease(
        leaseExpiresAt: Int64,
        twitchExpiresAt: Int64,
        validatedAt: Int64
    ) -> TwitchAccessLease {
        TwitchAccessLease(
            accessToken: "token",
            leaseExpiresAtEpochMilliseconds: leaseExpiresAt,
            twitchExpiresAtEpochMilliseconds: twitchExpiresAt,
            twitchValidatedAtEpochMilliseconds: validatedAt,
            backendSessionExpiresAtEpochMilliseconds: twitchExpiresAt + 60_000,
            session: TwitchSession(
                clientID: "client",
                userID: "user",
                login: "login",
                scopes: ["user:read:chat"],
                expiresInSeconds: 120
            )
        )
    }
}
