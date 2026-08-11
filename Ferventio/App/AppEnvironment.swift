import FerventioDomain
import Observation

@MainActor
@Observable
final class AppEnvironment {
    var state: AppState = .launching
    var session: TwitchSession?
    var currentUser: TwitchUser?
    var isAuthorizing = false
    var isSigningOut = false
    var showsAuthenticationError = false

    @ObservationIgnored private let authService: any Authenticating
    @ObservationIgnored private let twitchBootstrap: any TwitchBootstrapping
    @ObservationIgnored private var authenticationGrant: AuthenticationGrant?

    init(
        authService: (any Authenticating)? = nil,
        twitchBootstrap: (any TwitchBootstrapping)? = nil
    ) {
        self.authService = authService ?? AuthService.live()
        self.twitchBootstrap = twitchBootstrap ?? TwitchBootstrapService()
    }

    func start() async {
        guard state == .launching else {
            return
        }
        do {
            if let grant = try await authService.restoreAuthentication() {
                apply(grant)
                await loadCurrentUser(for: grant)
            } else {
                state = .signedOut
            }
        } catch {
            clearSession()
            state = .signedOut
            showsAuthenticationError = true
        }
    }

    func signIn() async {
        guard !isAuthorizing else {
            return
        }
        isAuthorizing = true
        showsAuthenticationError = false
        defer { isAuthorizing = false }

        do {
            let grant = try await authService.signIn()
            apply(grant)
            await loadCurrentUser(for: grant)
        } catch {
            showsAuthenticationError = true
        }
    }

    func signOut() async {
        guard !isSigningOut else {
            return
        }
        isSigningOut = true
        defer { isSigningOut = false }

        do {
            try await authService.signOut()
            clearSession()
            state = .signedOut
        } catch {
            showsAuthenticationError = true
        }
    }

    private func apply(_ grant: AuthenticationGrant) {
        authenticationGrant = grant
        session = grant.accessLease.session
        state = .signedIn
    }

    private func loadCurrentUser(for grant: AuthenticationGrant) async {
        currentUser = try? await twitchBootstrap.loadCurrentUser(for: grant)
    }

    private func clearSession() {
        authenticationGrant = nil
        session = nil
        currentUser = nil
    }
}
