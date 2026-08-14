import Foundation
import FerventioDomain

public struct FrankerFaceZAPIClient: Sendable {
    public enum Error: Swift.Error, Equatable { case invalidResponse, malformedResponse(String), httpStatus(Int, String), invalidArgument(String) }

    private struct APIResponse: Decodable, Sendable {
        let defaultSets: [Int]?
        let room: Room?
        let sets: [String: EmoteSet]
        enum CodingKeys: String, CodingKey { case defaultSets = "default_sets", room, sets }
    }
    private struct Room: Decodable, Sendable { let set: Int? }
    private struct EmoteSet: Decodable, Sendable { let emoticons: [Emote] }
    private struct Emote: Decodable, Sendable {
        let id: Int
        let name: String
        let urls: [String: String]
        let animated: [String: String]?
        let modifier: Bool?
        let modifierFlags: Int?
        let modifierPrefix: Bool?
        enum CodingKeys: String, CodingKey {
            case id, name, urls, animated, modifier
            case modifierFlags = "modifier_flags"
            case modifierPrefix = "modifier_prefix"
        }
    }

    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func getGlobalEmotes() async throws -> [ThirdPartyEmoteDefinition] { try await perform(Self.makeGlobalRequest(), selection: .global) }
    public func getChannelEmotes(twitchUserID: String) async throws -> [ThirdPartyEmoteDefinition] {
        try await perform(Self.makeChannelRequest(twitchUserID: twitchUserID), selection: .channel)
    }
    static func makeGlobalRequest() -> URLRequest { URLRequest(url: URL(string: "https://api.frankerfacez.com/v1/set/global")!) }
    static func makeChannelRequest(twitchUserID: String) throws -> URLRequest {
        let userID = twitchUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty else { throw Error.invalidArgument("twitchUserID") }
        return URLRequest(url: URL(string: "https://api.frankerfacez.com/v1/room/id/\(userID)")!)
    }
    static func parseGlobalResponse(_ data: Data) throws -> [ThirdPartyEmoteDefinition] {
        let response = try decode(data)
        return definitions(from: response.defaultSets ?? [], sets: response.sets)
    }
    static func parseChannelResponse(_ data: Data) throws -> [ThirdPartyEmoteDefinition] {
        let response = try decode(data)
        guard let setID = response.room?.set else { return [] }
        return definitions(from: [setID], sets: response.sets)
    }

    private enum Selection { case global, channel }
    private func perform(_ request: URLRequest, selection: Selection) async throws -> [ThirdPartyEmoteDefinition] {
        var request = request
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw Error.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data.prefix(300), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Error.httpStatus(httpResponse.statusCode, body?.isEmpty == false ? body! : "unknown FrankerFaceZ error")
        }
        switch selection {
        case .global: return try Self.parseGlobalResponse(data)
        case .channel: return try Self.parseChannelResponse(data)
        }
    }
    private static func decode(_ data: Data) throws -> APIResponse {
        do { return try JSONDecoder().decode(APIResponse.self, from: data) }
        catch { throw Error.malformedResponse(String(describing: error)) }
    }
    private static func definitions(from setIDs: [Int], sets: [String: EmoteSet]) -> [ThirdPartyEmoteDefinition] {
        var result: [ThirdPartyEmoteDefinition] = []
        for setID in setIDs {
            guard let set = sets[String(setID)] else { continue }
            result.append(contentsOf: set.emoticons.compactMap(mapEmote))
        }
        return result
    }
    private static func mapEmote(_ emote: Emote) -> ThirdPartyEmoteDefinition? {
        let code = emote.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        let animatedURL = preferredURL(emote.animated)
        let staticURL = preferredURL(emote.urls)
        guard let imageURL = animatedURL ?? staticURL else { return nil }
        return ThirdPartyEmoteDefinition(
            code: code,
            emoteID: String(emote.id),
            provider: "ffz",
            animated: animatedURL != nil,
            imageURL: imageURL,
            zeroWidth: false,
            modifier: emote.modifier == true,
            modifierPrefix: emote.modifierPrefix == true,
            modifierFlags: max(0, emote.modifierFlags ?? 0)
        )
    }
    private static func preferredURL(_ urls: [String: String]?) -> String? {
        guard let urls else { return nil }
        for scale in ["2", "4", "1"] { if let value = urls[scale], let resolved = absoluteURL(value) { return resolved } }
        return nil
    }
    private static func absoluteURL(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("//") { return "https:\(value)" }
        guard let url = URL(string: value), url.scheme?.lowercased() == "https" else { return nil }
        return value
    }
}
