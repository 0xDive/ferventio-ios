import Foundation
import FerventioDomain

public struct TwitchInteractiveMutationAPIClient: Sendable {
    public enum Error: Swift.Error, Equatable {
        case invalidResponse
        case httpStatus(Int, String)
        case responseTooLarge
    }

    private static let maximumResponseBytes = 512 * 1_024
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func createPoll(
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        draft: PollDraft
    ) async throws {
        try await perform(
            TwitchInteractiveMutationRequestFactory.makeCreatePollRequest(
                clientID: clientID,
                accessToken: accessToken,
                broadcasterID: broadcasterID,
                draft: draft
            )
        )
    }

    public func endPoll(
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        pollID: String,
        status: PollEndStatus
    ) async throws {
        try await perform(
            TwitchInteractiveMutationRequestFactory.makeEndPollRequest(
                clientID: clientID,
                accessToken: accessToken,
                broadcasterID: broadcasterID,
                pollID: pollID,
                status: status
            )
        )
    }

    public func createPrediction(
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        draft: PredictionDraft
    ) async throws {
        try await perform(
            TwitchInteractiveMutationRequestFactory.makeCreatePredictionRequest(
                clientID: clientID,
                accessToken: accessToken,
                broadcasterID: broadcasterID,
                draft: draft
            )
        )
    }

    public func endPrediction(
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        predictionID: String,
        status: PredictionEndStatus,
        winningOutcomeID: String? = nil
    ) async throws {
        try await perform(
            TwitchInteractiveMutationRequestFactory.makeEndPredictionRequest(
                clientID: clientID,
                accessToken: accessToken,
                broadcasterID: broadcasterID,
                predictionID: predictionID,
                status: status,
                winningOutcomeID: winningOutcomeID
            )
        )
    }

    private func perform(_ request: URLRequest) async throws {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw Error.responseTooLarge
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data.prefix(300), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Error.httpStatus(
                httpResponse.statusCode,
                message?.isEmpty == false ? message! : "unknown Twitch interactive error"
            )
        }
    }
}