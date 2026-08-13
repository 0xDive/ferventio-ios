import FerventioDomain
import FerventioNetworking
import Testing
@testable import Ferventio

@MainActor
struct InteractiveChatOverlayStoreTests {
    @Test
    func reducesCurrentChannelSnapshotsAndRejectsStaleUpdates() async {
        let store = ChatStore(client: OverlayEventSubStub())
        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: nil
        )

        let current = makePoll(status: .completed, updatedAt: 300)
        store.apply(.poll(current))
        store.apply(.poll(makePoll(status: .active, updatedAt: 200)))

        #expect(store.interactiveOverlayState.pollsByChannel["channel"] == current)
        await store.disconnect()
    }

    @Test
    func ignoresOverlayForAnotherChannel() async {
        let store = ChatStore(client: OverlayEventSubStub())
        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: nil
        )

        store.apply(.prediction(makePrediction(channelID: "other")))

        #expect(store.interactiveOverlayState.predictionsByChannel.isEmpty)
        await store.disconnect()
    }

    @Test
    func optionalRevocationClearsOverlayWithoutFailingChat() async {
        let store = ChatStore(client: OverlayEventSubStub())
        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: nil
        )
        store.apply(.poll(makePoll(status: .active, updatedAt: 100)))

        store.apply(
            .revocation(
                subscriptionType: "channel.poll.progress",
                status: "version_removed"
            )
        )

        #expect(store.connectionState == .connected)
        #expect(store.interactiveOverlayState.pollsByChannel.isEmpty)
        #expect(!store.showsConnectionError)
        await store.disconnect()
    }

    @Test
    func chatRevocationStillFailsConnection() async {
        let store = ChatStore(client: OverlayEventSubStub())
        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: nil
        )

        store.apply(
            .revocation(
                subscriptionType: "channel.chat.message",
                status: "version_removed"
            )
        )

        #expect(store.connectionState == .failed)
        #expect(store.showsConnectionError)
        await store.disconnect()
    }

    @Test
    func disconnectClearsInteractiveState() async {
        let store = ChatStore(client: OverlayEventSubStub())
        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: nil
        )
        store.apply(.poll(makePoll(status: .active, updatedAt: 100)))
        store.apply(.prediction(makePrediction(channelID: "channel")))

        await store.disconnect()

        #expect(store.interactiveOverlayState == InteractiveChatOverlayState())
    }

    private func makeChannel() -> ChatChannel {
        ChatChannel(id: "channel", login: "channel", displayName: "Channel")
    }

    private func makeLease() -> TwitchAccessLease {
        TwitchAccessLease(
            accessToken: "access",
            leaseExpiresAtEpochMilliseconds: 100_000,
            twitchExpiresAtEpochMilliseconds: 200_000,
            twitchValidatedAtEpochMilliseconds: 50_000,
            backendSessionExpiresAtEpochMilliseconds: 300_000,
            session: TwitchSession(
                clientID: "client",
                userID: "user",
                login: "viewer",
                scopes: [
                    "user:read:chat",
                    "user:write:chat",
                    "channel:manage:polls",
                    "channel:manage:predictions",
                ],
                expiresInSeconds: 200
            )
        )
    }

    private func makePoll(
        status: PollStatus,
        updatedAt: Int64
    ) -> PollOverlay {
        PollOverlay(
            id: "poll",
            channelID: "channel",
            title: "Poll",
            choices: [PollChoice(id: "a", title: "A", votes: 1)],
            status: status,
            startedAtMilliseconds: 50,
            updatedAtMilliseconds: updatedAt
        )
    }

    private func makePrediction(channelID: String) -> PredictionOverlay {
        PredictionOverlay(
            id: "prediction",
            channelID: channelID,
            title: "Prediction",
            outcomes: [
                PredictionOutcome(
                    id: "yes",
                    title: "Yes",
                    users: 1,
                    channelPoints: 100,
                    color: .blue
                )
            ],
            status: .active,
            startedAtMilliseconds: 50,
            updatedAtMilliseconds: 100
        )
    }
}

private actor OverlayEventSubStub: EventSubChatStreaming {
    func connect(
        channel: ChatChannel,
        lease: TwitchAccessLease
    ) async throws -> EventSubSubscription {
        EventSubSubscription(
            id: "subscription",
            status: "enabled",
            type: "channel.chat.message",
            version: "1",
            cost: 0,
            sessionID: "session"
        )
    }

    func nextEvent() async throws -> TwitchEventSubChatClient.Event {
        try await Task.sleep(for: .seconds(3_600))
        throw CancellationError()
    }

    func disconnect() async {}
}
