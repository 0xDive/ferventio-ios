import Foundation
import FerventioDomain

public struct TwitchRecentMessagesResult: Equatable, Sendable {
    public let messages: [ChatMessage]
    public let errorCode: String?

    public init(messages: [ChatMessage], errorCode: String? = nil) {
        self.messages = messages
        self.errorCode = errorCode
    }
}

public struct TwitchRecentMessagesClient: Sendable {
    public enum Error: Swift.Error, Equatable {
        case invalidBaseURL
        case invalidChannelLogin
        case invalidResponse
        case responseTooLarge
        case httpStatus(Int)
        case malformedResponse(String)
    }

    public static let defaultBaseURL = URL(
        string: "https://recent-messages.robotty.de/api/v2/recent-messages"
    )!
    public static let defaultLimit = 100
    public static let maximumLimit = 500
    public static let maximumResponseBytes = 2 * 1024 * 1024

    private let baseURL: URL
    private let session: URLSession

    public init(
        baseURL: URL = Self.defaultBaseURL,
        session: URLSession = .shared
    ) throws {
        guard baseURL.scheme?.lowercased() == "https",
              baseURL.host?.isEmpty == false else {
            throw Error.invalidBaseURL
        }
        self.baseURL = baseURL
        self.session = session
    }

    public func load(
        channel: ChatChannel,
        limit: Int = Self.defaultLimit
    ) async throws -> TwitchRecentMessagesResult {
        let login = channel.login
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard Self.isValidLogin(login) else {
            throw Error.invalidChannelLogin
        }
        let safeLimit = min(max(limit, 1), Self.maximumLimit)

        var components = URLComponents(
            url: baseURL.appendingPathComponent(login),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "limit", value: String(safeLimit))]
        guard let url = components.url else {
            throw Error.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }
        if http.expectedContentLength > Int64(Self.maximumResponseBytes) {
            throw Error.responseTooLarge
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw Error.responseTooLarge
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Error.httpStatus(http.statusCode)
        }

        return try Self.parseResponse(data, channel: channel, limit: safeLimit)
    }

    static func parseResponse(
        _ data: Data,
        channel: ChatChannel,
        limit: Int,
        nowMilliseconds: @Sendable () -> Int64 = {
            Int64((Date().timeIntervalSince1970 * 1_000).rounded(.towardZero))
        }
    ) throws -> TwitchRecentMessagesResult {
        struct Payload: Decodable {
            let messages: [String]
            let errorCode: String?

            enum CodingKeys: String, CodingKey {
                case messages
                case errorCode = "error_code"
            }
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw Error.malformedResponse(String(describing: error))
        }

        let parsed = TwitchIRCRecentSnapshotParser.parse(
            lines: payload.messages,
            channel: channel,
            limit: min(max(limit, 0), Self.maximumLimit),
            nowMilliseconds: nowMilliseconds
        )
        return TwitchRecentMessagesResult(
            messages: parsed,
            errorCode: payload.errorCode
        )
    }

    private static func isValidLogin(_ login: String) -> Bool {
        guard (1...25).contains(login.count) else {
            return false
        }
        return login.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 97...122, 95:
                true
            default:
                false
            }
        }
    }
}
