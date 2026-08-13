import Foundation
import FerventioDomain

public struct EventSubSubscription: Equatable, Sendable, Identifiable {
    public let id: String
    public let status: String
    public let type: String
    public let version: String
    public let cost: Int
    public let sessionID: String?

    public init(
        id: String,
        status: String,
        type: String,
        version: String,
        cost: Int,
        sessionID: String?
    ) {
        self.id = id
        self.status = status
        self.type = type
        self.version = version
        self.cost = cost
        self.sessionID = sessionID
    }
}

public enum InteractiveEventSubSubscriptionType: String, CaseIterable, Equatable, Sendable {
    case pollBegin = "channel.poll.begin"
    case pollProgress = "channel.poll.progress"
    case pollEnd = "channel.poll.end"
    case predictionBegin = "channel.prediction.begin"
    case predictionProgress = "channel.prediction.progress"
    case predictionLock = "channel.prediction.lock"
    case predictionEnd = "channel.prediction.end"

    public var isPoll: Bool {
        switch self {
        case .pollBegin, .pollProgress, .pollEnd:
            true
        case .predictionBegin, .predictionProgress, .predictionLock, .predictionEnd:
            false
        }
    }

    public static func enabledTypes(for scopes: Set<String>) -> [Self] {
        let scopes = Set(scopes.map { $0.lowercased() })
        let canReadPolls = scopes.contains("channel:read:polls")
            || scopes.contains("channel:manage:polls")
        let canReadPredictions = scopes.contains("channel:read:predictions")
            || scopes.contains("channel:manage:predictions")

        var types: [Self] = []
        if canReadPolls {
            types.append(contentsOf: [.pollBegin, .pollProgress, .pollEnd])
        }
        if canReadPredictions {
            types.append(contentsOf: [
                .predictionBegin,
                .predictionProgress,
                .predictionLock,
                .predictionEnd,
            ])
        }
        return types
    }
}

public struct TwitchEventSubAPIClient: Sendable {
    public enum Error: Swift.Error, Equatable {
        case invalidResponse
        case malformedResponse(String)
        case httpStatus(Int, String)
        case missingSubscription
        case invalidArgument(String)
    }

    private struct CreateSubscriptionRequest: Encodable {
        let type: String
        let version: String
        let condition: Condition
        let transport: Transport

        struct Condition: Encodable {
            let broadcasterUserID: String
            let userID: String?

            enum CodingKeys: String, CodingKey {
                case broadcasterUserID = "broadcaster_user_id"
                case userID = "user_id"
            }
        }

        struct Transport: Encodable {
            let method: String
            let sessionID: String

            enum CodingKeys: String, CodingKey {
                case method
                case sessionID = "session_id"
            }
        }
    }

    private struct CreateSubscriptionResponse: Decodable, Sendable {
        let data: [SubscriptionResponse]
    }

    private struct SubscriptionResponse: Decodable, Sendable {
        let id: String
        let status: String
        let type: String
        let version: String
        let cost: Int
        let transport: TransportResponse?

        struct TransportResponse: Decodable, Sendable {
            let method: String?
            let sessionID: String?

            enum CodingKeys: String, CodingKey {
                case method
                case sessionID = "session_id"
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

    public func createChatMessageSubscription(
        clientID: String,
        accessToken: String,
        sessionID: String,
        broadcasterID: String,
        userID: String
    ) async throws -> EventSubSubscription {
        let request = try Self.makeChatMessageSubscriptionRequest(
            clientID: clientID,
            accessToken: accessToken,
            sessionID: sessionID,
            broadcasterID: broadcasterID,
            userID: userID
        )
        return try await createSubscription(request)
    }

    public func createInteractiveSubscription(
        clientID: String,
        accessToken: String,
        sessionID: String,
        broadcasterID: String,
        type: InteractiveEventSubSubscriptionType
    ) async throws -> EventSubSubscription {
        let request = try Self.makeInteractiveSubscriptionRequest(
            clientID: clientID,
            accessToken: accessToken,
            sessionID: sessionID,
            broadcasterID: broadcasterID,
            type: type
        )
        return try await createSubscription(request)
    }

    static func makeChatMessageSubscriptionRequest(
        clientID: String,
        accessToken: String,
        sessionID: String,
        broadcasterID: String,
        userID: String
    ) throws -> URLRequest {
        try makeSubscriptionRequest(
            clientID: clientID,
            accessToken: accessToken,
            sessionID: sessionID,
            broadcasterID: broadcasterID,
            userID: userID,
            type: "channel.chat.message",
            version: "1"
        )
    }

    static func makeInteractiveSubscriptionRequest(
        clientID: String,
        accessToken: String,
        sessionID: String,
        broadcasterID: String,
        type: InteractiveEventSubSubscriptionType
    ) throws -> URLRequest {
        try makeSubscriptionRequest(
            clientID: clientID,
            accessToken: accessToken,
            sessionID: sessionID,
            broadcasterID: broadcasterID,
            userID: nil,
            type: type.rawValue,
            version: "1"
        )
    }

    private static func makeSubscriptionRequest(
        clientID: String,
        accessToken: String,
        sessionID: String,
        broadcasterID: String,
        userID: String?,
        type: String,
        version: String
    ) throws -> URLRequest {
        let clientID = try requireNonEmpty(clientID, name: "clientID")
        let accessToken = try requireNonEmpty(accessToken, name: "accessToken")
        let sessionID = try requireNonEmpty(sessionID, name: "sessionID")
        let broadcasterID = try requireNonEmpty(broadcasterID, name: "broadcasterID")
        let type = try requireNonEmpty(type, name: "type")
        let version = try requireNonEmpty(version, name: "version")
        let userID = try userID.map { try requireNonEmpty($0, name: "userID") }

        var request = URLRequest(url: URL(string: "https://api.twitch.tv/helix/eventsub/subscriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(
            CreateSubscriptionRequest(
                type: type,
                version: version,
                condition: .init(
                    broadcasterUserID: broadcasterID,
                    userID: userID
                ),
                transport: .init(
                    method: "websocket",
                    sessionID: sessionID
                )
            )
        )
        return request
    }

    private func createSubscription(_ request: URLRequest) async throws -> EventSubSubscription {
        let response: CreateSubscriptionResponse = try await perform(request)
        guard let subscription = response.data.first else {
            throw Error.missingSubscription
        }
        return EventSubSubscription(
            id: subscription.id,
            status: subscription.status,
            type: subscription.type,
            version: subscription.version,
            cost: subscription.cost,
            sessionID: subscription.transport?.sessionID
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
}
