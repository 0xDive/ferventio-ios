import Foundation
import FerventioDomain

public struct TwitchInteractiveAPIClient: Sendable {
    public enum Error: Swift.Error, Equatable {
        case invalidResponse
        case malformedResponse(String)
        case httpStatus(Int, String)
        case invalidArgument(String)
        case responseTooLarge
    }

    private static let maximumResponseBytes = 512 * 1_024

    private struct PollResponse: Decodable, Sendable {
        let data: [PollDTO]
    }

    private struct PollDTO: Decodable, Sendable {
        let id: String
        let broadcasterID: String
        let title: String
        let choices: [ChoiceDTO]
        let bitsVotingEnabled: Bool
        let bitsPerVote: Int
        let channelPointsVotingEnabled: Bool
        let channelPointsPerVote: Int
        let status: String
        let duration: Int
        let startedAt: String
        let endedAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case broadcasterID = "broadcaster_id"
            case title
            case choices
            case bitsVotingEnabled = "bits_voting_enabled"
            case bitsPerVote = "bits_per_vote"
            case channelPointsVotingEnabled = "channel_points_voting_enabled"
            case channelPointsPerVote = "channel_points_per_vote"
            case status
            case duration
            case startedAt = "started_at"
            case endedAt = "ended_at"
        }

        struct ChoiceDTO: Decodable, Sendable {
            let id: String
            let title: String
            let votes: Int
            let channelPointsVotes: Int
            let bitsVotes: Int

            enum CodingKeys: String, CodingKey {
                case id
                case title
                case votes
                case channelPointsVotes = "channel_points_votes"
                case bitsVotes = "bits_votes"
            }
        }
    }

    private struct PredictionResponse: Decodable, Sendable {
        let data: [PredictionDTO]
    }

    private struct PredictionDTO: Decodable, Sendable {
        let id: String
        let broadcasterID: String
        let title: String
        let winningOutcomeID: String?
        let outcomes: [OutcomeDTO]
        let predictionWindow: Int
        let status: String
        let createdAt: String
        let endedAt: String?
        let lockedAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case broadcasterID = "broadcaster_id"
            case title
            case winningOutcomeID = "winning_outcome_id"
            case outcomes
            case predictionWindow = "prediction_window"
            case status
            case createdAt = "created_at"
            case endedAt = "ended_at"
            case lockedAt = "locked_at"
        }

        struct OutcomeDTO: Decodable, Sendable {
            let id: String
            let title: String
            let users: Int
            let channelPoints: Int64
            let color: String

            enum CodingKeys: String, CodingKey {
                case id
                case title
                case users
                case channelPoints = "channel_points"
                case color
            }
        }
    }

    private struct ErrorResponse: Decodable, Sendable {
        let message: String?
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func loadActivePoll(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) async throws -> PollOverlay? {
        let request = try Self.makePollRequest(
            clientID: clientID,
            accessToken: accessToken,
            broadcasterID: broadcasterID
        )
        let response: PollResponse = try await perform(request)
        guard let poll = response.data.first(where: {
            PollStatus(twitchValue: $0.status) == .active
        }) else {
            return nil
        }
        return Self.map(poll)
    }

    public func loadActivePrediction(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) async throws -> PredictionOverlay? {
        let request = try Self.makePredictionRequest(
            clientID: clientID,
            accessToken: accessToken,
            broadcasterID: broadcasterID
        )
        let response: PredictionResponse = try await perform(request)
        guard let prediction = response.data.first(where: {
            let status = PredictionStatus(twitchValue: $0.status)
            return status == .active || status == .locked
        }) else {
            return nil
        }
        return Self.map(prediction)
    }

    static func makePollRequest(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) throws -> URLRequest {
        try makeRequest(
            path: "/helix/polls",
            clientID: clientID,
            accessToken: accessToken,
            broadcasterID: broadcasterID,
            pageSize: 20
        )
    }

    static func makePredictionRequest(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) throws -> URLRequest {
        try makeRequest(
            path: "/helix/predictions",
            clientID: clientID,
            accessToken: accessToken,
            broadcasterID: broadcasterID,
            pageSize: 20
        )
    }

    private static func makeRequest(
        path: String,
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        pageSize: Int
    ) throws -> URLRequest {
        let clientID = try requireNonEmpty(clientID, name: "clientID")
        let accessToken = try requireNonEmpty(accessToken, name: "accessToken")
        let broadcasterID = try requireNonEmpty(broadcasterID, name: "broadcasterID")

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.twitch.tv"
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "broadcaster_id", value: broadcasterID),
            URLQueryItem(name: "first", value: String(pageSize)),
        ]
        guard let url = components.url else {
            throw Error.invalidArgument("url")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        return request
    }

    private static func map(_ poll: PollDTO) -> PollOverlay {
        let startedAt = epochMilliseconds(poll.startedAt) ?? 0
        let endedAt = optionalEpochMilliseconds(poll.endedAt)
        let endsAt = PollStatus(twitchValue: poll.status) == .active
            ? startedAt + Int64(max(0, poll.duration)) * 1_000
            : endedAt
        return PollOverlay(
            id: poll.id,
            channelID: poll.broadcasterID,
            title: poll.title,
            choices: poll.choices.map {
                PollChoice(
                    id: $0.id,
                    title: $0.title,
                    votes: $0.votes,
                    channelPointsVotes: $0.channelPointsVotes,
                    bitsVotes: $0.bitsVotes
                )
            },
            status: PollStatus(twitchValue: poll.status),
            startedAtMilliseconds: startedAt,
            endsAtMilliseconds: endsAt,
            endedAtMilliseconds: endedAt,
            channelPointsVotingEnabled: poll.channelPointsVotingEnabled,
            channelPointsPerVote: poll.channelPointsPerVote,
            bitsVotingEnabled: poll.bitsVotingEnabled,
            bitsPerVote: poll.bitsPerVote,
            updatedAtMilliseconds: max(startedAt, endedAt ?? startedAt)
        )
    }

    private static func map(_ prediction: PredictionDTO) -> PredictionOverlay {
        let startedAt = epochMilliseconds(prediction.createdAt) ?? 0
        let endedAt = optionalEpochMilliseconds(prediction.endedAt)
        let lockedAt = optionalEpochMilliseconds(prediction.lockedAt)
        let locksAt = startedAt + Int64(max(0, prediction.predictionWindow)) * 1_000
        let updatedAt = max(max(startedAt, lockedAt ?? startedAt), endedAt ?? startedAt)
        return PredictionOverlay(
            id: prediction.id,
            channelID: prediction.broadcasterID,
            title: prediction.title,
            outcomes: prediction.outcomes.map {
                PredictionOutcome(
                    id: $0.id,
                    title: $0.title,
                    users: $0.users,
                    channelPoints: $0.channelPoints,
                    color: PredictionOutcomeColor(twitchValue: $0.color)
                )
            },
            status: PredictionStatus(twitchValue: prediction.status),
            startedAtMilliseconds: startedAt,
            locksAtMilliseconds: locksAt,
            lockedAtMilliseconds: lockedAt,
            endedAtMilliseconds: endedAt,
            winningOutcomeID: prediction.winningOutcomeID,
            updatedAtMilliseconds: updatedAt
        )
    }

    private static func requireNonEmpty(_ value: String, name: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw Error.invalidArgument(name)
        }
        return value
    }

    private func perform<Response: Decodable & Sendable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw Error.responseTooLarge
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw makeHTTPError(statusCode: httpResponse.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw Error.malformedResponse(String(describing: error))
        }
    }

    private func makeHTTPError(statusCode: Int, data: Data) -> Error {
        let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data).message)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = String(data: data.prefix(300), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .httpStatus(
            statusCode,
            message?.isEmpty == false ? message! : (fallback ?? "unknown Twitch error")
        )
    }

    private static func epochMilliseconds(_ raw: String) -> Int64? {
        guard let date = parseDate(raw) else {
            return nil
        }
        return Int64((date.timeIntervalSince1970 * 1_000).rounded(.towardZero))
    }

    private static func optionalEpochMilliseconds(_ raw: String?) -> Int64? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return epochMilliseconds(raw)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return fractional.date(from: raw) ?? standard.date(from: raw)
    }
}
