import Testing
@testable import FerventioDomain

struct InteractiveChatMutationTests {
    @Test
    func validPollDraftMatchesTwitchAndAndroidBounds() {
        let draft = PollDraft(
            title: "  Which game?  ",
            choices: [" One ", "Two"],
            durationSeconds: 300,
            channelPointsVotingEnabled: true,
            channelPointsPerVote: 100
        )

        #expect(InteractiveOverlayDraftValidator.validate(draft).isEmpty)
        #expect(draft.normalized.title == "Which game?")
        #expect(draft.normalized.choices == ["One", "Two"])
    }

    @Test
    func pollValidationRejectsBoundsDuplicatesAndInvalidPointsCost() {
        let draft = PollDraft(
            title: "",
            choices: ["Same", " same ", String(repeating: "x", count: 26), "four", "five", "six"],
            durationSeconds: 14,
            channelPointsVotingEnabled: true,
            channelPointsPerVote: 0
        )

        let issues = Set(InteractiveOverlayDraftValidator.validate(draft))
        #expect(issues.contains(.pollTitle))
        #expect(issues.contains(.pollChoiceCount))
        #expect(issues.contains(.pollChoiceTitle))
        #expect(issues.contains(.pollChoiceDuplicate))
        #expect(issues.contains(.pollDuration))
        #expect(issues.contains(.pollChannelPointsPerVote))
    }

    @Test
    func disabledChannelPointsDoesNotRequirePerVoteCost() {
        let draft = PollDraft(
            title: "Poll",
            choices: ["One", "Two"],
            durationSeconds: 60,
            channelPointsVotingEnabled: false,
            channelPointsPerVote: 0
        )

        #expect(!InteractiveOverlayDraftValidator.validate(draft).contains(.pollChannelPointsPerVote))
    }

    @Test
    func validPredictionDraftMatchesTwitchBounds() {
        let draft = PredictionDraft(
            title: "Winner?",
            outcomes: ["Blue", "Pink"],
            predictionWindowSeconds: 30
        )

        #expect(InteractiveOverlayDraftValidator.validate(draft).isEmpty)
    }

    @Test
    func predictionValidationRejectsInvalidDraft() {
        let draft = PredictionDraft(
            title: String(repeating: "x", count: 46),
            outcomes: ["Same", " same "],
            predictionWindowSeconds: 1_801
        )

        let issues = Set(InteractiveOverlayDraftValidator.validate(draft))
        #expect(issues.contains(.predictionTitle))
        #expect(issues.contains(.predictionOutcomeDuplicate))
        #expect(issues.contains(.predictionWindow))
    }

    @Test
    func mutationStatusesPreserveRecoveryContract() {
        let status = InteractiveMutationStatus(
            kind: .resolvePrediction,
            inFlight: false,
            failed: true,
            failureKind: .conflict,
            recovery: .refresh
        )

        #expect(status.kind == .resolvePrediction)
        #expect(status.failed)
        #expect(status.failureKind == .conflict)
        #expect(status.recovery == .refresh)
        #expect(PollEndStatus.archived.rawValue == "ARCHIVED")
        #expect(PredictionEndStatus.resolved.rawValue == "RESOLVED")
    }
}
