import Foundation
import Testing
@testable import FerventioNetworking

struct TwitchInteractiveAPIClientTests {
    @Test
    func buildsBroadcasterPollRequest() throws {
        let request = try TwitchInteractiveAPIClient.makePollRequest(
            clientID: "client-1",
            accessToken: "access-1",
            broadcasterID: "broadcaster-1"
        )

        #expect(request.httpMethod == "GET")
        #expect(request.url?.host == "api.twitch.tv")
        #expect(request.url?.path == "/helix/polls")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        #expect(request.value(forHTTPHeaderField: "Client-Id") == "client-1")

        let components = try #require(
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        )
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        #expect(query["broadcaster_id"] == "broadcaster-1")
        #expect(query["first"] == "20")
    }

    @Test
    func buildsBroadcasterPredictionRequest() throws {
        let request = try TwitchInteractiveAPIClient.makePredictionRequest(
            clientID: "client-1",
            accessToken: "access-1",
            broadcasterID: "broadcaster-1"
        )

        #expect(request.httpMethod == "GET")
        #expect(request.url?.host == "api.twitch.tv")
        #expect(request.url?.path == "/helix/predictions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        #expect(request.value(forHTTPHeaderField: "Client-Id") == "client-1")
    }

    @Test
    func rejectsBlankBroadcasterID() {
        #expect(throws: TwitchInteractiveAPIClient.Error.invalidArgument("broadcasterID")) {
            try TwitchInteractiveAPIClient.makePollRequest(
                clientID: "client",
                accessToken: "token",
                broadcasterID: "  "
            )
        }
    }

    @Test
    func rejectsBlankCredentials() {
        #expect(throws: TwitchInteractiveAPIClient.Error.invalidArgument("clientID")) {
            try TwitchInteractiveAPIClient.makePredictionRequest(
                clientID: " ",
                accessToken: "token",
                broadcasterID: "broadcaster"
            )
        }
        #expect(throws: TwitchInteractiveAPIClient.Error.invalidArgument("accessToken")) {
            try TwitchInteractiveAPIClient.makePollRequest(
                clientID: "client",
                accessToken: " ",
                broadcasterID: "broadcaster"
            )
        }
    }
}
