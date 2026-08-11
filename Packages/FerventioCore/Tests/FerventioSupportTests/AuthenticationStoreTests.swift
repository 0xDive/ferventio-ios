import FerventioDomain
import Foundation
import Testing
@testable import FerventioSupport

struct AuthenticationStoreTests {
    @Test
    func roundTripsVersionedAuthenticationPayload() throws {
        let secureStore = InMemorySecureStore()
        let store = AuthenticationStore(store: secureStore)
        let authentication = makeAuthentication()

        try store.save(authentication)

        #expect(try store.load() == authentication)
    }

    @Test
    func rejectsLeaseFromDifferentBackendSession() {
        let secureStore = InMemorySecureStore()
        let store = AuthenticationStore(store: secureStore)
        let authentication = makeAuthentication(leaseSessionExpiry: 99_000)

        #expect(throws: AuthenticationStore.Error.invalidPayload) {
            try store.save(authentication)
        }
    }

    private func makeAuthentication(leaseSessionExpiry: Int64 = 100_000) -> StoredAuthentication {
        StoredAuthentication(
            backendCredential: BackendSessionCredential(
                serverURL: "https://ferventio.godive.dev",
                token: "backend-session",
                expiresAtEpochMilliseconds: 100_000
            ),
            accessLease: TwitchAccessLease(
                accessToken: "twitch-access",
                leaseExpiresAtEpochMilliseconds: 50_000,
                twitchExpiresAtEpochMilliseconds: 80_000,
                twitchValidatedAtEpochMilliseconds: 40_000,
                backendSessionExpiresAtEpochMilliseconds: leaseSessionExpiry,
                session: TwitchSession(
                    clientID: "client-id",
                    userID: "user-id",
                    login: "user-login",
                    scopes: ["user:read:chat"],
                    expiresInSeconds: 80
                )
            )
        )
    }
}

private final class InMemorySecureStore: SecureKeyValueStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func set(_ value: String, forKey key: String) throws {
        lock.withLock {
            values[key] = value
        }
    }

    func string(forKey key: String) throws -> String? {
        lock.withLock {
            values[key]
        }
    }

    func removeValue(forKey key: String) throws {
        lock.withLock {
            _ = values.removeValue(forKey: key)
        }
    }
}
