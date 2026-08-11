import Foundation

public enum TwitchAccessLeasePolicy {
    private static let normalSafetyWindowMilliseconds: Int64 = 5_000
    private static let outageSafetyWindowMilliseconds: Int64 = 30_000
    private static let startupValidationTrustWindowMilliseconds: Int64 = 5_000
    private static let directValidationIntervalMilliseconds: Int64 = 55 * 60 * 1_000

    public static func canReuseWithoutBackendCall(
        _ lease: TwitchAccessLease,
        nowEpochMilliseconds: Int64
    ) -> Bool {
        isStructurallyUsable(lease)
            && lease.leaseExpiresAtEpochMilliseconds > nowEpochMilliseconds + normalSafetyWindowMilliseconds
    }

    public static func canUseDuringBackendOutage(
        _ lease: TwitchAccessLease,
        nowEpochMilliseconds: Int64
    ) -> Bool {
        isStructurallyUsable(lease)
            && lease.twitchExpiresAtEpochMilliseconds > nowEpochMilliseconds + outageSafetyWindowMilliseconds
    }

    public static func needsDirectValidationAtStartup(
        _ lease: TwitchAccessLease,
        nowEpochMilliseconds: Int64
    ) -> Bool {
        lease.twitchValidatedAtEpochMilliseconds
            <= nowEpochMilliseconds - startupValidationTrustWindowMilliseconds
    }

    public static func needsDirectValidationDuringOutage(
        _ lease: TwitchAccessLease,
        nowEpochMilliseconds: Int64
    ) -> Bool {
        lease.twitchValidatedAtEpochMilliseconds
            <= nowEpochMilliseconds - directValidationIntervalMilliseconds
    }

    public static func representsSameCachedCredential(
        _ left: TwitchAccessLease,
        _ right: TwitchAccessLease
    ) -> Bool {
        left.accessToken == right.accessToken
            && left.twitchExpiresAtEpochMilliseconds == right.twitchExpiresAtEpochMilliseconds
            && left.twitchValidatedAtEpochMilliseconds == right.twitchValidatedAtEpochMilliseconds
            && left.backendSessionExpiresAtEpochMilliseconds == right.backendSessionExpiresAtEpochMilliseconds
            && left.session.clientID == right.session.clientID
            && left.session.userID == right.session.userID
            && left.session.login == right.session.login
            && left.session.scopes == right.session.scopes
    }

    private static func isStructurallyUsable(_ lease: TwitchAccessLease) -> Bool {
        !lease.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lease.session.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lease.session.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lease.session.login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lease.session.scopes.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            && lease.twitchValidatedAtEpochMilliseconds > 0
    }
}
