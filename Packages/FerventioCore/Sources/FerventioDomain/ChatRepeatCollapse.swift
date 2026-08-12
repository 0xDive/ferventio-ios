import Foundation

public struct ChatRepeatCollapseConfig: Equatable, Sendable {
    public var enabled: Bool
    public var minimumRepeatCount: Int
    public var windowMilliseconds: Int64
    public var maximumParticipants: Int

    public init(
        enabled: Bool = true,
        minimumRepeatCount: Int = ChatRepeatCollapsePlanner.defaultMinimumRepeatCount,
        windowMilliseconds: Int64 = ChatRepeatCollapsePlanner.defaultWindowMilliseconds,
        maximumParticipants: Int = ChatRepeatCollapsePlanner.defaultMaximumParticipants
    ) {
        self.enabled = enabled
        self.minimumRepeatCount = minimumRepeatCount
        self.windowMilliseconds = windowMilliseconds
        self.maximumParticipants = maximumParticipants
    }
}

public struct ChatRepeatParticipant: Equatable, Sendable {
    public let userID: String
    public let displayName: String

    public init(userID: String, displayName: String) {
        self.userID = userID
        self.displayName = displayName
    }
}

public struct ChatRepeatGroup: Equatable, Sendable, Identifiable {
    public let id: String
    public let messages: [ChatMessage]
    public let participants: [ChatRepeatParticipant]
    public let totalParticipantCount: Int

    public var representative: ChatMessage {
        messages[0]
    }

    public var repeatCount: Int {
        messages.count
    }

    public var collapsedMessageCount: Int {
        max(0, repeatCount - 1)
    }

    public var omittedParticipantCount: Int {
        max(0, totalParticipantCount - participants.count)
    }

    public var memberIDs: [String] {
        messages.map(\.id)
    }

    init(
        messages: [ChatMessage],
        maximumParticipants: Int
    ) {
        precondition(!messages.isEmpty)
        self.messages = messages
        id = "repeat:\(messages[0].id)"

        var seen: Set<String> = []
        var distinct: [ChatRepeatParticipant] = []
        for message in messages {
            let fallback = message.author.displayName.lowercased()
            let key = message.author.id.isEmpty ? fallback : message.author.id
            guard seen.insert(key).inserted else {
                continue
            }
            distinct.append(
                ChatRepeatParticipant(
                    userID: message.author.id,
                    displayName: message.author.displayName
                )
            )
        }
        totalParticipantCount = distinct.count
        participants = Array(distinct.prefix(max(0, maximumParticipants)))
    }
}

public enum ChatRepeatCollapsePlanner {
    public static let defaultMinimumRepeatCount = 3
    public static let defaultWindowMilliseconds: Int64 = 10_000
    public static let defaultMaximumParticipants = 20

    private static let protectedBadgeSetIDs: Set<String> = [
        "broadcaster",
        "moderator",
        "vip",
    ]

    public static func collapse(
        _ messages: [ChatMessage],
        config: ChatRepeatCollapseConfig = ChatRepeatCollapseConfig()
    ) -> [ChatRepeatGroup] {
        guard !messages.isEmpty else {
            return []
        }

        let participantLimit = max(0, config.maximumParticipants)
        guard config.enabled else {
            return messages.map {
                ChatRepeatGroup(messages: [$0], maximumParticipants: participantLimit)
            }
        }

        let threshold = max(2, config.minimumRepeatCount)
        let window = max(0, config.windowMilliseconds)
        var result: [ChatRepeatGroup] = []
        result.reserveCapacity(messages.count)
        var run: [ChatMessage] = []
        run.reserveCapacity(4)
        var runKey: String?

        func flushRun() {
            guard !run.isEmpty else {
                return
            }

            if run.count >= threshold {
                result.append(
                    ChatRepeatGroup(
                        messages: run,
                        maximumParticipants: participantLimit
                    )
                )
            } else {
                result.append(contentsOf: run.map {
                    ChatRepeatGroup(
                        messages: [$0],
                        maximumParticipants: participantLimit
                    )
                })
            }
            run.removeAll(keepingCapacity: true)
            runKey = nil
        }

        for message in messages {
            guard let key = collapseKey(message) else {
                flushRun()
                result.append(
                    ChatRepeatGroup(
                        messages: [message],
                        maximumParticipants: participantLimit
                    )
                )
                continue
            }

            let previous = run.last
            let continuesRun = previous != nil
                && runKey == key
                && message.channelID == run[0].channelID
                && message.timestampMilliseconds >= previous!.timestampMilliseconds
                && message.timestampMilliseconds - run[0].timestampMilliseconds <= window

            if !continuesRun {
                flushRun()
            }
            if run.isEmpty {
                runKey = key
            }
            run.append(message)
        }

        flushRun()
        return result
    }

    private static func collapseKey(_ message: ChatMessage) -> String? {
        guard !message.id.isEmpty,
              message.type == .chat || message.type == .action,
              !message.flags.isDeleted,
              !message.flags.isSystem,
              message.reply == nil,
              message.reward == nil,
              message.outgoingState == .none || message.outgoingState == .sent,
              !message.author.badges.contains(where: {
                  protectedBadgeSetIDs.contains($0.setID)
              }) else {
            return nil
        }

        let normalized = normalize(message.text)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalize(_ text: String) -> String {
        text
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
