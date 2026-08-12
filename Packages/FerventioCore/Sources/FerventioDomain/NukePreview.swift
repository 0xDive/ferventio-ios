import Foundation

public enum NukeMatchMode: String, Codable, Equatable, Hashable, Sendable {
    case plainText
    case regex
}

public struct NukePreviewConfig: Equatable, Sendable {
    public var query: String
    public var matchMode: NukeMatchMode
    public var caseSensitive: Bool
    public var windowMilliseconds: Int64
    public var excludeBroadcaster: Bool
    public var excludeModerators: Bool
    public var excludeVIPs: Bool
    public var excludedUserIDs: Set<String>
    public var maximumSamples: Int

    public init(
        query: String,
        matchMode: NukeMatchMode = .plainText,
        caseSensitive: Bool = false,
        windowMilliseconds: Int64 = 30_000,
        excludeBroadcaster: Bool = true,
        excludeModerators: Bool = true,
        excludeVIPs: Bool = true,
        excludedUserIDs: Set<String> = [],
        maximumSamples: Int = 25
    ) {
        self.query = query
        self.matchMode = matchMode
        self.caseSensitive = caseSensitive
        self.windowMilliseconds = windowMilliseconds
        self.excludeBroadcaster = excludeBroadcaster
        self.excludeModerators = excludeModerators
        self.excludeVIPs = excludeVIPs
        self.excludedUserIDs = excludedUserIDs
        self.maximumSamples = maximumSamples
    }
}

public struct NukePreviewSample: Equatable, Sendable, Identifiable {
    public let messageID: String
    public let userID: String
    public let userLogin: String
    public let userDisplayName: String
    public let text: String
    public let timestampMilliseconds: Int64

    public var id: String { messageID }

    public init(
        messageID: String,
        userID: String,
        userLogin: String,
        userDisplayName: String,
        text: String,
        timestampMilliseconds: Int64
    ) {
        self.messageID = messageID
        self.userID = userID
        self.userLogin = userLogin
        self.userDisplayName = userDisplayName
        self.text = text
        self.timestampMilliseconds = timestampMilliseconds
    }
}

public struct NukeTargetUser: Equatable, Sendable, Identifiable {
    public let userID: String
    public let userLogin: String
    public let userDisplayName: String

    public var id: String {
        userID.isEmpty ? "login:\(userLogin.lowercased())" : userID
    }

    public init(userID: String, userLogin: String, userDisplayName: String) {
        self.userID = userID
        self.userLogin = userLogin
        self.userDisplayName = userDisplayName
    }
}

public struct NukePreview: Equatable, Sendable {
    public let matchedMessageCount: Int
    public let matchedUserCount: Int
    public let excludedMatchCount: Int
    public let scannedMessageCount: Int
    public let matchedUserIDs: Set<String>
    public let matchedUsers: [NukeTargetUser]
    public let matchedMessageIDs: [String]
    public let samples: [NukePreviewSample]

    public init(
        matchedMessageCount: Int,
        matchedUserCount: Int,
        excludedMatchCount: Int,
        scannedMessageCount: Int,
        matchedUserIDs: Set<String>,
        matchedUsers: [NukeTargetUser],
        matchedMessageIDs: [String],
        samples: [NukePreviewSample]
    ) {
        self.matchedMessageCount = matchedMessageCount
        self.matchedUserCount = matchedUserCount
        self.excludedMatchCount = excludedMatchCount
        self.scannedMessageCount = scannedMessageCount
        self.matchedUserIDs = matchedUserIDs
        self.matchedUsers = matchedUsers
        self.matchedMessageIDs = matchedMessageIDs
        self.samples = samples
    }
}

public struct NukeExecutionPlan: Equatable, Sendable {
    public let query: String
    public let matchMode: NukeMatchMode
    public let caseSensitive: Bool
    public let previewedAtMilliseconds: Int64
    public let targetUsers: [NukeTargetUser]
    public let targetMessageIDs: [String]

    public var targetUserCount: Int { targetUsers.count }
    public var targetMessageCount: Int { targetMessageIDs.count }

    public init(
        query: String,
        matchMode: NukeMatchMode,
        caseSensitive: Bool,
        previewedAtMilliseconds: Int64,
        targetUsers: [NukeTargetUser],
        targetMessageIDs: [String]
    ) {
        self.query = query
        self.matchMode = matchMode
        self.caseSensitive = caseSensitive
        self.previewedAtMilliseconds = previewedAtMilliseconds
        self.targetUsers = targetUsers
        self.targetMessageIDs = targetMessageIDs
    }
}

public enum NukePreviewError: Equatable, Sendable {
    case emptyQuery
    case queryTooLong(maximumLength: Int)
    case invalidRegularExpression
}

public enum NukePreviewResult: Equatable, Sendable {
    case success(NukePreview)
    case failure(NukePreviewError)

    public var preview: NukePreview? {
        guard case let .success(preview) = self else { return nil }
        return preview
    }
}

public enum NukeExecutionPlanError: Equatable, Sendable {
    case noTargetUsers
    case inconsistentMessageTargetSet
    case inconsistentUserTargetSet
}

public enum NukeExecutionPlanResult: Equatable, Sendable {
    case success(NukeExecutionPlan)
    case failure(NukeExecutionPlanError)

    public var plan: NukeExecutionPlan? {
        guard case let .success(plan) = self else { return nil }
        return plan
    }
}

public enum NukePreviewPlanner {
    public static let maximumQueryLength = 256

    public static func build(
        messages: [ChatMessage],
        config: NukePreviewConfig,
        nowMilliseconds: Int64
    ) -> NukePreviewResult {
        let query = config.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return .failure(.emptyQuery)
        }
        guard query.count <= maximumQueryLength else {
            return .failure(.queryTooLong(maximumLength: maximumQueryLength))
        }

        let matcher: (String) -> Bool
        switch config.matchMode {
        case .plainText:
            matcher = plainTextMatcher(query: query, caseSensitive: config.caseSensitive)
        case .regex:
            guard let regexMatcher = regexMatcher(
                query: query,
                caseSensitive: config.caseSensitive
            ) else {
                return .failure(.invalidRegularExpression)
            }
            matcher = regexMatcher
        }

        let window = max(Int64(0), config.windowMilliseconds)
        let cutoff = nowMilliseconds - window
        let maximumSamples = max(0, config.maximumSamples)
        var matchedUsersByKey: [String: NukeTargetUser] = [:]
        var matchedUserKeys: [String] = []
        var matchedMessageIDs: [String] = []
        var samples: [NukePreviewSample] = []
        var matchedMessages = 0
        var excludedMatches = 0
        var scannedMessages = 0

        for message in messages {
            guard isScannable(
                message,
                cutoffMilliseconds: cutoff,
                nowMilliseconds: nowMilliseconds
            ) else {
                continue
            }
            scannedMessages += 1
            guard matcher(message.text) else {
                continue
            }
            if isExcluded(message, config: config) {
                excludedMatches += 1
                continue
            }

            matchedMessages += 1
            let userKey = message.author.id.isEmpty
                ? "login:\(message.author.login.lowercased())"
                : message.author.id
            if matchedUsersByKey[userKey] == nil {
                matchedUsersByKey[userKey] = NukeTargetUser(
                    userID: message.author.id,
                    userLogin: message.author.login,
                    userDisplayName: message.author.displayName
                )
                matchedUserKeys.append(userKey)
            }
            matchedMessageIDs.append(message.id)
            if samples.count < maximumSamples {
                samples.append(
                    NukePreviewSample(
                        messageID: message.id,
                        userID: message.author.id,
                        userLogin: message.author.login,
                        userDisplayName: message.author.displayName,
                        text: message.text,
                        timestampMilliseconds: message.timestampMilliseconds
                    )
                )
            }
        }

        let matchedUsers = matchedUserKeys.compactMap { matchedUsersByKey[$0] }
        return .success(
            NukePreview(
                matchedMessageCount: matchedMessages,
                matchedUserCount: matchedUsers.count,
                excludedMatchCount: excludedMatches,
                scannedMessageCount: scannedMessages,
                matchedUserIDs: Set(matchedUserKeys),
                matchedUsers: matchedUsers,
                matchedMessageIDs: matchedMessageIDs,
                samples: samples
            )
        )
    }

    private static func isScannable(
        _ message: ChatMessage,
        cutoffMilliseconds: Int64,
        nowMilliseconds: Int64
    ) -> Bool {
        guard !message.id.isEmpty,
              message.type == .chat || message.type == .action,
              !message.flags.isDeleted,
              !message.flags.isSystem else {
            return false
        }
        return message.timestampMilliseconds >= cutoffMilliseconds
            && message.timestampMilliseconds <= nowMilliseconds
    }

    private static func isExcluded(
        _ message: ChatMessage,
        config: NukePreviewConfig
    ) -> Bool {
        if config.excludedUserIDs.contains(message.author.id) {
            return true
        }
        let badgeSetIDs = Set(message.author.badges.map(\.setID))
        return (config.excludeBroadcaster && badgeSetIDs.contains("broadcaster"))
            || (config.excludeModerators && badgeSetIDs.contains("moderator"))
            || (config.excludeVIPs && badgeSetIDs.contains("vip"))
    }

    private static func plainTextMatcher(
        query: String,
        caseSensitive: Bool
    ) -> (String) -> Bool {
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        return { text in
            text.range(of: query, options: options) != nil
        }
    }

    private static func regexMatcher(
        query: String,
        caseSensitive: Bool
    ) -> ((String) -> Bool)? {
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: query, options: options) else {
            return nil
        }
        return { text in
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }
}

public enum NukeExecutionPlanner {
    public static func freeze(
        config: NukePreviewConfig,
        preview: NukePreview,
        previewedAtMilliseconds: Int64
    ) -> NukeExecutionPlanResult {
        guard preview.matchedUserCount > 0, !preview.matchedUsers.isEmpty else {
            return .failure(.noTargetUsers)
        }
        guard preview.matchedMessageCount == preview.matchedMessageIDs.count else {
            return .failure(.inconsistentMessageTargetSet)
        }
        guard preview.matchedUserCount == preview.matchedUsers.count else {
            return .failure(.inconsistentUserTargetSet)
        }
        return .success(
            NukeExecutionPlan(
                query: config.query.trimmingCharacters(in: .whitespacesAndNewlines),
                matchMode: config.matchMode,
                caseSensitive: config.caseSensitive,
                previewedAtMilliseconds: previewedAtMilliseconds,
                targetUsers: preview.matchedUsers,
                targetMessageIDs: preview.matchedMessageIDs
            )
        )
    }
}
