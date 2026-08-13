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

        if interactiveOverlayState.pollsByChannel[channelID] == nil,
           let poll = snapshot.poll,
           poll.channelID == channelID {
            apply(.poll(poll))
        }

        if interactiveOverlayState.predictionsByChannel[channelID] == nil,
           let prediction = snapshot.prediction,
           prediction.channelID == channelID {
            apply(.prediction(prediction))
        }
    }
}
