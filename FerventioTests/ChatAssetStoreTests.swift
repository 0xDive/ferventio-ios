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
    func oneFailedBadgeCatalogStillKeepsSuccessfulCatalog() async {
        let moderator = ChatBadgeAsset(setID: "moderator", versionID: "1")
        let store = ChatAssetStore(
            badges: StubBadgeLoader(
                global: [moderator],
                channel: [],
                failChannel: true
            )
        )

        await store.loadBadges(
            clientID: "client",
            accessToken: "access",
            broadcasterID: "channel"
        )

        #expect(store.badgeAssets[moderator.id] == moderator)
    }

    @Test
    func channelBetterTTVEmoteOverridesGlobalCode() async {
        let global = ThirdPartyEmoteDefinition(
            code: "SameCode",
            emoteID: "global",
            provider: "bttv",
            animated: false,
            imageURL: "https://example.com/global"
        )
        let channel = ThirdPartyEmoteDefinition(
            code: "SameCode",
            emoteID: "channel",
            provider: "bttv",
            animated: true,
            imageURL: "https://example.com/channel"
        )
        let store = ChatAssetStore(
            betterTTV: StubBetterTTVLoader(global: [global], channel: [channel])
        )

        await store.loadBetterTTV(twitchUserID: "123")

        #expect(store.thirdPartyEmoteCatalog.count == 1)
        #expect(store.thirdPartyEmoteCatalog.emote(for: "SameCode") == channel)
        #expect(!store.isLoadingThirdPartyEmotes)
    }

    @Test
    func failedBetterTTVChannelStillKeepsGlobalCatalog() async {
        let global = ThirdPartyEmoteDefinition(
            code: "OMEGALUL",
            emoteID: "global",
            provider: "bttv",
            animated: false,
            imageURL: nil
        )
        let store = ChatAssetStore(
            betterTTV: StubBetterTTVLoader(
                global: [global],
                channel: [],
                failChannel: true
            )
        )

        await store.loadBetterTTV(twitchUserID: "123")

        #expect(store.thirdPartyEmoteCatalog.emote(for: "OMEGALUL") == global)
    }

    @Test
    func resetClearsBadgeAndThirdPartyCatalogs() async {
        let badge = ChatBadgeAsset(setID: "moderator", versionID: "1")
        let emote = ThirdPartyEmoteDefinition(
            code: "OMEGALUL",
            emoteID: "1",
            provider: "bttv",
            animated: false,
            imageURL: nil
        )
        let store = ChatAssetStore(
            badges: StubBadgeLoader(global: [badge], channel: []),
            betterTTV: StubBetterTTVLoader(global: [emote], channel: [])
        )

        await store.loadBadges(clientID: "client", accessToken: "access", broadcasterID: "channel")
        await store.loadBetterTTV(twitchUserID: "123")
        store.reset()

        #expect(store.badgeAssets.isEmpty)
        #expect(store.thirdPartyEmoteCatalog.isEmpty)
        #expect(!store.isLoadingBadges)
        #expect(!store.isLoadingThirdPartyEmotes)
    }
}

private struct StubBadgeLoader: ChatBadgeLoading, Sendable {
    enum Failure: Swift.Error {
        case failed
    }

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
        if failGlobal {
            throw Failure.failed
        }
        return global
    }

    func getChannelBadges(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) async throws -> [ChatBadgeAsset] {
        if failChannel {
            throw Failure.failed
        }
        return channel
    }
}

private struct StubBetterTTVLoader: BetterTTVEmoteLoading, Sendable {
    enum Failure: Swift.Error {
        case failed
    }

    let global: [ThirdPartyEmoteDefinition]
    let channel: [ThirdPartyEmoteDefinition]
    let failGlobal: Bool
    let failChannel: Bool

    init(
        global: [ThirdPartyEmoteDefinition],
        channel: [ThirdPartyEmoteDefinition],
        failGlobal: Bool = false,
        failChannel: Bool = false
    ) {
        self.global = global
        self.channel = channel
        self.failGlobal = failGlobal
        self.failChannel = failChannel
    }

    func getGlobalEmotes() async throws -> [ThirdPartyEmoteDefinition] {
        if failGlobal {
            throw Failure.failed
        }
        return global
    }

    func getChannelEmotes(twitchUserID: String) async throws -> [ThirdPartyEmoteDefinition] {
        if failChannel {
            throw Failure.failed
        }
        return channel
    }
}
