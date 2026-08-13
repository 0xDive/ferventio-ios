import Foundation

public enum InteractiveMutationKind: String, Codable, Equatable, Sendable {
    case createPoll
    case endPoll
    case archivePoll
    case createPrediction
    case lockPrediction
    case cancelPrediction
    case resolvePrediction
}

public enum InteractiveMutationFailureKind: String, Codable, Equatable, Sendable {
    case authentication
    case permission
    case rateLimited
    case network
    case server
    case conflict
    case unknown
}

public enum InteractiveMutationRecovery: String, Codable, Equatable, Sendable {
    case none
    case retry
    case refresh
}

public struct InteractiveMutationStatus: Codable, Equatable, Sendable {
    public let kind: InteractiveMutationKind
    public let inFlight: Bool
    public let failed: Bool
    public let failureKind: InteractiveMutationFailureKind?
    public let recovery: InteractiveMutationRecovery

    public init(
        kind: InteractiveMutationKind,
        inFlight: Bool = true,
        failed: Bool = false,
        failureKind: InteractiveMutationFailureKind? = nil,
        recovery: InteractiveMutationRecovery = .none
    ) {
        self.kind = kind
        self.inFlight = inFlight
        self.failed = failed
        self.failureKind = failureKind
        self.recovery = recovery
    }
}

public struct PollDraft: Codable, Equatable, Sendable {
    public let title: String
    public let choices: [String]
    public let durationSeconds: Int
    public let channelPointsVotingEnabled: Bool
    public let channelPointsPerVote: Int

    public init(
        title: String,
        choices: [String],
        durationSeconds: Int,
        channelPointsVotingEnabled: Bool = false,
        channelPointsPerVote: Int = 0
    ) {
        self.title = title
        self.choices = choices
        self.durationSeconds = durationSeconds
        self.channelPointsVotingEnabled = channelPointsVotingEnabled
        self.channelPointsPerVote = channelPointsPerVote
    }

    public var normalized: PollDraft {
        PollDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            choices: choices.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            durationSeconds: durationSeconds,
            channelPointsVotingEnabled: channelPointsVotingEnabled,
            channelPointsPerVote: channelPointsPerVote
        )
    }
}

public struct PredictionDraft: Codable, Equatable, Sendable {
    public let title: String
    public let outcomes: [String]
    public let predictionWindowSeconds: Int

    public init(
        title: String,
        outcomes: [String],
        predictionWindowSeconds: Int
    ) {
        self.title = title
        self.outcomes = outcomes
        self.predictionWindowSeconds = predictionWindowSeconds
    }

    public var normalized: PredictionDraft {
        PredictionDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            outcomes: outcomes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            predictionWindowSeconds: predictionWindowSeconds
        )
    }
}

public enum InteractiveDraftValidationIssue: String, Codable, Equatable, Sendable {
    case pollTitle
    case pollChoiceCount
    case pollChoiceTitle
    case pollChoiceDuplicate
    case pollDuration
    case pollChannelPointsPerVote
    case predictionTitle
    case predictionOutcomeCount
    case predictionOutcomeTitle
    case predictionOutcomeDuplicate
    case predictionWindow
}

public enum InteractiveOverlayDraftValidator {
    public static let pollTitleLength = 1...60
    public static let pollChoiceCount = 2...5
    public static let pollChoiceTitleLength = 1...25
    public static let pollDurationSeconds = 15...1_800
    public static let pollChannelPointsPerVote = 1...1_000_000
    public static let predictionTitleLength = 1...45
    public static let predictionOutcomeCount = 2...10
    public static let predictionOutcomeTitleLength = 1...25
    public static let predictionWindowSeconds = 30...1_800

    public static func validate(_ draft: PollDraft) -> [InteractiveDraftValidationIssue] {
        let draft = draft.normalized
        var issues: [InteractiveDraftValidationIssue] = []

        if !pollTitleLength.contains(draft.title.count) {
            issues.append(.pollTitle)
        }
        if !pollChoiceCount.contains(draft.choices.count) {
            issues.append(.pollChoiceCount)
        }
        if draft.choices.contains(where: { !pollChoiceTitleLength.contains($0.count) }) {
            issues.append(.pollChoiceTitle)
        }
        if normalizedUniqueCount(draft.choices) != draft.choices.count {
            issues.append(.pollChoiceDuplicate)
        }
        if !pollDurationSeconds.contains(draft.durationSeconds) {
            issues.append(.pollDuration)
        }
        if draft.channelPointsVotingEnabled,
           !pollChannelPointsPerVote.contains(draft.channelPointsPerVote) {
            issues.append(.pollChannelPointsPerVote)
        }
        return issues
    }

    public static func validate(_ draft: PredictionDraft) -> [InteractiveDraftValidationIssue] {
        let draft = draft.normalized
        var issues: [InteractiveDraftValidationIssue] = []

        if !predictionTitleLength.contains(draft.title.count) {
            issues.append(.predictionTitle)
        }
        if !predictionOutcomeCount.contains(draft.outcomes.count) {
            issues.append(.predictionOutcomeCount)
        }
        if draft.outcomes.contains(where: { !predictionOutcomeTitleLength.contains($0.count) }) {
            issues.append(.predictionOutcomeTitle)
        }
        if normalizedUniqueCount(draft.outcomes) != draft.outcomes.count {
            issues.append(.predictionOutcomeDuplicate)
        }
        if !predictionWindowSeconds.contains(draft.predictionWindowSeconds) {
            issues.append(.predictionWindow)
        }
        return issues
    }

    private static func normalizedUniqueCount(_ values: [String]) -> Int {
        Set(values.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }).count
    }
}

public enum PollEndStatus: String, Codable, Equatable, Sendable {
    case terminated = "TERMINATED"
    case archived = "ARCHIVED"
}

public enum PredictionEndStatus: String, Codable, Equatable, Sendable {
    case locked = "LOCKED"
    case canceled = "CANCELED"
    case resolved = "RESOLVED"
}
