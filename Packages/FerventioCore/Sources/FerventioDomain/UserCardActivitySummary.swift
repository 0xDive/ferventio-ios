import Foundation

public struct UserCardActivitySummary: Equatable, Sendable {
    public let messageCount: Int
    public let deletedMessageCount: Int
    public let replyCount: Int
    public let actionCount: Int
    public let cheerCount: Int
    public let rewardCount: Int
    public let hasFirstMessage: Bool
    public let hasReturningChatter: Bool
    public let firstMessageTimestampMilliseconds: Int64?
    public let latestMessageTimestampMilliseconds: Int64?

    public init(
        messageCount: Int,
        deletedMessageCount: Int,
        replyCount: Int,
        actionCount: Int,
        cheerCount: Int,
        rewardCount: Int,
        hasFirstMessage: Bool,
        hasReturningChatter: Bool,
        firstMessageTimestampMilliseconds: Int64?,
        latestMessageTimestampMilliseconds: Int64?
    ) {
        self.messageCount = messageCount
        self.deletedMessageCount = deletedMessageCount
        self.replyCount = replyCount
        self.actionCount = actionCount
        self.cheerCount = cheerCount
        self.rewardCount = rewardCount
        self.hasFirstMessage = hasFirstMessage
        self.hasReturningChatter = hasReturningChatter
        self.firstMessageTimestampMilliseconds = firstMessageTimestampMilliseconds
        self.latestMessageTimestampMilliseconds = latestMessageTimestampMilliseconds
    }

    public var activitySpanMilliseconds: Int64? {
        guard let firstMessageTimestampMilliseconds,
              let latestMessageTimestampMilliseconds else {
            return nil
        }
        return max(0, latestMessageTimestampMilliseconds - firstMessageTimestampMilliseconds)
    }

    public static let empty = UserCardActivitySummary(
        messageCount: 0,
        deletedMessageCount: 0,
        replyCount: 0,
        actionCount: 0,
        cheerCount: 0,
        rewardCount: 0,
        hasFirstMessage: false,
        hasReturningChatter: false,
        firstMessageTimestampMilliseconds: nil,
        latestMessageTimestampMilliseconds: nil
    )
}

public extension UserCardContext {
    static func activitySummary(
        for author: ChatAuthor,
        in messages: [ChatMessage]
    ) -> UserCardActivitySummary {
        let matching = self.messages(for: author, in: messages)
        guard !matching.isEmpty else {
            return .empty
        }

        var deletedMessageCount = 0
        var replyCount = 0
        var actionCount = 0
        var cheerCount = 0
        var rewardCount = 0
        var hasFirstMessage = false
        var hasReturningChatter = false
        var firstTimestamp: Int64?
        var latestTimestamp: Int64?

        for message in matching {
            if message.flags.isDeleted {
                deletedMessageCount += 1
            }
            if message.reply != nil {
                replyCount += 1
            }
            if message.type == .action || message.flags.isAction {
                actionCount += 1
            }
            if message.type == .cheer {
                cheerCount += 1
            }
            if message.type == .reward || message.reward != nil {
                rewardCount += 1
            }
            hasFirstMessage = hasFirstMessage || message.flags.isFirstMessage
            hasReturningChatter = hasReturningChatter || message.flags.isReturningChatter
            firstTimestamp = min(firstTimestamp ?? message.timestampMilliseconds, message.timestampMilliseconds)
            latestTimestamp = max(latestTimestamp ?? message.timestampMilliseconds, message.timestampMilliseconds)
        }

        return UserCardActivitySummary(
            messageCount: matching.count,
            deletedMessageCount: deletedMessageCount,
            replyCount: replyCount,
            actionCount: actionCount,
            cheerCount: cheerCount,
            rewardCount: rewardCount,
            hasFirstMessage: hasFirstMessage,
            hasReturningChatter: hasReturningChatter,
            firstMessageTimestampMilliseconds: firstTimestamp,
            latestMessageTimestampMilliseconds: latestTimestamp
        )
    }
}
