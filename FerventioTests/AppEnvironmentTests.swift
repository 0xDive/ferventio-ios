import FerventioDomain
import Testing
@testable import Ferventio

@MainActor
struct AppEnvironmentTests {
    @Test
    func startMovesApplicationToSignedOutStateWithoutStoredSession() async {
        let service = StubAuthService(restoreResult: nil)
        let environment = AppEnvironment(
            authService: service,
            twitchBootstrap: StubTwitchBootstrap()
        )

        await environment.start()

        #expect(environment.state == .signedOut)
        #expect(environment.session == nil)
        #expect(environment.currentUser == nil)
    }

    @Test
    func signInPublishesTwitchSessionAndCurrentUser() async {
        let grant = makeGrant()
        let user = TwitchUser(
            id: grant.accessLease.session.userID,
            login: grant.accessLease.session.login,
            displayName: "Test User",
            profileImageURL: nil,
            createdAt: nil,
            broadcasterType: nil,
            description: nil
        )
        let service = StubAuthService(restoreResult: nil, signInResult: grant)
        let environment = AppEnvironment(
            authService: service,
            twitchBootstrap: StubTwitchBootstrap(user: user)
        )
        await environment.start()

        await environment.signIn()

        #expect(environment.state == .signedIn)
        #expect(environment.session == grant.accessLease.session)
        #expect(environment.currentUser == user)
    }

    @Test
    func profileBootstrapFailureDoesNotDiscardAuthenticatedSession() async {
        let grant = makeGrant()
        let service = StubAuthService(restoreResult: grant, signInResult: grant)
        let environment = AppEnvironment(
            authService: service,
            twitchBootstrap: StubTwitchBootstrap(shouldFail: true)
        )

        await environment.start()

        #expect(environment.state == .signedIn)
        #expect(environment.session == grant.accessLease.session)
        #expect(environment.currentUser == nil)
        #expect(!environment.showsAuthenticationError)
    }

    @Test
    func signOutIgnoresProfileBootstrapThatCompletesForOldSession() async {
        let grant = makeGrant()
        let staleUser = TwitchUser(
            id: grant.accessLease.session.userID,
            login: grant.accessLease.session.login,
            displayName: "Stale User",
            profileImageURL: nil,
            createdAt: nil,
            broadcasterType: nil,
            description: nil
        )
        let service = StubAuthService(restoreResult: nil, signInResult: grant)
        let bootstrap = BlockingTwitchBootstrap()
        let environment = AppEnvironment(
            authService: service,
            twitchBootstrap: bootstrap
        )
        await environment.start()

        let signInTask = Task { @MainActor in
            await environment.signIn()
        }
        await bootstrap.waitUntilLoadStarts()

        #expect(environment.state == .signedIn)
        await environment.signOut()
        await bootstrap.complete(with: staleUser)
        await signInTask.value

        #expect(environment.state == .signedOut)
        #expect(environment.session == nil)
        #expect(environment.currentUser == nil)
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

private struct StubTwitchBootstrap: TwitchBootstrapping, Sendable {
    let user: TwitchUser?
    let shouldFail: Bool

    init(user: TwitchUser? = nil, shouldFail: Bool = false) {
        self.user = user
        self.shouldFail = shouldFail
    }

    func loadCurrentUser(for grant: AuthenticationGrant) async throws -> TwitchUser {
        if shouldFail {
            throw BootstrapFailure.failed
        }
        return user ?? TwitchUser(
            id: grant.accessLease.session.userID,
            login: grant.accessLease.session.login,
            displayName: grant.accessLease.session.login,
            profileImageURL: nil,
            createdAt: nil,
            broadcasterType: nil,
            description: nil
        )
    }

    func resolveChannel(login: String, for grant: AuthenticationGrant) async throws -> ChatChannel {
        ChatChannel(id: "channel", login: login, displayName: login)
    }
}

private actor BlockingTwitchBootstrap: TwitchBootstrapping {
    private var loadStarted = false
    private var loadStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var profileContinuation: CheckedContinuation<TwitchUser, Never>?

    func loadCurrentUser(for grant: AuthenticationGrant) async throws -> TwitchUser {
        await withCheckedContinuation { continuation in
            profileContinuation = continuation
            loadStarted = true
            let waiters = loadStartWaiters
            loadStartWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func resolveChannel(login: String, for grant: AuthenticationGrant) async throws -> ChatChannel {
        ChatChannel(id: "channel", login: login, displayName: login)
    }

    func waitUntilLoadStarts() async {
        guard !loadStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            loadStartWaiters.append(continuation)
        }
    }

    func complete(with user: TwitchUser) {
        profileContinuation?.resume(returning: user)
        profileContinuation = nil
    }
}

private enum BootstrapFailure: Swift.Error, Sendable {
    case failed
}
