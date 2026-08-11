import Foundation
import Testing
@testable import FerventioNetworking

struct SevenTVAPIClientTests {
    @Test
    func buildsCurrentV3Requests() throws {
        #expect(
            SevenTVAPIClient.makeGlobalRequest().url?.absoluteString
                == "https://7tv.io/v3/emote-sets/global"
        )
        #expect(
            try SevenTVAPIClient.makeChannelRequest(twitchUserID: "123").url?.absoluteString
                == "https://7tv.io/v3/users/twitch/123"
        )
    }

    @Test
    func rejectsEmptyChannelID() {
        #expect(throws: SevenTVAPIClient.Error.invalidArgument("twitchUserID")) {
            try SevenTVAPIClient.makeChannelRequest(twitchUserID: "  ")
        }
    }

    @Test
    func parsesGlobalEmoteAndZeroWidthFlag() throws {
        let json = """
        {
          "emotes": [
            {
              "id": "emote-1",
              "name": "Overlay",
              "flags": 1,
              "data": {
                "animated": true,
                "host": {
                  "url": "//cdn.7tv.app/emote/emote-1",
                  "files": [
                    {"name": "1x.webp", "width": 32, "height": 32, "frame_count": 4},
                    {"name": "2x.webp", "width": 64, "height": 64, "frame_count": 4}
                  ]
                }
              }
            }
          ]
        }
        """

        let emotes = try SevenTVAPIClient.parseGlobalResponse(Data(json.utf8))

        #expect(emotes.count == 1)
        #expect(emotes[0].provider == "7tv")
        #expect(emotes[0].zeroWidth)
        #expect(emotes[0].animated)
        #expect(emotes[0].imageURL == "https://cdn.7tv.app/emote/emote-1/2x.webp")
    }

    @Test
    func channelParserUsesMatchingTwitchConnection() throws {
        let json = """
        {
          "connections": [
            {
              "id": "other",
              "platform": "TWITCH",
              "emote_set": {"emotes": []}
            },
            {
              "id": "123",
              "platform": "TWITCH",
              "emote_set": {
                "emotes": [
                  {
                    "id": "channel-1",
                    "name": "SevenTV",
                    "flags": 0,
                    "data": {
                      "animated": false,
                      "host": {
                        "url": "https://cdn.7tv.app/emote/channel-1/",
                        "files": [
                          {"name": "2x.webp", "width": 64, "height": 32, "frame_count": 1}
                        ]
                      }
                    }
                  }
                ]
              }
            }
          ]
        }
        """

        let emotes = try SevenTVAPIClient.parseChannelResponse(
            Data(json.utf8),
            twitchUserID: "123"
        )

        #expect(emotes.count == 1)
        #expect(emotes[0].code == "SevenTV")
        #expect(!emotes[0].zeroWidth)
        #expect(emotes[0].imageURL == "https://cdn.7tv.app/emote/channel-1/2x.webp")
    }
}
