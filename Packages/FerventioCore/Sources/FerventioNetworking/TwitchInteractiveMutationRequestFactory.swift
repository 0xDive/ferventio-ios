import Foundation
import FerventioDomain

public enum TwitchInteractiveMutationRequestFactory {
    public enum Error: Swift.Error, Equatable {
        case invalidArgument(String)
        case invalidPollDraft([InteractiveDraftValidationIssue])
        case invalidPredictionDraft([InteractiveDraftValidationIssue])
        case missingWinningOutcome
    }

    public static func makeCreatePollRequest(
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        draft: PollDraft
    ) throws -> URLRequest {
        let draft = draft.normalized
        let issues = InteractiveOverlayDraftValidator.validate(draft)
        guard issues.isEmpty else {
            throw Error.invalidPollDraft(issues)
        }

        var body: [String: Any] = [
            "broadcaster_id": try requireNonEmpty(broadcasterID, name: "broadcasterID"),
            "title": draft.title,
            "choices": draft.choices.map { ["title": $0] },
            "duration": draft.durationSeconds,
        ]
        if draft.channelPointsVotingEnabled {
            body["channel_points_voting_enabled"] = true
            body["channel_points_per_vote"] = draft.channelPointsPerVote
        }
        return try makeRequest(
            method: "POST",
            path: "/helix/polls",
            clientID: clientID,
            accessToken: accessToken,
            body: body
        )
    }

    public static func makeEndPollRequest(
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        pollID: String,
        status: PollEndStatus
    ) throws -> URLRequest {
        try makeRequest(
            method: "PATCH",
            path: "/helix/polls",
            clientID: clientID,
            accessToken: accessToken,
            body: [
                "broadcaster_id": try requireNonEmpty(broadcasterID, name: "broadcasterID"),
                "id": try requireNonEmpty(pollID, name: "pollID"),
                "status": status.rawValue,
            ]
        )
    }

    public static func makeCreatePredictionRequest(
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        draft: PredictionDraft
    ) throws -> URLRequest {
        let draft = draft.normalized
        let issues = InteractiveOverlayDraftValidator.validate(draft)
        guard issues.isEmpty else {
            throw Error.invalidPredictionDraft(issues)
        }

        return try makeRequest(
            method: "POST",
            path: "/helix/predictions",
            clientID: clientID,
            accessToken: accessToken,
            body: [
                "broadcaster_id": try requireNonEmpty(broadcasterID, name: "broadcasterID"),
                "title": draft.title,
                "outcomes": draft.outcomes.map { ["title": $0] },
                "prediction_window": draft.predictionWindowSeconds,
            ]
        )
    }

    public static func makeEndPredictionRequest(
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        predictionID: String,
        status: PredictionEndStatus,
        winningOutcomeID: String? = nil
    ) throws -> URLRequest {
        var body: [String: Any] = [
            "broadcaster_id": try requireNonEmpty(broadcasterID, name: "broadcasterID"),
            "id": try requireNonEmpty(predictionID, name: "predictionID"),
            "status": status.rawValue,
        ]
        if status == .resolved {
            guard let winningOutcomeID else {
                throw Error.missingWinningOutcome
            }
            body["winning_outcome_id"] = try requireNonEmpty(
                winningOutcomeID,
                name: "winningOutcomeID"
            )
        }
        return try makeRequest(
            method: "PATCH",
            path: "/helix/predictions",
            clientID: clientID,
            accessToken: accessToken,
            body: body
        )
    }

    private static func makeRequest(
        method: String,
        path: String,
        clientID: String,
        accessToken: String,
        body: [String: Any]
    ) throws -> URLRequest {
        let clientID = try requireNonEmpty(clientID, name: "clientID")
        let accessToken = try requireNonEmpty(accessToken, name: "accessToken")
        guard let url = URL(string: "https://api.twitch.tv\(path)") else {
            throw Error.invalidArgument("url")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func requireNonEmpty(_ value: String, name: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw Error.invalidArgument(name)
        }
        return value
    }
}