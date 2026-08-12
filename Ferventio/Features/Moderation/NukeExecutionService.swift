import Foundation
import FerventioDomain
import FerventioNetworking

protocol NukeExecuting: Sendable {
    func execute(
        plan: NukeExecutionPlan,
        broadcasterID: String,
        grant: AuthenticationGrant
    ) async throws -> NukeExecutionResult
}

enum NukeExecutionServiceError: Swift.Error, Equatable, Sendable {
    case notAuthenticated
    case missingChannel
    case missingScope
    case missingTargetUserID
}

struct TwitchNukeExecutionService: NukeExecuting, Sendable {
    static let requiredScope = "moderator:manage:banned_users"

    private let api: TwitchModerationAPIClient

    init(api: TwitchModerationAPIClient = TwitchModerationAPIClient()) {
        self.api = api
    }

    func execute(
        plan: NukeExecutionPlan,
        broadcasterID: String,
        grant: AuthenticationGrant
    ) async throws -> NukeExecutionResult {
        let lease = grant.accessLease
        guard lease.session.scopes.contains(Self.requiredScope) else {
            throw NukeExecutionServiceError.missingScope
        }

        let api = self.api
        let coordinator = NukeExecutionCoordinator { user, durationSeconds, reason in
            let targetUserID = user.userID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !targetUserID.isEmpty else {
                throw NukeExecutionServiceError.missingTargetUserID
            }
            try await api.timeoutUser(
                clientID: lease.session.clientID,
                accessToken: lease.accessToken,
                broadcasterID: broadcasterID,
                moderatorID: lease.session.userID,
                targetUserID: targetUserID,
                durationSeconds: durationSeconds,
                reason: reason
            )
        }

        return try await coordinator.execute(plan: plan)
    }
}
