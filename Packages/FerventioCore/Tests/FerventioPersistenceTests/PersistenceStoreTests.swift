import FerventioDomain
import Testing
@testable import FerventioPersistence

struct PersistenceStoreTests {
    @Test
    func roundTripsRichChatMessage() async throws {
        let store = try PersistenceStore.inMemory()
        let message = makeMessage(
            id: "message-1",
            timestamp: 100,
            text: "hello OMEGALUL",
            fragments: [
                .text("hello "),
                .thirdPartyEmote(
                    text: "OMEGALUL",
                    emoteID: "bttv-1",
                    provider: "bttv",
                    animated: true,
                    imageURL: "https://example.com/emote.gif",
                    zeroWidth: false
                ),
            ],
            reply: ReplyContext(
                parentMessageID: "parent",
                parentMessageBody: "parent body",
                parentUserID: "parent-user",
                parentUserLogin: "parent-login",
                parentUserName: "Parent"
            )
        )

        try await store.save(message)
        let recent = try await store.recentMessages(channelID: "channel", limit: 50)

        #expect(recent == [message])
        #expect(try await store.count(channelID: "channel") == 1)
    }

    @Test
    func upsertReplacesPayloadForSameChannelAndMessageID() async throws {
        let store = try PersistenceStore.inMemory()
        let first = makeMessage(id: "message-1", timestamp: 100, text: "before")
        let replacement = makeMessage(id: "message-1", timestamp: 100, text: "after")

        try await store.save(first)
        try await store.save(replacement)

        #expect(try await store.count() == 1)
        #expect(try await store.recentMessages(channelID: "channel", limit: 10) == [replacement])
    }

    @Test
    func recentMessagesReturnChronologicalTail() async throws {
        let store = try PersistenceStore.inMemory()
        try await store.save((0..<8).map { index in
            makeMessage(
                id: "message-\(index)",
                timestamp: Int64(index * 100),
                text: "Message \(index)"
            )
        })

        let recent = try await store.recentMessages(channelID: "channel", limit: 3)

        #expect(recent.map(\.id) == ["message-5", "message-6", "message-7"])
    }

    @Test
    func recentMessagesCanPageBeforeTimestamp() async throws {
        let store = try PersistenceStore.inMemory()
        try await store.save((0..<6).map { index in
            makeMessage(
                id: "message-\(index)",
                timestamp: Int64(index * 100),
                text: "Message \(index)"
            )
        })

        let page = try await store.recentMessages(
            channelID: "channel",
            limit: 2,
            beforeTimestampMilliseconds: 400
        )

        #expect(page.map(\.id) == ["message-2", "message-3"])
    }

    @Test
    func retentionPruneDeletesOnlyOlderRowsAcrossChannels() async throws {
        let store = try PersistenceStore.inMemory()
        try await store.save([
            makeMessage(id: "old-a", channelID: "channel-a", timestamp: 100, text: "old"),
            makeMessage(id: "new-a", channelID: "channel-a", timestamp: 500, text: "new"),
            makeMessage(id: "old-b", channelID: "channel-b", timestamp: 200, text: "old"),
            makeMessage(id: "new-b", channelID: "channel-b", timestamp: 600, text: "new"),
        ])

        let deleted = try await store.prune(olderThanTimestampMilliseconds: 400)

        #expect(deleted == 2)
        #expect(try await store.count() == 2)
        #expect(try await store.count(channelID: "channel-a") == 1)
        #expect(try await store.count(channelID: "channel-b") == 1)
    }

    @Test
    func channelTrimKeepsNewestRowsOnly() async throws {
        let store = try PersistenceStore.inMemory()
        try await store.save((0..<7).map { index in
            makeMessage(
                id: "message-\(index)",
                timestamp: Int64(index),
                text: "Message \(index)"
            )
        })

        let deleted = try await store.trim(channelID: "channel", keepingLatest: 3)
        let recent = try await store.recentMessages(channelID: "channel", limit: 10)

        #expect(deleted == 4)
        #expect(recent.map(\.id) == ["message-4", "message-5", "message-6"])
    }

    @Test
    func rejectsInvalidLimitsAndRetentionBoundaries() async throws {
        let store = try PersistenceStore.inMemory()

        await #expect(throws: PersistenceStore.Error.invalidLimit) {
            try await store.recentMessages(channelID: "channel", limit: 0)
        }
        await #expect(throws: PersistenceStore.Error.invalidLimit) {
            try await store.trim(channelID: "channel", keepingLatest: -1)
        }
        await #expect(throws: PersistenceStore.Error.invalidRetentionBoundary) {
            try await store.prune(olderThanTimestampMilliseconds: -1)
        }
    }

    private func makeMessage(
        id: String,
        channelID: String = "channel",
        timestamp: Int64,
        text: String,
        fragments: [ChatFragment]? = nil,
        reply: ReplyContext? = nil
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            eventSubMessageID: "event-\(id)",
            channelID: channelID,
            channelLogin: channelID,
            author: ChatAuthor(
                id: "author",
                login: "viewer",
                displayName: "Viewer",
                color: "#9146FF",
                badges: [ChatBadge(setID: "moderator", id: "1")]
            ),
            text: text,
            fragments: fragments,
            timestamp: "2026-08-11T10:00:00Z",
            timestampMilliseconds: timestamp,
            reply: reply
        )
    }
}
