import Foundation

public enum PollStatus: String, Codable, Equatable, Sendable {
    case active
    case completed
    case terminated
    case archived
    case moderated
    case invalid
    case unknown

    public init(twitchValue: String?) {
        switch twitchValue?.lowercased() {
        case "active": self = .active
        case "completed": self = .completed
        case "terminated": self = .terminated
        case "archived": self = .archived
        case "moderated": self = .moderated
        case "invalid": self = .invalid
        default: self = .unknown
        }
    }
}

public struct PollChoice: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let votes: Int
    public let channelPointsVotes: Int
    public let bitsVotes: Int

    public init(
        id: String,
        title: String,
        votes: Int = 0,
        channelPointsVotes: Int = 0,
        bitsVotes: Int = 0
    ) {
        self.id = id
        self.title = title
        self.votes = votes
        self.channelPointsVotes = channelPointsVotes
        self.bitsVotes = bitsVotes
    }
}

public struct PollOverlay: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let channelID: String
    public let title: String
    public let choices: [PollChoice]
    public let status: PollStatus
    public let startedAtMilliseconds: Int64
    public let endsAtMilliseconds: Int64?
    public let endedAtMilliseconds: Int64?
    public let channelPointsVotingEnabled: Bool
    public let channelPointsPerVote: Int
    public let bitsVotingEnabled: Bool
    public let bitsPerVote: Int
    public let updatedAtMilliseconds: Int64

    public init(
        id: String,
        channelID: String,
        title: String,
        choices: [PollChoice],
        status: PollStatus,
        startedAtMilliseconds: Int64,
        endsAtMilliseconds: Int64? = nil,
        endedAtMilliseconds: Int64? = nil,
        channelPointsVotingEnabled: Bool = false,
        channelPointsPerVote: Int = 0,
        bitsVotingEnabled: Bool = false,
        bitsPerVote: Int = 0,
        updatedAtMilliseconds: Int64
    ) {
        self.id = id
        self.channelID = channelID
        self.title = title
        self.choices = choices
        self.status = status
        self.startedAtMilliseconds = startedAtMilliseconds
        self.endsAtMilliseconds = endsAtMilliseconds
        self.endedAtMilliseconds = endedAtMilliseconds
        self.channelPointsVotingEnabled = channelPointsVotingEnabled
        self.channelPointsPerVote = channelPointsPerVote
        self.bitsVotingEnabled = bitsVotingEnabled
        self.bitsPerVote = bitsPerVote
        self.updatedAtMilliseconds = updatedAtMilliseconds
    }

    public var totalVotes: Int {
        choices.reduce(0) { $0 + $1.votes }
    }

    public var isActive: Bool {
        status == .active
    }

    public func voteShare(choiceID: String) -> Double {
        guard totalVotes > 0,
              let votes = choices.first(where: { $0.id == choiceID })?.votes else {
            return 0
        }
        return Double(votes) / Double(totalVotes)
    }
}

public enum PredictionStatus: String, Codable, Equatable, Sendable {
    case active
    case locked
    case resolved
    case canceled
    case unknown

    public init(twitchValue: String?) {
        switch twitchValue?.lowercased() {
        case "active": self = .active
        case "locked": self = .locked
        case "resolved": self = .resolved
        case "canceled", "cancelled": self = .canceled
        default: self = .unknown
        }
    }
}

public enum PredictionOutcomeColor: String, Codable, Equatable, Sendable {
    case blue
    case pink
    case unknown

    public init(twitchValue: String?) {
        switch twitchValue?.lowercased() {
        case "blue": self = .blue
        case "pink": self = .pink
        default: self = .unknown
        }
    }
}

public struct PredictionOutcome: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let users: Int
    public let channelPoints: Int64
    public let color: PredictionOutcomeColor

    public init(
        id: String,
        title: String,
        users: Int = 0,
        channelPoints: Int64 = 0,
        color: PredictionOutcomeColor = .unknown
    ) {
        self.id = id
        self.title = title
        self.users = users
        self.channelPoints = channelPoints
        self.color = color
    }
}

public struct PredictionOverlay: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let channelID: String
    public let title: String
    public let outcomes: [PredictionOutcome]
    public let status: PredictionStatus
    public let startedAtMilliseconds: Int64
    public let locksAtMilliseconds: Int64?
    public let lockedAtMilliseconds: Int64?
    public let endedAtMilliseconds: Int64?
    public let winningOutcomeID: String?
    public let updatedAtMilliseconds: Int64

    public init(
        id: String,
        channelID: String,
        title: String,
        outcomes: [PredictionOutcome],
        status: PredictionStatus,
        startedAtMilliseconds: Int64,
        locksAtMilliseconds: Int64? = nil,
        lockedAtMilliseconds: Int64? = nil,
        endedAtMilliseconds: Int64? = nil,
        winningOutcomeID: String? = nil,
        updatedAtMilliseconds: Int64
    ) {
        self.id = id
        self.channelID = channelID
        self.title = title
        self.outcomes = outcomes
        self.status = status
        self.startedAtMilliseconds = startedAtMilliseconds
        self.locksAtMilliseconds = locksAtMilliseconds
        self.lockedAtMilliseconds = lockedAtMilliseconds
        self.endedAtMilliseconds = endedAtMilliseconds
        self.winningOutcomeID = winningOutcomeID
        self.updatedAtMilliseconds = updatedAtMilliseconds
    }

    public var totalUsers: Int {
        outcomes.reduce(0) { $0 + $1.users }
    }

    public var totalChannelPoints: Int64 {
        outcomes.reduce(0) { $0 + $1.channelPoints }
    }

    public var isActive: Bool {
        status == .active
    }

    public var isLocked: Bool {
        status == .locked
    }

    public func pointsShare(outcomeID: String) -> Double {
        guard totalChannelPoints > 0,
              let points = outcomes.first(where: { $0.id == outcomeID })?.channelPoints else {
            return 0
        }
        return Double(points) / Double(totalChannelPoints)
    }
}

public struct InteractiveChatOverlayState: Equatable, Sendable {
    public var pollsByChannel: [String: PollOverlay]
    public var predictionsByChannel: [String: PredictionOverlay]

    public init(
        pollsByChannel: [String: PollOverlay] = [:],
        predictionsByChannel: [String: PredictionOverlay] = [:]
    ) {
        self.pollsByChannel = pollsByChannel
        self.predictionsByChannel = predictionsByChannel
    }
}

public enum InteractiveChatOverlayEvent: Equatable, Sendable {
    case pollSnapshot(PollOverlay)
    case predictionSnapshot(PredictionOverlay)
    case clearChannel(String)
}

public enum InteractiveChatOverlayReducer {
    public static func reduce(
        state: InteractiveChatOverlayState,
        event: InteractiveChatOverlayEvent
    ) -> InteractiveChatOverlayState {
        var state = state
        switch event {
        case let .pollSnapshot(incoming):
            if let existing = state.pollsByChannel[incoming.channelID],
               incoming.updatedAtMilliseconds < existing.updatedAtMilliseconds {
                return state
            }
            state.pollsByChannel[incoming.channelID] = incoming

        case let .predictionSnapshot(incoming):
            if let existing = state.predictionsByChannel[incoming.channelID],
               incoming.updatedAtMilliseconds < existing.updatedAtMilliseconds {
                return state
            }
            state.predictionsByChannel[incoming.channelID] = incoming

        case let .clearChannel(channelID):
            state.pollsByChannel.removeValue(forKey: channelID)
            state.predictionsByChannel.removeValue(forKey: channelID)
        }
        return state
    }
}
