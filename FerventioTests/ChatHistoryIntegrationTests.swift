import FerventioDomain
import FerventioNetworking
import Testing
@testable import Ferventio

@MainActor
struct ChatHistoryIntegrationTests {
    @Test
    func connectRestoresRecentHistoryBeforeLiveMessages() async {
        let historical = makeMessage(id: "history-1", timestamp: 100)
        let history = StubChatHistory(recent: [historical])
        let store = ChatStore(
            client: IdleEventSubClient(),
            history: history
        )

        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: nil
        )

        #expect(store.connectionState == .connected)
        #expect(store.messages == [historical])
        let maintenance = await history.recordedMaintenance()
        #expect(maintenance?.channelID == "channel")
        #expect(maintenance?.keepingLatest == ChatStore.maximumPersistedMessagesPerChannel)
        #expect(maintenance?.olderThanTimestampMilliseconds ?? -1 >= 0)

        await store.disconnect()
    }

    @Test
    func remoteBootstrapRunsAfterConnectAndMergesSnapshot() async {
        let remote = makeMessage(id: "remote-1", timestamp: 200)
        let loader = StubRecentMessagesLoader(result: TwitchRecentMessagesResult(messages: [remote]))
        let store = ChatStore(
            client: IdleEventSubClient(),
            recentMessagesLoader: loader
        )

        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: nil
        )

        for _ in 0..<50 where !store.messages.contains(where: { $0.id == "remote-1" }) {
            await Task.yield()
        }

        #expect(store.connectionState == .connected)
        #expect(store.messages.map(\.id) == ["remote-1"])
        #expect(await loader.recordedLimit() == ChatStore.remoteRecentMessagesLimit)
        await store.disconnect()
    }

    @Test
    func remoteMergePersistsOnlyNewCanonicalRows() async {
        let history = StubChatHistory()
        let store = ChatStore(
            history: history,
            recentMessagesLoader: NoopRecentMessagesLoader()
        )
        let catalog = ThirdPartyEmoteCatalog(emotes: [
            ThirdPartyEmoteDefinition(
                code: "OMEGALUL",
                emoteID: "bttv-1",
                provider: "bttv",
                animated: false,
                imageURL: "https://example.com/omegalul"
            )
        ])
        store.setThirdPartyEmoteCatalog(catalog)

        let canonical = ChatMessage(
            id: "remote-1",
            channelID: "channel",
            channelLogin: "channel",
            author: ChatAuthor(id: "viewer", login: "viewer", displayName: "Viewer"),
            text: "OMEGALUL",
            fragments: [.text("OMEGALUL")],
            timestamp: "2026-08-11T10:00:00Z",
            timestampMilliseconds: 200
        )

        await store.mergeRecentMessages([canonical])
        await store.mergeRecentMessages([canonical])

        #expect(store.messages.count == 1)
        #expect(store.messages[0].fragments.first == .thirdPartyEmote(
            text: "OMEGALUL",
            emoteID: "bttv-1",
            provider: "bttv",
            animated: false,
            imageURL: "https://example.com/omegalul",
            zeroWidth: false
        ))
        let persisted = await history.recordedEnqueued()
        #expect(persisted == [canonical])
    }

    @Test
    func backgroundAndDisconnectFlushPendingHistory() async {
        let history = StubChatHistory()
        let store = ChatStore(
            client: IdleEventSubClient(),
            history: history
        )

        await store.connect(
            channel: makeChannel(),
            lease: makeLease(),
            currentUser: nil
        )
        let flushesAfterConnect = await history.recordedFlushCount()

        await store.suspend()
        let flushesAfterSuspend = await history.recordedFlushCount()
        await store.disconnect()
        let flushesAfterDisconnect = await history.recordedFlushCount()

        #expect(flushesAfterConnect >= 1)
        #expect(flushesAfterSuspend > flushesAfterConnect)
        #expect(flushesAfterDisconnect > flushesAfterSuspend)
    }

    private func makeChannel() -> ChatChannel {
        ChatChannel(id: "channel", login: "channel", displayName: "Channel")
    }

    private func makeMessage(id: String, timestamp: Int64) -> ChatMessage {
        ChatMessage(
            id: id,
            channelID: "channel",
            channelLogin: "channel",
            author: ChatAuthor(id: "viewer", login: "viewer", displayName: "Viewer"),
            text: "Persisted",
            timestamp: "2026-08-11T10:00:00Z",
            timestampMilliseconds: timestamp
        )
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
                userID: "viewer",
                login: "viewer",
                scopes: ["user:read:chat", "user:write:chat"],
                expiresInSeconds: 200
            )
        )
    }
}

private actor StubChatHistory: ChatHistoryPersisting {
    struct Maintenance: Sendable {
        let channelID: String
        let olderThanTimestampMilliseconds: Int64
        let keepingLatest: Int
    }

    private let recent: [ChatMessage]
    private var maintenance: Maintenance?
    private var enqueued: [ChatMessage] = []
    private var flushCount = 0

    init(recent: [ChatMessage] = []) {
        self.recent = recent
    }

    func recentMessages(channelID: String, limit: Int) async -> [ChatMessage] {
        Array(recent.suffix(limit))
    }

    func enqueue(_ message: ChatMessage) async {
        enqueued.append(message)
    }

    func maintain(
        channelID: String,
        olderThanTimestampMilliseconds: Int64,
        keepingLatest: Int
    ) async {
        maintenance = Maintenance(
            channelID: channelID,
            olderThanTimestampMilliseconds: olderThanTimestampMilliseconds,
            keepingLatest: keepingLatest
        )
    }

    func flush() async {
        flushCount += 1
    }

    func recordedMaintenance() -> Maintenance? {
        maintenance
    }

    func recordedFlushCount() -> Int {
        flushCount
    }

    func recordedEnqueued() -> [ChatMessage] {
        enqueued
    }
}

private actor StubRecentMessagesLoader: RecentMessagesLoading {
    private let result: TwitchRecentMessagesResult
    private var limit: Int?

    init(result: TwitchRecentMessagesResult) {
        self.result = result
    }

    func load(
        channel: ChatChannel,
        limit: Int
    ) async throws -> TwitchRecentMessagesResult {
        self.limit = limit
        return result
    }

    func recordedLimit() -> Int? {
        limit
    }
}

private actor IdleEventSubClient: EventSubChatStreaming {
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
