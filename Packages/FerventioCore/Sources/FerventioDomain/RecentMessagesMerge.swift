public struct RecentMessagesMergeResult: Equatable, Sendable {
    public let messages: [ChatMessage]
    public let addedMessages: [ChatMessage]

    public init(messages: [ChatMessage], addedMessages: [ChatMessage]) {
        self.messages = messages
        self.addedMessages = addedMessages
    }
}

public enum RecentMessagesMerge {
    public static func merge(
        existing: [ChatMessage],
        recent: [ChatMessage],
        limit: Int
    ) -> RecentMessagesMergeResult {
        guard limit > 0 else {
            return RecentMessagesMergeResult(messages: [], addedMessages: [])
        }

        let existingIDs = Set(existing.lazy.map(\.id).filter { !$0.isEmpty })
        var byID: [String: ChatMessage] = [:]

        // The remote snapshot is intentionally inserted first. Existing local
        // and live messages can contain richer EventSub/provider state and must
        // win whenever both sources contain the same Twitch message id.
        for message in recent where !message.id.isEmpty {
            byID[message.id] = message
        }
        for message in existing where !message.id.isEmpty {
            byID[message.id] = message
        }

        let sorted = byID.values.sorted { lhs, rhs in
            if lhs.timestampMilliseconds != rhs.timestampMilliseconds {
                return lhs.timestampMilliseconds < rhs.timestampMilliseconds
            }
            return lhs.id < rhs.id
        }
        let merged = Array(sorted.suffix(limit))
        let added = merged.filter { !existingIDs.contains($0.id) }

        return RecentMessagesMergeResult(
            messages: merged,
            addedMessages: added
        )
    }
}
