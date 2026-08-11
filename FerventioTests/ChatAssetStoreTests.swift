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
    func oneFailedCatalogStillKeepsSuccessfulCatalog() async {
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
