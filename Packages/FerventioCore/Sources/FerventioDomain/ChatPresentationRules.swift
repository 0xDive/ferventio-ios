import Foundation

public enum ChatPresentationRuleAction: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case hide
    case highlight
}

public enum ChatPresentationRuleTarget: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case message
    case author
}

public enum ChatPresentationRuleMatchMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case contains
    case regex
}

public struct ChatPresentationRule: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var isEnabled: Bool
    public var action: ChatPresentationRuleAction
    public var target: ChatPresentationRuleTarget
    public var matchMode: ChatPresentationRuleMatchMode
    public var query: String
    public var caseSensitive: Bool

    public init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        action: ChatPresentationRuleAction,
        target: ChatPresentationRuleTarget,
        matchMode: ChatPresentationRuleMatchMode = .contains,
        query: String,
        caseSensitive: Bool = false
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.action = action
        self.target = target
        self.matchMode = matchMode
        self.query = query
        self.caseSensitive = caseSensitive
    }
}

public enum ChatPresentationRuleValidationError: Equatable, Sendable {
    case emptyQuery
    case queryTooLong(maximumLength: Int)
    case invalidRegularExpression
}

public struct ChatPresentationRuleProjection: Equatable, Sendable {
    public let visibleMessages: [ChatMessage]
    public let highlightedMessageIDs: Set<String>

    public init(
        visibleMessages: [ChatMessage],
        highlightedMessageIDs: Set<String>
    ) {
        self.visibleMessages = visibleMessages
        self.highlightedMessageIDs = highlightedMessageIDs
    }

    public func isHighlighted(messageID: String) -> Bool {
        highlightedMessageIDs.contains(messageID)
    }
}

public enum ChatPresentationRuleEngine {
    public static let maximumQueryLength = 256

    public static func validate(
        _ rule: ChatPresentationRule
    ) -> ChatPresentationRuleValidationError? {
        let query = normalizedQuery(rule.query)
        guard !query.isEmpty else {
            return .emptyQuery
        }
        guard query.count <= maximumQueryLength else {
            return .queryTooLong(maximumLength: maximumQueryLength)
        }
        if rule.matchMode == .regex,
           compileRegex(query: query, caseSensitive: rule.caseSensitive) == nil {
            return .invalidRegularExpression
        }
        return nil
    }

    public static func project(
        messages: [ChatMessage],
        rules: [ChatPresentationRule]
    ) -> ChatPresentationRuleProjection {
        let compiledRules = rules.compactMap(CompiledRule.init)
        guard !compiledRules.isEmpty else {
            return ChatPresentationRuleProjection(
                visibleMessages: messages,
                highlightedMessageIDs: []
            )
        }

        var visibleMessages: [ChatMessage] = []
        visibleMessages.reserveCapacity(messages.count)
        var highlightedMessageIDs: Set<String> = []

        for message in messages {
            var hidden = false
            var highlighted = false

            for rule in compiledRules where rule.matches(message) {
                switch rule.action {
                case .hide:
                    hidden = true
                case .highlight:
                    highlighted = true
                }
            }

            guard !hidden else {
                continue
            }
            visibleMessages.append(message)
            if highlighted {
                highlightedMessageIDs.insert(message.id)
            }
        }

        return ChatPresentationRuleProjection(
            visibleMessages: visibleMessages,
            highlightedMessageIDs: highlightedMessageIDs
        )
    }

    private static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func compileRegex(
        query: String,
        caseSensitive: Bool
    ) -> NSRegularExpression? {
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        return try? NSRegularExpression(pattern: query, options: options)
    }

    private static func folded(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
    }

    private struct CompiledRule {
        let action: ChatPresentationRuleAction
        let target: ChatPresentationRuleTarget
        let matcher: (String) -> Bool

        init?(_ rule: ChatPresentationRule) {
            guard rule.isEnabled,
                  ChatPresentationRuleEngine.validate(rule) == nil else {
                return nil
            }
            action = rule.action
            target = rule.target

            let query = ChatPresentationRuleEngine.normalizedQuery(rule.query)
            switch rule.matchMode {
            case .contains:
                if rule.caseSensitive {
                    matcher = { value in value.contains(query) }
                } else {
                    let foldedQuery = ChatPresentationRuleEngine.folded(query)
                    matcher = { value in
                        ChatPresentationRuleEngine.folded(value).contains(foldedQuery)
                    }
                }

            case .regex:
                guard let expression = ChatPresentationRuleEngine.compileRegex(
                    query: query,
                    caseSensitive: rule.caseSensitive
                ) else {
                    return nil
                }
                matcher = { value in
                    let range = NSRange(value.startIndex..<value.endIndex, in: value)
                    return expression.firstMatch(
                        in: value,
                        options: [],
                        range: range
                    ) != nil
                }
            }
        }

        func matches(_ message: ChatMessage) -> Bool {
            switch target {
            case .message:
                matcher(message.text)
            case .author:
                matcher(message.author.login) || matcher(message.author.displayName)
            }
        }
    }
}
