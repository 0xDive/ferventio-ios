import Foundation

public struct ChatRepeatGroup: Equatable, Sendable, Identifiable {
    public let id: String
    public let messages: [ChatMessage]

    public var representative: ChatMessage {
        messages[messages.index(before: messages.endIndex)]
    }

    public var repeatCount: Int {
        messages.count
    }

    public var memberIDs: [String] {
        messages.map(\.id)
    }

    init(messages: [ChatMessage]) {
        precondition(!messages.isEmpty)
        self.messages = messages
        id = "repeat:\(messages[0].id)"
    }
}

public enum ChatRepeatCollapsePlanner {
    public static let defaultMaximumGapMilliseconds: Int64 = 30_000

    public static func collapse(
        _ messages: [ChatMessage],
        maximumGapMilliseconds: Int64 = defaultMaximumGapMilliseconds
    ) -> [ChatRepeatGroup] {
        guard !messages.isEmpty else {
            return []
        }

        var result: [ChatRepeatGroup] = []
        result.reserveCapacity(messages.count)
        var current: [ChatMessage] = []
        current.reserveCapacity(4)

        func flushCurrent() {
            guard !current.isEmpty else {
                return
            }
            result.append(ChatRepeatGroup(messages: current))
            current.removeAll(keepingCapacity: true)
        }

        for message in messages {
            guard let previous = current.last else {
                current.append(message)
                continue
            }

            if canCollapse(
                previous,
                with: message,
                maximumGapMilliseconds: maximumGapMilliseconds
            ) {
                current.append(message)
            } else {
                flushCurrent()
                current.append(message)
            }
        }

        flushCurrent()
        return result
    }

    private static func canCollapse(
        _ previous: ChatMessage,
        with next: ChatMessage,
        maximumGapMilliseconds: Int64
    ) -> Bool {
        guard maximumGapMilliseconds >= 0,
              isEligible(previous),
              isEligible(next),
              previous.channelID == next.channelID,
              normalizedText(previous.text) == normalizedText(next.text),
              next.timestampMilliseconds >= previous.timestampMilliseconds,
              next.timestampMilliseconds - previous.timestampMilliseconds <= maximumGapMilliseconds else {
            return false
        }
        return true
    }

    private static func isEligible(_ message: ChatMessage) -> Bool {
        guard message.type == .chat,
              !message.flags.isDeleted,
              !message.flags.isSystem,
              !message.flags.isAction,
              message.reply == nil,
              message.reward == nil,
              message.outgoingState == .none || message.outgoingState == .sent else {
            return false
        }
        return !normalizedText(message.text).isEmpty
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
