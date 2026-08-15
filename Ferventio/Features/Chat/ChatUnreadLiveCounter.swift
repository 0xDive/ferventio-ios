import FerventioDomain

struct ChatUnreadLiveCounter {
    static let maximumCount = 9_999

    static func updatedCount(
        currentCount: Int,
        previousLastMessageID: String?,
        visibleMessages: [ChatMessage],
        isFollowingLive: Bool
    ) -> Int {
        if isFollowingLive {
            return 0
        }
        guard let previousLastMessageID,
              let currentLastMessageID = visibleMessages.last?.id,
              previousLastMessageID != currentLastMessageID else {
            return min(Self.maximumCount, max(0, currentCount))
        }

        let appendedCount: Int
        if let previousIndex = visibleMessages.lastIndex(where: { $0.id == previousLastMessageID }) {
            let nextIndex = visibleMessages.index(after: previousIndex)
            appendedCount = visibleMessages.distance(from: nextIndex, to: visibleMessages.endIndex)
        } else {
            // If the previously visible tail was trimmed from the bounded live buffer,
            // still surface that something new arrived without guessing the full delta.
            appendedCount = 1
        }

        return min(
            Self.maximumCount,
            max(0, currentCount) + max(1, appendedCount)
        )
    }
}
