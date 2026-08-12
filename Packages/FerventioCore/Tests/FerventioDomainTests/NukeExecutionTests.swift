import Testing
@testable import FerventioDomain

struct NukeExecutionTests {
    @Test
    func defaultsMatchAndroidSafetyPolicy() {
        let policy = NukeExecutionPolicy()
        #expect(policy.timeoutSeconds == 600)
        #expect(policy.reason == "Mass moderation")
        #expect(policy.maxTargetUsers == 100)
        #expect(policy.delayBetweenActionsMilliseconds == 175)
    }

    @Test
    func executesFrozenUsersInOrderAndPacesActions() async throws {
        let recorder = Recorder()
        let coordinator = NukeExecutionCoordinator(
            moderationAction: { user, duration, reason in
                await recorder.recordAction(user: user, duration: duration, reason: reason)
            },
            delayAction: { milliseconds in
                await recorder.recordDelay(milliseconds)
            }
        )
        let plan = makePlan(userIDs: ["a", "b", "c"])

        let result = try await coordinator.execute(plan: plan)

        #expect(result.attemptedUsers == 3)
        #expect(result.succeededUsers == 3)
        #expect(result.completed)
        #expect(await recorder.userIDs() == ["a", "b", "c"])
        #expect(await recorder.delays() == [175, 175])
        #expect(await recorder.durations() == [600, 600, 600])
    }

    @Test
    func continuesAfterIndividualTargetFailure() async throws {
        let recorder = Recorder()
        let coordinator = NukeExecutionCoordinator(
            moderationAction: { user, _, _ in
                await recorder.recordUserID(user.userID)
                if user.userID == "b" {
                    throw TestFailure.expected
                }
            },
            delayAction: { _ in }
        )

        let result = try await coordinator.execute(plan: makePlan(userIDs: ["a", "b", "c"]))

        #expect(result.attemptedUsers == 3)
        #expect(result.succeededUsers == 2)
        #expect(result.failedUsers == 1)
        #expect(result.failures.first?.user.userID == "b")
        #expect(await recorder.userIDs() == ["a", "b", "c"])
    }

    @Test
    func rejectsUnsafeOrEmptyPlansBeforeAnyAction() async {
        let coordinator = NukeExecutionCoordinator(
            moderationAction: { _, _, _ in },
            delayAction: { _ in }
        )

        await #expect(throws: NukeExecutionCoordinatorError.emptyTargetSet) {
            try await coordinator.execute(plan: makePlan(userIDs: []))
        }

        let oversized = makePlan(userIDs: (0..<101).map(String.init))
        await #expect(throws: NukeExecutionCoordinatorError.targetLimitExceeded(limit: 100)) {
            try await coordinator.execute(plan: oversized)
        }
    }

    @Test
    func propagatesCancellationInsteadOfRecordingFailure() async {
        let coordinator = NukeExecutionCoordinator(
            moderationAction: { _, _, _ in throw CancellationError() },
            delayAction: { _ in }
        )

        await #expect(throws: CancellationError.self) {
            try await coordinator.execute(plan: makePlan(userIDs: ["a"]))
        }
    }

    private func makePlan(userIDs: [String]) -> NukeExecutionPlan {
        NukeExecutionPlan(
            query: "spam",
            matchMode: .plainText,
            caseSensitive: false,
            previewedAtMilliseconds: 1,
            targetUsers: userIDs.map {
                NukeTargetUser(userID: $0, userLogin: $0, userDisplayName: $0)
            },
            targetMessageIDs: userIDs.map { "message-\($0)" }
        )
    }
}

private enum TestFailure: Swift.Error {
    case expected
}

private actor Recorder {
    struct Action: Sendable {
        let userID: String
        let duration: Int
        let reason: String
    }

    private var actions: [Action] = []
    private var delayValues: [Int64] = []

    func recordAction(user: NukeTargetUser, duration: Int, reason: String) {
        actions.append(Action(userID: user.userID, duration: duration, reason: reason))
    }

    func recordUserID(_ userID: String) {
        actions.append(Action(userID: userID, duration: 0, reason: ""))
    }

    func recordDelay(_ milliseconds: Int64) {
        delayValues.append(milliseconds)
    }

    func userIDs() -> [String] {
        actions.map(\.userID)
    }

    func durations() -> [Int] {
        actions.map(\.duration)
    }

    func delays() -> [Int64] {
        delayValues
    }
}
