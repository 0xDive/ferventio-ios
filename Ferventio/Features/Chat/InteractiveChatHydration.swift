import FerventioDomain
import FerventioNetworking

struct InteractiveChatHydrationSnapshot: Equatable, Sendable {
    let poll: PollOverlay?
    let prediction: PredictionOverlay?

    static let empty = InteractiveChatHydrationSnapshot(
        poll: nil,
        prediction: nil
    )
}

protocol InteractiveChatHydrating: Sendable {
    func load(
        channel: ChatChannel,
        lease: TwitchAccessLease
    ) async -> InteractiveChatHydrationSnapshot
}

protocol InteractiveChatSnapshotLoading: Sendable {
    func loadActivePoll(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) async throws -> PollOverlay?

    func loadActivePrediction(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) async throws -> PredictionOverlay?
}

extension TwitchInteractiveAPIClient: InteractiveChatSnapshotLoading {}

struct NoopInteractiveChatHydrator: InteractiveChatHydrating {
    func load(
        channel: ChatChannel,
        lease: TwitchAccessLease
    ) async -> InteractiveChatHydrationSnapshot {
        .empty
    }
}

struct TwitchInteractiveChatHydrator: InteractiveChatHydrating {
    private let client: any InteractiveChatSnapshotLoading

    init(client: any InteractiveChatSnapshotLoading = TwitchInteractiveAPIClient()) {
        self.client = client
    }

    func load(
        channel: ChatChannel,
        lease: TwitchAccessLease
    ) async -> InteractiveChatHydrationSnapshot {
        guard channel.id == lease.session.userID else {
            return .empty
        }

        let scopes = Set(lease.session.scopes.map { $0.lowercased() })
        let canReadPolls = scopes.contains("channel:read:polls")
            || scopes.contains("channel:manage:polls")
        let canReadPredictions = scopes.contains("channel:read:predictions")
            || scopes.contains("channel:manage:predictions")

        async let poll = loadPollIfAllowed(
            canRead: canReadPolls,
            lease: lease,
            broadcasterID: channel.id
        )
        async let prediction = loadPredictionIfAllowed(
            canRead: canReadPredictions,
            lease: lease,
            broadcasterID: channel.id
        )

        return await InteractiveChatHydrationSnapshot(
            poll: poll,
            prediction: prediction
        )
    }

    private func loadPollIfAllowed(
        canRead: Bool,
        lease: TwitchAccessLease,
        broadcasterID: String
    ) async -> PollOverlay? {
        guard canRead else {
            return nil
        }
        return try? await client.loadActivePoll(
            clientID: lease.session.clientID,
            accessToken: lease.accessToken,
            broadcasterID: broadcasterID
        )
    }

    private func loadPredictionIfAllowed(
        canRead: Bool,
        lease: TwitchAccessLease,
        broadcasterID: String
    ) async -> PredictionOverlay? {
        guard canRead else {
            return nil
        }
        return try? await client.loadActivePrediction(
            clientID: lease.session.clientID,
            accessToken: lease.accessToken,
            broadcasterID: broadcasterID
        )
    }
}

extension ChatStore {
    func applyHydratedInteractiveOverlays(
        _ snapshot: InteractiveChatHydrationSnapshot
    ) {
        guard let channelID = channel?.id else {
            return
        }

        if let poll = snapshot.poll,
           poll.channelID == channelID {
            interactiveOverlayState = InteractiveChatOverlayReducer.reduce(
                state: interactiveOverlayState,
                event: .pollSnapshot(poll)
            )
        }

        if let prediction = snapshot.prediction,
           prediction.channelID == channelID {
            interactiveOverlayState = InteractiveChatOverlayReducer.reduce(
                state: interactiveOverlayState,
                event: .predictionSnapshot(prediction)
            )
        }
    }

    func applyConfirmedPollMutation(
        _ poll: PollOverlay,
        status: PollEndStatus
    ) {
        guard poll.channelID == channel?.id else {
            return
        }
        let confirmedStatus: PollStatus = switch status {
        case .terminated: .terminated
        case .archived: .archived
        }
        apply(.poll(PollOverlay(
            id: poll.id,
            channelID: poll.channelID,
            title: poll.title,
            choices: poll.choices,
            status: confirmedStatus,
            startedAtMilliseconds: poll.startedAtMilliseconds,
            endsAtMilliseconds: poll.endsAtMilliseconds,
            endedAtMilliseconds: poll.endedAtMilliseconds,
            channelPointsVotingEnabled: poll.channelPointsVotingEnabled,
            channelPointsPerVote: poll.channelPointsPerVote,
            bitsVotingEnabled: poll.bitsVotingEnabled,
            bitsPerVote: poll.bitsPerVote,
            updatedAtMilliseconds: nextInteractiveMutationTimestamp(
                after: poll.updatedAtMilliseconds
            )
        )))
    }

    func applyConfirmedPredictionMutation(
        _ prediction: PredictionOverlay,
        status: PredictionEndStatus,
        winningOutcomeID: String?
    ) {
        guard prediction.channelID == channel?.id else {
            return
        }
        let confirmedStatus: PredictionStatus = switch status {
        case .locked: .locked
        case .canceled: .canceled
        case .resolved: .resolved
        }
        apply(.prediction(PredictionOverlay(
            id: prediction.id,
            channelID: prediction.channelID,
            title: prediction.title,
            outcomes: prediction.outcomes,
            status: confirmedStatus,
            startedAtMilliseconds: prediction.startedAtMilliseconds,
            locksAtMilliseconds: prediction.locksAtMilliseconds,
            lockedAtMilliseconds: prediction.lockedAtMilliseconds,
            endedAtMilliseconds: prediction.endedAtMilliseconds,
            winningOutcomeID: status == .resolved ? winningOutcomeID : nil,
            updatedAtMilliseconds: nextInteractiveMutationTimestamp(
                after: prediction.updatedAtMilliseconds
            )
        )))
    }

    private func nextInteractiveMutationTimestamp(after timestamp: Int64) -> Int64 {
        timestamp == .max ? .max : timestamp + 1
    }
}
