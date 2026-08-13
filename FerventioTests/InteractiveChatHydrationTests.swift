import FerventioDomain
import Testing
@testable import Ferventio

struct InteractiveChatHydrationTests {
    @Test
    func skipsHydrationForAnotherBroadcaster() async {
        let client = StubInteractiveSnapshotClient()
        let hydrator = TwitchInteractiveChatHydrator(client: client)

        let snapshot = await hydrator.load(
            channel: ChatChannel(id: "other", login: "other", displayName: "Other"),
            lease: makeLease(scopes: ["channel:read:polls", "channel:read:predictions"])
        )

        #expect(snapshot == .empty)
        #expect(await client.requests.isEmpty)
    }

    @Test
    func gatesPollAndPredictionHydrationIndependently() async {
        let client = StubInteractiveSnapshotClient(
            poll: makePoll(),
            prediction: makePrediction()
        )
        let hydrator = TwitchInteractiveChatHydrator(client: client)

        let snapshot = await hydrator.load(
            channel: ownChannel(),
            lease: makeLease(scopes: ["channel:manage:polls"])
        )

        #expect(snapshot.poll?.id == "poll")
        #expect(snapshot.prediction == nil)
        #expect(await client.requests == [.poll])
    }

    @Test
    func oneHydrationFailureDoesNotSuppressOtherSnapshot() async {
        let client = StubInteractiveSnapshotClient(
            poll: nil,
            prediction: makePrediction(),
            pollFails: true
        )
        let hydrator = TwitchInteractiveChatHydrator(client: client)

        let snapshot = await hydrator.load(
            channel: ownChannel(),
            lease: makeLease(scopes: ["channel:read:polls", "channel:manage:predictions"])
        )

        #expect(snapshot.poll == nil)
        #expect(snapshot.prediction?.id == "prediction")
        #expect(Set(await client.requests) == [.poll, .prediction])
    }

    private func ownChannel() -> ChatChannel {
        ChatChannel(id: "user", login: "tester", displayName: "Tester")
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

    private func makePoll() -> PollOverlay {
        PollOverlay(
            id: "poll",
            channelID: "user",
            title: "Poll",
            choices: [],
            status: .active,
            startedAtMilliseconds: 100,
            updatedAtMilliseconds: 100
        )
    }

    private func makePrediction() -> PredictionOverlay {
        PredictionOverlay(
            id: "prediction",
            channelID: "user",
            title: "Prediction",
            outcomes: [],
            status: .active,
            startedAtMilliseconds: 100,
            updatedAtMilliseconds: 100
        )
    }
}

private enum InteractiveSnapshotRequest: Hashable, Sendable {
    case poll
    case prediction
}

private actor StubInteractiveSnapshotClient: InteractiveChatSnapshotLoading {
    private(set) var requests: [InteractiveSnapshotRequest] = []
    let poll: PollOverlay?
    let prediction: PredictionOverlay?
    let pollFails: Bool

    init(
        poll: PollOverlay? = nil,
        prediction: PredictionOverlay? = nil,
        pollFails: Bool = false
    ) {
        self.poll = poll
        self.prediction = prediction
        self.pollFails = pollFails
    }

    func loadActivePoll(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) async throws -> PollOverlay? {
        requests.append(.poll)
        if pollFails {
            throw StubInteractiveHydrationError.failed
        }
        return poll
    }

    func loadActivePrediction(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) async throws -> PredictionOverlay? {
        requests.append(.prediction)
        return prediction
    }
}

private enum StubInteractiveHydrationError: Swift.Error {
    case failed
}
