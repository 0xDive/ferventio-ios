import Foundation
import FerventioDomain

public struct TwitchAPIClient: Sendable {
    public enum Error: Swift.Error, Equatable {
        case invalidResponse
        case malformedResponse(String)
        case httpStatus(Int, String)
        case userNotFound
    }

    private struct ValidationResponse: Decodable, Sendable {
        let clientID: String
        let userID: String
        let login: String
        let scopes: [String]
        let expiresIn: Int64

        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case userID = "user_id"
            case login
            case scopes
            case expiresIn = "expires_in"
        }
    }

    private struct UsersResponse: Decodable, Sendable {
        let data: [UserResponse]
    }

    private struct UserResponse: Decodable, Sendable {
        let id: String
        let login: String
        let displayName: String
        let profileImageURL: String?
        let createdAt: String?
        let broadcasterType: String?
        let description: String?

        enum CodingKeys: String, CodingKey {
            case id
            case login
            case displayName = "display_name"
            case profileImageURL = "profile_image_url"
            case createdAt = "created_at"
            case broadcasterType = "broadcaster_type"
            case description
        }
    }

    private struct ErrorResponse: Decodable, Sendable {
        let message: String?
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func validateAccessToken(_ token: String) async throws -> TwitchSession {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw Error.malformedResponse("empty access token")
        }

        var request = URLRequest(url: URL(string: "https://id.twitch.tv/oauth2/validate")!)
        request.httpMethod = "GET"
        request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let response: ValidationResponse = try await perform(request)
        let scopes = Set(response.scopes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard !response.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !response.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !response.login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !scopes.contains(""),
              response.expiresIn >= 0 else {
            throw Error.malformedResponse("invalid Twitch validation payload")
        }

        return TwitchSession(
            clientID: response.clientID,
            userID: response.userID,
            login: response.login,
            scopes: scopes,
            expiresInSeconds: response.expiresIn
        )
    }

    public func getCurrentUser(clientID: String, token: String) async throws -> TwitchUser {
        guard let user = try await getUsers(clientID: clientID, token: token, queryItems: []).first else {
            throw Error.userNotFound
        }
        return user
    }

    public func getUserByLogin(clientID: String, token: String, login: String) async throws -> TwitchUser {
        let normalized = normalizeLogin(login)
        guard !normalized.isEmpty else {
            throw Error.userNotFound
        }
        guard let user = try await getUsers(
            clientID: clientID,
            token: token,
            queryItems: [URLQueryItem(name: "login", value: normalized)]
        ).first else {
            throw Error.userNotFound
        }
        return user
    }

    public func getChannel(clientID: String, token: String, login: String) async throws -> ChatChannel {
        let user = try await getUserByLogin(clientID: clientID, token: token, login: login)
        return channel(from: user)
    }

    public func getChannelsByLogins(
        clientID: String,
        token: String,
        logins: [String]
    ) async throws -> [ChatChannel] {
        var seen = Set<String>()
        let normalized = logins
            .map(normalizeLogin)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(100)
        guard !normalized.isEmpty else {
            return []
        }
        let users = try await getUsers(
            clientID: clientID,
            token: token,
            queryItems: normalized.map { URLQueryItem(name: "login", value: $0) }
        )
        return users.map { channel(from: $0) }
    }

    private func getUsers(
        clientID: String,
        token: String,
        queryItems: [URLQueryItem]
    ) async throws -> [TwitchUser] {
        var components = URLComponents(string: "https://api.twitch.tv/helix/users")!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let response: UsersResponse = try await perform(request)
        return response.data.map { user in
            TwitchUser(
                id: user.id,
                login: user.login,
                displayName: user.displayName.isEmpty ? user.login : user.displayName,
                profileImageURL: user.profileImageURL,
                createdAt: user.createdAt,
                broadcasterType: user.broadcasterType,
                description: user.description
            )
        }
    }

    private func channel(from user: TwitchUser) -> ChatChannel {
        ChatChannel(
            id: user.id,
            login: user.login,
            displayName: user.displayName,
            profileImageURL: user.profileImageURL
        )
    }

    private func normalizeLogin(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix: Substring
        if trimmed.first == "@" || trimmed.first == "#" {
            withoutPrefix = trimmed.dropFirst()
        } else {
            withoutPrefix = Substring(trimmed)
        }
        return withoutPrefix.lowercased()
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
