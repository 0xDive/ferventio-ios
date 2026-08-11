import FerventioDomain
import FerventioNetworking

protocol TwitchBootstrapping: Sendable {
    func loadCurrentUser(for grant: AuthenticationGrant) async throws -> TwitchUser
    func resolveChannel(login: String, for grant: AuthenticationGrant) async throws -> ChatChannel
}

struct TwitchBootstrapService: TwitchBootstrapping, Sendable {
    enum Error: Swift.Error, Equatable {
        case currentUserMismatch
    }

    private let api: TwitchAPIClient

    init(api: TwitchAPIClient = TwitchAPIClient()) {
        self.api = api
    }

    func loadCurrentUser(for grant: AuthenticationGrant) async throws -> TwitchUser {
        let session = grant.accessLease.session
        let user = try await api.getCurrentUser(
            clientID: session.clientID,
            token: grant.accessLease.accessToken
        )
        guard user.id == session.userID,
              user.login.caseInsensitiveCompare(session.login) == .orderedSame else {
            throw Error.currentUserMismatch
        }
        return user
    }

    func resolveChannel(login: String, for grant: AuthenticationGrant) async throws -> ChatChannel {
        let session = grant.accessLease.session
        return try await api.getChannel(
            clientID: session.clientID,
            token: grant.accessLease.accessToken,
            login: login
        )
    }
}
