import Testing
@testable import FerventioNetworking

struct BetterTTVAPIClientTests {
    @Test
    func buildsCanonicalTwoXImageURL() {
        #expect(
            BetterTTVAPIClient.imageURL(emoteID: "abc123")
                == "https://cdn.betterttv.net/emote/abc123/2x"
        )
    }

    @Test
    func supportsAvailableBttvScales() {
        #expect(
            BetterTTVAPIClient.imageURL(emoteID: "abc123", scale: 1)
                == "https://cdn.betterttv.net/emote/abc123/1x"
        )
        #expect(
            BetterTTVAPIClient.imageURL(emoteID: "abc123", scale: 3)
                == "https://cdn.betterttv.net/emote/abc123/3x"
        )
    }

    @Test
    func rejectsInvalidImageURLInputs() {
        #expect(BetterTTVAPIClient.imageURL(emoteID: "   ") == nil)
        #expect(BetterTTVAPIClient.imageURL(emoteID: "abc123", scale: 4) == nil)
    }
}
