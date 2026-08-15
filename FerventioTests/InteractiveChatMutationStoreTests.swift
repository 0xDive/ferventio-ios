import FerventioDomain
import FerventioNetworking
import Testing
@testable import Ferventio

@MainActor
struct InteractiveChatMutationStoreTests {
    @Test
    func refusesAnotherBroadcasterWithoutCallingClient() async {
        let client = StubInteractiveMutator()
        let store = InteractiveChatMutationStore(client: client)
        let result = await store.createPoll(
            channel: ChatChannel(id: "other", login: "other", displayName: "Other"),
            lease: makeLease(scopes: ["channel:manage:polls"]),
            draft: pollDraft()
        )
        #expect(!result)
        #expect(store.status?.failureKind == .permission)
        #expect(await client.calls == 0)
    }

    @Test
    func successfulPollMutationClearsStatus() async {
        let client = StubInteractiveMutator()
        let store = InteractiveChatMutationStore(client: client)
        let result = await store.createPoll(
            channel: ownChannel(),
            lease: makeLease(scopes: ["channel:manage:polls"]),
            draft: pollDraft()
        )
        #expect(result)
        #expect(store.status == nil)
        #expect(await client.calls == 1)
    }

    @Test
    func forbiddenMutationIsClassifiedWithoutRetry() async {
        let client = StubInteractiveMutator(error: TwitchInteractiveMutationAPIClient.Error.httpStatus(403, "forbidden"))
        let store = InteractiveChatMutationStore(client: client)
        let result = await store.createPrediction(
            channel: ownChannel(),
            lease: makeLease(scopes: ["channel:manage:predictions"]),
            draft: PredictionDraft(title: "Winner?", outcomes: ["A", "B"], predictionWindowSeconds: 60)
        )
        #expect(!result)
        #expect(store.status?.failureKind == .permission)
        #expect(store.status?.recovery == InteractiveMutationRecovery.none)
    }

    @Test
    func ignoresConcurrentMutationWhileRequestIsInFlight() async {
        let client = BlockingInteractiveMutator()
        let store = InteractiveChatMutationStore(client: client)

        async let firstResult = store.createPoll(
            channel: ownChannel(),
            lease: makeLease(scopes: ["channel:manage:polls"]),
            draft: pollDraft()
        )

        await client.waitUntilStarted()
        let secondResult = await store.createPoll(
            channel: ownChannel(),
            lease: makeLease(scopes: ["channel:manage:polls"]),
            draft: pollDraft()
        )

        #expect(!secondResult)
        #expect(await client.calls == 1)

        await client.release()
        #expect(await firstResult)
        #expect(store.status == nil)
    }

    @Test
    func clearInvalidatesOldMutationWithoutClearingNewStatus() async {
        let client = SequencedInteractiveMutator()
        let store = InteractiveChatMutationStore(client: client)

        async let oldResult = store.createPoll(
            channel: ownChannel(),
            lease: makeLease(scopes: ["channel:manage:polls"]),
            draft: pollDraft()
        )
        await client.waitUntilCallCount(1)

        store.clear()
        #expect(store.status == nil)

        async let newResult = store.createPoll(
            channel: ownChannel(),
            lease: makeLease(scopes: ["channel:manage:polls"]),
            draft: pollDraft()
        )
        await client.waitUntilCallCount(2)
        #expect(store.status?.inFlight == true)

        await client.releaseCall(1)
        #expect(!(await oldResult))
        #expect(store.status?.inFlight == true)

        await client.releaseCall(2)
        #expect(await newResult)
        #expect(store.status == nil)
    }

    private func ownChannel() -> ChatChannel {
        ChatChannel(id: "user", login: "tester", displayName: "Tester")
    }

    private func pollDraft() -> PollDraft {
        PollDraft(title: "Poll", choices: ["A", "B"], durationSeconds: 60)
    }

    private func makeLease(scopes: Set<String>) -> TwitchAccessLease {
        TwitchAccessLease(
            accessToken: "access",
            leaseExpiresAtEpochMilliseconds: 200_000,
            twitchExpiresAtEpochMilliseconds: 200_000,
            twitchValidatedAtEpochMilliseconds: 100_000,
            backendSessionExpiresAtEpochMilliseconds: 300_000,
            session: TwitchSession(
                clientID: "client",
                userID: "user",
                login: "tester",
                scopes: scopes,
                expiresInSeconds: 100
            )
        )
    }
}

private actor StubInteractiveMutator: InteractiveChatMutating {
    private(set) var calls = 0
    let error: Swift.Error?

    init(error: Swift.Error? = nil) {
        self.error = error
    }

    func createPoll(clientID: String, accessToken: String, broadcasterID: String, draft: PollDraft) async throws {
        calls += 1
        if let error { throw error }
    }

    func endPoll(clientID: String, accessToken: String, broadcasterID: String, pollID: String, status: PollEndStatus) async throws {
        calls += 1
        if let error { throw error }
    }

    func createPrediction(clientID: String, accessToken: String, broadcasterID: String, draft: PredictionDraft) async throws {
        calls += 1
        if let error { throw error }
    }

    func endPrediction(clientID: String, accessToken: String, broadcasterID: String, predictionID: String, status: PredictionEndStatus, winningOutcomeID: String?) async throws {
        calls += 1
        if let error { throw error }
    }
}

private actor BlockingInteractiveMutator: InteractiveChatMutating {
    private(set) var calls = 0
    private var started = false
    private var isReleased = false

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func release() {
        isReleased = true
    }

    func createPoll(clientID: String, accessToken: String, broadcasterID: String, draft: PollDraft) async throws {
        calls += 1
        started = true
        while !isReleased {
            await Task.yield()
        }
    }

    func endPoll(clientID: String, accessToken: String, broadcasterID: String, pollID: String, status: PollEndStatus) async throws {
        calls += 1
    }

    func createPrediction(clientID: String, accessToken: String, broadcasterID: String, draft: PredictionDraft) async throws {
        calls += 1
    }

    func endPrediction(clientID: String, accessToken: String, broadcasterID: String, predictionID: String, status: PredictionEndStatus, winningOutcomeID: String?) async throws {
        calls += 1
    }
}

private actor SequencedInteractiveMutator: InteractiveChatMutating {
    private var calls = 0
    private var releasedCalls: Set<Int> = []

    func waitUntilCallCount(_ expected: Int) async {
        while calls < expected {
            await Task.yield()
        }
    }

    func releaseCall(_ call: Int) {
        releasedCalls.insert(call)
    }

    func createPoll(clientID: String, accessToken: String, broadcasterID: String, draft: PollDraft) async throws {
        calls += 1
        let call = calls
        while !releasedCalls.contains(call) {
            await Task.yield()
        }
    }

    func endPoll(clientID: String, accessToken: String, broadcasterID: String, pollID: String, status: PollEndStatus) async throws {}

    func createPrediction(clientID: String, accessToken: String, broadcasterID: String, draft: PredictionDraft) async throws {}

    func endPrediction(clientID: String, accessToken: String, broadcasterID: String, predictionID: String, status: PredictionEndStatus, winningOutcomeID: String?) async throws {}
}
