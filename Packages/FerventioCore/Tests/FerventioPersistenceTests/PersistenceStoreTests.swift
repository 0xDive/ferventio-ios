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
    func reportsUsedDatabasePages() async throws {
        let store = try PersistenceStore.inMemory()
        try await store.save(makeMessage(id: "message", timestamp: 1, text: "hello"))

        let stats = try await store.databaseStats()

        #expect(stats.pageSizeBytes > 0)
        #expect(stats.pageCount > 0)
        #expect(stats.freePageCount >= 0)
        #expect(stats.usedBytes > 0)
    }

    @Test
    func zeroDatabaseCapMeansUnlimitedAndDeletesNothing() async throws {
        let store = try PersistenceStore.inMemory()
        try await store.save((0..<20).map { index in
            makeMessage(id: "message-\(index)", timestamp: Int64(index), text: "payload")
        })

        let deleted = try await store.enforceMaximumSize(megabytes: 0)

        #expect(deleted == 0)
        #expect(try await store.count() == 20)
    }

    @Test
    func positiveDatabaseCapDeletesOldestRowsUntilUsedPagesFit() async throws {
        let store = try PersistenceStore.inMemory()
        let payload = String(repeating: "x", count: 12_000)
        try await store.save((0..<220).map { index in
            makeMessage(
                id: String(format: "message-%04d", index),
                timestamp: Int64(index),
                text: payload
            )
        })
        let before = try await store.databaseStats()
        #expect(before.usedBytes > 1_024 * 1_024)

        let deleted = try await store.enforceMaximumSize(
            megabytes: 1,
            trimBatch: 25,
            maximumPasses: 20
        )
        let after = try await store.databaseStats()
        let remaining = try await store.recentMessages(channelID: "channel", limit: 220)

        #expect(deleted > 0)
        #expect(after.usedBytes <= 1_024 * 1_024)
        #expect(remaining.count < 220)
        if let first = remaining.first {
            #expect(first.timestampMilliseconds > 0)
        }
    }

    @Test
    func rejectsInvalidLimitsRetentionAndDatabaseSize() async throws {
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
        await #expect(throws: PersistenceStore.Error.invalidDatabaseSize) {
            try await store.enforceMaximumSize(megabytes: -1)
        }
        await #expect(throws: PersistenceStore.Error.invalidDatabaseSize) {
            try await store.enforceMaximumSize(megabytes: 1_025)
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
