import Foundation

public struct ChatBadge: Codable, Equatable, Sendable {
    public let setID: String
    public let id: String
    public let info: String?

    public init(setID: String, id: String, info: String? = nil) {
        self.setID = setID
        self.id = id
        self.info = info
    }
}

public struct ChatAuthor: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let login: String
    public let displayName: String
    public let color: String?
    public let badges: [ChatBadge]
    public let profileImageURL: String?

    public init(
        id: String,
        login: String,
        displayName: String,
        color: String? = nil,
        badges: [ChatBadge] = [],
        profileImageURL: String? = nil
    ) {
        self.id = id
        self.login = login
        self.displayName = displayName
        self.color = color
        self.badges = badges
        self.profileImageURL = profileImageURL
    }
}

public enum ChatFragment: Codable, Equatable, Sendable {
    case text(String)
    case twitchEmote(text: String, emoteID: String, emoteSetID: String?, ownerID: String?, formats: Set<String>)
    case thirdPartyEmote(text: String, emoteID: String, provider: String, animated: Bool, imageURL: String?, zeroWidth: Bool)
    case gif(text: String, gifID: String, url: String)
    case mention(text: String, userID: String, userLogin: String, userName: String)
    case cheermote(text: String, prefix: String, bits: Int, tier: Int)
    case link(text: String, url: String)
    case unknown(text: String, rawType: String)

    public var text: String {
        switch self {
        case let .text(text),
             let .twitchEmote(text, _, _, _, _),
             let .thirdPartyEmote(text, _, _, _, _, _),
             let .gif(text, _, _),
             let .mention(text, _, _, _),
             let .cheermote(text, _, _, _),
             let .link(text, _),
             let .unknown(text, _):
            return text
        }
    }

    public func replacingText(with value: String) -> ChatFragment {
        switch self {
        case .text:
            return .text(value)
        case let .twitchEmote(_, emoteID, emoteSetID, ownerID, formats):
            return .twitchEmote(text: value, emoteID: emoteID, emoteSetID: emoteSetID, ownerID: ownerID, formats: formats)
        case let .thirdPartyEmote(_, emoteID, provider, animated, imageURL, zeroWidth):
            return .thirdPartyEmote(text: value, emoteID: emoteID, provider: provider, animated: animated, imageURL: imageURL, zeroWidth: zeroWidth)
        case let .gif(_, gifID, url):
            return .gif(text: value, gifID: gifID, url: url)
        case let .mention(_, userID, userLogin, userName):
            return .mention(text: value, userID: userID, userLogin: userLogin, userName: userName)
        case let .cheermote(_, prefix, bits, tier):
            return .cheermote(text: value, prefix: prefix, bits: bits, tier: tier)
        case let .link(_, url):
            return .link(text: value, url: url)
        case let .unknown(_, rawType):
            return .unknown(text: value, rawType: rawType)
        }
    }
}

public struct ReplyContext: Codable, Equatable, Sendable {
    public let parentMessageID: String
    public let parentMessageBody: String?
    public let parentUserID: String?
    public let parentUserLogin: String?
    public let parentUserName: String?
    public let threadMessageID: String?
    public let threadUserID: String?
    public let threadUserLogin: String?
    public let threadUserName: String?

    public init(
        parentMessageID: String,
        parentMessageBody: String? = nil,
        parentUserID: String? = nil,
        parentUserLogin: String? = nil,
        parentUserName: String? = nil,
        threadMessageID: String? = nil,
        threadUserID: String? = nil,
        threadUserLogin: String? = nil,
        threadUserName: String? = nil
    ) {
        self.parentMessageID = parentMessageID
        self.parentMessageBody = parentMessageBody
        self.parentUserID = parentUserID
        self.parentUserLogin = parentUserLogin
        self.parentUserName = parentUserName
        self.threadMessageID = threadMessageID
        self.threadUserID = threadUserID
        self.threadUserLogin = threadUserLogin
        self.threadUserName = threadUserName
    }
}

public enum ChatMessageType: String, Codable, Equatable, Sendable {
    case chat
    case action
    case system
    case announcement
    case subscription
    case resubscription
    case giftSubscription
    case raid
    case cheer
    case reward
    case moderation
    case unknown
}

public struct MessageFlags: Codable, Equatable, Sendable {
    public let isDeleted: Bool
    public let isSystem: Bool
    public let isAction: Bool
    public let isFirstMessage: Bool
    public let isReturningChatter: Bool

    public init(
        isDeleted: Bool = false,
        isSystem: Bool = false,
        isAction: Bool = false,
        isFirstMessage: Bool = false,
        isReturningChatter: Bool = false
    ) {
        self.isDeleted = isDeleted
        self.isSystem = isSystem
        self.isAction = isAction
        self.isFirstMessage = isFirstMessage
        self.isReturningChatter = isReturningChatter
    }
}

public enum OutgoingMessageState: String, Codable, Equatable, Sendable {
    case none
    case sending
    case sent
    case failed
}

public struct ChatReward: Codable, Equatable, Sendable {
    public let id: String?
    public let title: String?
    public let cost: Int64?

    public init(id: String? = nil, title: String? = nil, cost: Int64? = nil) {
        self.id = id
        self.title = title
        self.cost = cost
    }
}

public struct ChatMessage: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let eventSubMessageID: String?
    public let channelID: String
    public let channelLogin: String
    public let author: ChatAuthor
    public let text: String
    public let fragments: [ChatFragment]
    public let timestamp: String
    public let timestampMilliseconds: Int64
    public let reply: ReplyContext?
    public let reward: ChatReward?
    public let type: ChatMessageType
    public let flags: MessageFlags
    public let outgoingState: OutgoingMessageState
    public let outgoingError: String?
    public let clientNonce: String?
    public let serverMessageID: String?

    public init(
        id: String,
        eventSubMessageID: String? = nil,
        channelID: String,
        channelLogin: String,
        author: ChatAuthor,
        text: String,
        fragments: [ChatFragment]? = nil,
        timestamp: String,
        timestampMilliseconds: Int64,
        reply: ReplyContext? = nil,
        reward: ChatReward? = nil,
        type: ChatMessageType = .chat,
        flags: MessageFlags = MessageFlags(),
        outgoingState: OutgoingMessageState = .none,
        outgoingError: String? = nil,
        clientNonce: String? = nil,
        serverMessageID: String? = nil
    ) {
        self.id = id
        self.eventSubMessageID = eventSubMessageID
        self.channelID = channelID
        self.channelLogin = channelLogin
        self.author = author
        self.text = text
        self.fragments = fragments ?? [.text(text)]
        self.timestamp = timestamp
        self.timestampMilliseconds = timestampMilliseconds
        self.reply = reply
        self.reward = reward
        self.type = type
        self.flags = flags
        self.outgoingState = outgoingState
        self.outgoingError = outgoingError
        self.clientNonce = clientNonce
        self.serverMessageID = serverMessageID
    }
}
