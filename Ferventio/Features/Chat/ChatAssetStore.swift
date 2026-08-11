import FerventioDomain
import FerventioNetworking
import Observation

protocol ChatBadgeLoading: Sendable {
    func getGlobalBadges(clientID: String, accessToken: String) async throws -> [ChatBadgeAsset]
    func getChannelBadges(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) async throws -> [ChatBadgeAsset]
}

extension TwitchChatAssetsAPIClient: ChatBadgeLoading {}

protocol BetterTTVEmoteLoading: Sendable {
    func getGlobalEmotes() async throws -> [ThirdPartyEmoteDefinition]
    func getChannelEmotes(twitchUserID: String) async throws -> [ThirdPartyEmoteDefinition]
}

extension BetterTTVAPIClient: BetterTTVEmoteLoading {}

protocol FrankerFaceZEmoteLoading: Sendable {
    func getGlobalEmotes() async throws -> [ThirdPartyEmoteDefinition]
    func getChannelEmotes(twitchUserID: String) async throws -> [ThirdPartyEmoteDefinition]
}

extension FrankerFaceZAPIClient: FrankerFaceZEmoteLoading {}

@MainActor
@Observable
final class ChatAssetStore {
    private(set) var badgeAssets: [String: ChatBadgeAsset] = [:]
    private(set) var thirdPartyEmoteCatalog = ThirdPartyEmoteCatalog(emotes: [])
    private(set) var isLoadingBadges = false
    private(set) var isLoadingThirdPartyEmotes = false

    @ObservationIgnored private let badges: any ChatBadgeLoading
    @ObservationIgnored private let betterTTV: any BetterTTVEmoteLoading
    @ObservationIgnored private let frankerFaceZ: any FrankerFaceZEmoteLoading
    @ObservationIgnored private var badgeLoadGeneration = 0
    @ObservationIgnored private var emoteLoadGeneration = 0

    init(
        badges: (any ChatBadgeLoading)? = nil,
        betterTTV: (any BetterTTVEmoteLoading)? = nil,
        frankerFaceZ: (any FrankerFaceZEmoteLoading)? = nil
    ) {
        self.badges = badges ?? TwitchChatAssetsAPIClient()
        self.betterTTV = betterTTV ?? BetterTTVAPIClient()
        self.frankerFaceZ = frankerFaceZ ?? FrankerFaceZAPIClient()
    }

    func loadBadges(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) async {
        badgeLoadGeneration &+= 1
        let generation = badgeLoadGeneration
        isLoadingBadges = true
        defer {
            if badgeLoadGeneration == generation {
                isLoadingBadges = false
            }
        }

        async let globalRequest = optionalGlobalBadges(
            clientID: clientID,
            accessToken: accessToken
        )
        async let channelRequest = optionalChannelBadges(
            clientID: clientID,
            accessToken: accessToken,
            broadcasterID: broadcasterID
        )
        let (global, channel) = await (globalRequest, channelRequest)
        guard badgeLoadGeneration == generation else {
            return
        }

        var merged = Dictionary(uniqueKeysWithValues: global.map { ($0.id, $0) })
        for asset in channel {
            merged[asset.id] = asset
        }
        badgeAssets = merged
    }

    func loadThirdPartyEmotes(twitchUserID: String) async {
        emoteLoadGeneration &+= 1
        let generation = emoteLoadGeneration
        isLoadingThirdPartyEmotes = true
        defer {
            if emoteLoadGeneration == generation {
                isLoadingThirdPartyEmotes = false
            }
        }

        async let betterTTVRequest = loadBetterTTVCatalog(twitchUserID: twitchUserID)
        async let frankerFaceZRequest = loadFrankerFaceZCatalog(twitchUserID: twitchUserID)
        let (betterTTVEmotes, frankerFaceZEmotes) = await (
            betterTTVRequest,
            frankerFaceZRequest
        )
        guard emoteLoadGeneration == generation else {
            return
        }

        // Keep Android provider precedence stable: BetterTTV > FFZ > 7TV.
        // The catalog keeps the last definition for a code, so lower-priority
        // providers must be appended first. 7TV is added in the next provider step.
        thirdPartyEmoteCatalog = ThirdPartyEmoteCatalog(
            emotes: frankerFaceZEmotes + betterTTVEmotes
        )
    }

    func reset() {
        badgeLoadGeneration &+= 1
        emoteLoadGeneration &+= 1
        badgeAssets.removeAll(keepingCapacity: false)
        thirdPartyEmoteCatalog = ThirdPartyEmoteCatalog(emotes: [])
        isLoadingBadges = false
        isLoadingThirdPartyEmotes = false
    }

    private func loadBetterTTVCatalog(
        twitchUserID: String
    ) async -> [ThirdPartyEmoteDefinition] {
        async let globalRequest = optionalGlobalBetterTTVEmotes()
        async let channelRequest = optionalChannelBetterTTVEmotes(twitchUserID: twitchUserID)
        let (global, channel) = await (globalRequest, channelRequest)
        return mergeByCode(global: global, channel: channel)
    }

    private func loadFrankerFaceZCatalog(
        twitchUserID: String
    ) async -> [ThirdPartyEmoteDefinition] {
        async let globalRequest = optionalGlobalFrankerFaceZEmotes()
        async let channelRequest = optionalChannelFrankerFaceZEmotes(twitchUserID: twitchUserID)
        let (global, channel) = await (globalRequest, channelRequest)
        return mergeByCode(global: global, channel: channel)
    }

    private func mergeByCode(
        global: [ThirdPartyEmoteDefinition],
        channel: [ThirdPartyEmoteDefinition]
    ) -> [ThirdPartyEmoteDefinition] {
        var byCode: [String: ThirdPartyEmoteDefinition] = [:]
        for emote in global where !emote.code.isEmpty {
            byCode[emote.code] = emote
        }
        for emote in channel where !emote.code.isEmpty {
            byCode[emote.code] = emote
        }
        return Array(byCode.values)
    }

    private func optionalGlobalBadges(
        clientID: String,
        accessToken: String
    ) async -> [ChatBadgeAsset] {
        (try? await badges.getGlobalBadges(
            clientID: clientID,
            accessToken: accessToken
        )) ?? []
    }

    private func optionalChannelBadges(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) async -> [ChatBadgeAsset] {
        (try? await badges.getChannelBadges(
            clientID: clientID,
            accessToken: accessToken,
            broadcasterID: broadcasterID
        )) ?? []
    }

    private func optionalGlobalBetterTTVEmotes() async -> [ThirdPartyEmoteDefinition] {
        (try? await betterTTV.getGlobalEmotes()) ?? []
    }

    private func optionalChannelBetterTTVEmotes(
        twitchUserID: String
    ) async -> [ThirdPartyEmoteDefinition] {
        (try? await betterTTV.getChannelEmotes(twitchUserID: twitchUserID)) ?? []
    }

    private func optionalGlobalFrankerFaceZEmotes() async -> [ThirdPartyEmoteDefinition] {
        (try? await frankerFaceZ.getGlobalEmotes()) ?? []
    }

    private func optionalChannelFrankerFaceZEmotes(
        twitchUserID: String
    ) async -> [ThirdPartyEmoteDefinition] {
        (try? await frankerFaceZ.getChannelEmotes(twitchUserID: twitchUserID)) ?? []
    }
}
