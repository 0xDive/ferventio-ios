import Foundation
import FerventioDomain

public struct TwitchChatAssetsAPIClient: Sendable {
    public enum Error: Swift.Error, Equatable {
        case invalidResponse
        case malformedResponse(String)
        case httpStatus(Int, String)
        case invalidArgument(String)
    }

    private struct BadgeSetsResponse: Decodable, Sendable {
        let data: [BadgeSetResponse]
    }

    private struct BadgeSetResponse: Decodable, Sendable {
        let setID: String
        let versions: [BadgeVersionResponse]

        enum CodingKeys: String, CodingKey {
            case setID = "set_id"
            case versions
        }
    }

    private struct BadgeVersionResponse: Decodable, Sendable {
        let id: String
        let imageURL1x: String?
        let imageURL2x: String?
        let imageURL4x: String?
        let title: String?
        let description: String?

        enum CodingKeys: String, CodingKey {
            case id
            case imageURL1x = "image_url_1x"
            case imageURL2x = "image_url_2x"
            case imageURL4x = "image_url_4x"
            case title
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

    public func getGlobalBadges(clientID: String, accessToken: String) async throws -> [ChatBadgeAsset] {
        let request = try Self.makeBadgesRequest(
            clientID: clientID,
            accessToken: accessToken,
            broadcasterID: nil
        )
        return try await loadBadges(request)
    }

    public func getChannelBadges(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) async throws -> [ChatBadgeAsset] {
        let request = try Self.makeBadgesRequest(
            clientID: clientID,
            accessToken: accessToken,
            broadcasterID: broadcasterID
        )
        return try await loadBadges(request)
    }

    static func makeBadgesRequest(
        clientID: String,
        accessToken: String,
        broadcasterID: String?
    ) throws -> URLRequest {
        let clientID = try requireNonEmpty(clientID, name: "clientID")
        let accessToken = try requireNonEmpty(accessToken, name: "accessToken")
        let endpoint: URL
        if let broadcasterID {
            let broadcasterID = try requireNonEmpty(broadcasterID, name: "broadcasterID")
            var components = URLComponents(string: "https://api.twitch.tv/helix/chat/badges")!
            components.queryItems = [URLQueryItem(name: "broadcaster_id", value: broadcasterID)]
            endpoint = components.url!
        } else {
            endpoint = URL(string: "https://api.twitch.tv/helix/chat/badges/global")!
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        return request
    }

    private func loadBadges(_ request: URLRequest) async throws -> [ChatBadgeAsset] {
        let response: BadgeSetsResponse = try await perform(request)
        return response.data.flatMap { set in
            set.versions.map { version in
                ChatBadgeAsset(
                    setID: set.setID,
                    versionID: version.id,
                    imageURL1x: version.imageURL1x,
                    imageURL2x: version.imageURL2x,
                    imageURL4x: version.imageURL4x,
                    title: version.title,
                    description: version.description
                )
            }
        }
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
