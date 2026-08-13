import Foundation
import Testing
@testable import FerventioNetworking

struct TwitchEventSubAPIClientTests {
    @Test
    func buildsChannelChatMessageWebSocketSubscription() throws {
        let request = try TwitchEventSubAPIClient.makeChatMessageSubscriptionRequest(
            clientID: "client-1",
            accessToken: "access-1",
            sessionID: "session-1",
            broadcasterID: "broadcaster-1",
            userID: "user-1"
        )

        #expect(request.url?.absoluteString == "https://api.twitch.tv/helix/eventsub/subscriptions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        #expect(request.value(forHTTPHeaderField: "Client-Id") == "client-1")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let data = try #require(request.httpBody)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let condition = try #require(root["condition"] as? [String: Any])
        let transport = try #require(root["transport"] as? [String: Any])

        #expect(root["type"] as? String == "channel.chat.message")
        #expect(root["version"] as? String == "1")
        #expect(condition["broadcaster_user_id"] as? String == "broadcaster-1")
        #expect(condition["user_id"] as? String == "user-1")
        #expect(transport["method"] as? String == "websocket")
        #expect(transport["session_id"] as? String == "session-1")
    }

    @Test
    func buildsBroadcasterOnlyInteractiveSubscriptions() throws {
        for type in InteractiveEventSubSubscriptionType.allCases {
            let request = try TwitchEventSubAPIClient.makeInteractiveSubscriptionRequest(
                clientID: "client-1",
                accessToken: "access-1",
                sessionID: "session-1",
                broadcasterID: "broadcaster-1",
                type: type
            )
            let data = try #require(request.httpBody)
            let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let condition = try #require(root["condition"] as? [String: Any])

            #expect(root["type"] as? String == type.rawValue)
            #expect(root["version"] as? String == "1")
            #expect(condition["broadcaster_user_id"] as? String == "broadcaster-1")
            #expect(condition["user_id"] == nil)
        }
    }

    @Test
    func interactiveTypeGroupingDistinguishesPollsAndPredictions() {
        #expect(InteractiveEventSubSubscriptionType.pollBegin.isPoll)
        #expect(InteractiveEventSubSubscriptionType.pollProgress.isPoll)
        #expect(InteractiveEventSubSubscriptionType.pollEnd.isPoll)
        #expect(!InteractiveEventSubSubscriptionType.predictionBegin.isPoll)
        #expect(!InteractiveEventSubSubscriptionType.predictionProgress.isPoll)
        #expect(!InteractiveEventSubSubscriptionType.predictionLock.isPoll)
        #expect(!InteractiveEventSubSubscriptionType.predictionEnd.isPoll)
    }

    @Test
    func rejectsMissingWebSocketSessionID() {
        #expect(throws: TwitchEventSubAPIClient.Error.invalidArgument("sessionID")) {
            try TwitchEventSubAPIClient.makeChatMessageSubscriptionRequest(
                clientID: "client-1",
                accessToken: "access-1",
                sessionID: "  ",
                broadcasterID: "broadcaster-1",
                userID: "user-1"
            )
        }
    }
}
