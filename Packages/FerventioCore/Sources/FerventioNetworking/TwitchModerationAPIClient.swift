import Foundation

public struct TwitchModerationAPIClient: Sendable {
    public enum Error: Swift.Error, Equatable {
        case invalidResponse
        case httpStatus(Int, String)
        case invalidArgument(String)
        case invalidTimeoutDuration
    }

    private struct TimeoutRequest: Encodable {
        let data: Data

        struct Data: Encodable {
            let userID: String
            let duration: Int
            let reason: String?

            enum CodingKeys: String, CodingKey {
                case userID = "user_id"
                case duration
                case reason
            }
        }
    }

    private struct ErrorResponse: Decodable, Sendable {
        let message: String?
    }

    public static let maximumTimeoutSeconds = 1_209_600
    public static let maximumReasonLength = 500

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func timeoutUser(
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        moderatorID: String,
        targetUserID: String,
        durationSeconds: Int,
        reason: String
    ) async throws {
        let request = try Self.makeTimeoutRequest(
            clientID: clientID,
            accessToken: accessToken,
            broadcasterID: broadcasterID,
            moderatorID: moderatorID,
            targetUserID: targetUserID,
            durationSeconds: durationSeconds,
            reason: reason
        )
        try await perform(request)
    }

    static func makeTimeoutRequest(
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        moderatorID: String,
        targetUserID: String,
        durationSeconds: Int,
        reason: String
    ) throws -> URLRequest {
        let clientID = try requireNonEmpty(clientID, name: "clientID")
        let accessToken = try requireNonEmpty(accessToken, name: "accessToken")
        let broadcasterID = try requireNonEmpty(broadcasterID, name: "broadcasterID")
        let moderatorID = try requireNonEmpty(moderatorID, name: "moderatorID")
        let targetUserID = try requireNonEmpty(targetUserID, name: "targetUserID")
        guard (1...maximumTimeoutSeconds).contains(durationSeconds) else {
            throw Error.invalidTimeoutDuration
        }

        let normalizedReason = reason
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maximumReasonLength)
        let cleanReason = normalizedReason.isEmpty ? nil : String(normalizedReason)

        var components = URLComponents(string: "https://api.twitch.tv/helix/moderation/bans")!
        components.queryItems = [
            URLQueryItem(name: "broadcaster_id", value: broadcasterID),
            URLQueryItem(name: "moderator_id", value: moderatorID),
        ]
        guard let url = components.url else {
            throw Error.invalidArgument("url")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(
            TimeoutRequest(
                data: TimeoutRequest.Data(
                    userID: targetUserID,
                    duration: durationSeconds,
                    reason: cleanReason
                )
            )
        )
        return request
    }

    private static func requireNonEmpty(_ value: String, name: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw Error.invalidArgument(name)
        }
        return normalized
    }

    private func perform(_ request: URLRequest) async throws {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw makeHTTPError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    private func makeHTTPError(statusCode: Int, data: Data) -> Error {
        let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data).message)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = String(data: data.prefix(300), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .httpStatus(
            statusCode,
            message?.isEmpty == false ? message! : (fallback ?? "unknown Twitch moderation error")
        )
    }
}
