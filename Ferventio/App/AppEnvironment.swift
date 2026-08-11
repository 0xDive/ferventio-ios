import FerventioDomain
import Observation

@MainActor
@Observable
final class AppEnvironment {
    var state: AppState = .launching
    var session: TwitchSession?
    var isAuthorizing = false
    var isSigningOut = false
    var showsAuthenticationError = false

    private let authService: any Authenticating

    init(authService: (any Authenticating)? = nil) {
        self.authService = authService ?? AuthService.live()
    }

    func start() async {
        guard state == .launching else {
            return
        }
        do {
            if let grant = try await authService.restoreAuthentication() {
                session = grant.accessLease.session
                state = .signedIn
            } else {
                state = .signedOut
            }
        } catch {
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
            session = grant.accessLease.session
            state = .signedIn
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
            session = nil
            state = .signedOut
        } catch {
            showsAuthenticationError = true
        }
    }
}
