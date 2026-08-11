import Testing
@testable import FerventioDomain

struct RecentMessagesMergeTests {
    @Test
    func existingMessagesWinDuplicateIDs() {
        let recent = makeMessage(id: "shared", timestamp: 100, text: "remote")
        let existing = makeMessage(id: "shared", timestamp: 100, text: "richer local")

        let result = RecentMessagesMerge.merge(
            existing: [existing],
            recent: [recent],
            limit: 100
        )

        #expect(result.messages == [existing])
        #expect(result.addedMessages.isEmpty)
    }

    @Test
    func addsRemoteRowsSortsAndKeepsLatestLimit() {
        let existing = [
            makeMessage(id: "live", timestamp: 400, text: "live"),
        ]
        let recent = [
            makeMessage(id: "old", timestamp: 100, text: "old"),
            makeMessage(id: "middle", timestamp: 300, text: "middle"),
            makeMessage(id: "new", timestamp: 500, text: "new"),
        ]

        let result = RecentMessagesMerge.merge(
            existing: existing,
            recent: recent,
            limit: 3
        )

        #expect(result.messages.map(\.id) == ["middle", "live", "new"])
        #expect(result.addedMessages.map(\.id) == ["middle", "new"])
    }

    @Test
    func tiesAreSortedByMessageID() {
        let result = RecentMessagesMerge.merge(
            existing: [],
            recent: [
                makeMessage(id: "b", timestamp: 100, text: "b"),
                makeMessage(id: "a", timestamp: 100, text: "a"),
            ],
            limit: 10
        )

        #expect(result.messages.map(\.id) == ["a", "b"])
    }

    @Test
    func zeroLimitReturnsEmptyResult() {
        let result = RecentMessagesMerge.merge(
            existing: [makeMessage(id: "a", timestamp: 100, text: "a")],
            recent: [makeMessage(id: "b", timestamp: 200, text: "b")],
            limit: 0
        )

        #expect(result.messages.isEmpty)
        #expect(result.addedMessages.isEmpty)
    }

    private func makeMessage(
        id: String,
        timestamp: Int64,
        text: String
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            channelID: "channel",
            channelLogin: "channel",
            author: ChatAuthor(id: "user", login: "viewer", displayName: "Viewer"),
            text: text,
            timestamp: "2026-08-11T10:00:00Z",
            timestampMilliseconds: timestamp
        )
    }
}
