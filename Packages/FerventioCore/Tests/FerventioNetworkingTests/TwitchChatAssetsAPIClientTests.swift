import Foundation
import Testing
@testable import FerventioNetworking

struct TwitchChatAssetsAPIClientTests {
    @Test
    func buildsGlobalBadgesRequest() throws {
        let request = try TwitchChatAssetsAPIClient.makeBadgesRequest(
            clientID: "client-1",
            accessToken: "access-1",
            broadcasterID: nil
        )

        #expect(request.url?.absoluteString == "https://api.twitch.tv/helix/chat/badges/global")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        #expect(request.value(forHTTPHeaderField: "Client-Id") == "client-1")
    }

    @Test
    func buildsChannelBadgesRequest() throws {
        let request = try TwitchChatAssetsAPIClient.makeBadgesRequest(
            clientID: "client-1",
            accessToken: "access-1",
            broadcasterID: "broadcaster-1"
        )

        #expect(
            request.url?.absoluteString
                == "https://api.twitch.tv/helix/chat/badges?broadcaster_id=broadcaster-1"
        )
    }

    @Test
    func rejectsEmptyBroadcasterID() {
        #expect(throws: TwitchChatAssetsAPIClient.Error.invalidArgument("broadcasterID")) {
            try TwitchChatAssetsAPIClient.makeBadgesRequest(
                clientID: "client-1",
                accessToken: "access-1",
                broadcasterID: "   "
            )
        }
    }
}
