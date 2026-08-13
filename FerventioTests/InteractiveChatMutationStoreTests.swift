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
        #expect(store.status?.recovery == .none)
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
