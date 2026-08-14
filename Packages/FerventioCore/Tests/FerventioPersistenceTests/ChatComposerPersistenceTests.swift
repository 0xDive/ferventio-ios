import Testing
@testable import FerventioPersistence

struct ChatComposerPersistenceTests {
    @Test
    func draftsAreIsolatedPerChannelAndCanBeUpdatedOrDeleted() async throws {
        let store = try PersistenceStore.inMemory()

        try await store.saveDraft(
            channelID: "channel-a",
            text: "first draft",
            updatedAtMilliseconds: 10
        )
        try await store.saveDraft(
            channelID: "channel-b",
            text: "other draft",
            updatedAtMilliseconds: 20
        )
        try await store.saveDraft(
            channelID: "channel-a",
            text: "updated draft",
            updatedAtMilliseconds: 30
        )

        #expect(try await store.draft(channelID: "channel-a") == "updated draft")
        #expect(try await store.draft(channelID: "channel-b") == "other draft")

        try await store.deleteDraft(channelID: "channel-a")

        #expect(try await store.draft(channelID: "channel-a") == nil)
        #expect(try await store.draft(channelID: "channel-b") == "other draft")
    }

    @Test
    func sentHistoryIsNewestFirstBoundedAndChannelScoped() async throws {
        let store = try PersistenceStore.inMemory()

        for index in 0..<5 {
            try await store.recordSentMessage(
                SentChatMessageRecord(
                    id: "a-\(index)",
                    channelID: "channel-a",
                    text: "Message \(index)",
                    sentAtMilliseconds: Int64(index)
                ),
                keepingLatest: 3
            )
        }
        try await store.recordSentMessage(
            SentChatMessageRecord(
                id: "b-1",
                channelID: "channel-b",
                text: "Other channel",
                sentAtMilliseconds: 100
            ),
            keepingLatest: 3
        )

        let channelA = try await store.sentMessages(channelID: "channel-a", limit: 10)
        let channelB = try await store.sentMessages(channelID: "channel-b", limit: 10)

        #expect(channelA.map(\.id) == ["a-4", "a-3", "a-2"])
        #expect(channelA.map(\.text) == ["Message 4", "Message 3", "Message 2"])
        #expect(channelB.map(\.id) == ["b-1"])
    }

    @Test
    func sentHistoryUsesEntryIDAsStableTieBreaker() async throws {
        let store = try PersistenceStore.inMemory()

        for id in ["a", "c", "b"] {
            try await store.recordSentMessage(
                SentChatMessageRecord(
                    id: id,
                    channelID: "channel",
                    text: id,
                    sentAtMilliseconds: 100
                ),
                keepingLatest: 10
            )
        }

        let messages = try await store.sentMessages(channelID: "channel", limit: 10)

        #expect(messages.map(\.id) == ["c", "b", "a"])
    }

    @Test
    func sentHistoryRejectsNonPositiveLimits() async throws {
        let store = try PersistenceStore.inMemory()
        let entry = SentChatMessageRecord(
            id: "id",
            channelID: "channel",
            text: "hello",
            sentAtMilliseconds: 1
        )

        await #expect(throws: PersistenceStore.Error.invalidLimit) {
            try await store.recordSentMessage(entry, keepingLatest: 0)
        }
        await #expect(throws: PersistenceStore.Error.invalidLimit) {
            try await store.sentMessages(channelID: "channel", limit: 0)
        }
    }
}
