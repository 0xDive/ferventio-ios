import Testing
@testable import FerventioDomain

struct ThirdPartyEmoteParserTests {
    @Test
    func replacesExactTextTokensAndPreservesWhitespace() {
        let catalog = ThirdPartyEmoteCatalog(
            emotes: [
                ThirdPartyEmoteDefinition(
                    code: "OMEGALUL",
                    emoteID: "1",
                    provider: "bttv",
                    animated: false,
                    imageURL: "https://example.com/omegalul.png"
                )
            ]
        )

        let parsed = ThirdPartyEmoteParser.apply(
            to: [.text("hello  OMEGALUL world")],
            catalog: catalog
        )

        #expect(parsed == [
            .text("hello"),
            .text("  "),
            .thirdPartyEmote(
                text: "OMEGALUL",
                emoteID: "1",
                provider: "bttv",
                animated: false,
                imageURL: "https://example.com/omegalul.png",
                zeroWidth: false
            ),
            .text(" "),
            .text("world"),
        ])
    }

    @Test
    func doesNotRewriteTwitchEmoteFragments() {
        let twitch: ChatFragment = .twitchEmote(
            text: "Kappa",
            emoteID: "25",
            emoteSetID: "0",
            ownerID: "0",
            formats: ["static"]
        )
        let catalog = ThirdPartyEmoteCatalog(
            emotes: [
                ThirdPartyEmoteDefinition(
                    code: "Kappa",
                    emoteID: "third-party",
                    provider: "bttv",
                    animated: false,
                    imageURL: nil
                )
            ]
        )

        #expect(ThirdPartyEmoteParser.apply(to: [twitch], catalog: catalog) == [twitch])
    }

    @Test
    func channelCatalogOverridesGlobalCode() {
        let global = ThirdPartyEmoteDefinition(
            code: "SameCode",
            emoteID: "global",
            provider: "bttv",
            animated: false,
            imageURL: nil
        )
        let channel = ThirdPartyEmoteDefinition(
            code: "SameCode",
            emoteID: "channel",
            provider: "7tv",
            animated: true,
            imageURL: nil,
            zeroWidth: true
        )
        let catalog = ThirdPartyEmoteCatalog.merging(global: [global], channel: [channel])

        #expect(catalog.emote(for: "SameCode") == channel)
    }

    @Test
    func preservesZeroWidthMetadata() {
        let overlay = ThirdPartyEmoteDefinition(
            code: "RainTime",
            emoteID: "overlay",
            provider: "bttv",
            animated: true,
            imageURL: "https://example.com/overlay.gif",
            zeroWidth: true
        )
        let catalog = ThirdPartyEmoteCatalog(emotes: [overlay])

        let parsed = ThirdPartyEmoteParser.apply(to: [.text("RainTime")], catalog: catalog)

        #expect(parsed == [
            .thirdPartyEmote(
                text: "RainTime",
                emoteID: "overlay",
                provider: "bttv",
                animated: true,
                imageURL: "https://example.com/overlay.gif",
                zeroWidth: true
            )
        ])
    }
}
