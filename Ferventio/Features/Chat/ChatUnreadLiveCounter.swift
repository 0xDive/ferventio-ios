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

        let clampedCurrentCount = min(Self.maximumCount, max(0, currentCount))
        guard let previousLastMessageID,
              let currentLastMessageID = visibleMessages.last?.id,
              previousLastMessageID != currentLastMessageID else {
            return clampedCurrentCount
        }

        guard let previousIndex = visibleMessages.lastIndex(where: { $0.id == previousLastMessageID }) else {
            // A missing previous tail is ambiguous: it may have been deleted, hidden by
            // presentation rules, or replaced during a refresh. Do not manufacture an
            // unread message from a view-only change; later appends will be counted normally.
            return clampedCurrentCount
        }

        let nextIndex = visibleMessages.index(after: previousIndex)
        let appendedCount = visibleMessages.distance(from: nextIndex, to: visibleMessages.endIndex)
        return min(Self.maximumCount, clampedCurrentCount + appendedCount)
    }
}
