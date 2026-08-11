import FerventioDomain
import FerventioNetworking
import Testing
@testable import Ferventio

@MainActor
struct ChatStoreTests {
    @Test
    func boundsInMemoryMessageBuffer() {
        let store = ChatStore()

        for index in 0..<(ChatStore.maximumMessages + 5) {
            store.apply(.message(makeMessage(index)))
        }

        #expect(store.messages.count == ChatStore.maximumMessages)
        #expect(store.messages.first?.id == "message-5")
        #expect(store.messages.last?.id == "message-2004")
    }

    @Test
    func reconnectEventReturnsStoreToConnectedState() {
        let store = ChatStore()

        store.apply(.reconnected(sessionID: "session-2"))

        #expect(store.connectionState == .connected)
    }

    @Test
    func revocationMarksConnectionAsFailed() {
        let store = ChatStore()

        store.apply(.revocation(subscriptionType: "channel.chat.message", status: "version_removed"))

        #expect(store.connectionState == .failed)
        #expect(store.showsConnectionError)
    }

    @Test
    func sentOptimisticMessageIsReconciledWithEventSubMessage() async {
        let eventSub = StubEventSubChatClient()
        let sender = StubChatMessageSender(
            result: ChatSendResult(messageID: "server-1", isSent: true, dropReason: nil)
        )
        let store = ChatStore(client: eventSub, sender: sender)
        store.composerText = "Hello chat"

        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: makeCurrentUser()
        )
        await store.sendCurrentMessage()

        #expect(store.messages.count == 1)
        #expect(store.messages[0].outgoingState == .sent)
        #expect(store.messages[0].serverMessageID == "server-1")
        #expect(store.composerText.isEmpty)

        store.apply(.message(makeMessage(1, id: "server-1", text: "Hello chat")))

        #expect(store.messages.count == 1)
        #expect(store.messages[0].id == "server-1")
        #expect(store.messages[0].outgoingState == .none)
        await store.disconnect()
    }

    @Test
    func droppedMessageStaysVisibleAsFailed() async {
        let eventSub = StubEventSubChatClient()
        let sender = StubChatMessageSender(
            result: ChatSendResult(
                messageID: nil,
                isSent: false,
                dropReason: ChatSendDropReason(code: "automod_held", message: "Held by AutoMod")
            )
        )
        let store = ChatStore(client: eventSub, sender: sender)
        store.composerText = "Potentially held"

        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: makeCurrentUser()
        )
        await store.sendCurrentMessage()

        #expect(store.messages.count == 1)
        #expect(store.messages[0].outgoingState == .failed)
        #expect(store.messages[0].outgoingError == "Held by AutoMod")
        #expect(store.showsSendError)
        await store.disconnect()
    }

    private func makeMessage(
        _ index: Int,
        id: String? = nil,
        text: String? = nil
    ) -> ChatMessage {
        ChatMessage(
            id: id ?? "message-\(index)",
            channelID: "channel",
            channelLogin: "channel",
            author: ChatAuthor(
                id: "user",
                login: "viewer",
                displayName: "Viewer"
            ),
            text: text ?? "Message \(index)",
            timestamp: "2026-08-11T09:00:00Z",
            timestampMilliseconds: Int64(index)
        )
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
                scopes: ["user:read:chat", "user:write:chat"],
                expiresInSeconds: 200
            )
        )
    }

    private func makeCurrentUser() -> TwitchUser {
        TwitchUser(
            id: "user",
            login: "viewer",
            displayName: "Viewer",
            profileImageURL: nil,
            createdAt: nil,
            broadcasterType: nil,
            description: nil
        )
    }
}

private actor StubEventSubChatClient: EventSubChatStreaming {
    func connect(channel: ChatChannel, lease: TwitchAccessLease) async throws -> EventSubSubscription {
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

private actor StubChatMessageSender: ChatMessageSending {
    let result: ChatSendResult

    init(result: ChatSendResult) {
        self.result = result
    }

    func sendMessage(
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        senderID: String,
        message: String,
        replyParentMessageID: String?
    ) async throws -> ChatSendResult {
        result
    }
}
