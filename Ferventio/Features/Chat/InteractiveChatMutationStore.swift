import FerventioDomain
import FerventioNetworking
import Foundation
import Observation

protocol InteractiveChatMutating: Sendable {
    func createPoll(clientID: String, accessToken: String, broadcasterID: String, draft: PollDraft) async throws
    func endPoll(clientID: String, accessToken: String, broadcasterID: String, pollID: String, status: PollEndStatus) async throws
    func createPrediction(clientID: String, accessToken: String, broadcasterID: String, draft: PredictionDraft) async throws
    func endPrediction(clientID: String, accessToken: String, broadcasterID: String, predictionID: String, status: PredictionEndStatus, winningOutcomeID: String?) async throws
}

extension TwitchInteractiveMutationAPIClient: InteractiveChatMutating {}

@MainActor
@Observable
final class InteractiveChatMutationStore {
    private(set) var status: InteractiveMutationStatus?
    @ObservationIgnored private let client: any InteractiveChatMutating

    init(client: (any InteractiveChatMutating)? = nil) {
        self.client = client ?? TwitchInteractiveMutationAPIClient()
    }

    func clear() {
        status = nil
    }

    func createPoll(channel: ChatChannel, lease: TwitchAccessLease, draft: PollDraft) async -> Bool {
        await run(kind: .createPoll, channel: channel, lease: lease, requiredScope: "channel:manage:polls") {
            try await client.createPoll(
                clientID: lease.session.clientID,
                accessToken: lease.accessToken,
                broadcasterID: channel.id,
                draft: draft
            )
        }
    }

    func endPoll(channel: ChatChannel, lease: TwitchAccessLease, pollID: String, status endStatus: PollEndStatus) async -> Bool {
        let kind: InteractiveMutationKind = endStatus == .archived ? .archivePoll : .endPoll
        return await run(kind: kind, channel: channel, lease: lease, requiredScope: "channel:manage:polls") {
            try await client.endPoll(
                clientID: lease.session.clientID,
                accessToken: lease.accessToken,
                broadcasterID: channel.id,
                pollID: pollID,
                status: endStatus
            )
        }
    }

    func createPrediction(channel: ChatChannel, lease: TwitchAccessLease, draft: PredictionDraft) async -> Bool {
        await run(kind: .createPrediction, channel: channel, lease: lease, requiredScope: "channel:manage:predictions") {
            try await client.createPrediction(
                clientID: lease.session.clientID,
                accessToken: lease.accessToken,
                broadcasterID: channel.id,
                draft: draft
            )
        }
    }

    func endPrediction(
        channel: ChatChannel,
        lease: TwitchAccessLease,
        predictionID: String,
        status endStatus: PredictionEndStatus,
        winningOutcomeID: String? = nil
    ) async -> Bool {
        let kind: InteractiveMutationKind
        switch endStatus {
        case .locked: kind = .lockPrediction
        case .canceled: kind = .cancelPrediction
        case .resolved: kind = .resolvePrediction
        }
        return await run(kind: kind, channel: channel, lease: lease, requiredScope: "channel:manage:predictions") {
            try await client.endPrediction(
                clientID: lease.session.clientID,
                accessToken: lease.accessToken,
                broadcasterID: channel.id,
                predictionID: predictionID,
                status: endStatus,
                winningOutcomeID: winningOutcomeID
            )
        }
    }

    private func run(
        kind: InteractiveMutationKind,
        channel: ChatChannel,
        lease: TwitchAccessLease,
        requiredScope: String,
        operation: () async throws -> Void
    ) async -> Bool {
        guard channel.id == lease.session.userID,
              lease.session.scopes.contains(requiredScope) else {
            status = InteractiveMutationStatus(
                kind: kind,
                inFlight: false,
                failed: true,
                failureKind: .permission,
                recovery: .none
            )
            return false
        }

        status = InteractiveMutationStatus(kind: kind)
        do {
            try await operation()
            status = nil
            return true
        } catch is CancellationError {
            status = nil
            return false
        } catch {
            let classified = Self.classify(error)
            status = InteractiveMutationStatus(
                kind: kind,
                inFlight: false,
                failed: true,
                failureKind: classified.kind,
                recovery: classified.recovery
            )
            return false
        }
    }

    private static func classify(_ error: Swift.Error) -> (kind: InteractiveMutationFailureKind, recovery: InteractiveMutationRecovery) {
        if let error = error as? TwitchInteractiveMutationAPIClient.Error,
           case let .httpStatus(code, _) = error {
            switch code {
            case 401: return (.authentication, .refresh)
            case 403: return (.permission, .none)
            case 409: return (.conflict, .refresh)
            case 429: return (.rateLimited, .retry)
            case 500...599: return (.server, .retry)
            default: return (.unknown, .none)
            }
        }
        if error is URLError {
            return (.network, .retry)
        }
        return (.unknown, .none)
    }
}