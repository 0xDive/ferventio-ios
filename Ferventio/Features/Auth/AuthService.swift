import Foundation
import FerventioDomain
import FerventioNetworking
import FerventioSupport

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
    private let identityStore: DeviceIdentityStore
    private let authenticationStore: AuthenticationStore
    private let webAuthentication: WebAuthenticationSessionRunner

    init(
        configuration: AppConfiguration,
        backendClient: BackendClient,
        identityStore: DeviceIdentityStore,
        authenticationStore: AuthenticationStore,
        webAuthentication: WebAuthenticationSessionRunner
    ) {
        self.configuration = configuration
        self.backendClient = backendClient
        self.identityStore = identityStore
        self.authenticationStore = authenticationStore
        self.webAuthentication = webAuthentication
    }

    static func live(configuration: AppConfiguration = .live) -> AuthService {
        let keychain = KeychainStore(service: configuration.keychainService)
        return AuthService(
            configuration: configuration,
            backendClient: BackendClient(baseURL: configuration.backendURL),
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
        let lease = try await backendClient.leaseAccessToken(
            device: device,
            credential: stored.backendCredential
        )
        let updatedCredential = BackendSessionCredential(
            serverURL: stored.backendCredential.serverURL,
            token: stored.backendCredential.token,
            expiresAtEpochMilliseconds: lease.backendSessionExpiresAtEpochMilliseconds
        )
        let grant = AuthenticationGrant(
            backendCredential: updatedCredential,
            accessLease: lease
        )
        try authenticationStore.save(grant)
        return grant
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
        let grant = try await backendClient.completeAuthorization(
            device: device,
            code: handoff.code,
            state: handoff.state
        )
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

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func epochMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.towardZero))
    }
}
