import Testing
@testable import FerventioDomain

struct InteractiveChatOverlaysTests {
    @Test
    func pollHelpersMatchAndroidPresentationSemantics() {
        let poll = PollOverlay(
            id: "poll-1",
            channelID: "channel-1",
            title: "Choose",
            choices: [
                PollChoice(id: "a", title: "A", votes: 3),
                PollChoice(id: "b", title: "B", votes: 1),
            ],
            status: .active,
            startedAtMilliseconds: 100,
            updatedAtMilliseconds: 200
        )

        #expect(poll.totalVotes == 4)
        #expect(poll.isActive)
        #expect(poll.voteShare(choiceID: "a") == 0.75)
        #expect(poll.voteShare(choiceID: "missing") == 0)
    }

    @Test
    func predictionHelpersMatchAndroidPresentationSemantics() {
        let prediction = PredictionOverlay(
            id: "prediction-1",
            channelID: "channel-1",
            title: "Will it happen?",
            outcomes: [
                PredictionOutcome(id: "yes", title: "Yes", users: 2, channelPoints: 3_000, color: .blue),
                PredictionOutcome(id: "no", title: "No", users: 1, channelPoints: 1_000, color: .pink),
            ],
            status: .locked,
            startedAtMilliseconds: 100,
            lockedAtMilliseconds: 200,
            updatedAtMilliseconds: 200
        )

        #expect(prediction.totalUsers == 3)
        #expect(prediction.totalChannelPoints == 4_000)
        #expect(!prediction.isActive)
        #expect(prediction.isLocked)
        #expect(prediction.pointsShare(outcomeID: "yes") == 0.75)
    }

    @Test
    func reducerRejectsStalePollSnapshot() {
        let current = makePoll(status: .completed, updatedAt: 300)
        let stale = makePoll(status: .active, updatedAt: 200)
        let state = InteractiveChatOverlayState(pollsByChannel: ["channel-1": current])

        let reduced = InteractiveChatOverlayReducer.reduce(
            state: state,
            event: .pollSnapshot(stale)
        )

        #expect(reduced.pollsByChannel["channel-1"] == current)
    }

    @Test
    func reducerRejectsStalePredictionAfterLock() {
        let current = makePrediction(status: .locked, updatedAt: 300)
        let stale = makePrediction(status: .active, updatedAt: 200)
        let state = InteractiveChatOverlayState(predictionsByChannel: ["channel-1": current])

        let reduced = InteractiveChatOverlayReducer.reduce(
            state: state,
            event: .predictionSnapshot(stale)
        )

        #expect(reduced.predictionsByChannel["channel-1"] == current)
    }

    @Test
    func equalTimestampAllowsLatestDeliveredSnapshot() {
        let first = makePoll(status: .active, updatedAt: 300)
        let second = makePoll(status: .completed, updatedAt: 300)
        let state = InteractiveChatOverlayState(pollsByChannel: ["channel-1": first])

        let reduced = InteractiveChatOverlayReducer.reduce(
            state: state,
            event: .pollSnapshot(second)
        )

        #expect(reduced.pollsByChannel["channel-1"] == second)
    }

    @Test
    func clearChannelRemovesOnlyMatchingInteractiveState() {
        let state = InteractiveChatOverlayState(
            pollsByChannel: [
                "channel-1": makePoll(channelID: "channel-1", status: .active, updatedAt: 100),
                "channel-2": makePoll(channelID: "channel-2", status: .active, updatedAt: 100),
            ],
            predictionsByChannel: [
                "channel-1": makePrediction(channelID: "channel-1", status: .active, updatedAt: 100),
                "channel-2": makePrediction(channelID: "channel-2", status: .active, updatedAt: 100),
            ]
        )

        let reduced = InteractiveChatOverlayReducer.reduce(
            state: state,
            event: .clearChannel("channel-1")
        )

        #expect(reduced.pollsByChannel["channel-1"] == nil)
        #expect(reduced.predictionsByChannel["channel-1"] == nil)
        #expect(reduced.pollsByChannel["channel-2"] != nil)
        #expect(reduced.predictionsByChannel["channel-2"] != nil)
    }

    @Test
    func twitchStatusValuesMapDefensively() {
        #expect(PollStatus(twitchValue: "completed") == .completed)
        #expect(PollStatus(twitchValue: "future_status") == .unknown)
        #expect(PredictionStatus(twitchValue: "cancelled") == .canceled)
        #expect(PredictionOutcomeColor(twitchValue: "BLUE") == .blue)
        #expect(PredictionOutcomeColor(twitchValue: "green") == .unknown)
    }

    private func makePoll(
        channelID: String = "channel-1",
        status: PollStatus,
        updatedAt: Int64
    ) -> PollOverlay {
        PollOverlay(
            id: "poll-1",
            channelID: channelID,
            title: "Poll",
            choices: [PollChoice(id: "a", title: "A")],
            status: status,
            startedAtMilliseconds: 100,
            updatedAtMilliseconds: updatedAt
        )
    }

    private func makePrediction(
        channelID: String = "channel-1",
        status: PredictionStatus,
        updatedAt: Int64
    ) -> PredictionOverlay {
        PredictionOverlay(
            id: "prediction-1",
            channelID: channelID,
            title: "Prediction",
            outcomes: [PredictionOutcome(id: "a", title: "A")],
            status: status,
            startedAtMilliseconds: 100,
            updatedAtMilliseconds: updatedAt
        )
    }
}
