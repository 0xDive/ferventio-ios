import FerventioDomain
import FerventioNetworking
import Testing
@testable import Ferventio

@MainActor
struct InteractiveMutationReconciliationTests {
    @Test
    func confirmedPollTerminationReplacesActiveOverlayImmediately() async {
        let store = ChatStore(client: ReconciliationEventSubStub())
        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: nil
        )
        let poll = makePoll(status: .active, updatedAt: 100)
        store.apply(.poll(poll))

        store.applyConfirmedPollMutation(poll, status: .terminated)

        let updated = store.interactiveOverlayState.pollsByChannel["channel"]
        #expect(updated?.status == .terminated)
        #expect(updated?.updatedAtMilliseconds == 101)
        await store.disconnect()
    }

    @Test
    func confirmedPredictionLockReplacesActiveOverlayImmediately() async {
        let store = ChatStore(client: ReconciliationEventSubStub())
        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: nil
        )
        let prediction = makePrediction(status: .active, updatedAt: 200)
        store.apply(.prediction(prediction))

        store.applyConfirmedPredictionMutation(
            prediction,
            status: .locked,
            winningOutcomeID: nil
        )

        let updated = store.interactiveOverlayState.predictionsByChannel["channel"]
        #expect(updated?.status == .locked)
        #expect(updated?.winningOutcomeID == nil)
        #expect(updated?.updatedAtMilliseconds == 201)
        await store.disconnect()
    }

    @Test
    func confirmedPredictionResolutionPublishesWinner() async {
        let store = ChatStore(client: ReconciliationEventSubStub())
        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: nil
        )
        let prediction = makePrediction(status: .locked, updatedAt: 300)
        store.apply(.prediction(prediction))

        store.applyConfirmedPredictionMutation(
            prediction,
            status: .resolved,
            winningOutcomeID: "yes"
        )

        let updated = store.interactiveOverlayState.predictionsByChannel["channel"]
        #expect(updated?.status == .resolved)
        #expect(updated?.winningOutcomeID == "yes")
        #expect(updated?.updatedAtMilliseconds == 301)
        await store.disconnect()
    }

    @Test
    func hydratedSnapshotCanReplaceExistingOverlayWhenItIsNewer() async {
        let store = ChatStore(client: ReconciliationEventSubStub())
        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: nil
        )
        store.apply(.poll(makePoll(status: .active, updatedAt: 100)))
        let refreshed = makePoll(status: .active, updatedAt: 200, votes: 5)

        store.applyHydratedInteractiveOverlays(
            InteractiveChatHydrationSnapshot(poll: refreshed, prediction: nil)
        )

        #expect(store.interactiveOverlayState.pollsByChannel["channel"]?.totalVotes == 5)
        #expect(store.interactiveOverlayState.pollsByChannel["channel"]?.updatedAtMilliseconds == 200)
        await store.disconnect()
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
                scopes: ["channel:manage:polls", "channel:manage:predictions"],
                expiresInSeconds: 200
            )
        )
    }

    private func makePoll(
        status: PollStatus,
        updatedAt: Int64,
        votes: Int = 1
    ) -> PollOverlay {
        PollOverlay(
            id: "poll",
            channelID: "channel",
            title: "Poll",
            choices: [PollChoice(id: "a", title: "A", votes: votes)],
            status: status,
            startedAtMilliseconds: 50,
            updatedAtMilliseconds: updatedAt
        )
    }

    private func makePrediction(
        status: PredictionStatus,
        updatedAt: Int64
    ) -> PredictionOverlay {
        PredictionOverlay(
            id: "prediction",
            channelID: "channel",
            title: "Prediction",
            outcomes: [
                PredictionOutcome(
                    id: "yes",
                    title: "Yes",
                    users: 1,
                    channelPoints: 100,
                    color: .blue
                ),
                PredictionOutcome(
                    id: "no",
                    title: "No",
                    users: 1,
                    channelPoints: 100,
                    color: .pink
                ),
            ],
            status: status,
            startedAtMilliseconds: 50,
            updatedAtMilliseconds: updatedAt
        )
    }
}

private actor ReconciliationEventSubStub: EventSubChatStreaming {
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
