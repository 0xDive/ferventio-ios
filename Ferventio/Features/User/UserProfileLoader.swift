import FerventioDomain
import FerventioNetworking

protocol UserProfileLoading: Sendable {
    func loadUser(author: ChatAuthor, for grant: AuthenticationGrant) async throws -> TwitchUser
}

struct TwitchUserProfileLoader: UserProfileLoading, Sendable {
    private let api: TwitchAPIClient

    init(api: TwitchAPIClient = TwitchAPIClient()) {
        self.api = api
    }

    func loadUser(author: ChatAuthor, for grant: AuthenticationGrant) async throws -> TwitchUser {
        let session = grant.accessLease.session
        let userID = author.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if !userID.isEmpty {
            return try await api.getUserByID(
                clientID: session.clientID,
                token: grant.accessLease.accessToken,
                userID: userID
            )
        }
        return try await api.getUserByLogin(
            clientID: session.clientID,
            token: grant.accessLease.accessToken,
            login: author.login
        )
    }
}
