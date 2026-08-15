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

public struct ChatPresentationRulePlan {
    fileprivate let compiledRules: [CompiledPresentationRule]
    fileprivate let needsFoldedMessageText: Bool
    fileprivate let needsFoldedAuthor: Bool

    public init(rules: [ChatPresentationRule]) {
        compiledRules = rules.compactMap(CompiledPresentationRule.init)
        needsFoldedMessageText = compiledRules.contains { rule in
            rule.target == .message && rule.matcher.requiresFoldedValue
        }
        needsFoldedAuthor = compiledRules.contains { rule in
            rule.target == .author && rule.matcher.requiresFoldedValue
        }
    }

    public func project(messages: [ChatMessage]) -> ChatPresentationRuleProjection {
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
            let foldedMessageText = needsFoldedMessageText
                ? ChatPresentationRuleEngine.folded(message.text)
                : nil
            let foldedAuthorLogin = needsFoldedAuthor
                ? ChatPresentationRuleEngine.folded(message.author.login)
                : nil
            let foldedAuthorDisplayName = needsFoldedAuthor
                ? ChatPresentationRuleEngine.folded(message.author.displayName)
                : nil

            var hidden = false
            var highlighted = false

            for rule in compiledRules {
                guard rule.matches(
                    message,
                    foldedMessageText: foldedMessageText,
                    foldedAuthorLogin: foldedAuthorLogin,
                    foldedAuthorDisplayName: foldedAuthorDisplayName
                ) else {
                    continue
                }

                switch rule.action {
                case .hide:
                    hidden = true
                case .highlight:
                    highlighted = true
                }

                if hidden {
                    break
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
}

public enum ChatPresentationRuleEngine {
    public static let maximumQueryLength = 256

    private static let planCache = ChatPresentationRulePlanCache()

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
        planCache.plan(for: rules).project(messages: messages)
    }

    fileprivate static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func compileRegex(
        query: String,
        caseSensitive: Bool
    ) -> NSRegularExpression? {
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        return try? NSRegularExpression(pattern: query, options: options)
    }

    fileprivate static func folded(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
    }
}

private final class ChatPresentationRulePlanCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedRules: [ChatPresentationRule]?
    private var cachedPlan: ChatPresentationRulePlan?

    func plan(for rules: [ChatPresentationRule]) -> ChatPresentationRulePlan {
        lock.lock()
        if cachedRules == rules, let cachedPlan {
            lock.unlock()
            return cachedPlan
        }
        lock.unlock()

        let plan = ChatPresentationRulePlan(rules: rules)

        lock.lock()
        cachedRules = rules
        cachedPlan = plan
        lock.unlock()
        return plan
    }
}

private struct CompiledPresentationRule {
    let action: ChatPresentationRuleAction
    let target: ChatPresentationRuleTarget
    let matcher: CompiledPresentationMatcher

    init?(_ rule: ChatPresentationRule) {
        guard rule.isEnabled else {
            return nil
        }

        let query = ChatPresentationRuleEngine.normalizedQuery(rule.query)
        guard !query.isEmpty,
              query.count <= ChatPresentationRuleEngine.maximumQueryLength else {
            return nil
        }

        action = rule.action
        target = rule.target

        switch rule.matchMode {
        case .contains:
            if rule.caseSensitive {
                matcher = .containsCaseSensitive(query)
            } else {
                matcher = .containsFolded(ChatPresentationRuleEngine.folded(query))
            }

        case .regex:
            guard let expression = ChatPresentationRuleEngine.compileRegex(
                query: query,
                caseSensitive: rule.caseSensitive
            ) else {
                return nil
            }
            matcher = .regex(expression)
        }
    }

    func matches(
        _ message: ChatMessage,
        foldedMessageText: String?,
        foldedAuthorLogin: String?,
        foldedAuthorDisplayName: String?
    ) -> Bool {
        switch target {
        case .message:
            matcher.matches(
                rawValue: message.text,
                foldedValue: foldedMessageText
            )
        case .author:
            matcher.matches(
                rawValue: message.author.login,
                foldedValue: foldedAuthorLogin
            ) || matcher.matches(
                rawValue: message.author.displayName,
                foldedValue: foldedAuthorDisplayName
            )
        }
    }
}

private enum CompiledPresentationMatcher {
    case containsCaseSensitive(String)
    case containsFolded(String)
    case regex(NSRegularExpression)

    var requiresFoldedValue: Bool {
        if case .containsFolded = self {
            return true
        }
        return false
    }

    func matches(rawValue: String, foldedValue: String?) -> Bool {
        switch self {
        case let .containsCaseSensitive(query):
            rawValue.contains(query)

        case let .containsFolded(query):
            (foldedValue ?? ChatPresentationRuleEngine.folded(rawValue)).contains(query)

        case let .regex(expression):
            expression.firstMatch(
                in: rawValue,
                options: [],
                range: NSRange(rawValue.startIndex..<rawValue.endIndex, in: rawValue)
            ) != nil
        }
    }
}
