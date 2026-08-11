import Foundation
import FerventioDomain
import FerventioNetworking
import FerventioSupport

protocol TwitchSessionValidating: Sendable {
    func validateAccessToken(_ token: String) async throws -> TwitchSession
}

extension TwitchAPIClient: TwitchSessionValidating {}

@MainActor
protocol Authenticating: AnyObject {
    func restoreAuthentication() async throws -> AuthenticationGrant?
    func signIn() async throws -> AuthenticationGrant
    func signOut() async throws
}

@MainActor
final class AuthService: Authenticating {
    private let configuration: AppConfiguration
    private let backendClient: BackendClient
    private let twitchClient: any TwitchSessionValidating
    private let identityStore: DeviceIdentityStore
    private let authenticationStore: AuthenticationStore
    private let webAuthentication: WebAuthenticationSessionRunner

    init(
        configuration: AppConfiguration,
        backendClient: BackendClient,
        twitchClient: any TwitchSessionValidating = TwitchAPIClient(),
        identityStore: DeviceIdentityStore,
        authenticationStore: AuthenticationStore,
        webAuthentication: WebAuthenticationSessionRunner
    ) {
        self.configuration = configuration
        self.backendClient = backendClient
        self.twitchClient = twitchClient
        self.identityStore = identityStore
        self.authenticationStore = authenticationStore
        self.webAuthentication = webAuthentication
    }

    static func live(configuration: AppConfiguration = .live) -> AuthService {
        let keychain = KeychainStore(service: configuration.keychainService)
        return AuthService(
            configuration: configuration,
            backendClient: BackendClient(baseURL: configuration.backendURL),
            twitchClient: TwitchAPIClient(),
            identityStore: DeviceIdentityStore(store: keychain),
            authenticationStore: AuthenticationStore(store: keychain),
            webAuthentication: WebAuthenticationSessionRunner()
        )
    }

    func restoreAuthentication() async throws -> AuthenticationGrant? {
        guard let stored = try authenticationStore.load() else {
            return nil
        }
        guard normalized(stored.backendCredential.serverURL) == normalized(backendClient.serverURL.absoluteString) else {
            try authenticationStore.clear()
            return nil
        }

        let nowMilliseconds = Self.epochMilliseconds(Date())
        guard stored.backendCredential.expiresAtEpochMilliseconds > nowMilliseconds else {
            try authenticationStore.clear()
            return nil
        }

        if let cachedLease = stored.accessLease,
           TwitchAccessLeasePolicy.canReuseWithoutBackendCall(cachedLease, nowEpochMilliseconds: nowMilliseconds),
           !TwitchAccessLeasePolicy.needsDirectValidationAtStartup(cachedLease, nowEpochMilliseconds: nowMilliseconds) {
            return AuthenticationGrant(
                backendCredential: stored.backendCredential,
                accessLease: cachedLease
            )
        }

        let device = try identityStore.loadOrCreate()
        do {
            let backendLease = try await backendClient.leaseAccessToken(
                device: device,
                credential: stored.backendCredential
            )
            var grant = makeGrant(
                credential: stored.backendCredential,
                lease: backendLease
            )

            if TwitchAccessLeasePolicy.needsDirectValidationAtStartup(
                grant.accessLease,
                nowEpochMilliseconds: Self.epochMilliseconds(Date())
            ) {
                do {
                    grant = try await directlyValidated(grant)
                } catch {
                    let refreshedLease = try await backendClient.leaseAccessToken(
                        device: device,
                        credential: stored.backendCredential,
                        forceRefresh: true
                    )
                    grant = try await directlyValidated(
                        makeGrant(credential: stored.backendCredential, lease: refreshedLease)
                    )
                }
            }

            try authenticationStore.save(grant)
            return grant
        } catch {
            if isBackendSessionRejected(error) {
                try authenticationStore.clear()
                return nil
            }

            guard let cachedLease = stored.accessLease,
                  TwitchAccessLeasePolicy.canUseDuringBackendOutage(
                    cachedLease,
                    nowEpochMilliseconds: Self.epochMilliseconds(Date())
                  ) else {
                throw error
            }

            var fallbackGrant = AuthenticationGrant(
                backendCredential: stored.backendCredential,
                accessLease: cachedLease
            )
            if TwitchAccessLeasePolicy.needsDirectValidationAtStartup(
                cachedLease,
                nowEpochMilliseconds: Self.epochMilliseconds(Date())
            ) {
                fallbackGrant = try await directlyValidated(fallbackGrant)
                try authenticationStore.save(fallbackGrant)
            }
            return fallbackGrant
        }
    }

    func signIn() async throws -> AuthenticationGrant {
        let device = try identityStore.loadOrCreate()
        let start = try await backendClient.startAuthorization(
            device: device,
            appCallbackURL: configuration.oauthCallbackURL
        )
        let callbackURL = try await webAuthentication.authenticate(
            url: start.authorizationURL,
            callbackScheme: configuration.oauthCallbackScheme
        )
        let handoff = try MobileAuthCallback.parse(
            callbackURL,
            expectedScheme: configuration.oauthCallbackScheme,
            expectedState: start.state
        )
        var grant = try await backendClient.completeAuthorization(
            device: device,
            code: handoff.code,
            state: handoff.state
        )
        if TwitchAccessLeasePolicy.needsDirectValidationAtStartup(
            grant.accessLease,
            nowEpochMilliseconds: Self.epochMilliseconds(Date())
        ) {
            grant = try await directlyValidated(grant)
        }
        try authenticationStore.save(grant)
        return grant
    }

    func signOut() async throws {
        if let stored = try authenticationStore.load() {
            let device = try identityStore.loadOrCreate()
            try? await backendClient.logout(
                device: device,
                credential: stored.backendCredential
            )
        }
        try authenticationStore.clear()
    }

    func revokeDevice() async throws {
        guard let stored = try authenticationStore.load() else {
            return
        }
        let device = try identityStore.loadOrCreate()
        try await backendClient.revokeDevice(
            device: device,
            credential: stored.backendCredential
        )
        try authenticationStore.clear()
    }

    func revokeAllSessions() async throws {
        guard let stored = try authenticationStore.load() else {
            return
        }
        let device = try identityStore.loadOrCreate()
        try await backendClient.revokeAllSessions(
            device: device,
            credential: stored.backendCredential
        )
        try authenticationStore.clear()
    }

    private func directlyValidated(_ grant: AuthenticationGrant) async throws -> AuthenticationGrant {
        let validatedSession = try await twitchClient.validateAccessToken(grant.accessLease.accessToken)
        let validatedLease = try TwitchAccessLeaseValidation.updateAfterDirectValidation(
            cachedLease: grant.accessLease,
            validatedSession: validatedSession,
            requiredScopes: grant.accessLease.session.scopes,
            nowEpochMilliseconds: Self.epochMilliseconds(Date())
        )
        return AuthenticationGrant(
            backendCredential: grant.backendCredential,
            accessLease: validatedLease
        )
    }

    private func makeGrant(
        credential: BackendSessionCredential,
        lease: TwitchAccessLease
    ) -> AuthenticationGrant {
        AuthenticationGrant(
            backendCredential: BackendSessionCredential(
                serverURL: credential.serverURL,
                token: credential.token,
                expiresAtEpochMilliseconds: lease.backendSessionExpiresAtEpochMilliseconds
            ),
            accessLease: lease
        )
    }

    private func isBackendSessionRejected(_ error: Swift.Error) -> Bool {
        guard case let BackendClient.Error.httpStatus(status, _) = error else {
            return false
        }
        return status == 401 || status == 403
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func epochMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.towardZero))
    }
}
