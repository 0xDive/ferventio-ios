import FerventioDomain
import Testing
@testable import Ferventio

struct ChatUnreadLiveCounterTests {
    @Test
    func countsSingleAppendedMessageWhileReadingHistory() {
        let messages = [
            makeMessage(id: "one"),
            makeMessage(id: "two"),
        ]

        let count = ChatUnreadLiveCounter.updatedCount(
            currentCount: 0,
            previousLastMessageID: "one",
            visibleMessages: messages,
            isFollowingLive: false
        )

        #expect(count == 1)
    }

    @Test
    func countsBatchedAppendsFromPreviousTail() {
        let messages = [
            makeMessage(id: "one"),
            makeMessage(id: "two"),
            makeMessage(id: "three"),
            makeMessage(id: "four"),
        ]

        let count = ChatUnreadLiveCounter.updatedCount(
            currentCount: 5,
            previousLastMessageID: "one",
            visibleMessages: messages,
            isFollowingLive: false
        )

        #expect(count == 8)
    }

    @Test
    func prependingOlderHistoryDoesNotIncreaseCountWhenTailIsUnchanged() {
        let messages = [
            makeMessage(id: "older"),
            makeMessage(id: "one"),
            makeMessage(id: "two"),
        ]

        let count = ChatUnreadLiveCounter.updatedCount(
            currentCount: 7,
            previousLastMessageID: "two",
            visibleMessages: messages,
            isFollowingLive: false
        )

        #expect(count == 7)
    }

    @Test
    func followingLiveResetsUnreadCount() {
        let count = ChatUnreadLiveCounter.updatedCount(
            currentCount: 42,
            previousLastMessageID: "one",
            visibleMessages: [makeMessage(id: "two")],
            isFollowingLive: true
        )

        #expect(count == 0)
    }

    @Test
    func missingPreviousTailAddsConservativeSingleUnreadAndCapsTotal() {
        let messages = [makeMessage(id: "new-tail")]

        let ordinary = ChatUnreadLiveCounter.updatedCount(
            currentCount: 3,
            previousLastMessageID: "trimmed-tail",
            visibleMessages: messages,
            isFollowingLive: false
        )
        let capped = ChatUnreadLiveCounter.updatedCount(
            currentCount: ChatUnreadLiveCounter.maximumCount,
            previousLastMessageID: "trimmed-tail",
            visibleMessages: messages,
            isFollowingLive: false
        )

        #expect(ordinary == 4)
        #expect(capped == ChatUnreadLiveCounter.maximumCount)
    }

    private func makeMessage(id: String) -> ChatMessage {
        ChatMessage(
            id: id,
            channelID: "channel",
            channelLogin: "channel",
            author: ChatAuthor(
                id: "viewer",
                login: "viewer",
                displayName: "Viewer"
            ),
            text: id,
            timestamp: "2026-08-15T17:00:00Z",
            timestampMilliseconds: 1_000
        )
    }
}
