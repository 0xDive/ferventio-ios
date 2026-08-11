import Foundation
import FerventioDomain

public struct BetterTTVAPIClient: Sendable {
    public enum Error: Swift.Error, Equatable {
        case invalidResponse
        case malformedResponse(String)
        case httpStatus(Int, String)
        case invalidArgument(String)
    }

    private struct CachedEmote: Decodable, Sendable {
        let id: String
        let code: String
        let imageType: String?
    }

    private struct CachedChannel: Decodable, Sendable {
        let channelEmotes: [CachedEmote]
        let sharedEmotes: [CachedEmote]
    }

    private static let zeroWidthOverlayIDs: Set<String> = [
        "5e76d338d6581c3724c0f0b2",
        "5e76d399d6581c3724c0f0b8",
        "5849c9a4f52be01a7ee5f79d",
        "567b5b520e984428652809b6",
        "58487cc6f52be01a7ee5f205",
        "5849c9c8f52be01a7ee5f79e",
        "567b5c080e984428652809ba",
        "567b5dc00e984428652809bd",
    ]

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func getGlobalEmotes() async throws -> [ThirdPartyEmoteDefinition] {
        let request = URLRequest(
            url: URL(string: "https://api.betterttv.net/3/cached/emotes/global")!
        )
        let response: [CachedEmote] = try await perform(request)
        return response.compactMap(Self.mapEmote)
    }

    public func getChannelEmotes(twitchUserID: String) async throws -> [ThirdPartyEmoteDefinition] {
        let userID = twitchUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty else {
            throw Error.invalidArgument("twitchUserID")
        }

        let url = URL(string: "https://api.betterttv.net/3/cached/users/twitch/\(userID)")!
        let response: CachedChannel = try await perform(URLRequest(url: url))
        // Shared emotes are the lower-priority channel source; direct channel
        // emotes come last so catalog construction deterministically wins.
        return (response.sharedEmotes + response.channelEmotes).compactMap(Self.mapEmote)
    }

    public static func imageURL(emoteID: String, scale: Int = 2) -> String? {
        let id = emoteID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, (1...3).contains(scale) else {
            return nil
        }
        return "https://cdn.betterttv.net/emote/\(id)/\(scale)x"
    }

    private static func mapEmote(_ emote: CachedEmote) -> ThirdPartyEmoteDefinition? {
        let id = emote.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = emote.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !code.isEmpty else {
            return nil
        }

        return ThirdPartyEmoteDefinition(
            code: code,
            emoteID: id,
            provider: "bttv",
            animated: emote.imageType?.lowercased() == "gif",
            imageURL: imageURL(emoteID: id),
            zeroWidth: zeroWidthOverlayIDs.contains(id)
        )
    }

    private func perform<Response: Decodable & Sendable>(_ request: URLRequest) async throws -> Response {
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
                body?.isEmpty == false ? body! : "unknown BetterTTV error"
            )
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw Error.malformedResponse(String(describing: error))
        }
    }
}
