import Testing
@testable import FerventioDomain

struct TwitchAccessLeaseValidationTests {
    @Test
    func directValidationRefreshesTwitchDeadlineWithoutChangingLeaseDeadline() throws {
        let cached = makeLease(
            session: makeSession(expiresInSeconds: 10),
            leaseExpiresAt: 50_000,
            twitchExpiresAt: 100_000,
            validatedAt: 1_000
        )
        let validated = makeSession(expiresInSeconds: 120)

        let updated = try TwitchAccessLeaseValidation.updateAfterDirectValidation(
            cachedLease: cached,
            validatedSession: validated,
            requiredScopes: ["user:read:chat"],
            nowEpochMilliseconds: 10_000
        )

        #expect(updated.leaseExpiresAtEpochMilliseconds == 50_000)
        #expect(updated.twitchExpiresAtEpochMilliseconds == 130_000)
        #expect(updated.twitchValidatedAtEpochMilliseconds == 10_000)
        #expect(updated.session == cached.session)
    }

    @Test
    func rejectsDifferentUser() {
        let cached = makeLease(session: makeSession(userID: "user-a"))
        let validated = makeSession(userID: "user-b")

        #expect(throws: TwitchAccessLeaseValidation.Error.userIDMismatch) {
            try TwitchAccessLeaseValidation.updateAfterDirectValidation(
                cachedLease: cached,
                validatedSession: validated,
                requiredScopes: ["user:read:chat"],
                nowEpochMilliseconds: 10_000
            )
        }
    }

    @Test
    func rejectsScopeDowngrade() {
        let cached = makeLease(session: makeSession())
        let validated = makeSession(scopes: [])

        #expect(throws: TwitchAccessLeaseValidation.Error.missingScopes(["user:read:chat"])) {
            try TwitchAccessLeaseValidation.updateAfterDirectValidation(
                cachedLease: cached,
                validatedSession: validated,
                requiredScopes: ["user:read:chat"],
                nowEpochMilliseconds: 10_000
            )
        }
    }

    @Test
    func changedTransportIdentityReplacesValidationSnapshot() throws {
        let cached = makeLease(session: makeSession(login: "old-login", expiresInSeconds: 10))
        let validated = makeSession(login: "new-login", expiresInSeconds: 120)

        let updated = try TwitchAccessLeaseValidation.updateAfterDirectValidation(
            cachedLease: cached,
            validatedSession: validated,
            requiredScopes: ["user:read:chat"],
            nowEpochMilliseconds: 10_000
        )

        #expect(updated.session == validated)
    }

    private func makeLease(
        session: TwitchSession,
        leaseExpiresAt: Int64 = 50_000,
        twitchExpiresAt: Int64 = 100_000,
        validatedAt: Int64 = 1_000
    ) -> TwitchAccessLease {
        TwitchAccessLease(
            accessToken: "access-token",
            leaseExpiresAtEpochMilliseconds: leaseExpiresAt,
            twitchExpiresAtEpochMilliseconds: twitchExpiresAt,
            twitchValidatedAtEpochMilliseconds: validatedAt,
            backendSessionExpiresAtEpochMilliseconds: 200_000,
            session: session
        )
    }

    private func makeSession(
        userID: String = "user-a",
        login: String = "tester",
        scopes: Set<String> = ["user:read:chat"],
        expiresInSeconds: Int64 = 120
    ) -> TwitchSession {
        TwitchSession(
            clientID: "client-id",
            userID: userID,
            login: login,
            scopes: scopes,
            expiresInSeconds: expiresInSeconds
        )
    }
}
