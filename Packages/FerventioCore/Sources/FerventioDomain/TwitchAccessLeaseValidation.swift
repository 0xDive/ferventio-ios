import Foundation

public enum TwitchAccessLeaseValidation {
    public enum Error: Swift.Error, Equatable {
        case clientIDMismatch
        case userIDMismatch
        case missingScopes(Set<String>)
        case expiredAccessToken
        case expirationOverflow
    }

    public static func updateAfterDirectValidation(
        cachedLease: TwitchAccessLease,
        validatedSession: TwitchSession,
        requiredScopes: some Collection<String>,
        nowEpochMilliseconds: Int64
    ) throws -> TwitchAccessLease {
        guard validatedSession.clientID == cachedLease.session.clientID else {
            throw Error.clientIDMismatch
        }
        guard validatedSession.userID == cachedLease.session.userID else {
            throw Error.userIDMismatch
        }

        let required = Set(requiredScopes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let missingScopes = required.subtracting(validatedSession.scopes)
        guard missingScopes.isEmpty else {
            throw Error.missingScopes(missingScopes)
        }
        guard validatedSession.expiresInSeconds > 0 else {
            throw Error.expiredAccessToken
        }

        let (remainingMilliseconds, multiplyOverflow) = validatedSession.expiresInSeconds.multipliedReportingOverflow(by: 1_000)
        guard !multiplyOverflow else {
            throw Error.expirationOverflow
        }
        let (validatedExpiry, addOverflow) = nowEpochMilliseconds.addingReportingOverflow(remainingMilliseconds)
        guard !addOverflow else {
            throw Error.expirationOverflow
        }

        let stableSession: TwitchSession
        if sameTransportIdentity(cachedLease.session, validatedSession) {
            stableSession = cachedLease.session
        } else {
            stableSession = validatedSession
        }

        return TwitchAccessLease(
            accessToken: cachedLease.accessToken,
            leaseExpiresAtEpochMilliseconds: cachedLease.leaseExpiresAtEpochMilliseconds,
            twitchExpiresAtEpochMilliseconds: validatedExpiry,
            twitchValidatedAtEpochMilliseconds: nowEpochMilliseconds,
            backendSessionExpiresAtEpochMilliseconds: cachedLease.backendSessionExpiresAtEpochMilliseconds,
            session: stableSession
        )
    }

    private static func sameTransportIdentity(_ left: TwitchSession, _ right: TwitchSession) -> Bool {
        left.clientID == right.clientID
            && left.userID == right.userID
            && left.login == right.login
            && left.scopes == right.scopes
    }
}
