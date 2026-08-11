import Foundation
import Testing
@testable import FerventioNetworking

struct FrankerFaceZAPIClientTests {
    @Test
    func buildsGlobalAndChannelRequests() throws {
        #expect(
            FrankerFaceZAPIClient.makeGlobalRequest().url?.absoluteString
                == "https://api.frankerfacez.com/v1/set/global"
        )
        #expect(
            try FrankerFaceZAPIClient.makeChannelRequest(twitchUserID: "123").url?.absoluteString
                == "https://api.frankerfacez.com/v1/room/id/123"
        )
    }

    @Test
    func rejectsEmptyChannelID() {
        #expect(throws: FrankerFaceZAPIClient.Error.invalidArgument("twitchUserID")) {
            try FrankerFaceZAPIClient.makeChannelRequest(twitchUserID: "  ")
        }
    }

    @Test
    func globalParserUsesOnlyDefaultSetsAndSkipsModifiers() throws {
        let json = """
        {
          "default_sets": [3],
          "sets": {
            "3": {"emoticons": [
              {"id": 1, "name": "Global", "urls": {"1": "//cdn.frankerfacez.com/1/1", "2": "https://cdn.frankerfacez.com/1/2"}, "animated": null, "modifier": false, "modifier_flags": 0},
              {"id": 2, "name": "ffzX", "urls": {"1": "https://cdn.frankerfacez.com/2/1"}, "animated": null, "modifier": true, "modifier_flags": 3}
            ]},
            "99": {"emoticons": [
              {"id": 99, "name": "UserSpecific", "urls": {"1": "https://cdn.frankerfacez.com/99/1"}, "animated": null, "modifier": false, "modifier_flags": 0}
            ]}
          }
        }
        """
        let data = Data(json.utf8)

        let emotes = try FrankerFaceZAPIClient.parseGlobalResponse(data)

        #expect(emotes.count == 1)
        #expect(emotes[0].code == "Global")
        #expect(emotes[0].provider == "ffz")
        #expect(emotes[0].imageURL == "https://cdn.frankerfacez.com/1/2")
    }

    @Test
    func channelParserUsesPrimaryRoomSetAndPrefersAnimatedAsset() throws {
        let json = """
        {
          "room": {"set": 42},
          "sets": {
            "42": {"emoticons": [
              {"id": 7, "name": "Dance", "urls": {"2": "https://cdn.frankerfacez.com/7/2"}, "animated": {"2": "https://cdn.frankerfacez.com/7/2.webp"}, "modifier": false, "modifier_flags": 0}
            ]},
            "43": {"emoticons": [
              {"id": 8, "name": "WrongSet", "urls": {"2": "https://cdn.frankerfacez.com/8/2"}, "animated": null, "modifier": false, "modifier_flags": 0}
            ]}
          }
        }
        """
        let data = Data(json.utf8)

        let emotes = try FrankerFaceZAPIClient.parseChannelResponse(data)

        #expect(emotes.count == 1)
        #expect(emotes[0].code == "Dance")
        #expect(emotes[0].animated)
        #expect(emotes[0].imageURL == "https://cdn.frankerfacez.com/7/2.webp")
    }
}
