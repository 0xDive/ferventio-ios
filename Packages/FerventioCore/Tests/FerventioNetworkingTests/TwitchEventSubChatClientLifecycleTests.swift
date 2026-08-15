import FerventioDomain
import Foundation
import Testing
@testable import FerventioNetworking

struct TwitchEventSubChatClientLifecycleTests {
    @Test
    func staleSuccessfulConnectCannotReplaceNewLifecycle() async throws {
        let transport = LifecycleEventSubTransport()
        let subscriptions = BlockingLifecycleSubscriptionClient(firstOutcome: .success)
        let client = TwitchEventSubChatClient(
            transport: transport,
            subscriptionClient: subscriptions
        )
        let staleChannel = makeChannel(id: "100", login: "stale")
        let currentChannel = makeChannel(id: "200", login: "current")
        let lease = makeLease()

        let staleConnect = Task {
            try await client.connect(channel: staleChannel, lease: lease)
        }
        await subscriptions.waitUntilFirstSubscriptionStarts()

        await client.disconnect()
        _ = try await client.connect(channel: currentChannel, lease: lease)

        await subscriptions.releaseFirstSubscription()
        await #expect(throws: CancellationError.self) {
            try await staleConnect.value
        }

        try await assertCurrentChannel(
            currentChannel,
            rejects: staleChannel,
            client: client,
            transport: transport
        )
    }

    @Test
    func staleFailedConnectCannotClearNewLifecycle() async throws {
        let transport = LifecycleEventSubTransport()
        let subscriptions = BlockingLifecycleSubscriptionClient(firstOutcome: .failure)
        let client = TwitchEventSubChatClient(
            transport: transport,
            subscriptionClient: subscriptions
        )
        let staleChannel = makeChannel(id: "100", login: "stale")
        let currentChannel = makeChannel(id: "200", login: "current")
        let lease = makeLease()

        let staleConnect = Task {
            try await client.connect(channel: staleChannel, lease: lease)
        }
        await subscriptions.waitUntilFirstSubscriptionStarts()

        await client.disconnect()
        _ = try await client.connect(channel: currentChannel, lease: lease)

        await subscriptions.releaseFirstSubscription()
        let staleConnectFailed: Bool
        do {
            _ = try await staleConnect.value
            staleConnectFailed = false
        } catch {
            staleConnectFailed = true
        }
        #expect(staleConnectFailed)

        try await assertCurrentChannel(
            currentChannel,
            rejects: staleChannel,
            client: client,
            transport: transport
        )
    }

    private func assertCurrentChannel(
        _ currentChannel: ChatChannel,
        rejects staleChannel: ChatChannel,
        client: TwitchEventSubChatClient,
        transport: LifecycleEventSubTransport
    ) async throws {
        await transport.enqueueReceive(
            try makeMessageEnvelope(channel: staleChannel, messageID: "stale-message")
        )
        await transport.enqueueReceive(
            try makeMessageEnvelope(channel: currentChannel, messageID: "current-message")
        )

        let event = try await client.nextEvent()
        switch event {
        case let .message(message):
            #expect(message.channelID == currentChannel.id)
            #expect(message.id == "current-message")
        default:
            #expect(Bool(false))
        }
    }

    private func makeChannel(id: String, login: String) -> ChatChannel {
        ChatChannel(
            id: id,
            login: login,
            displayName: login.capitalized
        )
    }

    private func makeLease() -> TwitchAccessLease {
        TwitchAccessLease(
            accessToken: "access-token",
            leaseExpiresAtEpochMilliseconds: 9_999_999_999_999,
            twitchExpiresAtEpochMilliseconds: 9_999_999_999_999,
            twitchValidatedAtEpochMilliseconds: 1,
            backendSessionExpiresAtEpochMilliseconds: 9_999_999_999_999,
            session: TwitchSession(
                clientID: "client-id",
                userID: "viewer-id",
                login: "viewer",
                scopes: [],
                expiresInSeconds: 3_600
            )
        )
    }

    private func makeMessageEnvelope(
        channel: ChatChannel,
        messageID: String
    ) throws -> EventSubEnvelope {
        try EventSubEnvelopeParser.parse(
            """
            {
              "metadata": {
                "message_id": "event-\(messageID)",
                "message_type": "notification",
                "message_timestamp": "2026-08-15T20:20:00Z"
              },
              "payload": {
                "subscription": {"type": "channel.chat.message"},
                "event": {
                  "broadcaster_user_id": "\(channel.id)",
                  "broadcaster_user_login": "\(channel.login)",
                  "chatter_user_id": "viewer-id",
                  "chatter_user_login": "viewer",
                  "chatter_user_name": "Viewer",
                  "color": "#FFFFFF",
                  "message_id": "\(messageID)",
                  "message_type": "text",
                  "badges": [],
                  "message": {
                    "text": "hello",
                    "fragments": [{"type": "text", "text": "hello"}]
                  }
                }
              }
            }
            """
        )
    }
}

private actor LifecycleEventSubTransport: EventSubWebSocketTransport {
    private var connectCount = 0
    private var receiveQueue: [EventSubEnvelope] = []

    func connect(to url: URL) async throws -> EventSubEnvelope {
        connectCount += 1
        return try EventSubEnvelopeParser.parse(
            """
            {
              "metadata": {
                "message_id": "welcome-\(connectCount)",
                "message_type": "session_welcome",
                "message_timestamp": "2026-08-15T20:20:00Z"
              },
              "payload": {
                "session": {
                  "id": "session-\(connectCount)",
                  "keepalive_timeout_seconds": 30,
                  "reconnect_url": null
                }
              }
            }
            """
        )
    }

    func receive() async throws -> EventSubEnvelope {
        guard !receiveQueue.isEmpty else {
            throw CancellationError()
        }
        return receiveQueue.removeFirst()
    }

    func migrate(to reconnectURL: URL) async throws -> EventSubEnvelope {
        throw CancellationError()
    }

    func close() {}

    func enqueueReceive(_ envelope: EventSubEnvelope) {
        receiveQueue.append(envelope)
    }
}

private actor BlockingLifecycleSubscriptionClient: EventSubSubscriptionCreating {
    enum FirstOutcome: Sendable {
        case success
        case failure
    }

    enum Failure: Swift.Error {
        case injected
    }

    private let firstOutcome: FirstOutcome
    private var chatSubscriptionAttempts = 0
    private var firstSubscriptionStarted = false
    private var firstSubscriptionWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstSubscriptionContinuation: CheckedContinuation<Void, Never>?

    init(firstOutcome: FirstOutcome) {
        self.firstOutcome = firstOutcome
    }

    func createChatMessageSubscription(
        clientID: String,
        accessToken: String,
        sessionID: String,
        broadcasterID: String,
        userID: String
    ) async throws -> EventSubSubscription {
        chatSubscriptionAttempts += 1
        if chatSubscriptionAttempts == 1 {
            await withCheckedContinuation { continuation in
                firstSubscriptionContinuation = continuation
                firstSubscriptionStarted = true
                let waiters = firstSubscriptionWaiters
                firstSubscriptionWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume()
                }
            }
            switch firstOutcome {
            case .success:
                break
            case .failure:
                throw Failure.injected
            }
        }

        return EventSubSubscription(
            id: "subscription-\(sessionID)",
            status: "enabled",
            type: "channel.chat.message",
            version: "1",
            cost: 0,
            sessionID: sessionID
        )
    }

    func createInteractiveSubscription(
        clientID: String,
        accessToken: String,
        sessionID: String,
        broadcasterID: String,
        type: InteractiveEventSubSubscriptionType
    ) async throws -> EventSubSubscription {
        EventSubSubscription(
            id: "interactive-\(sessionID)-\(type.rawValue)",
            status: "enabled",
            type: type.rawValue,
            version: "1",
            cost: 0,
            sessionID: sessionID
        )
    }

    func waitUntilFirstSubscriptionStarts() async {
        guard !firstSubscriptionStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            firstSubscriptionWaiters.append(continuation)
        }
    }

    func releaseFirstSubscription() {
        firstSubscriptionContinuation?.resume()
        firstSubscriptionContinuation = nil
    }
}
