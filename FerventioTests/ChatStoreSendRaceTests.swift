import FerventioDomain
import FerventioNetworking
import Testing
@testable import Ferventio

@MainActor
struct ChatStoreSendRaceTests {
    @Test
    func staleSendFailureDoesNotLeakAcrossReconnect() async {
        let sender = BlockingChatMessageSender()
        let store = ChatStore(
            client: PassiveEventSubChatClient(),
            sender: sender
        )

        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: makeCurrentUser()
        )
        store.composerText = "old-session message"

        let sendTask = Task { @MainActor in
            await store.sendCurrentMessage()
        }
        await sender.waitUntilSendStarts()

        await store.disconnect()
        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: makeCurrentUser()
        )

        #expect(store.connectionState == .connected)
        #expect(!store.isSending)
        #expect(!store.showsSendError)
        #expect(store.messages.isEmpty)

        await sender.complete(
            with: ChatSendResult(
                messageID: nil,
                isSent: false,
                dropReason: ChatSendDropReason(
                    code: "stale_failure",
                    message: "Old session failure"
                )
            )
        )
        await sendTask.value

        #expect(store.connectionState == .connected)
        #expect(!store.isSending)
        #expect(!store.showsSendError)
        #expect(store.messages.isEmpty)
        await store.disconnect()
    }

    @Test
    func inFlightSendCanCompleteAcrossSuspendAndResume() async {
        let sender = BlockingChatMessageSender()
        let store = ChatStore(
            client: PassiveEventSubChatClient(),
            sender: sender
        )

        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: makeCurrentUser()
        )
        store.composerText = "background send"

        let sendTask = Task { @MainActor in
            await store.sendCurrentMessage()
        }
        await sender.waitUntilSendStarts()

        await store.suspend()
        #expect(store.connectionState == .suspended)
        #expect(store.isSending)
        #expect(store.messages.count == 1)

        await store.resumeIfNeeded()
        #expect(store.connectionState == .connected)
        #expect(store.isSending)

        await sender.complete(
            with: ChatSendResult(
                messageID: "server-message",
                isSent: true,
                dropReason: nil
            )
        )
        await sendTask.value

        #expect(!store.isSending)
        #expect(!store.showsSendError)
        #expect(store.messages.count == 1)
        #expect(store.messages[0].outgoingState == .sent)
        #expect(store.messages[0].serverMessageID == "server-message")
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

private actor PassiveEventSubChatClient: EventSubChatStreaming {
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

private actor BlockingChatMessageSender: ChatMessageSending {
    private var sendStarted = false
    private var sendStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<ChatSendResult, Never>?

    func sendMessage(
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        senderID: String,
        message: String,
        replyParentMessageID: String?
    ) async throws -> ChatSendResult {
        sendStarted = true
        let waiters = sendStartWaiters
        sendStartWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilSendStarts() async {
        guard !sendStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            sendStartWaiters.append(continuation)
        }
    }

    func complete(with result: ChatSendResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
