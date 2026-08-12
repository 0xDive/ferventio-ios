import FerventioDomain
import FerventioPersistence
import Testing
@testable import Ferventio

@MainActor
struct ChatHistoryPagerTests {
    @Test
    func disabledLocalHistoryDoesNotRequestOlderMessages() async {
        let history = PagingStubChatHistory(pages: [
            "channel": [[makeMessage(id: "older", timestamp: 10)]],
        ])
        let pager = ChatHistoryPager(
            history: history,
            preferences: preferences(localHistoryEnabled: false)
        )
        let visible = makeMessage(id: "visible", timestamp: 20)
        pager.reset(channelID: "channel")

        let anchor = await pager.loadOlderHistory(
            before: visible,
            excluding: [visible.id]
        )

        #expect(anchor == nil)
        #expect(await history.recordedRequests().isEmpty)
        #expect(pager.olderMessages.isEmpty)
        #expect(!pager.canLoadOlderHistory)
    }

    @Test
    func duplicateMessageIDsAreOmittedWhenPrepending() async {
        let duplicate = makeMessage(id: "duplicate", timestamp: 15)
        let older = makeMessage(id: "older", timestamp: 10)
        let visible = makeMessage(id: "visible", timestamp: 20)
        let history = PagingStubChatHistory(pages: [
            "channel": [[older, duplicate]],
        ])
        let pager = ChatHistoryPager(
            history: history,
            preferences: preferences()
        )
        pager.reset(channelID: "channel")

        _ = await pager.loadOlderHistory(
            before: visible,
            excluding: [visible.id, duplicate.id]
        )

        #expect(pager.olderMessages.map(\.id) == ["older"])
        #expect(pager.mergedMessages(with: [duplicate, visible]).map(\.id) == [
            "older",
            "duplicate",
            "visible",
        ])
    }

    @Test
    func channelSwitchResetsLoadedRowsAndPagingCursor() async {
        let aOlder = makeMessage(id: "a-older", channelID: "a", timestamp: 10)
        let bOlder = makeMessage(id: "b-older", channelID: "b", timestamp: 30)
        let history = PagingStubChatHistory(pages: [
            "a": [[aOlder]],
            "b": [[bOlder]],
        ])
        let pager = ChatHistoryPager(
            history: history,
            preferences: preferences()
        )

        pager.reset(channelID: "a")
        _ = await pager.loadOlderHistory(
            before: makeMessage(id: "a-visible", channelID: "a", timestamp: 20),
            excluding: []
        )
        #expect(pager.olderMessages.map(\.id) == ["a-older"])

        pager.reset(channelID: "b")
        #expect(pager.olderMessages.isEmpty)
        #expect(pager.canLoadOlderHistory)

        _ = await pager.loadOlderHistory(
            before: makeMessage(id: "b-visible", channelID: "b", timestamp: 40),
            excluding: []
        )

        #expect(pager.olderMessages.map(\.id) == ["b-older"])
        let requests = await history.recordedRequests()
        #expect(requests.map(\.channelID) == ["a", "b"])
        #expect(requests[1].cursor == ChatHistoryCursor(
            timestampMilliseconds: 40,
            messageID: "b-visible"
        ))
    }

    @Test
    func successfulPrependReturnsPreviousFirstMessageAsLogicalAnchor() async {
        let history = PagingStubChatHistory(pages: [
            "channel": [[
                makeMessage(id: "older-1", timestamp: 10),
                makeMessage(id: "older-2", timestamp: 11),
            ]],
        ])
        let pager = ChatHistoryPager(
            history: history,
            preferences: preferences()
        )
        let visible = makeMessage(id: "visible", timestamp: 20)
        pager.reset(channelID: "channel")

        let anchor = await pager.loadOlderHistory(
            before: visible,
            excluding: [visible.id]
        )

        #expect(anchor == "visible")
        #expect(pager.mergedMessages(with: [visible]).map(\.id) == [
            "older-1",
            "older-2",
            "visible",
        ])
    }

    @Test
    func pagingCursorAdvancesEvenWhenFetchedRowsAreDuplicates() async {
        let duplicate = makeMessage(id: "duplicate", timestamp: 10)
        let nextOlder = makeMessage(id: "next-older", timestamp: 5)
        let history = PagingStubChatHistory(pages: [
            "channel": [
                Array(repeating: duplicate, count: ChatHistoryPager.pageSize),
                [nextOlder],
            ],
        ])
        let pager = ChatHistoryPager(
            history: history,
            preferences: preferences()
        )
        let visible = makeMessage(id: "visible", timestamp: 20)
        pager.reset(channelID: "channel")

        _ = await pager.loadOlderHistory(
            before: visible,
            excluding: [duplicate.id, visible.id]
        )
        _ = await pager.loadOlderHistory(
            before: visible,
            excluding: [duplicate.id, visible.id]
        )

        let requests = await history.recordedRequests()
        #expect(requests.count == 2)
        #expect(requests[0].cursor.messageID == "visible")
        #expect(requests[1].cursor.messageID == "duplicate")
        #expect(pager.olderMessages.map(\.id) == ["next-older"])
    }

    private func preferences(localHistoryEnabled: Bool = true) -> ChatHistoryPreferences {
        ChatHistoryPreferences(
            recentMessagesEnabled: false,
            localHistoryEnabled: localHistoryEnabled,
            localHistoryLimit: 5_000,
            retentionDays: 0,
            maxDatabaseSizeMB: 0
        )
    }

    private func makeMessage(
        id: String,
        channelID: String = "channel",
        timestamp: Int64
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            channelID: channelID,
            channelLogin: channelID,
            author: ChatAuthor(
                id: "viewer",
                login: "viewer",
                displayName: "Viewer"
            ),
            text: id,
            timestamp: "2026-08-12T08:00:00Z",
            timestampMilliseconds: timestamp
        )
    }
}

private actor PagingStubChatHistory: ChatHistoryPersisting {
    struct Request: Equatable, Sendable {
        let channelID: String
        let cursor: ChatHistoryCursor
        let limit: Int
    }

    private var pages: [String: [[ChatMessage]]]
    private var requests: [Request] = []

    init(pages: [String: [[ChatMessage]]]) {
        self.pages = pages
    }

    func recentMessages(channelID: String, limit: Int) async -> [ChatMessage] {
        []
    }

    func olderMessages(
        channelID: String,
        before cursor: ChatHistoryCursor,
        limit: Int
    ) async -> [ChatMessage] {
        requests.append(Request(channelID: channelID, cursor: cursor, limit: limit))
        guard var channelPages = pages[channelID], !channelPages.isEmpty else {
            return []
        }
        let page = channelPages.removeFirst()
        pages[channelID] = channelPages
        return page
    }

    func enqueue(_ message: ChatMessage) async {}

    func maintain(
        channelID: String,
        retentionBoundaryMilliseconds: Int64?,
        keepingLatest: Int,
        maxDatabaseSizeMB: Int
    ) async {}

    func flush() async {}

    func recordedRequests() -> [Request] {
        requests
    }
}
