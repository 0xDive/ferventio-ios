import FerventioDomain
import Testing
@testable import Ferventio

@MainActor
struct AppEnvironmentTests {
    @Test
    func startMovesApplicationToSignedOutStateWithoutStoredSession() async {
        let service = StubAuthService(restoreResult: nil)
        let environment = AppEnvironment(authService: service)

        await environment.start()

        #expect(environment.state == .signedOut)
        #expect(environment.session == nil)
    }

    @Test
    func signInPublishesTwitchSession() async {
        let grant = makeGrant()
        let service = StubAuthService(restoreResult: nil, signInResult: grant)
        let environment = AppEnvironment(authService: service)
        await environment.start()

        await environment.signIn()

        #expect(environment.state == .signedIn)
        #expect(environment.session == grant.accessLease.session)
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
private final class StubAuthService: Authenticating {
    let restoreResult: AuthenticationGrant?
    let signInResult: AuthenticationGrant

    init(
        restoreResult: AuthenticationGrant?,
        signInResult: AuthenticationGrant? = nil
    ) {
        self.restoreResult = restoreResult
        self.signInResult = signInResult ?? AuthenticationGrant(
            backendCredential: BackendSessionCredential(
                serverURL: "https://ferventio.godive.dev",
                token: "session",
                expiresAtEpochMilliseconds: 1
            ),
            accessLease: TwitchAccessLease(
                accessToken: "access",
                leaseExpiresAtEpochMilliseconds: 1,
                twitchExpiresAtEpochMilliseconds: 1,
                twitchValidatedAtEpochMilliseconds: 1,
                backendSessionExpiresAtEpochMilliseconds: 1,
                session: TwitchSession(
                    clientID: "client",
                    userID: "user",
                    login: "tester",
                    scopes: [],
                    expiresInSeconds: 0
                )
            )
        )
    }

    func restoreAuthentication() async throws -> AuthenticationGrant? {
        restoreResult
    }

    func signIn() async throws -> AuthenticationGrant {
        signInResult
    }

    func signOut() async throws {}
}
