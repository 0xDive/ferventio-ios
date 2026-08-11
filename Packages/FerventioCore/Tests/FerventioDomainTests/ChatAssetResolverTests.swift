import Testing
@testable import FerventioDomain

struct ChatAssetResolverTests {
    @Test
    func buildsStaticTwitchEmoteURLByDefault() {
        let url = ChatAssetResolver.twitchEmoteURL(
            emoteID: "25",
            formats: ["static", "animated"],
            animate: false
        )

        #expect(url?.absoluteString == "https://static-cdn.jtvnw.net/emoticons/v2/25/static/dark/2.0")
    }

    @Test
    func selectsAnimatedTwitchFormatWhenAvailable() {
        let url = ChatAssetResolver.twitchEmoteURL(
            emoteID: "25",
            formats: ["static", "animated"],
            animate: true,
            theme: .light,
            scale: .large
        )

        #expect(url?.absoluteString == "https://static-cdn.jtvnw.net/emoticons/v2/25/animated/light/3.0")
    }

    @Test
    func fallsBackToStaticWhenAnimatedFormatIsUnavailable() {
        let url = ChatAssetResolver.twitchEmoteURL(
            emoteID: "25",
            formats: ["static"],
            animate: true
        )

        #expect(url?.absoluteString == "https://static-cdn.jtvnw.net/emoticons/v2/25/static/dark/2.0")
    }

    @Test
    func resolvesProtocolRelativeImageURL() {
        #expect(
            ChatAssetResolver.absoluteImageURL("//cdn.example.com/image.png")?.absoluteString
                == "https://cdn.example.com/image.png"
        )
    }

    @Test
    func resolvesBadgeBySetAndVersion() {
        let asset = ChatBadgeAsset(setID: "subscriber", versionID: "12", imageURL2x: "https://example.com/badge.png")
        let badge = ChatBadge(setID: "subscriber", id: "12")

        #expect(ChatAssetResolver.badgeAsset(for: badge, assets: [asset.id: asset]) == asset)
    }
}
