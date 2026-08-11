import Foundation

public struct ChatSendDropReason: Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct ChatSendResult: Equatable, Sendable {
    public let messageID: String?
    public let isSent: Bool
    public let dropReason: ChatSendDropReason?

    public init(messageID: String?, isSent: Bool, dropReason: ChatSendDropReason?) {
        self.messageID = messageID
        self.isSent = isSent
        self.dropReason = dropReason
    }
}

public struct TwitchChatAPIClient: Sendable {
    public enum Error: Swift.Error, Equatable {
        case invalidResponse
        case malformedResponse(String)
        case httpStatus(Int, String)
        case missingResult
        case invalidArgument(String)
        case messageTooLong
    }

    private struct SendMessageRequest: Encodable {
        let broadcasterID: String
        let senderID: String
        let message: String
        let replyParentMessageID: String?

        enum CodingKeys: String, CodingKey {
            case broadcasterID = "broadcaster_id"
            case senderID = "sender_id"
            case message
            case replyParentMessageID = "reply_parent_message_id"
        }
    }

    private struct SendMessageResponse: Decodable, Sendable {
        let data: [Result]

        struct Result: Decodable, Sendable {
            let messageID: String
            let isSent: Bool
            let dropReason: DropReason?

            enum CodingKeys: String, CodingKey {
                case messageID = "message_id"
                case isSent = "is_sent"
                case dropReason = "drop_reason"
            }
        }

        struct DropReason: Decodable, Sendable {
            let code: String
            let message: String
        }
    }

    private struct ErrorResponse: Decodable, Sendable {
        let message: String?
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func sendMessage(
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        senderID: String,
        message: String,
        replyParentMessageID: String? = nil
    ) async throws -> ChatSendResult {
        let request = try Self.makeSendMessageRequest(
            clientID: clientID,
            accessToken: accessToken,
            broadcasterID: broadcasterID,
            senderID: senderID,
            message: message,
            replyParentMessageID: replyParentMessageID
        )
        let response: SendMessageResponse = try await perform(request)
        guard let result = response.data.first else {
            throw Error.missingResult
        }
        let messageID = result.messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatSendResult(
            messageID: messageID.isEmpty ? nil : messageID,
            isSent: result.isSent,
            dropReason: result.dropReason.map {
                ChatSendDropReason(code: $0.code, message: $0.message)
            }
        )
    }

    static func makeSendMessageRequest(
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        senderID: String,
        message: String,
        replyParentMessageID: String? = nil
    ) throws -> URLRequest {
        let clientID = try requireNonEmpty(clientID, name: "clientID")
        let accessToken = try requireNonEmpty(accessToken, name: "accessToken")
        let broadcasterID = try requireNonEmpty(broadcasterID, name: "broadcasterID")
        let senderID = try requireNonEmpty(senderID, name: "senderID")
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.invalidArgument("message")
        }
        guard message.count <= 500 else {
            throw Error.messageTooLong
        }
        let replyParentMessageID = replyParentMessageID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let replyParentMessageID, replyParentMessageID.isEmpty {
            throw Error.invalidArgument("replyParentMessageID")
        }

        var request = URLRequest(url: URL(string: "https://api.twitch.tv/helix/chat/messages")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(
            SendMessageRequest(
                broadcasterID: broadcasterID,
                senderID: senderID,
                message: message,
                replyParentMessageID: replyParentMessageID
            )
        )
        return request
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
