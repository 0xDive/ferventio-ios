import FerventioDomain
import Testing
@testable import Ferventio

@MainActor
struct ChatAssetStoreTests {
    @Test
    func channelBadgesOverrideMatchingGlobalBadgeVersion() async {
        let global = ChatBadgeAsset(
            setID: "subscriber",
            versionID: "1",
            imageURL2x: "https://example.com/global.png"
        )
        let channel = ChatBadgeAsset(
            setID: "subscriber",
            versionID: "1",
            imageURL2x: "https://example.com/channel.png"
        )
        let moderator = ChatBadgeAsset(
            setID: "moderator",
            versionID: "1",
            imageURL2x: "https://example.com/mod.png"
        )
        let store = ChatAssetStore(
            badges: StubBadgeLoader(global: [global, moderator], channel: [channel])
        )

        await store.loadBadges(
            clientID: "client",
            accessToken: "access",
            broadcasterID: "channel"
        )

        #expect(store.badgeAssets.count == 2)
        #expect(store.badgeAssets[channel.id] == channel)
        #expect(store.badgeAssets[moderator.id] == moderator)
        #expect(!store.isLoadingBadges)
    }

    @Test
    func duplicateGlobalBadgeIDsUseLatestDefinitionWithoutCrashing() async {
        let first = ChatBadgeAsset(
            setID: "subscriber",
            versionID: "1",
            imageURL2x: "https://example.com/first.png"
        )
        let latest = ChatBadgeAsset(
            setID: "subscriber",
            versionID: "1",
            imageURL2x: "https://example.com/latest.png"
        )
        let store = ChatAssetStore(
            badges: StubBadgeLoader(global: [first, latest], channel: [])
        )

        await store.loadBadges(
            clientID: "client",
            accessToken: "access",
            broadcasterID: "channel"
        )

        #expect(store.badgeAssets.count == 1)
        #expect(store.badgeAssets[first.id] == latest)
        #expect(!store.isLoadingBadges)
    }

    @Test
    func oneFailedBadgeCatalogStillKeepsSuccessfulCatalog() async {
        let moderator = ChatBadgeAsset(setID: "moderator", versionID: "1")
        let store = ChatAssetStore(
            badges: StubBadgeLoader(global: [moderator], channel: [], failChannel: true)
        )

        await store.loadBadges(
            clientID: "client",
            accessToken: "access",
            broadcasterID: "channel"
        )

        #expect(store.badgeAssets[moderator.id] == moderator)
    }

    @Test
    func channelEmoteOverridesGlobalWithinProvider() async {
        let global = emote(code: "SameCode", id: "global", provider: "bttv")
        let channel = emote(code: "SameCode", id: "channel", provider: "bttv")
        let store = ChatAssetStore(
            betterTTV: StubEmoteLoader(global: [global], channel: [channel]),
            frankerFaceZ: StubEmoteLoader(),
            sevenTV: StubEmoteLoader()
        )

        await store.loadThirdPartyEmotes(twitchUserID: "123")

        #expect(store.thirdPartyEmoteCatalog.emote(for: "SameCode") == channel)
        #expect(!store.isLoadingThirdPartyEmotes)
    }

    @Test
    func providerPrecedenceIsBetterTTVThenFrankerFaceZThenSevenTV() async {
        let seven = emote(code: "Shared", id: "seven", provider: "7tv")
        let ffz = emote(code: "Shared", id: "ffz", provider: "ffz")
        let bttv = emote(code: "Shared", id: "bttv", provider: "bttv")
        let ffzOnly = emote(code: "LowerConflict", id: "ffz-only", provider: "ffz")
        let sevenLower = emote(code: "LowerConflict", id: "seven-lower", provider: "7tv")
        let store = ChatAssetStore(
            betterTTV: StubEmoteLoader(global: [bttv]),
            frankerFaceZ: StubEmoteLoader(global: [ffz, ffzOnly]),
            sevenTV: StubEmoteLoader(global: [seven, sevenLower])
        )

        await store.loadThirdPartyEmotes(twitchUserID: "123")

        #expect(store.thirdPartyEmoteCatalog.emote(for: "Shared") == bttv)
        #expect(store.thirdPartyEmoteCatalog.emote(for: "LowerConflict") == ffzOnly)
    }

    @Test
    func failedProviderEndpointStillKeepsOtherCatalogs() async {
        let ffzGlobal = emote(code: "FFZ", id: "ffz-global", provider: "ffz")
        let bttvGlobal = emote(code: "BTTV", id: "bttv-global", provider: "bttv")
        let sevenChannel = emote(code: "Seven", id: "seven-channel", provider: "7tv")
        let store = ChatAssetStore(
            betterTTV: StubEmoteLoader(global: [bttvGlobal]),
            frankerFaceZ: StubEmoteLoader(global: [ffzGlobal], failChannel: true),
            sevenTV: StubEmoteLoader(channel: [sevenChannel], failGlobal: true)
        )

        await store.loadThirdPartyEmotes(twitchUserID: "123")

        #expect(store.thirdPartyEmoteCatalog.emote(for: "FFZ") == ffzGlobal)
        #expect(store.thirdPartyEmoteCatalog.emote(for: "BTTV") == bttvGlobal)
        #expect(store.thirdPartyEmoteCatalog.emote(for: "Seven") == sevenChannel)
    }

    @Test
    func resetClearsBadgeAndThirdPartyCatalogs() async {
        let badge = ChatBadgeAsset(setID: "moderator", versionID: "1")
        let bttv = emote(code: "OMEGALUL", id: "1", provider: "bttv")
        let store = ChatAssetStore(
            badges: StubBadgeLoader(global: [badge], channel: []),
            betterTTV: StubEmoteLoader(global: [bttv]),
            frankerFaceZ: StubEmoteLoader(),
            sevenTV: StubEmoteLoader()
        )

        await store.loadBadges(clientID: "client", accessToken: "access", broadcasterID: "channel")
        await store.loadThirdPartyEmotes(twitchUserID: "123")
        store.reset()

        #expect(store.badgeAssets.isEmpty)
        #expect(store.thirdPartyEmoteCatalog.isEmpty)
        #expect(!store.isLoadingBadges)
        #expect(!store.isLoadingThirdPartyEmotes)
    }

    private func emote(
        code: String,
        id: String,
        provider: String
    ) -> ThirdPartyEmoteDefinition {
        ThirdPartyEmoteDefinition(
            code: code,
            emoteID: id,
            provider: provider,
            animated: false,
            imageURL: nil
        )
    }
}

private struct StubBadgeLoader: ChatBadgeLoading, Sendable {
    enum Failure: Swift.Error { case failed }

    let global: [ChatBadgeAsset]
    let channel: [ChatBadgeAsset]
    let failGlobal: Bool
    let failChannel: Bool

    init(
        global: [ChatBadgeAsset],
        channel: [ChatBadgeAsset],
        failGlobal: Bool = false,
        failChannel: Bool = false
    ) {
        self.global = global
        self.channel = channel
        self.failGlobal = failGlobal
        self.failChannel = failChannel
    }

    func getGlobalBadges(clientID: String, accessToken: String) async throws -> [ChatBadgeAsset] {
        if failGlobal { throw Failure.failed }
        return global
    }

    func getChannelBadges(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) async throws -> [ChatBadgeAsset] {
        if failChannel { throw Failure.failed }
        return channel
    }
}

private struct StubEmoteLoader: BetterTTVEmoteLoading, FrankerFaceZEmoteLoading, SevenTVEmoteLoading, Sendable {
    enum Failure: Swift.Error { case failed }

    let global: [ThirdPartyEmoteDefinition]
    let channel: [ThirdPartyEmoteDefinition]
    let failGlobal: Bool
    let failChannel: Bool

    init(
        global: [ThirdPartyEmoteDefinition] = [],
        channel: [ThirdPartyEmoteDefinition] = [],
        failGlobal: Bool = false,
        failChannel: Bool = false
    ) {
        self.global = global
        self.channel = channel
        self.failGlobal = failGlobal
        self.failChannel = failChannel
    }

    func getGlobalEmotes() async throws -> [ThirdPartyEmoteDefinition] {
        if failGlobal { throw Failure.failed }
        return global
    }

    func getChannelEmotes(twitchUserID: String) async throws -> [ThirdPartyEmoteDefinition] {
        if failChannel { throw Failure.failed }
        return channel
    }
}
