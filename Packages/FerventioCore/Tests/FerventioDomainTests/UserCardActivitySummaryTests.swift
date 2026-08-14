import Testing
@testable import FerventioDomain

struct UserCardActivitySummaryTests {
    @Test
    func summarizesCanonicalActivityForSelectedUser() {
        let author = ChatAuthor(id: "user", login: "viewer", displayName: "Viewer")
        let messages = [
            makeMessage(
                id: "first",
                author: author,
                timestamp: 1_000,
                type: .chat,
                flags: MessageFlags(isFirstMessage: true)
            ),
            makeMessage(
                id: "reply",
                author: author,
                timestamp: 3_000,
                reply: ReplyContext(parentMessageID: "parent"),
                type: .action,
                flags: MessageFlags(isDeleted: true, isAction: true, isReturningChatter: true)
            ),
            makeMessage(
                id: "cheer",
                author: author,
                timestamp: 5_000,
                type: .cheer
            ),
            makeMessage(
                id: "reward",
                author: author,
                timestamp: 7_000,
                reward: ChatReward(id: "reward"),
                type: .reward
            ),
            makeMessage(
                id: "other",
                author: ChatAuthor(id: "other", login: "other", displayName: "Other"),
                timestamp: 9_000,
                type: .reward,
                flags: MessageFlags(isDeleted: true)
            ),
        ]

        let summary = UserCardContext.activitySummary(for: author, in: messages)

        #expect(summary.messageCount == 4)
        #expect(summary.deletedMessageCount == 1)
        #expect(summary.replyCount == 1)
        #expect(summary.actionCount == 1)
        #expect(summary.cheerCount == 1)
        #expect(summary.rewardCount == 1)
        #expect(summary.hasFirstMessage)
        #expect(summary.hasReturningChatter)
        #expect(summary.firstMessageTimestampMilliseconds == 1_000)
        #expect(summary.latestMessageTimestampMilliseconds == 7_000)
        #expect(summary.activitySpanMilliseconds == 6_000)
    }

    @Test
    func returnsEmptySummaryWhenUserHasNoMessages() {
        let author = ChatAuthor(id: "user", login: "viewer", displayName: "Viewer")

        #expect(UserCardContext.activitySummary(for: author, in: []) == .empty)
    }

    @Test
    func activitySpanUsesChronologicalBoundsInsteadOfInputOrder() {
        let author = ChatAuthor(id: "user", login: "viewer", displayName: "Viewer")
        let messages = [
            makeMessage(id: "latest", author: author, timestamp: 9_000),
            makeMessage(id: "first", author: author, timestamp: 2_000),
            makeMessage(id: "middle", author: author, timestamp: 5_000),
        ]

        let summary = UserCardContext.activitySummary(for: author, in: messages)

        #expect(summary.firstMessageTimestampMilliseconds == 2_000)
        #expect(summary.latestMessageTimestampMilliseconds == 9_000)
        #expect(summary.activitySpanMilliseconds == 7_000)
    }

    private func makeMessage(
        id: String,
        author: ChatAuthor,
        timestamp: Int64,
        reply: ReplyContext? = nil,
        reward: ChatReward? = nil,
        type: ChatMessageType = .chat,
        flags: MessageFlags = MessageFlags()
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            channelID: "channel",
            channelLogin: "channel",
            author: author,
            text: id,
            timestamp: "2026-08-14T08:00:00Z",
            timestampMilliseconds: timestamp,
            reply: reply,
            reward: reward,
            type: type,
            flags: flags
        )
    }
}
