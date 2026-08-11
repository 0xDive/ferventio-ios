import Foundation
import FerventioDomain

public struct SevenTVAPIClient: Sendable {
    public enum Error: Swift.Error, Equatable {
        case invalidResponse
        case malformedResponse(String)
        case httpStatus(Int, String)
        case invalidArgument(String)
    }

    private struct EmoteSetResponse: Decodable, Sendable {
        let emotes: [ActiveEmote]
    }

    private struct UserResponse: Decodable, Sendable {
        let connections: [Connection]
    }

    private struct Connection: Decodable, Sendable {
        let id: String
        let platform: String
        let emoteSet: EmoteSetResponse?

        enum CodingKeys: String, CodingKey {
            case id
            case platform
            case emoteSet = "emote_set"
        }
    }

    private struct ActiveEmote: Decodable, Sendable {
        let id: String
        let name: String
        let flags: Int
        let data: EmoteData?
    }

    private struct EmoteData: Decodable, Sendable {
        let animated: Bool
        let host: ImageHost
    }

    private struct ImageHost: Decodable, Sendable {
        let url: String
        let files: [ImageFile]
    }

    private struct ImageFile: Decodable, Sendable {
        let name: String
        let width: Int
        let height: Int
        let frameCount: Int

        enum CodingKeys: String, CodingKey {
            case name
            case width
            case height
            case frameCount = "frame_count"
        }
    }

    private static let zeroWidthFlag = 1 << 0
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func getGlobalEmotes() async throws -> [ThirdPartyEmoteDefinition] {
        try await perform(Self.makeGlobalRequest(), decode: Self.parseGlobalResponse)
    }

    public func getChannelEmotes(twitchUserID: String) async throws -> [ThirdPartyEmoteDefinition] {
        let request = try Self.makeChannelRequest(twitchUserID: twitchUserID)
        return try await perform(request) { data in
            try Self.parseChannelResponse(data, twitchUserID: twitchUserID)
        }
    }

    static func makeGlobalRequest() -> URLRequest {
        URLRequest(url: URL(string: "https://7tv.io/v3/emote-sets/global")!)
    }

    static func makeChannelRequest(twitchUserID: String) throws -> URLRequest {
        let userID = twitchUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty else {
            throw Error.invalidArgument("twitchUserID")
        }
        return URLRequest(url: URL(string: "https://7tv.io/v3/users/twitch/\(userID)")!)
    }

    static func parseGlobalResponse(_ data: Data) throws -> [ThirdPartyEmoteDefinition] {
        let set: EmoteSetResponse = try decode(data)
        return set.emotes.compactMap(mapEmote)
    }

    static func parseChannelResponse(
        _ data: Data,
        twitchUserID: String
    ) throws -> [ThirdPartyEmoteDefinition] {
        let user: UserResponse = try decode(data)
        let normalizedID = twitchUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        let connection = user.connections.first { connection in
            connection.platform.caseInsensitiveCompare("twitch") == .orderedSame
                && connection.id == normalizedID
        } ?? user.connections.first { connection in
            connection.platform.caseInsensitiveCompare("twitch") == .orderedSame
        }
        return connection?.emoteSet?.emotes.compactMap(mapEmote) ?? []
    }

    private func perform<Response>(
        _ request: URLRequest,
        decode: @Sendable (Data) throws -> Response
    ) async throws -> Response where Response: Sendable {
        var request = request
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data.prefix(300), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Error.httpStatus(
                httpResponse.statusCode,
                body?.isEmpty == false ? body! : "unknown 7TV error"
            )
        }
        return try decode(data)
    }

    private static func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw Error.malformedResponse(String(describing: error))
        }
    }

    private static func mapEmote(_ emote: ActiveEmote) -> ThirdPartyEmoteDefinition? {
        let code = emote.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, let data = emote.data,
              let file = preferredFile(data.host.files),
              let imageURL = assetURL(host: data.host.url, fileName: file.name) else {
            return nil
        }

        return ThirdPartyEmoteDefinition(
            code: code,
            emoteID: emote.id,
            provider: "7tv",
            animated: data.animated || file.frameCount > 1,
            imageURL: imageURL,
            zeroWidth: (emote.flags & zeroWidthFlag) != 0
        )
    }

    private static func preferredFile(_ files: [ImageFile]) -> ImageFile? {
        guard !files.isEmpty else {
            return nil
        }
        for scale in ["2x.", "3x.", "4x.", "1x."] {
            if let file = files.first(where: { $0.name.lowercased().hasPrefix(scale) }) {
                return file
            }
        }
        return files.min { lhs, rhs in
            abs(lhs.width - 56) < abs(rhs.width - 56)
        }
    }

    private static func assetURL(host: String, fileName: String) -> String? {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !fileName.isEmpty else {
            return nil
        }

        let absoluteHost: String
        if host.hasPrefix("//") {
            absoluteHost = "https:\(host)"
        } else if host.hasPrefix("https://") {
            absoluteHost = host
        } else {
            return nil
        }
        return absoluteHost.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/"
            + fileName
    }
}
